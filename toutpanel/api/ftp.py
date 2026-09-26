from __future__ import annotations
from typing import Optional

from pathlib import Path

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.api.deps import current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import FtpUser
from toutpanel.security import hash_password
from toutpanel.services import ftp

router = APIRouter(prefix="/api/ftp", tags=["ftp"], dependencies=[Depends(current_user)])


@router.get("")
def list_users(db: Session = DbDep):
    s = config.get_settings()
    return ok({"users": [u.to_dict() for u in db.query(FtpUser).order_by(FtpUser.id.desc()).all()],
               "running": ftp.is_running(), "port": s.get("ftp_port"), "passive_ports": s.get("ftp_passive_ports"),
               "enabled": s.get("ftp_enabled")})


class FtpIn(BaseModel):
    username: str
    password: str
    home: str = ""
    perm: str = "elradfmwMT"


@router.post("")
def create(data: FtpIn, db: Session = DbDep):
    home = data.home or str(config.WWW_ROOT / data.username)
    try:
        u = ftp.create_user(db, data.username, data.password, home, data.perm)
    except ValueError as e:
        fail(str(e))
    return ok(u.to_dict(), "Utilisateur FTP créé")


class FtpUpdate(BaseModel):
    password: Optional[str] = None
    home: Optional[str] = None
    perm: Optional[str] = None
    enabled: Optional[bool] = None


@router.put("/{uid}")
def update(uid: int, data: FtpUpdate, db: Session = DbDep):
    u = db.get(FtpUser, uid)
    if not u:
        fail("Introuvable", 404)
    if data.password:
        if len(data.password) < 6:
            fail("Mot de passe trop court")
        u.password = hash_password(data.password)
    if data.home:
        Path(data.home).mkdir(parents=True, exist_ok=True)
        u.home = data.home
    if data.perm is not None:
        u.perm = data.perm
    if data.enabled is not None:
        u.enabled = data.enabled
    return ok(u.to_dict(), "Utilisateur mis à jour")


@router.delete("/{uid}")
def delete(uid: int, db: Session = DbDep):
    u = db.get(FtpUser, uid)
    if not u:
        fail("Introuvable", 404)
    db.delete(u)
    return ok(msg="Utilisateur supprimé")


class ServerIn(BaseModel):
    action: str  # start | stop | restart
    port: Optional[int] = None
    passive_ports: Optional[str] = None


@router.post("/server")
def server(data: ServerIn):
    s = config.get_settings()
    if data.port:
        s.set("ftp_port", int(data.port))
    if data.passive_ports:
        s.set("ftp_passive_ports", data.passive_ports)
    if data.action == "start":
        err = ftp.start()
        s.set("ftp_enabled", True)
    elif data.action == "stop":
        ftp.stop()
        err = ""
        s.set("ftp_enabled", False)
    elif data.action == "restart":
        err = ftp.restart()
    else:
        fail("Action invalide")
    if err and err != "déjà démarré":
        fail(err)
    return ok({"running": ftp.is_running()}, "Serveur FTP : " + data.action)
