"""Detectors for sensitive values and account/service signals.

Each sensitive detector returns matches as (kind, raw_value) so the redaction
layer can decide how much to keep. Crypto seed phrases are handled specially:
we only report that one *appears* to be present and never return the words.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Callable, List, Optional, Tuple


@dataclass
class Finding:
    kind: str          # e.g. "credit_card", "ssn", "iban", "seed_phrase"
    raw: Optional[str] # the matched text, or None when we refuse to keep it
    severity: str      # "high" | "medium" | "low"
    advice: str        # recommended action for the user


# --- helpers ---------------------------------------------------------------

def _luhn_ok(digits: str) -> bool:
    """Validate a card-like number with the Luhn checksum."""
    total = 0
    reverse = digits[::-1]
    for i, ch in enumerate(reverse):
        d = ord(ch) - 48
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return total % 10 == 0


# --- regexes ---------------------------------------------------------------

_CARD_RE = re.compile(r"\b(?:\d[ -]?){13,19}\b")
_SSN_RE = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")
_IBAN_RE = re.compile(r"\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b")
_ROUTING_RE = re.compile(r"\b(?:routing|aba)\D{0,12}(\d{9})\b", re.IGNORECASE)
_US_ACCT_RE = re.compile(r"\b(?:account|acct)\D{0,12}(\d{8,17})\b", re.IGNORECASE)
_PRIVKEY_RE = re.compile(
    r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----"
)
_ETH_KEY_RE = re.compile(r"\b0x[a-fA-F0-9]{64}\b")
_PASSWORD_LABEL_RE = re.compile(
    r"(?:password|passwd|pwd|passphrase)\s*[:=]\s*(\S{6,})", re.IGNORECASE
)
_GIFTCARD_RE = re.compile(
    r"(?:gift\s*card|redemption|redeem)\D{0,30}([A-Z0-9]{4}(?:[- ][A-Z0-9]{4}){2,5})",
    re.IGNORECASE,
)
# A plausible BIP39 recovery phrase: 12 or 24 lowercase words of 3-8 letters.
_WORD = r"[a-z]{3,8}"
_SEED_RE = re.compile(
    rf"\b(?:{_WORD}\s+){{11}}{_WORD}\b(?:\s+(?:{_WORD}\s+){{11}}{_WORD}\b)?"
)


def _find_cards(text: str) -> List[Finding]:
    out: List[Finding] = []
    for m in _CARD_RE.finditer(text):
        digits = re.sub(r"[ -]", "", m.group())
        if 13 <= len(digits) <= 19 and _luhn_ok(digits):
            out.append(
                Finding(
                    "credit_card",
                    digits,
                    "high",
                    "Looks like a payment card number. Don't keep it in email; "
                    "store cards only in your bank app or a password manager.",
                )
            )
    return out


def _find_seed(text: str) -> List[Finding]:
    out: List[Finding] = []
    for _m in _SEED_RE.finditer(text):
        # We deliberately do NOT keep the matched words.
        out.append(
            Finding(
                "seed_phrase",
                None,
                "high",
                "Possible crypto recovery/seed phrase. If real, move it OFFLINE "
                "immediately (hardware wallet / paper in a safe) and delete it "
                "from email. Anyone who reads it can drain the wallet.",
            )
        )
    return out


def _simple(regex: re.Pattern, kind: str, severity: str, advice: str):
    def fn(text: str) -> List[Finding]:
        return [Finding(kind, m.group(0), severity, advice) for m in regex.finditer(text)]
    return fn


def _group1(regex: re.Pattern, kind: str, severity: str, advice: str):
    def fn(text: str) -> List[Finding]:
        return [Finding(kind, m.group(1), severity, advice) for m in regex.finditer(text)]
    return fn


SENSITIVE_DETECTORS: List[Tuple[str, Callable[[str], List[Finding]]]] = [
    ("credit_card", _find_cards),
    ("seed_phrase", _find_seed),
    ("ssn", _simple(_SSN_RE, "ssn", "high",
                    "US Social Security Number. Remove from email; store securely.")),
    ("iban", _simple(_IBAN_RE, "iban", "medium",
                     "Bank IBAN. Fine to keep privately, but not in your inbox.")),
    ("routing", _group1(_ROUTING_RE, "bank_routing", "medium",
                        "Bank routing number near this text.")),
    ("bank_account", _group1(_US_ACCT_RE, "bank_account", "medium",
                             "Possible bank account number.")),
    ("private_key", _simple(_PRIVKEY_RE, "private_key", "high",
                            "A private key block. Rotate it and never email keys.")),
    ("eth_key", _simple(_ETH_KEY_RE, "crypto_private_key", "high",
                        "Looks like a 32-byte hex private key. Treat as compromised.")),
    ("password", _group1(_PASSWORD_LABEL_RE, "password", "high",
                         "A labeled password in plaintext. Change it and use a "
                         "password manager.")),
    ("gift_card", _group1(_GIFTCARD_RE, "gift_card", "medium",
                          "Possible gift card / redemption code — still has value.")),
]


def scan_sensitive(text: str) -> List[Finding]:
    findings: List[Finding] = []
    for _name, fn in SENSITIVE_DETECTORS:
        findings.extend(fn(text))
    return findings
