from __future__ import annotations
from typing import Optional

import re

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session

import platform

from toutpanel import __version__, config, security
from toutpanel.services.system_info import _local_ip
from toutpanel.api.deps import current_sid, current_user, fail, ok, revoke_sessions
from toutpanel.db import DbDep
from toutpanel.models import ApiToken, AuditLog, LoginLog, User, UserSession

router = APIRouter(prefix="/api/settings", tags=["settings"])


@router.get("")
def get_settings(user: User = Depends(current_user), db: Session = DbDep):
    s = config.get_settings()
    d = s.as_dict()
    d.pop("mysql_root", None)
    d.pop("postgres_root", None)
    d["username"] = user.username
    d["totp_enabled"] = user.totp_enabled
    d["home"] = str(config.HOME)
    d["www_root"] = str(config.WWW_ROOT)
    d["memo"] = s.get("memo", "")
    d["panel_url"] = panel_url()
    d["ip"] = _local_ip()
    d["data_dir"] = str(config.DATA_DIR)
    d["log_dir"] = str(config.LOG_DIR)
    d["backup_dir"] = str(config.BACKUP_DIR)
    d["version"] = __version__
    d["python"] = platform.python_version()
    d["users_count"] = db.query(User).count()
    return ok(d)


def panel_url(host: Optional[str] = None) -> str:
    """URL complète d'accès au panel (schéma, IP, port, entrée sécurisée)."""
    s = config.get_settings()
    scheme = "https" if s.get("panel_ssl") else "http"
    return f"{scheme}://{host or _local_ip()}:{s.get('panel_port')}{s.get('security_entrance') or ''}"


class SettingsIn(BaseModel):
    panel_port: Optional[int] = None
    panel_host: Optional[str] = None
    panel_ssl: Optional[bool] = None
    security_entrance: Optional[str] = None
    session_hours: Optional[int] = None
    language: Optional[str] = None
    ip_whitelist: Optional[list[str]] = None
    trusted_proxies: Optional[list[str]] = None
    max_login_attempts: Optional[int] = None
    lockout_minutes: Optional[int] = None
    webserver: Optional[str] = None
    backup_keep: Optional[int] = None
    monitor_enabled: Optional[bool] = None
    monitor_interval: Optional[int] = None
    monitor_retention_days: Optional[int] = None
    panel_name: Optional[str] = None
    memo: Optional[str] = None
    file_roots: Optional[list[str]] = None
    ftp_port: Optional[int] = None
    ftp_passive_ports: Optional[str] = None
    panel_cert_site: Optional[str] = None


@router.post("")
def update_settings(data: SettingsIn, user: User = Depends(current_user), db: Session = DbDep):
    values = data.model_dump(exclude_unset=True)
    restart = False
    if "panel_port" in values and not (1 <= int(values["panel_port"]) <= 65535):
        fail("Port invalide")
    if "security_entrance" in values:
        e = (values["security_entrance"] or "").strip()
        if e and not re.fullmatch(r"/[a-zA-Z0-9_-]{4,64}", e):
            fail("L'entrée sécurisée doit être de la forme /mot (4 à 64 caractères)")
        values["security_entrance"] = e
    if "webserver" in values and values["webserver"] not in ("auto", "nginx", "apache", "iis"):
        fail("Serveur web invalide")
    if "language" in values and values["language"] not in config.LANGUAGES:
        fail("Langue invalide")
    if "ip_whitelist" in values:
        values["ip_whitelist"] = [x.strip() for x in values["ip_whitelist"] if x.strip()]
    if "trusted_proxies" in values:
        values["trusted_proxies"] = [x.strip() for x in values["trusted_proxies"] if x.strip()]
    if "panel_cert_site" in values:
        from toutpanel.models import Site

        name = (values["panel_cert_site"] or "").strip()
        if name:
            site = db.query(Site).filter(Site.name == name).first()
            if not site or not site.ssl_enabled or not site.ssl_cert:
                fail("Ce site n'a pas de certificat actif")
        values["panel_cert_site"] = name
        restart = True
    if "session_hours" in values and not (1 <= int(values["session_hours"]) <= 720):
        fail("Durée de session invalide (1 à 720 h)")
    if "ftp_port" in values and not (1 <= int(values["ftp_port"]) <= 65535):
        fail("Port FTP invalide")
    if "ftp_passive_ports" in values and not re.fullmatch(r"\d{2,5}-\d{2,5}", str(values["ftp_passive_ports"]).strip()):
        fail("Plage de ports passifs invalide (ex : 60000-60100)")
    if "monitor_interval" in values and not (5 <= int(values["monitor_interval"]) <= 3600):
        fail("Intervalle de monitoring invalide (5 à 3600 s)")
    config.get_settings().update(values)
    restart = restart or any(k in values for k in ("panel_port", "panel_host", "panel_ssl"))
    return ok({"restart_required": restart}, "Paramètres enregistrés" + (" (redémarrage du panel nécessaire)" if restart else ""))


class AccountIn(BaseModel):
    username: Optional[str] = None
    current_password: str
    new_password: Optional[str] = None


@router.post("/account")
def update_account(data: AccountIn, request: Request, user: User = Depends(current_user), db: Session = DbDep):
    u = db.get(User, user.id)
    if not security.verify_password(data.current_password, u.password_hash):
        fail("Mot de passe actuel incorrect", 403)
    if data.username:
        if not re.fullmatch(r"[a-zA-Z0-9_.-]{3,32}", data.username):
            fail("Nom d'utilisateur invalide")
        if data.username != u.username and db.query(User).filter(User.username == data.username).first():
            fail("Ce nom d'utilisateur est déjà pris")
        u.username = data.username
    msg = "Compte mis à jour"
    if data.new_password:
        err = security.password_policy(data.new_password, u.username)
        if err:
            fail(err)
        u.password_hash = security.hash_password(data.new_password)
        (config.DATA_DIR / "initial_password.txt").unlink(missing_ok=True)
        n = revoke_sessions(db, u.id, keep_sid=current_sid(request))  # les autres sessions ne survivent pas au changement
        msg += f" — {n} autre(s) session(s) déconnectée(s)" if n else ""
    return ok(msg=msg)


# ---------------------------------------------------------------- utilisateurs
@router.get("/users")
def list_users(user: User = Depends(current_user), db: Session = DbDep):
    rows = db.query(User).order_by(User.id).all()
    return ok([{"id": u.id, "username": u.username, "role": u.role or "admin", "totp_enabled": u.totp_enabled, "last_login": u.last_login.isoformat() if u.last_login else None,
                "created_at": u.created_at.isoformat() if u.created_at else None, "is_me": u.id == user.id} for u in rows])


class UserIn(BaseModel):
    username: str
    password: str
    current_password: str
    role: str = "admin"


class RoleIn(BaseModel):
    role: str
    current_password: str


@router.post("/users/{uid}/role")
def set_role(uid: int, data: RoleIn, user: User = Depends(current_user), db: Session = DbDep):
    _check_me(db, user, data.current_password)
    if data.role not in ("admin", "viewer"):
        fail("Rôle invalide")
    u = db.get(User, uid)
    if not u:
        fail("Introuvable", 404)
    if u.id == user.id and data.role != "admin":
        fail("Vous ne pouvez pas retirer vos propres droits")
    if data.role == "viewer" and db.query(User).filter(User.role == "admin", User.id != u.id).count() == 0:
        fail("Il faut conserver au moins un administrateur")
    u.role = data.role
    revoke_sessions(db, u.id)  # les droits changent : les sessions ouvertes sont fermées
    return ok(msg="Rôle mis à jour, sessions de l'utilisateur fermées")


def _check_me(db: Session, user: User, current_password: str) -> None:
    me_ = db.get(User, user.id)
    if not security.verify_password(current_password, me_.password_hash):
        fail("Mot de passe actuel incorrect", 403)


@router.post("/users")
def create_user(data: UserIn, user: User = Depends(current_user), db: Session = DbDep):
    _check_me(db, user, data.current_password)
    if not re.fullmatch(r"[a-zA-Z0-9_.-]{3,32}", data.username):
        fail("Nom d'utilisateur invalide")
    err = security.password_policy(data.password, data.username)
    if err:
        fail(err)
    if db.query(User).filter(User.username == data.username).first():
        fail("Cet utilisateur existe déjà")
    if data.role not in ("admin", "viewer"):
        fail("Rôle invalide")
    db.add(User(username=data.username, password_hash=security.hash_password(data.password), role=data.role))
    return ok(msg="Utilisateur créé")


class UserPasswordIn(BaseModel):
    password: str
    current_password: str


@router.post("/users/{uid}/password")
def reset_user_password(uid: int, data: UserPasswordIn, user: User = Depends(current_user), db: Session = DbDep):
    _check_me(db, user, data.current_password)
    u = db.get(User, uid)
    if not u:
        fail("Introuvable", 404)
    err = security.password_policy(data.password, u.username)
    if err:
        fail(err)
    u.password_hash = security.hash_password(data.password)
    revoke_sessions(db, u.id)
    db.query(ApiToken).filter(ApiToken.user_id == u.id).delete()
    return ok(msg="Mot de passe réinitialisé, sessions et jetons de cet utilisateur révoqués")


class ConfirmIn(BaseModel):
    current_password: str


@router.post("/users/{uid}/totp/reset")
def reset_user_totp(uid: int, data: ConfirmIn, user: User = Depends(current_user), db: Session = DbDep):
    _check_me(db, user, data.current_password)
    u = db.get(User, uid)
    if not u:
        fail("Introuvable", 404)
    u.totp_enabled = False
    u.totp_secret = None
    u.recovery_codes = []
    revoke_sessions(db, u.id)
    return ok(msg="2FA désactivée pour cet utilisateur, ses sessions sont fermées")


@router.post("/users/{uid}/delete")
def delete_user(uid: int, data: ConfirmIn, user: User = Depends(current_user), db: Session = DbDep):
    _check_me(db, user, data.current_password)
    u = db.get(User, uid)
    if not u:
        fail("Introuvable", 404)
    if u.id == user.id:
        fail("Vous ne pouvez pas supprimer votre propre compte")
    if db.query(User).count() <= 1:
        fail("Impossible de supprimer le dernier utilisateur")
    revoke_sessions(db, u.id)
    db.query(ApiToken).filter(ApiToken.user_id == u.id).delete()
    db.delete(u)
    return ok(msg="Utilisateur supprimé")


@router.get("/export")
def export_settings(user: User = Depends(current_user)):
    """Export de settings.json sans les secrets (clé de session, identifiants root)."""
    from fastapi.responses import Response
    import json

    d = config.get_settings().as_dict()
    for k in ("secret_key", "mysql_root", "postgres_root"):
        d.pop(k, None)
    body = json.dumps(d, indent=2, ensure_ascii=False)
    return Response(body, media_type="application/json", headers={"Content-Disposition": 'attachment; filename="toutpanel-settings.json"'})


class ImportIn(BaseModel):
    values: dict


@router.post("/import")
def import_settings(data: ImportIn, user: User = Depends(current_user)):
    allowed = set(SettingsIn.model_fields) | {"ftp_enabled", "www_root", "backup_dir", "accent_color", "logo_letter", "logo_url", "default_theme", "default_contrast",
                                              "custom_css", "footer_text", "custom_links", "sidebar_compact", "show_version"}
    values = {k: v for k, v in data.values.items() if k in allowed}
    if not values:
        fail("Aucun paramètre reconnu dans le fichier")
    config.get_settings().update(values)
    return ok({"count": len(values)}, f"{len(values)} paramètre(s) importé(s) — redémarrez le panel si le port ou l'adresse ont changé")


@router.post("/totp/setup")
def totp_setup(user: User = Depends(current_user), db: Session = DbDep):
    u = db.get(User, user.id)
    secret = security.new_totp_secret()
    u.totp_secret = secret
    u.totp_enabled = False
    return ok({"secret": secret, "uri": security.totp_uri(secret, u.username)})


class TotpIn(BaseModel):
    code: str


@router.post("/totp/enable")
def totp_enable(data: TotpIn, user: User = Depends(current_user), db: Session = DbDep):
    u = db.get(User, user.id)
    valid, counter = security.verify_totp(u.totp_secret or "", data.code)
    if not u.totp_secret or not valid:
        fail("Code invalide")
    u.totp_enabled = True
    u.totp_last_used = counter
    codes, hashes = security.new_recovery_codes()
    u.recovery_codes = hashes
    return ok({"recovery_codes": codes}, "Double authentification activée — conservez vos codes de secours, ils ne seront plus affichés")


@router.post("/totp/disable")
def totp_disable(data: TotpIn, user: User = Depends(current_user), db: Session = DbDep):
    u = db.get(User, user.id)
    valid, _ = security.verify_totp(u.totp_secret or "", data.code, u.totp_last_used or 0)
    if not valid and security.use_recovery_code(u.recovery_codes or [], data.code) is None:
        fail("Code invalide")
    u.totp_enabled = False
    u.totp_secret = None
    u.recovery_codes = []
    return ok(msg="Double authentification désactivée")


@router.post("/totp/recovery")
def totp_recovery(data: ConfirmIn, user: User = Depends(current_user), db: Session = DbDep):
    """Régénère les codes de secours 2FA (mot de passe actuel requis)."""
    u = db.get(User, user.id)
    if not security.verify_password(data.current_password, u.password_hash):
        fail("Mot de passe actuel incorrect", 403)
    if not u.totp_enabled:
        fail("La double authentification n'est pas activée")
    codes, hashes = security.new_recovery_codes()
    u.recovery_codes = hashes
    return ok({"recovery_codes": codes}, "Nouveaux codes de secours générés — les anciens ne fonctionnent plus")


# ---------------------------------------------------------------- jetons d'API
@router.get("/tokens")
def list_tokens(user: User = Depends(current_user), db: Session = DbDep):
    return ok([t.to_dict() for t in db.query(ApiToken).filter(ApiToken.user_id == user.id).order_by(ApiToken.id).all()])


class TokenIn(BaseModel):
    name: str
    expires_days: int = 0
    current_password: str


@router.post("/tokens")
def create_token(data: TokenIn, user: User = Depends(current_user), db: Session = DbDep):
    from datetime import datetime, timedelta

    _check_me(db, user, data.current_password)
    name = data.name.strip()[:64]
    if not name:
        fail("Nom requis")
    if not (0 <= data.expires_days <= 3650):
        fail("Durée invalide (0 = sans expiration, jusqu'à 3650 jours)")
    if db.query(ApiToken).filter(ApiToken.user_id == user.id).count() >= 20:
        fail("20 jetons maximum par utilisateur")
    raw, prefix, h = security.new_api_token()
    tok = ApiToken(user_id=user.id, name=name, prefix=prefix, token_hash=h,
                   expires_at=(datetime.utcnow() + timedelta(days=data.expires_days)) if data.expires_days else None)
    db.add(tok)
    db.flush()
    return ok({"token": raw, "id": tok.id, "prefix": prefix},
              "Jeton créé — copiez-le maintenant, il ne sera plus affiché. Utilisation : en-tête Authorization: Bearer <jeton>")


@router.delete("/tokens/{tid}")
def delete_token(tid: int, user: User = Depends(current_user), db: Session = DbDep):
    t = db.get(ApiToken, tid)
    if not t or t.user_id != user.id:
        fail("Jeton introuvable", 404)
    db.delete(t)
    return ok(msg="Jeton révoqué")


# ---------------------------------------------------------------- audit
@router.get("/audit")
def audit_log(limit: int = 200, q: str = "", user: User = Depends(current_user), db: Session = DbDep):
    limit = max(1, min(int(limit), 1000))
    query = db.query(AuditLog)
    if q:
        like = f"%{q[:64]}%"
        query = query.filter((AuditLog.path.like(like)) | (AuditLog.username.like(like)) | (AuditLog.ip.like(like)))
    rows = query.order_by(AuditLog.id.desc()).limit(limit).all()
    logins = db.query(LoginLog).order_by(LoginLog.id.desc()).limit(50).all()
    return ok({"actions": [r.to_dict() for r in rows], "logins": [x.to_dict() for x in logins], "sessions_total": db.query(UserSession).count()})


@router.post("/restart")
def restart_panel(user: User = Depends(current_user)):
    import os
    import signal
    import threading

    def _kill():
        import sys
        import time

        time.sleep(0.5)
        if os.environ.get("INVOCATION_ID") or config.IS_WINDOWS:  # systemd (ou service Windows) relance le processus
            os.kill(os.getpid(), signal.SIGTERM if hasattr(signal, "SIGTERM") else signal.SIGINT)
            return
        # lancé à la main (toutpanel start / run) : on remplace le processus par une nouvelle instance
        try:
            os.execv(sys.executable, [sys.executable, "-m", "toutpanel", "run"])
        except OSError:
            os.kill(os.getpid(), signal.SIGTERM)

    threading.Thread(target=_kill, daemon=True).start()
    return ok(msg="Redémarrage du panel…")


@router.get("/totp/qr.svg")
def totp_qr(user: User = Depends(current_user), db: Session = DbDep):
    from fastapi.responses import Response

    import qrcode
    import qrcode.image.svg

    u = db.get(User, user.id)
    if not u.totp_secret:
        fail("Aucun secret 2FA en attente", 404)
    img = qrcode.make(security.totp_uri(u.totp_secret, u.username), image_factory=qrcode.image.svg.SvgPathImage, box_size=8, border=2)
    import io

    buf = io.BytesIO()
    img.save(buf)
    return Response(buf.getvalue(), media_type="image/svg+xml", headers={"Cache-Control": "no-store"})


# ---------------------------------------------------------------- notifications
@router.get("/notifications")
def get_notifications(user: User = Depends(current_user)):
    from toutpanel.services import notifications

    st = notifications.settings()
    st["notify_smtp_password_set"] = bool(st.pop("notify_smtp_password", ""))
    st["notify_telegram_token_set"] = bool(st.get("notify_telegram_token"))
    st["notify_telegram_token"] = ""
    st["channels"] = notifications.channels()
    st["events"] = notifications.EVENT_LABELS
    return ok(st)


class NotificationsIn(BaseModel):
    values: dict


@router.post("/notifications")
def set_notifications(data: NotificationsIn, user: User = Depends(current_user)):
    from toutpanel.services import notifications

    values = {}
    for k, v in data.values.items():
        if k not in notifications.DEFAULTS and k != "notify_services":
            continue
        if k in ("notify_smtp_password", "notify_telegram_token") and not v:
            continue  # secret conservé si vide
        if k == "notify_email" and v and not re.fullmatch(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", str(v)):
            fail("Adresse e-mail invalide")
        if k == "notify_webhook_url" and v and not re.match(r"^https?://", str(v)):
            fail("URL de webhook invalide")
        if k == "notify_smtp_port" and not (1 <= int(v or 25) <= 65535):
            fail("Port SMTP invalide")
        if k == "notify_disk_threshold" and not (50 <= int(v or 90) <= 99):
            fail("Seuil disque invalide (50 à 99 %)")
        if k == "notify_interval_min" and not (1 <= int(v or 15) <= 1440):
            fail("Intervalle invalide (1 à 1440 min)")
        values[k] = v
    config.get_settings().update(values)
    try:
        notifications.start()
    except Exception:  # noqa: BLE001
        pass
    return ok(notifications.channels(), "Alertes enregistrées")


@router.post("/notifications/test")
def test_notifications(user: User = Depends(current_user)):
    from toutpanel.services import notifications

    if not notifications.channels():
        fail("Aucun canal configuré (e-mail, webhook ou Telegram)")
    errors = notifications.send("test", "test des alertes", f"Message de test envoyé par {user.username}. Les alertes fonctionnent.", force=True)
    if errors:
        fail(" ; ".join(errors))
    return ok(msg="Message de test envoyé sur : " + ", ".join(notifications.channels()))


@router.post("/notifications/check")
def run_checks(user: User = Depends(current_user)):
    from toutpanel.services import notifications

    return ok(notifications.check_all(), "Vérifications effectuées")


# ---------------------------------------------------------------- mise à jour du panel
@router.get("/update")
def update_check(user: User = Depends(current_user)):
    from toutpanel.services import software

    return ok(software.check_update())


@router.post("/update")
def update_run(user: User = Depends(current_user)):
    from toutpanel.services import software

    if not software.panel_source_dir():
        fail("Dépôt du panel introuvable : mettez à jour avec install.sh")
    return ok({"task_id": software.update_panel()}, "Mise à jour lancée — le panel redémarre à la fin")
