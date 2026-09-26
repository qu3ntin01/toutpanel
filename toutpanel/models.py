"""Modèles SQLAlchemy."""
from __future__ import annotations
from typing import Optional

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from toutpanel.db import Base


def utcnow() -> datetime:
    """Horodatage UTC naïf (remplace datetime.utcnow(), déprécié depuis Python 3.12)."""
    from datetime import timezone

    return datetime.now(timezone.utc).replace(tzinfo=None)


def now() -> datetime:
    return utcnow()


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    totp_secret: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    totp_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    role: Mapped[str] = mapped_column(String(16), default="admin")           # admin | viewer (lecture seule)
    totp_last_used: Mapped[int] = mapped_column(Integer, default=0)          # anti-rejeu : dernier compteur TOTP accepté
    recovery_codes: Mapped[list] = mapped_column(JSON, default=list)          # codes de secours 2FA (empreintes)
    last_login: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class UserSession(Base):
    """Session de connexion : révocable côté serveur (déconnexion, changement de mot de passe, suppression)."""
    __tablename__ = "user_sessions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(Integer, index=True)
    sid: Mapped[str] = mapped_column(String(48), unique=True, index=True)
    ip: Mapped[str] = mapped_column(String(64), default="")
    user_agent: Mapped[str] = mapped_column(String(256), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    last_seen: Mapped[datetime] = mapped_column(DateTime, default=now)
    expires_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "sid": self.sid, "ip": self.ip, "user_agent": self.user_agent, "created_at": self.created_at.isoformat() if self.created_at else None,
                "last_seen": self.last_seen.isoformat() if self.last_seen else None, "expires_at": self.expires_at.isoformat() if self.expires_at else None}


class ApiToken(Base):
    """Jeton d'API personnel (Authorization: Bearer …), stocké sous forme d'empreinte."""
    __tablename__ = "api_tokens"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(Integer, index=True)
    name: Mapped[str] = mapped_column(String(64), default="")
    prefix: Mapped[str] = mapped_column(String(16), default="")
    token_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    last_used: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    def to_dict(self) -> dict:
        return {"id": self.id, "name": self.name, "prefix": self.prefix, "created_at": self.created_at.isoformat() if self.created_at else None,
                "last_used": self.last_used.isoformat() if self.last_used else None, "expires_at": self.expires_at.isoformat() if self.expires_at else None}


class AuditLog(Base):
    """Journal d'audit : chaque action qui modifie quelque chose (méthode, route, utilisateur, IP, résultat)."""
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(64), default="")
    ip: Mapped[str] = mapped_column(String(64), default="")
    method: Mapped[str] = mapped_column(String(8), default="")
    path: Mapped[str] = mapped_column(String(256), default="")
    status: Mapped[int] = mapped_column(Integer, default=0)
    detail: Mapped[str] = mapped_column(String(512), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now, index=True)

    def to_dict(self) -> dict:
        return {"id": self.id, "username": self.username, "ip": self.ip, "method": self.method, "path": self.path, "status": self.status, "detail": self.detail,
                "created_at": self.created_at.isoformat() if self.created_at else None}


class GitDeploy(Base):
    """Déploiement Git d'un site : dépôt, branche, mode d'authentification, actualisation périodique, commande post-déploiement."""
    __tablename__ = "git_deploys"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    site_id: Mapped[int] = mapped_column(Integer, unique=True, index=True)
    repo_url: Mapped[str] = mapped_column(String(512), default="")
    branch: Mapped[str] = mapped_column(String(128), default="main")
    mode: Mapped[str] = mapped_column(String(16), default="https")        # https | ssh
    auth_user: Mapped[str] = mapped_column(String(128), default="")        # https : utilisateur (ou x-access-token)
    auth_token: Mapped[str] = mapped_column(String(512), default="")       # https : jeton / mot de passe d'application
    key_name: Mapped[str] = mapped_column(String(64), default="")          # ssh : "" = clé globale du panel, sinon clé dédiée au site
    auto_minutes: Mapped[int] = mapped_column(Integer, default=0)          # 0 = pas d'actualisation automatique
    post_command: Mapped[str] = mapped_column(Text, default="")            # exécutée dans la racine après chaque déploiement
    subdir: Mapped[str] = mapped_column(String(256), default="")           # sous-dossier du dépôt à servir (vide = racine)
    webhook_secret: Mapped[str] = mapped_column(String(128), default="")
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    last_run: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    last_status: Mapped[str] = mapped_column(String(16), default="")       # ok | error | skipped
    last_commit: Mapped[str] = mapped_column(String(64), default="")
    last_message: Mapped[str] = mapped_column(String(256), default="")
    last_output: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "site_id": self.site_id, "repo_url": self.repo_url, "branch": self.branch, "mode": self.mode, "auth_user": self.auth_user,
                "has_token": bool(self.auth_token), "key_name": self.key_name, "auto_minutes": self.auto_minutes, "post_command": self.post_command,
                "subdir": self.subdir, "has_webhook": bool(self.webhook_secret), "enabled": self.enabled,
                "last_run": self.last_run.isoformat() if self.last_run else None, "last_status": self.last_status, "last_commit": self.last_commit,
                "last_message": self.last_message, "last_output": (self.last_output or "")[-4000:], "created_at": self.created_at.isoformat() if self.created_at else None}


class Site(Base):
    __tablename__ = "sites"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(128), unique=True, nullable=False)
    domains: Mapped[list] = mapped_column(JSON, default=list)
    root: Mapped[str] = mapped_column(String(512), nullable=False)
    php_version: Mapped[str] = mapped_column(String(16), default="")   # "" = statique / autre
    site_type: Mapped[str] = mapped_column(String(32), default="php")  # php | static | proxy | node
    proxy_target: Mapped[str] = mapped_column(String(256), default="")
    ssl_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    ssl_cert: Mapped[str] = mapped_column(String(512), default="")
    ssl_key: Mapped[str] = mapped_column(String(512), default="")
    force_https: Mapped[bool] = mapped_column(Boolean, default=False)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    waf_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    php_isolation: Mapped[bool] = mapped_column(Boolean, default=False)   # open_basedir limité à la racine du site
    upstreams: Mapped[list] = mapped_column(JSON, default=list)            # répartition de charge : [{url, weight, backup, max_fails, fail_timeout}]
    lb_method: Mapped[str] = mapped_column(String(16), default="round_robin")  # round_robin | least_conn | ip_hash
    lb_keepalive: Mapped[int] = mapped_column(Integer, default=32)
    remark: Mapped[str] = mapped_column(String(256), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {
            "id": self.id, "name": self.name, "domains": self.domains or [], "root": self.root, "waf_enabled": self.waf_enabled, "php_isolation": self.php_isolation,
            "upstreams": self.upstreams or [], "lb_method": self.lb_method or "round_robin", "lb_keepalive": self.lb_keepalive if self.lb_keepalive is not None else 32,
            "php_version": self.php_version, "site_type": self.site_type, "proxy_target": self.proxy_target,
            "ssl_enabled": self.ssl_enabled, "ssl_cert": self.ssl_cert, "ssl_key": self.ssl_key,
            "force_https": self.force_https, "enabled": self.enabled, "remark": self.remark,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class Database(Base):
    __tablename__ = "databases"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    engine: Mapped[str] = mapped_column(String(16), default="mysql")  # mysql | postgres | sqlite
    username: Mapped[str] = mapped_column(String(64), default="")
    password: Mapped[str] = mapped_column(String(128), default="")
    host: Mapped[str] = mapped_column(String(128), default="localhost")
    remark: Mapped[str] = mapped_column(String(256), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self, with_password: bool = False) -> dict:
        d = {
            "id": self.id, "name": self.name, "engine": self.engine, "username": self.username,
            "host": self.host, "remark": self.remark,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if with_password:
            d["password"] = self.password
        return d


class FtpUser(Base):
    __tablename__ = "ftp_users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    password: Mapped[str] = mapped_column(String(128), nullable=False)
    home: Mapped[str] = mapped_column(String(512), nullable=False)
    perm: Mapped[str] = mapped_column(String(16), default="elradfmwMT")
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "username": self.username, "home": self.home, "perm": self.perm,
                "enabled": self.enabled, "created_at": self.created_at.isoformat() if self.created_at else None}


class CronJob(Base):
    __tablename__ = "cron_jobs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    schedule: Mapped[str] = mapped_column(String(64), nullable=False)  # expression cron 5 champs
    job_type: Mapped[str] = mapped_column(String(32), default="shell")  # shell | backup_site | backup_db | url
    target: Mapped[str] = mapped_column(Text, default="")  # commande, id de site, id de bdd, url
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    last_run: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    last_status: Mapped[str] = mapped_column(String(16), default="")
    last_output: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "name": self.name, "schedule": self.schedule, "job_type": self.job_type,
                "target": self.target, "enabled": self.enabled,
                "last_run": self.last_run.isoformat() if self.last_run else None,
                "last_status": self.last_status, "last_output": (self.last_output or "")[-4000:],
                "created_at": self.created_at.isoformat() if self.created_at else None}


class Backup(Base):
    __tablename__ = "backups"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)  # site | database | path
    target: Mapped[str] = mapped_column(String(256), nullable=False)
    path: Mapped[str] = mapped_column(String(512), nullable=False)
    size: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "kind": self.kind, "target": self.target, "path": self.path, "size": self.size,
                "created_at": self.created_at.isoformat() if self.created_at else None}


class FirewallRule(Base):
    __tablename__ = "firewall_rules"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    port: Mapped[str] = mapped_column(String(32), nullable=False)
    protocol: Mapped[str] = mapped_column(String(8), default="tcp")
    action: Mapped[str] = mapped_column(String(8), default="allow")  # allow | deny
    source: Mapped[str] = mapped_column(String(64), default="")  # ip/cidr, vide = tous
    remark: Mapped[str] = mapped_column(String(256), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "port": self.port, "protocol": self.protocol, "action": self.action,
                "source": self.source, "remark": self.remark,
                "created_at": self.created_at.isoformat() if self.created_at else None}


class LoginLog(Base):
    __tablename__ = "login_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(64), default="")
    ip: Mapped[str] = mapped_column(String(64), default="")
    success: Mapped[bool] = mapped_column(Boolean, default=False)
    detail: Mapped[str] = mapped_column(String(256), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "username": self.username, "ip": self.ip, "success": self.success,
                "detail": self.detail, "created_at": self.created_at.isoformat() if self.created_at else None}


class MonitorSample(Base):
    __tablename__ = "monitor_samples"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ts: Mapped[datetime] = mapped_column(DateTime, default=now, index=True)
    cpu: Mapped[float] = mapped_column(Float, default=0)
    mem: Mapped[float] = mapped_column(Float, default=0)
    disk: Mapped[float] = mapped_column(Float, default=0)
    net_in: Mapped[float] = mapped_column(Float, default=0)   # octets/s
    net_out: Mapped[float] = mapped_column(Float, default=0)
    load1: Mapped[float] = mapped_column(Float, default=0)

    def to_dict(self) -> dict:
        return {"ts": self.ts.isoformat(), "cpu": self.cpu, "mem": self.mem, "disk": self.disk,
                "net_in": self.net_in, "net_out": self.net_out, "load1": self.load1}


class Task(Base):
    """Tâches longues (installations logicielles, sauvegardes) avec journal."""
    __tablename__ = "tasks"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending | running | done | error
    log: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    finished_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    def to_dict(self) -> dict:
        return {"id": self.id, "name": self.name, "status": self.status, "log": (self.log or "")[-20000:],
                "created_at": self.created_at.isoformat() if self.created_at else None,
                "finished_at": self.finished_at.isoformat() if self.finished_at else None}


class MailDomain(Base):
    __tablename__ = "mail_domains"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    domain: Mapped[str] = mapped_column(String(253), unique=True, nullable=False)
    dkim_selector: Mapped[str] = mapped_column(String(32), default="toutpanel")
    dkim_private_key: Mapped[str] = mapped_column(Text, default="")
    dkim_public_key: Mapped[str] = mapped_column(Text, default="")
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "domain": self.domain, "dkim_selector": self.dkim_selector, "dkim": bool(self.dkim_private_key),
                "enabled": self.enabled, "created_at": self.created_at.isoformat() if self.created_at else None}


class Mailbox(Base):
    __tablename__ = "mailboxes"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    domain_id: Mapped[int] = mapped_column(Integer, ForeignKey("mail_domains.id", ondelete="CASCADE"), nullable=False)
    local_part: Mapped[str] = mapped_column(String(64), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(256), nullable=False)
    full_name: Mapped[str] = mapped_column(String(128), default="")
    quota_mb: Mapped[int] = mapped_column(Integer, default=1024)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self, domain: str = "") -> dict:
        return {"id": self.id, "domain_id": self.domain_id, "local_part": self.local_part, "address": f"{self.local_part}@{domain}" if domain else self.local_part,
                "full_name": self.full_name, "quota_mb": self.quota_mb, "enabled": self.enabled,
                "created_at": self.created_at.isoformat() if self.created_at else None}


class MailAlias(Base):
    __tablename__ = "mail_aliases"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    domain_id: Mapped[int] = mapped_column(Integer, ForeignKey("mail_domains.id", ondelete="CASCADE"), nullable=False)
    source: Mapped[str] = mapped_column(String(320), nullable=False)       # adresse complète ou @domaine (catch-all)
    destination: Mapped[str] = mapped_column(String(1024), nullable=False)  # une ou plusieurs adresses séparées par des virgules
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "domain_id": self.domain_id, "source": self.source, "destination": self.destination, "enabled": self.enabled,
                "created_at": self.created_at.isoformat() if self.created_at else None}


class WafRule(Base):
    """Règle WAF personnalisée : ip_block | ip_allow | ua_block | uri_block | query_block."""
    __tablename__ = "waf_rules"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    value: Mapped[str] = mapped_column(String(512), nullable=False)
    remark: Mapped[str] = mapped_column(String(256), default="")
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "kind": self.kind, "value": self.value, "remark": self.remark, "enabled": self.enabled,
                "created_at": self.created_at.isoformat() if self.created_at else None}


class WafBan(Base):
    __tablename__ = "waf_bans"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ip: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    reason: Mapped[str] = mapped_column(String(256), default="")
    until: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)  # None = permanent
    hits: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "ip": self.ip, "reason": self.reason, "until": self.until.isoformat() if self.until else None,
                "hits": self.hits, "created_at": self.created_at.isoformat() if self.created_at else None}


class DnsZone(Base):
    """Zone DNS gérée par le panel : servie par BIND (provider bind) ou poussée chez Cloudflare (provider cloudflare)."""
    __tablename__ = "dns_zones"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    domain: Mapped[str] = mapped_column(String(253), unique=True, nullable=False)
    provider: Mapped[str] = mapped_column(String(16), default="bind")
    ttl: Mapped[int] = mapped_column(Integer, default=3600)
    serial: Mapped[int] = mapped_column(Integer, default=0)
    admin_email: Mapped[str] = mapped_column(String(190), default="")
    cf_zone_id: Mapped[str] = mapped_column(String(64), default="")
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)

    def to_dict(self) -> dict:
        return {"id": self.id, "domain": self.domain, "provider": self.provider, "ttl": self.ttl, "serial": self.serial,
                "admin_email": self.admin_email, "cf_zone_id": self.cf_zone_id, "enabled": self.enabled,
                "created_at": self.created_at.isoformat() if self.created_at else None}


class DnsRecord(Base):
    __tablename__ = "dns_records"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    zone_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(8), nullable=False)
    name: Mapped[str] = mapped_column(String(253), default="@")
    value: Mapped[str] = mapped_column(Text, nullable=False)
    ttl: Mapped[int] = mapped_column(Integer, default=0)
    priority: Mapped[int] = mapped_column(Integer, default=0)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    remark: Mapped[str] = mapped_column(String(190), default="")

    def to_dict(self) -> dict:
        return {"id": self.id, "zone_id": self.zone_id, "type": self.type, "name": self.name, "value": self.value, "ttl": self.ttl,
                "priority": self.priority, "enabled": self.enabled, "remark": self.remark}
