"""WP Toolkit : installation de WordPress en un clic dans un site."""
from __future__ import annotations

import re
import secrets
import zipfile
from pathlib import Path

from toutpanel import config
from toutpanel.db import session_scope
from toutpanel.models import Database, Site
from toutpanel.platform import get_platform
from toutpanel.security import generate_password
from toutpanel.services import databases, tasks

WP_URL = {"fr": "https://fr.wordpress.org/latest-fr_FR.zip", "en": "https://wordpress.org/latest.zip"}


def _download(url: str, dest: Path, log) -> None:
    import httpx

    log(f"Téléchargement de {url}")
    with httpx.stream("GET", url, follow_redirects=True, timeout=120) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_bytes(1024 * 256):
                f.write(chunk)
    log(f"Téléchargé : {dest.stat().st_size // 1024} Ko")


def _salts() -> str:
    keys = ["AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY", "AUTH_SALT", "SECURE_AUTH_SALT",
            "LOGGED_IN_SALT", "NONCE_SALT"]
    return "\n".join(f"define('{k}', '{secrets.token_urlsafe(48)}');" for k in keys)


def install(site_id: int, lang: str = "fr", db_engine: str = "mysql", db_name: str = "", db_user: str = "",
            db_password: str = "", table_prefix: str = "wp_") -> int:
    if not re.fullmatch(r"[a-z0-9_]{1,12}", table_prefix):
        raise ValueError("Préfixe de table invalide")

    def _job(log):
        with session_scope() as db:
            site = db.get(Site, site_id)
            if not site:
                site_root = None
            else:
                site_root, name = site.root, site.name
        if site_root is None:
            log("Site introuvable")
            return 1
        root = Path(site_root)
        log(f"Installation de WordPress dans {root}")
        dbn = db_name or re.sub(r"[^a-z0-9_]", "_", name.lower())[:48]
        dbu = db_user or dbn[:32]
        dbp = db_password or generate_password(20)
        db_msg, db_err = "", ""
        with session_scope() as db:  # session courte : pas de log pendant la transaction (verrou SQLite)
            existing = db.query(Database).filter(Database.name == dbn, Database.engine == db_engine).first()
            if existing:
                db_msg = f"Base {dbn} déjà présente dans le panel, réutilisation."
                dbu, dbp = existing.username, existing.password
            else:
                try:
                    databases.create_database(db, dbn, db_engine, dbu, dbp)
                    db_msg = f"Base de données {dbn} créée (utilisateur {dbu})."
                except databases.DbError as e:
                    db_err = str(e)
        if db_err:
            log(f"Erreur base de données : {db_err}")
            return 1
        log(db_msg)
        if lang not in WP_URL:
            lang = "en"
        tmp = config.TMP_DIR / f"wordpress_{lang}.zip"
        config.TMP_DIR.mkdir(parents=True, exist_ok=True)
        try:
            _download(WP_URL.get(lang, WP_URL["en"]), tmp, log)
        except Exception as e:
            log(f"Téléchargement impossible : {e}")
            return 1
        with zipfile.ZipFile(tmp) as zf:
            log("Extraction…")
            for m in zf.infolist():
                rel = m.filename.split("/", 1)[1] if "/" in m.filename else ""
                if not rel:
                    continue
                target = root / rel
                if m.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with zf.open(m) as src, open(target, "wb") as dst:
                        dst.write(src.read())
        sample = (root / "wp-config-sample.php").read_text(encoding="utf-8")
        host = "localhost"
        php_str = lambda v: v.replace("\\", "\\\\").replace("'", "\\'")  # noqa: E731 — littéral PHP entre apostrophes
        cfg = sample.replace("database_name_here", dbn).replace("username_here", dbu).replace("password_here", php_str(dbp)) \
            .replace("localhost", host).replace("$table_prefix = 'wp_';", f"$table_prefix = '{table_prefix}';")
        cfg = re.sub(r"define\( 'AUTH_KEY'.*?define\( 'NONCE_SALT',\s*'put your unique phrase here' \);", _salts(), cfg, flags=re.S)
        (root / "wp-config.php").write_text(cfg, encoding="utf-8")
        index = root / "index.html"
        if index.exists() and "ToutPanel" in index.read_text(encoding="utf-8", errors="ignore"):
            index.unlink()
        get_platform().chown_web(str(root))
        log("WordPress installé. Ouvrez le site pour terminer la configuration (titre, admin).")
        log(f"Base : {dbn} / utilisateur : {dbu}")
        return 0

    return tasks.run_in_background(f"WordPress → site #{site_id}", _job)


def detect(site_root: str) -> dict:
    root = Path(site_root)
    cfg = root / "wp-config.php"
    version = ""
    vfile = root / "wp-includes" / "version.php"
    if vfile.exists():
        m = re.search(r"\$wp_version\s*=\s*'([^']+)'", vfile.read_text(encoding="utf-8", errors="ignore"))
        version = m.group(1) if m else ""
    return {"installed": cfg.exists(), "version": version}
