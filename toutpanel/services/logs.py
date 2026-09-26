"""Consultation des journaux (panel, sites, système)."""
from __future__ import annotations

import os
from pathlib import Path

from toutpanel import config
from toutpanel.platform import get_platform


def resolve_log(ref: str) -> Path:
    """Accepte un identifiant de available_logs() ou un chemin figurant dans cette liste ; rien d'autre
    (un chemin libre permettrait de lire settings.json ou de vider la base)."""
    for entry in available_logs():
        if ref == entry["id"] or ref == entry["path"]:
            return Path(entry["path"])
    p = Path(ref)
    try:
        if p.resolve().is_relative_to(config.LOG_DIR.resolve()) and p.suffix in (".log", ".txt", ".err", ".out"):
            return p
    except (OSError, ValueError, AttributeError):
        pass
    raise ValueError("Journal inconnu")


def tail(path: str, lines: int = 200, max_bytes: int = 2 * 1024 * 1024) -> str:
    p = resolve_log(path)
    if not p.is_file():
        return ""
    size = p.stat().st_size
    with open(p, "rb") as f:
        f.seek(max(0, size - max_bytes))
        data = f.read().decode("utf-8", errors="replace")
    return "\n".join(data.splitlines()[-lines:])


def available_logs() -> list[dict]:
    out = [{"id": "panel", "label": "Panel ToutPanel", "path": str(config.LOG_DIR / "panel.log")}]
    site_logs = config.LOG_DIR / "sites"
    if site_logs.exists():
        for f in sorted(site_logs.iterdir()):
            out.append({"id": f"site:{f.name}", "label": f"Site : {f.name}", "path": str(f)})
    candidates = ["/var/log/nginx/error.log", "/var/log/nginx/access.log", "/var/log/apache2/error.log",
                  "/var/log/httpd/error_log", "/var/log/mysql/error.log", "/var/log/syslog", "/var/log/messages",
                  "/var/log/auth.log", "/var/log/secure", "/var/log/letsencrypt/letsencrypt.log",
                  "C:/nginx/logs/error.log", "C:/nginx/logs/access.log"]
    for c in candidates:
        if os.path.isfile(c):
            out.append({"id": f"file:{c}", "label": c, "path": c})
    return out


def journal(unit: str = "", lines: int = 200) -> str:
    plat = get_platform()
    if config.IS_WINDOWS:
        r = plat.run_shell(f"Get-EventLog -LogName System -Newest {lines} | Format-Table -AutoSize | Out-String -Width 200", timeout=60)
        return r.output
    if plat.which("journalctl"):
        cmd = ["journalctl", "--no-pager", "-n", str(lines)]
        if unit:
            cmd += ["-u", unit]
        return plat.run(cmd, timeout=60).output
    return tail("/var/log/syslog", lines) or tail("/var/log/messages", lines)


def clear(path: str) -> None:
    p = resolve_log(path)
    if p.is_file():
        p.write_text("", encoding="utf-8")
