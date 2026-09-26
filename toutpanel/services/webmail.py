"""Webmail Roundcube installé et configuré automatiquement contre le serveur mail du panel.

- Téléchargement de la version complète depuis GitHub, extraction dans <www_root>/webmail.
- Base MySQL créée par le panel (ou SQLite en repli), schéma initialisé par bin/initdb.sh.
- config/config.inc.php généré : IMAP / SMTP locaux (Dovecot / Postfix), clé DES aléatoire, thème Elastic,
  langue du panel, dossiers spéciaux, plugins utiles (archive, zipdownload, markasjunk, emoticons, newmail_notifier).
- Site PHP créé dans le panel (domaine webmail.<domaine>) avec un snippet de sécurité (config/, temp/, logs/, bin/ interdits).
"""
from __future__ import annotations

import json
import re
import secrets
import shutil
import tarfile
from pathlib import Path
from typing import Optional

from toutpanel import config
from toutpanel.platform import get_platform
from toutpanel.services import tasks

ROUNDCUBE_VERSION = "1.6.9"
ROUNDCUBE_URL = f"https://github.com/roundcube/roundcubemail/releases/download/{ROUNDCUBE_VERSION}/roundcubemail-{ROUNDCUBE_VERSION}-complete.tar.gz"
SITE_NAME = "webmail"
LANG_MAP = {"fr": "fr_FR", "en": "en_US", "es": "es_ES", "de": "de_DE", "it": "it_IT", "pt": "pt_PT", "nl": "nl_NL", "ru": "ru_RU", "zh": "zh_CN", "ar": "ar_SA"}


class WebmailError(ValueError):
    pass


def root_dir() -> Path:
    return config.WWW_ROOT / SITE_NAME


def state_file() -> Path:
    return config.DATA_DIR / "webmail.json"


def state() -> dict:
    try:
        return json.loads(state_file().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def installed_version() -> str:
    p = root_dir() / "program" / "include" / "iniset.php"
    try:
        m = re.search(r"define\('RCMAIL_VERSION',\s*'([^']+)'", p.read_text(encoding="utf-8", errors="replace"))
        return m.group(1) if m else ""
    except OSError:
        return ""


def status(db=None) -> dict:
    from toutpanel.models import MailDomain, Site

    st = state()
    installed = (root_dir() / "config" / "config.inc.php").exists()
    site = None
    if db is not None and st.get("site_id"):
        s = db.get(Site, st["site_id"])
        if s:
            site = s.to_dict()
    domains = [d.domain for d in db.query(MailDomain).order_by(MailDomain.domain).all()] if db is not None else []
    url = ""
    if site:
        dom = (site.get("domains") or [""])[0]
        url = ("https://" if site.get("ssl_enabled") else "http://") + dom
    return {"installed": installed, "version": installed_version() if installed else "", "latest": ROUNDCUBE_VERSION, "root": str(root_dir()),
            "site": site, "url": url, "db_engine": st.get("db_engine", ""), "db_name": st.get("db_name", ""), "mail_domains": domains,
            "suggested_domain": ("webmail." + domains[0]) if domains else ""}


def render_config(opts: dict) -> str:
    """config.inc.php de Roundcube."""
    lang = LANG_MAP.get(config.get_settings().get("language", "fr"), "fr_FR")
    plugins = ["archive", "zipdownload", "markasjunk", "emoticons", "newmail_notifier", "attachment_reminder", "identity_select"]
    if opts.get("managesieve"):
        plugins.append("managesieve")
    lines = ["<?php", "// Généré par ToutPanel - Roundcube configuré contre le serveur mail du panel", "$config = [];",
             f"$config['db_dsnw'] = '{opts['dsn']}';",
             f"$config['imap_host'] = '{opts.get('imap_host', 'localhost:143')}';",
             "$config['imap_conn_options'] = ['ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true]];",
             f"$config['smtp_host'] = '{opts.get('smtp_host', 'localhost:587')}';",
             "$config['smtp_user'] = '%u';", "$config['smtp_pass'] = '%p';",
             "$config['smtp_conn_options'] = ['ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true]];",
             f"$config['support_url'] = '{opts.get('support_url', '')}';",
             f"$config['product_name'] = '{opts.get('product_name', 'Webmail')}';",
             f"$config['des_key'] = '{opts['des_key']}';",
             f"$config['plugins'] = {json.dumps(plugins)};".replace('"', "'"),
             "$config['skin'] = 'elastic';", f"$config['language'] = '{lang}';",
             "$config['create_default_folders'] = true;", "$config['drafts_mbox'] = 'Drafts';", "$config['junk_mbox'] = 'Junk';",
             "$config['sent_mbox'] = 'Sent';", "$config['trash_mbox'] = 'Trash';", "$config['archive_mbox'] = 'Archive';",
             "$config['htmleditor'] = 1;", "$config['draft_autosave'] = 60;", "$config['refresh_interval'] = 60;",
             "$config['session_lifetime'] = 30;", "$config['enable_installer'] = false;", "$config['check_all_folders'] = true;",
             "$config['log_driver'] = 'file';", "$config['temp_dir'] = __DIR__ . '/../temp';", "$config['log_dir'] = __DIR__ . '/../logs';",
             "$config['use_https'] = false;", "$config['ip_check'] = false;", "$config['login_rate_limit'] = 5;",
             "$config['max_message_size'] = '25M';", ""]
    return "\n".join(lines)


def security_snippet(nginx: bool = True) -> str:
    """Règles ajoutées au vhost : les dossiers internes de Roundcube ne doivent jamais être servis.
    nginx : préfixes « ^~ » pour passer avant le bloc PHP du modèle de vhost."""
    if nginx:
        lines = ["# Roundcube : dossiers sensibles interdits (généré par ToutPanel)"]
        for d in ("config", "temp", "logs", "bin", "SQL", "installer", "vendor"):
            lines.append(f"location ^~ /{d}/ {{ deny all; }}")
        lines.append("location ^~ /program/ { location ~ \\.php$ { deny all; } location ~* \\.(js|css|png|jpg|gif|svg|woff2?)$ { expires 30d; } }")
        lines.append("location ~ ^/(README\\.md|INSTALL|LICENSE|CHANGELOG\\.md|UPGRADING|SECURITY\\.md|composer\\.(json|lock|json-dist)|\\.htaccess)$ { deny all; }")
        return "\n".join(lines) + "\n"
    return ("# Roundcube : dossiers sensibles interdits (généré par ToutPanel)\n"
            "RedirectMatch 403 ^/(config|temp|logs|bin|SQL|installer|vendor)(/|$)\n"
            "RedirectMatch 403 ^/program/.*\\.php$\n"
            "RedirectMatch 403 ^/(README\\.md|INSTALL|LICENSE|CHANGELOG\\.md|UPGRADING|SECURITY\\.md|composer\\.(json|lock|json-dist))$\n")


def install(domain: str, db_engine: str = "auto", php_version: str = "", managesieve: bool = False) -> int:
    from toutpanel.services import sites as sites_svc

    domain = domain.strip().lower()
    if not sites_svc.DOMAIN_RE.match(domain):
        raise WebmailError("Nom de domaine invalide")
    if db_engine not in ("auto", "mysql", "sqlite"):
        raise WebmailError("Moteur de base invalide")

    def _job(log):
        from toutpanel.db import session_scope
        from toutpanel.models import Site
        from toutpanel.services import databases, sites as sites_svc, webserver

        plat = get_platform()
        if not (plat.which("php") or config.IS_WINDOWS):
            log("PHP est requis (Logiciels → PHP).")
            return 1
        root = root_dir()
        tmp = config.TMP_DIR / "roundcube"
        tmp.mkdir(parents=True, exist_ok=True)
        archive = tmp / f"roundcube-{ROUNDCUBE_VERSION}.tar.gz"
        log(f"=== Étape 1/4 : téléchargement de Roundcube {ROUNDCUBE_VERSION}")
        log(f"$ curl -L {ROUNDCUBE_URL}")
        r = plat.run(["curl", "-fsSL", "-o", str(archive), ROUNDCUBE_URL], timeout=600)
        if not r.ok or not archive.exists() or archive.stat().st_size < 1_000_000:
            log("Téléchargement impossible : " + r.output[-300:])
            return 1
        log(f"Archive : {archive.stat().st_size // 1024} Ko")
        log("=== Étape 2/4 : extraction")
        extract = tmp / "extract"
        shutil.rmtree(extract, ignore_errors=True)
        extract.mkdir(parents=True)
        with tarfile.open(archive) as tf:
            for m in tf.getmembers():
                if m.name.startswith("/") or ".." in m.name.split("/"):
                    log("Archive suspecte, arrêt")
                    return 1
            tf.extractall(extract)
        src = next((p for p in extract.iterdir() if p.is_dir()), None)
        if src is None:
            log("Archive vide")
            return 1
        keep_cfg = (root / "config" / "config.inc.php").read_text(encoding="utf-8") if (root / "config" / "config.inc.php").exists() else ""
        if root.exists():
            log(f"Mise à jour : ancienne installation conservée dans {root}.bak")
            shutil.rmtree(str(root) + ".bak", ignore_errors=True)
            root.rename(str(root) + ".bak")
        shutil.move(str(src), str(root))
        shutil.rmtree(root / "installer", ignore_errors=True)
        (root / "temp").mkdir(exist_ok=True)
        (root / "logs").mkdir(exist_ok=True)
        log(f"Roundcube extrait dans {root}")
        log("=== Étape 3/4 : base de données et configuration")
        # Les sessions SQLite sont courtes et fermées avant chaque log() : le journal de tâche écrit dans la même base.
        st = state()
        engine = db_engine
        if engine == "auto":
            engine = "mysql" if databases.engine_available("mysql") else "sqlite"
        msgs: list[str] = []
        dsn = ""
        if keep_cfg and st.get("dsn"):
            dsn = st["dsn"]
            msgs.append("Configuration existante réutilisée (base conservée)")
        elif engine == "mysql":
            pwd = secrets.token_urlsafe(18)
            name = "roundcube"
            try:
                with session_scope() as db:
                    row = databases.create_database(db, name, "mysql", "roundcube", pwd, remark="Webmail Roundcube")
                    dsn = f"mysql://{row.username}:{row.password}@localhost/{row.name}"
                msgs.append(f"Base MySQL « {name} » créée")
            except databases.DbError as e:
                if "existe déjà" in str(e) and st.get("dsn"):
                    dsn = st["dsn"]
                    msgs.append("Base MySQL existante réutilisée")
                else:
                    msgs.append(f"MySQL indisponible ({e}) : repli sur SQLite")
                    engine = "sqlite"
        if engine == "sqlite" and not dsn:
            sq = config.DATA_DIR / "sqlite"
            sq.mkdir(parents=True, exist_ok=True)
            dsn = f"sqlite:///{(sq / 'roundcube.db').as_posix()}?mode=0640"
        for m in msgs:
            log(m)
        cfg = keep_cfg or render_config({"dsn": dsn, "des_key": secrets.token_urlsafe(18)[:24], "product_name": config.get_settings().get("panel_name", "ToutPanel") + " Webmail",
                                         "managesieve": managesieve})
        (root / "config" / "config.inc.php").write_text(cfg, encoding="utf-8")
        if engine == "mysql" and not keep_cfg:
            php = plat.which("php") or "php"
            r = plat.run([php, str(root / "bin" / "initdb.sh"), "--dir", str(root / "SQL")], timeout=300, cwd=str(root))
            log("Schéma : " + ("initialisé" if r.ok else "échec — " + r.output[-300:]))
            if not r.ok:
                return 1
        log("=== Étape 4/4 : site web")
        msgs = []
        with session_scope() as db:
            site = db.get(Site, st["site_id"]) if st.get("site_id") else None
            if site is None:
                site = db.query(Site).filter(Site.name == SITE_NAME).first()
            if site is None:
                try:
                    site, warn = sites_svc.create_site(db, SITE_NAME, [domain], root=str(root), php_version=php_version or "", site_type="php",
                                                       remark="Webmail Roundcube (généré par ToutPanel)", create_index=False)
                    if warn:
                        msgs.append(warn)
                    msgs.append(f"Site « {SITE_NAME} » créé pour {domain}")
                except sites_svc.SiteError as e:
                    log(f"Site non créé : {e}")
                    return 1
            else:
                site.domains = [domain]
                site.root = str(root)
                if php_version:
                    site.php_version = php_version
                db.flush()
                msgs.append(f"Site « {SITE_NAME} » mis à jour ({domain})")
            site_id, site_dict = site.id, site.to_dict()
        for m in msgs:
            log(m)
        custom = config.VHOST_DIR / "custom"
        custom.mkdir(parents=True, exist_ok=True)
        adapter = webserver.get_adapter()
        (custom / f"{SITE_NAME}.conf").write_text(security_snippet(adapter.name == "nginx"), encoding="utf-8")
        adapter.apply(site_dict)
        if webserver.is_installed(adapter.name):
            rr = adapter.reload()
            log(f"{adapter.name} : " + ("rechargé" if rr.ok else rr.output[-300:]))
            if not rr.ok:
                log("Le serveur web a refusé la configuration : corrigez puis relancez l'installation.")
                return 1
        plat.chown_web(str(root))
        state_file().write_text(json.dumps({"site_id": site_id, "domain": domain, "db_engine": engine, "dsn": dsn, "db_name": "roundcube" if engine == "mysql" else "",
                                            "version": ROUNDCUBE_VERSION}), encoding="utf-8")
        shutil.rmtree(str(root) + ".bak", ignore_errors=True)
        shutil.rmtree(extract, ignore_errors=True)
        log(f"Webmail prêt : http://{domain}  (connexion avec une adresse mail complète et son mot de passe)")
        log("Terminé avec le code 0")
        return 0

    return tasks.run_in_background("Installation du webmail Roundcube", _job)


def uninstall(delete_data: bool = False) -> int:
    def _job(log):
        from toutpanel.db import session_scope
        from toutpanel.models import Database, Site
        from toutpanel.services import databases, sites as sites_svc

        st = state()
        msgs: list[str] = []
        with session_scope() as db:
            site = db.get(Site, st["site_id"]) if st.get("site_id") else db.query(Site).filter(Site.name == SITE_NAME).first()
            if site:
                sites_svc.delete_site(db, site, delete_files=False)
                msgs.append("Site webmail supprimé")
            if delete_data:
                row = db.query(Database).filter(Database.name == "roundcube", Database.engine == "mysql").first()
                if row:
                    databases.delete_database(db, row, drop=True)
                    msgs.append("Base MySQL roundcube supprimée")
                sq = config.DATA_DIR / "sqlite" / "roundcube.db"
                if sq.exists():
                    sq.unlink()
        for m in msgs:
            log(m)
        custom = config.VHOST_DIR / "custom" / f"{SITE_NAME}.conf"
        if custom.exists():
            custom.unlink()
        shutil.rmtree(root_dir(), ignore_errors=True)
        state_file().unlink(missing_ok=True)
        log("Fichiers Roundcube supprimés. Terminé avec le code 0")
        return 0

    return tasks.run_in_background("Suppression du webmail", _job)
