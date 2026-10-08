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
    context: str = ""  # the surrounding text, exactly as it appears in the email


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

# --- identity / contact details (for the "my info in my inbox" audit) ------
_EMAIL_RE = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
_PHONE_RE = re.compile(
    r"(?<!\d)(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}(?!\d)")
_DOB_RE = re.compile(
    r"(?:date of birth|d\.?o\.?b\.?|birth\s*date|born(?:\s+on)?)\s*[:\-]?\s*"
    r"((?:\d{1,2}[/-]\d{1,2}[/-]\d{2,4})|"
    r"(?:(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}))",
    re.IGNORECASE)
_ADDRESS_RE = re.compile(
    r"\b\d{1,6}\s+(?:[A-Za-z0-9.'-]+\s){1,4}"
    r"(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Dr|Drive|Lane|Ln|Ct|Court|Way|"
    r"Pl|Place|Ter|Terrace|Cir|Circle|Hwy|Highway|Pkwy|Parkway)\.?"
    r"(?:\s*,?\s*(?:Apt|Unit|Ste|Suite|#)\s*\w+)?",
    re.IGNORECASE)

# --- tax info -------------------------------------------------------------
# Employer Identification Number, written near an EIN label (XX-XXXXXXX).
_EIN_RE = re.compile(
    r"(?:ein|employer\s+identification(?:\s*(?:no\.?|number|#))?)\D{0,8}(\d{2}-\d{7})",
    re.IGNORECASE)
# Tax forms / IRS references that mean "tax documents live in this email".
_TAX_DOC_RE = re.compile(
    r"\b(W-?2|1099(?:-[A-Z]{1,4})?|1098(?:-[A-Z]{1,4})?|1040(?:-[A-Z]{1,4})?|"
    r"W-?4|W-?9|Schedule\s+[A-K]|K-1|tax\s+return|adjusted\s+gross\s+income|"
    r"\bAGI\b|TurboTax|TaxAct|H&R\s*Block|IRS|tax\s+year\s+\d{4}|"
    r"tax\s+(?:document|statement|transcript|refund))\b",
    re.IGNORECASE)


def _in_url(text: str, start: int, end: int) -> bool:
    """True if the match at [start:end] is part of a URL / query string."""
    before = text[max(0, start - 40):start]
    if "http" in before or "www." in before or ".com/" in before:
        return True
    if start > 0 and text[start - 1] in "=/?&.:#":
        return True
    if end < len(text) and text[end] in "=/?&#":
        return True
    return False


def _find_cards(text: str) -> List[Finding]:
    out: List[Finding] = []
    for m in _CARD_RE.finditer(text):
        if _in_url(text, m.start(), m.end()):
            continue  # a number inside a link/tracking URL, not a card
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


_PW_INSTRUCTION = re.compile(
    r"(reset|forgot|change|create|set|update|new|choose|enter your|your new)\s+"
    r"(?:your\s+)?(?:password|passwd)", re.IGNORECASE)


def _find_passwords(text: str) -> List[Finding]:
    """Real plaintext passwords only — skip reset links and instructions."""
    out: List[Finding] = []
    for m in _PASSWORD_LABEL_RE.finditer(text):
        value = m.group(1)
        # Skip "reset/forgot/change your password" instruction emails.
        pre = text[max(0, m.start() - 25):m.start() + 8]
        if _PW_INSTRUCTION.search(pre):
            continue
        # Skip when the "value" is actually a URL / link.
        if value.lower().startswith(("http", "www.")) or "://" in value or "/" in value:
            continue
        out.append(Finding("password", value, "high",
                           "A labeled password in plaintext. Change it and use a "
                           "password manager."))
    return out


_SEED_CONTEXT = re.compile(
    r"(seed|recovery|mnemonic|wallet|private\s*key|backup\s*phrase|bip-?39|"
    r"metamask|ledger|trezor|coinbase|crypto)", re.IGNORECASE)


def _find_seed(text: str) -> List[Finding]:
    out: List[Finding] = []
    for m in _SEED_RE.finditer(text):
        # Require crypto context nearby, or 12+ random words in prose would match.
        near = text[max(0, m.start() - 60):m.start()]
        if not _SEED_CONTEXT.search(near):
            continue
        out.append(
            Finding(
                "seed_phrase",
                m.group(0).strip(),
                "high",
                "Possible crypto recovery/seed phrase. If real, move it OFFLINE "
                "(hardware wallet / paper in a safe) and delete it from email. "
                "Anyone who reads it can drain the wallet.",
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
    ("password", _find_passwords),
    ("gift_card", _group1(_GIFTCARD_RE, "gift_card", "medium",
                          "Possible gift card / redemption code — still has value.")),
    ("ein", _group1(_EIN_RE, "ein", "medium",
                    "Employer Identification Number (a tax ID). Keep it private.")),
    ("tax_document", _simple(_TAX_DOC_RE, "tax_document", "medium",
                             "Tax info in this email (W-2/1099/1040/IRS, etc.). "
                             "Store tax documents securely, not in your inbox.")),
]

# --- labeled values: catch info written in plain language -----------------
# e.g. "my card number is 5424189090238457", "ssn is 34398543",
#      "seed key: oniuni...", "pin: 1234". Format-tolerant, label-driven.
_L_CARD = re.compile(
    r"card(?:\s*(?:number|num|no\.?|#))?\s*(?:is|:|=)?\s*"
    r"(\d{4}(?:[ -]?\d{4}){2,4}|\d{12,19})", re.IGNORECASE)
_L_SSN = re.compile(
    r"(?:ssn|social\s*security(?:\s*(?:number|no\.?|#))?)\s*(?:is|:|=)?\s*"
    r"(\d{3}-?\d{2}-?\d{4}|\d{6,11})", re.IGNORECASE)
_L_SEED = re.compile(
    r"(?:seed\s*(?:key|phrase)?|recovery\s*(?:phrase|key)|mnemonic|"
    r"wallet\s*backup)\s*(?:is|:|=)?\s*([A-Za-z0-9][A-Za-z0-9 ]{11,199})",
    re.IGNORECASE)
_L_PIN = re.compile(r"\b(?:cvv|cvc|security\s*code|pin)\b\s*(?:is|:|=)?\s*(\d{3,6})\b",
                    re.IGNORECASE)
_L_ROUTING = re.compile(r"routing\s*(?:number|no\.?|#)?\s*(?:is|:|=)?\s*(\d{9})\b",
                        re.IGNORECASE)
_L_ACCT = re.compile(
    r"(?:account|acct)\s*(?:number|no\.?|#)?\s*(?:is|:|=)?\s*(\d{6,17})\b",
    re.IGNORECASE)

LABELED_DETECTORS: List[Tuple[str, Callable[[str], List[Finding]]]] = [
    ("credit_card", _group1(_L_CARD, "credit_card", "high",
                            "A card number is written out here. Don't keep card "
                            "numbers in email.")),
    ("ssn", _group1(_L_SSN, "ssn", "high",
                    "An SSN is written out here. Remove it from email.")),
    ("seed_phrase", _group1(_L_SEED, "seed_phrase", "high",
                            "A crypto seed/recovery key is written out here. "
                            "Move it offline and delete it from email.")),
    ("pin", _group1(_L_PIN, "pin_or_cvv", "high",
                    "A PIN / CVV / security code is written out here.")),
    ("bank_routing", _group1(_L_ROUTING, "bank_routing", "medium",
                             "A bank routing number is written out here.")),
    ("bank_account", _group1(_L_ACCT, "bank_account", "medium",
                             "A bank account number is written out here.")),
]

# Identity / contact details found in your own inbox. These are "low" severity
# because they're normal to have — the point is to SEE what's exposed so you can
# remove or secure it. Kinds here are grouped as "Personal info found".
IDENTITY_KINDS = {"email_address", "phone", "date_of_birth", "mailing_address"}

IDENTITY_DETECTORS: List[Tuple[str, Callable[[str], List[Finding]]]] = [
    ("phone", _simple(_PHONE_RE, "phone", "low",
                      "A phone number appears in this inbox.")),
    ("email_address", _simple(_EMAIL_RE, "email_address", "low",
                              "An email address appears in this inbox.")),
    ("date_of_birth", _group1(_DOB_RE, "date_of_birth", "low",
                              "A date of birth appears in this inbox — sensitive, "
                              "consider removing it from stored mail.")),
    ("mailing_address", _simple(_ADDRESS_RE, "mailing_address", "low",
                                "A mailing address appears in this inbox.")),
]


def scan_sensitive(text: str) -> List[Finding]:
    findings: List[Finding] = []
    for _name, fn in SENSITIVE_DETECTORS:
        findings.extend(fn(text))
    for _name, fn in LABELED_DETECTORS:
        findings.extend(fn(text))
    for _name, fn in IDENTITY_DETECTORS:
        findings.extend(fn(text))

    # De-duplicate so strict + labeled detectors don't double-report. Most kinds
    # de-dupe by (kind, value); "signal" kinds that just mean "this email
    # contains X" collapse to ONE per message (e.g. tax keywords W-2/1099/1040).
    _ONE_PER_MESSAGE = {"tax_document"}
    seen = set()
    unique: List[Finding] = []
    for f in findings:
        key = (f.kind,) if f.kind in _ONE_PER_MESSAGE else (f.kind, (f.raw or "").strip())
        if key in seen:
            continue
        seen.add(key)
        f.context = _context_for(f.raw, text)
        unique.append(f)
    return unique


def _context_for(value: Optional[str], text: str, window: int = 60) -> str:
    """The text surrounding a found value, exactly as it appears (trimmed)."""
    if not value:
        return ""
    idx = text.find(value)
    if idx < 0:
        # value may have been normalized (e.g. card digits with spaces stripped)
        return value
    start = max(0, idx - window)
    end = min(len(text), idx + len(value) + window)
    snippet = text[start:end]
    snippet = " ".join(snippet.split())  # collapse newlines / runs of spaces
    if start > 0:
        snippet = "…" + snippet
    if end < len(text):
        snippet = snippet + "…"
    return snippet
