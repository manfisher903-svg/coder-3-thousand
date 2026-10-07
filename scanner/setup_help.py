"""Provider-specific, step-by-step setup instructions.

When a scan fails (usually a login/app-password issue), the app looks up the
account's provider here and shows exactly what to do — with the real settings
link — instead of a generic error.
"""

from __future__ import annotations

from typing import Optional

from .providers import _domain_of


def _guide(provider, url, steps, note=""):
    return {"provider": provider, "url": url, "steps": steps, "note": note}


_YAHOO = _guide(
    "Yahoo", "https://login.yahoo.com/account/security",
    [
        "Sign in to Yahoo, then open Account Info → Account Security.",
        "If you don't see “Generate app password”, first turn on "
        "“Two-step verification” (confirm a code by text).",
        "Click “Generate app password” (or “Generate and manage app passwords”), "
        "pick “Other app”, and name it “scanner”.",
        "Yahoo shows a 16-character code — copy it and remove the spaces.",
        "In SpeedRunner click Edit on this account, paste that code as the "
        "password, Save, then Re-scan.",
    ],
    "Your normal Yahoo password is rejected by mail apps on purpose — the "
    "16-character app password is what works.")

_GMAIL = _guide(
    "Gmail", "https://myaccount.google.com/apppasswords",
    [
        "Turn on 2-Step Verification: myaccount.google.com/signinoptions/two-step-verification.",
        "Open App passwords: myaccount.google.com/apppasswords.",
        "Create one named “scanner” and copy the 16-character code.",
        "Enable IMAP in Gmail: Settings (gear) → See all settings → "
        "“Forwarding and POP/IMAP” → Enable IMAP → Save.",
        "In SpeedRunner click Edit on this account, paste the 16-character code "
        "as the password, Save, then Re-scan.",
    ],
    "Gmail needs BOTH an app password and IMAP switched on.")

_MICROSOFT = _guide(
    "Outlook / Hotmail", "https://account.microsoft.com/security",
    [
        "Open account.microsoft.com/security → Advanced security options.",
        "Turn on Two-step verification if it isn't already.",
        "Under “App passwords”, click “Create a new app password”.",
        "Copy the password it shows.",
        "In SpeedRunner click Edit on this account, paste it as the password, "
        "Save, then Re-scan.",
    ],
    "Microsoft blocks the normal password for mail apps; the app password is "
    "required.")

_APPLE = _guide(
    "iCloud", "https://appleid.apple.com",
    [
        "Sign in at appleid.apple.com.",
        "Go to “Sign-In and Security” → “App-Specific Passwords”.",
        "Click “Generate an app-specific password”, name it “scanner”.",
        "Copy the password shown.",
        "In SpeedRunner click Edit on this account, paste it as the password, "
        "Save, then Re-scan.",
    ],
    "iCloud Mail requires an app-specific password (two-factor is already on).")

_AOL = _guide(
    "AOL", "https://login.aol.com/account/security",
    [
        "Sign in to AOL → Account Security.",
        "Turn on Two-step verification if needed.",
        "Click “Generate app password”, name it “scanner”.",
        "Copy the 16-character code (remove spaces).",
        "In SpeedRunner click Edit on this account, paste it as the password, "
        "Save, then Re-scan.",
    ])

_POP_LEGACY = _guide(
    "NetZero / Juno", "",
    [
        "These are POP-only providers and free plans usually block app access.",
        "Check your account/webmail for a “POP access” or “email program access” "
        "setting and turn it on (often only available on a paid plan).",
        "POP can read only the Inbox — not Sent or folders.",
        "If you can’t enable POP, this provider can’t be scanned; use a Gmail/"
        "Yahoo/Outlook account instead.",
    ],
    "Logging into the website is different from app (POP) access.")

_BY_DOMAIN = {}
for d in ("yahoo.com", "yahoo.co.uk", "ymail.com", "rocketmail.com"):
    _BY_DOMAIN[d] = _YAHOO
for d in ("gmail.com", "googlemail.com"):
    _BY_DOMAIN[d] = _GMAIL
for d in ("outlook.com", "hotmail.com", "live.com", "msn.com",
          "hotmail.co.uk", "outlook.co.uk"):
    _BY_DOMAIN[d] = _MICROSOFT
for d in ("icloud.com", "me.com", "mac.com"):
    _BY_DOMAIN[d] = _APPLE
for d in ("aol.com", "verizon.net"):
    _BY_DOMAIN[d] = _AOL
for d in ("netzero.net", "netzero.com", "juno.com"):
    _BY_DOMAIN[d] = _POP_LEGACY


def _generic(domain: str):
    return _guide(
        domain or "your provider", "",
        [
            f"Search the web for “{domain} IMAP app password”.",
            "In your email account’s Security settings, turn on two-step "
            "verification, then create an “app password”.",
            "Make sure IMAP access is enabled in the mail settings.",
            "In SpeedRunner click Edit on this account, paste the app password, "
            "Save, then Re-scan.",
        ],
        "Most providers block your normal password for mail apps and require an "
        "app password instead.")


def get_setup_guide(email: str) -> Optional[dict]:
    domain = _domain_of(email)
    return _BY_DOMAIN.get(domain) or _generic(domain)
