"""Historique des métriques système (CPU, RAM, disque, réseau) échantillonné périodiquement."""
from __future__ import annotations
from typing import Optional

import logging
import threading
import time
from datetime import datetime, timedelta

import psutil

from toutpanel import config
from toutpanel.db import session_scope
from toutpanel.models import MonitorSample, utcnow

log = logging.getLogger("toutpanel.monitor")
_stop = threading.Event()
_thread: Optional[threading.Thread] = None


def _sample(prev: Optional[tuple[float, int, int]]) -> tuple[MonitorSample, tuple[float, int, int]]:
    c = psutil.net_io_counters()
    now = time.time()
    net_in = net_out = 0.0
    if prev:
        dt = max(now - prev[0], 1e-3)
        net_in, net_out = (c.bytes_recv - prev[1]) / dt, (c.bytes_sent - prev[2]) / dt
    try:
        import os

        load1 = os.getloadavg()[0] if hasattr(os, "getloadavg") else psutil.getloadavg()[0]
    except (OSError, AttributeError):
        load1 = 0.0
    try:
        disk = psutil.disk_usage(str(config.HOME if config.HOME.exists() else "/")).percent
    except OSError:
        disk = 0.0
    s = MonitorSample(cpu=psutil.cpu_percent(interval=None), mem=psutil.virtual_memory().percent, disk=disk,
                      net_in=net_in, net_out=net_out, load1=load1)
    return s, (now, c.bytes_recv, c.bytes_sent)


def _loop() -> None:
    prev = None
    psutil.cpu_percent(interval=None)
    while not _stop.is_set():
        s = config.get_settings()
        interval = max(10, int(s.get("monitor_interval", 60)))
        if s.get("monitor_enabled", True):
            try:
                sample, prev = _sample(prev)
                with session_scope() as db:
                    db.add(sample)
                    cutoff = utcnow() - timedelta(days=int(s.get("monitor_retention_days", 7)))
                    db.query(MonitorSample).filter(MonitorSample.ts < cutoff).delete()
            except Exception as e:  # pragma: no cover
                log.warning("échantillon impossible : %s", e)
        _stop.wait(interval)


def start() -> None:
    global _thread
    if _thread and _thread.is_alive():
        return
    _stop.clear()
    _thread = threading.Thread(target=_loop, name="toutpanel-monitor", daemon=True)
    _thread.start()


def stop() -> None:
    _stop.set()


def history(hours: int = 24, max_points: int = 600) -> list[dict]:
    since = utcnow() - timedelta(hours=hours)
    with session_scope() as db:
        rows = db.query(MonitorSample).filter(MonitorSample.ts >= since).order_by(MonitorSample.ts).all()
        if len(rows) > max_points:
            step = len(rows) // max_points + 1
            rows = rows[::step]
        return [r.to_dict() for r in rows]
