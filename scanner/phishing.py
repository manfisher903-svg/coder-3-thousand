"""Judge whether an email looks legit or like phishing/spoofing.

Heuristic, explainable scoring — no network calls. Returns a verdict plus the
specific reasons, so you can see WHY something is flagged. Signals:

  * brand impersonation (display name says a brand, domain doesn't match)
  * freemail sender claiming to be a company
  * Reply-To domain differs from the From domain
  * failed SPF/DKIM/DMARC (when the headers are present)
  * urgency / threat / credential-request language
  * risky links (IP-address URLs, look-alike domains, shorteners)
  * risky attachment types (.exe, .scr, .js, .iso, …)
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import List, Optional

# Well-known brands and the domains that legitimately send their mail.
_BRANDS = {
    "paypal": ["paypal.com", "paypal.co.uk"],
    "apple": ["apple.com", "icloud.com", "id.apple.com"],
    "amazon": ["amazon.com", "amazon.co.uk"],
    "microsoft": ["microsoft.com", "outlook.com", "office365.com", "live.com"],
    "google": ["google.com", "googlemail.com", "gmail.com", "accounts.google.com"],
    "netflix": ["netflix.com"],
    "bank of america": ["bankofamerica.com", "bofa.com"],
    "chase": ["chase.com", "jpmorgan.com"],
    "wells fargo": ["wellsfargo.com"],
    "irs": ["irs.gov"],
    "usps": ["usps.com", "email.usps.com"],
    "fedex": ["fedex.com"],
    "ups": ["ups.com"],
    "coinbase": ["coinbase.com"],
    "venmo": ["venmo.com"],
    "facebook": ["facebook.com", "facebookmail.com"],
    "instagram": ["instagram.com", "mail.instagram.com"],
}

_FREEMAIL = {"gmail.com", "yahoo.com", "outlook.com", "hotmail.com", "aol.com",
             "icloud.com", "proton.me", "gmx.com", "mail.com", "yandex.com"}

_URGENT = re.compile(
    r"\b(verify your (account|identity)|confirm your (password|account|identity)|"
    r"suspended|unusual (activity|sign|login)|your account (will|has been)|"
    r"act now|urgent|immediately|final (notice|warning)|update your (payment|billing)|"
    r"re-?activate|limited|locked|unauthorized|wire transfer|gift card|"
    r"bitcoin|crypto|social security|refund pending|claim your)\b",
    re.IGNORECASE)

_CRED_REQUEST = re.compile(
    r"\b(enter your (password|pin|ssn|card)|login (here|below)|"
    r"click (here|the link) to (verify|confirm|log ?in|update)|"
    r"provide your (password|ssn|card|bank))\b", re.IGNORECASE)

_SHORTENERS = {"bit.ly", "tinyurl.com", "goo.gl", "t.co", "ow.ly", "is.gd",
               "buff.ly", "rebrand.ly", "cutt.ly"}

_RISKY_EXT = {".exe", ".scr", ".js", ".jar", ".vbs", ".bat", ".cmd", ".iso",
              ".img", ".ps1", ".hta", ".lnk", ".docm", ".xlsm"}

_URL_RE = re.compile(r"https?://([^/\s\"'>)]+)", re.IGNORECASE)
_IP_HOST_RE = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}$")


@dataclass
class Verdict:
    label: str            # "legit" | "suspicious" | "likely phishing"
    score: int
    reasons: List[str] = field(default_factory=list)


def _domain(addr: str) -> str:
    return addr.split("@")[-1].lower().strip() if "@" in (addr or "") else ""


def _registrable(domain: str) -> str:
    parts = (domain or "").split(".")
    return ".".join(parts[-2:]) if len(parts) >= 2 else domain


def _looks_lookalike(domain: str) -> bool:
    # digits swapped for letters, or a brand name embedded in a longer domain.
    reg = _registrable(domain)
    for brand, domains in _BRANDS.items():
        b = brand.replace(" ", "")
        if b in reg.replace("-", "") and reg not in [_registrable(d) for d in domains]:
            return True
    if re.search(r"(paypa1|g00gle|micr0soft|amaz0n|app1e|netf1ix)", domain):
        return True
    return False


def analyze_email(from_addr: str, from_name: str, subject: str, body: str,
                  reply_to: Optional[str] = None,
                  auth_results: Optional[str] = None,
                  attachment_names: Optional[List[str]] = None) -> Verdict:
    reasons: List[str] = []
    score = 0
    from_dom = _domain(from_addr)
    name = (from_name or "").lower()
    text = f"{subject}\n{body}"

    # 1. Brand impersonation in the display name.
    for brand, domains in _BRANDS.items():
        if brand in name or brand.replace(" ", "") in name.replace(" ", ""):
            ok = any(from_dom == d or from_dom.endswith("." + d) for d in domains)
            if not ok and from_dom:
                score += 3
                reasons.append(f"Display name mentions “{brand}”, but it was sent "
                               f"from {from_dom} (not an official {brand} domain).")
            break

    # 2. Freemail sender claiming to be a company (brand word in name + freemail).
    if from_dom in _FREEMAIL and any(b in name for b in _BRANDS):
        score += 2
        reasons.append(f"Claims to be a company but was sent from a free personal "
                       f"address ({from_dom}).")

    # 3. Reply-To domain mismatch.
    if reply_to:
        rdom = _domain(reply_to)
        if rdom and from_dom and _registrable(rdom) != _registrable(from_dom):
            score += 2
            reasons.append(f"Reply-To goes to a different domain ({rdom}) than the "
                           f"sender ({from_dom}).")

    # 4. Authentication results (if present in headers).
    if auth_results:
        ar = auth_results.lower()
        for mech in ("spf", "dkim", "dmarc"):
            if f"{mech}=fail" in ar or f"{mech}=softfail" in ar:
                score += 2
                reasons.append(f"Email failed {mech.upper()} authentication "
                               f"(a spoofing red flag).")

    # 5. Look-alike / spoofed sender domain.
    if from_dom and _looks_lookalike(from_dom):
        score += 3
        reasons.append(f"Sender domain {from_dom} looks like a fake imitation of a "
                       f"real brand.")

    # 6. Urgency / credential-request language.
    if _URGENT.search(text):
        score += 1
        reasons.append("Uses urgency / threat wording common in scams.")
    if _CRED_REQUEST.search(text):
        score += 2
        reasons.append("Asks you to click a link and enter a password / personal info.")

    # 7. Risky links.
    hosts = {h.lower() for h in _URL_RE.findall(body or "")}
    for h in hosts:
        host = h.split(":")[0]
        if _IP_HOST_RE.match(host):
            score += 2
            reasons.append(f"Contains a link to a raw IP address ({host}).")
        elif _registrable(host) in _SHORTENERS:
            score += 1
            reasons.append(f"Uses a link shortener ({host}) that hides the real "
                           f"destination.")
        elif _looks_lookalike(host):
            score += 2
            reasons.append(f"Links to a look-alike domain ({host}).")

    # 8. Risky attachments.
    for nm in (attachment_names or []):
        ext = ("." + nm.rsplit(".", 1)[-1].lower()) if "." in nm else ""
        if ext in _RISKY_EXT:
            score += 3
            reasons.append(f"Has a dangerous attachment type ({nm}).")

    if score >= 4:
        label = "likely phishing"
    elif score >= 2:
        label = "suspicious"
    else:
        label = "legit"
        if not reasons:
            reasons.append("No common phishing signals found.")
    return Verdict(label=label, score=score, reasons=reasons)
