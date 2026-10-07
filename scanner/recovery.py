"""Official account-recovery links per provider.

This is the safe, effective way to get back into your own account: the
provider verifies it's you (backup email, phone, security questions) and lets
you set a new password. It works even when you've forgotten the password
entirely, and — unlike guessing — it won't lock the account or get your IP
blocked.
"""

from __future__ import annotations

from typing import Optional

from .providers import _domain_of  # reuse the address -> domain helper

# domain -> official "forgot password" / account recovery URL
_RECOVERY = {
    "gmail.com": "https://accounts.google.com/signin/recovery",
    "googlemail.com": "https://accounts.google.com/signin/recovery",
    "yahoo.com": "https://login.yahoo.com/account/challenge/password",
    "ymail.com": "https://login.yahoo.com/account/challenge/password",
    "outlook.com": "https://account.live.com/password/reset",
    "hotmail.com": "https://account.live.com/password/reset",
    "live.com": "https://account.live.com/password/reset",
    "msn.com": "https://account.live.com/password/reset",
    "icloud.com": "https://iforgot.apple.com/",
    "me.com": "https://iforgot.apple.com/",
    "mac.com": "https://iforgot.apple.com/",
    "aol.com": "https://login.aol.com/account/challenge/password",
    "verizon.net": "https://login.aol.com/account/challenge/password",
    "proton.me": "https://account.proton.me/reset-password",
    "protonmail.com": "https://account.proton.me/reset-password",
    "gmx.com": "https://www.gmx.com/password-reset/",
    "zoho.com": "https://accounts.zoho.com/password",
    "fastmail.com": "https://www.fastmail.com/login/",
    "yandex.com": "https://passport.yandex.com/auth/restore/login",
    "comcast.net": "https://idm.xfinity.com/myaccount/reset",
    "att.net": "https://www.att.com/acctmgmt/forgotpassword",
    "netzero.net": "https://www.netzero.net/my-account/",
    "juno.com": "https://www.juno.com/my-account/",
    "my.com": "https://account.my.com/password/recovery/",
    "mail.ru": "https://account.mail.ru/recovery",
}


def recovery_url(address: str) -> Optional[str]:
    return _RECOVERY.get(_domain_of(address))


def recovery_steps(address: str) -> str:
    url = recovery_url(address)
    where = url or "your email provider's sign-in page (look for 'Forgot password')"
    return (
        f"To get back into {address}:\n"
        f"  1. Open {where}\n"
        f"  2. Enter your email address and choose 'Forgot password'.\n"
        f"  3. Verify it's you via your recovery phone or backup email.\n"
        f"  4. Set a new password and save it in a password manager.\n"
        f"If you no longer have the recovery phone/email, use the provider's "
        f"account-recovery form and answer the identity questions."
    )
