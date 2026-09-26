from __future__ import annotations

import mimetypes
import os
import tarfile
import zipfile
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

from toutpanel.api.deps import current_user, fail, ok
from toutpanel.services import files

router = APIRouter(prefix="/api/files", tags=["files"], dependencies=[Depends(current_user)])


def _guard(fn, *a, **kw):
    try:
        return fn(*a, **kw)
    except files.FileError as e:
        fail(str(e))
    except PermissionError:
        fail("Permission refusée", 403)
    except FileNotFoundError:
        fail("Introuvable", 404)
    except OSError as e:
        fail(str(e))
    except (ValueError, LookupError) as e:
        fail(f"Requête invalide : {e}")
    except (zipfile.BadZipFile, tarfile.TarError) as e:
        fail(f"Archive illisible : {e}")


@router.get("/list")
def list_dir(path: str = "", hidden: bool = True):
    return ok(_guard(files.list_dir, path, hidden))


@router.get("/read")
def read(path: str):
    return ok(_guard(files.read_file, path))


class WriteIn(BaseModel):
    path: str
    content: str
    encoding: str = "utf-8"


@router.post("/write")
def write(data: WriteIn):
    _guard(files.write_file, data.path, data.content, data.encoding)
    return ok(msg="Enregistré")


class NameIn(BaseModel):
    path: str
    name: str


@router.post("/mkdir")
def mkdir(data: NameIn):
    return ok(str(_guard(files.mkdir, data.path, data.name)), "Dossier créé")


@router.post("/touch")
def touch(data: NameIn):
    return ok(str(_guard(files.touch, data.path, data.name)), "Fichier créé")


@router.post("/rename")
def rename(data: NameIn):
    return ok(str(_guard(files.rename, data.path, data.name)), "Renommé")


class PathsIn(BaseModel):
    paths: list[str]


@router.post("/delete")
def delete(data: PathsIn):
    errors = _guard(files.delete, data.paths)
    if errors:
        fail("; ".join(errors))
    return ok(msg="Supprimé")


class CopyIn(BaseModel):
    paths: list[str]
    dest: str
    move: bool = False


@router.post("/copy")
def copy(data: CopyIn):
    errors = _guard(files.copy_move, data.paths, data.dest, data.move)
    if errors:
        fail("; ".join(errors))
    return ok(msg="Déplacé" if data.move else "Copié")


class ChmodIn(BaseModel):
    path: str
    mode: str
    recursive: bool = False


@router.post("/chmod")
def chmod(data: ChmodIn):
    try:
        int(data.mode, 8)
    except ValueError:
        fail("Mode invalide")
    _guard(files.chmod, data.path, data.mode, data.recursive)
    return ok(msg="Permissions modifiées")


class CompressIn(BaseModel):
    paths: list[str]
    archive: str
    fmt: str = "zip"


@router.post("/compress")
def compress(data: CompressIn):
    return ok(str(_guard(files.compress, data.paths, data.archive, data.fmt)), "Archive créée")


class ExtractIn(BaseModel):
    archive: str
    dest: str


@router.post("/extract")
def extract(data: ExtractIn):
    _guard(files.extract, data.archive, data.dest)
    return ok(msg="Archive extraite")


@router.get("/size")
def size(path: str):
    return ok({"size": _guard(files.dir_size, path)})


@router.get("/search")
def search(path: str, q: str):
    return ok(_guard(files.search, path, q))


@router.post("/upload")
async def upload(path: str = Form(...), file: UploadFile = File(...), overwrite: bool = Form(False)):
    from toutpanel import config

    dest = _guard(files.safe_path, path)
    if not dest.is_dir():
        fail("Répertoire invalide")
    name = Path((file.filename or "upload").replace("\\", "/")).name
    if name in ("", ".", "..") or "\0" in name:
        fail("Nom de fichier invalide")
    target = _guard(files.safe_path, str(dest / name))
    if target.exists() and not overwrite:
        fail("Le fichier existe déjà (cochez « remplacer » pour l'écraser)", 409)
    max_bytes = int(config.get_settings().get("max_upload_mb", 2048)) * 1024 * 1024
    tmp = dest / (".upload-" + name + ".part")
    written = 0
    try:
        with open(tmp, "wb") as f:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                written += len(chunk)
                if written > max_bytes:
                    raise ValueError("Fichier trop volumineux")
                f.write(chunk)
        os.replace(tmp, target)
    except ValueError as e:
        tmp.unlink(missing_ok=True)
        fail(str(e), 413)
    except OSError as e:
        tmp.unlink(missing_ok=True)
        fail(str(e))
    return ok(str(target), "Fichier envoyé")


@router.get("/download")
def download(path: str):
    p = _guard(files.safe_path, path)
    if not p.is_file():
        fail("Fichier introuvable", 404)
    mt, _ = mimetypes.guess_type(str(p))
    return FileResponse(str(p), filename=p.name, media_type=mt or "application/octet-stream")
