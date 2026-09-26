"""Magasin de logiciels : installation/suppression via le gestionnaire de paquets du système."""
from __future__ import annotations

from pathlib import Path

from toutpanel import config
from toutpanel.platform import get_platform
from toutpanel.services import tasks

# Catalogue : id -> infos + paquets par famille de distribution / Windows (winget id)
CATALOG: list[dict] = [
    {"id": "nginx", "name": "Nginx", "category": "web", "desc": "Serveur web / reverse proxy haute performance.",
     "pkgs": {"debian": ["nginx"], "rhel": ["nginx"], "arch": ["nginx"], "alpine": ["nginx"], "suse": ["nginx"], "winget": ["nginx.nginx"]},
     "service": "nginx", "bin": "nginx"},
    {"id": "apache", "name": "Apache HTTPD", "category": "web", "desc": "Serveur web Apache 2.4.",
     "pkgs": {"debian": ["apache2"], "rhel": ["httpd"], "arch": ["apache"], "alpine": ["apache2"], "suse": ["apache2"], "winget": ["ApacheFriends.Xampp.8.2"]},
     "service": "apache2", "bin": "apache2"},
    {"id": "php83", "name": "PHP 8.3", "category": "php", "desc": "PHP 8.3 + FPM + extensions courantes.",
     "pkgs": {"debian": ["php8.3-fpm", "php8.3-cli", "php8.3-mysql", "php8.3-curl", "php8.3-mbstring", "php8.3-xml", "php8.3-zip", "php8.3-gd", "php8.3-intl"],
              "rhel": ["php-fpm", "php-cli", "php-mysqlnd", "php-mbstring", "php-xml", "php-gd", "php-intl"], "arch": ["php", "php-fpm"], "alpine": ["php83", "php83-fpm"],
              "suse": ["php8", "php8-fpm"], "winget": ["PHP.PHP.8.3"]},
     "service": "php8.3-fpm", "bin": "php8.3"},
    {"id": "php82", "name": "PHP 8.2", "category": "php", "desc": "PHP 8.2 + FPM + extensions courantes.",
     "pkgs": {"debian": ["php8.2-fpm", "php8.2-cli", "php8.2-mysql", "php8.2-curl", "php8.2-mbstring", "php8.2-xml", "php8.2-zip", "php8.2-gd", "php8.2-intl"],
              "rhel": ["php-fpm", "php-cli", "php-mysqlnd"], "alpine": ["php82", "php82-fpm"], "winget": ["PHP.PHP.8.2"]},
     "service": "php8.2-fpm", "bin": "php8.2"},
    {"id": "php81", "name": "PHP 8.1", "category": "php", "desc": "PHP 8.1 + FPM.",
     "pkgs": {"debian": ["php8.1-fpm", "php8.1-cli", "php8.1-mysql", "php8.1-curl", "php8.1-mbstring", "php8.1-xml", "php8.1-zip", "php8.1-gd"],
              "alpine": ["php81", "php81-fpm"], "winget": ["PHP.PHP.8.1"]},
     "service": "php8.1-fpm", "bin": "php8.1"},
    {"id": "mariadb", "name": "MariaDB", "category": "database", "desc": "Serveur de bases de données compatible MySQL.",
     "pkgs": {"debian": ["mariadb-server", "mariadb-client"], "rhel": ["mariadb-server"], "arch": ["mariadb"], "alpine": ["mariadb", "mariadb-client"],
              "suse": ["mariadb"], "winget": ["MariaDB.Server"]},
     "service": "mariadb", "bin": "mariadbd"},
    {"id": "mysql", "name": "MySQL", "category": "database", "desc": "Serveur MySQL communautaire.",
     "pkgs": {"debian": ["mysql-server"], "rhel": ["mysql-server"], "winget": ["Oracle.MySQL"]},
     "service": "mysql", "bin": "mysqld"},
    {"id": "postgresql", "name": "PostgreSQL", "category": "database", "desc": "Base de données relationnelle avancée.",
     "pkgs": {"debian": ["postgresql"], "rhel": ["postgresql-server"], "arch": ["postgresql"], "alpine": ["postgresql"], "suse": ["postgresql-server"],
              "winget": ["PostgreSQL.PostgreSQL.16"]},
     "service": "postgresql", "bin": "psql"},
    {"id": "redis", "name": "Redis / Valkey", "category": "database", "desc": "Cache / base clé-valeur en mémoire (Valkey sur Alma/Rocky 10 et Fedora récentes).",
     "pkgs": {"debian": ["redis-server"], "rhel": ["redis"], "arch": ["redis"], "alpine": ["redis"], "suse": ["redis"], "winget": ["Redis.Redis"]},
     "fallback": {"rhel": ["valkey"]}, "service": "redis-server", "bin": "redis-server"},
    {"id": "memcached", "name": "Memcached", "category": "database", "desc": "Cache mémoire distribué.",
     "pkgs": {"debian": ["memcached"], "rhel": ["memcached"], "arch": ["memcached"], "alpine": ["memcached"]},
     "service": "memcached", "bin": "memcached"},
    {"id": "docker", "name": "Docker", "category": "tools", "desc": "Moteur de conteneurs (Docker CE depuis download.docker.com sur RHEL/Fedora).",
     "pkgs": {"debian": ["docker.io", "docker-compose-v2"], "rhel": ["docker-ce", "docker-ce-cli", "containerd.io", "docker-compose-plugin"], "arch": ["docker"],
              "alpine": ["docker"], "suse": ["docker"], "winget": ["Docker.DockerDesktop"]},
     "service": "docker", "bin": "docker"},
    {"id": "bunkerweb", "name": "BunkerWeb (WAF)", "category": "security", "desc": "WAF open source Nginx + ModSecurity / OWASP CRS en conteneur devant vos sites, "
                                                                           "configuration automatique des sites du panel. Piloté par la page WAF → Moteur.",
     "pkgs": {"debian": ["docker"], "rhel": ["docker"], "arch": ["docker"], "alpine": ["docker"], "suse": ["docker"]}, "service": "", "bin": "", "kind": "waf_engine"},
    {"id": "safeline", "name": "SafeLine (WAF)", "category": "security", "desc": "WAF open source à analyse sémantique (Chaitin) déployé par Docker Compose, "
                                                                          "console web et configuration automatique des sites. Piloté par la page WAF → Moteur.",
     "pkgs": {"debian": ["docker"], "rhel": ["docker"], "arch": ["docker"], "alpine": ["docker"], "suse": ["docker"]}, "service": "", "bin": "", "kind": "waf_engine"},
    {"id": "certbot", "name": "Certbot (Let's Encrypt)", "category": "tools", "desc": "Certificats SSL gratuits.",
     "pkgs": {"debian": ["certbot"], "rhel": ["certbot"], "arch": ["certbot"], "alpine": ["certbot"], "suse": ["certbot"], "winget": ["EFF.Certbot"]},
     "service": "", "bin": "certbot"},
    {"id": "nodejs", "name": "Node.js", "category": "tools", "desc": "Runtime JavaScript.",
     "pkgs": {"debian": ["nodejs", "npm"], "rhel": ["nodejs", "npm"], "arch": ["nodejs", "npm"], "alpine": ["nodejs", "npm"], "suse": ["nodejs20"],
              "winget": ["OpenJS.NodeJS.LTS"]},
     "service": "", "bin": "node"},
    {"id": "git", "name": "Git", "category": "tools", "desc": "Gestion de versions.",
     "pkgs": {"debian": ["git"], "rhel": ["git"], "arch": ["git"], "alpine": ["git"], "suse": ["git"], "winget": ["Git.Git"]},
     "service": "", "bin": "git"},
    {"id": "composer", "name": "Composer", "category": "php", "desc": "Gestionnaire de dépendances PHP.",
     "pkgs": {"debian": ["composer"], "rhel": ["composer"], "arch": ["composer"], "alpine": ["composer"], "winget": ["Composer.Composer"]},
     "service": "", "bin": "composer"},
    {"id": "fail2ban", "name": "Fail2ban", "category": "security", "desc": "Bannissement automatique des IP malveillantes.",
     "pkgs": {"debian": ["fail2ban"], "rhel": ["fail2ban"], "arch": ["fail2ban"], "alpine": ["fail2ban"]},
     "service": "fail2ban", "bin": "fail2ban-client"},
    {"id": "ufw", "name": "UFW", "category": "security", "desc": "Pare-feu simple pour Linux.",
     "pkgs": {"debian": ["ufw"], "arch": ["ufw"]},
     "service": "ufw", "bin": "ufw"},
    {"id": "mailserver", "name": "Serveur mail (Postfix + Dovecot + OpenDKIM)", "category": "mail", "desc": "SMTP, IMAP/POP3, signature DKIM. Piloté par la page Serveur mail.",
     "pkgs": {"debian": ["postfix", "dovecot-core", "dovecot-imapd", "dovecot-pop3d", "dovecot-lmtpd", "opendkim", "opendkim-tools"],
              "rhel": ["postfix", "dovecot", "opendkim", "opendkim-tools"], "arch": ["postfix", "dovecot", "opendkim"], "alpine": ["postfix", "dovecot", "dovecot-lmtpd", "dovecot-pop3d", "opendkim"],
              "suse": ["postfix", "dovecot", "opendkim"]},
     "service": "postfix", "bin": "postfix"},
    {"id": "roundcube", "name": "Webmail Roundcube", "category": "mail", "desc": "Webmail professionnel installé depuis la version officielle, configuré automatiquement "
                                                                              "contre Dovecot / Postfix avec sa base et son site. Piloté par Serveur mail → Webmail.",
     "pkgs": {"debian": ["php"], "rhel": ["php"], "arch": ["php"], "alpine": ["php"], "suse": ["php"]}, "service": "", "bin": "", "kind": "webmail"},
    {"id": "openssh-client", "name": "Client SSH (clés Git)", "category": "tools", "desc": "ssh et ssh-keygen : nécessaires au déploiement Git en mode SSH (clé générée par le panel).",
     "pkgs": {"debian": ["openssh-client"], "rhel": ["openssh-clients"], "arch": ["openssh"], "alpine": ["openssh-client"], "suse": ["openssh-clients"]},
     "service": "", "bin": "ssh-keygen"},
    {"id": "bind", "name": "BIND (serveur DNS)", "category": "tools", "desc": "Serveur DNS faisant autorité pour vos domaines, zones générées par la page DNS.",
     "pkgs": {"debian": ["bind9", "bind9-utils", "dnsutils"], "rhel": ["bind", "bind-utils"], "arch": ["bind"], "alpine": ["bind", "bind-tools"], "suse": ["bind", "bind-utils"]},
     "service": "named", "bin": "named"},
    {"id": "spamassassin", "name": "SpamAssassin", "category": "mail", "desc": "Filtrage anti-spam pour Postfix.",
     "pkgs": {"debian": ["spamassassin", "spamc"], "rhel": ["spamassassin"], "arch": ["spamassassin"], "alpine": ["spamassassin"]},
     "service": "spamassassin", "bin": "spamassassin"},
    {"id": "phpmyadmin", "name": "phpMyAdmin", "category": "database", "desc": "Administration MySQL via le navigateur.",
     "pkgs": {"debian": ["phpmyadmin"], "rhel": ["phpMyAdmin"], "arch": ["phpmyadmin"]},
     "service": "", "bin": ""},
]


def distro_family() -> str:
    if config.IS_WINDOWS:
        return "winget"
    info = get_platform().os_info()
    ids = f"{info.get('distro_id', '')} {info.get('distro_like', '')}".lower()
    if any(k in ids for k in ("debian", "ubuntu")):
        return "debian"
    if any(k in ids for k in ("rhel", "centos", "fedora", "rocky", "alma")):
        return "rhel"
    if "arch" in ids:
        return "arch"
    if "alpine" in ids:
        return "alpine"
    if "suse" in ids:
        return "suse"
    pm = get_platform().package_manager()
    return {"apt-get": "debian", "dnf": "rhel", "yum": "rhel", "pacman": "arch", "apk": "alpine", "zypper": "suse"}.get(pm, "")


def is_installed(item: dict) -> bool:
    plat = get_platform()
    if item.get("kind") == "waf_engine":
        from toutpanel.services import waf_engines

        return waf_engines.is_installed(item["id"])
    if item.get("kind") == "webmail":
        from toutpanel.services import webmail

        return webmail.status()["installed"]
    if item.get("bin") and plat.which(item["bin"]):
        return True
    if item.get("service") and plat.service_status(item["service"]) != "unknown":
        return True
    fam = distro_family()
    pkgs = item["pkgs"].get(fam) or []
    if pkgs and plat.package_installed(pkgs[0]):
        return True
    if item["id"] == "phpmyadmin":
        return Path("/usr/share/phpmyadmin").exists() or Path("/usr/share/phpMyAdmin").exists()
    if item["id"] == "roundcube":
        return Path("/usr/share/roundcube").exists() or Path("/usr/share/roundcubemail").exists()
    return False


def catalog() -> list[dict]:
    fam = distro_family()
    plat = get_platform()
    out = []
    for item in CATALOG:
        d = {k: v for k, v in item.items() if k != "pkgs"}
        d["packages"] = item["pkgs"].get(fam) or []
        d["supported"] = bool(d["packages"])
        d["installed"] = is_installed(item)
        d["status"] = plat.service_status(item["service"]) if d["installed"] and item.get("service") else ""
        out.append(d)
    return out


def _item(item_id: str) -> dict:
    for it in CATALOG:
        if it["id"] == item_id:
            return it
    raise ValueError("Logiciel inconnu")


def install(item_id: str) -> int:
    item = _item(item_id)
    if item.get("kind") == "waf_engine":
        from toutpanel.services import waf_engines

        return waf_engines.install(item_id)
    if item.get("kind") == "webmail":
        from toutpanel.db import session_scope
        from toutpanel.services import webmail

        with session_scope() as db:
            dom = webmail.status(db)["suggested_domain"]
        from toutpanel.services.system_info import _local_ip

        return webmail.install(dom or f"webmail.{_local_ip()}.nip.io")
    pkgs = item["pkgs"].get(distro_family()) or []
    if not pkgs:
        raise ValueError("Non disponible pour ce système")

    def _job(log):
        plat = get_platform()
        fam = distro_family()
        if fam == "rhel":
            _prepare_rhel(item, plat, log)
        log(f"Installation de {item['name']} ({', '.join(pkgs)})…")
        rc = plat.install_packages(pkgs, log)
        fb = (item.get("fallback") or {}).get(fam)
        if rc != 0 and fb:
            log(f"Échec, tentative avec les paquets alternatifs : {', '.join(fb)}")
            rc = plat.install_packages(fb, log)
            if rc == 0 and item["id"] == "redis":
                item_service = "valkey"
                r = plat.service_action(item_service, "enable")
                log(f"Service {item_service} : {'activé' if r.ok else r.output[:200]}")
                log("Terminé avec le code 0")
                return 0
        if rc == 0 and item.get("service") and not config.IS_WINDOWS:
            r = plat.service_action(item["service"], "enable")
            log(f"Service {item['service']} : {'activé' if r.ok else r.output[:300]}")
        log("Terminé avec le code " + str(rc))
        return rc

    return tasks.run_in_background(f"Installation {item['name']}", _job)


def _prepare_rhel(item: dict, plat, log) -> None:
    """Dépôts requis sur Alma/Rocky/RHEL/Fedora avant l'installation."""
    if item["id"] in ("certbot", "fail2ban", "mailserver", "phpmyadmin", "roundcube", "spamassassin", "memcached", "composer"):
        plat.ensure_epel(log)
    if item["id"] == "docker":
        ri = plat.rhel_info()
        url = "https://download.docker.com/linux/fedora/docker-ce.repo" if ri["is_fedora"] else "https://download.docker.com/linux/centos/docker-ce.repo"
        if not Path("/etc/yum.repos.d/docker-ce.repo").exists():
            log("Ajout du dépôt Docker CE…")
            r = plat.run([plat.package_manager() or "dnf", "config-manager", "--add-repo", url], timeout=120)
            if not r.ok:
                plat.run(["bash", "-c", f"curl -fsSL {url} -o /etc/yum.repos.d/docker-ce.repo"], timeout=120)


def remove(item_id: str) -> int:
    item = _item(item_id)
    if item.get("kind") == "waf_engine":
        from toutpanel.services import waf_engines

        return waf_engines.uninstall(item_id)
    if item.get("kind") == "webmail":
        from toutpanel.services import webmail

        return webmail.uninstall(False)
    pkgs = item["pkgs"].get(distro_family()) or []
    if not pkgs:
        raise ValueError("Non disponible pour ce système")

    def _job(log):
        log(f"Suppression de {item['name']}…")
        rc = get_platform().remove_packages(pkgs, log)
        log("Terminé avec le code " + str(rc))
        return rc

    return tasks.run_in_background(f"Suppression {item['name']}", _job)


def service_action(item_id: str, action: str) -> str:
    item = _item(item_id)
    if not item.get("service"):
        raise ValueError("Pas de service associé")
    plat = get_platform()
    names = [item["service"]]
    if item_id == "apache":
        names = ["apache2", "httpd", "Apache2.4"]
    if item_id == "mysql":
        names = ["mysql", "mysqld", "MySQL80"]
    if item_id == "mariadb":
        names = ["mariadb", "mysql", "MariaDB"]
    if item_id == "redis":
        names = ["redis-server", "redis", "valkey"]
    if item_id == "mailserver":
        last = ""
        for n in ("postfix", "dovecot", "opendkim"):
            r = plat.service_action(n, action)
            if not r.ok:
                last = r.output
        return last
    last = ""
    for n in names:
        r = plat.service_action(n, action)
        if r.ok:
            return ""
        last = r.output
    return last


# --------------------------------------------------------------------------- mise à jour du panel

def panel_source_dir():
    """Dépôt Git du panel installé par install.sh (<home>/src), s'il existe."""
    from pathlib import Path

    from toutpanel import config

    for cand in (config.HOME / "src", Path(__file__).resolve().parents[2]):
        if (cand / ".git").exists() and (cand / "pyproject.toml").exists():
            return cand
    return None


def check_update() -> dict:
    """Compare le commit installé et le commit distant de la branche suivie."""
    from toutpanel import __version__

    src = panel_source_dir()
    plat = get_platform()
    out = {"version": __version__, "source": str(src) if src else "", "git": bool(plat.which("git")), "local": "", "remote": "", "update_available": False, "branch": ""}
    if not src or not out["git"]:
        return out
    r = plat.run(["git", "-c", "safe.directory=*", "rev-parse", "--abbrev-ref", "HEAD"], timeout=30, cwd=str(src))
    out["branch"] = r.stdout.strip() if r.ok else ""
    r = plat.run(["git", "-c", "safe.directory=*", "rev-parse", "HEAD"], timeout=30, cwd=str(src))
    out["local"] = r.stdout.strip()[:12] if r.ok else ""
    r = plat.run(["git", "-c", "safe.directory=*", "ls-remote", "origin", out["branch"] or "HEAD"], timeout=60, cwd=str(src), env={"GIT_TERMINAL_PROMPT": "0"})
    if r.ok and r.stdout.strip():
        out["remote"] = r.stdout.split()[0][:12]
        out["update_available"] = bool(out["local"]) and not out["remote"].startswith(out["local"])
    else:
        out["error"] = r.output[-300:]
    return out


def update_panel() -> int:
    """Tâche : git pull du dépôt du panel, réinstallation du paquet, redémarrage."""
    from toutpanel.services import tasks

    def _job(log):
        import sys

        src = panel_source_dir()
        plat = get_platform()
        if not src:
            log("Dépôt du panel introuvable (installation manuelle ?) : mettez à jour avec install.sh")
            return 1
        log(f"=== Mise à jour de ToutPanel depuis {src}")
        for cmd in (["git", "-c", "safe.directory=*", "fetch", "--prune", "origin"], ["git", "-c", "safe.directory=*", "reset", "--hard", "origin/HEAD"]):
            log("$ " + " ".join(cmd))
            r = plat.run(cmd, timeout=600, cwd=str(src), env={"GIT_TERMINAL_PROMPT": "0"})
            log(r.output[-1500:])
            if not r.ok:
                return 1
        log(f"$ {sys.executable} -m pip install --upgrade --quiet {src}")
        rc = plat.stream([sys.executable, "-m", "pip", "install", "--upgrade", "--quiet", str(src)], log, timeout=1800)
        if rc != 0:
            return rc
        log("Redémarrage du panel dans 3 secondes…")
        import threading

        def _restart():
            import os
            import signal
            import time

            time.sleep(3)
            if os.environ.get("INVOCATION_ID"):
                os.kill(os.getpid(), signal.SIGTERM)
            else:
                os.execv(sys.executable, [sys.executable, "-m", "toutpanel", "run"])

        threading.Thread(target=_restart, daemon=True).start()
        log("Terminé avec le code 0")
        return 0

    return tasks.run_in_background("Mise à jour du panel", _job)
