"""Dépendances communes : authentification (session révocable ou jeton d'API), liste blanche d'IP, accès BDD."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from fastapi import Depends, HTTPException, Request, WebSocket
from sqlalchemy.orm import Session

from toutpanel.db import DbDep
from toutpanel.models import ApiToken, User, UserSession
from toutpanel.security import SESSION_COOKIE, hash_token, ip_allowed, read_session_token

SESSION_TOUCH_SECONDS = 60


def client_ip(request) -> str:
    """IP du client. X-Forwarded-For n'est pris en compte que si la connexion directe provient d'un proxy
    de confiance (sinon n'importe qui pourrait usurper une IP de la liste blanche)."""
    from toutpanel.config import get_settings

    direct = request.client.host if request.client else "?"
    trusted = get_settings().get("trusted_proxies") or ["127.0.0.1", "::1"]
    fwd = request.headers.get("x-forwarded-for")
    if fwd and direct in trusted:
        return fwd.split(",")[0].strip()
    return direct


def _user_from_cookie(cookie: Optional[str], db: Session, ip: str = "") -> Optional[User]:
    if not cookie:
        return None
    data = read_session_token(cookie)
    if not data:
        return None
    sid = str(data.get("n") or "")
    sess = db.query(UserSession).filter(UserSession.sid == sid).first() if sid else None
    if not sess:
        return None
    now = datetime.utcnow()
    if sess.expires_at and sess.expires_at < now:
        db.delete(sess)
        return None
    user = db.get(User, int(data.get("uid", 0)))
    if not user or user.id != sess.user_id:
        return None
    if not sess.last_seen or (now - sess.last_seen).total_seconds() > SESSION_TOUCH_SECONDS:
        sess.last_seen = now
        if ip:
            sess.ip = ip
    return user


def _user_from_bearer(header: Optional[str], db: Session) -> Optional[User]:
    if not header or not header.lower().startswith("bearer "):
        return None
    raw = header[7:].strip()
    if not raw:
        return None
    tok = db.query(ApiToken).filter(ApiToken.token_hash == hash_token(raw)).first()
    if not tok:
        return None
    now = datetime.utcnow()
    if tok.expires_at and tok.expires_at < now:
        return None
    if not tok.last_used or (now - tok.last_used).total_seconds() > SESSION_TOUCH_SECONDS:
        tok.last_used = now
    return db.get(User, tok.user_id)


def current_user(request: Request, db: Session = DbDep) -> User:
    ip = client_ip(request)
    if not ip_allowed(ip):
        raise HTTPException(403, "IP non autorisée")
    user = _user_from_bearer(request.headers.get("authorization"), db)
    if user:
        request.state.auth = "token"
    else:
        user = _user_from_cookie(request.cookies.get(SESSION_COOKIE), db, ip)
        request.state.auth = "session"
    if not user:
        raise HTTPException(401, "Non authentifié")
    request.state.user = user.username
    request.state.role = user.role or "admin"
    if (user.role or "admin") == "viewer" and request.method in ("POST", "PUT", "PATCH", "DELETE") and not _viewer_allowed(request.url.path):
        raise HTTPException(403, "Compte en lecture seule : cette action est réservée aux administrateurs")
    return user


VIEWER_WRITABLE = ("/api/auth/logout", "/api/auth/sessions", "/api/settings/account", "/api/settings/totp", "/api/settings/tokens")


def _viewer_allowed(path: str) -> bool:
    """Un compte en lecture seule ne peut modifier que son propre compte (mot de passe, 2FA, sessions, jetons)."""
    return any(path.startswith(p) for p in VIEWER_WRITABLE)


def ws_user(websocket: WebSocket, db: Session) -> Optional[User]:
    """Utilisateur d'une connexion WebSocket : même origine obligatoire (pas de détournement depuis un autre site)."""
    if not ip_allowed(client_ip(websocket)):
        return None
    origin = websocket.headers.get("origin")
    host = websocket.headers.get("host")
    if origin and host:
        from urllib.parse import urlparse

        if urlparse(origin).netloc.lower() != host.lower():
            return None
    return _user_from_cookie(websocket.cookies.get(SESSION_COOKIE), db)


def open_session(db: Session, user: User, ip: str, user_agent: str, hours: int) -> UserSession:
    from toutpanel.security import new_session_id

    now = datetime.utcnow()
    sess = UserSession(user_id=user.id, sid=new_session_id(), ip=ip, user_agent=(user_agent or "")[:250], created_at=now, last_seen=now,
                       expires_at=now + timedelta(hours=hours))
    db.add(sess)
    # ménage : sessions expirées
    db.query(UserSession).filter(UserSession.expires_at < now).delete()
    return sess


def revoke_sessions(db: Session, user_id: int, keep_sid: Optional[str] = None) -> int:
    q = db.query(UserSession).filter(UserSession.user_id == user_id)
    if keep_sid:
        q = q.filter(UserSession.sid != keep_sid)
    return q.delete()


def current_sid(request: Request) -> str:
    data = read_session_token(request.cookies.get(SESSION_COOKIE) or "")
    return str(data.get("n")) if data else ""


def ok(data=None, msg: str = "") -> dict:
    return {"ok": True, "data": data, "msg": msg}


def fail(msg: str, status: int = 400):
    raise HTTPException(status, msg)
