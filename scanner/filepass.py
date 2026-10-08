"""Find the password for a password-protected attachment.

When a bank, tax preparer, or insurer emails you a protected PDF/ZIP, the
password (or a hint like "your date of birth") is almost always written in
that same email. This module reads the password out of the email you were
given — it does NOT crack or guess anything — so it can be saved right next
to the file for you.
"""

from __future__ import annotations

import io
import re
import zipfile
from typing import List, Optional

# ---------------------------------------------------------------------------
# 1. Is the saved file actually password-protected / encrypted?
# ---------------------------------------------------------------------------

_OLE_MAGIC = b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"  # legacy Office / encrypted OOXML


def is_encrypted(filename: str, data: bytes) -> bool:
    """Best-effort check for common protected formats (PDF, ZIP, Office)."""
    if not data:
        return False
    name = (filename or "").lower()

    # PDF: an /Encrypt entry in the trailer means it's password/owner protected.
    if data[:5] == b"%PDF-" or name.endswith(".pdf"):
        head = data[:2_000_000]
        if re.search(rb"/Encrypt\b", head):
            return True

    # ZIP (and modern Office files, which are ZIPs): check the encryption flag.
    if data[:2] == b"PK":
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                for info in zf.infolist():
                    if info.flag_bits & 0x1:  # bit 0 = encrypted
                        return True
        except Exception:
            # Can't open as a zip at all — may be encrypted/corrupt; stay cautious.
            if name.endswith((".zip", ".docx", ".xlsx", ".pptx")):
                return True

    # Encrypted modern Office is stored as an OLE container holding
    # "EncryptedPackage".
    if data[:8] == _OLE_MAGIC and b"EncryptedPackage" in data[:4096]:
        return True

    return False


# ---------------------------------------------------------------------------
# 2. Read the password (or hint) out of the email body.
# ---------------------------------------------------------------------------

# A literal password stated in the email: "the password is ABC123",
# "password: ABC123", "passcode = 1234", "PIN to open is 4821".
_LITERAL_RE = re.compile(
    r"""(?:pass\s?(?:word|code|phrase)|pwd|pin|passkey)\b
        [^.\n:=]{0,40}?
        (?:\bis\b|:|=|\bwill\s+be\b|\bare\b)\s*
        ["'“]?
        ([A-Za-z0-9!@#$%^&*_\-+./]{3,64})
        ["'”]?""",
    re.IGNORECASE | re.VERBOSE,
)

# A described password: "password is your date of birth", "use the last 4
# digits of your SSN", "protected with your account number". We keep the
# description so you know what to type.
_HINT_RE = re.compile(
    r"""(?:pass\s?(?:word|code|phrase)|pwd|pin)\b[^.\n]{0,40}?
        (your\s+(?:date\s+of\s+birth|dob|zip\s*code|postal\s*code|
                   account\s+number|member\s+(?:id|number)|
                   policy\s+number|customer\s+(?:id|number)|
                   last\s+name|first\s+name|
                   last\s+(?:4|four)\s+(?:digits\s+)?(?:of\s+)?
                       (?:your\s+)?(?:ssn|social|account|card|phone)?|
                   social\s+security(?:\s+number)?)
         [^.\n]{0,30})""",
    re.IGNORECASE | re.VERBOSE,
)

# Phrases that tell us the email is talking about a protected file at all —
# used to avoid grabbing "reset your password" links as a file password.
_PROTECTED_HINT = re.compile(
    r"(password[\s-]?protect|protected\s+(?:pdf|file|document|attachment|zip)|"
    r"to\s+open\s+(?:the|this|your)\s+(?:attach|file|pdf|document)|"
    r"open\s+the\s+attach|encrypted\s+(?:pdf|file|attachment|document))",
    re.IGNORECASE,
)

# Things that are NOT a file password even if they match the literal pattern.
_NOISE = re.compile(r"^(reset|change|forgot|your|the|a|to|is|be|here|https?|www)$",
                    re.IGNORECASE)


def find_password(text: str, require_context: bool = False) -> Optional[str]:
    """Return the best password/hint found in ``text``, or None.

    ``require_context`` only returns something when the email clearly refers to
    a protected file (good for scanning every email); pass False when you
    already know an attachment was encrypted.
    """
    if not text:
        return None
    if require_context and not _PROTECTED_HINT.search(text):
        return None

    results: List[str] = []

    for m in _LITERAL_RE.finditer(text):
        val = m.group(1).strip().strip(".,;")
        if val and not _NOISE.match(val) and not val.lower().startswith(("http", "www")):
            results.append(val)

    if not results:
        for m in _HINT_RE.finditer(text):
            desc = " ".join(m.group(1).split())
            if desc:
                results.append(f"(hint) {desc}")

    if not results:
        return None
    # Prefer a concrete literal password over a described hint.
    literals = [r for r in results if not r.startswith("(hint)")]
    return (literals or results)[0]
