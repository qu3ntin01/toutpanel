"""Processus système."""
from __future__ import annotations

import os

import psutil


def list_processes(limit: int = 300, sort: str = "cpu") -> list[dict]:
    out = []
    for p in psutil.process_iter(["pid", "name", "username", "cpu_percent", "memory_info", "status", "create_time", "cmdline"]):
        try:
            info = p.info
            mem = info["memory_info"].rss if info.get("memory_info") else 0
            out.append({"pid": info["pid"], "name": info.get("name") or "", "user": info.get("username") or "",
                        "cpu": info.get("cpu_percent") or 0.0, "memory": mem, "status": info.get("status") or "",
                        "started": info.get("create_time") or 0,
                        "cmdline": " ".join(info.get("cmdline") or [])[:300]})
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
    key = {"cpu": lambda x: -x["cpu"], "memory": lambda x: -x["memory"], "pid": lambda x: x["pid"], "name": lambda x: x["name"].lower()}
    out.sort(key=key.get(sort, key["cpu"]))
    return out[:limit]


def kill(pid: int, force: bool = False) -> None:
    if pid <= 1 or pid == os.getpid() or pid == os.getppid():
        raise ValueError("Ce processus ne peut pas être arrêté depuis le panel")
    p = psutil.Process(pid)
    if force:
        p.kill()
    else:
        p.terminate()
