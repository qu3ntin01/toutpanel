"""Ligne de commande : toutpanel start|run|stop|status|info|passwd|username|port|entrance|service|init"""
from __future__ import annotations
from typing import Optional

import argparse
import os
import signal
import subprocess
import sys
from pathlib import Path

from toutpanel import __version__, config


def _print_banner() -> None:
    print(f"ToutPanel {__version__} — {config.OS_NAME} — home: {config.HOME}")


def _ensure_admin_user() -> tuple[str, Optional[str]]:
    """Crée l'administrateur initial si absent. Retourne (username, mot de passe généré ou None)."""
    from toutpanel.db import init_db, session_scope
    from toutpanel.models import User
    from toutpanel.security import generate_password, hash_password

    init_db()
    with session_scope() as db:
        u = db.query(User).first()
        if u:
            return u.username, None
        pwd = generate_password(14)
        username = "admin"
        db.add(User(username=username, password_hash=hash_password(pwd)))
        (config.DATA_DIR / "initial_password.txt").write_text(f"{username}\n{pwd}\n", encoding="utf-8")
        config.restrict_file(config.DATA_DIR / "initial_password.txt")
        return username, pwd


def cmd_migrate(args) -> None:
    """Crée / met à jour le schéma de la base (tables et colonnes manquantes) sans démarrer le panel."""
    from toutpanel.db import get_engine, init_db

    config.ensure_dirs()
    init_db()
    from sqlalchemy import inspect

    tables = inspect(get_engine()).get_table_names()
    print(f"Base à jour : {len(tables)} tables ({config.DB_PATH})")
    s = config.get_settings()
    print(f"Réglages : port {s.get('panel_port')}, entrée {s.get('security_entrance') or '(aucune)'}, HTTPS {'oui' if s.get('panel_ssl') else 'non'}")


def cmd_info(args) -> None:
    from toutpanel.services.system_info import _local_ip

    s = config.get_settings()
    username, pwd = _ensure_admin_user()
    scheme = "https" if s.get("panel_ssl") else "http"
    ent = s.get("security_entrance") or ""
    _print_banner()
    print(f"URL      : {scheme}://{_local_ip()}:{s.get('panel_port')}{ent}")
    print(f"Utilisateur : {username}")
    pw_file = config.DATA_DIR / "initial_password.txt"
    if pwd:
        print(f"Mot de passe initial : {pwd}   (aussi dans {pw_file})")
    elif pw_file.exists():
        lines = pw_file.read_text(encoding="utf-8").splitlines()
        if len(lines) >= 2 and lines[0] == username:
            print(f"Mot de passe initial : {lines[1]}   (supprimez {pw_file} après l'avoir noté)")
        else:
            print("Mot de passe : (modifié — utilisez `toutpanel passwd` pour le réinitialiser)")
    else:
        print("Mot de passe : (inchangé — utilisez `toutpanel passwd` pour le réinitialiser)")


def cmd_run(args) -> None:
    import uvicorn

    from toutpanel.app import create_app

    config.ensure_dirs()
    s = config.get_settings()
    username, pwd = _ensure_admin_user()
    host = args.host or s.get("panel_host", "0.0.0.0")
    port = args.port or int(s.get("panel_port", 8888))
    kwargs = {}
    if s.get("panel_ssl"):
        from toutpanel.services.ssl import panel_cert

        cert, key = panel_cert()
        kwargs = {"ssl_certfile": str(cert), "ssl_keyfile": str(key)}
    try:
        config.PID_PATH.write_text(str(os.getpid()), encoding="utf-8")
    except OSError:
        pass
    cmd_info(args)
    uvicorn.run(create_app(), host=host, port=port, log_level="info", access_log=False, **kwargs)


def cmd_start(args) -> None:
    """Démarre en arrière-plan (nohup / processus détaché)."""
    if _running_pid():
        print("Le panel est déjà démarré (pid", _running_pid(), ")")
        return
    config.ensure_dirs()
    log = open(config.LOG_DIR / "panel.out", "ab")
    cmd = [sys.executable, "-m", "toutpanel", "run"]
    if config.IS_WINDOWS:
        flags = subprocess.CREATE_NEW_PROCESS_GROUP | getattr(subprocess, "DETACHED_PROCESS", 0x00000008)
        p = subprocess.Popen(cmd, stdout=log, stderr=log, creationflags=flags, close_fds=True)
    else:
        p = subprocess.Popen(cmd, stdout=log, stderr=log, start_new_session=True, close_fds=True)
    print("Panel démarré (pid", p.pid, ")")
    cmd_info(args)


def _running_pid() -> Optional[int]:
    try:
        pid = int(config.PID_PATH.read_text().strip())
    except (OSError, ValueError):
        return None
    try:
        import psutil

        if psutil.pid_exists(pid) and "toutpanel" in " ".join(psutil.Process(pid).cmdline()).lower():
            return pid
    except Exception:
        return None
    return None


def cmd_stop(args) -> None:
    pid = _running_pid()
    if not pid:
        print("Le panel n'est pas démarré.")
        return
    try:
        if config.IS_WINDOWS:
            subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
        else:
            os.kill(pid, signal.SIGTERM)
    except OSError as e:
        print("Erreur :", e)
        return
    config.PID_PATH.unlink(missing_ok=True)
    print("Panel arrêté.")


def cmd_restart(args) -> None:
    cmd_stop(args)
    import time

    time.sleep(1)
    cmd_start(args)


def cmd_status(args) -> None:
    pid = _running_pid()
    print("Statut :", f"démarré (pid {pid})" if pid else "arrêté")


def cmd_passwd(args) -> None:
    from toutpanel.db import init_db, session_scope
    from toutpanel.models import User
    from toutpanel.security import generate_password, hash_password

    init_db()
    pwd = args.password or generate_password(14)
    with session_scope() as db:
        u = db.query(User).first()
        if not u:
            _ensure_admin_user()
            u = db.query(User).first()
        u.password_hash = hash_password(pwd)
        (config.DATA_DIR / "initial_password.txt").unlink(missing_ok=True)
        if args.disable_2fa:
            u.totp_enabled = False
            u.totp_secret = None
        print(f"Mot de passe de {u.username} défini sur : {pwd}")


def cmd_username(args) -> None:
    from toutpanel.db import init_db, session_scope
    from toutpanel.models import User

    init_db()
    with session_scope() as db:
        u = db.query(User).first()
        if not u:
            _ensure_admin_user()
            u = db.query(User).first()
        u.username = args.username
        print("Nom d'utilisateur défini sur :", args.username)


def cmd_port(args) -> None:
    config.get_settings().set("panel_port", int(args.port))
    print("Port du panel :", args.port, "(redémarrez le panel)")


def cmd_entrance(args) -> None:
    val = args.path.strip()
    if val and not val.startswith("/"):
        val = "/" + val
    config.get_settings().set("security_entrance", val)
    print("Entrée sécurisée :", val or "(désactivée)")


def cmd_ssl(args) -> None:
    config.get_settings().set("panel_ssl", args.state == "on")
    print("SSL du panel :", args.state, "(redémarrez le panel)")


def cmd_service(args) -> None:
    exe = sys.executable
    if config.IS_WINDOWS:
        task = "ToutPanel"
        if args.action == "install":
            r = subprocess.run(["schtasks", "/Create", "/F", "/SC", "ONSTART", "/RU", "SYSTEM", "/RL", "HIGHEST",
                                "/TN", task, "/TR", f'"{exe}" -m toutpanel run'], capture_output=True, text=True)
            print(r.stdout or r.stderr)
            subprocess.run(["schtasks", "/Run", "/TN", task], capture_output=True)
            print("Tâche planifiée ToutPanel créée (démarrage automatique) et lancée.")
        else:
            subprocess.run(["schtasks", "/End", "/TN", task], capture_output=True)
            r = subprocess.run(["schtasks", "/Delete", "/F", "/TN", task], capture_output=True, text=True)
            print(r.stdout or r.stderr)
        return
    unit = Path("/etc/systemd/system/toutpanel.service")
    if args.action == "install":
        unit.write_text(f"""[Unit]
Description=ToutPanel - panel d'hébergement web
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Environment=TOUTPANEL_HOME={config.HOME}
Environment=PYTHONUNBUFFERED=1
ExecStart={exe} -m toutpanel run
Restart=always
RestartSec=3
TimeoutStopSec=20
LimitNOFILE=65536
User=root
PrivateTmp=true
ProtectHostname=true
ProtectClock=true
ProtectKernelTunables=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
""", encoding="utf-8")
        subprocess.run(["systemctl", "daemon-reload"])
        subprocess.run(["systemctl", "enable", "--now", "toutpanel"])
        print("Service systemd toutpanel installé et démarré.")
    else:
        subprocess.run(["systemctl", "disable", "--now", "toutpanel"])
        unit.unlink(missing_ok=True)
        subprocess.run(["systemctl", "daemon-reload"])
        print("Service systemd supprimé.")


def cmd_init(args) -> None:
    config.ensure_dirs()
    cmd_info(args)


def cmd_setup(args) -> None:
    """Configuration initiale scriptable : compte admin, entrée sécurisée, port (utilisé par install.sh / install.ps1)."""
    import json

    from toutpanel.db import init_db, session_scope
    from toutpanel.models import User
    from toutpanel.security import generate_password, hash_password

    config.ensure_dirs()
    init_db()
    s = config.get_settings()
    username = args.username or ("admin_" + generate_password(6).lower())
    password = args.password or generate_password(16)
    entrance = args.entrance if args.entrance is not None else ("/tp_" + generate_password(10).lower())
    if entrance and not entrance.startswith("/"):
        entrance = "/" + entrance
    with session_scope() as db:
        u = db.query(User).first()
        if u:
            u.username, u.password_hash = username, hash_password(password)
        else:
            db.add(User(username=username, password_hash=hash_password(password)))
    s.set("security_entrance", entrance)
    if args.port:
        s.set("panel_port", int(args.port))
    if args.ssl is not None:
        s.set("panel_ssl", bool(args.ssl))
    (config.DATA_DIR / "initial_password.txt").write_text(f"{username}\n{password}\n", encoding="utf-8")
    info = {"username": username, "password": password, "entrance": entrance, "port": s.get("panel_port"), "ssl": s.get("panel_ssl")}
    if args.json:
        print(json.dumps(info))
    else:
        print(f"Utilisateur : {username}\nMot de passe : {password}\nEntrée sécurisée : {entrance}\nPort : {s.get('panel_port')}")


def cmd_dbroot(args) -> None:
    """Enregistre les identifiants administrateur d'un moteur de base de données (MySQL/MariaDB ou PostgreSQL)."""
    from toutpanel.services import databases

    creds = databases.get_root_credentials(args.engine)
    if args.host:
        creds["host"] = args.host
    if args.port:
        creds["port"] = int(args.port)
    if args.user:
        creds["user"] = args.user
    if args.password is not None:
        creds["password"] = args.password
    databases.set_root_credentials(args.engine, creds)
    print(f"Identifiants {args.engine} enregistrés ({creds.get('user')}@{creds.get('host')}:{creds.get('port')}).")


SUPPORTED = {
    "linux": "Debian 11+, Ubuntu 20.04+, Fedora 39+, AlmaLinux 9/10, Rocky Linux 9/10, RHEL 9/10 (Arch, Alpine, openSUSE : pile réduite)",
    "windows": "Windows 10 / 11, Windows Server 2016 / 2019 / 2022 / 2025",
}


def cmd_check(args) -> None:
    """Diagnostic de compatibilité : OS, Python, droits, init, SELinux, gestionnaire de paquets, serveur web, ports."""
    import platform as _pl
    import socket

    from toutpanel.platform import get_platform

    plat = get_platform()
    info = plat.os_info()
    rows: list[tuple[str, str, str]] = []  # (état, sujet, détail)

    def add(ok, subject, detail):
        rows.append(("OK " if ok is True else "!! " if ok is False else "-- ", subject, detail))

    add(True, "Système", info.get("pretty", ""))
    add(sys.version_info >= (3, 9), "Python", f"{_pl.python_version()} (3.9+ requis)")
    add(plat.is_admin(), "Droits administrateur", "oui" if plat.is_admin() else "non : lancez en root / administrateur")
    if config.IS_WINDOWS:
        build = 0
        try:
            build = int(sys.getwindowsversion().build)  # type: ignore[attr-defined]
        except Exception:
            pass
        add(build >= 14393 if build else None, "Version Windows", f"build {build or '?'} (Windows 10 / Server 2016 = 14393 minimum)")
        add(bool(plat.which("powershell")), "PowerShell", "présent" if plat.which("powershell") else "absent")
        try:
            import winpty  # noqa: F401

            add(True, "Terminal (pywinpty)", "disponible")
        except ImportError:
            add(None, "Terminal (pywinpty)", "absent : terminal en mode simplifié")
    else:
        ri = plat.rhel_info() if hasattr(plat, "rhel_info") else {}
        ids = (info.get("distro_id", "") + " " + info.get("distro_like", "")).lower()
        known = any(k in ids for k in ("debian", "ubuntu", "fedora", "rhel", "rocky", "alma", "centos"))
        add(True if known else None, "Distribution", f"{info.get('distro_id', '?')} {ri.get('major', '')} — {'prise en charge' if known else 'non testée (Arch/Alpine/openSUSE : pile réduite)'}")
        add(bool(plat.package_manager()), "Gestionnaire de paquets", plat.package_manager() or "aucun")
        add(bool(plat.which("systemctl")), "systemd", "présent" if plat.which("systemctl") else "absent (service toutpanel non installable ; utilisez toutpanel start)")
        st = plat.selinux_status()
        marker = config.DATA_DIR / ".selinux-configured"
        add(True if st in ("", "disabled") or marker.exists() else None, "SELinux", f"{st or 'absent'}" + (" — contextes configurés" if marker.exists() else " — sera configuré au démarrage du panel" if st in ("enforcing", "permissive") else ""))
        add(True if plat.firewall_backend() else None, "Pare-feu", plat.firewall_backend() or "aucun (ufw / firewalld / iptables)")
    from toutpanel.services import webserver

    add(True if webserver.is_installed() else None, "Serveur web", f"{webserver.detect()} ({'installé' if webserver.is_installed() else 'non installé : page Logiciels'})")
    add(True if webserver.php_versions() else None, "PHP", ", ".join(webserver.php_versions()) or "aucune version (page PHP)")
    from toutpanel.services import databases

    add(True if databases.engine_available("mysql") else None, "MySQL / MariaDB", "présent" if databases.engine_available("mysql") else "absent (page Logiciels)")
    port = int(config.get_settings().get("panel_port", 8888))
    try:
        sock = socket.socket()
        sock.bind(("0.0.0.0", port))
        sock.close()
        add(True, f"Port du panel {port}", "libre")
    except OSError:
        add(None, f"Port du panel {port}", "occupé (panel déjà démarré ?)")
    add(True, "Répertoire du panel", str(config.HOME))
    _print_banner()
    print(f"Plateformes prises en charge : {SUPPORTED['windows' if config.IS_WINDOWS else 'linux']}\n")
    for state, subject, detail in rows:
        print(f"[{state.strip() or '--':>2}] {subject:<26} {detail}")
    bad = [r for r in rows if r[0] == "!! "]
    print("\n" + ("Tout est prêt." if not bad else f"{len(bad)} point(s) bloquant(s) à corriger."))
    if bad:
        sys.exit(1)


def cmd_selinux(args) -> None:
    from toutpanel.platform import get_platform

    plat = get_platform()
    if not hasattr(plat, "selinux_setup"):
        print("SELinux : non applicable sur cette plateforme.")
        return
    for m in plat.selinux_setup(str(config.WWW_ROOT), str(config.HOME)):
        print(m)
    config.ensure_dirs()
    (config.DATA_DIR / ".selinux-configured").write_text("ok", encoding="utf-8")


def cmd_php(args) -> None:
    """Installation / suppression synchrone d'une version de PHP (utilisée par les installeurs)."""
    from toutpanel.db import init_db
    from toutpanel.services import php, tasks

    config.ensure_dirs()
    init_db()
    fn = php.install if args.action == "install" else php.remove
    tid = fn(args.version) if args.action == "remove" else fn(args.version, args.extensions.split(",") if args.extensions else None)
    import time

    last = ""
    while True:
        t = tasks.get_task(tid)
        if t["log"] != last:
            print(t["log"][len(last):], end="", flush=True)
            last = t["log"]
        if t["status"] in ("done", "error"):
            break
        time.sleep(1)
    sys.exit(0 if t["status"] == "done" else 1)


def _wait_task(tid: int) -> int:
    from toutpanel.services import tasks
    import time

    last = ""
    while True:
        t = tasks.get_task(tid)
        if t["log"] != last:
            print(t["log"][len(last):], end="", flush=True)
            last = t["log"]
        if t["status"] in ("done", "error"):
            return 0 if t["status"] == "done" else 1
        time.sleep(1)


def cmd_waf(args) -> None:
    """Moteur WAF : état, installation / suppression de BunkerWeb ou SafeLine, synchronisation des sites."""
    from toutpanel.db import init_db, session_scope
    from toutpanel.services import waf_engines

    config.ensure_dirs()
    init_db()
    if args.action == "status":
        st = waf_engines.status()
        print(f"Moteur actif : {st['engine']}   Docker : {'oui' if st['docker'] else 'non'}   Ports vhosts : {st['web_ports'][0]} / {st['web_ports'][1]}")
        for k, e in st["engines"].items():
            print(f"  {k:10} {e['state'] or '-':8} {e['ui_url']}")
        return
    if args.action == "install":
        opts = {"web_http_port": args.http_port, "web_https_port": args.https_port, "lets_encrypt": bool(args.lets_encrypt), "email": args.email or "", "api_token": args.token or ""}
        sys.exit(_wait_task(waf_engines.install(args.engine, opts)))
    if args.action == "remove":
        sys.exit(_wait_task(waf_engines.uninstall(args.engine)))
    if args.action == "sync":
        with session_scope() as db:
            err = waf_engines.sync(args.engine, db, print)
        if err:
            print(err)
            sys.exit(1)


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(prog="toutpanel", description="ToutPanel — panel d'hébergement web")
    parser.add_argument("--version", action="version", version=__version__)
    sub = parser.add_subparsers(dest="cmd")
    p = sub.add_parser("run", help="démarrer au premier plan")
    p.add_argument("--host")
    p.add_argument("--port", type=int)
    p.set_defaults(fn=cmd_run)
    sub.add_parser("start", help="démarrer en arrière-plan").set_defaults(fn=cmd_start)
    sub.add_parser("stop", help="arrêter").set_defaults(fn=cmd_stop)
    sub.add_parser("restart", help="redémarrer").set_defaults(fn=cmd_restart)
    sub.add_parser("status", help="état").set_defaults(fn=cmd_status)
    sub.add_parser("info", help="URL et identifiants").set_defaults(fn=cmd_info)
    sub.add_parser("migrate", help="créer / mettre à jour le schéma de la base (après une mise à jour)").set_defaults(fn=cmd_migrate)
    sub.add_parser("init", help="créer les répertoires et l'administrateur").set_defaults(fn=cmd_init)
    p = sub.add_parser("setup", help="configuration initiale : compte admin, entrée sécurisée, port (valeurs aléatoires si omises)")
    p.add_argument("--username")
    p.add_argument("--password")
    p.add_argument("--entrance", help="ex: /mon-acces ; chaîne vide pour désactiver")
    p.add_argument("--port", type=int)
    p.add_argument("--ssl", type=lambda v: v.lower() in ("1", "on", "true", "yes"), default=None)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_setup)
    p = sub.add_parser("dbroot", help="identifiants root d'un moteur de base de données")
    p.add_argument("engine", choices=["mysql", "postgres"])
    p.add_argument("--host")
    p.add_argument("--port", type=int)
    p.add_argument("--user")
    p.add_argument("--password")
    p.set_defaults(fn=cmd_dbroot)
    p = sub.add_parser("passwd", help="réinitialiser le mot de passe")
    p.add_argument("password", nargs="?")
    p.add_argument("--disable-2fa", action="store_true")
    p.set_defaults(fn=cmd_passwd)
    p = sub.add_parser("username", help="changer le nom d'utilisateur")
    p.add_argument("username")
    p.set_defaults(fn=cmd_username)
    p = sub.add_parser("port", help="changer le port")
    p.add_argument("port", type=int)
    p.set_defaults(fn=cmd_port)
    p = sub.add_parser("entrance", help="définir l'entrée sécurisée (ex: /monpanel, vide pour désactiver)")
    p.add_argument("path", nargs="?", default="")
    p.set_defaults(fn=cmd_entrance)
    p = sub.add_parser("ssl", help="activer/désactiver le HTTPS du panel")
    p.add_argument("state", choices=["on", "off"])
    p.set_defaults(fn=cmd_ssl)
    sub.add_parser("check", help="diagnostic de compatibilité de la machine").set_defaults(fn=cmd_check)
    sub.add_parser("selinux", help="appliquer les contextes SELinux (Alma/Rocky/RHEL/Fedora)").set_defaults(fn=cmd_selinux)
    p = sub.add_parser("waf", help="moteur WAF : status | install | remove | sync (bunkerweb, safeline)")
    p.add_argument("action", choices=["status", "install", "remove", "sync"])
    p.add_argument("engine", nargs="?", default="bunkerweb", choices=["bunkerweb", "safeline"])
    p.add_argument("--http-port", type=int, default=8080, help="port de repli HTTP du serveur web (défaut 8080)")
    p.add_argument("--https-port", type=int, default=8443)
    p.add_argument("--lets-encrypt", action="store_true", help="BunkerWeb : certificats Let's Encrypt automatiques")
    p.add_argument("--email", help="e-mail Let's Encrypt")
    p.add_argument("--token", help="SafeLine : jeton API pour créer les sites automatiquement")
    p.set_defaults(fn=cmd_waf)
    p = sub.add_parser("php", help="installer / supprimer une version de PHP")
    p.add_argument("action", choices=["install", "remove"])
    p.add_argument("version")
    p.add_argument("--extensions", help="liste séparée par des virgules")
    p.set_defaults(fn=cmd_php)
    p = sub.add_parser("service", help="installer/désinstaller le service système")
    p.add_argument("action", choices=["install", "uninstall"])
    p.set_defaults(fn=cmd_service)
    args = parser.parse_args(argv)
    if not args.cmd:
        parser.print_help()
        return
    args.fn(args)


if __name__ == "__main__":
    main()
