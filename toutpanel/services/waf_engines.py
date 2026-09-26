"""Moteurs WAF externes déployés par Docker : BunkerWeb et SafeLine (Chaitin).

Principe : le moteur écoute sur 80/443 et fait du reverse proxy vers le serveur web du panel,
déplacé sur des ports de repli (8080/8443 par défaut). Les sites du panel sont configurés
automatiquement dans le moteur (fichier d'environnement BunkerWeb, API ouverte SafeLine).
"""
from __future__ import annotations

import json
import logging
import re
import secrets
import time
import ssl
import urllib.request
from pathlib import Path
from typing import Callable, Optional

from toutpanel import config
from toutpanel.platform import get_platform
from toutpanel.services import docker, tasks

log = logging.getLogger("toutpanel.waf_engines")

BUNKERWEB_IMAGE = "bunkerity/bunkerweb-all-in-one:1.6.5"
BUNKERWEB_CONTAINER = "toutpanel-bunkerweb"
SAFELINE_RELEASE = "https://waf.chaitin.com/release/latest"
SAFELINE_CONTAINERS = ("safeline-mgt", "safeline-tengine", "safeline-detector", "safeline-pg")

ENGINES = {
    "builtin": {"name": "WAF intégré ToutPanel", "desc": "Règles Nginx / Apache générées par le panel : SQLi, XSS, RCE, traversée, scanners, robots, "
                                                          "anti-CC, bannissement automatique. Aucune dépendance, actif immédiatement.", "docker": False},
    "bunkerweb": {"name": "BunkerWeb", "desc": "WAF open source (Nginx + ModSecurity + OWASP CRS) : anti-bots, listes noires, limitation, "
                                             "Let's Encrypt automatique, interface web. Déployé en conteneur devant vos sites.", "docker": True,
                  "url": "https://docs.bunkerweb.io", "ui_port_key": "bunkerweb_ui_port"},
    "safeline": {"name": "SafeLine (Chaitin)", "desc": "WAF open source à analyse sémantique : détection sans signatures, anti-bots, "
                                                     "limitation, auth, console web. Déployé par Docker Compose devant vos sites.", "docker": True,
                 "url": "https://docs.waf.chaitin.com", "ui_port_key": "safeline_mgt_port"},
}
DEFAULT_FALLBACK_PORTS = (8080, 8443)


# --------------------------------------------------------------------------- état

def engine_dir(engine: str) -> Path:
    d = config.HOME / "waf" / engine
    d.mkdir(parents=True, exist_ok=True)
    return d


def _container_state(name: str) -> str:
    """running | exited | missing"""
    r = get_platform().run(["docker", "inspect", "-f", "{{.State.Status}}", name], timeout=20)
    if not r.ok:
        return "missing"
    return "running" if r.stdout.strip() == "running" else "exited"


def is_installed(engine: str) -> bool:
    if engine == "builtin":
        return True
    if not docker.available():
        return False
    if engine == "bunkerweb":
        return _container_state(BUNKERWEB_CONTAINER) != "missing"
    return _container_state("safeline-mgt") != "missing"


def status() -> dict:
    from toutpanel.services.system_info import _local_ip
    from toutpanel.services.webserver import web_ports

    s = config.get_settings()
    ip = _local_ip()
    dock = docker.available()
    out = {"engine": s.get("waf_engine", "builtin"), "docker": dock, "web_ports": list(web_ports()), "engines": {}}
    for key, info in ENGINES.items():
        e = {"name": info["name"], "desc": info["desc"], "docker": info["docker"], "url": info.get("url", ""), "installed": False, "state": "", "ui_url": ""}
        if key == "builtin":
            e["installed"] = True
            e["state"] = "running" if s.get("waf_enabled", True) else "exited"
        elif dock:
            if key == "bunkerweb":
                e["state"] = _container_state(BUNKERWEB_CONTAINER)
                e["ui_url"] = f"http://{ip}:{s.get('bunkerweb_ui_port', 7000)}"
            else:
                e["state"] = _container_state("safeline-mgt")
                e["ui_url"] = f"https://{ip}:{s.get('safeline_mgt_port', 9443)}"
            e["installed"] = e["state"] != "missing"
        out["engines"][key] = e
    out["safeline_token_set"] = bool(s.get("safeline_api_token"))
    return out


# --------------------------------------------------------------------------- sites -> configuration des moteurs

def _sites(db) -> list[dict]:
    from toutpanel.models import Site

    return [x.to_dict() for x in db.query(Site).filter(Site.enabled.is_(True)).order_by(Site.name).all()]


def _cert_in_container(path: str) -> str:
    """Chemin d'un certificat vu depuis le conteneur BunkerWeb (volumes montés), ou '' si non exposé."""
    if not path:
        return ""
    p = Path(path)
    try:
        rel = p.resolve().relative_to(config.SSL_DIR.resolve())
        return "/tp-ssl/" + str(rel).replace("\\", "/")
    except (ValueError, OSError):
        pass
    if str(p).startswith("/etc/letsencrypt/"):
        return str(p)
    return ""


def docker_host_ip() -> str:
    """IP de l'hôte vue depuis le réseau bridge de Docker (BunkerWeb résout les cibles par DNS, pas via /etc/hosts)."""
    r = get_platform().run(["docker", "network", "inspect", "bridge", "-f", "{{(index .IPAM.Config 0).Gateway}}"], timeout=20)
    ip = r.stdout.strip() if r.ok else ""
    return ip if re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}", ip) else "172.17.0.1"


def bunkerweb_env(db, opts: Optional[dict] = None) -> str:
    """Fichier d'environnement BunkerWeb (mode multisite) généré depuis les sites du panel."""
    from toutpanel.services.webserver import web_ports

    opts = opts or {}
    s = config.get_settings()
    http_port, _ = web_ports()
    # le conteneur tourne en réseau bridge (ports publiés) : l'hôte est joignable par l'IP de la passerelle
    backend = f"http://{docker_host_ip()}:{http_port}"
    sites = _sites(db)
    servers = []
    lines = ["# Généré par ToutPanel - ne pas modifier à la main (WAF -> Moteur -> Synchroniser)",
             "MULTISITE=yes", "HTTP_PORT=8080", "HTTPS_PORT=8443", "DISABLE_DEFAULT_SERVER=yes", "USE_REAL_IP=no",
             "API_WHITELIST_IP=127.0.0.0/8 ::1 172.16.0.0/12", "SERVE_FILES=no", "USE_REVERSE_PROXY=yes",
             f"REVERSE_PROXY_HOST={backend}", "REVERSE_PROXY_URL=/",
             # BunkerWeb transmet déjà Host, X-Real-IP, X-Forwarded-For et X-Forwarded-Proto (ne pas les redéfinir : en-têtes en double)
             "USE_MODSECURITY=yes", "USE_MODSECURITY_CRS=yes", "USE_BAD_BEHAVIOR=yes", "USE_LIMIT_REQ=yes", "USE_DNSBL=yes",
             f"AUTO_LETS_ENCRYPT={'yes' if opts.get('lets_encrypt') else 'no'}"]
    if opts.get("lets_encrypt") and opts.get("email"):
        email = str(opts["email"]).strip()
        if re.fullmatch(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", email):
            lines.append(f"EMAIL_LETS_ENCRYPT={email}")
    lines.append("")
    for site in sites:
        domains = [d for d in (site.get("domains") or [site["name"]]) if re.fullmatch(r"[A-Za-z0-9.*-]+", d)]
        if not domains:
            continue
        key = domains[0].replace("*.", "")
        servers.append(key)
        lines += [f"# site {site['name']}", f"{key}_SERVER_NAME={' '.join(domains)}", f"{key}_USE_REVERSE_PROXY=yes",
                  f"{key}_REVERSE_PROXY_HOST={backend}", f"{key}_REVERSE_PROXY_URL=/"]
        cert, keyf = _cert_in_container(site.get("ssl_cert") or ""), _cert_in_container(site.get("ssl_key") or "")
        if site.get("ssl_enabled") and cert and keyf:
            lines += [f"{key}_USE_CUSTOM_SSL=yes", f"{key}_CUSTOM_SSL_CERT={cert}", f"{key}_CUSTOM_SSL_KEY={keyf}"]
        elif opts.get("lets_encrypt"):
            lines.append(f"{key}_AUTO_LETS_ENCRYPT=yes")
        if site.get("force_https"):
            lines.append(f"{key}_REDIRECT_HTTP_TO_HTTPS=yes")
        if not site.get("waf_enabled", True):
            lines += [f"{key}_USE_MODSECURITY=no", f"{key}_USE_BAD_BEHAVIOR=no"]
        lines.append("")
    lines.insert(1, "SERVER_NAME=" + " ".join(servers))
    return "\n".join(lines)


def safeline_env(mgt_port: int) -> str:
    return "\n".join([f"SAFELINE_DIR={engine_dir('safeline')}", "IMAGE_TAG=latest", f"MGT_PORT={mgt_port}",
                      f"POSTGRES_PASSWORD={secrets.token_hex(16)}", "SUBNET_PREFIX=172.22.222", "IMAGE_PREFIX=chaitin",
                      "ARCH_SUFFIX=", "RELEASE=", "CHANNEL=", "REGION=", "MGT_PROXY=", ""])


def safeline_sites_payload(db) -> list[dict]:
    """Corps des appels POST /api/open/site pour chaque site du panel."""
    from toutpanel.services.webserver import web_ports

    http_port, https_port = web_ports()
    out = []
    for site in _sites(db):
        domains = site.get("domains") or [site["name"]]
        ports = ["80"] + (["443"] if site.get("ssl_enabled") else [])
        out.append({"ports": ports, "server_names": domains, "upstreams": [f"http://127.0.0.1:{http_port}"],
                    "comment": f"ToutPanel: {site['name']}"})
    return out


def safeline_known_names(resp: dict) -> set[str]:
    """Noms de serveurs déjà déclarés dans SafeLine. GET /api/open/site répond {"data": {"data": [...]}} (ou "nodes", ou une liste)."""
    data = resp.get("data") or {}
    if isinstance(data, dict):
        items = data.get("data") or data.get("nodes") or []
    else:
        items = data
    names: set[str] = set()
    for it in items:
        if isinstance(it, dict):
            names.update(str(n) for n in it.get("server_names") or [])
    return names


def _safeline_api(path: str, payload: Optional[dict] = None, method: str = "POST") -> dict:
    s = config.get_settings()
    token = s.get("safeline_api_token") or ""
    if not token:
        raise RuntimeError("Jeton API SafeLine absent (Réglages du moteur → jeton créé dans la console SafeLine, Système → API)")
    url = f"https://127.0.0.1:{s.get('safeline_mgt_port', 9443)}{path}"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"X-SLCE-API-TOKEN": token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20, context=ctx) as resp:
        body = resp.read().decode("utf-8", "replace")
    try:
        return json.loads(body) if body else {}
    except json.JSONDecodeError:
        return {"raw": body}


# --------------------------------------------------------------------------- ports du serveur web

def switch_web_ports(db, http_port: int, https_port: int, log: Callable[[str], None]) -> str:
    """Déplace les vhosts du panel sur d'autres ports, réécrit la configuration proxy et recharge le serveur web."""
    from toutpanel.services import webserver

    s = config.get_settings()
    s.update({"web_http_port": int(http_port), "web_https_port": int(https_port)})
    adapter = webserver.get_adapter()
    log(f"Serveur web {adapter.name} : vhosts déplacés sur les ports {http_port} / {https_port}")
    webserver.write_proxy_conf()
    if adapter.name == "nginx":
        moved = webserver.move_default_server(http_port, https_port)
        if moved:
            log("Serveur par défaut de la distribution déplacé : " + ", ".join(moved))
    for site in _sites(db):
        try:
            adapter.apply(site)
        except Exception as e:  # noqa: BLE001
            log(f"  {site['name']} : {e}")
    if adapter.name == "apache":
        webserver.write_apache_ports(http_port, https_port)
    if webserver.is_installed(adapter.name):
        r = adapter.reload()
        if not r.ok:
            log(f"Rechargement {adapter.name} échoué : {r.output[:300]}")
            return r.output
        log(f"{adapter.name} rechargé")
    return ""


# --------------------------------------------------------------------------- installation / synchronisation

def _ensure_docker(log) -> bool:
    if docker.available():
        return True
    from toutpanel.services import software

    log("Docker absent : installation…")
    try:
        item = software._item("docker")
    except ValueError:
        return False
    plat = get_platform()
    fam = software.distro_family()
    pkgs = item["pkgs"].get(fam) or []
    if not pkgs:
        log("Docker n'est pas disponible pour ce système.")
        return False
    if fam == "rhel":
        software._prepare_rhel(item, plat, log)
    if plat.install_packages(pkgs, log) != 0:
        return False
    plat.service_action("docker", "enable")
    plat.service_action("docker", "start")
    ok = docker.available()
    log("Docker : " + ("prêt" if ok else "démarrage impossible"))
    return ok


def _open_port(port: int, remark: str, log) -> None:
    try:
        from toutpanel.db import session_scope
        from toutpanel.services import firewall

        with session_scope() as db:
            firewall.add_rule(db, str(port), "tcp", "allow", "", remark)
        log(f"Pare-feu : port {port}/tcp ouvert")
    except Exception as e:  # noqa: BLE001
        log(f"Pare-feu : port {port} non ouvert ({e})")


def install(engine: str, opts: Optional[dict] = None) -> int:
    if engine not in ("bunkerweb", "safeline"):
        raise ValueError("Moteur inconnu")
    opts = dict(opts or {})
    info = ENGINES[engine]

    def _job(log):
        from toutpanel.db import session_scope

        plat = get_platform()
        if config.IS_WINDOWS:
            log("Les moteurs WAF externes nécessitent Docker sous Linux.")
            return 1
        if not _ensure_docker(log):
            return 1
        http_port = int(opts.get("web_http_port") or DEFAULT_FALLBACK_PORTS[0])
        https_port = int(opts.get("web_https_port") or DEFAULT_FALLBACK_PORTS[1])
        with session_scope() as db:
            log("=== Étape 1/3 : libération des ports 80 / 443")
            config.get_settings().set("waf_engine", engine)  # dès maintenant : IP réelle du client transmise au serveur web
            err = switch_web_ports(db, http_port, https_port, log)
            if err:
                log("Le serveur web n'a pas pu être rechargé : arrêt.")
                config.get_settings().set("waf_engine", "builtin")
                return 1
            log(f"=== Étape 2/3 : déploiement de {info['name']}")
            if engine == "bunkerweb":
                rc = _install_bunkerweb(db, opts, plat, log)
            else:
                rc = _install_safeline(db, opts, plat, log)
            if rc != 0:
                log("Échec du déploiement : restauration des ports 80 / 443")
                config.get_settings().set("waf_engine", "builtin")
                switch_web_ports(db, 80, 443, log)
                return rc
        log("=== Étape 3/3 : pare-feu")
        for p in (80, 443):
            _open_port(p, "web", log)
        ui_port = int(config.get_settings().get(info["ui_port_key"]))
        _open_port(ui_port, info["name"], log)
        log(f"{info['name']} est installé. Console : {status()['engines'][engine]['ui_url']}")
        log("Terminé avec le code 0")
        return 0

    return tasks.run_in_background(f"Installation {info['name']}", _job)


def _install_bunkerweb(db, opts: dict, plat, log) -> int:
    s = config.get_settings()
    ui_port = int(opts.get("ui_port") or s.get("bunkerweb_ui_port", 7000))
    s.set("bunkerweb_ui_port", ui_port)
    d = engine_dir("bunkerweb")
    env_file = d / "bunkerweb.env"
    env_file.write_text(bunkerweb_env(db, opts), encoding="utf-8")
    (d / "options.json").write_text(json.dumps({k: v for k, v in opts.items() if k in ("lets_encrypt", "email")}), encoding="utf-8")
    log(f"Fichier d'environnement : {env_file} ({len(_sites(db))} site(s))")
    log(f"$ docker pull {BUNKERWEB_IMAGE}")
    if docker.pull(BUNKERWEB_IMAGE, log) != 0:
        return 1
    return _run_bunkerweb(plat, log)


def _run_bunkerweb(plat, log) -> int:
    d = engine_dir("bunkerweb")
    plat.run(["docker", "rm", "-f", BUNKERWEB_CONTAINER], timeout=60)
    ui_port = int(config.get_settings().get("bunkerweb_ui_port", 7000))
    # réseau bridge : BunkerWeb écoute sur 8080/8443 dans le conteneur (utilisateur non privilégié), publiés sur 80/443
    cmd = ["docker", "run", "-d", "--name", BUNKERWEB_CONTAINER, "--restart", "unless-stopped",
           "-p", "80:8080", "-p", "443:8443", "-p", f"{ui_port}:7000", "--add-host", "host.docker.internal:host-gateway",
           "--env-file", str(d / "bunkerweb.env"), "-v", "toutpanel-bunkerweb-data:/data",
           "-v", f"{config.SSL_DIR}:/tp-ssl:ro"]
    if Path("/etc/letsencrypt").is_dir():
        cmd += ["-v", "/etc/letsencrypt:/etc/letsencrypt:ro"]
    cmd.append(BUNKERWEB_IMAGE)
    log("$ " + " ".join(cmd))
    r = plat.run(cmd, timeout=300)
    if not r.ok:
        log(r.output[:1500])
        return 1
    log(f"Conteneur {BUNKERWEB_CONTAINER} démarré. Première visite de la console : assistant de configuration (/setup).")
    return 0


_PULL_NOISE = ("Extracting", "Downloading", "Waiting", "Pulling fs layer", "Verifying Checksum", "Download complete", "Already exists")


def quiet_compose_log(log: Callable[[str], None]) -> Callable[[str], None]:
    """Ne transmet au journal de tâche que les lignes utiles de docker compose (pas la progression octet par octet)."""
    def _w(line: str) -> None:
        t = line.strip()
        if not t or any(k in t for k in _PULL_NOISE):
            return
        log(line)
    return _w


def nofile_hard_limit() -> int:
    """Limite dure de fichiers ouverts de l'hôte (0 si inconnue)."""
    try:
        import resource

        return int(resource.getrlimit(resource.RLIMIT_NOFILE)[1])
    except Exception:  # noqa: BLE001
        return 0


def safeline_override(compose_dir: Path) -> Optional[Path]:
    """SafeLine demande nofile=131072 pour tengine ; si l'hôte ne l'autorise pas (conteneur, VPS bridé),
    un fichier d'override abaisse la limite au maximum permis au lieu de faire échouer le déploiement."""
    hard = nofile_hard_limit()
    if hard <= 0 or hard >= 131072:
        return None
    p = compose_dir / "compose.override.yaml"
    p.write_text(f"services:\n  tengine:\n    ulimits:\n      nofile: {hard}\n", encoding="utf-8")
    return p


def _install_safeline(db, opts: dict, plat, log) -> int:
    s = config.get_settings()
    mgt_port = int(opts.get("ui_port") or s.get("safeline_mgt_port", 9443))
    s.set("safeline_mgt_port", mgt_port)
    if opts.get("api_token"):
        s.set("safeline_api_token", str(opts["api_token"]).strip())
    d = engine_dir("safeline")
    compose = d / "compose.yaml"
    if not compose.exists():
        log(f"$ curl -fsSL {SAFELINE_RELEASE}/compose.yaml")
        r = plat.run(["curl", "-fsSL", "-o", str(compose), f"{SAFELINE_RELEASE}/compose.yaml"], timeout=120)
        if not r.ok:
            log("Téléchargement du fichier compose impossible : " + r.output[:300])
            return 1
    env_file = d / ".env"
    if not env_file.exists():
        env_file.write_text(safeline_env(mgt_port), encoding="utf-8")
    else:
        txt = re.sub(r"^MGT_PORT=.*$", f"MGT_PORT={mgt_port}", env_file.read_text(encoding="utf-8"), flags=re.M)
        env_file.write_text(txt, encoding="utf-8")
    if not plat.run(["docker", "compose", "version"], timeout=20).ok:
        log("Le plugin docker compose est requis (paquet docker-compose-plugin / docker-compose-v2).")
        return 1
    files = ["-f", str(compose)]
    ov = safeline_override(d)
    if ov:
        log(f"Limite de fichiers ouverts de l'hôte : {nofile_hard_limit()} (override compose pour tengine)")
        files += ["-f", str(ov)]
    log("$ docker compose up -d  (téléchargement des images SafeLine, plusieurs minutes)")
    rc = plat.stream(["docker", "compose", *files, "--env-file", str(env_file), "up", "-d"], quiet_compose_log(log), cwd=str(d))
    if rc != 0:
        return rc
    log("Attente de la console SafeLine (safeline-mgt)…")
    for _ in range(45):  # jusqu'à ~3 min : premier démarrage = initialisation de la base
        h = plat.run(["docker", "inspect", "-f", "{{.State.Health.Status}}", "safeline-mgt"], timeout=20)
        if h.ok and h.stdout.strip() == "healthy":
            break
        time.sleep(4)
    r = plat.run(["docker", "exec", "safeline-mgt", "/app/mgt-cli", "reset-admin", "--once"], timeout=120)
    if r.ok:
        log("Compte administrateur SafeLine :\n" + r.output.strip())
        (d / "admin.txt").write_text(r.output, encoding="utf-8")
    else:
        log("Mot de passe admin : lancez plus tard `docker exec safeline-mgt /app/mgt-cli reset-admin --once`")
    if s.get("safeline_api_token"):
        _safeline_sync(db, log)
    else:
        log("Sites : créez un jeton API dans la console SafeLine (Système → API) puis WAF → Moteur → Synchroniser.")
    return 0


def _safeline_sync(db, log) -> str:
    created, errors = 0, []
    try:
        existing = _safeline_api("/api/open/site", None, "GET")
    except Exception as e:  # noqa: BLE001
        log(f"API SafeLine injoignable : {e}")
        return str(e)
    known = safeline_known_names(existing)
    for payload in safeline_sites_payload(db):
        if any(n in known for n in payload["server_names"]):
            continue
        try:
            resp = _safeline_api("/api/open/site", payload)
            if resp.get("err"):
                errors.append(f"{payload['server_names'][0]} : {resp.get('msg') or resp.get('err')}")
            else:
                created += 1
        except Exception as e:  # noqa: BLE001
            errors.append(f"{payload['server_names'][0]} : {e}")
    log(f"SafeLine : {created} site(s) créé(s)" + (", erreurs : " + "; ".join(errors) if errors else ""))
    return "; ".join(errors)


def sync(engine: str, db, log: Optional[Callable[[str], None]] = None) -> str:
    """Re-synchronise les sites du panel dans le moteur actif. Retourne un message d'erreur éventuel."""
    log = log or (lambda m: None)
    plat = get_platform()
    if engine == "bunkerweb":
        d = engine_dir("bunkerweb")
        try:
            opts = json.loads((d / "options.json").read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            opts = {}
        (d / "bunkerweb.env").write_text(bunkerweb_env(db, opts), encoding="utf-8")
        log("Environnement BunkerWeb régénéré, redémarrage du conteneur…")
        return "" if _run_bunkerweb(plat, log) == 0 else "Redémarrage BunkerWeb échoué"
    if engine == "safeline":
        return _safeline_sync(db, log)
    raise ValueError("Moteur inconnu")


def action(engine: str, act: str) -> str:
    plat = get_platform()
    if act not in ("start", "stop", "restart"):
        raise ValueError("Action invalide")
    if engine == "bunkerweb":
        r = plat.run(["docker", act, BUNKERWEB_CONTAINER], timeout=120)
    elif engine == "safeline":
        d = engine_dir("safeline")
        r = plat.run(["docker", "compose", "-f", str(d / "compose.yaml"), "--env-file", str(d / ".env"), act], timeout=300, cwd=str(d))
    else:
        raise ValueError("Moteur inconnu")
    return "" if r.ok else r.output


def uninstall(engine: str) -> int:
    if engine not in ("bunkerweb", "safeline"):
        raise ValueError("Moteur inconnu")
    info = ENGINES[engine]

    def _job(log):
        from toutpanel.db import session_scope

        plat = get_platform()
        if engine == "bunkerweb":
            log(f"$ docker rm -f {BUNKERWEB_CONTAINER}")
            plat.run(["docker", "rm", "-f", BUNKERWEB_CONTAINER], timeout=120)
            plat.run(["docker", "volume", "rm", "toutpanel-bunkerweb-data"], timeout=60)
        else:
            d = engine_dir("safeline")
            if (d / "compose.yaml").exists():
                log("$ docker compose down -v")
                files = ["-f", str(d / "compose.yaml")] + (["-f", str(d / "compose.override.yaml")] if (d / "compose.override.yaml").exists() else [])
                plat.stream(["docker", "compose", *files, "--env-file", str(d / ".env"), "down", "-v"], quiet_compose_log(log), cwd=str(d))
        with session_scope() as db:
            config.get_settings().set("waf_engine", "builtin")
            switch_web_ports(db, 80, 443, log)
        log(f"{info['name']} retiré, le serveur web écoute de nouveau sur 80 / 443. Terminé avec le code 0")
        return 0

    return tasks.run_in_background(f"Suppression {info['name']}", _job)
