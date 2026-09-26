"""Authentification : mots de passe, sessions signées et révocables, TOTP (anti-rejeu, codes de secours),
jetons d'API, anti-bruteforce par IP et par compte, liste blanche d'IP."""
from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import time
from collections import defaultdict
from typing import Optional

import bcrypt
import pyotp
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer

from toutpanel.config import get_settings

SESSION_COOKIE = "tp_session"
CSRF_HEADER = "x-requested-with"
CSRF_VALUE = "ToutPanel"
TOKEN_PREFIX = "tp_"

# Empreinte bcrypt d'un mot de passe aléatoire : la vérification d'un utilisateur inexistant prend le même temps qu'une vraie.
_DUMMY_HASH = bcrypt.hashpw(secrets.token_bytes(16), bcrypt.gensalt()).decode("ascii")


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("ascii")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("ascii"))
    except (ValueError, TypeError):
        return False


def burn_time() -> None:
    """Consomme le temps d'une vérification bcrypt (utilisateur inconnu) pour ne pas révéler les comptes existants."""
    verify_password("x", _DUMMY_HASH)


def password_policy(password: str, username: str = "") -> str:
    """Retourne un message d'erreur si le mot de passe est trop faible, sinon une chaîne vide."""
    if len(password) < 8:
        return "Le mot de passe doit faire au moins 8 caractères"
    if len(password) > 256:
        return "Mot de passe trop long"
    if not re.search(r"[A-Za-z]", password) or not re.search(r"\d", password):
        return "Le mot de passe doit contenir au moins une lettre et un chiffre"
    if username and password.lower() == username.lower():
        return "Le mot de passe ne doit pas être identique au nom d'utilisateur"
    if password.lower() in ("password", "motdepasse", "admin123", "12345678", "azerty123", "qwerty123", "password1"):
        return "Ce mot de passe est trop courant"
    return ""


def generate_password(length: int = 16) -> str:
    alphabet = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(length))


# --- sessions ----------------------------------------------------------

def _serializer() -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(get_settings().get("secret_key"), salt="tp-session")


def new_session_id() -> str:
    return secrets.token_urlsafe(24)


def create_session_token(user_id: int, username: str, sid: str) -> str:
    return _serializer().dumps({"uid": user_id, "u": username, "n": sid})


def read_session_token(token: str) -> Optional[dict]:
    max_age = int(get_settings().get("session_hours", 12)) * 3600
    try:
        return _serializer().loads(token, max_age=max_age)
    except (BadSignature, SignatureExpired):
        return None


# --- jetons d'API ------------------------------------------------------

def new_api_token() -> tuple[str, str, str]:
    """(jeton en clair à afficher une seule fois, préfixe affichable, empreinte à stocker)."""
    raw = TOKEN_PREFIX + secrets.token_urlsafe(32)
    return raw, raw[:10], hash_token(raw)


def hash_token(raw: str) -> str:
    return hmac.new(str(get_settings().get("secret_key")).encode(), raw.encode(), hashlib.sha256).hexdigest()


# --- TOTP ---------------------------------------------------------------

def new_totp_secret() -> str:
    return pyotp.random_base32()


def totp_uri(secret: str, username: str, issuer: str = "ToutPanel") -> str:
    return pyotp.TOTP(secret).provisioning_uri(name=username, issuer_name=issuer)


def verify_totp(secret: str, code: str, last_used: int = -1) -> tuple[bool, int]:
    """Vérifie un code TOTP (fenêtre ±1). Retourne (valide, compteur) ; un compteur déjà accepté est refusé (anti-rejeu)."""
    if not secret or not code:
        return False, -1
    code = code.strip().replace(" ", "")
    if not re.fullmatch(r"\d{6,8}", code):
        return False, -1
    totp = pyotp.TOTP(secret)
    now = int(time.time())
    for offset in (0, -1, 1):
        counter = (now // 30) + offset
        if hmac.compare_digest(totp.at(counter * 30), code):
            if counter <= last_used:
                return False, -1
            return True, counter
    return False, -1


def new_recovery_codes(n: int = 8) -> tuple[list[str], list[str]]:
    """(codes en clair à afficher une seule fois, empreintes à stocker)."""
    alphabet = "abcdefghjkmnpqrstuvwxyz23456789"
    codes = ["".join(secrets.choice(alphabet) for _ in range(5)) + "-" + "".join(secrets.choice(alphabet) for _ in range(5)) for _ in range(n)]
    return codes, [hash_token("rc:" + c) for c in codes]


def use_recovery_code(stored: list, code: str) -> Optional[list]:
    """Consomme un code de secours. Retourne la nouvelle liste d'empreintes, ou None si le code est inconnu."""
    code = code.strip().lower().replace(" ", "")
    h = hash_token("rc:" + code)
    if not stored or h not in stored:
        return None
    return [x for x in stored if x != h]


# --- Anti brute force ---------------------------------------------------

class LoginLimiter:
    """Verrouillage par adresse IP et par nom de compte (une attaque distribuée sur un compte est aussi bloquée)."""

    def __init__(self):
        self._fails: dict[str, list[float]] = defaultdict(list)

    def _window_limit(self) -> tuple[int, int]:
        s = get_settings()
        return int(s.get("lockout_minutes", 10)) * 60, int(s.get("max_login_attempts", 5))

    def _prune(self, key: str, window: int) -> list[float]:
        now = time.time()
        kept = [t for t in self._fails.get(key, []) if now - t < window]
        if kept:
            self._fails[key] = kept
        else:
            self._fails.pop(key, None)
        # la table ne doit pas grossir indéfiniment sous un balayage d'IP
        if len(self._fails) > 5000:
            for k in list(self._fails)[:1000]:
                self._fails.pop(k, None)
        return kept

    def is_locked(self, ip: str, username: str = "") -> bool:
        window, limit = self._window_limit()
        if len(self._prune("ip:" + ip, window)) >= limit:
            return True
        return bool(username) and len(self._prune("user:" + username.lower(), window)) >= limit * 2

    def record_failure(self, ip: str, username: str = "") -> None:
        now = time.time()
        self._fails["ip:" + ip].append(now)
        if username:
            self._fails["user:" + username.lower()].append(now)

    def reset(self, ip: str, username: str = "") -> None:
        self._fails.pop("ip:" + ip, None)
        if username:
            self._fails.pop("user:" + username.lower(), None)


limiter = LoginLimiter()


def ip_allowed(ip: str) -> bool:
    """Liste blanche d'IP (vide = tout le monde). Supporte les CIDR."""
    import ipaddress

    wl = get_settings().get("ip_whitelist") or []
    if not wl:
        return True
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    for entry in wl:
        entry = str(entry).strip()
        if not entry:
            continue
        try:
            if "/" in entry:
                if addr in ipaddress.ip_network(entry, strict=False):
                    return True
            elif addr == ipaddress.ip_address(entry):
                return True
        except ValueError:
            continue
    return False
