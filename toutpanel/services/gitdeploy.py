"""Déploiement Git des sites : clone / mise à jour depuis un dépôt (HTTPS avec jeton ou SSH avec clé générée par le panel),
actualisation automatique toutes les X minutes, webhook, commande post-déploiement, historique.

Sécurité : les identifiants ne passent jamais sur la ligne de commande (variables d'environnement GIT_CONFIG_* et
GIT_SSH_COMMAND), la clé privée n'est lisible que par le panel, les hôtes SSH sont mémorisés dans un known_hosts dédié."""
from __future__ import annotations

import base64
import hashlib
import hmac
import logging
import os
import re
import secrets
import shlex
import socket
import threading
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional

from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.db import session_scope
from toutpanel.models import GitDeploy, Site
from toutpanel.platform import get_platform

log = logging.getLogger("toutpanel.git")

REPO_RE = re.compile(r"^(https?://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+|git@[A-Za-z0-9._-]+:[A-Za-z0-9._/~-]+|ssh://[A-Za-z0-9._~:/@-]+|file:///[A-Za-z0-9._/~-]+)$")
BRANCH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$")
KEY_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
AUTO_CHOICES = (0, 1, 5, 15, 30, 60, 180, 360, 720, 1440)
_locks: dict[int, threading.Lock] = {}
_locks_guard = threading.Lock()


class GitError(ValueError):
    pass


# --------------------------------------------------------------------------- clés SSH

def git_dir() -> Path:
    d = config.DATA_DIR / "git"
    d.mkdir(parents=True, exist_ok=True)
    (d / "keys").mkdir(exist_ok=True)
    if not config.IS_WINDOWS:
        for p in (d, d / "keys"):
            try:
                os.chmod(p, 0o700)
            except OSError:
                pass
    return d


def key_paths(name: str = "") -> tuple[Path, Path]:
    name = name or "deploy"
    if not KEY_RE.match(name):
        raise GitError("Nom de clé invalide")
    priv = git_dir() / "keys" / f"{name}.ed25519"
    return priv, priv.with_suffix(".ed25519.pub")


def public_key(name: str = "") -> str:
    _, pub = key_paths(name)
    return pub.read_text(encoding="utf-8").strip() if pub.exists() else ""


def generate_key(name: str = "", force: bool = False) -> str:
    """Génère une paire de clés ed25519 sans phrase de passe et retourne la clé publique à déclarer chez GitHub / GitLab."""
    plat = get_platform()
    priv, pub = key_paths(name)
    if priv.exists() and not force:
        return public_key(name)
    exe = plat.which("ssh-keygen")
    if not exe:
        raise GitError("ssh-keygen introuvable : installez le client OpenSSH")
    priv.unlink(missing_ok=True)
    pub.unlink(missing_ok=True)
    comment = f"toutpanel-{name or 'deploy'}@{socket.gethostname()}"
    r = plat.run([exe, "-t", "ed25519", "-N", "", "-C", comment, "-f", str(priv), "-q"], timeout=60)
    if not r.ok or not pub.exists():
        raise GitError("Génération de la clé impossible : " + r.output[-300:])
    config.restrict_file(priv)
    return public_key(name)


def delete_key(name: str) -> None:
    if not name:
        raise GitError("La clé globale ne se supprime pas (régénérez-la)")
    priv, pub = key_paths(name)
    priv.unlink(missing_ok=True)
    pub.unlink(missing_ok=True)


# --------------------------------------------------------------------------- validation

def validate(data: dict) -> dict:
    out = {}
    url = str(data.get("repo_url", "")).strip()
    if not url or not REPO_RE.match(url) or url.startswith("-") or any(c.isspace() for c in url):
        raise GitError("URL de dépôt invalide (https://…, git@hôte:chemin.git ou ssh://…)")
    out["repo_url"] = url
    mode = str(data.get("mode", "")).strip() or ("ssh" if url.startswith(("git@", "ssh://")) else "https")
    if mode not in ("https", "ssh"):
        raise GitError("Mode invalide (https ou ssh)")
    if mode == "ssh" and url.startswith("http"):
        raise GitError("Le mode SSH demande une URL git@hôte:… ou ssh://")
    if mode == "https" and not url.startswith(("http", "file://")):
        raise GitError("Le mode HTTPS demande une URL https://")
    if url.startswith("file://"):
        from toutpanel.services import files

        try:
            local = files.safe_path(url[7:])  # un dépôt local ne peut pas viser les données du panel
        except files.FileError as e:
            raise GitError(str(e))
        real = Path(os.path.realpath(str(local)))
        for sysdir in ("/etc", "/usr", "/bin", "/sbin", "/lib", "/lib64", "/boot", "/proc", "/sys", "/dev", "/root", "/run"):
            if real == Path(sysdir) or str(real).startswith(sysdir + "/"):
                raise GitError("Dépôt local refusé dans un répertoire système")
    out["mode"] = mode
    branch = str(data.get("branch", "main")).strip() or "main"
    if not BRANCH_RE.match(branch) or ".." in branch or branch.endswith((".lock", "/")) or "@{" in branch:
        raise GitError("Nom de branche invalide")
    out["branch"] = branch
    for k in ("auth_user", "auth_token"):
        v = str(data.get(k, "") or "")
        if any(ord(c) < 32 for c in v) or len(v) > 500:
            raise GitError("Identifiant invalide")
        out[k] = v.strip()
    key_name = str(data.get("key_name", "") or "").strip()
    if key_name and not KEY_RE.match(key_name):
        raise GitError("Nom de clé invalide (minuscules, chiffres, - _)")
    out["key_name"] = key_name
    try:
        auto = int(data.get("auto_minutes", 0) or 0)
    except (TypeError, ValueError):
        raise GitError("Intervalle invalide")
    if auto < 0 or auto > 10080:
        raise GitError("Intervalle invalide (0 = désactivé, jusqu'à 10080 min)")
    out["auto_minutes"] = auto
    post = str(data.get("post_command", "") or "").strip()
    if len(post) > 4000:
        raise GitError("Commande trop longue")
    out["post_command"] = post
    sub = str(data.get("subdir", "") or "").strip().strip("/")
    if sub and (".." in sub.split("/") or not re.fullmatch(r"[A-Za-z0-9._/-]+", sub)):
        raise GitError("Sous-dossier invalide")
    out["subdir"] = sub
    out["enabled"] = bool(data.get("enabled", True))
    return out


# --------------------------------------------------------------------------- environnement git

def _env(dep: GitDeploy) -> dict:
    d = git_dir()
    env = {"GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C.UTF-8", "HOME": str(d)}
    if dep.mode == "ssh":
        priv, _ = key_paths(dep.key_name)
        if not priv.exists():
            raise GitError("Clé SSH absente : générez-la puis déclarez la clé publique sur le dépôt")
        known = d / "known_hosts"
        env["GIT_SSH_COMMAND"] = ("ssh -i " + shlex.quote(str(priv)) + " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "
                                  "-o UserKnownHostsFile=" + shlex.quote(str(known)) + " -o BatchMode=yes")
    elif dep.auth_token:
        user = dep.auth_user or "x-access-token"
        cred = base64.b64encode(f"{user}:{dep.auth_token}".encode()).decode()
        env.update({"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "http.extraheader", "GIT_CONFIG_VALUE_0": f"AUTHORIZATION: basic {cred}"})
    return env


def _git(args: list[str], cwd: Optional[Path], env: dict, timeout: int = 900):
    plat = get_platform()
    exe = plat.which("git")
    if not exe:
        raise GitError("git n'est pas installé (Logiciels → Git)")
    return plat.run([exe, "-c", "safe.directory=*"] + args, timeout=timeout, cwd=str(cwd) if cwd else None, env=env)


def _lock_for(site_id: int) -> threading.Lock:
    with _locks_guard:
        return _locks.setdefault(site_id, threading.Lock())


# --------------------------------------------------------------------------- opérations

def test_connection(dep: GitDeploy) -> dict:
    """ls-remote : vérifie l'accès au dépôt et l'existence de la branche."""
    r = _git(["ls-remote", "--heads", dep.repo_url, dep.branch], None, _env(dep), timeout=60)
    if not r.ok:
        raise GitError(_clean(r.output) or "connexion au dépôt impossible")
    line = r.stdout.strip().splitlines()
    if not line:
        raise GitError(f"Branche « {dep.branch} » introuvable sur le dépôt")
    return {"commit": line[0].split()[0][:12], "branch": dep.branch}


def remote_head(dep: GitDeploy) -> str:
    r = _git(["ls-remote", "--heads", dep.repo_url, dep.branch], None, _env(dep), timeout=60)
    if not r.ok or not r.stdout.strip():
        return ""
    return r.stdout.strip().split()[0]


def _clean(output: str) -> str:
    # ne jamais renvoyer un jeton qui apparaîtrait dans un message d'erreur
    return re.sub(r"(https?://)[^/@\s]+@", r"\1***@", output).strip()[-1500:]


def deploy_site(site_id: int, log_fn: Optional[Callable[[str], None]] = None, reason: str = "manuel") -> dict:
    """Clone ou met à jour le site depuis son dépôt, exécute la commande post-déploiement. Retourne un résumé."""
    lines: list[str] = []

    def log(line: str) -> None:
        lines.append(line)
        if log_fn:
            log_fn(line)

    lock = _lock_for(site_id)
    if not lock.acquire(blocking=False):
        raise GitError("Un déploiement est déjà en cours pour ce site")
    try:
        with session_scope() as db:
            dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
            site = db.get(Site, site_id)
            if not dep or not site:
                raise GitError("Déploiement Git non configuré pour ce site")
            dep_d = dep.to_dict()
            dep_d["auth_token"] = dep.auth_token
            root = Path(site.root)
            site_name = site.name
        d = GitDeploy(**{k: v for k, v in dep_d.items() if k in GitDeploy.__table__.columns.keys() and k not in ("id", "last_run", "created_at")})
        env = _env(d)
        status, commit, message = "ok", "", ""
        try:
            root.mkdir(parents=True, exist_ok=True)
            log(f"=== Déploiement Git de {site_name} ({reason}) — {d.repo_url} @ {d.branch}")
            work = root
            if d.subdir:
                work = git_dir() / "work" / site_name
                work.mkdir(parents=True, exist_ok=True)
            if not (work / ".git").exists():
                if any(work.iterdir()):
                    log("Répertoire non vide : initialisation du dépôt en place (les fichiers non suivis sont conservés)")
                r = _git(["init", "-q"], work, env)
                if not r.ok:
                    raise GitError(_clean(r.output))
            r = _git(["remote", "get-url", "origin"], work, env, timeout=30)
            r = _git(["remote", "set-url", "origin", d.repo_url], work, env, timeout=30) if r.ok else _git(["remote", "add", "origin", d.repo_url], work, env, timeout=30)
            if not r.ok:
                raise GitError(_clean(r.output))
            log(f"$ git fetch origin {d.branch}")
            r = _git(["fetch", "--prune", "--tags", "origin", d.branch], work, env)
            if not r.ok:
                raise GitError(_clean(r.output))
            log(f"$ git checkout -f -B {d.branch} origin/{d.branch} && git reset --hard  (les fichiers suivis par le dépôt remplacent les fichiers locaux)")
            r = _git(["checkout", "-q", "-f", "-B", d.branch, f"origin/{d.branch}"], work, env)
            if not r.ok:
                raise GitError(_clean(r.output))
            r = _git(["reset", "-q", "--hard", f"origin/{d.branch}"], work, env)
            if not r.ok:
                raise GitError(_clean(r.output))
            r = _git(["submodule", "update", "--init", "--recursive", "--quiet"], work, env)
            if not r.ok:
                log("Sous-modules : " + _clean(r.output))
            r = _git(["log", "-1", "--format=%h|%s|%an|%ci"], work, env, timeout=30)
            if r.ok and "|" in r.stdout:
                commit, message, author, when = (r.stdout.strip().split("|", 3) + ["", "", ""])[:4]
                log(f"Version déployée : {commit} — {message} ({author}, {when})")
            if d.subdir:
                src = work / d.subdir
                if not src.is_dir():
                    raise GitError(f"Sous-dossier « {d.subdir} » absent du dépôt")
                log(f"Copie de {d.subdir}/ vers {root}")
                _sync_tree(src, root)
            if d.post_command:
                log("$ " + d.post_command)
                plat = get_platform()
                rr = plat.run_shell(d.post_command, timeout=1800, cwd=str(root))
                for ln in rr.output.strip().splitlines()[-200:]:
                    log("  " + ln)
                if not rr.ok:
                    raise GitError(f"La commande post-déploiement a échoué (code {rr.returncode})")
            get_platform().chown_web(str(root))
            log("Terminé avec le code 0")
        except GitError as e:
            status = "error"
            log("Erreur : " + str(e))
        with session_scope() as db:
            dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
            if dep:
                dep.last_run = datetime.utcnow()
                dep.last_status = status
                if commit:
                    dep.last_commit = commit
                    dep.last_message = message[:250]
                dep.last_output = "\n".join(lines)[-20000:]
        if status == "error":
            raise GitError(lines[-1] if lines else "échec")
        return {"status": status, "commit": commit, "message": message}
    finally:
        lock.release()


def _sync_tree(src: Path, dest: Path) -> None:
    """Copie src → dest (fichiers du dépôt) sans supprimer ce que dest contient en plus (uploads…)."""
    import shutil

    for p in src.rglob("*"):
        if ".git" in p.relative_to(src).parts:
            continue
        target = dest / p.relative_to(src)
        if p.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif p.is_symlink():
            continue
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, target)


def history(site_id: int, n: int = 20) -> list[dict]:
    with session_scope() as db:
        dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
        site = db.get(Site, site_id)
        if not dep or not site:
            return []
        root = Path(site.root) if not dep.subdir else git_dir() / "work" / site.name
        env = _env(dep) if dep.mode != "ssh" or key_paths(dep.key_name)[0].exists() else {"GIT_TERMINAL_PROMPT": "0"}
    if not (root / ".git").exists():
        return []
    r = _git(["log", f"-{max(1, min(n, 100))}", "--format=%h|%s|%an|%ci"], root, env, timeout=30)
    out = []
    for line in r.stdout.strip().splitlines() if r.ok else []:
        parts = (line.split("|", 3) + ["", "", ""])[:4]
        out.append({"commit": parts[0], "message": parts[1], "author": parts[2], "date": parts[3]})
    return out


def status(site_id: int) -> dict:
    with session_scope() as db:
        dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
        site = db.get(Site, site_id)
        if not dep or not site:
            return {"configured": False}
        d = dep.to_dict()
        root = Path(site.root) if not dep.subdir else git_dir() / "work" / site.name
    d["configured"] = True
    d["cloned"] = (root / ".git").exists()
    d["public_key"] = public_key(dep.key_name) if dep.mode == "ssh" else ""
    d["webhook_url"] = f"/api/git/webhook/{site_id}"
    d["next_run"] = _next_run(dep.id)
    return d


# --------------------------------------------------------------------------- webhook

def verify_webhook(dep: GitDeploy, body: bytes, headers: dict, token_param: str) -> bool:
    """Accepte GitHub / Gitea (X-Hub-Signature-256), GitLab (X-Gitlab-Token) ou ?token= — toujours en comparaison constante."""
    secret = dep.webhook_secret or ""
    if not secret:
        return False
    sig = headers.get("x-hub-signature-256", "")
    if sig.startswith("sha256="):
        expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        return hmac.compare_digest(sig[7:], expected)
    for cand in (headers.get("x-gitlab-token", ""), token_param or ""):
        if cand and hmac.compare_digest(cand, secret):
            return True
    return False


def new_webhook_secret() -> str:
    return secrets.token_urlsafe(24)


# --------------------------------------------------------------------------- actualisation périodique

def _job_id(dep_id: int) -> str:
    return f"git-{dep_id}"


def _auto_run(site_id: int) -> None:
    try:
        with session_scope() as db:
            dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
            if not dep or not dep.enabled or not dep.auto_minutes:
                return
            last = dep.last_commit
            probe = GitDeploy(repo_url=dep.repo_url, branch=dep.branch, mode=dep.mode, auth_user=dep.auth_user, auth_token=dep.auth_token, key_name=dep.key_name)
        head = remote_head(probe)
        if head and last and head.startswith(last):
            return  # rien de nouveau : pas de déploiement inutile
        deploy_site(site_id, reason="actualisation automatique")
    except Exception as e:  # noqa: BLE001
        log.warning("Git auto (site %s) : %s", site_id, e)


def schedule(dep: GitDeploy) -> None:
    from apscheduler.triggers.interval import IntervalTrigger

    from toutpanel.services.cron import get_scheduler

    sched = get_scheduler()
    jid = _job_id(dep.id)
    if sched.get_job(jid):
        sched.remove_job(jid)
    if dep.enabled and dep.auto_minutes:
        sched.add_job(_auto_run, IntervalTrigger(minutes=int(dep.auto_minutes)), id=jid, args=[dep.site_id], replace_existing=True,
                      misfire_grace_time=300, coalesce=True, max_instances=1)


def unschedule(dep_id: int) -> None:
    from toutpanel.services.cron import get_scheduler

    sched = get_scheduler()
    if sched.get_job(_job_id(dep_id)):
        sched.remove_job(_job_id(dep_id))


def _next_run(dep_id: int) -> Optional[str]:
    try:
        from toutpanel.services.cron import get_scheduler

        j = get_scheduler().get_job(_job_id(dep_id))
        nrt = getattr(j, "next_run_time", None) if j else None
        return nrt.isoformat() if nrt else None
    except Exception:  # noqa: BLE001
        return None


def start() -> None:
    """Planifie les actualisations automatiques (appelé au démarrage, après le planificateur)."""
    with session_scope() as db:
        for dep in db.query(GitDeploy).all():
            try:
                schedule(dep)
            except Exception as e:  # noqa: BLE001
                log.warning("Git : planification du site %s impossible : %s", dep.site_id, e)


# --------------------------------------------------------------------------- configuration

def configure(db: Session, site: Site, data: dict) -> GitDeploy:
    values = validate(data)
    dep = db.query(GitDeploy).filter(GitDeploy.site_id == site.id).first()
    if not dep:
        dep = GitDeploy(site_id=site.id, webhook_secret=new_webhook_secret())
        db.add(dep)
    for k, v in values.items():
        if k == "auth_token" and not v and dep.auth_token:
            continue  # jeton conservé si le champ est laissé vide
        setattr(dep, k, v)
    if dep.mode == "ssh":
        generate_key(dep.key_name)  # la clé existe toujours quand le mode SSH est choisi
    db.flush()
    schedule(dep)
    return dep


def remove(db: Session, site_id: int) -> None:
    dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
    if dep:
        unschedule(dep.id)
        db.delete(dep)
        db.flush()
