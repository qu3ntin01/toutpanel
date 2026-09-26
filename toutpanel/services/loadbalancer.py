"""Répartition de charge d'un site reverse proxy : plusieurs serveurs en amont (poids, secours, seuils de panne),
méthode (tour de rôle, moins de connexions, IP hash = sessions collantes), keepalive, et vérification de l'état des serveurs."""
from __future__ import annotations

import re
import socket
import ssl
import time
import urllib.request
from typing import Optional
from urllib.parse import urlparse

METHODS = ("round_robin", "least_conn", "ip_hash")
METHOD_LABELS = {"round_robin": "Tour de rôle (round-robin)", "least_conn": "Moins de connexions actives", "ip_hash": "IP hash (sessions collantes)"}
MAX_UPSTREAMS = 32


class LbError(ValueError):
    pass


def validate_upstreams(items: list, method: str = "round_robin", keepalive: int = 32) -> tuple[list[dict], str, int]:
    """Normalise la liste des serveurs. Chaque élément : {url, weight, backup, max_fails, fail_timeout}."""
    from toutpanel.services.sites import validate_proxy_target

    if method not in METHODS:
        raise LbError("Méthode de répartition invalide")
    try:
        keepalive = int(keepalive)
    except (TypeError, ValueError):
        raise LbError("Keepalive invalide")
    if not (0 <= keepalive <= 1024):
        raise LbError("Keepalive invalide (0 à 1024 connexions)")
    out: list[dict] = []
    schemes: set[str] = set()
    for raw in items or []:
        if isinstance(raw, str):
            raw = {"url": raw}
        if not isinstance(raw, dict):
            raise LbError("Serveur invalide")
        url = validate_proxy_target(str(raw.get("url", "")))
        u = urlparse(url)
        if u.path not in ("", "/"):
            raise LbError(f"{url} : un serveur d'un groupe ne doit pas avoir de chemin")
        schemes.add(u.scheme)
        try:
            weight = int(raw.get("weight", 1) or 1)
            max_fails = int(raw.get("max_fails", 3) if raw.get("max_fails") is not None else 3)
            fail_timeout = int(raw.get("fail_timeout", 10) if raw.get("fail_timeout") is not None else 10)
        except (TypeError, ValueError):
            raise LbError(f"{url} : poids ou seuils invalides")
        if not (1 <= weight <= 100) or not (0 <= max_fails <= 100) or not (1 <= fail_timeout <= 3600):
            raise LbError(f"{url} : poids 1-100, échecs 0-100, délai 1-3600 s")
        out.append({"url": url.rstrip("/"), "host": u.hostname, "port": u.port or (443 if u.scheme == "https" else 80), "scheme": u.scheme,
                    "weight": weight, "backup": bool(raw.get("backup")), "max_fails": max_fails, "fail_timeout": fail_timeout})
    if len(out) > MAX_UPSTREAMS:
        raise LbError(f"{MAX_UPSTREAMS} serveurs maximum")
    if len(schemes) > 1:
        raise LbError("Tous les serveurs d'un groupe doivent utiliser le même protocole (http ou https)")
    if out and all(x["backup"] for x in out):
        raise LbError("Au moins un serveur ne doit pas être de secours")
    seen = set()
    for x in out:
        key = (x["host"], x["port"])
        if key in seen:
            raise LbError(f"{x['url']} : serveur en double")
        seen.add(key)
    return out, method, keepalive


def upstream_name(site_name: str) -> str:
    return "tp_" + re.sub(r"[^a-z0-9_]", "_", site_name.lower())[:48]


def nginx_upstream(site: dict) -> str:
    """Bloc `upstream` nginx pour le site (vide si pas de répartition)."""
    ups = site.get("upstreams") or []
    if not ups:
        return ""
    lines = [f"upstream {upstream_name(site['name'])} {{"]
    method = site.get("lb_method") or "round_robin"
    if method == "least_conn":
        lines.append("    least_conn;")
    elif method == "ip_hash":
        lines.append("    ip_hash;")
    for u in ups:
        opts = []
        if u.get("weight", 1) != 1:
            opts.append(f"weight={int(u['weight'])}")
        opts.append(f"max_fails={int(u.get('max_fails', 3))}")
        opts.append(f"fail_timeout={int(u.get('fail_timeout', 10))}s")
        if u.get("backup"):
            opts.append("backup")
        host = u["host"] if ":" not in u["host"] else f"[{u['host']}]"
        lines.append(f"    server {host}:{u['port']} {' '.join(opts)};")
    ka = int(site.get("lb_keepalive", 32) or 0)
    if ka:
        lines.append(f"    keepalive {ka};")
    lines.append("}")
    return "\n".join(lines)


def nginx_pass(site: dict) -> str:
    ups = site.get("upstreams") or []
    if ups:
        return f"{ups[0]['scheme']}://{upstream_name(site['name'])}"
    return site.get("proxy_target", "")


def apache_balancer(site: dict) -> str:
    ups = site.get("upstreams") or []
    if not ups:
        return ""
    name = upstream_name(site["name"])
    lines = [f'    <Proxy "balancer://{name}">']
    for u in ups:
        opts = [f"loadfactor={int(u.get('weight', 1))}", f"retry={int(u.get('fail_timeout', 10))}"]
        if u.get("backup"):
            opts.append("status=+H")
        lines.append(f"        BalancerMember {u['url']} {' '.join(opts)}")
    method = {"round_robin": "byrequests", "least_conn": "bybusyness", "ip_hash": "byrequests"}[site.get("lb_method") or "round_robin"]
    extra = " stickysession=ROUTEID" if (site.get("lb_method") == "ip_hash") else ""
    lines.append(f"        ProxySet lbmethod={method}{extra}")
    lines.append("    </Proxy>")
    return "\n".join(lines)


def apache_pass(site: dict) -> str:
    ups = site.get("upstreams") or []
    if ups:
        return f"balancer://{upstream_name(site['name'])}"
    return (site.get("proxy_target") or "").rstrip("/")


# --------------------------------------------------------------------------- état des serveurs

def probe(url: str, host_header: Optional[str] = None, timeout: float = 4.0) -> dict:
    """Une requête HEAD (puis GET si HEAD refusé) : code HTTP et latence en ms. Aucun certificat n'est vérifié (serveurs internes)."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    started = time.perf_counter()
    for method in ("HEAD", "GET"):
        try:
            req = urllib.request.Request(url.rstrip("/") + "/", method=method, headers={"User-Agent": "ToutPanel-LB-check", **({"Host": host_header} if host_header else {})})
            with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
                return {"ok": resp.status < 500, "status": resp.status, "ms": round((time.perf_counter() - started) * 1000)}
        except urllib.error.HTTPError as e:
            if e.code in (405, 501) and method == "HEAD":
                continue
            return {"ok": e.code < 500, "status": e.code, "ms": round((time.perf_counter() - started) * 1000)}
        except (urllib.error.URLError, socket.timeout, OSError, ValueError) as e:
            return {"ok": False, "status": 0, "ms": round((time.perf_counter() - started) * 1000), "error": str(getattr(e, "reason", e))[:120]}
    return {"ok": False, "status": 0, "ms": 0, "error": "inconnu"}


def check_site(site: dict) -> list[dict]:
    host = (site.get("domains") or [None])[0]
    out = []
    for u in site.get("upstreams") or []:
        r = probe(u["url"], host)
        r.update({"url": u["url"], "backup": bool(u.get("backup")), "weight": u.get("weight", 1)})
        out.append(r)
    return out
