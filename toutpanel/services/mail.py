"""Serveur mail : Postfix + Dovecot (Linux) pilotés par le panel, DKIM, DNS, file d'attente.

Le panel est la source de vérité (domaines, boîtes, alias en base). `apply()` régénère :
  - les tables Postfix (domaines, boîtes, alias) + main.cf via postconf
  - la configuration Dovecot (auth passwd-file, LMTP, SSL)
  - OpenDKIM (clés, KeyTable, SigningTable)
puis recharge les services.
"""
from __future__ import annotations

import base64
import hashlib
import os
import re
import secrets
import socket
from pathlib import Path

from toutpanel import config
from toutpanel.db import session_scope
from toutpanel.models import MailAlias, MailDomain, Mailbox
from toutpanel.platform import get_platform

VMAIL_UID = 5000
DOMAIN_RE = re.compile(r"^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$")
LOCAL_RE = re.compile(r"^[a-z0-9._%+-]{1,64}$")


class MailError(ValueError):
    pass


# --------------------------------------------------------------------------- chemins & état

def postfix_dir() -> Path:
    return Path("/etc/postfix") if Path("/etc/postfix").is_dir() else config.HOME / "mail" / "postfix"


def dovecot_dir() -> Path:
    return Path("/etc/dovecot") if Path("/etc/dovecot").is_dir() else config.HOME / "mail" / "dovecot"


def opendkim_dir() -> Path:
    return Path("/etc/opendkim") if Path("/etc/opendkim").is_dir() or Path("/etc/opendkim.conf").exists() else config.HOME / "mail" / "opendkim"


def vmail_dir() -> Path:
    return Path(config.get_settings().get("mail_vmail_dir") or ("/var/vmail" if not config.IS_WINDOWS else str(config.HOME / "mail" / "vmail")))


def settings() -> dict:
    s = config.get_settings()
    return {
        "hostname": s.get("mail_hostname") or f"mail.{socket.getfqdn() if '.' in socket.getfqdn() else socket.gethostname()}",
        "ssl_cert": s.get("mail_ssl_cert") or "", "ssl_key": s.get("mail_ssl_key") or "",
        "vmail_dir": str(vmail_dir()), "dkim_enabled": s.get("mail_dkim_enabled", True),
        "smtp_port": 25, "submission_port": 587, "imap_port": 993, "pop3_port": 995,
    }


def status() -> dict:
    plat = get_platform()
    supported = not config.IS_WINDOWS
    postfix = bool(plat.which("postfix") or plat.which("postconf") or Path("/usr/sbin/postfix").exists())
    dovecot = bool(plat.which("dovecot") or Path("/usr/sbin/dovecot").exists())
    opendkim = bool(plat.which("opendkim") or Path("/usr/sbin/opendkim").exists())
    return {
        "supported": supported, "postfix": {"installed": postfix, "status": plat.service_status("postfix") if postfix else "missing"},
        "dovecot": {"installed": dovecot, "status": plat.service_status("dovecot") if dovecot else "missing"},
        "opendkim": {"installed": opendkim, "status": plat.service_status("opendkim") if opendkim else "missing"},
        "settings": settings(), "ports": _listening_mail_ports(),
    }


def _listening_mail_ports() -> dict:
    import psutil

    out = {25: False, 587: False, 465: False, 143: False, 993: False, 110: False, 995: False}
    try:
        for c in psutil.net_connections(kind="inet"):
            if c.status == psutil.CONN_LISTEN and c.laddr and c.laddr.port in out:
                out[c.laddr.port] = True
    except (psutil.AccessDenied, OSError):
        pass
    return {str(k): v for k, v in out.items()}


# --------------------------------------------------------------------------- mots de passe

def hash_password(password: str) -> str:
    """Format Dovecot {SSHA512} : base64(sha512(mdp + sel) + sel)."""
    salt = secrets.token_bytes(16)
    digest = hashlib.sha512(password.encode("utf-8") + salt).digest()
    return "{SSHA512}" + base64.b64encode(digest + salt).decode("ascii")


def verify_password(password: str, stored: str) -> bool:
    if not stored.startswith("{SSHA512}"):
        return False
    raw = base64.b64decode(stored[9:])
    digest, salt = raw[:64], raw[64:]
    return hashlib.sha512(password.encode("utf-8") + salt).digest() == digest


# --------------------------------------------------------------------------- DKIM

def generate_dkim() -> tuple[str, str]:
    """Retourne (clé privée PEM, clé publique base64 DER pour l'enregistrement DNS)."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    priv = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()).decode()
    pub_der = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return priv, base64.b64encode(pub_der).decode("ascii")


def dns_records(domain: MailDomain, server_ip: str) -> list[dict]:
    st = settings()
    host = st["hostname"]
    recs = [
        {"type": "A", "name": host, "value": server_ip, "note": "Hôte du serveur mail"},
        {"type": "MX", "name": domain.domain, "value": f"10 {host}.", "note": "Réception du courrier"},
        {"type": "TXT", "name": domain.domain, "value": f"v=spf1 mx a:{host} ip4:{server_ip} ~all", "note": "SPF"},
        {"type": "TXT", "name": f"_dmarc.{domain.domain}", "value": f"v=DMARC1; p=quarantine; rua=mailto:postmaster@{domain.domain}", "note": "DMARC"},
        {"type": "PTR", "name": server_ip, "value": f"{host}.", "note": "DNS inverse (chez votre hébergeur)"},
    ]
    if domain.dkim_public_key:
        recs.insert(3, {"type": "TXT", "name": f"{domain.dkim_selector}._domainkey.{domain.domain}",
                        "value": f"v=DKIM1; k=rsa; p={domain.dkim_public_key}", "note": "DKIM"})
    return recs


# --------------------------------------------------------------------------- CRUD

def add_domain(db, domain: str, dkim: bool = True) -> MailDomain:
    domain = domain.strip().lower().rstrip(".")
    if not DOMAIN_RE.match(domain):
        raise MailError("Domaine invalide")
    if db.query(MailDomain).filter(MailDomain.domain == domain).first():
        raise MailError("Domaine déjà présent")
    d = MailDomain(domain=domain)
    if dkim:
        d.dkim_private_key, d.dkim_public_key = generate_dkim()
    db.add(d)
    db.flush()
    return d


def add_mailbox(db, domain: MailDomain, local_part: str, password: str, full_name: str = "", quota_mb: int = 1024) -> Mailbox:
    local_part = local_part.strip().lower()
    if not LOCAL_RE.match(local_part):
        raise MailError("Nom de boîte invalide")
    if len(password) < 8:
        raise MailError("Mot de passe trop court (8 caractères minimum)")
    if db.query(Mailbox).filter(Mailbox.domain_id == domain.id, Mailbox.local_part == local_part).first():
        raise MailError("Cette boîte existe déjà")
    m = Mailbox(domain_id=domain.id, local_part=local_part, password_hash=hash_password(password), full_name=full_name,
                quota_mb=max(0, int(quota_mb or 0)))
    db.add(m)
    db.flush()
    return m


def add_alias(db, domain: MailDomain, source: str, destination: str) -> MailAlias:
    source = source.strip().lower()
    if source.startswith("@"):
        source = "@" + domain.domain
    elif "@" not in source:
        source = f"{source}@{domain.domain}"
    if not source.endswith("@" + domain.domain):
        raise MailError("La source doit appartenir au domaine " + domain.domain)
    dests = [x.strip().lower() for x in re.split(r"[,\s;]+", destination) if x.strip()]
    if not dests or any("@" not in x for x in dests):
        raise MailError("Destination(s) invalide(s)")
    if db.query(MailAlias).filter(MailAlias.source == source).first():
        raise MailError("Alias déjà existant")
    a = MailAlias(domain_id=domain.id, source=source, destination=", ".join(dests))
    db.add(a)
    db.flush()
    return a


# --------------------------------------------------------------------------- génération de configuration

def render_postfix_maps(db) -> dict[str, str]:
    domains = db.query(MailDomain).filter(MailDomain.enabled.is_(True)).all()
    by_id = {d.id: d for d in domains}
    vdomains = "\n".join(f"{d.domain}\tOK" for d in domains) + "\n"
    vmailbox = "\n".join(f"{m.local_part}@{by_id[m.domain_id].domain}\t{by_id[m.domain_id].domain}/{m.local_part}/"
                         for m in db.query(Mailbox).filter(Mailbox.enabled.is_(True)).all() if m.domain_id in by_id) + "\n"
    valias = "\n".join(f"{a.source}\t{a.destination}" for a in db.query(MailAlias).filter(MailAlias.enabled.is_(True)).all()
                       if a.domain_id in by_id) + "\n"
    return {"virtual_domains": vdomains, "virtual_mailboxes": vmailbox, "virtual_aliases": valias}


def render_dovecot_users(db) -> str:
    by_id = {d.id: d for d in db.query(MailDomain).filter(MailDomain.enabled.is_(True)).all()}
    vd = vmail_dir()
    lines = []
    for m in db.query(Mailbox).filter(Mailbox.enabled.is_(True)).all():
        if m.domain_id not in by_id:
            continue
        dom = by_id[m.domain_id].domain
        quota = f"userdb_quota_rule=*:storage={m.quota_mb}M" if m.quota_mb else ""
        lines.append(f"{m.local_part}@{dom}:{m.password_hash}:{VMAIL_UID}:{VMAIL_UID}::{vd}/{dom}/{m.local_part}::{quota}")
    return "\n".join(lines) + "\n"


def _ipv6() -> bool:
    from toutpanel.services.webserver import ipv6_available

    return ipv6_available()


def render_postfix_main(st: dict, dkim: bool) -> dict[str, str]:
    pdir = str(postfix_dir())
    conf = {
        "myhostname": st["hostname"], "smtpd_banner": "$myhostname ESMTP", "biff": "no", "append_dot_mydomain": "no",
        "mydestination": "localhost", "inet_interfaces": "all", "inet_protocols": "all" if _ipv6() else "ipv4",
        "virtual_mailbox_domains": f"hash:{pdir}/toutpanel/virtual_domains",
        "virtual_mailbox_maps": f"hash:{pdir}/toutpanel/virtual_mailboxes",
        "virtual_alias_maps": f"hash:{pdir}/toutpanel/virtual_aliases",
        "virtual_mailbox_base": str(vmail_dir()), "virtual_uid_maps": f"static:{VMAIL_UID}", "virtual_gid_maps": f"static:{VMAIL_UID}",
        "virtual_transport": "lmtp:unix:private/dovecot-lmtp",
        "smtpd_sasl_type": "dovecot", "smtpd_sasl_path": "private/auth", "smtpd_sasl_auth_enable": "yes",
        "smtpd_sasl_security_options": "noanonymous", "broken_sasl_auth_clients": "yes",
        "smtpd_recipient_restrictions": "permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination, reject_unknown_recipient_domain, reject_rbl_client zen.spamhaus.org",
        "smtpd_helo_required": "yes", "disable_vrfy_command": "yes", "message_size_limit": "52428800", "mailbox_size_limit": "0",
        "smtpd_tls_security_level": "may", "smtp_tls_security_level": "may", "smtpd_tls_auth_only": "yes",
        "smtpd_tls_protocols": "!SSLv2, !SSLv3, !TLSv1, !TLSv1.1", "smtp_tls_protocols": "!SSLv2, !SSLv3, !TLSv1, !TLSv1.1",
    }
    if st["ssl_cert"] and st["ssl_key"]:
        conf["smtpd_tls_cert_file"] = st["ssl_cert"]
        conf["smtpd_tls_key_file"] = st["ssl_key"]
    if dkim:
        conf.update({"milter_default_action": "accept", "milter_protocol": "6", "smtpd_milters": "inet:127.0.0.1:8891",
                     "non_smtpd_milters": "inet:127.0.0.1:8891"})
    else:
        conf.update({"smtpd_milters": "", "non_smtpd_milters": ""})
    return conf


def render_dovecot_conf(st: dict) -> str:
    vd = str(vmail_dir())
    ssl = f"ssl = required\nssl_cert = <{st['ssl_cert']}\nssl_key = <{st['ssl_key']}\n" if st["ssl_cert"] and st["ssl_key"] else "ssl = no\n"
    return f"""# Généré par ToutPanel - ne pas modifier à la main
protocols = imap pop3 lmtp
listen = {"*, ::" if _ipv6() else "*"}
mail_location = maildir:{vd}/%d/%n/Maildir
mail_uid = {VMAIL_UID}
mail_gid = {VMAIL_UID}
first_valid_uid = {VMAIL_UID}
last_valid_uid = {VMAIL_UID}
mail_privileged_group = mail
disable_plaintext_auth = yes
auth_mechanisms = plain login
{ssl}ssl_min_protocol = TLSv1.2
mail_plugins = $mail_plugins quota
passdb {{
  driver = passwd-file
  args = scheme=SSHA512 username_format=%u {dovecot_dir()}/toutpanel-users
}}
userdb {{
  driver = passwd-file
  args = username_format=%u {dovecot_dir()}/toutpanel-users
  default_fields = uid={VMAIL_UID} gid={VMAIL_UID} home={vd}/%d/%n
}}
service lmtp {{
  unix_listener /var/spool/postfix/private/dovecot-lmtp {{
    mode = 0600
    user = postfix
    group = postfix
  }}
}}
service auth {{
  unix_listener /var/spool/postfix/private/auth {{
    mode = 0660
    user = postfix
    group = postfix
  }}
  unix_listener auth-userdb {{
    mode = 0600
    user = vmail
  }}
}}
service imap-login {{
  inet_listener imap {{
    port = 143
  }}
  inet_listener imaps {{
    port = 993
    ssl = yes
  }}
}}
service pop3-login {{
  inet_listener pop3 {{
    port = 110
  }}
  inet_listener pop3s {{
    port = 995
    ssl = yes
  }}
}}
protocol imap {{
  mail_plugins = $mail_plugins imap_quota
}}
plugin {{
  quota = maildir:User quota
  quota_grace = 10%%
}}
namespace inbox {{
  inbox = yes
  mailbox Drafts {{
    auto = subscribe
    special_use = \\Drafts
  }}
  mailbox Junk {{
    auto = subscribe
    special_use = \\Junk
  }}
  mailbox Sent {{
    auto = subscribe
    special_use = \\Sent
  }}
  mailbox Trash {{
    auto = subscribe
    special_use = \\Trash
  }}
}}
"""


def render_opendkim(db) -> dict[str, str]:
    d_dir = opendkim_dir()
    domains = db.query(MailDomain).filter(MailDomain.enabled.is_(True), MailDomain.dkim_private_key != "").all()
    key_table = "\n".join(f"{d.dkim_selector}._domainkey.{d.domain} {d.domain}:{d.dkim_selector}:{d_dir}/keys/{d.domain}/{d.dkim_selector}.private" for d in domains) + "\n"
    signing = "\n".join(f"*@{d.domain} {d.dkim_selector}._domainkey.{d.domain}" for d in domains) + "\n"
    trusted = "127.0.0.1\nlocalhost\n::1\n"
    conf = f"""# Généré par ToutPanel
Syslog yes
UMask 007
Mode sv
Canonicalization relaxed/simple
SubDomains no
AutoRestart yes
Background yes
DNSTimeout 5
SignatureAlgorithm rsa-sha256
OversignHeaders From
Socket inet:8891@127.0.0.1
PidFile /run/opendkim/opendkim.pid
UserID opendkim
KeyTable {d_dir}/key.table
SigningTable refile:{d_dir}/signing.table
ExternalIgnoreList {d_dir}/trusted.hosts
InternalHosts {d_dir}/trusted.hosts
"""
    return {"key.table": key_table, "signing.table": signing, "trusted.hosts": trusted, "opendkim.conf": conf}


def write_configs(db) -> dict:
    """Écrit tous les fichiers de configuration. Retourne les chemins écrits."""
    st = settings()
    written = {}
    pdir = postfix_dir() / "toutpanel"
    pdir.mkdir(parents=True, exist_ok=True)
    for name, content in render_postfix_maps(db).items():
        (pdir / name).write_text(content, encoding="utf-8")
        written[name] = str(pdir / name)
    ddir = dovecot_dir()
    ddir.mkdir(parents=True, exist_ok=True)
    users = ddir / "toutpanel-users"
    users.write_text(render_dovecot_users(db), encoding="utf-8")
    try:
        os.chmod(users, 0o640)
    except OSError:
        pass
    written["dovecot_users"] = str(users)
    conf_d = ddir / "conf.d"
    conf_d.mkdir(parents=True, exist_ok=True)
    dconf = conf_d / "99-toutpanel.conf"
    dconf.write_text(render_dovecot_conf(st), encoding="utf-8")
    written["dovecot_conf"] = str(dconf)
    # OpenDKIM
    odir = opendkim_dir()
    (odir / "keys").mkdir(parents=True, exist_ok=True)
    for d in db.query(MailDomain).filter(MailDomain.dkim_private_key != "").all():
        kd = odir / "keys" / d.domain
        kd.mkdir(parents=True, exist_ok=True)
        kp = kd / f"{d.dkim_selector}.private"
        kp.write_text(d.dkim_private_key, encoding="utf-8")
        try:
            os.chmod(kp, 0o600)
        except OSError:
            pass
    for name, content in render_opendkim(db).items():
        target = (Path("/etc/opendkim.conf") if name == "opendkim.conf" and Path("/etc/opendkim.conf").exists() else odir / name)
        target.write_text(content, encoding="utf-8")
        written[name] = str(target)
    written["postfix_main"] = render_postfix_main(st, bool(st["dkim_enabled"]))
    return written


def ensure_vmail_user() -> None:
    if config.IS_WINDOWS:
        return
    plat = get_platform()
    vd = vmail_dir()
    vd.mkdir(parents=True, exist_ok=True)
    if plat.is_admin():
        plat.run(["groupadd", "-g", str(VMAIL_UID), "vmail"], timeout=15)
        plat.run(["useradd", "-r", "-u", str(VMAIL_UID), "-g", str(VMAIL_UID), "-d", str(vd), "-s", "/usr/sbin/nologin", "vmail"], timeout=15)
        plat.run(["chown", "-R", "vmail:vmail", str(vd)], timeout=60)
        plat.run(["chown", "-R", "opendkim:opendkim", str(opendkim_dir() / "keys")], timeout=30)
        users = dovecot_dir() / "toutpanel-users"
        if users.exists():
            plat.run(["chown", "root:dovecot", str(users)], timeout=15)


def apply(db) -> list[str]:
    """Écrit la configuration et recharge Postfix / Dovecot / OpenDKIM. Retourne les avertissements."""
    warns: list[str] = []
    written = write_configs(db)
    ensure_vmail_user()
    plat = get_platform()
    st = status()
    if not st["supported"]:
        warns.append("Serveur mail non pris en charge sous Windows (configuration générée uniquement).")
        return warns
    if st["postfix"]["installed"]:
        for k, v in written["postfix_main"].items():
            plat.run(["postconf", "-e", f"{k}={v}"], timeout=15)
        # submission (587) et smtps (465) dans master.cf
        plat.run(["postconf", "-M", "submission/inet=submission inet n - y - - smtpd -o syslog_name=postfix/submission -o smtpd_tls_security_level=encrypt -o smtpd_sasl_auth_enable=yes -o smtpd_client_restrictions=permit_sasl_authenticated,reject"], timeout=15)
        plat.run(["postconf", "-M", "smtps/inet=smtps inet n - y - - smtpd -o syslog_name=postfix/smtps -o smtpd_tls_wrappermode=yes -o smtpd_sasl_auth_enable=yes -o smtpd_client_restrictions=permit_sasl_authenticated,reject"], timeout=15)
        for name in ("virtual_domains", "virtual_mailboxes", "virtual_aliases"):
            r = plat.run(["postmap", str(postfix_dir() / "toutpanel" / name)], timeout=30)
            if not r.ok:
                warns.append(f"postmap {name} : {r.output[:200]}")
        r = plat.service_action("postfix", "restart")
        if not r.ok:
            warns.append("Postfix : " + r.output[:300])
    else:
        warns.append("Postfix n'est pas installé (Logiciels → Serveur mail).")
    if st["dovecot"]["installed"]:
        r = plat.service_action("dovecot", "restart")
        if not r.ok:
            warns.append("Dovecot : " + r.output[:300])
    else:
        warns.append("Dovecot n'est pas installé (Logiciels → Serveur mail).")
    if settings()["dkim_enabled"]:
        if st["opendkim"]["installed"]:
            r = plat.service_action("opendkim", "restart")
            if not r.ok:
                warns.append("OpenDKIM : " + r.output[:300])
        else:
            warns.append("OpenDKIM n'est pas installé : les mails ne seront pas signés DKIM.")
    return warns


# --------------------------------------------------------------------------- outils

def queue() -> list[dict]:
    plat = get_platform()
    if not plat.which("postqueue"):
        return []
    r = plat.run(["postqueue", "-p"], timeout=30)
    out, cur = [], None
    for line in r.stdout.splitlines():
        m = re.match(r"^([A-F0-9]+)\*?\s+(\d+)\s+(\w{3}\s+\w{3}\s+\d+\s+[\d:]+)\s+(\S+)", line)
        if m:
            cur = {"id": m.group(1), "size": int(m.group(2)), "date": m.group(3), "sender": m.group(4), "recipients": [], "reason": ""}
            out.append(cur)
        elif cur and line.startswith(" ") and "@" in line and not line.strip().startswith("("):
            cur["recipients"].append(line.strip())
        elif cur and line.strip().startswith("("):
            cur["reason"] = line.strip()[1:-1][:200]
    return out


def queue_action(action: str, qid: str = "") -> str:
    plat = get_platform()
    if action == "flush":
        r = plat.run(["postqueue", "-f"], timeout=60)
    elif action == "delete_all":
        r = plat.run(["postsuper", "-d", "ALL"], timeout=60)
    elif action == "delete" and re.fullmatch(r"[A-F0-9]+", qid or ""):
        r = plat.run(["postsuper", "-d", qid], timeout=30)
    else:
        return "action invalide"
    return "" if r.ok else r.output


def mail_log(lines: int = 200) -> str:
    from toutpanel.services import logs

    for cand in ("/var/log/mail.log", "/var/log/maillog"):
        if Path(cand).exists():
            return logs.tail(cand, lines)
    return logs.journal("postfix", lines)


def mailbox_usage(domain: str, local_part: str) -> int:
    p = vmail_dir() / domain / local_part
    if not p.exists():
        return 0
    total = 0
    for root, _, files in os.walk(p):
        for f in files:
            try:
                total += (Path(root) / f).stat().st_size
            except OSError:
                pass
    return total


def self_signed_cert() -> tuple[str, str]:
    from toutpanel.services import ssl

    st = settings()
    cert, key = ssl.self_signed([st["hostname"]], config.SSL_DIR / "mail")
    config.get_settings().update({"mail_ssl_cert": str(cert), "mail_ssl_key": str(key)})
    return str(cert), str(key)


def send_test(to: str, subject: str = "Test ToutPanel") -> str:
    import smtplib
    from email.message import EmailMessage

    st = settings()
    msg = EmailMessage()
    msg["From"] = f"postmaster@{st['hostname'].split('.', 1)[-1] if '.' in st['hostname'] else st['hostname']}"
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content("Ceci est un message de test envoyé par ToutPanel.")
    try:
        with smtplib.SMTP("127.0.0.1", 25, timeout=15) as s:
            s.send_message(msg)
        return ""
    except Exception as e:
        return str(e)
