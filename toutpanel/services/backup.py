"""Sauvegardes de sites, bases de données et répertoires."""
from __future__ import annotations

import os
import zipfile
from datetime import datetime
from pathlib import Path

from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.models import Backup, Database, Site
from toutpanel.services import databases


def _ts() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def _zip_dir(src: Path, out: Path) -> int:
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
        for root, dirs, files in os.walk(src):
            dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
            for f in files:
                fp = Path(root) / f
                if fp == out or fp.is_symlink() or not fp.is_file():
                    continue  # ni liens, ni périphériques/sockets, ni l'archive elle-même
                try:
                    zf.write(fp, fp.relative_to(src))
                except (OSError, ValueError):
                    continue
    config.restrict_file(out)
    return out.stat().st_size


def _out_dir(sub: str) -> Path:
    d = config.BACKUP_DIR / sub
    d.mkdir(parents=True, exist_ok=True)
    if not config.IS_WINDOWS:
        try:
            os.chmod(config.BACKUP_DIR, 0o700)
            os.chmod(d, 0o700)
        except OSError:
            pass
    return d


def _prune(db: Session, kind: str, target: str) -> None:
    keep = int(config.get_settings().get("backup_keep", 5))
    rows = db.query(Backup).filter(Backup.kind == kind, Backup.target == target).order_by(Backup.id.desc()).all()
    for old in rows[keep:]:
        Path(old.path).unlink(missing_ok=True)
        db.delete(old)


def backup_site(db: Session, site_id: int) -> Path:
    site = db.get(Site, site_id)
    if not site:
        raise ValueError("Site introuvable")
    out_dir = _out_dir("sites")
    out = out_dir / f"{site.name}_{_ts()}.zip"
    size = _zip_dir(Path(site.root), out)
    db.add(Backup(kind="site", target=site.name, path=str(out), size=size))
    db.flush()
    _prune(db, "site", site.name)
    return out


def backup_database(db: Session, db_id: int) -> Path:
    row = db.get(Database, db_id)
    if not row:
        raise ValueError("Base introuvable")
    out_dir = _out_dir("databases")
    ext = ".db" if row.engine == "sqlite" else ".sql"
    tmp = out_dir / f"{row.name}_{_ts()}{ext}"
    databases.dump_database(row, tmp)
    out = tmp.with_suffix(tmp.suffix + ".zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(tmp, tmp.name)
    tmp.unlink(missing_ok=True)
    config.restrict_file(out)
    db.add(Backup(kind="database", target=row.name, path=str(out), size=out.stat().st_size))
    db.flush()
    _prune(db, "database", row.name)
    return out


def backup_path(db: Session, path: str) -> Path:
    from toutpanel.services import files

    try:
        src = files.safe_path(path)  # mêmes interdits que le gestionnaire de fichiers (données du panel, /proc…)
    except files.FileError as e:
        raise ValueError(str(e))
    if src == Path(src.anchor):
        raise ValueError("Sauvegarde de la racine du disque refusée : choisissez un répertoire")
    if not src.exists():
        raise ValueError("Chemin introuvable")
    out_dir = _out_dir("paths")
    out = out_dir / f"{src.name or 'root'}_{_ts()}.zip"
    if src.is_dir():
        size = _zip_dir(src, out)
    else:
        if src.is_symlink() or not src.is_file():
            raise ValueError("Seuls les fichiers réguliers et les dossiers peuvent être sauvegardés")
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.write(src, src.name)
        config.restrict_file(out)
        size = out.stat().st_size
    db.add(Backup(kind="path", target=str(src), path=str(out), size=size))
    db.flush()
    _prune(db, "path", str(src))
    return out


def delete_backup(db: Session, row: Backup) -> None:
    Path(row.path).unlink(missing_ok=True)
    db.delete(row)
    db.flush()


def restore_site(db: Session, row: Backup) -> str:
    site = db.query(Site).filter(Site.name == row.target).first()
    if not site:
        raise ValueError("Site introuvable")
    from toutpanel.services import files

    files.extract(row.path, site.root)
    return site.root
