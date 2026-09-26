"""Alertes : e-mail (SMTP local ou externe), webhook JSON (Slack, Discord, n8n…) et Telegram.
Événements : service arrêté, disque presque plein, certificat qui expire, connexion depuis une nouvelle adresse,
bannissement WAF, échec de déploiement Git, sauvegarde échouée. Chaque alerte n'est envoyée qu'une fois par état
(pas de répétition toutes les heures tant que le problème persiste)."""
from __future__ import annotations

import json
import logging
import smtplib
import threading
import time
import urllib.request
from email.message import EmailMessage
from typing import Optional

from toutpanel import config

log = logging.getLogger("toutpanel.notify")

DEFAULTS = {
    "notify_email": "", "notify_smtp_host": "127.0.0.1", "notify_smtp_port": 25, "notify_smtp_user": "", "notify_smtp_password": "",
    "notify_smtp_tls": False, "notify_from": "", "notify_webhook_url": "", "notify_telegram_token": "", "notify_telegram_chat": "",
    "notify_on_login": True, "notify_on_service": True, "notify_on_disk": True, "notify_disk_threshold": 90, "notify_on_cert": True,
    "notify_on_ban": False, "notify_on_git": True, "notify_on_backup": True, "notify_on_upstream": True, "notify_interval_min": 15,
}
EVENT_LABELS = {"login": "Connexion depuis une nouvelle adresse", "service": "Service arrêté", "disk": "Disque presque plein",
                "cert": "Certificat proche de l'expiration", "ban": "Adresse bannie par le WAF", "git": "Déploiement Git en échec",
                "backup": "Sauvegarde en échec", "upstream": "Serveur en amont (répartition de charge) injoignable", "test": "Message de test"}
_state_lock = threading.Lock()


def settings() -> dict:
    s = config.get_settings()
    return {k: s.get(k, v) for k, v in DEFAULTS.items()}


def channels() -> list[str]:
    st = settings()
    out = []
    if st["notify_email"]:
        out.append("email")
    if st["notify_webhook_url"]:
        out.append("webhook")
    if st["notify_telegram_token"] and st["notify_telegram_chat"]:
        out.append("telegram")
    return out


# --------------------------------------------------------------------------- envoi

def _send_email(subject: str, body: str) -> str:
    st = settings()
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = st["notify_from"] or f"toutpanel@{__import__('socket').gethostname()}"
    msg["To"] = st["notify_email"]
    msg.set_content(body)
    try:
        with smtplib.SMTP(st["notify_smtp_host"] or "127.0.0.1", int(st["notify_smtp_port"] or 25), timeout=20) as s:
            if st["notify_smtp_tls"]:
                s.starttls()
            if st["notify_smtp_user"]:
                s.login(st["notify_smtp_user"], st["notify_smtp_password"])
            s.send_message(msg)
        return ""
    except Exception as e:  # noqa: BLE001
        return f"e-mail : {e}"


def _post_json(url: str, payload: dict) -> str:
    try:
        req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json", "User-Agent": "ToutPanel"}, method="POST")
        with urllib.request.urlopen(req, timeout=15) as resp:
            if resp.status >= 400:
                return f"webhook : HTTP {resp.status}"
        return ""
    except Exception as e:  # noqa: BLE001
        return f"webhook : {e}"


def _send_webhook(event: str, subject: str, body: str) -> str:
    st = settings()
    return _post_json(st["notify_webhook_url"], {"source": "toutpanel", "event": event, "title": subject, "text": f"{subject}\n{body}",
                                                  "content": f"**{subject}**\n{body}", "host": __import__("socket").gethostname(), "time": time.time()})


def _send_telegram(subject: str, body: str) -> str:
    st = settings()
    url = f"https://api.telegram.org/bot{st['notify_telegram_token']}/sendMessage"
    return _post_json(url, {"chat_id": st["notify_telegram_chat"], "text": f"{subject}\n\n{body}"[:4000]})


def send(event: str, subject: str, body: str, force: bool = False) -> list[str]:
    """Envoie sur tous les canaux configurés. Retourne la liste des erreurs. `force` ignore les préférences par événement."""
    st = settings()
    if not force and event != "test" and not st.get(f"notify_on_{event}", True):
        return []
    host = __import__("socket").gethostname()
    subject = f"[{config.get_settings().get('panel_name', 'ToutPanel')} · {host}] {subject}"
    errors = []
    for ch in channels():
        err = {"email": lambda: _send_email(subject, body), "webhook": lambda: _send_webhook(event, subject, body), "telegram": lambda: _send_telegram(subject, body)}[ch]()
        if err:
            errors.append(err)
            log.warning("notification %s : %s", ch, err)
    return errors


def send_async(event: str, subject: str, body: str) -> None:
    if not channels():
        return
    threading.Thread(target=send, args=(event, subject, body), daemon=True, name="notify").start()


# --------------------------------------------------------------------------- état (une alerte par changement)

def _state_path():
    return config.DATA_DIR / "notify_state.json"


def _load_state() -> dict:
    try:
        return json.loads(_state_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_state(st: dict) -> None:
    try:
        config.atomic_write(_state_path(), json.dumps(st), mode=0o600)
    except OSError:
        pass


def alert_once(key: str, active: bool, event: str, subject: str, body: str) -> bool:
    """Envoie l'alerte quand `key` passe à l'état actif, et un message de retour à la normale quand elle disparaît."""
    with _state_lock:
        st = _load_state()
        was = bool(st.get(key))
        if active and not was:
            st[key] = time.time()
            _save_state(st)
            send_async(event, subject, body)
            return True
        if not active and was:
            st.pop(key, None)
            _save_state(st)
            send_async(event, "Rétabli : " + subject, "Le problème signalé précédemment n'est plus détecté.\n" + body)
    return False


# --------------------------------------------------------------------------- vérifications périodiques

def check_all() -> dict:
    """Services attendus, disques, certificats. Appelé par le planificateur ; utilisable à la demande (bouton « vérifier »)."""
    st = settings()
    res = {"services": [], "disks": [], "certs": [], "upstreams": []}
    if not channels():
        return res
    try:
        from toutpanel.db import session_scope
        from toutpanel.models import Site
        from toutpanel.services import loadbalancer

        with session_scope() as db:
            sites = [s.to_dict() for s in db.query(Site).filter(Site.site_type == "proxy", Site.enabled.is_(True)).all() if s.upstreams]
        for site in sites:
            for r in loadbalancer.check_site(site):
                if not r["ok"]:
                    res["upstreams"].append({"site": site["name"], "url": r["url"]})
                alert_once(f"upstream:{site['name']}:{r['url']}", not r["ok"], "upstream", f"serveur {r['url']} injoignable ({site['name']})",
                           f"Le serveur en amont {r['url']} du site {site['name']} ne répond pas ({r.get('error') or 'HTTP ' + str(r['status'])}). "
                           "Le trafic est réparti sur les autres serveurs du groupe.")
    except Exception as e:  # noqa: BLE001
        log.debug("check upstreams : %s", e)
    try:
        from toutpanel.services import system_info

        watched = set(config.get_settings().get("notify_services") or ["nginx", "apache", "mysql", "postgresql", "php-fpm", "redis", "docker", "memcached"])
        for svc in system_info.services_summary():
            name = svc.get("label", "")
            if svc.get("builtin") or svc.get("status") == "missing" or name not in watched:
                continue
            down = svc.get("status") == "stopped"
            if down:
                res["services"].append(name)
            alert_once(f"service:{name}", down, "service", f"service {name} arrêté",
                       f"Le service {name} ({svc.get('service') or name}) est arrêté. Redémarrez-le depuis le tableau de bord ou vérifiez ses journaux.")
    except Exception as e:  # noqa: BLE001
        log.debug("check services : %s", e)
    try:
        import psutil

        seen = set()
        for part in psutil.disk_partitions(all=False):
            if part.mountpoint in seen or part.fstype in ("squashfs", "overlay", "tmpfs", "devtmpfs"):
                continue
            seen.add(part.mountpoint)
            try:
                u = psutil.disk_usage(part.mountpoint)
            except OSError:
                continue
            full = u.percent >= float(st["notify_disk_threshold"] or 90)
            if full:
                res["disks"].append({"mount": part.mountpoint, "percent": u.percent})
            alert_once(f"disk:{part.mountpoint}", full, "disk", f"disque {part.mountpoint} à {u.percent:.0f} %",
                       f"Le volume {part.mountpoint} est rempli à {u.percent:.0f} % ({u.free // (1024**3)} Go libres). Libérez de l'espace (sauvegardes, journaux, tmp).")
    except Exception as e:  # noqa: BLE001
        log.debug("check disks : %s", e)
    try:
        from toutpanel.services import ssl as ssl_svc

        exp = ssl_svc.expiring_sites(14)
        res["certs"] = exp
        for e in exp:
            alert_once(f"cert:{e['site']}", True, "cert", f"certificat de {e['site']} expire dans {e['days_left']} j",
                       f"Le certificat de {', '.join(e['domains'])} expire dans {e['days_left']} jour(s). Le renouvellement automatique (certbot) tourne chaque nuit ; "
                       "vérifiez qu'il réussit ou renouvelez depuis la page Sites → SSL.")
        active = {e["site"] for e in exp}
        with _state_lock:
            stt = _load_state()
            for k in [k for k in stt if k.startswith("cert:") and k[5:] not in active]:
                stt.pop(k)
            _save_state(stt)
    except Exception as e:  # noqa: BLE001
        log.debug("check certs : %s", e)
    return res


def notify_login(username: str, ip: str, user_agent: str) -> None:
    """Connexion réussie : alerte si l'adresse n'a jamais été vue pour ce compte (les 50 dernières adresses sont mémorisées)."""
    if not settings()["notify_on_login"] or not channels():
        return
    with _state_lock:
        st = _load_state()
        known = st.setdefault("login_ips", {}).setdefault(username, [])
        new = ip not in known
        if new:
            known.append(ip)
            del known[:-50]
            _save_state(st)
    if new and len(known) > 1:  # la toute première connexion n'est pas une anomalie
        send_async("login", f"connexion de {username} depuis {ip}", f"Nouvelle adresse pour le compte {username} : {ip}\nNavigateur : {user_agent[:200]}\n"
                   "Si ce n'est pas vous, changez le mot de passe et révoquez les sessions (Réglages → Utilisateurs).")


def _job() -> None:
    try:
        check_all()
    except Exception as e:  # noqa: BLE001
        log.warning("vérifications : %s", e)


def start() -> None:
    from apscheduler.triggers.interval import IntervalTrigger

    from toutpanel.services.cron import get_scheduler

    sched = get_scheduler()
    if sched.get_job("notify-check"):
        sched.remove_job("notify-check")
    minutes = max(1, int(settings()["notify_interval_min"] or 15))
    sched.add_job(_job, IntervalTrigger(minutes=minutes), id="notify-check", replace_existing=True, misfire_grace_time=300, coalesce=True, max_instances=1)
