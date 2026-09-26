"""Statistiques système pour le tableau de bord (psutil)."""
from __future__ import annotations
from typing import Optional

import os
import socket
import time
from datetime import datetime

import psutil

from toutpanel import __version__, config
from toutpanel.platform import get_platform

_last_net: Optional[tuple[float, int, int]] = None


def _net_rates() -> tuple[float, float]:
    """Retourne (octets/s entrants, octets/s sortants) depuis le dernier appel."""
    global _last_net
    c = psutil.net_io_counters()
    now = time.time()
    if _last_net is None:
        _last_net = (now, c.bytes_recv, c.bytes_sent)
        return 0.0, 0.0
    t0, r0, s0 = _last_net
    dt = max(now - t0, 1e-3)
    rates = ((c.bytes_recv - r0) / dt, (c.bytes_sent - s0) / dt)
    _last_net = (now, c.bytes_recv, c.bytes_sent)
    return rates


def disks() -> list[dict]:
    out = []
    seen = set()
    for part in psutil.disk_partitions(all=False):
        if part.mountpoint in seen:
            continue
        if "cdrom" in part.opts or (config.IS_LINUX and part.fstype in ("squashfs", "tmpfs", "devtmpfs", "overlay")):
            continue
        try:
            u = psutil.disk_usage(part.mountpoint)
        except (PermissionError, OSError):
            continue
        seen.add(part.mountpoint)
        out.append({"device": part.device, "mountpoint": part.mountpoint, "fstype": part.fstype,
                    "total": u.total, "used": u.used, "free": u.free, "percent": u.percent})
    return out


def _local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


def overview() -> dict:
    cpu_percent = psutil.cpu_percent(interval=None)
    mem = psutil.virtual_memory()
    swap = psutil.swap_memory()
    try:
        load = os.getloadavg() if hasattr(os, "getloadavg") else psutil.getloadavg()
    except (OSError, AttributeError):
        load = (0.0, 0.0, 0.0)
    net_in, net_out = _net_rates()
    boot = psutil.boot_time()
    try:
        freq = psutil.cpu_freq()
        freq_mhz = freq.current if freq else 0
    except Exception:
        freq_mhz = 0
    plat = get_platform()
    return {
        "panel": {"name": config.get_settings().get("panel_name"), "version": __version__, "home": str(config.HOME),
                  "os": config.OS_NAME, "python": f"{os.sys.version_info.major}.{os.sys.version_info.minor}.{os.sys.version_info.micro}",
                  "is_admin": plat.is_admin(), "webserver": detect_webserver()},
        "os": {**plat.os_info(), "selinux": plat.selinux_status() if hasattr(plat, "selinux_status") else ""},
        "time": datetime.now().isoformat(),
        "uptime": int(time.time() - boot),
        "ip": _local_ip(),
        "cpu": {"percent": cpu_percent, "cores": psutil.cpu_count(logical=False) or 1,
                "threads": psutil.cpu_count(logical=True) or 1, "freq_mhz": freq_mhz,
                "per_cpu": psutil.cpu_percent(interval=None, percpu=True)},
        "memory": {"total": mem.total, "used": mem.used, "available": mem.available, "percent": mem.percent},
        "swap": {"total": swap.total, "used": swap.used, "percent": swap.percent},
        "load": {"1": round(load[0], 2), "5": round(load[1], 2), "15": round(load[2], 2)},
        "disks": disks(),
        "network": {"in": net_in, "out": net_out, "total": psutil.net_io_counters()._asdict()},
        "processes": len(psutil.pids()),
    }


def detect_webserver() -> str:
    from toutpanel.services.webserver import detect

    return detect()


def _php_versions() -> list[str]:
    from toutpanel.services.webserver import php_versions

    try:
        return php_versions()
    except Exception:
        return []


def services_summary() -> list[dict]:
    """État des services principaux (nginx, apache, mysql, php-fpm, redis, docker...)."""
    plat = get_platform()
    candidates = [
        ("nginx", ["nginx"]), ("apache", ["apache2", "httpd", "Apache2.4"]),
        ("mysql", ["mariadb", "mysql", "mysqld", "MySQL80", "MariaDB"]),
        ("postgresql", ["postgresql", "postgresql-14", "postgresql-15", "postgresql-16", "postgresql-x64-16"]),
        ("php-fpm", [f"php{v}-fpm" for v in sorted(_php_versions(), reverse=True)] + ["php-fpm", f"php-fpm{''.join(_php_versions()[-1:]).replace('.', '')}"]),
        ("redis", ["redis-server", "redis", "valkey", "Redis"]), ("docker", ["docker", "com.docker.service"]),
        ("memcached", ["memcached"]), ("ftp (intégré)", []),
    ]
    out = []
    for label, names in candidates:
        if label.startswith("ftp"):
            from toutpanel.services import ftp

            out.append({"label": label, "service": "toutpanel-ftp", "status": "running" if ftp.is_running() else "stopped",
                        "builtin": True})
            continue
        status, found = "missing", ""
        for n in names:
            st = plat.service_status(n)
            if st != "unknown":
                status, found = st, n
                break
        out.append({"label": label, "service": found, "status": status, "builtin": False})
    return out
