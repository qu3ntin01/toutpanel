from __future__ import annotations

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.api.deps import current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import Backup
from toutpanel.services import backup, tasks

router = APIRouter(prefix="/api/backups", tags=["backups"], dependencies=[Depends(current_user)])


@router.get("")
def list_backups(db: Session = DbDep):
    return ok({"backups": [b.to_dict() for b in db.query(Backup).order_by(Backup.id.desc()).all()],
               "dir": str(config.BACKUP_DIR), "keep": config.get_settings().get("backup_keep")})


class BackupIn(BaseModel):
    kind: str  # site | database | path
    target: str


@router.post("")
def create(data: BackupIn):
    from pathlib import Path

    from toutpanel.db import session_scope
    from toutpanel.services import files

    if data.kind == "path":
        try:
            src = files.safe_path(data.target)  # données du panel, /proc… refusés avant même de lancer la tâche
        except files.FileError as e:
            fail(str(e))
        if src == Path(src.anchor):
            fail("Sauvegarde de la racine du disque refusée : choisissez un répertoire")
        if not src.exists():
            fail("Chemin introuvable", 404)
    elif data.kind not in ("site", "database"):
        fail("Type de sauvegarde invalide")

    def _job(log):
        with session_scope() as db:
            if data.kind == "site":
                p = backup.backup_site(db, int(data.target))
            elif data.kind == "database":
                p = backup.backup_database(db, int(data.target))
            elif data.kind == "path":
                p = backup.backup_path(db, data.target)
            else:
                log("type invalide")
                return 1
        log(f"Sauvegarde créée : {p}")
        return 0

    tid = tasks.run_in_background(f"Sauvegarde {data.kind} {data.target}", _job)
    return ok({"task_id": tid}, "Sauvegarde lancée")


@router.delete("/{bid}")
def delete(bid: int, db: Session = DbDep):
    b = db.get(Backup, bid)
    if not b:
        fail("Introuvable", 404)
    backup.delete_backup(db, b)
    return ok(msg="Sauvegarde supprimée")


@router.get("/{bid}/download")
def download(bid: int, db: Session = DbDep):
    from pathlib import Path

    b = db.get(Backup, bid)
    if not b or not Path(b.path).is_file():
        fail("Introuvable", 404)
    return FileResponse(b.path, filename=Path(b.path).name)


@router.post("/{bid}/restore")
def restore(bid: int, db: Session = DbDep):
    b = db.get(Backup, bid)
    if not b:
        fail("Introuvable", 404)
    if b.kind != "site":
        fail("Restauration disponible pour les sites uniquement (importez le .sql via Bases de données)")
    try:
        root = backup.restore_site(db, b)
    except ValueError as e:
        fail(str(e))
    return ok(msg=f"Restauré dans {root}")
