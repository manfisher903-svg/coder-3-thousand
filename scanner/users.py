"""Multi-user accounts for the app login.

Each person registers a unique username + their own password. Passwords are
stored hashed (PBKDF2-HMAC-SHA256, per-user random salt) — never plaintext, and
never compared between users. Usernames are unique (case-insensitive).
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
from typing import Optional, Tuple

_ITER = 200_000


def load_users(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def _save(path: str, users: dict) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(users, fh)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def username_taken(path: str, username: str) -> bool:
    return username.strip().lower() in load_users(path)


def valid_username(username: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9._-]{3,32}", username or ""))


def add_user(path: str, username: str, password: str) -> Tuple[bool, str]:
    username = (username or "").strip()
    if not valid_username(username):
        return False, ("Username must be 3–32 characters: letters, numbers, "
                       "dot, dash or underscore.")
    if len(password or "") < 6:
        return False, "Password must be at least 6 characters."
    users = load_users(path)
    if username.lower() in users:
        return False, "That username is already taken — pick another."
    salt = secrets.token_bytes(16)
    h = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _ITER)
    users[username.lower()] = {
        "username": username, "salt": salt.hex(), "hash": h.hex(), "iter": _ITER,
    }
    _save(path, users)
    return True, "ok"


def verify(path: str, username: str, password: str) -> Optional[str]:
    """Return the stored username on success, else None."""
    rec = load_users(path).get((username or "").strip().lower())
    if not rec:
        return None
    salt = bytes.fromhex(rec["salt"])
    want = bytes.fromhex(rec["hash"])
    got = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt,
                              rec.get("iter", _ITER))
    return rec["username"] if hmac.compare_digest(got, want) else None


def user_dirname(username: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "_", username) or "user"
