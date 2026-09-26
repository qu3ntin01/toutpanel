"""Gestion DNS : zones et enregistrements servis par BIND (named) ou poussés chez Cloudflare.

- Les zones sont stockées dans la base du panel (DnsZone / DnsRecord) et rendues en fichiers de zone BIND
  dans <home>/dns/, inclus dans la configuration de named (named.conf.local / named.conf) puis rechargés.
- Vérification de propagation par résolution (dig ou socket) auprès de résolveurs publics.
- Fournisseur Cloudflare : lecture / création / mise à jour des enregistrements via l'API v4 avec un jeton.
"""
from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Optional

from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.models import DnsRecord, DnsZone, MailDomain, Site
from toutpanel.platform import get_platform

RECORD_TYPES = ("A", "AAAA", "CNAME", "MX", "TXT", "SRV", "NS", "CAA", "PTR")
DOMAIN_RE = re.compile(r"^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$")
NAME_RE = re.compile(r"^(@|\*|[a-z0-9_*](?:[a-z0-9_.*-]{0,251}[a-z0-9_*])?)$", re.I)
IPV4_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")


def _is_ipv4(value: str) -> bool:
    if not IPV4_RE.match(value):
        return False
    return all(int(x) <= 255 for x in value.split("."))
PUBLIC_RESOLVERS = ("1.1.1.1", "8.8.8.8", "9.9.9.9")


class DnsError(ValueError):
    pass


# --------------------------------------------------------------------------- réglages / état

def settings() -> dict:
    s = config.get_settings()
    return {"ns1": s.get("dns_ns1", ""), "ns2": s.get("dns_ns2", ""), "admin_email": s.get("dns_admin_email", ""),
            "default_ttl": int(s.get("dns_default_ttl", 3600) or 3600), "cloudflare_token_set": bool(s.get("cloudflare_token")),
            "cloudflare_proxied": bool(s.get("cloudflare_proxied", False))}


def dns_dir() -> Path:
    """Répertoire des fichiers de zone : celui de BIND quand il existe (lisible par named, autorisé par AppArmor / SELinux),
    sinon <home>/dns."""
    candidates = [] if config.IS_WINDOWS else [Path("/var/lib/bind"), Path("/var/named"), Path("/var/lib/named")]
    for base in candidates:
        if base.is_dir():
            d = base / "toutpanel"
            try:
                d.mkdir(exist_ok=True)
                os.chmod(d, 0o775)
                return d
            except OSError:
                continue
    d = config.HOME / "dns"
    d.mkdir(parents=True, exist_ok=True)
    return d


def named_paths() -> dict:
    """Emplacements de BIND selon la distribution."""
    for conf, local, service in (("/etc/bind/named.conf", "/etc/bind/named.conf.local", "named"),
                                 ("/etc/named.conf", "/etc/named.conf", "named"),
                                 ("/etc/bind/named.conf", "/etc/bind/named.conf", "named")):
        if Path(conf).exists():
            return {"conf": conf, "local": local, "service": service}
    return {"conf": "", "local": "", "service": "named"}


def bind_installed() -> bool:
    plat = get_platform()
    return bool(plat.which("named") or plat.which("named-checkzone") or Path("/usr/sbin/named").exists())


def status() -> dict:
    plat = get_platform()
    paths = named_paths()
    installed = bind_installed()
    st = plat.service_status(paths["service"]) if installed else "missing"
    if installed and st == "unknown":
        st = plat.service_status("bind9")
    return {"installed": installed, "status": st, "service": paths["service"], "conf": paths["conf"], "windows": config.IS_WINDOWS,
            "ip": server_ip(), "settings": settings()}


def server_ip() -> str:
    from toutpanel.services.system_info import _local_ip

    return _local_ip()


# --------------------------------------------------------------------------- CRUD

def _clean_domain(domain: str) -> str:
    d = domain.strip().lower().rstrip(".")
    if not DOMAIN_RE.match(d):
        raise DnsError(f"Nom de domaine invalide : {domain}")
    return d


def validate_record(zone: DnsZone, rtype: str, name: str, value: str, ttl: int, priority: int) -> tuple[str, str, str, int, int]:
    rtype = rtype.strip().upper()
    if rtype not in RECORD_TYPES:
        raise DnsError("Type d'enregistrement invalide")
    name = (name or "@").strip().lower().rstrip(".") or "@"
    if name.endswith("." + zone.domain):
        name = name[: -len(zone.domain) - 1]
    elif name == zone.domain:
        name = "@"
    if not NAME_RE.match(name):
        raise DnsError("Nom d'enregistrement invalide")
    value = value.strip()
    if not value:
        raise DnsError("Valeur requise")
    if any(ord(c) < 32 for c in value):
        raise DnsError("Valeur invalide (caractère de contrôle)")
    if rtype == "A" and not _is_ipv4(value):
        raise DnsError("Adresse IPv4 invalide")
    if rtype == "AAAA":
        try:
            socket.inet_pton(socket.AF_INET6, value)
        except (OSError, AttributeError):
            raise DnsError("Adresse IPv6 invalide")
    if rtype in ("CNAME", "MX", "NS", "PTR"):
        target = value.rstrip(".")
        if not (DOMAIN_RE.match(target) or target == "@" or NAME_RE.match(target)):
            raise DnsError("Cible invalide (nom d'hôte attendu)")
    if rtype == "MX" and priority < 0:
        raise DnsError("Priorité MX invalide")
    if rtype == "SRV" and not re.fullmatch(r"\d+ \d+ [A-Za-z0-9.-]+\.?", value):
        raise DnsError("SRV : valeur attendue « poids port cible » (ex : 5 5060 sip.exemple.com)")
    if rtype == "CAA" and not re.fullmatch(r"\d+ (issue|issuewild|iodef) \".*\"", value):
        raise DnsError('CAA : valeur attendue « 0 issue "letsencrypt.org" »')
    if rtype == "TXT" and len(value) > 4000:
        raise DnsError("TXT trop long")
    ttl = int(ttl or 0)
    if ttl and not (60 <= ttl <= 604800):
        raise DnsError("TTL invalide (60 à 604800 s, 0 = TTL de la zone)")
    return rtype, name, value, ttl, int(priority or 0)


def create_zone(db: Session, domain: str, ip: str = "", provider: str = "bind", with_mail: bool = True, with_www: bool = True,
                admin_email: str = "") -> DnsZone:
    domain = _clean_domain(domain)
    if provider not in ("bind", "cloudflare"):
        raise DnsError("Fournisseur invalide")
    if db.query(DnsZone).filter(DnsZone.domain == domain).first():
        raise DnsError("Cette zone existe déjà")
    ip = (ip or server_ip()).strip()
    if not _is_ipv4(ip):
        raise DnsError("Adresse IPv4 invalide")
    st = settings()
    zone = DnsZone(domain=domain, provider=provider, ttl=st["default_ttl"], serial=0, admin_email=admin_email or st["admin_email"] or f"hostmaster@{domain}")
    db.add(zone)
    db.flush()
    recs = [("A", "@", ip, 0, "Serveur web")]
    if with_www:
        recs.append(("CNAME", "www", f"{domain}.", 0, "Alias www"))
    if st["ns1"]:
        recs.append(("NS", "@", st["ns1"].rstrip(".") + ".", 0, "Serveur de noms"))
    if st["ns2"]:
        recs.append(("NS", "@", st["ns2"].rstrip(".") + ".", 0, "Serveur de noms"))
    if with_mail:
        recs += mail_records_for(db, domain, ip)
    for rtype, name, value, prio, remark in recs:
        db.add(DnsRecord(zone_id=zone.id, type=rtype, name=name, value=value, priority=prio, remark=remark))
    db.flush()
    return zone


def mail_records_for(db: Session, domain: str, ip: str) -> list[tuple]:
    """Enregistrements mail (MX, SPF, DKIM, DMARC) : depuis le module mail si le domaine y est déclaré."""
    from toutpanel.services import mail as mail_svc

    md = db.query(MailDomain).filter(MailDomain.domain == domain).first()
    out = []
    if md:
        for r in mail_svc.dns_records(md, ip):
            if r["type"] == "PTR":
                continue
            name = r["name"]
            if name == domain:
                name = "@"
            elif name.endswith("." + domain):
                name = name[: -len(domain) - 1]
            if r["type"] == "MX":
                prio, target = r["value"].split(" ", 1)
                out.append(("MX", name, target, int(prio), r["note"]))
            elif r["type"] == "A" and not DOMAIN_RE.match(name) and name != "@":
                out.append(("A", name, r["value"], 0, r["note"]))
            elif r["type"] == "A":
                host = r["name"]
                sub = host[: -len(domain) - 1] if host.endswith("." + domain) else host
                out.append(("A", sub if sub and sub != domain else "mail", r["value"], 0, r["note"]))
            else:
                out.append((r["type"], name, r["value"], 0, r["note"]))
    else:
        out += [("A", "mail", ip, 0, "Serveur mail"), ("MX", "@", f"mail.{domain}.", 10, "Réception du courrier"),
                ("TXT", "@", f"v=spf1 mx a ip4:{ip} ~all", 0, "SPF"),
                ("TXT", "_dmarc", f"v=DMARC1; p=quarantine; rua=mailto:postmaster@{domain}", 0, "DMARC")]
    return out


def add_record(db: Session, zone: DnsZone, rtype: str, name: str, value: str, ttl: int = 0, priority: int = 0, remark: str = "") -> DnsRecord:
    rtype, name, value, ttl, priority = validate_record(zone, rtype, name, value, ttl, priority)
    if rtype == "CNAME" and db.query(DnsRecord).filter(DnsRecord.zone_id == zone.id, DnsRecord.name == name, DnsRecord.type != "CNAME").first():
        raise DnsError("Un CNAME ne peut pas coexister avec d'autres enregistrements du même nom")
    r = DnsRecord(zone_id=zone.id, type=rtype, name=name, value=value, ttl=ttl, priority=priority, remark=remark[:190])
    db.add(r)
    db.flush()
    return r


def update_record(db: Session, zone: DnsZone, rec: DnsRecord, **fields) -> DnsRecord:
    rtype, name, value, ttl, priority = validate_record(zone, fields.get("type", rec.type), fields.get("name", rec.name), fields.get("value", rec.value),
                                                        fields.get("ttl", rec.ttl), fields.get("priority", rec.priority))
    rec.type, rec.name, rec.value, rec.ttl, rec.priority = rtype, name, value, ttl, priority
    if "enabled" in fields:
        rec.enabled = bool(fields["enabled"])
    if "remark" in fields:
        rec.remark = str(fields["remark"])[:190]
    db.flush()
    return rec


def zone_from_site(db: Session, site: Site, ip: str = "") -> DnsZone:
    """Crée la zone du domaine principal d'un site avec tous ses domaines."""
    domains = site.domains or [site.name]
    main = domains[0].lstrip("*.")
    parts = main.split(".")
    root = ".".join(parts[-2:]) if len(parts) >= 2 else main
    zone = create_zone(db, root, ip)
    ip = ip or server_ip()
    for d in domains:
        d = d.lstrip("*.")
        if d == root:
            continue
        if d.endswith("." + root):
            sub = d[: -len(root) - 1]
            if sub != "www" and not db.query(DnsRecord).filter(DnsRecord.zone_id == zone.id, DnsRecord.name == sub).first():
                db.add(DnsRecord(zone_id=zone.id, type="A", name=sub, value=ip, remark=f"Site {site.name}"))
    db.flush()
    return zone


# --------------------------------------------------------------------------- rendu BIND

def next_serial(zone: DnsZone) -> int:
    base = int(datetime.utcnow().strftime("%Y%m%d")) * 100
    return base if zone.serial < base else zone.serial + 1


def render_zone(zone: DnsZone, records: list[DnsRecord], serial: Optional[int] = None) -> str:
    st = settings()
    ns1 = (st["ns1"] or f"ns1.{zone.domain}").rstrip(".") + "."
    admin = zone.admin_email if zone.admin_email and re.fullmatch(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", zone.admin_email) else f"hostmaster@{zone.domain}"
    email = admin.replace("@", ".").rstrip(".") + "."
    serial = serial if serial is not None else (zone.serial or next_serial(zone))
    lines = [f"; Zone {zone.domain} générée par ToutPanel - ne pas modifier à la main", f"$ORIGIN {zone.domain}.", f"$TTL {zone.ttl}",
             f"@\tIN\tSOA\t{ns1} {email} (", f"\t\t{serial}\t; serial", "\t\t3600\t; refresh", "\t\t900\t; retry", "\t\t1209600\t; expire", "\t\t300 )\t; minimum", ""]
    has_ns = any(r.type == "NS" and r.name == "@" and r.enabled for r in records)
    ns_hosts = [ns1]
    if not has_ns:
        lines.append(f"@\tIN\tNS\t{ns1}")
        if st["ns2"]:
            lines.append(f"@\tIN\tNS\t{st['ns2'].rstrip('.')}.")
            ns_hosts.append(st["ns2"].rstrip(".") + ".")
    else:
        ns_hosts = [r.value.rstrip(".") + "." for r in records if r.type == "NS" and r.name == "@" and r.enabled]
    # Glue : un serveur de noms situé dans la zone doit avoir une adresse, sinon BIND refuse la zone
    names_with_addr = {r.name for r in records if r.type in ("A", "AAAA") and r.enabled}
    ip = server_ip()
    for host in ns_hosts:
        if host.endswith("." + zone.domain + "."):
            sub = host[: -len(zone.domain) - 2]
            if sub and sub not in names_with_addr and _is_ipv4(ip):
                lines.append(f"{sub}\tIN\tA\t{ip}\t; glue")
                names_with_addr.add(sub)
    for r in sorted(records, key=lambda x: (x.type != "NS", x.type, x.name)):
        if not r.enabled:
            continue
        ttl = str(r.ttl) if r.ttl else ""
        val = r.value
        if r.type == "TXT":
            val = " ".join('"' + chunk.replace('"', '\\"') + '"' for chunk in [val[i:i + 250] for i in range(0, len(val), 250)])
        elif r.type in ("CNAME", "MX", "NS", "PTR", "SRV") and not val.endswith(".") and "." in val.split()[-1]:
            val = val + "."
        if r.type == "MX":
            val = f"{r.priority} {val}"
        if r.type == "SRV":
            val = f"{r.priority} {val}"
        lines.append(f"{r.name}\t{ttl}\tIN\t{r.type}\t{val}".replace("\t\tIN", "\tIN") if not ttl else f"{r.name}\t{ttl}\tIN\t{r.type}\t{val}")
    lines.append("")
    return "\n".join(lines)


def render_named_conf(zones: list[DnsZone]) -> str:
    lines = ["// Zones ToutPanel - généré, ne pas modifier à la main"]
    for z in zones:
        if z.enabled and z.provider == "bind":
            lines.append(f'zone "{z.domain}" {{ type master; file "{(dns_dir() / ("db." + z.domain)).as_posix()}"; allow-transfer {{ none; }}; }};')
    lines.append("")
    return "\n".join(lines)


def check_zone_file(domain: str, path: Path) -> str:
    plat = get_platform()
    if not plat.which("named-checkzone"):
        return ""
    r = plat.run(["named-checkzone", domain, str(path)], timeout=30)
    if r.ok:
        return ""
    # Ligne la plus parlante : celle qui cite le fichier et la position
    for line in r.output.splitlines():
        if str(path) in line and ":" in line:
            tail = line.split(str(path), 1)[1]
            return "ligne" + tail.replace(" near ", " près de ")
    return r.output[-800:]


def write_zones(db: Session, bump_serial: bool = True) -> dict:
    """Écrit les fichiers de zone et l'include named, vérifie la syntaxe. Retourne {written, errors, include}."""
    out = {"written": [], "errors": {}, "include": ""}
    d = dns_dir()
    zones = db.query(DnsZone).order_by(DnsZone.domain).all()
    for z in zones:
        if z.provider != "bind":
            continue
        recs = db.query(DnsRecord).filter(DnsRecord.zone_id == z.id).all()
        if bump_serial:
            z.serial = next_serial(z)
        path = d / f"db.{z.domain}"
        path.write_text(render_zone(z, recs, z.serial), encoding="utf-8")
        try:
            os.chmod(path, 0o644)
        except OSError:
            pass
        err = check_zone_file(z.domain, path)
        if err:
            out["errors"][z.domain] = err
        out["written"].append(str(path))
    inc = d / "toutpanel-zones.conf"
    inc.write_text(render_named_conf(zones), encoding="utf-8")
    out["include"] = str(inc)
    _ensure_include(inc)
    if not config.IS_WINDOWS:
        try:
            get_platform().run(["chmod", "-R", "a+rX", str(d)], timeout=10)
        except Exception:  # noqa: BLE001
            pass
    db.flush()
    return out


def _ensure_include(inc: Path) -> None:
    paths = named_paths()
    target = paths["local"] or paths["conf"]
    if not target:
        return
    p = Path(target)
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    line = f'include "{inc.as_posix()}";'
    if line not in text:
        try:
            p.write_text(text.rstrip("\n") + "\n" + line + "\n", encoding="utf-8")
        except OSError:
            pass


def reload_named() -> str:
    """Recharge BIND (rndc reload, sinon service reload). Retourne un message d'erreur éventuel."""
    plat = get_platform()
    if not bind_installed():
        return "BIND n'est pas installé (Logiciels → BIND / serveur DNS)."
    if plat.which("named-checkconf"):
        r = plat.run(["named-checkconf"], timeout=30)
        if not r.ok:
            return "named-checkconf : " + r.output[-600:]
    svc = named_paths()["service"]
    st = plat.service_status(svc)
    if st == "unknown":
        svc = "bind9"
        st = plat.service_status(svc)
    if st != "running":
        r = plat.service_action(svc, "start")
        if not r.ok:
            # sans systemd : lancer named directement
            r2 = plat.run(["named", "-u", "bind"], timeout=20) if plat.which("named") else r
            if not r2.ok:
                return "Démarrage de named impossible : " + (r.output or r2.output)[-400:]
        return ""
    if plat.which("rndc"):
        r = plat.run(["rndc", "reload"], timeout=30)
        if r.ok:
            return ""
    r = plat.service_action(svc, "reload")
    return "" if r.ok else "Rechargement échoué : " + r.output[-400:]


def apply(db: Session) -> tuple[dict, str]:
    res = write_zones(db)
    if res["errors"]:
        return res, "Zone refusée : " + "; ".join(f"{k} : {v.splitlines()[0] if v else ''}" for k, v in res["errors"].items())
    if config.IS_WINDOWS:
        return res, windows_apply(db)
    return res, reload_named()


def _ps_quote(v: str) -> str:
    """Chaîne PowerShell entre apostrophes (une apostrophe se double)."""
    return "'" + str(v).replace("'", "''") + "'"


def windows_script(db: Session) -> str:
    """Script PowerShell (module DnsServer) qui met les zones du panel en place sur le rôle Serveur DNS de Windows."""
    lines = ["$ErrorActionPreference = 'Stop'", "Import-Module DnsServer"]
    for z in db.query(DnsZone).filter(DnsZone.provider == "bind", DnsZone.enabled.is_(True)).order_by(DnsZone.domain).all():
        zn = _ps_quote(z.domain)
        lines.append(f"if (-not (Get-DnsServerZone -Name {zn} -ErrorAction SilentlyContinue)) {{ Add-DnsServerPrimaryZone -Name {zn} -ZoneFile {_ps_quote(z.domain + '.dns')} }}")
        lines.append(f"Get-DnsServerResourceRecord -ZoneName {zn} | Where-Object {{ $_.RecordType -ne 'SOA' -and $_.RecordType -ne 'NS' }} "
                     f"| Remove-DnsServerResourceRecord -ZoneName {zn} -Force")
        for r in db.query(DnsRecord).filter(DnsRecord.zone_id == z.id, DnsRecord.enabled.is_(True)).order_by(DnsRecord.type, DnsRecord.name).all():
            n = _ps_quote(r.name)
            ttl = f" -TimeToLive (New-TimeSpan -Seconds {r.ttl})" if r.ttl else ""
            target = _ps_quote(r.value.rstrip("."))
            if r.type == "A":
                lines.append(f"Add-DnsServerResourceRecordA -ZoneName {zn} -Name {n} -IPv4Address {_ps_quote(r.value)}{ttl}")
            elif r.type == "AAAA":
                lines.append(f"Add-DnsServerResourceRecordAAAA -ZoneName {zn} -Name {n} -IPv6Address {_ps_quote(r.value)}{ttl}")
            elif r.type == "CNAME":
                lines.append(f"Add-DnsServerResourceRecordCName -ZoneName {zn} -Name {n} -HostNameAlias {target}{ttl}")
            elif r.type == "MX":
                lines.append(f"Add-DnsServerResourceRecordMX -ZoneName {zn} -Name {n} -MailExchange {target} -Preference {int(r.priority)}{ttl}")
            elif r.type == "TXT":
                lines.append(f"Add-DnsServerResourceRecord -Txt -ZoneName {zn} -Name {n} -DescriptiveText {_ps_quote(r.value)}{ttl}")
            elif r.type == "NS":
                lines.append(f"Add-DnsServerResourceRecord -NS -ZoneName {zn} -Name {n} -NameServer {target}{ttl}")
            elif r.type == "PTR":
                lines.append(f"Add-DnsServerResourceRecordPtr -ZoneName {zn} -Name {n} -PtrDomainName {target}{ttl}")
            elif r.type == "SRV":
                parts = r.value.split()
                if len(parts) == 3:
                    lines.append(f"Add-DnsServerResourceRecord -Srv -ZoneName {zn} -Name {n} -DomainName {_ps_quote(parts[2].rstrip('.'))} "
                                 f"-Priority {int(r.priority)} -Weight {int(parts[0])} -Port {int(parts[1])}{ttl}")
            elif r.type == "CAA":
                m = re.fullmatch(r"(\d+) (issue|issuewild|iodef) \"(.*)\"", r.value)
                if m:
                    lines.append(f"Add-DnsServerResourceRecord -ZoneName {zn} -Name {n} -Type 257 "
                                 f"-RecordData ([byte[]]@({int(m.group(1))}) + [byte[]]@({len(m.group(2))}) + [Text.Encoding]::ASCII.GetBytes({_ps_quote(m.group(2) + m.group(3))})){ttl}")
    lines.append("Write-Output 'ToutPanel DNS : zones appliquées'")
    return "\n".join(lines) + "\n"


def windows_apply(db: Session) -> str:
    """Windows : serveur DNS intégré (rôle DNS requis), via PowerShell. Retourne un message d'erreur éventuel."""
    plat = get_platform()
    exe = plat.which("powershell") or plat.which("pwsh")
    if not exe:
        return "PowerShell introuvable"
    script = dns_dir() / "toutpanel-dns.ps1"
    script.write_text(windows_script(db), encoding="utf-8-sig")
    r = plat.run([exe, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(script)], timeout=180)
    return "" if r.ok else r.output[-500:]


# --------------------------------------------------------------------------- vérification

def resolve(name: str, rtype: str, server: str = "") -> list[str]:
    plat = get_platform()
    if plat.which("dig"):
        cmd = ["dig", "+short", "+time=3", "+tries=1", rtype, name] + ([f"@{server}"] if server else [])
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
            return [l.strip() for l in r.stdout.splitlines() if l.strip()]
        except (OSError, subprocess.TimeoutExpired):
            return []
    if rtype in ("A", "AAAA") and not server:
        try:
            fam = socket.AF_INET if rtype == "A" else socket.AF_INET6
            return sorted({x[4][0] for x in socket.getaddrinfo(name, None, fam)})
        except OSError:
            return []
    return []


def check(db: Session, zone: DnsZone) -> dict:
    """Compare les enregistrements de la zone avec ce que voient les résolveurs publics et le serveur local."""
    recs = db.query(DnsRecord).filter(DnsRecord.zone_id == zone.id, DnsRecord.enabled.is_(True)).all()
    out = {"domain": zone.domain, "ns": resolve(zone.domain, "NS", PUBLIC_RESOLVERS[0]), "records": []}
    for r in recs:
        if r.type not in ("A", "AAAA", "CNAME", "MX", "TXT", "NS"):
            continue
        fqdn = zone.domain if r.name == "@" else f"{r.name}.{zone.domain}"
        public = resolve(fqdn, r.type, PUBLIC_RESOLVERS[0])
        local = resolve(fqdn, r.type, "127.0.0.1") if zone.provider == "bind" else []
        expected = r.value.rstrip(".")
        if r.type == "MX":
            expected = f"{r.priority} {r.value.rstrip('.')}"
        norm = lambda vals: [v.strip('"').rstrip(".").replace('" "', "") for v in vals]  # noqa: E731
        out["records"].append({"type": r.type, "name": fqdn, "expected": expected, "public": public, "local": local,
                               "ok": expected in norm(public), "local_ok": expected in norm(local)})
    out["propagated"] = bool(out["records"]) and all(x["ok"] for x in out["records"])
    return out


# --------------------------------------------------------------------------- Cloudflare

CF_API = "https://api.cloudflare.com/client/v4"


def _cf(method: str, path: str, payload: Optional[dict] = None) -> dict:
    token = config.get_settings().get("cloudflare_token") or ""
    if not token:
        raise DnsError("Jeton API Cloudflare absent (DNS → Réglages)")
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(CF_API + path, data=data, method=method, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            body = json.loads(resp.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode("utf-8", "replace"))
        except Exception:  # noqa: BLE001
            raise DnsError(f"Cloudflare : HTTP {e.code}")
    except (urllib.error.URLError, OSError) as e:
        raise DnsError(f"Cloudflare injoignable : {e}")
    if not body.get("success", False):
        errs = "; ".join(str(x.get("message", x)) for x in body.get("errors", [])) or "erreur inconnue"
        raise DnsError("Cloudflare : " + errs)
    return body


def cf_zones() -> list[dict]:
    b = _cf("GET", "/zones?per_page=50&status=active")
    return [{"id": z["id"], "name": z["name"], "status": z.get("status"), "name_servers": z.get("name_servers", [])} for z in b.get("result", [])]


def cf_records(zone_id: str) -> list[dict]:
    b = _cf("GET", f"/zones/{zone_id}/dns_records?per_page=500")
    return b.get("result", [])


def cf_push(db: Session, zone: DnsZone) -> dict:
    """Crée / met à jour chez Cloudflare les enregistrements de la zone (les enregistrements Cloudflare absents du panel sont conservés)."""
    if not zone.cf_zone_id:
        for z in cf_zones():
            if z["name"] == zone.domain:
                zone.cf_zone_id = z["id"]
                break
        if not zone.cf_zone_id:
            raise DnsError("Zone introuvable chez Cloudflare : ajoutez d'abord le domaine dans votre compte Cloudflare")
    existing = cf_records(zone.cf_zone_id)
    proxied = settings()["cloudflare_proxied"]
    created = updated = 0
    for r in db.query(DnsRecord).filter(DnsRecord.zone_id == zone.id, DnsRecord.enabled.is_(True)).all():
        if r.type in ("PTR",):
            continue
        fqdn = zone.domain if r.name == "@" else f"{r.name}.{zone.domain}"
        content = r.value.rstrip(".") if r.type in ("CNAME", "MX", "NS") else r.value
        payload = {"type": r.type, "name": fqdn, "content": content, "ttl": r.ttl or 1}
        if r.type == "MX":
            payload["priority"] = r.priority
        if r.type in ("A", "AAAA", "CNAME"):
            payload["proxied"] = proxied and r.name not in ("mail", "ftp", "@mx")
        if r.type == "SRV":
            w, port, target = r.value.split()
            payload["data"] = {"priority": r.priority, "weight": int(w), "port": int(port), "target": target.rstrip(".")}
            payload.pop("content")
        match = [e for e in existing if e["type"] == r.type and e["name"] == fqdn and (r.type != "TXT" or e["content"].strip('"') == content)]
        if match:
            e = match[0]
            if e.get("content") != content or (r.type == "MX" and e.get("priority") != r.priority):
                _cf("PATCH", f"/zones/{zone.cf_zone_id}/dns_records/{e['id']}", payload)
                updated += 1
        else:
            _cf("POST", f"/zones/{zone.cf_zone_id}/dns_records", payload)
            created += 1
    db.flush()
    return {"created": created, "updated": updated}


def cf_import(db: Session, cf_zone: dict) -> DnsZone:
    """Importe une zone Cloudflare (et ses enregistrements) dans le panel."""
    domain = _clean_domain(cf_zone["name"])
    zone = db.query(DnsZone).filter(DnsZone.domain == domain).first()
    if not zone:
        zone = DnsZone(domain=domain, provider="cloudflare", ttl=settings()["default_ttl"], admin_email=f"hostmaster@{domain}")
        db.add(zone)
        db.flush()
    zone.provider = "cloudflare"
    zone.cf_zone_id = cf_zone["id"]
    db.query(DnsRecord).filter(DnsRecord.zone_id == zone.id).delete()
    for e in cf_records(cf_zone["id"]):
        if e["type"] not in RECORD_TYPES:
            continue
        name = "@" if e["name"] == domain else e["name"][: -len(domain) - 1] if e["name"].endswith("." + domain) else e["name"]
        value = e.get("content", "")
        if e["type"] == "SRV" and e.get("data"):
            d = e["data"]
            value = f"{d.get('weight', 0)} {d.get('port', 0)} {d.get('target', '')}"
        db.add(DnsRecord(zone_id=zone.id, type=e["type"], name=name, value=value, ttl=0 if e.get("ttl", 1) == 1 else int(e["ttl"]),
                         priority=int(e.get("priority") or (e.get("data") or {}).get("priority") or 0), remark="Cloudflare" + (" (proxy)" if e.get("proxied") else "")))
    db.flush()
    return zone
