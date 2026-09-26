"""Exécution de tâches longues en arrière-plan avec journal en base."""
from __future__ import annotations

import threading
import traceback
from datetime import datetime
from typing import Callable, Optional

from toutpanel.db import session_scope
from toutpanel.models import Task, utcnow

_lock = threading.Lock()


TASKS_KEEP = 300
_buffers: dict[int, list[str]] = {}
_last_flush: dict[int, float] = {}


def create_task(name: str) -> int:
    with session_scope() as db:
        t = Task(name=name, status="pending")
        db.add(t)
        db.flush()
        tid = t.id
        # rétention : on ne garde que les dernières tâches (journal des anciennes inclus)
        if tid % 20 == 0:
            oldest = db.query(Task.id).order_by(Task.id.desc()).offset(TASKS_KEEP).limit(1).scalar()
            if oldest:
                db.query(Task).filter(Task.id <= oldest).delete()
        return tid


def append_log(task_id: int, line: str) -> None:
    """Journal mis en tampon et écrit par paquets (une écriture par seconde au plus) : un `apt install` verbeux
    ne génère plus une transaction SQLite par ligne."""
    import time

    with _lock:
        _buffers.setdefault(task_id, []).append(line)
        due = time.time() - _last_flush.get(task_id, 0) > 1.0
    if due:
        flush_log(task_id)


def flush_log(task_id: int) -> None:
    import time

    with _lock:
        lines = _buffers.pop(task_id, [])
        _last_flush[task_id] = time.time()
    if not lines:
        return
    with session_scope() as db:
        t = db.get(Task, task_id)
        if t:
            t.log = ((t.log or "") + "\n".join(lines) + "\n")[-400_000:]


def set_status(task_id: int, status: str) -> None:
    if status in ("done", "error"):
        flush_log(task_id)
    with session_scope() as db:
        t = db.get(Task, task_id)
        if t:
            t.status = status
            if status in ("done", "error"):
                t.finished_at = utcnow()


def run_in_background(name: str, fn: Callable[[Callable[[str], None]], Optional[int]]) -> int:
    """Lance fn(log) dans un thread. fn retourne un code (0 = succès)."""
    task_id = create_task(name)

    def _runner():
        set_status(task_id, "running")
        log = lambda line: append_log(task_id, line)  # noqa: E731
        try:
            rc = fn(log)
            set_status(task_id, "done" if not rc else "error")
        except Exception as e:  # pragma: no cover
            log("Exception: " + str(e))
            log(traceback.format_exc())
            set_status(task_id, "error")

    threading.Thread(target=_runner, name=f"task-{task_id}", daemon=True).start()
    return task_id


def list_tasks(limit: int = 50) -> list[dict]:
    with session_scope() as db:
        rows = db.query(Task).order_by(Task.id.desc()).limit(limit).all()
        return [r.to_dict() for r in rows]


def get_task(task_id: int) -> Optional[dict]:
    with session_scope() as db:
        t = db.get(Task, task_id)
        d = t.to_dict() if t else None
    if d is not None:
        with _lock:
            pending = list(_buffers.get(task_id, []))
        if pending:
            d["log"] = (d.get("log") or "") + "\n".join(pending) + "\n"
    return d


def flush_all() -> None:
    for tid in list(_buffers):
        flush_log(tid)
