from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel.api.deps import current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import CronJob
from toutpanel.services import cron

router = APIRouter(prefix="/api/cron", tags=["cron"], dependencies=[Depends(current_user)])


@router.get("")
def list_jobs(db: Session = DbDep):
    out = []
    for j in db.query(CronJob).order_by(CronJob.id.desc()).all():
        d = j.to_dict()
        d["next_run"] = cron.next_run(j.id)
        out.append(d)
    return ok(out)


class JobIn(BaseModel):
    name: str
    schedule: str
    job_type: str = "shell"
    target: str = ""
    enabled: bool = True


@router.post("")
def create(data: JobIn, db: Session = DbDep):
    try:
        cron.parse_schedule(data.schedule)
        cron.validate_target(data.job_type, data.target)
    except ValueError as e:
        fail(str(e))
    j = CronJob(name=data.name.strip() or "Tâche", schedule=cron.PRESETS.get(data.schedule.strip(), data.schedule.strip()),
                job_type=data.job_type, target=data.target, enabled=data.enabled)
    db.add(j)
    db.flush()
    cron.schedule_job(j)
    return ok(j.to_dict(), "Tâche créée")


@router.put("/{jid}")
def update(jid: int, data: JobIn, db: Session = DbDep):
    j = db.get(CronJob, jid)
    if not j:
        fail("Introuvable", 404)
    try:
        cron.parse_schedule(data.schedule)
        cron.validate_target(data.job_type, data.target)
    except ValueError as e:
        fail(str(e))
    j.name, j.schedule, j.job_type, j.target, j.enabled = data.name, cron.PRESETS.get(data.schedule.strip(), data.schedule.strip()), data.job_type, data.target, data.enabled
    db.flush()
    cron.schedule_job(j)
    return ok(j.to_dict(), "Tâche mise à jour")


@router.delete("/{jid}")
def delete(jid: int, db: Session = DbDep):
    j = db.get(CronJob, jid)
    if not j:
        fail("Introuvable", 404)
    cron.unschedule_job(jid)
    db.delete(j)
    return ok(msg="Tâche supprimée")


@router.post("/{jid}/run")
def run(jid: int, db: Session = DbDep):
    if not db.get(CronJob, jid):
        fail("Introuvable", 404)
    cron.run_now(jid)
    return ok(msg="Exécution lancée")
