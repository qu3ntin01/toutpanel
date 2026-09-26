from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel.api.deps import current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import GitDeploy, Site
from toutpanel.services import gitdeploy, tasks

router = APIRouter(prefix="/api/git", tags=["git"])
protected = APIRouter(prefix="/api/git", tags=["git"], dependencies=[Depends(current_user)])


def _site(db: Session, site_id: int) -> Site:
    s = db.get(Site, site_id)
    if not s:
        fail("Site introuvable", 404)
    return s


@protected.get("")
def overview(db: Session = DbDep):
    from toutpanel.platform import get_platform

    deps = {d.site_id: d.to_dict() for d in db.query(GitDeploy).all()}
    sites = []
    for s in db.query(Site).order_by(Site.name).all():
        d = deps.get(s.id)
        if d:
            d["next_run"] = gitdeploy._next_run(d["id"])
        sites.append({"id": s.id, "name": s.name, "domains": s.domains or [], "root": s.root, "git": d})
    plat = get_platform()
    return ok({"sites": sites, "public_key": gitdeploy.public_key(), "git_installed": bool(plat.which("git")), "ssh_installed": bool(plat.which("ssh-keygen")),
               "auto_choices": list(gitdeploy.AUTO_CHOICES)})


class KeyIn(BaseModel):
    name: str = ""
    force: bool = False


@protected.post("/key")
def make_key(data: KeyIn):
    try:
        pub = gitdeploy.generate_key(data.name.strip(), force=data.force)
    except gitdeploy.GitError as e:
        fail(str(e))
    return ok({"public_key": pub, "name": data.name.strip() or "deploy"}, "Clé SSH prête — ajoutez la clé publique dans GitHub (Settings → Deploy keys) ou GitLab")


@protected.get("/sites/{site_id}")
def site_status(site_id: int, db: Session = DbDep):
    _site(db, site_id)
    return ok(gitdeploy.status(site_id))


class ConfigIn(BaseModel):
    repo_url: str
    branch: str = "main"
    mode: str = ""
    auth_user: str = ""
    auth_token: str = ""
    key_name: str = ""
    auto_minutes: int = 0
    post_command: str = ""
    subdir: str = ""
    enabled: bool = True
    deploy_now: bool = False


@protected.put("/sites/{site_id}")
def configure(site_id: int, data: ConfigIn, db: Session = DbDep):
    site = _site(db, site_id)
    try:
        dep = gitdeploy.configure(db, site, data.model_dump())
    except gitdeploy.GitError as e:
        fail(str(e))
    db.commit()
    out = dep.to_dict()
    out["public_key"] = gitdeploy.public_key(dep.key_name) if dep.mode == "ssh" else ""
    if data.deploy_now:
        out["task_id"] = tasks.run_in_background(f"Déploiement Git · {site.name}", _deploy_job(site_id))
    return ok(out, "Déploiement Git configuré")


def _deploy_job(site_id: int, reason: str = "manuel"):
    def _job(log):
        try:
            gitdeploy.deploy_site(site_id, log, reason=reason)
            return 0
        except gitdeploy.GitError as e:
            log(str(e))
            return 1
    return _job


@protected.delete("/sites/{site_id}")
def unconfigure(site_id: int, db: Session = DbDep):
    _site(db, site_id)
    gitdeploy.remove(db, site_id)
    return ok(msg="Déploiement Git retiré (les fichiers du site sont conservés)")


@protected.post("/sites/{site_id}/test")
def test_connection(site_id: int, db: Session = DbDep):
    _site(db, site_id)
    dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
    if not dep:
        fail("Déploiement Git non configuré")
    try:
        return ok(gitdeploy.test_connection(dep), "Dépôt accessible")
    except gitdeploy.GitError as e:
        fail(str(e))


@protected.post("/sites/{site_id}/deploy")
def deploy_now(site_id: int, db: Session = DbDep):
    site = _site(db, site_id)
    if not db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first():
        fail("Déploiement Git non configuré")

    return ok({"task_id": tasks.run_in_background(f"Déploiement Git · {site.name}", _deploy_job(site_id))}, "Déploiement lancé")


@protected.get("/sites/{site_id}/history")
def site_history(site_id: int, db: Session = DbDep):
    _site(db, site_id)
    return ok(gitdeploy.history(site_id))


@protected.post("/sites/{site_id}/webhook/rotate")
def rotate_webhook(site_id: int, db: Session = DbDep):
    _site(db, site_id)
    dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
    if not dep:
        fail("Déploiement Git non configuré")
    dep.webhook_secret = gitdeploy.new_webhook_secret()
    return ok({"secret": dep.webhook_secret, "url": f"/api/git/webhook/{site_id}"}, "Nouveau secret de webhook — mettez-le à jour chez GitHub / GitLab")


@protected.get("/sites/{site_id}/webhook")
def webhook_info(site_id: int, db: Session = DbDep):
    _site(db, site_id)
    dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
    if not dep:
        fail("Déploiement Git non configuré")
    return ok({"secret": dep.webhook_secret, "url": f"/api/git/webhook/{site_id}"})


@router.post("/webhook/{site_id}")
async def webhook(site_id: int, request: Request, token: Optional[str] = None, db: Session = DbDep):
    """Point d'entrée public appelé par GitHub / GitLab / Gitea : signature HMAC (X-Hub-Signature-256), X-Gitlab-Token ou ?token=."""
    body = await request.body()
    dep = db.query(GitDeploy).filter(GitDeploy.site_id == site_id).first()
    site = db.get(Site, site_id)
    if not dep or not site or not dep.enabled or not gitdeploy.verify_webhook(dep, body, {k.lower(): v for k, v in request.headers.items()}, token or ""):
        fail("Webhook refusé", 403)
    event = request.headers.get("x-github-event") or request.headers.get("x-gitlab-event") or request.headers.get("x-gitea-event") or "push"
    if event.lower() == "ping":
        return ok({"pong": True})
    try:
        import json

        payload = json.loads(body.decode("utf-8") or "{}")
        ref = str(payload.get("ref", ""))
        if ref and ref.startswith("refs/heads/") and ref[11:] != dep.branch:
            return ok({"ignored": True, "reason": f"branche {ref[11:]} ≠ {dep.branch}"})
    except ValueError:
        pass

    return ok({"task_id": tasks.run_in_background(f"Déploiement Git (webhook) · {site.name}", _deploy_job(site_id, "webhook"))}, "Déploiement lancé")
