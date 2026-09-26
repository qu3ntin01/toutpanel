"""Gestion Docker via la CLI (containers, images, compose)."""
from __future__ import annotations

import os
from typing import Optional

import json

from toutpanel.platform import get_platform


def available() -> bool:
    plat = get_platform()
    if not plat.which("docker"):
        return False
    return plat.run(["docker", "info", "--format", "{{.ServerVersion}}"], timeout=15).ok


def _json_lines(out: str) -> list[dict]:
    rows = []
    for line in out.splitlines():
        line = line.strip()
        if line:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows


def containers(all_: bool = True) -> list[dict]:
    plat = get_platform()
    cmd = ["docker", "ps", "--format", "{{json .}}"] + (["-a"] if all_ else [])
    r = plat.run(cmd, timeout=30)
    if not r.ok:
        raise RuntimeError(r.output)
    return [{"id": c.get("ID"), "name": c.get("Names"), "image": c.get("Image"), "status": c.get("Status"),
             "state": c.get("State"), "ports": c.get("Ports"), "created": c.get("CreatedAt")} for c in _json_lines(r.stdout)]


def images() -> list[dict]:
    r = get_platform().run(["docker", "images", "--format", "{{json .}}"], timeout=30)
    if not r.ok:
        raise RuntimeError(r.output)
    return [{"id": i.get("ID"), "repository": i.get("Repository"), "tag": i.get("Tag"), "size": i.get("Size"),
             "created": i.get("CreatedSince")} for i in _json_lines(r.stdout)]


def container_action(cid: str, action: str) -> str:
    if action not in ("start", "stop", "restart", "pause", "unpause", "rm", "kill"):
        raise ValueError("action invalide")
    cmd = ["docker", action, cid] if action != "rm" else ["docker", "rm", "-f", cid]
    r = get_platform().run(cmd, timeout=120)
    return "" if r.ok else r.output


def logs(cid: str, tail: int = 200) -> str:
    r = get_platform().run(["docker", "logs", "--tail", str(tail), cid], timeout=30)
    return r.output


def remove_image(image_id: str) -> str:
    r = get_platform().run(["docker", "rmi", image_id], timeout=120)
    return "" if r.ok else r.output


def pull(image: str, log) -> int:
    import re

    if not image or image.startswith("-") or not re.fullmatch(r"[A-Za-z0-9._/:@-]+", image):
        log("Nom d'image invalide")
        return 1
    return get_platform().stream(["docker", "pull", image], log)


FORBIDDEN_MOUNTS = ("/", "/etc", "/root", "/var/run/docker.sock", "/run/docker.sock", "/proc", "/sys", "/dev", "/boot")


def validate_run_args(image: str, name: str, ports: list[str], env: list[str], volumes: list[str], restart: str) -> None:
    import re

    if restart not in ("no", "always", "unless-stopped", "on-failure"):
        raise ValueError("Politique de redémarrage invalide")
    if not image or image.startswith("-") or not re.fullmatch(r"[A-Za-z0-9._/:@-]+", image):
        raise ValueError("Nom d'image invalide")
    if name and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", name):
        raise ValueError("Nom de conteneur invalide")
    for p in ports:
        if not re.fullmatch(r"(\d{1,3}(\.\d{1,3}){3}:)?\d{1,5}(:\d{1,5})?(/(tcp|udp))?", p):
            raise ValueError(f"Port invalide : {p}")
    for e in env:
        if "=" not in e or e.startswith("-") or "\n" in e:
            raise ValueError(f"Variable invalide : {e}")
    from toutpanel import config

    for v in volumes:
        host = v.split(":")[0]
        if host.startswith("-") or "\n" in v:
            raise ValueError(f"Volume invalide : {v}")
        if host.startswith("/"):
            real = os.path.realpath(host)
            if real in FORBIDDEN_MOUNTS or real.startswith(str(config.DATA_DIR)) or real == str(config.HOME):
                raise ValueError(f"Montage refusé : {host}")


def run_container(image: str, name: str = "", ports: Optional[list[str]] = None, env: Optional[list[str]] = None,
                  volumes: Optional[list[str]] = None, restart: str = "unless-stopped") -> str:
    validate_run_args(image, name, ports or [], env or [], volumes or [], restart)
    cmd = ["docker", "run", "-d", "--restart", restart]
    if name:
        cmd += ["--name", name]
    for p in ports or []:
        cmd += ["-p", p]
    for e in env or []:
        cmd += ["-e", e]
    for v in volumes or []:
        cmd += ["-v", v]
    cmd.append(image)
    r = get_platform().run(cmd, timeout=600)
    if not r.ok:
        raise RuntimeError(r.output)
    return r.stdout.strip()


def stats() -> list[dict]:
    r = get_platform().run(["docker", "stats", "--no-stream", "--format", "{{json .}}"], timeout=30)
    if not r.ok:
        return []
    return [{"id": s.get("ID"), "name": s.get("Name"), "cpu": s.get("CPUPerc"), "memory": s.get("MemUsage"),
             "net": s.get("NetIO"), "block": s.get("BlockIO")} for s in _json_lines(r.stdout)]
