"""Chemins, constantes et paramètres persistants du panel.

Le panel stocke tout dans un répertoire "home" :
  - Linux   : /www/toutpanel   (surchargeable via TOUTPANEL_HOME)
  - Windows : C:\\toutpanel     (surchargeable via TOUTPANEL_HOME)
"""
from __future__ import annotations
from typing import Optional

import json
import os
import platform
import secrets
import sys
from pathlib import Path

IS_WINDOWS = sys.platform.startswith("win")
IS_LINUX = sys.platform.startswith("linux")
IS_MAC = sys.platform == "darwin"
OS_NAME = "windows" if IS_WINDOWS else ("linux" if IS_LINUX else platform.system().lower())


def default_home() -> Path:
    env = os.environ.get("TOUTPANEL_HOME")
    if env:
        return Path(env)
    if IS_WINDOWS:
        return Path(os.environ.get("SystemDrive", "C:") + "\\toutpanel")
    return Path("/www/toutpanel")


HOME = default_home()
DATA_DIR = HOME / "data"
LOG_DIR = HOME / "logs"
VHOST_DIR = HOME / "vhost"
SSL_DIR = HOME / "ssl"
BACKUP_DIR = HOME / "backup"
TMP_DIR = HOME / "tmp"
PLUGIN_DIR = HOME / "plugins"
WWW_ROOT = Path(os.environ.get("TOUTPANEL_WWW", str(HOME.parent / "wwwroot" if not IS_WINDOWS else HOME / "wwwroot")))
DB_PATH = DATA_DIR / "toutpanel.db"
SETTINGS_PATH = DATA_DIR / "settings.json"
PID_PATH = DATA_DIR / "panel.pid"

PACKAGE_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = PACKAGE_DIR / "web" / "templates"
STATIC_DIR = PACKAGE_DIR / "web" / "static"
I18N_DIR = PACKAGE_DIR / "i18n"
# Langues de l'interface (code -> nom natif, locale JS, sens d'écriture)
LANGUAGES = {
    "fr": ("Français", "fr-FR", "ltr"), "en": ("English", "en-GB", "ltr"), "es": ("Español", "es-ES", "ltr"), "de": ("Deutsch", "de-DE", "ltr"),
    "it": ("Italiano", "it-IT", "ltr"), "pt": ("Português", "pt-PT", "ltr"), "nl": ("Nederlands", "nl-NL", "ltr"), "ru": ("Русский", "ru-RU", "ltr"),
    "zh": ("中文", "zh-CN", "ltr"), "ar": ("العربية", "ar", "rtl"),
}

DEFAULT_SETTINGS = {
    "panel_port": 8888,
    "panel_host": "0.0.0.0",
    "panel_ssl": False,
    "security_entrance": "",          # ex: "/tp_a1b2c3" - vide = désactivé
    "session_hours": 12,
    "language": "fr",
    "ip_whitelist": [],
    "trusted_proxies": ["127.0.0.1", "::1"],
    "max_login_attempts": 5,
    "lockout_minutes": 10,
    "ftp_enabled": False,
    "ftp_port": 21,
    "ftp_passive_ports": "60000-60100",
    "webserver": "auto",              # auto | nginx | apache | iis
    "web_http_port": 80,              # ports d'écoute des vhosts (8080/8443 derrière BunkerWeb ou SafeLine)
    "web_https_port": 443,
    "waf_engine": "builtin",          # builtin | bunkerweb | safeline
    "bunkerweb_ui_port": 7000,
    "safeline_mgt_port": 9443,
    "safeline_api_token": "",
    "backup_keep": 5,
    "monitor_enabled": True,
    "monitor_interval": 60,
    "monitor_retention_days": 7,
    "secret_key": "",
    "panel_name": "ToutPanel",
}


def ensure_dirs() -> None:
    for d in (HOME, DATA_DIR, LOG_DIR, VHOST_DIR, SSL_DIR, BACKUP_DIR, TMP_DIR, PLUGIN_DIR, WWW_ROOT):
        try:
            d.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            pass
    # les données du panel (clé de session, base, mots de passe root) ne sont lisibles que par son compte
    if not IS_WINDOWS:
        for d in (DATA_DIR, SSL_DIR, BACKUP_DIR):
            try:
                os.chmod(d, 0o700)
            except OSError:
                pass


def atomic_write(path: Path, text: str, mode: Optional[int] = None) -> None:
    """Écrit un fichier de configuration sans jamais laisser un contenu tronqué visible (tmp + fsync + rename) :
    un `nginx -t` concurrent ne lit jamais un fichier à moitié écrit."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        try:
            os.fsync(f.fileno())
        except OSError:
            pass
    if mode is not None and not IS_WINDOWS:
        try:
            os.chmod(tmp, mode)
        except OSError:
            pass
    os.replace(tmp, path)


def restrict_file(path: Path) -> None:
    """Fichier lisible et modifiable uniquement par le propriétaire (secrets)."""
    if IS_WINDOWS:
        return
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


_save_lock = __import__("threading").Lock()
log = __import__("logging").getLogger("toutpanel.config")


class Settings:
    """Paramètres persistés dans settings.json (lecture/écriture atomique, sauvegarde .bak)."""

    def __init__(self, path: Path = SETTINGS_PATH):
        self.path = path
        self._data: dict = dict(DEFAULT_SETTINGS)
        self._mtime = None
        self.load()

    def load(self) -> None:
        loaded = False
        if self.path.exists():
            for cand in (self.path, self.path.with_suffix(".json.bak")):
                try:
                    self._data.update(json.loads(cand.read_text(encoding="utf-8")))
                    self._mtime = self.path.stat().st_mtime_ns
                    loaded = True
                    if cand != self.path:
                        log.warning("settings.json illisible : sauvegarde .bak utilisée")
                    break
                except (json.JSONDecodeError, OSError):
                    continue
            if not loaded and self.path.stat().st_size > 0:
                # ne jamais écraser un fichier existant mais illisible : on perdrait port, entrée, secrets
                raise RuntimeError(f"{self.path} est illisible (JSON invalide) : corrigez ou restaurez le fichier .bak")
        if not self._data.get("secret_key"):
            self._data["secret_key"] = secrets.token_hex(32)
            self.save()
        apply_dir_overrides(self._data)

    def save(self) -> None:
        ensure_dirs()
        with _save_lock:
            if self.path.exists():
                try:
                    bak = self.path.with_suffix(".json.bak")
                    bak.write_bytes(self.path.read_bytes())
                    restrict_file(bak)
                except OSError:
                    pass
            atomic_write(self.path, json.dumps(self._data, indent=2, ensure_ascii=False), mode=0o600)
            try:
                self._mtime = self.path.stat().st_mtime_ns
            except OSError:
                pass

    def refresh_if_changed(self) -> None:
        """Recharge settings.json s'il a été modifié par un autre processus (CLI, installeur)."""
        try:
            m = self.path.stat().st_mtime_ns
        except OSError:
            return
        if m != getattr(self, "_mtime", None):
            self._data = dict(DEFAULT_SETTINGS)
            self.load()

    def get(self, key: str, default=None):
        return self._data.get(key, default)

    def set(self, key: str, value) -> None:
        self._data[key] = value
        self.save()

    def update(self, values: dict) -> None:
        self._data.update(values)
        self.save()

    def as_dict(self) -> dict:
        d = dict(self._data)
        d.pop("secret_key", None)
        return d


_DEFAULT_WWW_ROOT = WWW_ROOT
_DEFAULT_BACKUP_DIR = BACKUP_DIR


def apply_dir_overrides(data: Optional[dict] = None) -> None:
    """Applique les répertoires personnalisés (www_root, backup_dir) définis dans les paramètres."""
    global WWW_ROOT, BACKUP_DIR
    if data is None:
        data = _settings._data if _settings else {}
    WWW_ROOT = Path(data["www_root"]) if data.get("www_root") else _DEFAULT_WWW_ROOT
    BACKUP_DIR = Path(data["backup_dir"]) if data.get("backup_dir") else _DEFAULT_BACKUP_DIR
    for d in (WWW_ROOT, BACKUP_DIR):
        try:
            d.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass


_settings: Optional[Settings] = None


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        ensure_dirs()
        _settings = Settings()
    else:
        _settings.refresh_if_changed()
    return _settings


def reset_settings_cache() -> None:
    global _settings
    _settings = None
