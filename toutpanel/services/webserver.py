"""Adaptateurs serveur web : génération des vhosts et rechargement (Nginx, Apache, IIS)."""
from __future__ import annotations
from typing import Optional

import os
import re
import shutil
from pathlib import Path

import threading

from toutpanel import config
from toutpanel.services import loadbalancer
from toutpanel.platform import get_platform
from toutpanel.platform.base import CommandResult


def detect() -> str:
    pref = config.get_settings().get("webserver", "auto")
    if pref and pref != "auto":
        return pref
    plat = get_platform()
    if plat.which("nginx") or Path("/etc/nginx").exists() or Path("C:/nginx/nginx.exe").exists():
        return "nginx"
    if plat.which("apache2") or plat.which("httpd") or Path("/etc/apache2").exists() or Path("/etc/httpd").exists():
        return "apache"
    if config.IS_WINDOWS and Path(os.environ.get("SystemRoot", "C:/Windows")) .joinpath("System32/inetsrv/appcmd.exe").exists():
        return "iis"
    return "nginx"


def web_ports() -> tuple[int, int]:
    """Ports d'écoute des vhosts : 80/443, ou les ports de repli quand un WAF externe (BunkerWeb, SafeLine) est devant."""
    st = config.get_settings()
    try:
        return int(st.get("web_http_port", 80) or 80), int(st.get("web_https_port", 443) or 443)
    except (TypeError, ValueError):
        return 80, 443


def ipv6_available() -> bool:
    """Vrai si la machine peut écouter en IPv6 (évite un nginx -t en échec sur les hôtes sans IPv6)."""
    import socket

    if not socket.has_ipv6:
        return False
    if config.IS_LINUX and not Path("/proc/net/if_inet6").exists():
        return False
    try:
        s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        s.bind(("::", 0))
        s.close()
        return True
    except OSError:
        return False


_nginx_version: Optional[tuple] = None


def nginx_version() -> tuple:
    """Version de nginx (ex: (1, 24, 0)) ; (0,) si inconnue."""
    global _nginx_version
    if _nginx_version is None:
        plat = get_platform()
        exe = plat.which("nginx") or ("C:/nginx/nginx.exe" if config.IS_WINDOWS else "/usr/sbin/nginx")
        r = plat.run([exe, "-v"], timeout=10)
        m = re.search(r"nginx/(\d+)\.(\d+)\.(\d+)", r.output)
        _nginx_version = tuple(int(x) for x in m.groups()) if m else (0,)
    return _nginx_version


def _php_fastcgi_pass(php_version: str) -> str:
    """Adresse FastCGI de PHP-FPM selon la plateforme et la version."""
    from toutpanel.services import php as php_svc

    if php_version in php_svc.VERSIONS:
        p = php_svc.paths(php_version)
        target = p["fpm_pass"]
        sock = target[5:] if target.startswith("unix:") else ""
        if config.IS_WINDOWS or not sock or os.path.exists(sock):
            return target
    if config.IS_WINDOWS:
        return "127.0.0.1:9000"
    if php_version:
        for cand in (f"/run/php/php{php_version}-fpm.sock", f"/var/run/php/php{php_version}-fpm.sock",
                     f"/run/php-fpm/php{php_version.replace('.', '')}-fpm.sock", f"/var/opt/remi/php{php_version.replace('.', '')}/run/php-fpm/www.sock"):
            if os.path.exists(cand):
                return "unix:" + cand
    for cand in ("/run/php-fpm/www.sock", "/run/php/php-fpm.sock", "/var/run/php-fpm/www.sock"):
        if os.path.exists(cand):
            return "unix:" + cand
    if php_version:
        return f"unix:/run/php/php{php_version}-fpm.sock"
    return "127.0.0.1:9000"


def _waf_active(site: dict) -> bool:
    if not site.get("waf_enabled", True):
        return False
    s = config.get_settings()
    if not s.get("waf_enabled", True):
        return False
    from toutpanel.services import waf as waf_svc

    return waf_svc.nginx_site_include().exists()


# --------------------------------------------------------------------------- NGINX
RELOAD_LOCK = threading.RLock()


class NginxAdapter:
    name = "nginx"

    def conf_dir(self) -> Path:
        if os.environ.get("TOUTPANEL_ISOLATED_VHOSTS"):
            d = config.VHOST_DIR / "nginx"
            d.mkdir(parents=True, exist_ok=True)
            return d
        for cand in ("/etc/nginx/conf.d", "/etc/nginx/sites-enabled", "/usr/local/nginx/conf/vhost",
                     "C:/nginx/conf/vhost", "/opt/homebrew/etc/nginx/servers"):
            p = Path(cand)
            if p.parent.exists() and (p.exists() or cand.endswith("vhost")):
                p.mkdir(parents=True, exist_ok=True)
                return p
        d = config.VHOST_DIR / "nginx"
        d.mkdir(parents=True, exist_ok=True)
        return d

    def conf_path(self, site_name: str) -> Path:
        return self.conf_dir() / f"toutpanel_{site_name}.conf"

    def render(self, site: dict) -> str:
        from toutpanel.services import templates

        domain_list = site.get("domains") or [site["name"]]
        log_dir = str(config.LOG_DIR / "sites").replace("\\", "/")
        Path(log_dir).mkdir(parents=True, exist_ok=True)
        (config.VHOST_DIR / "custom").mkdir(parents=True, exist_ok=True)
        ssl = bool(site.get("ssl_enabled") and site.get("ssl_cert") and site.get("ssl_key"))
        waf_inc = ""
        if _waf_active(site):
            from toutpanel.services import waf as waf_svc

            waf_inc = str(waf_svc.nginx_site_include()).replace("\\", "/")
        return templates.render(
            "nginx.conf.j2", site=site, domains=" ".join(domain_list), domain_list=domain_list, root=site["root"].replace("\\", "/"),
            log_dir=log_dir, v6=(not config.IS_WINDOWS and ipv6_available()), ssl=ssl, http2_on=nginx_version() >= (1, 25, 1),
            http_port=web_ports()[0], https_port=web_ports()[1],
            cert=(site.get("ssl_cert") or "").replace("\\", "/"), key=(site.get("ssl_key") or "").replace("\\", "/"),
            stype=site.get("site_type", "php"), fpm=_php_fastcgi_pass(site.get("php_version", "")), waf_include=waf_inc,
            lb_upstream=loadbalancer.nginx_upstream(site), lb_pass=loadbalancer.nginx_pass(site),
            custom_include=str(config.VHOST_DIR / "custom" / (site["name"] + ".conf")).replace("\\", "/"),
        )

    def apply(self, site: dict) -> None:
        (config.VHOST_DIR / "custom").mkdir(parents=True, exist_ok=True)
        ensure_nginx_includes(self.conf_dir())
        write_proxy_conf()
        config.atomic_write(self.conf_path(site["name"]), self.render(site))

    def remove(self, site_name: str) -> None:
        p = self.conf_path(site_name)
        if p.exists():
            p.unlink()

    def test(self) -> CommandResult:
        plat = get_platform()
        exe = plat.which("nginx") or ("C:/nginx/nginx.exe" if config.IS_WINDOWS else "/usr/sbin/nginx")
        return plat.run([exe, "-t"], timeout=30)

    def reload(self) -> CommandResult:
        with RELOAD_LOCK:  # un seul test + rechargement à la fois (autoban, édition de site, certbot…)
            return self._reload()

    def _reload(self) -> CommandResult:
        plat = get_platform()
        t = self.test()
        if not t.ok:
            return t
        if config.IS_WINDOWS:
            exe = plat.which("nginx") or "C:/nginx/nginx.exe"
            return plat.run([exe, "-s", "reload"], timeout=30, cwd=str(Path(exe).parent))
        r = plat.service_action("nginx", "reload")
        if not r.ok:
            r = plat.run([plat.which("nginx") or "nginx", "-s", "reload"], timeout=30)
        if not r.ok and plat.service_status("nginx") != "running":
            r = plat.service_action("nginx", "start")  # arrêté (ex. port occupé lors d'un changement de moteur) : on le relance
        if r.ok:
            import time

            time.sleep(0.5)  # laisse aux nouveaux workers le temps de charger la configuration
        return r


# --------------------------------------------------------------------------- APACHE
class ApacheAdapter:
    name = "apache"

    def conf_dir(self) -> Path:
        for cand in ("/etc/apache2/sites-enabled", "/etc/httpd/conf.d", "C:/Apache24/conf/vhost"):
            p = Path(cand)
            if p.parent.exists():
                p.mkdir(parents=True, exist_ok=True)
                return p
        d = config.VHOST_DIR / "apache"
        d.mkdir(parents=True, exist_ok=True)
        return d

    def conf_path(self, site_name: str) -> Path:
        return self.conf_dir() / f"toutpanel_{site_name}.conf"

    def render(self, site: dict) -> str:
        from toutpanel.services import templates

        domain_list = site.get("domains") or [site["name"]]
        log_dir = str(config.LOG_DIR / "sites").replace("\\", "/")
        Path(log_dir).mkdir(parents=True, exist_ok=True)
        (config.VHOST_DIR / "custom").mkdir(parents=True, exist_ok=True)
        ssl = bool(site.get("ssl_enabled") and site.get("ssl_cert") and site.get("ssl_key"))
        fpm = _php_fastcgi_pass(site.get("php_version", ""))
        apache_fcgi = f"unix:{fpm[5:]}|fcgi://localhost" if fpm.startswith("unix:") else f"fcgi://{fpm}"
        waf_inc = ""
        if _waf_active(site):
            from toutpanel.services import waf as waf_svc

            waf_inc = str(waf_svc.apache_site_include()).replace("\\", "/")
        return templates.render(
            "apache.conf.j2", http_port=web_ports()[0], https_port=web_ports()[1], site=site, domain_list=domain_list, root=site["root"].replace("\\", "/"), log_dir=log_dir, ssl=ssl,
            cert=site.get("ssl_cert") or "", key=site.get("ssl_key") or "", stype=site.get("site_type", "php"), apache_fcgi=apache_fcgi,
            waf_include=waf_inc, lb_balancer=loadbalancer.apache_balancer(site), lb_pass=loadbalancer.apache_pass(site),
            custom_include=str(config.VHOST_DIR / "custom" / (site["name"] + ".apache.conf")).replace("\\", "/"),
        )

    def apply(self, site: dict) -> None:
        (config.VHOST_DIR / "custom").mkdir(parents=True, exist_ok=True)
        config.atomic_write(self.conf_path(site["name"]), self.render(site))

    def remove(self, site_name: str) -> None:
        p = self.conf_path(site_name)
        if p.exists():
            p.unlink()

    def test(self) -> CommandResult:
        plat = get_platform()
        exe = plat.which("apachectl") or plat.which("httpd") or plat.which("apache2ctl") or "apachectl"
        return plat.run([exe, "-t"], timeout=30)

    def reload(self) -> CommandResult:
        with RELOAD_LOCK:
            return self._reload()

    def _reload(self) -> CommandResult:
        plat = get_platform()
        t = self.test()
        if not t.ok:
            return t
        for svc in ("apache2", "httpd", "Apache2.4"):
            r = plat.service_action(svc, "reload")
            if r.ok:
                return r
        return CommandResult(1, "", "impossible de recharger Apache")


# --------------------------------------------------------------------------- IIS
class IISAdapter:
    """Support basique d'IIS via appcmd (Windows)."""
    name = "iis"

    def _appcmd(self) -> str:
        return str(Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32" / "inetsrv" / "appcmd.exe")

    def render(self, site: dict) -> str:
        domains = site.get("domains") or [site["name"]]
        bindings = ",".join(f"http/*:80:{d}" for d in domains)
        return f'appcmd add site /name:"{site["name"]}" /physicalPath:"{site["root"]}" /bindings:"{bindings}"'

    def apply(self, site: dict) -> None:
        plat = get_platform()
        domains = site.get("domains") or [site["name"]]
        bindings = ",".join(f"http/*:80:{d}" for d in domains)
        if site.get("ssl_enabled"):
            bindings += "," + ",".join(f"https/*:443:{d}" for d in domains)
        plat.run([self._appcmd(), "delete", "site", site["name"]], timeout=30)
        plat.run([self._appcmd(), "add", "site", f"/name:{site['name']}", f"/physicalPath:{site['root']}",
                  f"/bindings:{bindings}"], timeout=30)

    def remove(self, site_name: str) -> None:
        get_platform().run([self._appcmd(), "delete", "site", site_name], timeout=30)

    def test(self) -> CommandResult:
        return CommandResult(0, "", "")

    def reload(self) -> CommandResult:
        return get_platform().run(["iisreset", "/noforce"], timeout=60)


def nginx_confd() -> Optional[Path]:
    for cand in ("/etc/nginx/conf.d", "C:/nginx/conf/conf.d", "/usr/local/nginx/conf/conf.d"):
        p = Path(cand)
        if p.parent.exists():
            p.mkdir(parents=True, exist_ok=True)
            return p
    return None


def write_proxy_conf() -> None:
    """conf.d/toutpanel_proxy.conf : schéma réel derrière un proxy ($tp_scheme, évite les boucles de redirection
    HTTPS) et adresse IP réelle du client quand un WAF externe (BunkerWeb, SafeLine) est devant nginx."""
    d = nginx_confd()
    if d is None:
        return
    external = config.get_settings().get("waf_engine", "builtin") != "builtin"
    lines = ["# Généré par ToutPanel - ne pas modifier à la main",
             "map $http_x_forwarded_proto $tp_scheme { default $scheme; https https; http http; }",
             "map $http_upgrade $connection_upgrade { default upgrade; '' close; }"]
    if external:
        # proxies de confiance : boucle locale (SafeLine en réseau hôte) et réseaux Docker (BunkerWeb en bridge)
        lines += ["set_real_ip_from 127.0.0.1;", "set_real_ip_from ::1;", "set_real_ip_from 172.16.0.0/12;", "set_real_ip_from 10.0.0.0/8;",
                  "real_ip_header X-Forwarded-For;", "real_ip_recursive on;"]
    lines.append("")
    try:
        config.atomic_write(d / "toutpanel_proxy.conf", "\n".join(lines))
    except OSError:
        pass


DEFAULT_SERVER_FILES = ("/etc/nginx/sites-available/default", "/etc/nginx/conf.d/default.conf", "/etc/nginx/nginx.conf",
                        "/usr/local/nginx/conf/nginx.conf", "C:/nginx/conf/nginx.conf")


def move_default_server(http_port: int, https_port: int) -> list[str]:
    """Déplace le serveur par défaut de la distribution (sites-available/default, conf.d/default.conf, nginx.conf)
    sur les ports de repli pour libérer 80 / 443 devant un WAF externe ; (80, 443) restaure les ports d'origine.
    Une copie .toutpanel-orig est conservée au premier passage."""
    changed = []
    for cand in DEFAULT_SERVER_FILES:
        f = Path(cand)
        if not f.exists():
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        orig = f.with_name(f.name + ".toutpanel-orig")
        if not orig.exists():
            try:
                orig.write_text(text, encoding="utf-8")
            except OSError:
                continue
        base = orig.read_text(encoding="utf-8", errors="replace")
        new = base
        if (http_port, https_port) != (80, 443):
            new = re.sub(r"(listen\s+(?:\[::\]:)?)80(\s|;)", lambda m: f"{m.group(1)}{http_port}{m.group(2)}", new)
            new = re.sub(r"(listen\s+(?:\[::\]:)?)443(\s|;)", lambda m: f"{m.group(1)}{https_port}{m.group(2)}", new)
        if new != text:
            try:
                f.write_text(new, encoding="utf-8")
                changed.append(str(f))
            except OSError:
                pass
    return changed


def write_apache_ports(http_port: int, https_port: int) -> None:
    """Directives Listen d'Apache pour les ports de repli (conf.d / conf-enabled)."""
    for cand in ("/etc/apache2/conf-enabled", "/etc/httpd/conf.d"):
        d = Path(cand)
        if d.exists():
            body = "# Généré par ToutPanel\n" + "".join(f"Listen {p}\n" for p in {http_port, https_port} - {80, 443})
            try:
                (d / "toutpanel_ports.conf").write_text(body, encoding="utf-8")
            except OSError:
                pass
            return


def ensure_nginx_includes(vhost_dir: Path) -> None:
    """S'assure que nginx.conf inclut le dossier des vhosts et conf.d (nécessaire sous Windows et pour les
    installations manuelles de nginx ; les paquets Debian/RHEL incluent déjà conf.d)."""
    for conf in (Path("C:/nginx/conf/nginx.conf"), Path("/usr/local/nginx/conf/nginx.conf")):
        if not conf.exists():
            continue
        try:
            text = conf.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        wanted = []
        rel_vhost = vhost_dir.name if vhost_dir.parent == conf.parent else str(vhost_dir).replace("\\", "/")
        if f"include {rel_vhost}/*.conf;" not in text and "include vhost/*.conf;" not in text:
            wanted.append(f"    include {rel_vhost}/*.conf;")
        if "include conf.d/*.conf;" not in text:
            (conf.parent / "conf.d").mkdir(exist_ok=True)
            wanted.append("    include conf.d/*.conf;")
        if wanted and re.search(r"^\s*http\s*\{", text, re.M):
            text = re.sub(r"(^\s*http\s*\{)", lambda m: m.group(1) + "\n" + "\n".join(wanted), text, count=1, flags=re.M)
            conf.write_text(text, encoding="utf-8")


def get_adapter(name: Optional[str] = None):
    name = name or detect()
    return {"nginx": NginxAdapter, "apache": ApacheAdapter, "iis": IISAdapter}.get(name, NginxAdapter)()


def is_installed(name: Optional[str] = None) -> bool:
    name = name or detect()
    plat = get_platform()
    if name == "nginx":
        return bool(plat.which("nginx")) or Path("/usr/sbin/nginx").exists() or Path("C:/nginx/nginx.exe").exists()
    if name == "apache":
        return bool(plat.which("apache2") or plat.which("httpd") or plat.which("apachectl"))
    if name == "iis":
        return Path(os.environ.get("SystemRoot", "C:/Windows")).joinpath("System32/inetsrv/appcmd.exe").exists()
    return False


def php_versions() -> list[str]:
    """Versions PHP détectées sur la machine."""
    from toutpanel.services import php as php_svc

    try:
        found_svc = php_svc.installed_versions()
        if found_svc:
            return sorted(found_svc)
    except Exception:
        pass
    found: set[str] = set()
    plat = get_platform()
    if config.IS_WINDOWS:
        for base in (Path("C:/php"), config.HOME / "php"):
            if base.exists():
                for d in base.iterdir():
                    m = re.search(r"(\d+\.\d+)", d.name)
                    if d.is_dir() and m:
                        found.add(m.group(1))
        if plat.which("php") and not found:
            r = plat.run(["php", "-r", "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"], timeout=15)
            if r.ok:
                found.add(r.stdout.strip())
        return sorted(found)
    for d in (Path("/etc/php"), Path("/usr/bin"), Path("/opt/remi")):
        if d.exists():
            for p in d.iterdir():
                m = re.fullmatch(r"(?:php)?(\d+\.\d+)", p.name) or re.fullmatch(r"php(\d)(\d)", p.name)
                if m:
                    found.add(m.group(1) if len(m.groups()) == 1 else f"{m.group(1)}.{m.group(2)}")
    if not found and plat.which("php"):
        r = plat.run(["php", "-r", "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"], timeout=15)
        if r.ok and re.fullmatch(r"\d+\.\d+", r.stdout.strip()):
            found.add(r.stdout.strip())
    return sorted(found)
