"""Tâches planifiées (APScheduler) : commandes shell, sauvegardes, appels d'URL."""
from __future__ import annotations
from typing import Optional

import logging
import re
from datetime import datetime

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

from toutpanel.db import session_scope
from toutpanel.models import CronJob, utcnow
from toutpanel.platform import get_platform

log = logging.getLogger("toutpanel.cron")
_scheduler: Optional[BackgroundScheduler] = None

PRESETS = {
    "@hourly": "0 * * * *", "@daily": "0 3 * * *", "@weekly": "0 3 * * 0", "@monthly": "0 3 1 * *",
    "@minutely": "* * * * *",
}


def parse_schedule(expr: str) -> CronTrigger:
    expr = PRESETS.get(expr.strip(), expr.strip())
    parts = expr.split()
    if len(parts) != 5:
        raise ValueError("Expression cron invalide (5 champs : min heure jour mois jour_semaine)")
    minute, hour, day, month, dow = parts
    return CronTrigger(minute=minute, hour=hour, day=day, month=month, day_of_week=dow)


def _run_job(job_id: int) -> None:
    with session_scope() as db:
        job = db.get(CronJob, job_id)
        if not job or not job.enabled:
            return
        name, jtype, target = job.name, job.job_type, job.target
    output, status = "", "ok"
    try:
        if jtype == "shell":
            r = get_platform().run_shell(target, timeout=3600)
            output, status = r.output, ("ok" if r.ok else "error")
        elif jtype == "url":
            import httpx

            resp = httpx.get(target, timeout=60, follow_redirects=True)
            output, status = f"HTTP {resp.status_code}\n{resp.text[:2000]}", ("ok" if resp.status_code < 400 else "error")
        elif jtype == "backup_site":
            from toutpanel.services import backup

            with session_scope() as db:
                p = backup.backup_site(db, int(target))
            output = f"Sauvegarde créée : {p}"
        elif jtype == "backup_db":
            from toutpanel.services import backup

            with session_scope() as db:
                p = backup.backup_database(db, int(target))
            output = f"Sauvegarde créée : {p}"
        elif jtype == "backup_path":
            from toutpanel.services import backup

            with session_scope() as db:
                p = backup.backup_path(db, target)
            output = f"Sauvegarde créée : {p}"
        else:
            output, status = "type de tâche inconnu", "error"
    except Exception as e:
        output, status = f"Erreur : {e}", "error"
    with session_scope() as db:
        job = db.get(CronJob, job_id)
        if job:
            job.last_run = utcnow()
            job.last_status = status
            job.last_output = output[-10000:]
    log.info("Tâche %s (%s) terminée : %s", job_id, name, status)


def get_scheduler() -> BackgroundScheduler:
    global _scheduler
    if _scheduler is None:
        _scheduler = BackgroundScheduler()
    return _scheduler


def schedule_job(job: CronJob) -> None:
    sched = get_scheduler()
    jid = f"cron-{job.id}"
    if sched.get_job(jid):
        sched.remove_job(jid)
    if job.enabled:
        sched.add_job(_run_job, parse_schedule(job.schedule), id=jid, args=[job.id], replace_existing=True,
                      misfire_grace_time=300, coalesce=True)


def unschedule_job(job_id: int) -> None:
    sched = get_scheduler()
    jid = f"cron-{job_id}"
    if sched.get_job(jid):
        sched.remove_job(jid)


def next_run(job_id: int) -> Optional[str]:
    j = get_scheduler().get_job(f"cron-{job_id}")
    nrt = getattr(j, "next_run_time", None) if j else None
    return nrt.isoformat() if nrt else None


def run_now(job_id: int) -> None:
    import threading

    threading.Thread(target=_run_job, args=(job_id,), daemon=True).start()


def start() -> None:
    sched = get_scheduler()
    with session_scope() as db:
        for job in db.query(CronJob).all():
            try:
                schedule_job(job)
            except ValueError as e:
                log.warning("Tâche %s ignorée : %s", job.id, e)
    if not sched.running:
        sched.start()


def stop() -> None:
    global _scheduler
    if _scheduler and _scheduler.running:
        _scheduler.shutdown(wait=False)
    _scheduler = None


def validate_target(job_type: str, target: str) -> None:
    if job_type == "shell" and not target.strip():
        raise ValueError("Commande requise")
    if job_type == "url" and not re.match(r"^https?://", target):
        raise ValueError("URL invalide")
    if job_type in ("backup_site", "backup_db") and not target.strip().isdigit():
        raise ValueError("Identifiant requis")
    if job_type == "backup_path" and not target.strip():
        raise ValueError("Chemin requis")
