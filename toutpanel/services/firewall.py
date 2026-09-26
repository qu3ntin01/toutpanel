"""Pare-feu : règles appliquées au système (ufw/firewalld/iptables/netsh) et mémorisées en base."""
from __future__ import annotations

import re

from sqlalchemy.orm import Session

from toutpanel.models import FirewallRule
from toutpanel.platform import get_platform

PORT_RE = re.compile(r"^\d{1,5}(-\d{1,5})?$")


def status() -> dict:
    return get_platform().firewall_status()


def set_enabled(enable: bool) -> str:
    r = get_platform().firewall_enable(enable)
    return "" if r.ok else r.output


def add_rule(db: Session, port: str, protocol: str = "tcp", action: str = "allow", source: str = "", remark: str = "") -> tuple[FirewallRule, str]:
    port = port.strip()
    if not PORT_RE.match(port):
        raise ValueError("Port invalide (ex: 80 ou 8000-8100)")
    if protocol not in ("tcp", "udp"):
        raise ValueError("Protocole invalide")
    if action not in ("allow", "deny"):
        raise ValueError("Action invalide")
    source = source.strip()
    if source and not re.match(r"^[0-9a-fA-F.:/]+$", source):
        raise ValueError("Source invalide (IP ou CIDR)")
    if db.query(FirewallRule).filter_by(port=port, protocol=protocol, action=action, source=source).first():
        raise ValueError("Règle déjà existante")
    r = get_platform().firewall_add(port, protocol, action, source, remark)
    rule = FirewallRule(port=port, protocol=protocol, action=action, source=source, remark=remark)
    db.add(rule)
    db.flush()
    return rule, ("" if r.ok else r.output)


def remove_rule(db: Session, rule: FirewallRule) -> str:
    r = get_platform().firewall_remove(rule.port, rule.protocol, rule.action, rule.source, rule.remark)
    db.delete(rule)
    db.flush()
    return "" if r.ok else r.output


def listening_ports() -> list[dict]:
    import psutil

    out = []
    seen = set()
    try:
        conns = psutil.net_connections(kind="inet")
    except (psutil.AccessDenied, OSError):
        return out
    for c in conns:
        if c.status != psutil.CONN_LISTEN and c.type != 2:  # 2 = UDP
            continue
        if not c.laddr:
            continue
        key = (c.laddr.port, c.type)
        if key in seen:
            continue
        seen.add(key)
        name = ""
        if c.pid:
            try:
                name = psutil.Process(c.pid).name()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        out.append({"port": c.laddr.port, "address": c.laddr.ip, "protocol": "tcp" if c.type == 1 else "udp",
                    "pid": c.pid, "process": name})
    out.sort(key=lambda x: x["port"])
    return out
