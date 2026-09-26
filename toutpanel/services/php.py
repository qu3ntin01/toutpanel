"""Gestion multi-versions de PHP : dépôts, installation, extensions, php.ini, pools FPM.

Familles prises en charge :
  - debian / ubuntu : dépôt Sury (packages.sury.org) ou PPA ondrej/php  -> php8.3-fpm, socket /run/php/php8.3-fpm.sock
  - rhel (Rocky/Alma/Fedora) : dépôt Remi (collections)                 -> php83-php-fpm, socket /var/opt/remi/php83/run/php-fpm/www.sock
  - alpine : paquets community                                          -> php83-fpm, socket /run/php-fpm83/php-fpm.sock (ou /run/php/php83-fpm.sock)
  - windows : archives officielles windows.php.net                      -> C:\\toutpanel\\php\\8.3\\php-cgi.exe sur 127.0.0.1:90xx
"""
from __future__ import annotations
from typing import Optional

import json
import os
import re
import shutil
import subprocess
import threading
from pathlib import Path

from toutpanel import config
from toutpanel.platform import get_platform
from toutpanel.services import tasks

VERSIONS = ["8.4", "8.3", "8.2", "8.1", "8.0", "7.4", "7.3", "7.2", "7.1", "7.0", "5.6"]
EXTENSIONS = [
    ("mysql", "MySQL / MariaDB (mysqli, pdo_mysql)"), ("pgsql", "PostgreSQL"), ("sqlite3", "SQLite"), ("curl", "cURL"), ("gd", "GD (images)"),
    ("imagick", "ImageMagick"), ("intl", "Intl"), ("mbstring", "Multibyte"), ("xml", "XML"), ("zip", "Zip"), ("bcmath", "BCMath"), ("soap", "SOAP"),
    ("redis", "Redis"), ("memcached", "Memcached"), ("apcu", "APCu"), ("opcache", "OPcache"), ("imap", "IMAP"), ("ldap", "LDAP"), ("gmp", "GMP"),
    ("exif", "EXIF"), ("xdebug", "Xdebug (dev)"), ("igbinary", "igbinary"), ("msgpack", "msgpack"), ("bz2", "Bzip2"), ("readline", "Readline"),
]
DEFAULT_EXTS = ["mysql", "curl", "gd", "intl", "mbstring", "xml", "zip", "bcmath", "opcache", "sqlite3"]
INI_KEYS = ["memory_limit", "upload_max_filesize", "post_max_size", "max_execution_time", "max_input_time", "max_input_vars",
            "display_errors", "error_reporting", "date.timezone", "short_open_tag", "disable_functions", "expose_php",
            "opcache.enable", "opcache.memory_consumption", "session.gc_maxlifetime", "max_file_uploads", "default_socket_timeout"]
POOL_KEYS = ["pm", "pm.max_children", "pm.start_servers", "pm.min_spare_servers", "pm.max_spare_servers", "pm.max_requests",
             "pm.process_idle_timeout", "request_terminate_timeout", "listen", "user", "group"]
_lock = threading.Lock()


class PhpError(ValueError):
    pass


def family() -> str:
    from toutpanel.services.software import distro_family

    return distro_family()


def _vv(ver: str) -> str:
    return ver.replace(".", "")


# --------------------------------------------------------------------------- chemins par famille

def paths(ver: str) -> dict:
    fam = family()
    v, vv = ver, _vv(ver)
    if config.IS_WINDOWS:
        base = config.HOME / "php" / v
        return {"bin": str(base / "php.exe"), "cgi": str(base / "php-cgi.exe"), "ini": str(base / "php.ini"), "service": "",
                "pool": "", "fpm_pass": f"127.0.0.1:{9000 + int(vv)}", "ext_dir": str(base / "ext"), "base": str(base)}
    if fam == "rhel":
        return {"bin": f"/usr/bin/php{vv}", "ini": f"/etc/opt/remi/php{vv}/php.ini", "service": f"php{vv}-php-fpm",
                "pool": f"/etc/opt/remi/php{vv}/php-fpm.d/www.conf", "fpm_pass": f"unix:/var/opt/remi/php{vv}/run/php-fpm/www.sock",
                "ext_dir": f"/etc/opt/remi/php{vv}/php.d"}
    if fam == "alpine":
        return {"bin": f"/usr/bin/php{vv}", "ini": f"/etc/php{vv}/php.ini", "service": f"php-fpm{vv}", "pool": f"/etc/php{vv}/php-fpm.d/www.conf",
                "fpm_pass": f"unix:/run/php-fpm{vv}/php-fpm.sock", "ext_dir": f"/etc/php{vv}/conf.d"}
    return {"bin": f"/usr/bin/php{v}", "ini": f"/etc/php/{v}/fpm/php.ini", "cli_ini": f"/etc/php/{v}/cli/php.ini", "service": f"php{v}-fpm",
            "pool": f"/etc/php/{v}/fpm/pool.d/www.conf", "fpm_pass": f"unix:/run/php/php{v}-fpm.sock", "ext_dir": f"/etc/php/{v}/mods-available"}


def packages(ver: str, exts: Optional[list[str]] = None) -> list[str]:
    fam = family()
    v, vv = ver, _vv(ver)
    exts = exts if exts is not None else DEFAULT_EXTS
    if fam == "debian":
        base = [f"php{v}-fpm", f"php{v}-cli", f"php{v}-common"]
        builtin = {"exif"}  # fourni par php-common
        return base + [f"php{v}-{e}" for e in exts if e not in builtin]
    if fam == "rhel":
        # collections Remi (php83-php-*) : curl/exif/bz2/readline sont dans common ou cli
        m = {"mysql": "mysqlnd", "sqlite3": "pdo", "zip": "pecl-zip", "redis": "pecl-redis6", "memcached": "pecl-memcached", "apcu": "pecl-apcu",
             "imagick": "pecl-imagick-im7", "xdebug": "pecl-xdebug3", "igbinary": "pecl-igbinary", "msgpack": "pecl-msgpack", "imap": "pecl-imap"}
        builtin = {"curl", "exif", "bz2", "readline"}
        return [f"php{vv}-php-fpm", f"php{vv}-php-cli", f"php{vv}-php-common"] + [f"php{vv}-php-{m.get(e, e)}" for e in exts if e not in builtin]
    if fam == "alpine":
        m = {"mysql": "mysqli", "redis": "pecl-redis", "memcached": "pecl-memcached", "apcu": "pecl-apcu", "imagick": "pecl-imagick", "xdebug": "pecl-xdebug"}
        return [f"php{vv}", f"php{vv}-fpm", f"php{vv}-session", f"php{vv}-openssl", f"php{vv}-json", f"php{vv}-phar", f"php{vv}-ctype", f"php{vv}-dom",
                f"php{vv}-tokenizer", f"php{vv}-fileinfo"] + [f"php{vv}-{m.get(e, e)}" for e in exts] + ([f"php{vv}-pdo_mysql"] if "mysql" in exts else [])
    return []


# --------------------------------------------------------------------------- dépôts

def ensure_repository(log) -> bool:
    """Ajoute le dépôt multi-versions PHP de la distribution. Retourne True si disponible."""
    plat = get_platform()
    fam = family()
    info = plat.os_info()
    if fam == "debian":
        marker = Path("/etc/apt/sources.list.d/toutpanel-php.list")
        ppa_marker = list(Path("/etc/apt/sources.list.d").glob("ondrej*php*")) if Path("/etc/apt/sources.list.d").exists() else []
        if marker.exists() or ppa_marker:
            log("Dépôt PHP multi-versions déjà présent.")
            return True
        codename = ""
        r = plat.run(["bash", "-c", ". /etc/os-release; echo ${VERSION_CODENAME:-$UBUNTU_CODENAME}"], timeout=10)
        codename = r.stdout.strip()
        is_ubuntu = "ubuntu" in (info.get("distro_id", "") + info.get("distro_like", "")).lower()
        plat.run(["apt-get", "install", "-y", "-qq", "ca-certificates", "apt-transport-https", "gnupg", "curl", "lsb-release"], timeout=600, env={"DEBIAN_FRONTEND": "noninteractive"})
        Path("/etc/apt/keyrings").mkdir(parents=True, exist_ok=True)
        if is_ubuntu and plat.which("add-apt-repository"):
            log("Ajout du PPA ondrej/php…")
            rc = plat.stream(["add-apt-repository", "-y", "ppa:ondrej/php"], log, env={"DEBIAN_FRONTEND": "noninteractive"})
            if rc == 0:
                return True
            log("add-apt-repository a échoué, tentative manuelle…")
        if is_ubuntu:
            log("Ajout du PPA ondrej/php (méthode manuelle)…")
            key_url = "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x14aa40ec0831756756d7f66c4f4ea0aae5267a6c"
            r = plat.run(["bash", "-c", f"curl -fsSL '{key_url}' | gpg --dearmor --yes -o /etc/apt/keyrings/toutpanel-php.gpg"], timeout=120)
            if not r.ok:
                log("Clé GPG introuvable : " + r.output[:300])
                return False
            marker.write_text(f"deb [signed-by=/etc/apt/keyrings/toutpanel-php.gpg] https://ppa.launchpadcontent.net/ondrej/php/ubuntu {codename} main\n")
        else:
            log("Ajout du dépôt packages.sury.org…")
            r = plat.run(["bash", "-c", "curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/keyrings/toutpanel-php.gpg"], timeout=120)
            if not r.ok:
                log("Clé GPG introuvable : " + r.output[:300])
                return False
            marker.write_text(f"deb [signed-by=/etc/apt/keyrings/toutpanel-php.gpg] https://packages.sury.org/php/ {codename} main\n")
        rc = plat.stream(["apt-get", "update", "-qq"], log, env={"DEBIAN_FRONTEND": "noninteractive"})
        return rc == 0
    if fam == "rhel":
        plat.ensure_epel(log)
        if plat.package_installed("remi-release"):
            return True
        log("Ajout du dépôt Remi…")
        r = plat.run(["bash", "-c", ". /etc/os-release; echo $ID $VERSION_ID"], timeout=10)
        parts = r.stdout.split()
        did, vid = (parts + ["", ""])[:2]
        major = vid.split(".")[0]
        url = f"https://rpms.remirepo.net/fedora/remi-release-{major}.rpm" if did == "fedora" else f"https://rpms.remirepo.net/enterprise/remi-release-{major}.rpm"
        pm = plat.package_manager()
        if did != "fedora":
            plat.stream([pm, "install", "-y", "epel-release"], log)
        rc = plat.stream([pm, "install", "-y", url], log)
        return rc == 0
    if fam == "alpine":
        return True
    if config.IS_WINDOWS:
        return True
    log("Famille de distribution sans dépôt multi-versions connu ; seule la version du système est disponible.")
    return False


# --------------------------------------------------------------------------- détection

def _run_php(ver: str, args: list[str], timeout: int = 30):
    p = paths(ver)
    return get_platform().run([p["bin"]] + args, timeout=timeout)


def installed_versions() -> list[str]:
    out = []
    for v in VERSIONS:
        p = paths(v)
        if Path(p["bin"]).exists():
            out.append(v)
    if not out and get_platform().which("php"):
        r = get_platform().run(["php", "-r", "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"], timeout=15)
        if r.ok and re.fullmatch(r"\d+\.\d+", r.stdout.strip()):
            out.append(r.stdout.strip())
    return out


def version_info(ver: str) -> dict:
    plat = get_platform()
    p = paths(ver)
    installed = Path(p["bin"]).exists()
    full = ""
    status = "missing"
    if installed:
        r = _run_php(ver, ["-r", "echo PHP_VERSION;"], 15)
        full = r.stdout.strip() if r.ok else ""
        if config.IS_WINDOWS:
            status = "running" if _win_running(ver) else "stopped"
        else:
            status = plat.service_status(p["service"])
    default_cli = ""
    r = plat.run(["php", "-r", "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"], timeout=15) if plat.which("php") else None
    if r and r.ok:
        default_cli = r.stdout.strip()
    return {"version": ver, "installed": installed, "full_version": full, "status": status, "is_default_cli": default_cli == ver,
            "paths": {k: p[k] for k in ("bin", "ini", "service", "pool", "fpm_pass") if k in p}}


def overview() -> dict:
    fam = family()
    return {"family": fam, "supported": fam in ("debian", "rhel", "alpine") or config.IS_WINDOWS, "versions": [version_info(v) for v in VERSIONS],
            "extensions": [{"id": k, "label": lbl} for k, lbl in EXTENSIONS], "default_extensions": DEFAULT_EXTS}


# --------------------------------------------------------------------------- installation

def install(ver: str, exts: Optional[list[str]] = None) -> int:
    if ver not in VERSIONS:
        raise PhpError("Version inconnue")
    exts = [e for e in (exts or DEFAULT_EXTS) if e in dict(EXTENSIONS)]

    def _job(log):
        plat = get_platform()
        if config.IS_WINDOWS:
            return _install_windows(ver, log)
        if not ensure_repository(log):
            return 1
        pkgs = packages(ver, exts)
        if not pkgs:
            log("Famille non prise en charge.")
            return 1
        pkgs = _filter_available(plat, pkgs, log)
        log(f"Installation de PHP {ver} : {' '.join(pkgs)}")
        rc = plat.install_packages(pkgs, log)
        if rc != 0:
            log("Installation échouée (certaines extensions n'existent peut-être pas pour cette version). Nouvel essai sans les extensions optionnelles…")
            rc = plat.install_packages(packages(ver, [e for e in exts if e in ("mysql", "curl", "mbstring", "xml", "zip")]), log)
            if rc != 0:
                return rc
        svc = paths(ver)["service"]
        r = plat.service_action(svc, "enable")
        if not r.ok:
            r = plat.service_action(svc, "start")
        log(f"Service {svc} : {'démarré' if r.ok else r.output[:200]}")
        _post_install(ver, log)
        log(f"PHP {ver} prêt : {paths(ver)['fpm_pass']}")
        return 0

    return tasks.run_in_background(f"Installation PHP {ver}", _job)


def _filter_available(plat, pkgs: list[str], log) -> list[str]:
    """Écarte les paquets absents des dépôts (un seul nom inconnu ferait échouer apt/dnf)."""
    keep = []
    for pkg in pkgs:
        if plat.package_available(pkg):
            keep.append(pkg)
        else:
            log(f"Paquet {pkg} indisponible dans les dépôts : ignoré.")
    return keep


def _post_install(ver: str, log) -> None:
    """Réglages de base raisonnables pour l'hébergement."""
    if family() == "rhel":
        # Remi : socket réservée à apache par défaut, et nginx est le serveur web du panel
        pool = Path(paths(ver)["pool"])
        if pool.exists():
            text = pool.read_text(encoding="utf-8", errors="replace")
            web = get_platform().web_user() or "nginx"
            text = re.sub(r"^user = .*$", f"user = {web}", text, count=1, flags=re.M)
            text = re.sub(r"^group = .*$", f"group = {web}", text, count=1, flags=re.M)
            text = re.sub(r"^;?listen\.acl_users = .*$", "listen.acl_users = apache,nginx", text, count=1, flags=re.M)
            pool.write_text(text, encoding="utf-8")
            log(f"Pool FPM : utilisateur {web}, socket accessible à nginx.")
    try:
        set_ini(ver, {"upload_max_filesize": "64M", "post_max_size": "64M", "memory_limit": "256M", "max_execution_time": "120",
                      "expose_php": "Off", "date.timezone": "UTC"}, restart=True)
        log("php.ini : upload 64M, mémoire 256M, expose_php Off.")
    except PhpError as e:
        log("php.ini non ajusté : " + str(e))


def remove(ver: str) -> int:
    if ver not in VERSIONS:
        raise PhpError("Version inconnue")

    def _job(log):
        plat = get_platform()
        if config.IS_WINDOWS:
            _win_stop(ver)
            shutil.rmtree(paths(ver)["base"], ignore_errors=True)
            log(f"PHP {ver} supprimé.")
            return 0
        fam = family()
        v, vv = ver, _vv(ver)
        pattern = f"php{v}-*" if fam == "debian" else f"php{vv}-*" if fam == "rhel" else f"php{vv}*"
        log(f"Suppression des paquets {pattern}…")
        if fam == "debian":
            r = plat.run(["bash", "-c", f"dpkg-query -W -f='${{Package}}\\n' 'php{v}*' 2>/dev/null"], timeout=30)
            pkgs = [x for x in r.stdout.split() if x]
        elif fam == "rhel":
            r = plat.run(["bash", "-c", f"rpm -qa 'php{vv}-*'"], timeout=30)
            pkgs = [x for x in r.stdout.split() if x]
        else:
            r = plat.run(["bash", "-c", f"apk info | grep '^php{vv}'"], timeout=30)
            pkgs = [x for x in r.stdout.split() if x]
        if not pkgs:
            log("Aucun paquet trouvé.")
            return 1
        return plat.remove_packages(pkgs, log)

    return tasks.run_in_background(f"Suppression PHP {ver}", _job)


def install_extensions(ver: str, exts: list[str]) -> int:
    exts = [e for e in exts if e in dict(EXTENSIONS)]
    if not exts:
        raise PhpError("Aucune extension valide")

    def _job(log):
        plat = get_platform()
        if config.IS_WINDOWS:
            log("Sous Windows, activez les extensions dans php.ini (extension=…) ; les DLL sont fournies avec l'archive.")
            return enable_windows_ext(ver, exts, log)
        pkgs = [p for p in packages(ver, exts) if not p.endswith(("-fpm", "-cli", "-common")) and not re.search(r"php\d+$", p)]
        pkgs = _filter_available(plat, pkgs, log)
        if not pkgs:
            log("Aucun paquet disponible pour ces extensions.")
            return 1
        log("Installation : " + " ".join(pkgs))
        rc = plat.install_packages(pkgs, log)
        if rc == 0:
            restart(ver)
        return rc

    return tasks.run_in_background(f"Extensions PHP {ver} : {', '.join(exts)}", _job)


def modules(ver: str) -> list[str]:
    r = _run_php(ver, ["-m"], 30)
    return sorted({l.strip().lower() for l in r.stdout.splitlines() if l.strip() and not l.startswith("[")}) if r.ok else []


# --------------------------------------------------------------------------- php.ini

def _ini_path(ver: str) -> Path:
    p = Path(paths(ver)["ini"])
    if not p.exists():
        raise PhpError(f"php.ini introuvable : {p}")
    return p


def get_ini(ver: str) -> dict:
    text = _ini_path(ver).read_text(encoding="utf-8", errors="replace")
    out = {}
    for key in INI_KEYS:
        m = re.search(r"^\s*" + re.escape(key) + r"\s*=\s*(.*?)\s*$", text, re.M)
        out[key] = m.group(1) if m else ""
    return out


def set_ini(ver: str, values: dict, restart: bool = True) -> None:
    p = _ini_path(ver)
    text = p.read_text(encoding="utf-8", errors="replace")
    for key, val in values.items():
        if key not in INI_KEYS:
            continue
        val = str(val).strip().replace("\n", "")
        pattern = re.compile(r"^[ \t]*;?[ \t]*" + re.escape(key) + r"[ \t]*=.*$", re.M)
        if pattern.search(text):
            text = pattern.sub(f"{key} = {val}", text, count=1)
        else:
            text += f"\n{key} = {val}\n"
    p.write_text(text, encoding="utf-8")
    cli = paths(ver).get("cli_ini")
    if cli and Path(cli).exists():  # garder la CLI cohérente
        ctext = Path(cli).read_text(encoding="utf-8", errors="replace")
        for key, val in values.items():
            if key in ("date.timezone", "memory_limit", "disable_functions") and key in INI_KEYS:
                pattern = re.compile(r"^[ \t]*;?[ \t]*" + re.escape(key) + r"[ \t]*=.*$", re.M)
                ctext = pattern.sub(f"{key} = {str(val).strip()}", ctext, count=1) if pattern.search(ctext) else ctext
        Path(cli).write_text(ctext, encoding="utf-8")
    if restart:
        restart_service(ver)


def read_ini_raw(ver: str) -> str:
    return _ini_path(ver).read_text(encoding="utf-8", errors="replace")


def write_ini_raw(ver: str, content: str) -> None:
    _ini_path(ver).write_text(content, encoding="utf-8")
    restart_service(ver)


# --------------------------------------------------------------------------- pool FPM

def _pool_path(ver: str) -> Path:
    p = Path(paths(ver)["pool"] or "")
    if not p.exists():
        raise PhpError(f"Pool FPM introuvable : {p}")
    return p


def get_pool(ver: str) -> dict:
    text = _pool_path(ver).read_text(encoding="utf-8", errors="replace")
    out = {}
    for key in POOL_KEYS:
        m = re.search(r"^\s*" + re.escape(key) + r"\s*=\s*(.*?)\s*$", text, re.M)
        out[key] = m.group(1) if m else ""
    return out


def set_pool(ver: str, values: dict) -> None:
    p = _pool_path(ver)
    text = p.read_text(encoding="utf-8", errors="replace")
    for key, val in values.items():
        if key not in POOL_KEYS or key in ("listen", "user", "group"):
            continue
        val = str(val).strip()
        pattern = re.compile(r"^[ \t]*;?[ \t]*" + re.escape(key) + r"[ \t]*=.*$", re.M)
        text = pattern.sub(f"{key} = {val}", text, count=1) if pattern.search(text) else text + f"\n{key} = {val}\n"
    p.write_text(text, encoding="utf-8")
    restart_service(ver)


def read_pool_raw(ver: str) -> str:
    return _pool_path(ver).read_text(encoding="utf-8", errors="replace")


def write_pool_raw(ver: str, content: str) -> None:
    _pool_path(ver).write_text(content, encoding="utf-8")
    restart_service(ver)


# --------------------------------------------------------------------------- service

def restart_service(ver: str) -> str:
    return service_action(ver, "restart")


restart = restart_service


def service_action(ver: str, action: str) -> str:
    if config.IS_WINDOWS:
        if action in ("start", "restart"):
            _win_stop(ver)
            return _win_start(ver)
        if action == "stop":
            _win_stop(ver)
            return ""
        return ""
    r = get_platform().service_action(paths(ver)["service"], action)
    return "" if r.ok else r.output[:400]


def phpinfo(ver: str) -> str:
    r = _run_php(ver, ["-i"], 30)
    return r.output


def set_default_cli(ver: str) -> str:
    plat = get_platform()
    p = paths(ver)
    if config.IS_WINDOWS:
        config.get_settings().set("php_default_cli", ver)
        return ""
    if plat.which("update-alternatives") and family() == "debian":
        r = plat.run(["update-alternatives", "--set", "php", p["bin"]], timeout=30)
        return "" if r.ok else r.output[:300]
    try:
        link = Path("/usr/local/bin/php")
        if link.is_symlink() or not link.exists():
            link.unlink(missing_ok=True)
            link.symlink_to(p["bin"])
            return ""
        return "/usr/local/bin/php existe déjà et n'est pas un lien"
    except OSError as e:
        return str(e)


def test_config(ver: str) -> str:
    plat = get_platform()
    if config.IS_WINDOWS:
        return _run_php(ver, ["-v"], 15).output
    fpm = {"debian": f"/usr/sbin/php-fpm{ver}", "rhel": f"/opt/remi/php{_vv(ver)}/root/usr/sbin/php-fpm", "alpine": f"/usr/sbin/php-fpm{_vv(ver)}"}.get(family(), "")
    if fpm and Path(fpm).exists():
        return plat.run([fpm, "-t"], timeout=30).output
    return "php-fpm introuvable"


# --------------------------------------------------------------------------- Windows : php-cgi géré par le panel

_win_procs: dict[str, subprocess.Popen] = {}


def _win_running(ver: str) -> bool:
    p = _win_procs.get(ver)
    return bool(p and p.poll() is None)


def _win_start(ver: str) -> str:
    p = paths(ver)
    if not Path(p["cgi"]).exists():
        return "php-cgi.exe introuvable"
    port = p["fpm_pass"].split(":")[1]
    env = dict(os.environ, PHP_FCGI_MAX_REQUESTS="10000", PHP_FCGI_CHILDREN="4")
    logf = open(config.LOG_DIR / f"php-cgi-{ver}.log", "ab")
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    _win_procs[ver] = subprocess.Popen([p["cgi"], "-b", f"127.0.0.1:{port}", "-c", p["ini"]], stdout=logf, stderr=logf, creationflags=flags)
    return ""


def _win_stop(ver: str) -> None:
    p = _win_procs.pop(ver, None)
    if p and p.poll() is None:
        p.kill()


def start_all_windows() -> None:
    if not config.IS_WINDOWS:
        return
    for v in installed_versions():
        _win_start(v)


def _install_windows(ver: str, log) -> int:
    import io
    import zipfile

    import httpx

    log("Recherche de la dernière archive sur windows.php.net…")
    try:
        rel = httpx.get("https://windows.php.net/downloads/releases/releases.json", timeout=60, follow_redirects=True).json()
    except Exception as e:
        log(f"Impossible de lire la liste des versions : {e}")
        return 1
    entry = rel.get(ver)
    if not entry:
        log(f"PHP {ver} n'est plus disponible sur windows.php.net (versions : {', '.join(rel.keys())}).")
        return 1
    key = next((k for k in entry if k.startswith("nts-vs") and k.endswith("-x64")), None) or next((k for k in entry if k.startswith("nts-vc") and k.endswith("-x64")), None)
    if not key:
        log("Aucune archive NTS x64 trouvée.")
        return 1
    zipname = entry[key]["zip"]["path"]
    url = f"https://windows.php.net/downloads/releases/{zipname}"
    log(f"Téléchargement de {url}")
    try:
        data = httpx.get(url, timeout=600, follow_redirects=True).content
    except Exception as e:
        log(f"Téléchargement échoué : {e}")
        return 1
    base = Path(paths(ver)["base"])
    base.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        zf.extractall(base)
    ini = base / "php.ini"
    if not ini.exists():
        src = base / "php.ini-production"
        text = src.read_text(encoding="utf-8", errors="replace") if src.exists() else ""
        text = text.replace(';extension_dir = "ext"', f'extension_dir = "{base / "ext"}"')
        for e in ("curl", "gd", "intl", "mbstring", "mysqli", "pdo_mysql", "openssl", "zip", "fileinfo", "sqlite3", "pdo_sqlite"):
            text = text.replace(f";extension={e}", f"extension={e}")
        text = text.replace(";cgi.force_redirect = 1", "cgi.force_redirect = 0").replace(";cgi.fix_pathinfo=1", "cgi.fix_pathinfo=1")
        ini.write_text(text, encoding="utf-8")
    log(f"PHP {ver} installé dans {base}. Démarrage de php-cgi…")
    err = _win_start(ver)
    if err:
        log(err)
        return 1
    return 0


def enable_windows_ext(ver: str, exts: list[str], log) -> int:
    ini = Path(paths(ver)["ini"])
    text = ini.read_text(encoding="utf-8", errors="replace")
    m = {"mysql": ["mysqli", "pdo_mysql"], "pgsql": ["pgsql", "pdo_pgsql"], "sqlite3": ["sqlite3", "pdo_sqlite"], "opcache": ["opcache"]}
    for e in exts:
        for name in m.get(e, [e]):
            if f"extension={name}" not in text:
                text = text.replace(f";extension={name}", f"extension={name}") if f";extension={name}" in text else text + f"\nextension={name}\n"
            log(f"extension={name}")
    ini.write_text(text, encoding="utf-8")
    _win_stop(ver)
    _win_start(ver)
    return 0
