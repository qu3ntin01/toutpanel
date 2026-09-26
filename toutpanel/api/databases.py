from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel.api.deps import current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import Database
from toutpanel.security import generate_password
from toutpanel.services import databases

router = APIRouter(prefix="/api/databases", tags=["databases"], dependencies=[Depends(current_user)])


@router.get("")
def list_databases(db: Session = DbDep):
    rows = db.query(Database).order_by(Database.id.desc()).all()
    return ok({"databases": [r.to_dict(with_password=True) for r in rows], "engines": databases.engines_status()})


class DbIn(BaseModel):
    name: str
    engine: str = "mysql"
    username: str = ""
    password: str = ""
    host: str = "localhost"
    remark: str = ""


@router.post("")
def create(data: DbIn, db: Session = DbDep):
    try:
        row = databases.create_database(db, data.name, data.engine, data.username, data.password, data.host, data.remark)
    except databases.DbError as e:
        fail(str(e))
    return ok(row.to_dict(with_password=True), "Base créée")


@router.delete("/{db_id}")
def delete(db_id: int, drop: bool = True, db: Session = DbDep):
    row = db.get(Database, db_id)
    if not row:
        fail("Introuvable", 404)
    try:
        databases.delete_database(db, row, drop)
    except databases.DbError as e:
        fail(str(e))
    return ok(msg="Base supprimée")


class PasswordIn(BaseModel):
    password: str = ""


@router.post("/{db_id}/password")
def change_password(db_id: int, data: PasswordIn, db: Session = DbDep):
    row = db.get(Database, db_id)
    if not row:
        fail("Introuvable", 404)
    pwd = data.password or generate_password(16)
    try:
        databases.change_password(row, pwd)
    except databases.DbError as e:
        fail(str(e))
    return ok({"password": pwd}, "Mot de passe modifié")


class RootIn(BaseModel):
    engine: str
    host: str = "localhost"
    port: int = 3306
    user: str = "root"
    password: str = ""


@router.get("/root")
def get_root():
    return ok({"mysql": databases.get_root_credentials("mysql"), "postgres": databases.get_root_credentials("postgres")})


@router.post("/root")
def set_root(data: RootIn):
    if data.engine not in ("mysql", "postgres"):
        fail("Moteur invalide")
    databases.set_root_credentials(data.engine, {"host": data.host, "port": data.port, "user": data.user, "password": data.password})
    st = databases.mysql_status() if data.engine == "mysql" else databases.postgres_status()
    return ok(st, "Identifiants enregistrés" + ("" if st.get("ok") else " (connexion impossible : " + st.get("error", "") + ")"))


@router.get("/server/{engine}")
def server_databases(engine: str):
    try:
        if engine == "mysql":
            return ok(databases.mysql_list_databases())
    except databases.DbError as e:
        fail(str(e))
    return ok([])


class ImportIn(BaseModel):
    path: str


@router.post("/{db_id}/import")
def import_sql(db_id: int, data: ImportIn, db: Session = DbDep):
    from pathlib import Path

    row = db.get(Database, db_id)
    if not row:
        fail("Introuvable", 404)
    p = Path(data.path)
    if not p.is_file():
        fail("Fichier introuvable")
    try:
        if row.engine == "mysql":
            databases.mysql_import(row.name, p)
        else:
            fail("Import supporté uniquement pour MySQL pour le moment")
    except databases.DbError as e:
        fail(str(e))
    return ok(msg="Import terminé")
