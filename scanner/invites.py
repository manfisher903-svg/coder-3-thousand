"""Invite codes for registration (owner-controlled access).

The owner generates codes and hands them out. A new person can only create an
account if they enter a valid, unused code. Codes live in a small local JSON
file on the machine that hosts the app (never committed, never uploaded).
"""

from __future__ import annotations

import json
import os
import secrets
import string
from datetime import datetime, timezone
from typing import List, Tuple

_ALPHABET = string.ascii_uppercase + string.digits
# Avoid look-alike characters so codes are easy to read/type over the phone.
_ALPHABET = "".join(c for c in _ALPHABET if c not in "O0I1")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def load_codes(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def _save(path: str, codes: dict) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(codes, fh)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def _gen() -> str:
    block = lambda: "".join(secrets.choice(_ALPHABET) for _ in range(4))
    return f"SR-{block()}-{block()}"


def create_code(path: str, created_by: str, label: str = "",
                max_uses: int = 1) -> str:
    """Make and store a new invite code; return it."""
    codes = load_codes(path)
    code = _gen()
    while code in codes:
        code = _gen()
    codes[code] = {
        "created_by": created_by,
        "created_at": _now(),
        "label": (label or "").strip()[:60],
        "max_uses": max(1, int(max_uses or 1)),
        "used_by": [],          # usernames that redeemed it
        "disabled": False,
    }
    _save(path, codes)
    return code


def _normalize(code: str) -> str:
    return (code or "").strip().upper()


def check_valid(path: str, code: str) -> Tuple[bool, str]:
    """Is this code usable right now? Does NOT consume it."""
    rec = load_codes(path).get(_normalize(code))
    if not rec:
        return False, "That invite code isn't valid."
    if rec.get("disabled"):
        return False, "That invite code has been turned off."
    if len(rec.get("used_by", [])) >= rec.get("max_uses", 1):
        return False, "That invite code has already been used up."
    return True, "ok"


def redeem(path: str, code: str, username: str) -> Tuple[bool, str]:
    """Consume one use of a code for `username`."""
    codes = load_codes(path)
    key = _normalize(code)
    rec = codes.get(key)
    ok, msg = check_valid(path, code)
    if not ok:
        return False, msg
    rec["used_by"].append(username)
    _save(path, codes)
    return True, "ok"


def revoke(path: str, code: str) -> Tuple[bool, str]:
    """Turn a code off so it can no longer be used."""
    codes = load_codes(path)
    key = _normalize(code)
    if key not in codes:
        return False, "No such code."
    codes[key]["disabled"] = True
    _save(path, codes)
    return True, "ok"


def delete_code(path: str, code: str) -> Tuple[bool, str]:
    codes = load_codes(path)
    key = _normalize(code)
    if key not in codes:
        return False, "No such code."
    del codes[key]
    _save(path, codes)
    return True, "ok"


def list_codes(path: str) -> List[dict]:
    """All codes, newest first, each annotated with its live status."""
    out = []
    for code, rec in load_codes(path).items():
        used = len(rec.get("used_by", []))
        mx = rec.get("max_uses", 1)
        if rec.get("disabled"):
            status = "revoked"
        elif used >= mx:
            status = "used up"
        else:
            status = "active"
        out.append({"code": code, "status": status, "used": used,
                    "max_uses": mx, **rec})
    out.sort(key=lambda r: r.get("created_at", ""), reverse=True)
    return out
