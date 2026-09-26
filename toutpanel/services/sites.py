"""Gestion des sites web."""
from __future__ import annotations

import re
import shutil
from pathlib import Path

from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.models import Site
from toutpanel.platform import get_platform
from toutpanel.services import webserver

DOMAIN_RE = re.compile(r"^(\*\.)?([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$|^localhost$|^\d{1,3}(\.\d{1,3}){3}$")
NAME_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$")

DEFAULT_INDEX = """<!DOCTYPE html>
<html lang="fr">
<head><meta charset="utf-8"><title>{name}</title>
<style>body{{font-family:system-ui,sans-serif;background:#f4f6fb;color:#222;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}}
.card{{background:#fff;padding:2rem 3rem;border-radius:12px;box-shadow:0 8px 30px rgba(0,0,0,.08);text-align:center}}h1{{margin:0 0 .5rem}}</style></head>
<body><div class="card"><h1>{name}</h1><p>Site créé avec ToutPanel. Déposez vos fichiers dans <code>{root}</code>.</p></div></body></html>
"""


class SiteError(ValueError):
    pass


def validate_domains(domains: list[str]) -> list[str]:
    cleaned = []
    for d in domains:
        d = d.strip().lower().rstrip(".")
        if not d:
            continue
        if not DOMAIN_RE.match(d):
            raise SiteError(f"Nom de domaine invalide : {d}")
        if d not in cleaned:
            cleaned.append(d)
    if not cleaned:
        raise SiteError("Au moins un domaine est requis")
    return cleaned


def _apply(site: Site, reload: bool = True) -> str:
    """Écrit le vhost et recharge le serveur web. Retourne un message d'avertissement éventuel."""
    adapter = webserver.get_adapter()
    if not site.enabled:
        adapter.remove(site.name)
    else:
        adapter.apply(site.to_dict())
    if reload and webserver.is_installed(adapter.name):
        r = adapter.reload()
        if not r.ok:
            return f"Vhost écrit mais rechargement {adapter.name} échoué : {r.output[:500]}"
        return ""
    if reload:
        return f"Vhost écrit dans {getattr(adapter, 'conf_dir', lambda: '')()} ; {adapter.name} n'est pas installé (voir Logiciels)."
    return ""


ROOT_RE = re.compile(r"^[A-Za-z0-9_./ :\\-]+$")


def validate_root(root: str) -> str:
    """Racine d'un site : chemin absolu sans caractère capable de fermer une directive nginx / apache."""
    root = (root or "").strip()
    if not root:
        return ""
    if not ROOT_RE.match(root) or ".." in root.replace("\\", "/").split("/") or "\n" in root:
        raise SiteError("Répertoire racine invalide (chemin absolu, sans caractères spéciaux)")
    p = Path(root)
    if not p.is_absolute():
        raise SiteError("Répertoire racine : chemin absolu requis")
    from toutpanel.services import files

    try:
        files.safe_path(str(p))
    except files.FileError as e:
        raise SiteError(f"Répertoire racine refusé : {e}")
    return str(p)


def validate_proxy_target(target: str) -> str:
    """Cible de reverse proxy : http(s)://hôte[:port][/chemin] sans espace, guillemet, point-virgule ni retour à la ligne."""
    from urllib.parse import urlparse

    target = (target or "").strip()
    if not re.fullmatch(r"https?://[A-Za-z0-9.\-_\[\]:]+(/[A-Za-z0-9._~%/\-]*)?", target):
        raise SiteError("Cible du proxy invalide (http://host:port)")
    u = urlparse(target)
    if not u.hostname or (u.port is not None and not (1 <= u.port <= 65535)):
        raise SiteError("Cible du proxy invalide (http://host:port)")
    return target


def validate_remark(remark: str) -> str:
    remark = (remark or "").strip()
    if any(c in remark for c in "\r\n\x00"):
        raise SiteError("Remarque invalide")
    return remark[:250]


def create_site(db: Session, name: str, domains: list[str], root: str = "", php_version: str = "",
                site_type: str = "php", proxy_target: str = "", remark: str = "", create_index: bool = True, php_isolation: bool = True) -> tuple[Site, str]:
    name = name.strip()
    if not NAME_RE.match(name):
        raise SiteError("Nom de site invalide (lettres, chiffres, . _ -)")
    if db.query(Site).filter(Site.name == name).first():
        raise SiteError("Un site portant ce nom existe déjà")
    domains = validate_domains(domains)
    for s in db.query(Site).all():
        clash = set(s.domains or []) & set(domains)
        if clash:
            raise SiteError(f"Domaine déjà utilisé par le site {s.name} : {', '.join(clash)}")
    if site_type not in ("php", "static", "proxy"):
        raise SiteError("Type de site invalide")
    if site_type == "proxy":
        proxy_target = validate_proxy_target(proxy_target)
    remark = validate_remark(remark)
    if php_version and not re.fullmatch(r"\d+\.\d+", php_version):
        raise SiteError("Version PHP invalide")
    root = validate_root(root)
    root_path = Path(root) if root else config.WWW_ROOT / name
    root_path.mkdir(parents=True, exist_ok=True)
    if create_index and not any(root_path.iterdir()):
        from toutpanel.services import templates

        (root_path / "index.html").write_text(templates.render("site_index.html.j2", name=name, root=str(root_path)), encoding="utf-8")
    get_platform().chown_web(str(root_path))
    site = Site(name=name, domains=domains, root=str(root_path), php_version=php_version or "", site_type=site_type,
                proxy_target=proxy_target or "", remark=remark or "", php_isolation=bool(php_isolation))
    db.add(site)
    db.flush()
    return site, _apply(site)


def update_site(db: Session, site: Site, data: dict) -> str:
    if "domains" in data:
        domains = validate_domains(list(data["domains"]))
        for s in db.query(Site).filter(Site.id != site.id).all():
            clash = set(s.domains or []) & set(domains)
            if clash:
                raise SiteError(f"Domaine déjà utilisé par le site {s.name} : {', '.join(clash)}")
        site.domains = domains
    if data.get("root"):
        data["root"] = validate_root(str(data["root"]))
    if "remark" in data and data["remark"] is not None:
        data["remark"] = validate_remark(str(data["remark"]))
    if data.get("php_version") and not re.fullmatch(r"\d+\.\d+", str(data["php_version"])):
        raise SiteError("Version PHP invalide")
    if data.get("site_type") and data["site_type"] not in ("php", "static", "proxy"):
        raise SiteError("Type de site invalide")
    if "upstreams" in data and data["upstreams"] is not None or "lb_method" in data or "lb_keepalive" in data:
        from toutpanel.services import loadbalancer

        try:
            ups, method, ka = loadbalancer.validate_upstreams(data.get("upstreams", site.upstreams or []) if data.get("upstreams") is not None else (site.upstreams or []),
                                                               data.get("lb_method") or site.lb_method or "round_robin", data.get("lb_keepalive", site.lb_keepalive if site.lb_keepalive is not None else 32))
        except loadbalancer.LbError as e:
            raise SiteError(str(e))
        site.upstreams, site.lb_method, site.lb_keepalive = ups, method, ka
        if ups and not data.get("proxy_target") and not site.proxy_target:
            site.proxy_target = ups[0]["url"]  # cible de repli affichée ; le vhost utilise le groupe
    for key in ("ssl_cert", "ssl_key"):
        if data.get(key) and (any(c in str(data[key]) for c in "\r\n;{}\"") or not Path(str(data[key])).is_absolute()):
            raise SiteError("Chemin de certificat invalide")
    for key in ("php_version", "site_type", "proxy_target", "remark", "force_https", "enabled", "root",
                "ssl_enabled", "ssl_cert", "ssl_key", "waf_enabled", "php_isolation"):
        if key in data and data[key] is not None:
            setattr(site, key, data[key])
    if site.site_type == "proxy" and not (site.upstreams and not data.get("proxy_target")):
        site.proxy_target = validate_proxy_target(site.proxy_target)
    if site.ssl_enabled and not (site.ssl_cert and site.ssl_key):
        raise SiteError("Certificat et clé requis pour activer le SSL")
    Path(site.root).mkdir(parents=True, exist_ok=True)
    db.flush()
    return _apply(site)


def delete_site(db: Session, site: Site, delete_files: bool = False) -> str:
    from toutpanel.services import gitdeploy

    gitdeploy.remove(db, site.id)
    adapter = webserver.get_adapter()
    adapter.remove(site.name)
    custom = config.VHOST_DIR / "custom"
    for p in custom.glob(f"{site.name}.*"):
        p.unlink(missing_ok=True)
    if delete_files and site.root and Path(site.root).exists():
        root = Path(site.root).resolve()
        if root not in (Path("/"), Path("C:\\")) and len(root.parts) > 1:
            shutil.rmtree(root, ignore_errors=True)
    db.delete(site)
    db.flush()
    if webserver.is_installed(adapter.name):
        r = adapter.reload()
        return "" if r.ok else r.output[:500]
    return ""


def custom_config_path(site: Site) -> Path:
    ws = webserver.detect()
    suffix = ".apache.conf" if ws == "apache" else ".conf"
    (config.VHOST_DIR / "custom").mkdir(parents=True, exist_ok=True)
    return config.VHOST_DIR / "custom" / f"{site.name}{suffix}"


def get_rendered_config(site: Site) -> str:
    return webserver.get_adapter().render(site.to_dict())
