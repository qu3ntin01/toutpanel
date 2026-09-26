from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel import config, security
from toutpanel.api.deps import client_ip, current_sid, current_user, fail, ok, open_session, revoke_sessions
from toutpanel.db import DbDep
from toutpanel.models import LoginLog, User, UserSession

router = APIRouter(prefix="/api/auth", tags=["auth"])


class LoginIn(BaseModel):
    username: str
    password: str
    code: str = ""


def _secure_cookie(request: Request) -> bool:
    """Cookie « Secure » dès que le panel est servi en HTTPS (directement ou derrière un proxy de confiance)."""
    if request.url.scheme == "https" or config.get_settings().get("panel_ssl"):
        return True
    return request.headers.get("x-forwarded-proto", "").lower() == "https" and client_ip(request) != (request.client.host if request.client else "")


def _log(db: Session, username: str, ip: str, success: bool, detail: str) -> None:
    db.add(LoginLog(username=username[:64], ip=ip, success=success, detail=detail))
    db.flush()
    if db.query(LoginLog).count() > 5500:  # rétention : 5 000 dernières entrées (un balayage d'IP ne remplit pas la base)
        oldest = db.query(LoginLog.id).order_by(LoginLog.id.desc()).offset(5000).limit(1).scalar()
        if oldest:
            db.query(LoginLog).filter(LoginLog.id <= oldest).delete()
    db.commit()


@router.post("/login")
def login(data: LoginIn, request: Request, response: Response, db: Session = DbDep):
    ip = client_ip(request)
    username = data.username.strip()[:64]
    if not security.ip_allowed(ip):
        fail("IP non autorisée", 403)
    if security.limiter.is_locked(ip, username):
        _log(db, username, ip, False, "verrouillé")
        fail("Trop de tentatives, réessayez plus tard", 429)
    user = db.query(User).filter(User.username == username).first()
    if not user:
        security.burn_time()
    if not user or not security.verify_password(data.password, user.password_hash):
        security.limiter.record_failure(ip, username)
        _log(db, username, ip, False, "identifiants invalides")
        fail("Identifiants invalides", 401)
    if user.totp_enabled:
        if not data.code:
            return {"ok": False, "need_totp": True, "msg": "Code 2FA requis"}
        valid, counter = security.verify_totp(user.totp_secret or "", data.code, user.totp_last_used or 0)
        if valid:
            user.totp_last_used = counter
        else:
            remaining = security.use_recovery_code(user.recovery_codes or [], data.code)
            if remaining is None:
                security.limiter.record_failure(ip, username)
                _log(db, username, ip, False, "code 2FA invalide")
                fail("Code 2FA invalide", 401)
            user.recovery_codes = remaining
            _log(db, username, ip, True, f"code de secours utilisé ({len(remaining)} restant(s))")
    security.limiter.reset(ip, username)
    user.last_login = datetime.utcnow()
    hours = int(config.get_settings().get("session_hours", 12))
    sess = open_session(db, user, ip, request.headers.get("user-agent", ""), hours)
    db.commit()
    _log(db, user.username, ip, True, "connexion")
    try:
        from toutpanel.services import notifications

        notifications.notify_login(user.username, ip, request.headers.get("user-agent", ""))
    except Exception:  # noqa: BLE001 — jamais bloquer une connexion pour une alerte
        pass
    token = security.create_session_token(user.id, user.username, sess.sid)
    response.set_cookie(security.SESSION_COOKIE, token, httponly=True, samesite="lax", secure=_secure_cookie(request), max_age=hours * 3600, path="/")
    return ok({"username": user.username, "role": user.role or "admin", "recovery_left": len(user.recovery_codes or []) if user.totp_enabled else None})


@router.post("/logout")
def logout(request: Request, response: Response, db: Session = DbDep):
    sid = current_sid(request)
    if sid:
        db.query(UserSession).filter(UserSession.sid == sid).delete()
    response.delete_cookie(security.SESSION_COOKIE, path="/")
    return ok()


@router.get("/me")
def me(request: Request, user: User = Depends(current_user)):
    return ok({"username": user.username, "role": user.role or "admin", "totp_enabled": user.totp_enabled, "auth": getattr(request.state, "auth", "session")})


# ---------------------------------------------------------------- sessions actives
@router.get("/sessions")
def list_sessions(request: Request, user: User = Depends(current_user), db: Session = DbDep):
    sid = current_sid(request)
    rows = db.query(UserSession).filter(UserSession.user_id == user.id).order_by(UserSession.last_seen.desc()).all()
    out = []
    for r in rows:
        d = r.to_dict()
        d["current"] = r.sid == sid
        d.pop("sid")
        out.append(d)
    return ok(out)


@router.post("/sessions/{sess_id}/revoke")
def revoke_session(sess_id: int, request: Request, user: User = Depends(current_user), db: Session = DbDep):
    r = db.get(UserSession, sess_id)
    if not r or r.user_id != user.id:
        fail("Session introuvable", 404)
    db.delete(r)
    return ok(msg="Session révoquée")


@router.post("/sessions/revoke-others")
def revoke_other_sessions(request: Request, user: User = Depends(current_user), db: Session = DbDep):
    n = revoke_sessions(db, user.id, keep_sid=current_sid(request))
    return ok({"count": n}, f"{n} session(s) déconnectée(s)")
