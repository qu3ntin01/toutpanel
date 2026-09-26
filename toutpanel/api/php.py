from __future__ import annotations
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from toutpanel.api.deps import current_user, fail, ok
from toutpanel.services import php

router = APIRouter(prefix="/api/php", tags=["php"], dependencies=[Depends(current_user)])


@router.get("")
def overview():
    return ok(php.overview())


class InstallIn(BaseModel):
    extensions: Optional[list[str]] = None


@router.post("/{ver}/install")
def install(ver: str, data: InstallIn):
    try:
        tid = php.install(ver, data.extensions)
    except php.PhpError as e:
        fail(str(e))
    return ok({"task_id": tid}, f"Installation de PHP {ver} lancée")


@router.post("/{ver}/remove")
def remove(ver: str):
    try:
        tid = php.remove(ver)
    except php.PhpError as e:
        fail(str(e))
    return ok({"task_id": tid}, f"Suppression de PHP {ver} lancée")


class ActionIn(BaseModel):
    action: str


@router.post("/{ver}/service")
def service(ver: str, data: ActionIn):
    if data.action not in ("start", "stop", "restart", "reload"):
        fail("Action invalide")
    err = php.service_action(ver, data.action)
    if err:
        fail(err)
    return ok(msg=f"PHP-FPM {ver} : {data.action} OK")


@router.get("/{ver}/modules")
def modules(ver: str):
    return ok({"modules": php.modules(ver)})


class ExtIn(BaseModel):
    extensions: list[str]


@router.post("/{ver}/extensions")
def extensions(ver: str, data: ExtIn):
    try:
        tid = php.install_extensions(ver, data.extensions)
    except php.PhpError as e:
        fail(str(e))
    return ok({"task_id": tid}, "Installation des extensions lancée")


@router.get("/{ver}/ini")
def get_ini(ver: str):
    try:
        return ok({"values": php.get_ini(ver), "raw": php.read_ini_raw(ver), "path": php.paths(ver)["ini"], "keys": php.INI_KEYS})
    except php.PhpError as e:
        fail(str(e))


class IniIn(BaseModel):
    values: Optional[dict] = None
    raw: Optional[str] = None


@router.post("/{ver}/ini")
def set_ini(ver: str, data: IniIn):
    try:
        if data.raw is not None:
            php.write_ini_raw(ver, data.raw)
        elif data.values:
            php.set_ini(ver, data.values)
    except php.PhpError as e:
        fail(str(e))
    return ok(msg="php.ini enregistré, PHP-FPM redémarré")


@router.get("/{ver}/pool")
def get_pool(ver: str):
    try:
        return ok({"values": php.get_pool(ver), "raw": php.read_pool_raw(ver), "path": php.paths(ver)["pool"], "keys": php.POOL_KEYS})
    except php.PhpError as e:
        fail(str(e))


@router.post("/{ver}/pool")
def set_pool(ver: str, data: IniIn):
    try:
        if data.raw is not None:
            php.write_pool_raw(ver, data.raw)
        elif data.values:
            php.set_pool(ver, data.values)
    except php.PhpError as e:
        fail(str(e))
    return ok(msg="Pool FPM enregistré, PHP-FPM redémarré")


@router.get("/{ver}/info")
def info(ver: str):
    return ok({"info": php.phpinfo(ver), "test": php.test_config(ver)})


@router.post("/{ver}/default")
def set_default(ver: str):
    err = php.set_default_cli(ver)
    if err:
        fail(err)
    return ok(msg=f"PHP {ver} est maintenant la version CLI par défaut")
