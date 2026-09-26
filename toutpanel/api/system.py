"""Tableau de bord, monitoring, processus, services, journaux, tâches."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from toutpanel.api.deps import current_user, fail, ok
from toutpanel.platform import get_platform
from toutpanel.services import logs, monitor, processes, system_info, tasks

router = APIRouter(prefix="/api/system", tags=["system"], dependencies=[Depends(current_user)])


@router.get("/overview")
def overview():
    return ok(system_info.overview())


@router.get("/services")
def services():
    return ok(system_info.services_summary())


@router.get("/services/all")
def services_all():
    return ok(get_platform().list_services())


class ServiceAction(BaseModel):
    name: str
    action: str


@router.post("/services/action")
def service_action(data: ServiceAction):
    r = get_platform().service_action(data.name, data.action)
    if not r.ok:
        fail(r.output or "échec")
    return ok(msg=f"{data.name} : {data.action} OK")


@router.get("/monitor")
def monitor_history(hours: int = 24):
    return ok(monitor.history(hours=min(max(hours, 1), 24 * 30)))


@router.get("/processes")
def list_processes(sort: str = "cpu"):
    return ok(processes.list_processes(sort=sort))


class KillIn(BaseModel):
    pid: int
    force: bool = False


@router.post("/processes/kill")
def kill_process(data: KillIn):
    import psutil

    try:
        processes.kill(data.pid, data.force)
    except ValueError as e:
        fail(str(e))
    except psutil.NoSuchProcess:
        fail("Processus introuvable")
    except psutil.AccessDenied:
        fail("Accès refusé", 403)
    return ok(msg="Signal envoyé")


@router.get("/logs")
def list_logs():
    return ok(logs.available_logs())


@router.get("/logs/read")
def read_log(path: str, lines: int = 300):
    try:
        return ok({"path": path, "content": logs.tail(path, lines=min(max(lines, 1), 5000))})
    except ValueError as e:
        fail(str(e), 404)


@router.get("/logs/journal")
def read_journal(unit: str = "", lines: int = 200):
    return ok({"content": logs.journal(unit, min(lines, 2000))})


class ClearIn(BaseModel):
    path: str


@router.post("/logs/clear")
def clear_log(data: ClearIn):
    try:
        logs.clear(data.path)
    except ValueError as e:
        fail(str(e), 404)
    return ok(msg="Journal vidé")


@router.get("/tasks")
def list_tasks():
    return ok(tasks.list_tasks())


@router.get("/tasks/{task_id}")
def get_task(task_id: int):
    t = tasks.get_task(task_id)
    if not t:
        fail("Tâche introuvable", 404)
    return ok(t)


@router.post("/reboot")
def reboot():
    r = get_platform().reboot()
    if not r.ok:
        fail(r.output)
    return ok(msg="Redémarrage demandé")
