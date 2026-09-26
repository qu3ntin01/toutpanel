from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel.api.deps import current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import FirewallRule, LoginLog
from toutpanel.services import firewall

router = APIRouter(prefix="/api/firewall", tags=["firewall"], dependencies=[Depends(current_user)])


@router.get("")
def get(db: Session = DbDep):
    return ok({"status": firewall.status(), "rules": [r.to_dict() for r in db.query(FirewallRule).order_by(FirewallRule.id.desc()).all()],
               "listening": firewall.listening_ports()})


class ToggleIn(BaseModel):
    enabled: bool


@router.post("/toggle")
def toggle(data: ToggleIn):
    err = firewall.set_enabled(data.enabled)
    if err:
        fail(err)
    return ok(firewall.status(), "Pare-feu " + ("activé" if data.enabled else "désactivé"))


class RuleIn(BaseModel):
    port: str
    protocol: str = "tcp"
    action: str = "allow"
    source: str = ""
    remark: str = ""


@router.post("/rules")
def add_rule(data: RuleIn, db: Session = DbDep):
    try:
        rule, warn = firewall.add_rule(db, data.port, data.protocol, data.action, data.source, data.remark)
    except ValueError as e:
        fail(str(e))
    return ok(rule.to_dict(), ("Règle enregistrée, mais application système : " + warn) if warn else "Règle ajoutée")


@router.delete("/rules/{rid}")
def delete_rule(rid: int, db: Session = DbDep):
    rule = db.get(FirewallRule, rid)
    if not rule:
        fail("Introuvable", 404)
    warn = firewall.remove_rule(db, rule)
    return ok(msg=("Règle retirée du panel, système : " + warn) if warn else "Règle supprimée")


@router.get("/login-logs")
def login_logs(limit: int = 100, db: Session = DbDep):
    rows = db.query(LoginLog).order_by(LoginLog.id.desc()).limit(min(limit, 1000)).all()
    return ok([r.to_dict() for r in rows])
