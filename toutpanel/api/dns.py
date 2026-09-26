from __future__ import annotations

import re
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.api.deps import current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import DnsRecord, DnsZone, Site
from toutpanel.services import dns

router = APIRouter(prefix="/api/dns", tags=["dns"], dependencies=[Depends(current_user)])


def _zone(db: Session, zid: int) -> DnsZone:
    z = db.get(DnsZone, zid)
    if not z:
        fail("Zone introuvable", 404)
    return z


@router.get("")
def overview(db: Session = DbDep):
    zones = []
    for z in db.query(DnsZone).order_by(DnsZone.domain).all():
        d = z.to_dict()
        d["records"] = db.query(DnsRecord).filter(DnsRecord.zone_id == z.id).count()
        zones.append(d)
    return ok({"status": dns.status(), "zones": zones, "types": dns.RECORD_TYPES,
               "sites": [{"id": s.id, "name": s.name, "domains": s.domains or []} for s in db.query(Site).order_by(Site.name).all()]})


class ZoneIn(BaseModel):
    domain: str = ""
    ip: str = ""
    provider: str = "bind"
    with_mail: bool = True
    with_www: bool = True
    site_id: Optional[int] = None


@router.post("/zones")
def create_zone(data: ZoneIn, db: Session = DbDep):
    try:
        if data.site_id:
            site = db.get(Site, data.site_id)
            if not site:
                fail("Site introuvable", 404)
            z = dns.zone_from_site(db, site, data.ip)
            if data.provider == "cloudflare":
                z.provider = "cloudflare"
        else:
            z = dns.create_zone(db, data.domain, data.ip, data.provider, data.with_mail, data.with_www)
    except dns.DnsError as e:
        fail(str(e))
    return ok(z.to_dict(), "Zone créée — appliquez pour la servir.")


@router.get("/zones/{zid}")
def zone_detail(zid: int, db: Session = DbDep):
    z = _zone(db, zid)
    recs = db.query(DnsRecord).filter(DnsRecord.zone_id == z.id).order_by(DnsRecord.type, DnsRecord.name).all()
    return ok({"zone": z.to_dict(), "records": [r.to_dict() for r in recs], "file": dns.render_zone(z, recs)})


class ZoneUpdate(BaseModel):
    ttl: Optional[int] = None
    admin_email: Optional[str] = None
    enabled: Optional[bool] = None
    provider: Optional[str] = None


@router.put("/zones/{zid}")
def update_zone(zid: int, data: ZoneUpdate, db: Session = DbDep):
    z = _zone(db, zid)
    if data.ttl is not None:
        if not (60 <= data.ttl <= 604800):
            fail("TTL invalide (60 à 604800 s)")
        z.ttl = data.ttl
    if data.admin_email is not None:
        email = data.admin_email.strip()
        if email and not re.fullmatch(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", email):
            fail("E-mail administrateur invalide")
        z.admin_email = email
    if data.enabled is not None:
        z.enabled = data.enabled
    if data.provider is not None:
        if data.provider not in ("bind", "cloudflare"):
            fail("Fournisseur invalide")
        z.provider = data.provider
    return ok(z.to_dict(), "Zone mise à jour")


@router.delete("/zones/{zid}")
def delete_zone(zid: int, db: Session = DbDep):
    z = _zone(db, zid)
    db.query(DnsRecord).filter(DnsRecord.zone_id == z.id).delete()
    db.delete(z)
    p = dns.dns_dir() / f"db.{z.domain}"
    if p.exists():
        p.unlink()
    return ok(msg="Zone supprimée — appliquez pour mettre à jour le serveur.")


class RecordIn(BaseModel):
    type: str
    name: str = "@"
    value: str
    ttl: int = 0
    priority: int = 0
    remark: str = ""
    enabled: bool = True


@router.post("/zones/{zid}/records")
def add_record(zid: int, data: RecordIn, db: Session = DbDep):
    z = _zone(db, zid)
    try:
        r = dns.add_record(db, z, data.type, data.name, data.value, data.ttl, data.priority, data.remark)
    except dns.DnsError as e:
        fail(str(e))
    return ok(r.to_dict(), "Enregistrement ajouté")


class RecordUpdate(BaseModel):
    type: Optional[str] = None
    name: Optional[str] = None
    value: Optional[str] = None
    ttl: Optional[int] = None
    priority: Optional[int] = None
    remark: Optional[str] = None
    enabled: Optional[bool] = None


@router.put("/zones/{zid}/records/{rid}")
def update_record(zid: int, rid: int, data: RecordUpdate, db: Session = DbDep):
    z = _zone(db, zid)
    r = db.get(DnsRecord, rid)
    if not r or r.zone_id != z.id:
        fail("Enregistrement introuvable", 404)
    try:
        dns.update_record(db, z, r, **data.model_dump(exclude_unset=True))
    except dns.DnsError as e:
        fail(str(e))
    return ok(r.to_dict(), "Enregistrement mis à jour")


@router.delete("/zones/{zid}/records/{rid}")
def delete_record(zid: int, rid: int, db: Session = DbDep):
    z = _zone(db, zid)
    r = db.get(DnsRecord, rid)
    if not r or r.zone_id != z.id:
        fail("Enregistrement introuvable", 404)
    db.delete(r)
    return ok(msg="Enregistrement supprimé")


@router.post("/apply")
def apply(db: Session = DbDep):
    res, err = dns.apply(db)
    if err:
        fail(err)
    n = len(res["written"])
    return ok(res, f"{n} zone(s) écrite(s), serveur DNS rechargé" if n else "Aucune zone BIND à servir")


@router.get("/zones/{zid}/check")
def check_zone(zid: int, db: Session = DbDep):
    return ok(dns.check(db, _zone(db, zid)))


class DnsSettingsIn(BaseModel):
    dns_ns1: Optional[str] = None
    dns_ns2: Optional[str] = None
    dns_admin_email: Optional[str] = None
    dns_default_ttl: Optional[int] = None
    cloudflare_token: Optional[str] = None
    cloudflare_proxied: Optional[bool] = None


@router.post("/settings")
def update_settings(data: DnsSettingsIn):
    values = {k: v for k, v in data.model_dump(exclude_unset=True).items() if v is not None}
    for k in ("dns_ns1", "dns_ns2"):
        if k in values:
            values[k] = str(values[k]).strip().lower().rstrip(".")
            if values[k] and not dns.DOMAIN_RE.match(values[k]):
                fail("Nom de serveur DNS invalide")
    if "dns_default_ttl" in values and not (60 <= int(values["dns_default_ttl"]) <= 604800):
        fail("TTL invalide (60 à 604800 s)")
    if "cloudflare_token" in values:
        values["cloudflare_token"] = str(values["cloudflare_token"]).strip()
        if values["cloudflare_token"] and not re.fullmatch(r"[A-Za-z0-9_.-]{20,200}", values["cloudflare_token"]):
            fail("Jeton Cloudflare invalide")
    if values.get("dns_admin_email") and not re.fullmatch(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", str(values["dns_admin_email"])):
        fail("E-mail administrateur invalide")
    config.get_settings().update(values)
    return ok(dns.settings(), "Réglages DNS enregistrés")


# ---------------------------------------------------------------- Cloudflare
@router.get("/cloudflare/zones")
def cloudflare_zones():
    try:
        return ok(dns.cf_zones())
    except dns.DnsError as e:
        fail(str(e))


class CfImportIn(BaseModel):
    zone_id: str
    name: str


@router.post("/cloudflare/import")
def cloudflare_import(data: CfImportIn, db: Session = DbDep):
    try:
        z = dns.cf_import(db, {"id": data.zone_id, "name": data.name})
    except dns.DnsError as e:
        fail(str(e))
    return ok(z.to_dict(), "Zone importée depuis Cloudflare")


@router.post("/zones/{zid}/push")
def cloudflare_push(zid: int, db: Session = DbDep):
    z = _zone(db, zid)
    try:
        res = dns.cf_push(db, z)
    except dns.DnsError as e:
        fail(str(e))
    return ok(res, f"Cloudflare : {res['created']} créé(s), {res['updated']} mis à jour")
