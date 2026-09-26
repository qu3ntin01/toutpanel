"""Serveur FTP intégré (pyftpdlib) - multiplateforme, utilisateurs stockés en base."""
from __future__ import annotations
from typing import Optional

import logging
import threading
from pathlib import Path

from toutpanel import config
from toutpanel.db import session_scope
from toutpanel.models import FtpUser
from toutpanel.security import hash_password, verify_password

_server = None
_thread: Optional[threading.Thread] = None
_lock = threading.Lock()
log = logging.getLogger("toutpanel.ftp")


class DbAuthorizer:
    """Authorizer pyftpdlib qui lit les utilisateurs en base à chaque connexion."""

    def _get(self, username: str) -> Optional[FtpUser]:
        with session_scope() as db:
            return db.query(FtpUser).filter(FtpUser.username == username, FtpUser.enabled.is_(True)).first()

    def validate_authentication(self, username, password, handler):
        from pyftpdlib.authorizers import AuthenticationFailed

        u = self._get(username)
        if not u or not verify_password(password, u.password):
            raise AuthenticationFailed("Authentication failed.")

    def get_home_dir(self, username):
        u = self._get(username)
        return u.home if u else str(config.WWW_ROOT)

    def impersonate_user(self, username, password):
        pass

    def terminate_impersonation(self, username):
        pass

    def has_user(self, username):
        return self._get(username) is not None

    def has_perm(self, username, perm, path=None):
        u = self._get(username)
        return bool(u) and perm in (u.perm or "")

    def get_perms(self, username):
        u = self._get(username)
        return u.perm if u else ""

    def get_msg_login(self, username):
        return "Bienvenue sur ToutPanel FTP"

    def get_msg_quit(self, username):
        return "Au revoir."


def is_running() -> bool:
    return _thread is not None and _thread.is_alive()


def start() -> str:
    global _server, _thread
    with _lock:
        if is_running():
            return "déjà démarré"
        from pyftpdlib.handlers import FTPHandler
        from pyftpdlib.servers import ThreadedFTPServer

        s = config.get_settings()
        port = int(s.get("ftp_port", 21))
        pr = str(s.get("ftp_passive_ports", "60000-60100"))
        try:
            lo, hi = [int(x) for x in pr.split("-")]
        except ValueError:
            lo, hi = 60000, 60100

        class Handler(FTPHandler):
            pass

        Handler.authorizer = DbAuthorizer()
        Handler.banner = "ToutPanel FTP prêt."
        Handler.passive_ports = range(lo, hi + 1)
        Handler.permit_foreign_addresses = True
        try:
            _server = ThreadedFTPServer(("0.0.0.0", port), Handler)
        except OSError as e:
            return f"impossible d'écouter sur le port {port} : {e}"
        _server.max_cons = 256
        _server.max_cons_per_ip = 10
        _thread = threading.Thread(target=_server.serve_forever, name="toutpanel-ftp", daemon=True)
        _thread.start()
        log.info("FTP démarré sur le port %s", port)
        return ""


def stop() -> None:
    global _server, _thread
    with _lock:
        if _server is not None:
            try:
                _server.close_all()
            except Exception:
                pass
        _server = None
        _thread = None


def restart() -> str:
    stop()
    return start()


def create_user(db, username: str, password: str, home: str, perm: str = "elradfmwMT") -> FtpUser:
    import re

    if not re.fullmatch(r"[a-zA-Z0-9_.-]{2,64}", username):
        raise ValueError("Nom d'utilisateur invalide")
    if len(password) < 6:
        raise ValueError("Mot de passe trop court (6 min)")
    if db.query(FtpUser).filter(FtpUser.username == username).first():
        raise ValueError("Utilisateur déjà existant")
    Path(home).mkdir(parents=True, exist_ok=True)
    u = FtpUser(username=username, password=hash_password(password), home=str(Path(home)), perm=perm)
    db.add(u)
    db.flush()
    return u
