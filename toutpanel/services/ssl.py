"""Certificats SSL : auto-signés (cryptography) et Let's Encrypt (certbot)."""
from __future__ import annotations

import datetime
import ipaddress
from pathlib import Path

from toutpanel import config
from toutpanel.platform import get_platform


class SslError(RuntimeError):
    pass


def self_signed(domains: list[str], out_dir: Path, days: int = 3650) -> tuple[Path, Path]:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    out_dir.mkdir(parents=True, exist_ok=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, domains[0]),
                      x509.NameAttribute(NameOID.ORGANIZATION_NAME, "ToutPanel")])
    sans = []
    for d in domains:
        try:
            sans.append(x509.IPAddress(ipaddress.ip_address(d)))
        except ValueError:
            sans.append(x509.DNSName(d))
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=days))
            .add_extension(x509.SubjectAlternativeName(sans), critical=False)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .sign(key, hashes.SHA256()))
    key_path = out_dir / "privkey.pem"
    cert_path = out_dir / "fullchain.pem"
    key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
                                           serialization.NoEncryption()))
    cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    return cert_path, key_path


def cert_info(cert_path: str) -> dict:
    from cryptography import x509

    p = Path(cert_path)
    if not p.exists():
        return {"exists": False}
    try:
        cert = x509.load_pem_x509_certificate(p.read_bytes())
    except Exception as e:
        return {"exists": True, "error": str(e)}
    try:
        san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
        names = [str(n.value) for n in san]
    except x509.ExtensionNotFound:
        names = []
    not_after = getattr(cert, "not_valid_after_utc", None) or cert.not_valid_after.replace(tzinfo=datetime.timezone.utc)
    days_left = (not_after - datetime.datetime.now(datetime.timezone.utc)).days
    return {"exists": True, "subject": cert.subject.rfc4514_string(), "issuer": cert.issuer.rfc4514_string(),
            "not_after": not_after.isoformat(), "days_left": days_left, "domains": names,
            "self_signed": cert.subject == cert.issuer}


def certbot_available() -> bool:
    return bool(get_platform().which("certbot"))


def letsencrypt(domains: list[str], webroot: str, email: str, log) -> tuple[Path, Path]:
    """Obtient un certificat via certbot en mode webroot. Retourne (fullchain, privkey)."""
    plat = get_platform()
    exe = plat.which("certbot")
    if not exe:
        raise SslError("certbot n'est pas installé (voir Logiciels)")
    Path(webroot, ".well-known", "acme-challenge").mkdir(parents=True, exist_ok=True)
    cmd = [exe, "certonly", "--webroot", "-w", webroot, "--non-interactive", "--agree-tos", "--expand",
           "--cert-name", domains[0]]
    cmd += ["--email", email] if email else ["--register-unsafely-without-email"]
    for d in domains:
        cmd += ["-d", d]
    log("$ " + " ".join(cmd))
    rc = plat.stream(cmd, log)
    if rc != 0:
        raise SslError("certbot a échoué (voir le journal)")
    live = Path("/etc/letsencrypt/live" if not config.IS_WINDOWS else "C:/Certbot/live") / domains[0]
    cert, key = live / "fullchain.pem", live / "privkey.pem"
    if not cert.exists():
        raise SslError(f"Certificat introuvable dans {live}")
    return cert, key


def site_ssl_dir(site_name: str) -> Path:
    d = config.SSL_DIR / site_name
    d.mkdir(parents=True, exist_ok=True)
    return d


def panel_cert() -> tuple[Path, Path]:
    """Certificat du panel : celui d'un site (Let's Encrypt) si `panel_cert_site` est défini et valide, sinon auto-signé."""
    site_name = config.get_settings().get("panel_cert_site") or ""
    if site_name:
        try:
            from toutpanel.db import session_scope
            from toutpanel.models import Site

            with session_scope() as db:
                site = db.query(Site).filter(Site.name == site_name).first()
                if site and site.ssl_cert and site.ssl_key and Path(site.ssl_cert).exists() and Path(site.ssl_key).exists():
                    return Path(site.ssl_cert), Path(site.ssl_key)
        except Exception:  # noqa: BLE001
            pass
    d = config.SSL_DIR / "panel"
    cert, key = d / "fullchain.pem", d / "privkey.pem"
    if not cert.exists() or not key.exists():
        import socket

        self_signed([socket.gethostname() or "toutpanel", "localhost"], d)
    return cert, key


# --------------------------------------------------------------------------- renouvellement automatique

def renew_all(log=None) -> dict:
    """`certbot renew` puis rechargement du serveur web si un certificat a changé. Retourne un résumé."""
    from toutpanel.services import webserver

    log = log or (lambda m: None)
    plat = get_platform()
    exe = plat.which("certbot")
    out = {"certbot": bool(exe), "renewed": False, "output": ""}
    if not exe:
        log("certbot absent : rien à renouveler")
        return out
    r = plat.run([exe, "renew", "--non-interactive", "--no-random-sleep-on-renew"], timeout=900)
    out["output"] = r.output[-3000:]
    log(r.output[-3000:])
    renewed = "Congratulations" in r.output or "renewed" in r.output.lower() and "no renewals were attempted" not in r.output.lower()
    out["renewed"] = bool(renewed) and r.ok
    if out["renewed"] and webserver.is_installed():
        rr = webserver.get_adapter().reload()
        log("serveur web : " + ("rechargé" if rr.ok else rr.output[-300:]))
    return out


def expiring_sites(days: int = 14) -> list[dict]:
    """Sites dont le certificat expire dans moins de `days` jours (pour les alertes)."""
    from toutpanel.db import session_scope
    from toutpanel.models import Site

    out = []
    with session_scope() as db:
        for s in db.query(Site).filter(Site.ssl_enabled.is_(True)).all():
            info = cert_info(s.ssl_cert) if s.ssl_cert else {"exists": False}
            if info.get("exists") and info.get("days_left", 999) <= days:
                out.append({"site": s.name, "domains": s.domains or [], "days_left": info["days_left"], "self_signed": info.get("self_signed")})
    return out


def _renewal_job() -> None:
    import logging

    lg = logging.getLogger("toutpanel.ssl")
    try:
        res = renew_all()
        if res["renewed"]:
            lg.info("SSL : certificats renouvelés et serveur web rechargé")
    except Exception as e:  # noqa: BLE001
        lg.warning("SSL : renouvellement automatique : %s", e)


def start_renewal() -> None:
    """Tous les jours à 03:30 (heure locale) : renouvellement Let's Encrypt et rechargement du serveur web."""
    from apscheduler.triggers.cron import CronTrigger

    from toutpanel.services.cron import get_scheduler

    sched = get_scheduler()
    if sched.get_job("ssl-renew"):
        sched.remove_job("ssl-renew")
    sched.add_job(_renewal_job, CronTrigger(hour=3, minute=30), id="ssl-renew", replace_existing=True, misfire_grace_time=3600, coalesce=True)
