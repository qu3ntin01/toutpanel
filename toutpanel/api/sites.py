from __future__ import annotations
from typing import Optional

from pathlib import Path

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.api.deps import current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import Site
from toutpanel.services import sites, ssl, tasks, webserver, wordpress

router = APIRouter(prefix="/api/sites", tags=["sites"], dependencies=[Depends(current_user)])


class SiteIn(BaseModel):
    name: str
    domains: list[str]
    root: str = ""
    php_version: str = ""
    site_type: str = "php"
    proxy_target: str = ""
    remark: str = ""
    php_isolation: bool = True


class SiteUpdate(BaseModel):
    domains: Optional[list[str]] = None
    php_version: Optional[str] = None
    site_type: Optional[str] = None
    proxy_target: Optional[str] = None
    remark: Optional[str] = None
    force_https: Optional[bool] = None
    enabled: Optional[bool] = None
    root: Optional[str] = None
    waf_enabled: Optional[bool] = None
    php_isolation: Optional[bool] = None
    upstreams: Optional[list] = None
    lb_method: Optional[str] = None
    lb_keepalive: Optional[int] = None


def _get(db: Session, site_id: int) -> Site:
    s = db.get(Site, site_id)
    if not s:
        fail("Site introuvable", 404)
    return s


@router.get("")
def list_sites(db: Session = DbDep):
    from toutpanel.models import GitDeploy

    rows = db.query(Site).order_by(Site.id.desc()).all()
    gits = {g.site_id: {"branch": g.branch, "last_commit": g.last_commit, "last_status": g.last_status, "auto_minutes": g.auto_minutes} for g in db.query(GitDeploy).all()}
    out = []
    for s in rows:
        d = s.to_dict()
        d["ssl_info"] = ssl.cert_info(s.ssl_cert) if s.ssl_enabled and s.ssl_cert else None
        d["wordpress"] = wordpress.detect(s.root)
        d["git"] = gits.get(s.id)
        out.append(d)
    return ok({"sites": out, "webserver": webserver.detect(), "webserver_installed": webserver.is_installed(),
               "php_versions": webserver.php_versions(), "www_root": str(config.WWW_ROOT)})


@router.post("")
def create(data: SiteIn, db: Session = DbDep):
    try:
        site, warn = sites.create_site(db, data.name, data.domains, data.root, data.php_version, data.site_type,
                                       data.proxy_target, data.remark, php_isolation=data.php_isolation)
    except sites.SiteError as e:
        fail(str(e))
    return ok(site.to_dict(), warn or "Site créé")


@router.put("/{site_id}")
def update(site_id: int, data: SiteUpdate, db: Session = DbDep):
    site = _get(db, site_id)
    try:
        warn = sites.update_site(db, site, data.model_dump(exclude_unset=True))
    except sites.SiteError as e:
        fail(str(e))
    return ok(site.to_dict(), warn or "Site mis à jour")


@router.get("/{site_id}/upstreams/check")
def upstreams_check(site_id: int, db: Session = DbDep):
    """État de chaque serveur du groupe de répartition (code HTTP, latence)."""
    from toutpanel.services import loadbalancer

    site = _get(db, site_id)
    d = site.to_dict()
    if not d["upstreams"] and site.proxy_target:
        d["upstreams"] = [{"url": site.proxy_target, "weight": 1, "backup": False}]
    return ok({"servers": loadbalancer.check_site(d), "method": d["lb_method"], "methods": loadbalancer.METHOD_LABELS})


@router.delete("/{site_id}")
def delete(site_id: int, delete_files: bool = False, db: Session = DbDep):
    site = _get(db, site_id)
    warn = sites.delete_site(db, site, delete_files)
    return ok(msg=warn or "Site supprimé")


@router.get("/{site_id}/config")
def get_config(site_id: int, db: Session = DbDep):
    site = _get(db, site_id)
    custom = sites.custom_config_path(site)
    return ok({"generated": sites.get_rendered_config(site), "custom": custom.read_text(encoding="utf-8") if custom.exists() else "",
               "custom_path": str(custom), "webserver": webserver.detect()})


class CustomConfigIn(BaseModel):
    content: str


@router.post("/{site_id}/config")
def set_custom_config(site_id: int, data: CustomConfigIn, db: Session = DbDep):
    site = _get(db, site_id)
    p = sites.custom_config_path(site)
    p.write_text(data.content, encoding="utf-8")
    warn = sites.update_site(db, site, {})
    return ok(msg=warn or "Configuration enregistrée")


# ----------------------------------------------------------------------------- SSL
class SslSelfSigned(BaseModel):
    force_https: bool = False


@router.post("/{site_id}/ssl/self-signed")
def ssl_self_signed(site_id: int, data: SslSelfSigned, db: Session = DbDep):
    site = _get(db, site_id)
    cert, key = ssl.self_signed(site.domains or [site.name], ssl.site_ssl_dir(site.name))
    try:
        warn = sites.update_site(db, site, {"ssl_enabled": True, "ssl_cert": str(cert), "ssl_key": str(key),
                                            "force_https": data.force_https})
    except sites.SiteError as e:
        fail(str(e))
    return ok(site.to_dict(), warn or "Certificat auto-signé installé")


class SslManual(BaseModel):
    cert: str
    key: str
    force_https: bool = False


@router.post("/{site_id}/ssl/manual")
def ssl_manual(site_id: int, data: SslManual, db: Session = DbDep):
    site = _get(db, site_id)
    d = ssl.site_ssl_dir(site.name)
    cert, key = d / "fullchain.pem", d / "privkey.pem"
    cert.write_text(data.cert.strip() + "\n", encoding="utf-8")
    key.write_text(data.key.strip() + "\n", encoding="utf-8")
    info = ssl.cert_info(str(cert))
    if info.get("error"):
        fail("Certificat invalide : " + info["error"])
    try:
        warn = sites.update_site(db, site, {"ssl_enabled": True, "ssl_cert": str(cert), "ssl_key": str(key),
                                            "force_https": data.force_https})
    except sites.SiteError as e:
        fail(str(e))
    return ok(site.to_dict(), warn or "Certificat installé")


class SslLE(BaseModel):
    email: str = ""
    force_https: bool = True


@router.post("/{site_id}/ssl/letsencrypt")
def ssl_letsencrypt(site_id: int, data: SslLE, db: Session = DbDep):
    site = _get(db, site_id)
    sid, domains, root, name = site.id, list(site.domains or []), site.root, site.name

    def _job(log):
        from toutpanel.db import session_scope

        try:
            cert, key = ssl.letsencrypt(domains, root, data.email, log)
        except ssl.SslError as e:
            log(str(e))
            return 1
        with session_scope() as s:
            st = s.get(Site, sid)
            warn = sites.update_site(s, st, {"ssl_enabled": True, "ssl_cert": str(cert), "ssl_key": str(key),
                                             "force_https": data.force_https})
        log(warn or f"Certificat Let's Encrypt installé pour {name}")
        return 0

    tid = tasks.run_in_background(f"Let's Encrypt {name}", _job)
    return ok({"task_id": tid}, "Demande de certificat lancée")


@router.post("/{site_id}/ssl/disable")
def ssl_disable(site_id: int, db: Session = DbDep):
    site = _get(db, site_id)
    warn = sites.update_site(db, site, {"ssl_enabled": False, "force_https": False})
    return ok(site.to_dict(), warn or "SSL désactivé")


@router.get("/{site_id}/ssl")
def ssl_info(site_id: int, db: Session = DbDep):
    site = _get(db, site_id)
    return ok({"enabled": site.ssl_enabled, "info": ssl.cert_info(site.ssl_cert) if site.ssl_cert else None,
               "certbot": ssl.certbot_available(), "force_https": site.force_https})


# ----------------------------------------------------------------------------- WordPress
class WpInstall(BaseModel):
    lang: str = "fr"
    db_engine: str = "mysql"
    db_name: str = ""
    db_user: str = ""
    db_password: str = ""
    table_prefix: str = "wp_"


@router.post("/{site_id}/wordpress")
def wp_install(site_id: int, data: WpInstall, db: Session = DbDep):
    site = _get(db, site_id)
    try:
        tid = wordpress.install(site.id, data.lang, data.db_engine, data.db_name, data.db_user, data.db_password, data.table_prefix)
    except ValueError as e:
        fail(str(e))
    return ok({"task_id": tid}, "Installation WordPress lancée")


@router.get("/domains/all")
def all_domains(db: Session = DbDep):
    out = []
    for s in db.query(Site).all():
        for d in s.domains or []:
            out.append({"domain": d, "site": s.name, "site_id": s.id, "ssl": s.ssl_enabled, "enabled": s.enabled})
    out.sort(key=lambda x: x["domain"])
    return ok(out)


@router.get("/webserver/test")
def webserver_test():
    a = webserver.get_adapter()
    r = a.test()
    return ok({"webserver": a.name, "ok": r.ok, "output": r.output})


@router.post("/webserver/reload")
def webserver_reload():
    a = webserver.get_adapter()
    r = a.reload()
    if not r.ok:
        fail(r.output or "échec")
    return ok(msg=f"{a.name} rechargé")
