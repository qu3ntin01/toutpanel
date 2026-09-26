"""Gestionnaire de fichiers : navigation, lecture, écriture, archives, permissions."""
from __future__ import annotations

import os
import shutil
import stat
import tarfile
import time
import zipfile
from pathlib import Path

from toutpanel import config

MAX_EDIT_SIZE = 5 * 1024 * 1024
TEXT_EXT = {".txt", ".md", ".html", ".htm", ".css", ".js", ".json", ".py", ".php", ".xml", ".yml", ".yaml", ".ini",
            ".conf", ".cfg", ".env", ".sh", ".ps1", ".bat", ".sql", ".log", ".toml", ".ts", ".vue", ".jsx", ".tsx",
            ".htaccess", ".csv", ".gitignore", ".lock", ".service"}


class FileError(ValueError):
    pass


def _roots() -> list[Path]:
    """Racines autorisées. Par défaut tout le disque (le panel est un outil admin), sauf si restreint."""
    allowed = config.get_settings().get("file_roots") or []
    return [Path(p) for p in allowed]


def _under(p: Path, root: Path) -> bool:
    """p est root ou se trouve sous root (comparaison par composants, pas par préfixe de chaîne)."""
    try:
        p.relative_to(root)
        return True
    except ValueError:
        return False


def _real(p: Path) -> Path:
    """Chemin réel (liens symboliques résolus) ; pour une cible inexistante, résout le parent existant le plus proche."""
    parts = []
    cur = p
    while not cur.exists() and cur != cur.parent:
        parts.append(cur.name)
        cur = cur.parent
    real = Path(os.path.realpath(str(cur)))
    for name in reversed(parts):
        real = real / name
    return real


def protected_paths() -> list[Path]:
    """Jamais accessibles par le gestionnaire de fichiers, quelle que soit la configuration :
    les données du panel (clé de session, base, mots de passe) et ses certificats."""
    out = [config.DATA_DIR, config.SSL_DIR, config.HOME / "toutpanel"]
    if not config.IS_WINDOWS:
        out += [Path("/etc/shadow"), Path("/etc/gshadow"), Path("/etc/sudoers"), Path("/etc/sudoers.d"), Path("/root/.ssh"), Path("/proc"), Path("/sys"), Path("/dev")]
    return out


SYSTEM_DIRS = ("/etc", "/usr", "/bin", "/sbin", "/lib", "/lib64", "/boot", "/proc", "/sys", "/dev", "/var", "/root", "/opt", "/home", "/srv", "/run")


def safe_path(path: str) -> Path:
    if not path:
        path = str(config.WWW_ROOT)
    if "\0" in path:
        raise FileError("Chemin invalide")
    p = Path(path).expanduser()
    if not p.is_absolute():
        p = config.WWW_ROOT / p
    p = Path(os.path.normpath(str(p)))
    real = _real(p)
    for prot in protected_paths():
        if _under(real, _real(prot)) or _under(p, prot):
            raise FileError("Accès refusé : données protégées du panel ou du système")
    roots = _roots()
    if roots and not any(_under(p, r) or _under(real, _real(r)) for r in roots):
        raise FileError("Accès refusé à ce chemin")
    return p


def refuse_destructive(p: Path) -> None:
    """Interdit les opérations destructrices sur la racine du disque, le panel et les répertoires système."""
    real = _real(p)
    if p == Path(p.anchor) or real == Path(real.anchor) or _under(config.HOME, real) or real == _real(config.HOME):
        raise FileError("Opération refusée sur ce chemin")
    if _under(real, _real(config.WWW_ROOT)) and real == _real(config.WWW_ROOT):
        raise FileError("Opération refusée sur la racine des sites")
    if not config.IS_WINDOWS and any(real == Path(d) for d in SYSTEM_DIRS):
        raise FileError("Opération refusée sur un répertoire système")


def _owner(st: os.stat_result) -> str:
    if config.IS_WINDOWS:
        return ""
    try:
        import grp
        import pwd

        return f"{pwd.getpwuid(st.st_uid).pw_name}:{grp.getgrgid(st.st_gid).gr_name}"
    except (KeyError, ImportError):
        return f"{st.st_uid}:{st.st_gid}"


def entry_info(p: Path) -> dict:
    try:
        st = p.lstat()
    except OSError:
        return {"name": p.name, "path": str(p), "type": "unknown", "size": 0, "mtime": 0, "mode": "", "owner": ""}
    is_link = stat.S_ISLNK(st.st_mode)
    is_dir = p.is_dir()
    return {
        "name": p.name, "path": str(p), "type": "dir" if is_dir else ("link" if is_link else "file"),
        "size": 0 if is_dir else st.st_size, "mtime": int(st.st_mtime), "mode": oct(stat.S_IMODE(st.st_mode))[2:].zfill(3),
        "owner": _owner(st), "ext": p.suffix.lower(),
    }


def list_dir(path: str, show_hidden: bool = True) -> dict:
    p = safe_path(path)
    if not p.exists():
        raise FileError("Chemin introuvable")
    if not p.is_dir():
        raise FileError("Pas un répertoire")
    entries = []
    try:
        with os.scandir(p) as it:
            for e in it:
                if not show_hidden and e.name.startswith("."):
                    continue
                entries.append(entry_info(Path(e.path)))
    except PermissionError:
        raise FileError("Permission refusée")
    entries.sort(key=lambda x: (x["type"] != "dir", x["name"].lower()))
    return {"path": str(p), "parent": str(p.parent) if p.parent != p else None, "entries": entries,
            "sep": os.sep}


def read_file(path: str) -> dict:
    p = safe_path(path)
    if not p.is_file():
        raise FileError("Fichier introuvable")
    if p.stat().st_size > MAX_EDIT_SIZE:
        raise FileError("Fichier trop volumineux pour l'éditeur (5 Mo max)")
    data = p.read_bytes()
    try:
        text = data.decode("utf-8")
        encoding = "utf-8"
    except UnicodeDecodeError:
        try:
            text = data.decode("latin-1")
            encoding = "latin-1"
        except UnicodeDecodeError:
            raise FileError("Fichier binaire")
    return {"path": str(p), "content": text, "encoding": encoding, "size": len(data)}


def write_file(path: str, content: str, encoding: str = "utf-8") -> None:
    p = safe_path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "w", encoding=encoding, newline="") as f:  # newline="" : Python 3.9 (write_text(newline=) est 3.10+)
        f.write(content)


def mkdir(path: str, name: str) -> Path:
    if not name or "/" in name or "\\" in name or name in (".", ".."):
        raise FileError("Nom invalide")
    p = safe_path(path) / name
    if p.exists():
        raise FileError("Existe déjà")
    p.mkdir(parents=True)
    return p


def touch(path: str, name: str) -> Path:
    if not name or "/" in name or "\\" in name or name in (".", ".."):
        raise FileError("Nom invalide")
    p = safe_path(path) / name
    if p.exists():
        raise FileError("Existe déjà")
    p.touch()
    return p


def rename(path: str, new_name: str) -> Path:
    if not new_name or "/" in new_name or "\\" in new_name or new_name in (".", ".."):
        raise FileError("Nom invalide")
    p = safe_path(path)
    target = p.parent / new_name
    if target.exists():
        raise FileError("La cible existe déjà")
    p.rename(target)
    return target


def delete(paths: list[str]) -> list[str]:
    errors = []
    for path in paths:
        p = safe_path(path)
        try:
            refuse_destructive(p)
        except FileError as e:
            errors.append(f"{path}: {e}")
            continue
        try:
            if p.is_dir() and not p.is_symlink():
                shutil.rmtree(p)
            else:
                p.unlink()
        except OSError as e:
            errors.append(f"{path}: {e}")
    return errors


def copy_move(sources: list[str], dest_dir: str, move: bool = False) -> list[str]:
    errors = []
    d = safe_path(dest_dir)
    if not d.is_dir():
        raise FileError("Répertoire de destination invalide")
    for s in sources:
        sp = safe_path(s)
        target = d / sp.name
        try:
            if target.exists():
                raise FileError("existe déjà")
            if move:
                shutil.move(str(sp), str(target))
            elif sp.is_dir():
                shutil.copytree(sp, target, symlinks=True)
            else:
                shutil.copy2(sp, target)
        except (OSError, FileError) as e:
            errors.append(f"{s}: {e}")
    return errors


def chmod(path: str, mode: str, recursive: bool = False) -> None:
    if config.IS_WINDOWS:
        raise FileError("chmod non disponible sous Windows")
    p = safe_path(path)
    try:
        m = int(mode, 8)
    except ValueError:
        raise FileError("Mode invalide (octal attendu, ex. 755)")
    if not (0 <= m <= 0o7777):
        raise FileError("Mode invalide")
    if recursive:
        refuse_destructive(p)
    if p.is_symlink():
        raise FileError("chmod refusé sur un lien symbolique")
    p.chmod(m)
    if recursive and p.is_dir():
        for root, dirs, files in os.walk(p):
            for n in dirs + files:
                fp = os.path.join(root, n)
                if os.path.islink(fp):
                    continue  # ne jamais suivre un lien (il pourrait viser /etc/shadow)
                try:
                    os.chmod(fp, m)
                except OSError:
                    pass


def compress(paths: list[str], archive_path: str, fmt: str = "zip") -> Path:
    out = safe_path(archive_path)
    srcs = [safe_path(p) for p in paths]
    if not srcs:
        raise FileError("Aucun fichier")
    base = srcs[0].parent
    if any(s.parent != base for s in srcs):
        raise FileError("Les éléments à compresser doivent être dans le même dossier")
    if fmt == "zip":
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
            for s in srcs:
                if s.is_dir():
                    for root, _, files in os.walk(s):
                        for f in files:
                            fp = Path(root) / f
                            if fp == out or fp.is_symlink() or not fp.is_file():
                                continue
                            zf.write(fp, fp.relative_to(base))
                else:
                    zf.write(s, s.relative_to(base))
    else:
        with tarfile.open(out, "w:gz") as tf:
            for s in srcs:
                tf.add(s, arcname=str(s.relative_to(base)))
    return out


def extract(archive: str, dest_dir: str) -> None:
    a = safe_path(archive)
    d = safe_path(dest_dir)
    d.mkdir(parents=True, exist_ok=True)
    dest = Path(os.path.realpath(str(d)))
    name = a.name.lower()
    if name.endswith(".zip"):
        with zipfile.ZipFile(a) as zf:
            for info in zf.infolist():
                member = info.filename
                if member.startswith(("/", "\\")) or ".." in member.replace("\\", "/").split("/"):
                    raise FileError("Archive dangereuse (chemin hors destination)")
                target = Path(os.path.normpath(str(dest / member)))
                if not _under(target, dest):
                    raise FileError("Archive dangereuse (chemin hors destination)")
                if stat.S_ISLNK((info.external_attr >> 16) & 0o170000):
                    raise FileError("Archive dangereuse (lien symbolique)")
            zf.extractall(dest)
    elif name.endswith((".tar.gz", ".tgz", ".tar", ".tar.bz2", ".tar.xz")):
        with tarfile.open(a) as tf:
            for m in tf.getmembers():
                if m.name.startswith("/") or ".." in m.name.split("/") or m.issym() or m.islnk() or m.isdev():
                    raise FileError("Archive dangereuse (chemin hors destination, lien ou périphérique)")
                target = Path(os.path.normpath(str(dest / m.name)))
                if not _under(target, dest):
                    raise FileError("Archive dangereuse (chemin hors destination)")
            try:
                tf.extractall(dest, filter="data")  # Python ≥ 3.12 : filtre de sécurité intégré
            except TypeError:
                tf.extractall(dest)
    else:
        raise FileError("Format d'archive non pris en charge")


def dir_size(path: str) -> int:
    p = safe_path(path)
    if p.is_file():
        return p.stat().st_size
    total = 0
    for root, _, files in os.walk(p):
        for f in files:
            try:
                total += (Path(root) / f).stat().st_size
            except OSError:
                pass
    return total


def search(path: str, query: str, limit: int = 200) -> list[dict]:
    p = safe_path(path)
    q = query.lower()
    out = []
    t0 = time.time()
    for root, dirs, files in os.walk(p):
        for n in dirs + files:
            if q in n.lower():
                out.append(entry_info(Path(root) / n))
                if len(out) >= limit:
                    return out
        if time.time() - t0 > 20:
            break
    return out
