"""WAF (pare-feu applicatif) : règles Nginx / Apache générées par le panel + bannissement automatique.

Protections : injections SQL, XSS, traversée de répertoires, scanners & mauvais robots, limitation de débit
(anti-CC/DDoS applicatif), taille des requêtes, listes noires / blanches d'IP, motifs personnalisés (UA, URI, requête).
Les blocages sont détectés dans les journaux d'accès des sites (codes 403 / 429 / 444) et alimentent
le journal d'attaques et le bannissement automatique (règle de pare-feu temporaire).
"""
from __future__ import annotations
from typing import Optional

import logging
import re
import threading
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

from toutpanel import config
from toutpanel.db import session_scope
from toutpanel.models import Site, WafBan, WafRule, utcnow
from toutpanel.platform import get_platform

log = logging.getLogger("toutpanel.waf")

DEFAULTS = {
    "waf_enabled": True, "waf_sqli": True, "waf_xss": True, "waf_traversal": True, "waf_scanners": True, "waf_bad_bots": True,
    "waf_rate_limit": True, "waf_rate": 30, "waf_burst": 60, "waf_conn_limit": 60, "waf_max_body_mb": 64,
    "waf_block_exts": "php3,php4,php5,phtml,pl,py,cgi,sh,bak,sql,env,git,svn,htaccess,htpasswd,ini,log",
    "waf_autoban": True, "waf_autoban_threshold": 30, "waf_autoban_window": 5, "waf_autoban_minutes": 60,
    # renforts
    "waf_rce": True, "waf_php_injection": True, "waf_upload_exec": True, "waf_sensitive": True, "waf_methods": True,
    "waf_empty_ua": False, "waf_uri_max": 4096, "waf_headers": True, "waf_hsts": False, "waf_wp_hardening": True,
    "waf_path_inspect": True, "waf_engine": "builtin",
}
ENGINES = ("builtin", "bunkerweb", "safeline")
RULE_KINDS = ("ip_block", "ip_allow", "ua_block", "uri_block", "query_block")

SP = r"(?:\s|%20|\+|%09|%0a|%0d|/\*[^*]*\*/)+"   # espace, encodé ou commentaire SQL
SPO = r"(?:\s|%20|\+|%09|%0a|%0d|/\*[^*]*\*/)*"
SQLI = (r"(union" + SP + r"(all" + SP + r")?select|select" + SP + r".*from" + SP + r"|insert" + SP + r"into|delete" + SP + r"from|drop" + SP + r"table|update" + SP + r"\w+" + SP + r"set"
        r"|information_schema|sleep\(\d|benchmark\(|load_file\(|into" + SP + r"(out|dump)file|(%27|')" + SPO + r"(or|and)" + SPO + r"(%27|')?" + SPO + r"\d"
        r"|(%27|')" + SPO + r"or" + SPO + r"1" + SPO + r"=" + SPO + r"1|;" + SPO + r"(--|#|%23)|xp_cmdshell|@@version|char\(\d+\)|concat\(|extractvalue\(|updatexml\()")
XSS = r"(<script|</script|javascript:|vbscript:|onerror\s*=|onload\s*=|onmouseover\s*=|onfocus\s*=|<iframe|<object|<embed|<svg[\s/>]|document\.cookie|document\.write|alert\(|prompt\(|eval\(|expression\(|%3cscript|%3c/script)"
TRAVERSAL = r"(\.\./|\.\.\\|%2e%2e%2f|%2e%2e/|\.\.%2f|%252e%252e|/etc/passwd|/etc/shadow|/proc/self|c:\\windows|boot\.ini|win\.ini|\x00|%00)"
SCANNERS = r"(sqlmap|nikto|nmap|masscan|nessus|openvas|acunetix|w3af|zgrab|dirbuster|gobuster|wpscan|nuclei|havij|jbrofuzz|libwww-perl|python-requests/2\.\d\s*$|curl/7\.\d+\.\d+$|wget/)"
RCE = (r"(;|%3b|\||%7c|`|%60|\$\(|%24%28|\$\{ifs\}|%24%7bifs%7d)" + SPO + r"(cat|ls|id|whoami|uname|wget|curl|nc|ncat|bash|sh|python|perl|php|ruby|chmod|rm|echo|ping|sleep|powershell|cmd\.exe)\b"
       r"|/bin/(ba)?sh\b|/usr/bin/(wget|curl|perl|python)|cmd\.exe|powershell(\.exe)?" + SP + r"|\bnc" + SP + r"-e\b|\$\{ifs\}|%24%7bifs%7d")
PHP_INJ = r"(php://(input|filter|memory|temp)|data://|expect://|zip://|phar://|glob://|base64_decode\(|gzinflate\(|str_rot13\(|(system|passthru|shell_exec|exec|popen|proc_open|assert|preg_replace|create_function|call_user_func|file_put_contents|move_uploaded_file)\s*\(|<\?php|allow_url_include|auto_prepend_file|\$_(get|post|request|cookie|server)\[)"
SENSITIVE = (r"^/(\.git|\.svn|\.hg|\.env|\.htaccess|\.htpasswd|\.ssh|\.bash_history|\.DS_Store|composer\.(json|lock)|package(-lock)?\.json|yarn\.lock|phpinfo\.php|info\.php|test\.php|adminer\.php"
             r"|wp-config\.php(\.|~|$)|config\.php\.(bak|old|save|orig)|database\.yml|settings\.py|web\.config|dump\.sql|backup\.(zip|tar|gz|sql)|\.idea|\.vscode|vendor/composer)")
UPLOAD_EXEC = r"/(uploads?|wp-content/uploads|files|cache|tmp|temp|images?|img|media|assets|storage|static|public/uploads)/.*\.(php[3457]?|phtml|phar|pl|py|cgi|sh|jsp|asp|aspx)(\?|/|$)"
ALLOWED_METHODS = ("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
BAD_BOTS = r"(ahrefsbot|semrushbot|mj12bot|dotbot|petalbot|blexbot|megaindex|serpstatbot|dataforseobot|barkrowler|bytespider|gptbot|ccbot|amazonbot|seekportbot|zoominfobot|linkfluence)"


def get_settings() -> dict:
    s = config.get_settings()
    return {k: s.get(k, v) for k, v in DEFAULTS.items()}


def save_settings(values: dict) -> dict:
    clean = {}
    for k, v in values.items():
        if k not in DEFAULTS:
            continue
        if isinstance(DEFAULTS[k], bool):
            clean[k] = bool(v)
        elif isinstance(DEFAULTS[k], int):
            clean[k] = max(0, int(v))
        else:
            clean[k] = str(v).strip()
    config.get_settings().update(clean)
    return get_settings()


# --------------------------------------------------------------------------- règles

def add_rule(db, kind: str, value: str, remark: str = "") -> WafRule:
    if kind not in RULE_KINDS:
        raise ValueError("Type de règle invalide")
    value = value.strip()
    if not value:
        raise ValueError("Valeur requise")
    if kind in ("ip_block", "ip_allow"):
        if not re.fullmatch(r"[0-9a-fA-F.:]+(/\d{1,3})?", value):
            raise ValueError("IP ou CIDR invalide")
    else:
        try:
            re.compile(value)
        except re.error as e:
            raise ValueError(f"Expression régulière invalide : {e}")
        if len(value) > 500:
            raise ValueError("Motif trop long")
        if any(c in value for c in "\"{}\r\n\x00") or any(ord(c) < 32 for c in value):
            raise ValueError("Le motif ne doit contenir ni guillemet, ni accolade, ni retour à la ligne")
        if value.endswith("\\") or "\\\\" in value:
            raise ValueError("Barre oblique inverse finale ou doublée interdite dans un motif")
    if db.query(WafRule).filter(WafRule.kind == kind, WafRule.value == value).first():
        raise ValueError("Règle déjà existante")
    r = WafRule(kind=kind, value=value, remark=remark)
    db.add(r)
    db.flush()
    return r


# --------------------------------------------------------------------------- rendu Nginx

def _esc_nginx(pattern: str) -> str:
    """Motif dans une chaîne nginx entre guillemets : guillemets échappés, retours à la ligne supprimés."""
    return pattern.replace("\\\"", "\"").replace('"', '\\"').replace("\n", "").replace("\r", "")


def _esc_apache(pattern: str) -> str:
    """Motif dans une RewriteCond : ni espace (séparateur d'arguments), ni retour à la ligne."""
    return pattern.replace("\n", "").replace("\r", "").replace(" ", "\\ ")


def render_nginx_http(db) -> str:
    """Bloc http : zones de limitation et maps (inclus via conf.d)."""
    s = get_settings()
    rules = db.query(WafRule).filter(WafRule.enabled.is_(True)).all()
    bans = [b.ip for b in db.query(WafBan).filter((WafBan.until.is_(None)) | (WafBan.until > utcnow())).all()]
    lines = ["# Généré par ToutPanel WAF - ne pas modifier à la main",
             f"limit_req_zone $binary_remote_addr zone=tp_waf_req:10m rate={max(1, int(s['waf_rate']))}r/s;",
             "limit_conn_zone $binary_remote_addr zone=tp_waf_conn:10m;",
             'map $request_uri $tp_waf_login_key { default ""; "~*^/(wp-login\\.php|xmlrpc\\.php|administrator/index\\.php|admin/login|user/login)" $binary_remote_addr; }',
             "limit_req_zone $tp_waf_login_key zone=tp_waf_login:10m rate=1r/s;",
             "limit_req_status 429;", "limit_conn_status 429;", ""]
    # IP autorisées (exemptées) et bloquées
    lines += ["geo $tp_waf_allow {", "    default 0;"] + [f"    {r.value} 1;" for r in rules if r.kind == "ip_allow"] + ["}", ""]
    blocked = [r.value for r in rules if r.kind == "ip_block"] + bans
    lines += ["geo $tp_waf_ip_block {", "    default 0;"] + [f"    {ip} 1;" for ip in sorted(set(blocked))] + ["}", ""]
    # User-Agent
    ua_patterns = []
    if s["waf_scanners"]:
        ua_patterns.append(SCANNERS)
    if s["waf_bad_bots"]:
        ua_patterns.append(BAD_BOTS)
    ua_patterns += [r.value for r in rules if r.kind == "ua_block"]
    lines += ["map $http_user_agent $tp_waf_ua {", "    default 0;"] + [f'    "~*{_esc_nginx(p)}" 1;' for p in ua_patterns] + ["}", ""]
    # URI
    uri_patterns = []
    if s["waf_traversal"]:
        uri_patterns.append(TRAVERSAL)
    exts = [e.strip() for e in str(s["waf_block_exts"]).split(",") if e.strip()]
    if exts:
        uri_patterns.append(r"\.(" + "|".join(re.escape(e) for e in exts) + r")(\?|$)")
    if s["waf_sensitive"]:
        uri_patterns.append(SENSITIVE)
    if s["waf_upload_exec"]:
        uri_patterns.append(UPLOAD_EXEC)
    if s["waf_wp_hardening"]:
        uri_patterns.append(r"^/(xmlrpc\.php|wp-config\.php|wp-content/debug\.log|wp-includes/.*\.php|wp-content/plugins/.*/(readme|changelog)\.txt|readme\.html|license\.txt)")
    if s["waf_path_inspect"]:
        # injections encodées dans le chemin (et non seulement dans la query string)
        if s["waf_sqli"]:
            uri_patterns.append(SQLI)
        if s["waf_xss"]:
            uri_patterns.append(XSS)
        if s["waf_rce"]:
            uri_patterns.append(RCE)
        if s["waf_php_injection"]:
            uri_patterns.append(PHP_INJ)
    uri_patterns += [r.value for r in rules if r.kind == "uri_block"]
    lines += ["map $request_uri $tp_waf_uri {", "    default 0;"] + [f'    "~*{_esc_nginx(p)}" 1;' for p in uri_patterns] + ["}", ""]
    # Query string
    q_patterns = []
    if s["waf_sqli"]:
        q_patterns.append(SQLI)
    if s["waf_xss"]:
        q_patterns.append(XSS)
    if s["waf_traversal"]:
        q_patterns.append(TRAVERSAL)
    if s["waf_rce"]:
        q_patterns.append(RCE)
    if s["waf_php_injection"]:
        q_patterns.append(PHP_INJ)
    q_patterns += [r.value for r in rules if r.kind == "query_block"]
    lines += ["map $query_string $tp_waf_query {", "    default 0;"] + [f'    "~*{_esc_nginx(p)}" 1;' for p in q_patterns] + ["}", ""]
    # Méthodes HTTP, User-Agent vide, longueur d'URI, cookies / referer injectés
    lines += ["map $request_method $tp_waf_method {", "    default " + ("1" if s["waf_methods"] else "0") + ";"] + [f"    {m} 0;" for m in ALLOWED_METHODS] + ["}", ""]
    lines += ["map $http_user_agent $tp_waf_noua {", "    default 0;", '    "" ' + ("1" if s["waf_empty_ua"] else "0") + ";", "}", ""]
    umax = max(256, int(s["waf_uri_max"]))
    lines += ["map $request_uri $tp_waf_toolong {", "    default 0;", f'    "~^.{{{umax},}}$" 1;', "}", ""]
    hdr_patterns = ([SQLI] if s["waf_sqli"] else []) + ([XSS] if s["waf_xss"] else []) + ([RCE] if s["waf_rce"] else [])
    lines += ["map $http_cookie:$http_referer $tp_waf_hdr {", "    default 0;"] + [f'    "~*{_esc_nginx(p)}" 1;' for p in hdr_patterns] + ["}", ""]
    # Décision globale (0 = ok, sinon code de raison)
    lines += ["map $tp_waf_allow:$tp_waf_ip_block:$tp_waf_ua:$tp_waf_uri:$tp_waf_query:$tp_waf_method:$tp_waf_noua:$tp_waf_toolong:$tp_waf_hdr $tp_waf_block {",
              "    default 0;", '    "~^0:1" ip;', '    "~^0:0:1" ua;', '    "~^0:0:0:1" uri;', '    "~^0:0:0:0:1" query;',
              '    "~^0:0:0:0:0:1" method;', '    "~^0:0:0:0:0:0:1" noua;', '    "~^0:0:0:0:0:0:0:1" toolong;', '    "~^0:0:0:0:0:0:0:0:1" header;', "}", ""]
    return "\n".join(lines)


def render_nginx_site() -> str:
    """Snippet inclus dans chaque bloc server protégé."""
    s = get_settings()
    lines = ["# Généré par ToutPanel WAF - ne pas modifier à la main",
             "if ($tp_waf_block) { return 403; }",
             f"client_max_body_size {max(1, int(s['waf_max_body_mb']))}m;",
             "client_body_timeout 15s;", "client_header_timeout 15s;", "send_timeout 30s;"]
    if s["waf_rate_limit"]:
        lines += [f"limit_req zone=tp_waf_req burst={max(1, int(s['waf_burst']))} nodelay;",
                  f"limit_conn tp_waf_conn {max(1, int(s['waf_conn_limit']))};"]
    if s["waf_headers"]:
        lines += ["add_header X-Content-Type-Options nosniff always;", "add_header X-Frame-Options SAMEORIGIN always;",
                  "add_header Referrer-Policy strict-origin-when-cross-origin always;",
                  'add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;',
                  "server_tokens off;"]
    if s["waf_hsts"]:
        lines.append('add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;')
    if s["waf_upload_exec"]:
        lines.append("location ~* " + UPLOAD_EXEC.replace("(\\?|/|$)", "") + " { deny all; }")
    if s["waf_wp_hardening"]:
        lines += ["location = /xmlrpc.php { deny all; }",
                  "# pages de connexion : 1 requête/s par IP (WordPress, Joomla, Drupal…)",
                  "limit_req zone=tp_waf_login burst=5 nodelay;"]
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------- rendu Apache

def render_apache_site(db) -> str:
    s = get_settings()
    rules = db.query(WafRule).filter(WafRule.enabled.is_(True)).all()
    bans = [b.ip for b in db.query(WafBan).filter((WafBan.until.is_(None)) | (WafBan.until > utcnow())).all()]
    lines = ["# Généré par ToutPanel WAF - ne pas modifier à la main", "RewriteEngine On"]
    allow = [r.value for r in rules if r.kind == "ip_allow"]
    blocked = sorted(set([r.value for r in rules if r.kind == "ip_block"] + bans))
    if blocked:
        lines += ["<RequireAll>", "    Require all granted"] + [f"    Require not ip {ip}" for ip in blocked] + ["</RequireAll>"]
    for ip in allow:
        lines.append(f"RewriteCond %{{REMOTE_ADDR}} ^{re.escape(ip.split('/')[0])} [NC]")
        lines.append("RewriteRule .* - [L]")
    ua = ([SCANNERS] if s["waf_scanners"] else []) + ([BAD_BOTS] if s["waf_bad_bots"] else []) + [r.value for r in rules if r.kind == "ua_block"]
    for p in ua:
        lines += [f"RewriteCond %{{HTTP_USER_AGENT}} {_esc_apache(p)} [NC]", "RewriteRule .* - [F,L]"]
    uri = ([TRAVERSAL] if s["waf_traversal"] else []) + [r.value for r in rules if r.kind == "uri_block"]
    exts = [e.strip() for e in str(s["waf_block_exts"]).split(",") if e.strip()]
    if exts:
        uri.append(r"\.(" + "|".join(re.escape(e) for e in exts) + r")$")
    for p in uri:
        lines += [f"RewriteCond %{{REQUEST_URI}} {_esc_apache(p)} [NC]", "RewriteRule .* - [F,L]"]
    if s["waf_sensitive"]:
        uri.append(SENSITIVE)
    if s["waf_upload_exec"]:
        uri.append(UPLOAD_EXEC)
    if s["waf_wp_hardening"]:
        uri.append(r"^/(xmlrpc\.php|wp-config\.php|wp-content/debug\.log|readme\.html|license\.txt)")
    if s["waf_path_inspect"]:
        uri += ([SQLI] if s["waf_sqli"] else []) + ([XSS] if s["waf_xss"] else []) + ([RCE] if s["waf_rce"] else []) + ([PHP_INJ] if s["waf_php_injection"] else [])
    q = ([SQLI] if s["waf_sqli"] else []) + ([XSS] if s["waf_xss"] else []) + ([TRAVERSAL] if s["waf_traversal"] else []) + ([RCE] if s["waf_rce"] else []) + ([PHP_INJ] if s["waf_php_injection"] else []) + [r.value for r in rules if r.kind == "query_block"]
    for p in q:
        lines += [f"RewriteCond %{{QUERY_STRING}} {_esc_apache(p)} [NC]", "RewriteRule .* - [F,L]"]
    if s["waf_methods"]:
        lines += ["RewriteCond %{REQUEST_METHOD} !^(" + "|".join(ALLOWED_METHODS) + ")$", "RewriteRule .* - [F,L]"]
    if s["waf_empty_ua"]:
        lines += ["RewriteCond %{HTTP_USER_AGENT} ^$", "RewriteRule .* - [F,L]"]
    lines += [f"LimitRequestBody {max(1, int(s['waf_max_body_mb'])) * 1024 * 1024}", f"LimitRequestLine {max(256, int(s['waf_uri_max']))}"]
    if s["waf_headers"]:
        lines += ["Header always set X-Content-Type-Options nosniff", "Header always set X-Frame-Options SAMEORIGIN",
                  "Header always set Referrer-Policy strict-origin-when-cross-origin", 'Header always set Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()"',
                  "ServerSignature Off"]
    if s["waf_hsts"]:
        lines.append('Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"')
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------- application

def waf_dir() -> Path:
    d = config.VHOST_DIR / "waf"
    d.mkdir(parents=True, exist_ok=True)
    return d


def nginx_site_include() -> Path:
    return waf_dir() / "nginx_site.conf"


def apache_site_include() -> Path:
    return waf_dir() / "apache_site.conf"


def write_configs(db) -> dict:
    from toutpanel.services import webserver

    out = {}
    d = waf_dir()
    nginx_http = d / "nginx_http.conf"
    config.atomic_write(nginx_http, render_nginx_http(db))
    config.atomic_write(nginx_site_include(), render_nginx_site())
    config.atomic_write(apache_site_include(), render_apache_site(db))
    out["nginx_http"] = str(nginx_http)
    # Le fichier http doit être inclus dans le contexte http de nginx : conf.d est inclus par défaut.
    for cand in ("/etc/nginx/conf.d", "C:/nginx/conf/conf.d"):
        cdir = Path(cand)
        if cdir.parent.exists():
            cdir.mkdir(parents=True, exist_ok=True)
            target = cdir / "toutpanel_waf.conf"
            try:
                content = nginx_http.read_text(encoding="utf-8") if get_settings()["waf_enabled"] else "# WAF ToutPanel désactivé\n"
                config.atomic_write(target, content)
                out["nginx_http_installed"] = str(target)
            except OSError as e:
                out["error"] = str(e)
            break
    out["webserver"] = webserver.detect()
    return out


def apply(db) -> str:
    """Régénère les règles, réécrit les vhosts et recharge le serveur web. Retourne un avertissement éventuel."""
    from toutpanel.services import sites, webserver

    write_configs(db)
    adapter = webserver.get_adapter()
    for site in db.query(Site).all():
        if site.enabled:
            adapter.apply(site.to_dict())
    if webserver.is_installed(adapter.name):
        r = adapter.reload()
        if not r.ok:
            return f"Règles écrites mais rechargement {adapter.name} échoué : {r.output[:400]}"
        return ""
    return f"Règles écrites ; {adapter.name} n'est pas installé."


# --------------------------------------------------------------------------- journal d'attaques (lecture des access logs)

LOG_RE = re.compile(r'^(?P<ip>\S+) \S+ \S+ \[(?P<time>[^\]]+)\] "(?P<method>\S+) (?P<uri>\S+)[^"]*" (?P<status>\d{3}) \S+ "(?P<ref>[^"]*)" "(?P<ua>[^"]*)"')
BLOCK_STATUSES = {"403", "429", "444"}


def _tail_lines(path: Path, max_bytes: int = 3 * 1024 * 1024) -> list[str]:
    try:
        size = path.stat().st_size
        with open(path, "rb") as f:
            f.seek(max(0, size - max_bytes))
            return f.read().decode("utf-8", errors="replace").splitlines()[1 if size > max_bytes else 0:]
    except OSError:
        return []


def _parse_time(s: str) -> Optional[datetime]:
    try:
        return datetime.strptime(s.split()[0], "%d/%b/%Y:%H:%M:%S")
    except ValueError:
        return None


_EVENT_CACHE: dict[str, dict] = {}   # fichier -> {"pos": octets déjà lus, "inode": …, "events": [...]}
_EVENT_LOCK = __import__("threading").Lock()
_EVENT_KEEP_HOURS = 168


def _scan_file(f: Path, site: str) -> list[dict]:
    """Ne lit que les octets ajoutés depuis le dernier passage (rotation détectée par inode / taille)."""
    try:
        st = f.stat()
    except OSError:
        return []
    key = str(f)
    with _EVENT_LOCK:
        c = _EVENT_CACHE.get(key)
        if c and (c["inode"] != st.st_ino or st.st_size < c["pos"]):
            c = None  # fichier tourné ou tronqué : on repart du début
        if c is None:
            c = {"pos": max(0, st.st_size - 3 * 1024 * 1024), "inode": st.st_ino, "events": []}
            _EVENT_CACHE[key] = c
        start = c["pos"]
    new_events: list[dict] = []
    if st.st_size > start:
        try:
            with open(f, "rb") as fh:
                fh.seek(start)
                data = fh.read(st.st_size - start)
        except OSError:
            return list(c["events"])
        lines = data.decode("utf-8", errors="replace").splitlines()
        consumed = data.rfind(b"\n") + 1  # une ligne incomplète sera relue au prochain passage
        for line in lines[: len(lines) if data.endswith(b"\n") else -1]:
            m = LOG_RE.match(line)
            if not m or m.group("status") not in BLOCK_STATUSES:
                continue
            t = _parse_time(m.group("time"))
            new_events.append({"time": t.isoformat() if t else "", "ip": m.group("ip"), "site": site, "method": m.group("method"),
                               "uri": m.group("uri")[:200], "status": m.group("status"), "ua": m.group("ua")[:120]})
        with _EVENT_LOCK:
            c["pos"] = start + consumed
            c["events"].extend(new_events)
            cutoff = (datetime.now() - timedelta(hours=_EVENT_KEEP_HOURS)).isoformat()
            c["events"] = [e for e in c["events"] if not e["time"] or e["time"] >= cutoff][-50000:]
    with _EVENT_LOCK:
        return list(c["events"])


def events(limit: int = 300, hours: int = 24) -> list[dict]:
    site_logs = config.LOG_DIR / "sites"
    out: list[dict] = []
    since = (datetime.now() - timedelta(hours=hours)).isoformat()
    if not site_logs.exists():
        return out
    for f in site_logs.glob("*.access.log"):
        site = f.name[: -len(".access.log")]
        out.extend(e for e in _scan_file(f, site) if not e["time"] or e["time"] >= since)
    out.sort(key=lambda x: x["time"], reverse=True)
    return out[:limit]


def stats(hours: int = 24) -> dict:
    ev = events(limit=100000, hours=hours)
    by_ip = Counter(e["ip"] for e in ev)
    by_site = Counter(e["site"] for e in ev)
    by_status = Counter(e["status"] for e in ev)
    by_hour: dict[str, int] = defaultdict(int)
    for e in ev:
        by_hour[e["time"][:13]] += 1
    with session_scope() as db:
        bans = db.query(WafBan).filter((WafBan.until.is_(None)) | (WafBan.until > utcnow())).count()
        rules = db.query(WafRule).filter(WafRule.enabled.is_(True)).count()
    return {"total": len(ev), "top_ips": by_ip.most_common(10), "by_site": by_site.most_common(10), "by_status": dict(by_status),
            "by_hour": sorted(by_hour.items()), "bans": bans, "rules": rules}


# --------------------------------------------------------------------------- bannissement

def ban(db, ip: str, minutes: Optional[int], reason: str = "manuel", hits: int = 0) -> WafBan:
    ip = ip.strip()
    if not re.fullmatch(r"[0-9a-fA-F.:]+(/\d{1,3})?", ip):
        raise ValueError("IP invalide")
    import ipaddress

    try:
        net = ipaddress.ip_network(ip, strict=False)
        if net.network_address.is_loopback or net.network_address.is_unspecified or (net.prefixlen == 0):
            raise ValueError("Impossible de bannir l'adresse locale / toutes les adresses")
    except ValueError as e:
        if "bannir" in str(e):
            raise
        raise ValueError("IP invalide")
    existing = db.query(WafBan).filter(WafBan.ip == ip).first()
    until = utcnow() + timedelta(minutes=minutes) if minutes else None
    if existing:
        existing.until, existing.reason, existing.hits = until, reason, hits
        b = existing
    else:
        b = WafBan(ip=ip, until=until, reason=reason, hits=hits)
        db.add(b)
    db.flush()
    _pending_firewall.append(("add", ip))
    return b


def unban(db, b: WafBan) -> None:
    _pending_firewall.append(("remove", b.ip))
    db.delete(b)
    db.flush()


_pending_firewall: list[tuple[str, str]] = []
_firewall_lock = __import__("threading").Lock()


def flush_firewall() -> None:
    """Applique au pare-feu les bannissements enregistrés — à appeler après la fin de la transaction SQLite,
    pour ne jamais tenir le verrou de la base pendant `ufw` / `firewall-cmd` (plusieurs secondes)."""
    with _firewall_lock:
        ops, _pending_firewall[:] = list(_pending_firewall), []
    plat = get_platform()
    for op, ip in ops:
        try:
            if op == "add":
                plat.firewall_add("1-65535", "tcp", "deny", ip, "toutpanel-waf")
            else:
                plat.firewall_remove("1-65535", "tcp", "deny", ip, "toutpanel-waf")
        except Exception as e:  # noqa: BLE001
            log.warning("WAF pare-feu %s %s : %s", op, ip, e)


def _autoban_pass() -> int:
    s = get_settings()
    expired = 0
    with session_scope() as db:
        # lever les bannissements expirés, que l'autoban soit actif ou non (sinon ils resteraient au pare-feu)
        for b in db.query(WafBan).filter(WafBan.until.isnot(None), WafBan.until <= utcnow()).all():
            unban(db, b)
            expired += 1
    flush_firewall()
    if not (s["waf_enabled"] and s["waf_autoban"]):
        if expired:
            _reload_after_bans()
        return 0
    created = 0
    with session_scope() as db:
        allowed = {r.value for r in db.query(WafRule).filter(WafRule.kind == "ip_allow", WafRule.enabled.is_(True)).all()}
        active = {b.ip for b in db.query(WafBan).all()}
        counts = Counter(e["ip"] for e in events(limit=100000, hours=max(1, int(s["waf_autoban_window"]) // 60 + 1))
                         if e["time"] and datetime.fromisoformat(e["time"]) >= datetime.now() - timedelta(minutes=int(s["waf_autoban_window"])))
        for ip, n in counts.items():
            if n >= int(s["waf_autoban_threshold"]) and ip not in active and ip not in allowed and not ip.startswith("127."):
                ban(db, ip, int(s["waf_autoban_minutes"]) or None, f"auto : {n} requêtes bloquées en {s['waf_autoban_window']} min", n)
                created += 1
                log.info("WAF : IP %s bannie (%s blocages)", ip, n)
    flush_firewall()
    if created or expired:
        _reload_after_bans()
    return created


def _reload_after_bans() -> None:
    with session_scope() as db:
        write_configs(db)
    from toutpanel.services import webserver

    if webserver.is_installed():
        webserver.get_adapter().reload()


_stop = threading.Event()
_thread: Optional[threading.Thread] = None


def _loop() -> None:
    while not _stop.is_set():
        try:
            _autoban_pass()
        except Exception as e:  # pragma: no cover
            log.warning("autoban : %s", e)
        _stop.wait(60)


def start() -> None:
    global _thread
    if _thread and _thread.is_alive():
        return
    _stop.clear()
    _thread = threading.Thread(target=_loop, name="toutpanel-waf", daemon=True)
    _thread.start()


def stop() -> None:
    _stop.set()
