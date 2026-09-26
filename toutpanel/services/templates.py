"""Modèles Jinja personnalisables (vhosts, page d'accueil des sites).

Les modèles par défaut sont livrés dans toutpanel/templates/vhost ; l'utilisateur peut les surcharger
en déposant un fichier du même nom dans <home>/templates/vhost (édition depuis la page Personnalisation).
"""
from __future__ import annotations

from pathlib import Path

from jinja2.sandbox import SandboxedEnvironment
from jinja2 import ChoiceLoader, Environment, FileSystemLoader, TemplateSyntaxError

from toutpanel import config

TEMPLATES = {
    "nginx.conf.j2": "Vhost Nginx", "apache.conf.j2": "Vhost Apache", "site_index.html.j2": "Page d'accueil d'un nouveau site",
}


def default_dir() -> Path:
    return config.PACKAGE_DIR / "templates" / "vhost"


def override_dir() -> Path:
    d = config.HOME / "templates" / "vhost"
    d.mkdir(parents=True, exist_ok=True)
    return d


def env() -> Environment:
    return SandboxedEnvironment(loader=ChoiceLoader([FileSystemLoader(str(override_dir())), FileSystemLoader(str(default_dir()))]),
                       autoescape=False, trim_blocks=True, lstrip_blocks=True, keep_trailing_newline=True)


def source_of(name: str) -> str:
    return "personnalisé" if (override_dir() / name).exists() else "défaut"


def render(template_name: str, **ctx) -> str:
    ctx.setdefault("template_source", source_of(template_name))
    ctx.setdefault("panel_name", config.get_settings().get("panel_name", "ToutPanel"))
    return env().get_template(template_name).render(**ctx)


def get(name: str) -> dict:
    if name not in TEMPLATES:
        raise KeyError(name)
    ov = override_dir() / name
    default = (default_dir() / name).read_text(encoding="utf-8")
    return {"name": name, "label": TEMPLATES[name], "custom": ov.exists(), "content": ov.read_text(encoding="utf-8") if ov.exists() else default,
            "default": default}


def save(name: str, content: str) -> None:
    if name not in TEMPLATES:
        raise KeyError(name)
    try:
        Environment().parse(content)
    except TemplateSyntaxError as e:
        raise ValueError(f"Erreur de syntaxe Jinja ligne {e.lineno} : {e.message}")
    (override_dir() / name).write_text(content, encoding="utf-8")


def reset(name: str) -> None:
    (override_dir() / name).unlink(missing_ok=True)


def list_all() -> list[dict]:
    return [{"name": n, "label": l, "custom": (override_dir() / n).exists()} for n, l in TEMPLATES.items()]
