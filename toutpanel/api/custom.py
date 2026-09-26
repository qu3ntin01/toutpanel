"""Personnalisation : apparence, modèles, répertoires, liens de menu."""
from __future__ import annotations
from typing import Optional

import re
from pathlib import Path

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from toutpanel import config
from toutpanel.api.deps import current_user, fail, ok
from toutpanel.services import templates

router = APIRouter(prefix="/api/custom", tags=["custom"], dependencies=[Depends(current_user)])

APPEARANCE_KEYS = ("panel_name", "accent_color", "logo_letter", "logo_url", "default_theme", "custom_css", "footer_text", "custom_links",
                   "sidebar_compact", "show_version", "default_contrast", "ui_skin")
COLOR_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def appearance() -> dict:
    s = config.get_settings()
    return {"panel_name": s.get("panel_name", "ToutPanel"), "accent_color": ("#2563eb" if s.get("accent_color", "#2563eb") == "#12a150" else s.get("accent_color", "#2563eb")), "logo_letter": s.get("logo_letter", "T"),
            "logo_url": s.get("logo_url", ""), "default_theme": s.get("default_theme", "auto"), "custom_css": s.get("custom_css", ""),
            "footer_text": s.get("footer_text", ""), "custom_links": s.get("custom_links") or [], "sidebar_compact": bool(s.get("sidebar_compact", False)),
            "show_version": bool(s.get("show_version", True)), "default_contrast": s.get("default_contrast", "glass"), "ui_skin": s.get("ui_skin", "aurora")}


@router.get("")
def overview():
    s = config.get_settings()
    return ok({"appearance": appearance(), "templates": templates.list_all(),
               "dirs": {"www_root": str(config.WWW_ROOT), "backup_dir": str(config.BACKUP_DIR), "home": str(config.HOME),
                        "vhost_dir": str(config.VHOST_DIR), "ssl_dir": str(config.SSL_DIR), "log_dir": str(config.LOG_DIR),
                        "override_www_root": s.get("www_root", ""), "override_backup_dir": s.get("backup_dir", "")}})


class AppearanceIn(BaseModel):
    values: dict


@router.post("/appearance")
def set_appearance(data: AppearanceIn):
    values = {k: v for k, v in data.values.items() if k in APPEARANCE_KEYS}
    if "accent_color" in values and values["accent_color"] and not COLOR_RE.match(str(values["accent_color"])):
        fail("Couleur invalide (format #RRGGBB)")
    if "default_theme" in values and values["default_theme"] not in ("auto", "light", "dark"):
        fail("Thème invalide")
    if "default_contrast" in values and values["default_contrast"] not in ("glass", "high"):
        fail("Contraste invalide")
    if "ui_skin" in values and values["ui_skin"] not in ("aurora", "classic"):
        fail("Style invalide")
    if "logo_letter" in values:
        values["logo_letter"] = str(values["logo_letter"])[:2] or "T"
    if "custom_css" in values and len(str(values["custom_css"])) > 50000:
        fail("CSS trop long")
    if "custom_links" in values:
        links = []
        for l in values["custom_links"] or []:
            label, url = str(l.get("label", "")).strip()[:40], str(l.get("url", "")).strip()[:500]
            if label and url and re.match(r"^(https?://|/|#)", url):
                links.append({"label": label, "url": url, "icon": str(l.get("icon", "external"))[:20]})
        values["custom_links"] = links
    config.get_settings().update(values)
    return ok(appearance(), "Apparence enregistrée")


@router.get("/templates/{name}")
def get_template(name: str):
    try:
        return ok(templates.get(name))
    except KeyError:
        fail("Modèle inconnu", 404)


class TemplateIn(BaseModel):
    content: str


@router.post("/templates/{name}")
def save_template(name: str, data: TemplateIn):
    try:
        templates.save(name, data.content)
    except KeyError:
        fail("Modèle inconnu", 404)
    except ValueError as e:
        fail(str(e))
    return ok(templates.get(name), "Modèle enregistré — ré-appliquez les sites (WAF → Appliquer ou modification d'un site) pour régénérer les vhosts.")


@router.delete("/templates/{name}")
def reset_template(name: str):
    if name not in templates.TEMPLATES:
        fail("Modèle inconnu", 404)
    templates.reset(name)
    return ok(templates.get(name), "Modèle par défaut restauré")


class PreviewIn(BaseModel):
    content: str
    site_id: Optional[int] = None


@router.post("/templates/{name}/preview")
def preview_template(name: str, data: PreviewIn):
    """Rendu d'essai du modèle avec un site réel (ou un site fictif) sans rien enregistrer."""
    from jinja2 import Environment, TemplateSyntaxError

    from toutpanel.db import session_scope
    from toutpanel.models import Site
    from toutpanel.services import webserver

    if name not in templates.TEMPLATES:
        fail("Modèle inconnu", 404)
    site = None
    with session_scope() as db:
        if data.site_id:
            s = db.get(Site, data.site_id)
            site = s.to_dict() if s else None
    if site is None:
        site = {"name": "exemple", "domains": ["exemple.com", "www.exemple.com"], "root": str(config.WWW_ROOT / "exemple"), "site_type": "php",
                "php_version": (webserver.php_versions() or [""])[-1], "ssl_enabled": True, "ssl_cert": str(config.SSL_DIR / "exemple/fullchain.pem"),
                "ssl_key": str(config.SSL_DIR / "exemple/privkey.pem"), "force_https": True, "proxy_target": "", "waf_enabled": True, "enabled": True}
    try:
        Environment().parse(data.content)
    except TemplateSyntaxError as e:
        fail(f"Erreur de syntaxe Jinja ligne {e.lineno} : {e.message}")
    # rendu temporaire : on écrit le modèle dans un répertoire éphémère prioritaire
    import tempfile

    from jinja2 import ChoiceLoader, FileSystemLoader

    with tempfile.TemporaryDirectory() as tmp:
        Path(tmp, name).write_text(data.content, encoding="utf-8")
        original_env = templates.env

        def _env():
            e = original_env()
            e.loader = ChoiceLoader([FileSystemLoader(tmp), e.loader])
            return e

        templates.env = _env
        try:
            adapter = webserver.NginxAdapter() if name.startswith("nginx") else webserver.ApacheAdapter() if name.startswith("apache") else None
            if adapter:
                out = adapter.render(site)
            else:
                out = templates.render(name, name=site["name"], root=site["root"])
        except Exception as e:
            fail(f"Erreur de rendu : {e}")
        finally:
            templates.env = original_env
    return ok({"rendered": out})


class DirsIn(BaseModel):
    www_root: Optional[str] = None
    backup_dir: Optional[str] = None


@router.post("/dirs")
def set_dirs(data: DirsIn):
    values = {}
    for key in ("www_root", "backup_dir"):
        v = getattr(data, key)
        if v is None:
            continue
        v = v.strip()
        if v:
            p = Path(v)
            if not p.is_absolute():
                fail(f"{key} : chemin absolu requis")
            if key == "backup_dir":
                www = Path(getattr(data, "www_root", None) or config.WWW_ROOT)
                for base in (www, config.WWW_ROOT):
                    try:
                        p.resolve().relative_to(base.resolve())
                        fail("backup_dir : les sauvegardes ne doivent pas être dans un répertoire servi par le web")
                    except ValueError:
                        pass
            try:
                p.mkdir(parents=True, exist_ok=True)
            except OSError as e:
                fail(f"{key} : {e}")
        values[key] = v
    config.get_settings().update(values)
    config.apply_dir_overrides()
    return ok({"www_root": str(config.WWW_ROOT), "backup_dir": str(config.BACKUP_DIR)}, "Répertoires enregistrés (les sites existants conservent leur racine)")
