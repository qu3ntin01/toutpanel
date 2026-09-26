"""Application FastAPI : routes API, interface web, entrée sécurisée, services de fond."""
from __future__ import annotations

import json
import logging
from contextlib import asynccontextmanager
from logging.handlers import RotatingFileHandler

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from toutpanel import __version__, config
from toutpanel.api import auth, backup, cron, custom, databases, dns, files, firewall, ftp, git, mail, php, settings, sites, software, system, terminal, waf
from toutpanel.db import init_db

ENTRANCE_COOKIE = "tp_entrance"
log = logging.getLogger("toutpanel")


def setup_logging() -> None:
    config.ensure_dirs()
    root = logging.getLogger()
    if any(isinstance(h, RotatingFileHandler) for h in root.handlers):
        return
    root.setLevel(logging.INFO)
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        fh = RotatingFileHandler(config.LOG_DIR / "panel.log", maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8")
        fh.setFormatter(fmt)
        root.addHandler(fh)
    except OSError:
        pass
    sh = logging.StreamHandler()
    sh.setFormatter(fmt)
    root.addHandler(sh)
    logging.getLogger("pyftpdlib").setLevel(logging.WARNING)
    logging.getLogger("apscheduler").setLevel(logging.WARNING)


def load_i18n() -> dict:
    out = {}
    for p in config.I18N_DIR.glob("*.json"):
        try:
            out[p.stem] = json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            out[p.stem] = {}
    return out


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_logging()
    init_db()
    from toutpanel.services import cron as cron_svc
    from toutpanel.services import ftp as ftp_svc
    from toutpanel.services import monitor
    from toutpanel.services import waf as waf_svc

    if not getattr(app.state, "testing", False):
        from toutpanel.services import php as php_svc
        from toutpanel.services import gitdeploy, notifications, ssl as ssl_svc

        def _ftp_start():
            if config.get_settings().get("ftp_enabled"):
                err = ftp_svc.start()
                if err:
                    log.warning("FTP : %s", err)

        # chaque service de fond démarre indépendamment : un échec n'empêche pas le panel de répondre
        for label, fn in (("SELinux", _selinux_once), ("WAF", waf_svc.start), ("PHP Windows", php_svc.start_all_windows), ("planificateur", cron_svc.start),
                          ("monitoring", monitor.start), ("FTP", _ftp_start), ("déploiements Git", gitdeploy.start), ("renouvellement SSL", ssl_svc.start_renewal),
                          ("notifications", notifications.start)):
            try:
                fn()
            except Exception as e:  # noqa: BLE001
                log.warning("%s non démarré : %s", label, e)
    log.info("ToutPanel %s démarré (home=%s)", __version__, config.HOME)
    yield
    if not getattr(app.state, "testing", False):
        from toutpanel.services import tasks as tasks_svc

        for fn in (cron_svc.stop, monitor.stop, ftp_svc.stop, waf_svc.stop, tasks_svc.flush_all):
            try:
                fn()
            except Exception as e:  # noqa: BLE001
                log.debug("arrêt : %s", e)


def _selinux_once() -> None:
    """Sur les distributions SELinux (Alma/Rocky/RHEL/Fedora), déclare les contextes au premier démarrage."""
    from toutpanel.platform import get_platform

    plat = get_platform()
    if config.IS_WINDOWS or not hasattr(plat, "selinux_status") or not plat.is_admin():
        return
    marker = config.DATA_DIR / ".selinux-configured"
    if marker.exists() or plat.selinux_status() not in ("enforcing", "permissive"):
        return
    try:
        for m in plat.selinux_setup(str(config.WWW_ROOT), str(config.HOME)):
            log.info("SELinux : %s", m)
        marker.write_text("ok", encoding="utf-8")
    except Exception as e:  # pragma: no cover
        log.warning("SELinux : configuration impossible : %s", e)


def create_app(testing: bool = False) -> FastAPI:
    app = FastAPI(title="ToutPanel", version=__version__, lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    app.state.testing = testing
    templates = Jinja2Templates(directory=str(config.TEMPLATES_DIR))
    app.mount("/static", StaticFiles(directory=str(config.STATIC_DIR)), name="static")

    for r in (auth.router, system.router, sites.router, files.router, databases.router, ftp.router, cron.router,
              firewall.router, software.router, software.docker_router, backup.router, settings.router, terminal.router,
              mail.router, waf.router, php.router, custom.router, dns.router, git.router, git.protected):
        app.include_router(r)

    @app.middleware("http")
    async def security_layer(request: Request, call_next):
        """En-têtes de sécurité (CSP avec nonce), protection CSRF des appels d'API et journal d'audit."""
        import secrets as _secrets

        from toutpanel.security import CSRF_HEADER, CSRF_VALUE

        request.state.nonce = _secrets.token_urlsafe(16)
        path = request.url.path
        mutating = request.method in ("POST", "PUT", "PATCH", "DELETE")
        if path.startswith("/api/") and mutating and not path.startswith("/api/git/webhook/") \
                and not request.headers.get("authorization", "").lower().startswith("bearer "):
            # 1) en-tête que seul notre JavaScript envoie (un formulaire HTML cross-site ne le peut pas)
            if request.headers.get(CSRF_HEADER, "") != CSRF_VALUE:
                return JSONResponse({"ok": False, "msg": "Requête refusée (en-tête X-Requested-With absent)"}, status_code=403)
            # 2) l'origine, quand le navigateur l'envoie, doit être la nôtre
            origin = request.headers.get("origin") or request.headers.get("referer")
            host = request.headers.get("host", "")
            if origin and host:
                from urllib.parse import urlparse

                if urlparse(origin).netloc.lower() != host.lower():
                    return JSONResponse({"ok": False, "msg": "Origine de la requête refusée"}, status_code=403)
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "SAMEORIGIN"
        response.headers["Referrer-Policy"] = "same-origin"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
        response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
        response.headers["X-Permitted-Cross-Domain-Policies"] = "none"
        if request.url.scheme == "https" or config.get_settings().get("panel_ssl"):
            response.headers["Strict-Transport-Security"] = "max-age=31536000"
        if path.startswith("/api/"):
            response.headers["Cache-Control"] = "no-store"
        elif not path.startswith("/static/"):
            response.headers["Content-Security-Policy"] = (
                f"default-src 'self'; script-src 'self' 'nonce-{request.state.nonce}'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
                "font-src 'self' data: https://fonts.gstatic.com; img-src 'self' data: https: http:; connect-src 'self' ws: wss:; "
                "frame-ancestors 'self'; base-uri 'self'; form-action 'self'; object-src 'none'")
        if path.startswith("/api/") and mutating and path not in ("/api/auth/login", "/api/auth/logout") and not getattr(app.state, "testing_no_audit", False):
            _audit(request, response.status_code)
        return response

    def _audit(request: Request, status: int) -> None:
        """Trace toute action de modification (utilisateur, IP, route, résultat). Ne bloque jamais la requête."""
        try:
            from toutpanel.api.deps import client_ip
            from toutpanel.db import session_scope
            from toutpanel.models import AuditLog

            path = request.url.path
            if path.startswith("/api/system/tasks") or path.startswith("/api/terminal"):
                return
            with session_scope() as db:
                db.add(AuditLog(username=str(getattr(request.state, "user", "") or "")[:64], ip=client_ip(request), method=request.method, path=path[:256],
                                status=int(status), detail=(request.url.query or "")[:500]))
                # rétention : 20 000 dernières entrées
                if db.query(AuditLog).count() > 20500:
                    oldest = db.query(AuditLog.id).order_by(AuditLog.id.desc()).offset(20000).limit(1).scalar()
                    if oldest:
                        db.query(AuditLog).filter(AuditLog.id <= oldest).delete()
        except Exception as e:  # noqa: BLE001
            log.debug("audit : %s", e)

    def _entrance_ok(request: Request) -> bool:
        entrance = (config.get_settings().get("security_entrance") or "").strip()
        if not entrance:
            return True
        return request.cookies.get(ENTRANCE_COOKIE) == entrance.strip("/")

    @app.get("/", response_class=HTMLResponse)
    async def index(request: Request):
        if not _entrance_ok(request):
            return HTMLResponse("<h1>404 Not Found</h1>", status_code=404)
        s = config.get_settings()
        from toutpanel.api.custom import appearance

        lang = s.get("language", "fr")
        if lang not in config.LANGUAGES:
            lang = "fr"
        all_i18n = load_i18n()
        # seule la langue choisie (et l'anglais en repli) est embarquée dans la page
        i18n = {k: v for k, v in all_i18n.items() if k in (lang, "en")}
        return templates.TemplateResponse(request, "index.html", {
            "version": __version__, "panel_name": s.get("panel_name", "ToutPanel"), "language": lang, "languages": config.LANGUAGES,
            "dir": config.LANGUAGES[lang][2], "locale": config.LANGUAGES[lang][1],
            "i18n": json.dumps(i18n, ensure_ascii=False), "os_name": config.OS_NAME, "appearance": appearance(), "nonce": request.state.nonce,
        })

    @app.get("/{entrance}", include_in_schema=False)
    async def entrance(entrance: str, request: Request):
        expected = (config.get_settings().get("security_entrance") or "").strip().strip("/")
        if expected and entrance == expected:
            resp = RedirectResponse("/", status_code=302)
            resp.set_cookie(ENTRANCE_COOKIE, expected, httponly=True, samesite="lax", max_age=30 * 24 * 3600)
            return resp
        return HTMLResponse("<h1>404 Not Found</h1>", status_code=404)

    @app.exception_handler(404)
    async def not_found(request: Request, exc):
        if request.url.path.startswith("/api/"):
            return JSONResponse({"ok": False, "msg": getattr(exc, "detail", "Introuvable")}, status_code=404)
        return HTMLResponse("<h1>404 Not Found</h1>", status_code=404)

    from fastapi import HTTPException

    @app.exception_handler(HTTPException)
    async def http_exc(request: Request, exc: HTTPException):
        if request.url.path.startswith("/api/"):
            return JSONResponse({"ok": False, "msg": exc.detail}, status_code=exc.status_code)
        return HTMLResponse(f"<h1>{exc.status_code}</h1><p>{exc.detail}</p>", status_code=exc.status_code)

    return app


app = None


def get_app() -> FastAPI:
    global app
    if app is None:
        app = create_app()
    return app
