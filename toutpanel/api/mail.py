from __future__ import annotations
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.api.deps import current_user, fail, ok
from toutpanel.db import DbDep
from toutpanel.models import MailAlias, MailDomain, Mailbox
from toutpanel.services import mail

router = APIRouter(prefix="/api/mail", tags=["mail"], dependencies=[Depends(current_user)])


def _domain(db: Session, did: int) -> MailDomain:
    d = db.get(MailDomain, did)
    if not d:
        fail("Domaine introuvable", 404)
    return d


@router.get("")
def overview(db: Session = DbDep):
    domains = db.query(MailDomain).order_by(MailDomain.domain).all()
    by_id = {d.id: d.domain for d in domains}
    boxes = []
    for m in db.query(Mailbox).order_by(Mailbox.local_part).all():
        d = m.to_dict(by_id.get(m.domain_id, ""))
        d["usage"] = mail.mailbox_usage(by_id.get(m.domain_id, ""), m.local_part)
        boxes.append(d)
    return ok({"status": mail.status(), "domains": [d.to_dict() for d in domains], "mailboxes": boxes,
               "aliases": [a.to_dict() for a in db.query(MailAlias).order_by(MailAlias.source).all()]})


class DomainIn(BaseModel):
    domain: str
    dkim: bool = True


@router.post("/domains")
def add_domain(data: DomainIn, db: Session = DbDep):
    try:
        d = mail.add_domain(db, data.domain, data.dkim)
    except mail.MailError as e:
        fail(str(e))
    return ok(d.to_dict(), "Domaine ajouté — pensez à configurer les enregistrements DNS puis à appliquer.")


@router.delete("/domains/{did}")
def delete_domain(did: int, db: Session = DbDep):
    d = _domain(db, did)
    db.query(Mailbox).filter(Mailbox.domain_id == d.id).delete()
    db.query(MailAlias).filter(MailAlias.domain_id == d.id).delete()
    db.delete(d)
    return ok(msg="Domaine supprimé")


@router.post("/domains/{did}/dkim")
def regen_dkim(did: int, db: Session = DbDep):
    d = _domain(db, did)
    d.dkim_private_key, d.dkim_public_key = mail.generate_dkim()
    return ok(d.to_dict(), "Nouvelle clé DKIM générée")


@router.get("/domains/{did}/dns")
def dns(did: int, db: Session = DbDep):
    from toutpanel.services.system_info import _local_ip

    d = _domain(db, did)
    return ok(mail.dns_records(d, config.get_settings().get("mail_public_ip") or _local_ip()))


class MailboxIn(BaseModel):
    domain_id: int
    local_part: str
    password: str
    full_name: str = ""
    quota_mb: int = 1024


@router.post("/mailboxes")
def add_mailbox(data: MailboxIn, db: Session = DbDep):
    d = _domain(db, data.domain_id)
    try:
        m = mail.add_mailbox(db, d, data.local_part, data.password, data.full_name, data.quota_mb)
    except mail.MailError as e:
        fail(str(e))
    return ok(m.to_dict(d.domain), "Boîte créée")


class MailboxUpdate(BaseModel):
    password: Optional[str] = None
    full_name: Optional[str] = None
    quota_mb: Optional[int] = None
    enabled: Optional[bool] = None


@router.put("/mailboxes/{mid}")
def update_mailbox(mid: int, data: MailboxUpdate, db: Session = DbDep):
    m = db.get(Mailbox, mid)
    if not m:
        fail("Boîte introuvable", 404)
    if data.password:
        if len(data.password) < 8:
            fail("Mot de passe trop court (8 caractères minimum)")
        m.password_hash = mail.hash_password(data.password)
    if data.full_name is not None:
        m.full_name = data.full_name
    if data.quota_mb is not None:
        m.quota_mb = max(0, data.quota_mb)
    if data.enabled is not None:
        m.enabled = data.enabled
    return ok(m.to_dict(), "Boîte mise à jour")


@router.delete("/mailboxes/{mid}")
def delete_mailbox(mid: int, delete_files: bool = False, db: Session = DbDep):
    m = db.get(Mailbox, mid)
    if not m:
        fail("Boîte introuvable", 404)
    d = db.get(MailDomain, m.domain_id)
    if delete_files and d:
        import shutil

        shutil.rmtree(mail.vmail_dir() / d.domain / m.local_part, ignore_errors=True)
    db.delete(m)
    return ok(msg="Boîte supprimée")


class AliasIn(BaseModel):
    domain_id: int
    source: str
    destination: str


@router.post("/aliases")
def add_alias(data: AliasIn, db: Session = DbDep):
    d = _domain(db, data.domain_id)
    try:
        a = mail.add_alias(db, d, data.source, data.destination)
    except mail.MailError as e:
        fail(str(e))
    return ok(a.to_dict(), "Alias créé")


@router.delete("/aliases/{aid}")
def delete_alias(aid: int, db: Session = DbDep):
    a = db.get(MailAlias, aid)
    if not a:
        fail("Alias introuvable", 404)
    db.delete(a)
    return ok(msg="Alias supprimé")


@router.post("/apply")
def apply(db: Session = DbDep):
    try:
        warns = mail.apply(db)
    except Exception as e:
        fail(f"Échec : {e}")
    return ok({"warnings": warns}, "Configuration appliquée" + (" avec avertissements" if warns else ""))


@router.get("/preview")
def preview(db: Session = DbDep):
    st = mail.settings()
    return ok({"postfix_maps": mail.render_postfix_maps(db), "postfix_main": mail.render_postfix_main(st, bool(st["dkim_enabled"])),
               "dovecot": mail.render_dovecot_conf(st), "dovecot_users": mail.render_dovecot_users(db).replace("{SSHA512}", "{SSHA512}…")[:4000],
               "opendkim": mail.render_opendkim(db)})


class SettingsIn(BaseModel):
    mail_hostname: Optional[str] = None
    mail_public_ip: Optional[str] = None
    mail_dkim_enabled: Optional[bool] = None
    mail_ssl_cert: Optional[str] = None
    mail_ssl_key: Optional[str] = None
    mail_vmail_dir: Optional[str] = None


@router.post("/settings")
def update_settings(data: SettingsIn):
    values = {k: v for k, v in data.model_dump(exclude_unset=True).items() if v is not None}
    if "mail_hostname" in values and not mail.DOMAIN_RE.match(values["mail_hostname"].strip().lower()):
        fail("Nom d'hôte invalide")
    config.get_settings().update(values)
    return ok(mail.settings(), "Paramètres enregistrés — appliquez la configuration.")


@router.post("/ssl/self-signed")
def ssl_self_signed():
    cert, key = mail.self_signed_cert()
    return ok({"cert": cert, "key": key}, "Certificat auto-signé généré")


class SslFromSite(BaseModel):
    site_id: int


@router.post("/ssl/from-site")
def ssl_from_site(data: SslFromSite, db: Session = DbDep):
    from toutpanel.models import Site

    s = db.get(Site, data.site_id)
    if not s or not s.ssl_cert or not s.ssl_key:
        fail("Ce site n'a pas de certificat")
    config.get_settings().update({"mail_ssl_cert": s.ssl_cert, "mail_ssl_key": s.ssl_key})
    return ok(msg="Certificat du site utilisé pour le mail")


@router.get("/queue")
def queue():
    return ok(mail.queue())


class QueueAction(BaseModel):
    action: str
    id: str = ""


@router.post("/queue")
def queue_action(data: QueueAction):
    err = mail.queue_action(data.action, data.id)
    if err:
        fail(err)
    return ok(msg="OK")


@router.get("/log")
def mail_log(lines: int = 200):
    return ok({"content": mail.mail_log(min(lines, 2000))})


class TestIn(BaseModel):
    to: str


@router.post("/test")
def send_test(data: TestIn):
    err = mail.send_test(data.to)
    if err:
        fail("Envoi impossible : " + err)
    return ok(msg="Message de test remis à Postfix")


# ---------------------------------------------------------------- webmail (Roundcube)
from toutpanel.services import webmail  # noqa: E402


@router.get("/webmail")
def webmail_status(db: Session = DbDep):
    return ok(webmail.status(db))


class WebmailIn(BaseModel):
    domain: str
    db_engine: str = "auto"
    php_version: str = ""
    managesieve: bool = False


@router.post("/webmail/install")
def webmail_install(data: WebmailIn):
    try:
        tid = webmail.install(data.domain, data.db_engine, data.php_version, data.managesieve)
    except webmail.WebmailError as e:
        fail(str(e))
    return ok({"task_id": tid}, "Installation du webmail lancée")


class WebmailRemoveIn(BaseModel):
    delete_data: bool = False


@router.post("/webmail/uninstall")
def webmail_uninstall(data: WebmailRemoveIn):
    return ok({"task_id": webmail.uninstall(data.delete_data)}, "Suppression lancée")
