"""Classify a message/sender into a service category and derive the brand name.

This is what powers the "which stores / services do I have accounts with"
index. It uses the sender domain plus keyword signals in the subject/body.
"""

from __future__ import annotations

import re
from typing import Dict, List, Optional, Tuple

# Category -> keyword signals (matched against domain + subject + snippet).
CATEGORY_KEYWORDS: Dict[str, List[str]] = {
    "banking": ["bank", "chase", "wells fargo", "citi", "capital one", "statement",
                "credit union", "ach", "wire transfer", "overdraft", "visa", "mastercard"],
    "crypto": ["coinbase", "binance", "kraken", "crypto", "wallet", "bitcoin",
               "ethereum", "ledger", "trezor", "metamask", "blockchain"],
    "insurance": ["insurance", "geico", "allstate", "state farm", "progressive",
                  "policy number", "premium", "claim", "deductible", "coverage"],
    "shopping": ["order", "shipped", "your order", "receipt", "amazon", "ebay",
                 "etsy", "walmart", "target", "cart", "purchase", "delivery"],
    "subscription": ["subscription", "renew", "trial", "netflix", "spotify",
                     "membership", "billed", "auto-renew", "plan"],
    "utilities": ["electric", "water bill", "gas bill", "utility", "internet",
                  "comcast", "verizon", "at&t", "t-mobile", "broadband"],
    "travel": ["flight", "booking", "reservation", "itinerary", "hotel",
               "airbnb", "boarding pass", "airline", "expedia"],
    "health": ["health", "pharmacy", "prescription", "medical", "patient",
               "doctor", "clinic", "lab results", "appointment"],
    "government": ["irs", "dmv", "passport", "social security", "gov",
                   "tax return", "benefits", "license renewal"],
    "identity": ["verify your email", "reset your password", "welcome to",
                 "your account", "sign-in", "two-factor", "confirm your account"],
}

_ORDER_SIGNALS = re.compile(
    r"(order confirmation|your order|has shipped|welcome to|account created|"
    r"reset your password|verify your email|receipt|invoice)", re.IGNORECASE
)

# Generic mailbox hosts we should not treat as a "brand".
_GENERIC_HOSTS = {"gmail.com", "googlemail.com", "yahoo.com", "outlook.com",
                  "hotmail.com", "icloud.com", "proton.me", "aol.com"}


def brand_from_domain(domain: str) -> str:
    domain = (domain or "").lower().strip().strip(".")
    # Strip common mail subdomains.
    for prefix in ("email.", "mail.", "e.", "em.", "news.", "info.", "no-reply.",
                   "noreply.", "notifications.", "notification.", "updates."):
        if domain.startswith(prefix):
            domain = domain[len(prefix):]
    parts = domain.split(".")
    if len(parts) >= 2:
        return parts[-2]
    return domain or "unknown"


def classify(sender_domain: str, subject: str, snippet: str) -> Tuple[str, Optional[str]]:
    """Return (category, brand). Category is 'other' when nothing matches."""
    hay = " ".join([sender_domain or "", subject or "", snippet or ""]).lower()

    scores: Dict[str, int] = {}
    for category, words in CATEGORY_KEYWORDS.items():
        score = sum(1 for w in words if w in hay)
        if score:
            scores[category] = score

    category = max(scores, key=scores.get) if scores else "other"

    brand: Optional[str] = None
    dom = (sender_domain or "").lower()
    if dom and dom not in _GENERIC_HOSTS:
        brand = brand_from_domain(dom)

    return category, brand


def looks_like_account_signup(subject: str, snippet: str) -> bool:
    return bool(_ORDER_SIGNALS.search(f"{subject}\n{snippet}"))
