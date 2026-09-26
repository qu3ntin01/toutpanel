from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel.api.deps import client_ip, current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import Site, WafBan, WafRule, utcnow
from toutpanel.services import waf, waf_engines

router = APIRouter(prefix="/api/waf", tags=["waf"], dependencies=[Depends(current_user)])


@router.get("")
def overview(hours: int = 24, db: Session = DbDep):
    from datetime import datetime

    return ok({
        "settings": waf.get_settings(), "stats": waf.stats(hours=min(max(hours, 1), 24 * 30)),
        "rules": [r.to_dict() for r in db.query(WafRule).order_by(WafRule.id.desc()).all()],
        "bans": [b.to_dict() for b in db.query(WafBan).filter((WafBan.until.is_(None)) | (WafBan.until > utcnow())).order_by(WafBan.id.desc()).all()],
        "sites": [{"id": s.id, "name": s.name, "waf_enabled": s.waf_enabled, "enabled": s.enabled} for s in db.query(Site).order_by(Site.name).all()],
        "applied": waf.nginx_site_include().exists(),
    })


@router.get("/events")
def events(hours: int = 24, limit: int = 300):
    return ok(waf.events(limit=min(limit, 2000), hours=min(max(hours, 1), 24 * 30)))


class SettingsIn(BaseModel):
    values: dict


@router.post("/settings")
def update_settings(data: SettingsIn):
    try:
        s = waf.save_settings(data.values)
    except (TypeError, ValueError):
        fail("Valeurs invalides")
    return ok(s, "Paramètres enregistrés — appliquez pour recharger le serveur web.")


@router.post("/apply")
def apply(db: Session = DbDep):
    warn = waf.apply(db)
    return ok(msg=warn or "Règles WAF appliquées")


@router.get("/preview")
def preview(db: Session = DbDep):
    return ok({"nginx_http": waf.render_nginx_http(db), "nginx_site": waf.render_nginx_site(), "apache_site": waf.render_apache_site(db)})


class RuleIn(BaseModel):
    kind: str
    value: str
    remark: str = ""


@router.post("/rules")
def add_rule(data: RuleIn, db: Session = DbDep):
    try:
        r = waf.add_rule(db, data.kind, data.value, data.remark)
    except ValueError as e:
        fail(str(e))
    return ok(r.to_dict(), "Règle ajoutée — appliquez pour l'activer.")


class RuleToggle(BaseModel):
    enabled: bool


@router.put("/rules/{rid}")
def toggle_rule(rid: int, data: RuleToggle, db: Session = DbDep):
    r = db.get(WafRule, rid)
    if not r:
        fail("Introuvable", 404)
    r.enabled = data.enabled
    return ok(r.to_dict())


@router.delete("/rules/{rid}")
def delete_rule(rid: int, db: Session = DbDep):
    r = db.get(WafRule, rid)
    if not r:
        fail("Introuvable", 404)
    db.delete(r)
    return ok(msg="Règle supprimée — appliquez pour recharger.")


class BanIn(BaseModel):
    ip: str
    minutes: int = 60
    reason: str = "manuel"


@router.post("/bans")
def add_ban(data: BanIn, request: Request, db: Session = DbDep):
    if data.ip.strip().split("/")[0] == client_ip(request):
        fail("Vous ne pouvez pas bannir votre propre adresse IP")
    try:
        b = waf.ban(db, data.ip, data.minutes or None, data.reason)
        db.commit()
        waf.flush_firewall()
    except ValueError as e:
        fail(str(e))
    db.flush()
    waf.write_configs(db)
    return ok(b.to_dict(), "IP bannie (règle de pare-feu ajoutée)")


@router.delete("/bans/{bid}")
def delete_ban(bid: int, db: Session = DbDep):
    b = db.get(WafBan, bid)
    if not b:
        fail("Introuvable", 404)
    waf.unban(db, b)
    db.commit()
    waf.flush_firewall()
    waf.write_configs(db)
    return ok(msg="IP débannie")


class SiteToggle(BaseModel):
    waf_enabled: bool


@router.put("/sites/{sid}")
def toggle_site(sid: int, data: SiteToggle, db: Session = DbDep):
    from toutpanel.services import sites

    s = db.get(Site, sid)
    if not s:
        fail("Site introuvable", 404)
    warn = sites.update_site(db, s, {"waf_enabled": data.waf_enabled})
    return ok(s.to_dict(), warn or ("WAF activé pour " + s.name if data.waf_enabled else "WAF désactivé pour " + s.name))


# ---------------------------------------------------------------- moteurs externes (BunkerWeb, SafeLine)
@router.get("/engines")
def engines():
    return ok(waf_engines.status())


class EngineInstallIn(BaseModel):
    web_http_port: int = 8080
    web_https_port: int = 8443
    ui_port: Optional[int] = None
    lets_encrypt: bool = False
    email: str = ""
    api_token: str = ""


@router.post("/engines/{engine}/install")
def engine_install(engine: str, data: EngineInstallIn):
    if engine not in ("bunkerweb", "safeline"):
        fail("Moteur inconnu", 404)
    for pnum in (data.web_http_port, data.web_https_port):
        if not (1024 <= pnum <= 65535):
            fail("Ports de repli invalides (1024 à 65535)")
    if data.web_http_port in (80, 443) or data.web_https_port in (80, 443) or data.web_http_port == data.web_https_port:
        fail("Les ports de repli doivent être différents de 80 / 443 et entre eux")
    try:
        tid = waf_engines.install(engine, data.model_dump())
    except ValueError as e:
        fail(str(e))
    return ok({"task_id": tid}, "Installation lancée")


@router.post("/engines/{engine}/uninstall")
def engine_uninstall(engine: str):
    try:
        tid = waf_engines.uninstall(engine)
    except ValueError as e:
        fail(str(e))
    return ok({"task_id": tid}, "Suppression lancée")


@router.post("/engines/{engine}/sync")
def engine_sync(engine: str, db: Session = DbDep):
    lines: list[str] = []
    try:
        err = waf_engines.sync(engine, db, lines.append)
    except (ValueError, RuntimeError) as e:
        fail(str(e))
    if err:
        fail(err)
    return ok({"log": lines}, "Sites synchronisés dans " + waf_engines.ENGINES[engine]["name"])


class EngineActionIn(BaseModel):
    action: str


@router.post("/engines/{engine}/action")
def engine_action(engine: str, data: EngineActionIn):
    try:
        err = waf_engines.action(engine, data.action)
    except ValueError as e:
        fail(str(e))
    if err:
        fail(err)
    return ok(msg="Action effectuée")


@router.get("/engines/{engine}/preview")
def engine_preview(engine: str, db: Session = DbDep):
    if engine == "bunkerweb":
        return ok({"content": waf_engines.bunkerweb_env(db)})
    if engine == "safeline":
        import json as _json

        return ok({"content": _json.dumps(waf_engines.safeline_sites_payload(db), indent=2, ensure_ascii=False)})
    fail("Moteur inconnu", 404)


class EngineSettingsIn(BaseModel):
    safeline_api_token: Optional[str] = None
    safeline_mgt_port: Optional[int] = None
    bunkerweb_ui_port: Optional[int] = None


@router.post("/engines/settings")
def engine_settings(data: EngineSettingsIn):
    values = {k: v for k, v in data.model_dump(exclude_unset=True).items() if v is not None}
    for k in ("safeline_mgt_port", "bunkerweb_ui_port"):
        if k in values and not (1 <= int(values[k]) <= 65535):
            fail("Port invalide")
    from toutpanel import config

    config.get_settings().update(values)
    return ok(msg="Réglages du moteur enregistrés")
