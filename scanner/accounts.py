"""Load a list of email accounts to scan in batch.

The accounts file holds YOUR OWN accounts. It is sensitive (it contains
passwords), so it is git-ignored by default and should be deleted or kept in
an encrypted place when you're done.

Three formats are accepted, pick whichever is easiest:

1. YAML:
     accounts:
       - email: you@gmail.com
         password: "app-password"
       - email: you@yahoo.com
         password: "app-password"
         mailbox: "INBOX"     # optional
         host: ""             # optional manual IMAP host override

2. Plain lines — the simplest form: the email, a space, then the password.
   Everything after the first space is the password:
     frank439@gmail.com 979password
     you@yahoo.com my app password with spaces

   You may instead use commas or pipes, which also allow an optional third
   mailbox field:
     you@gmail.com,app-password
     you@outlook.com | app-password | INBOX

Lines starting with # are comments.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import List, Optional

import yaml


@dataclass
class Account:
    email: str
    password: str
    mailbox: Optional[str] = None
    host: Optional[str] = None

    def safe_name(self) -> str:
        """A filesystem-safe folder name derived from the address."""
        return re.sub(r"[^A-Za-z0-9._-]", "_", self.email) or "account"


def _looks_like_yaml(text: str) -> bool:
    stripped = text.lstrip()
    return stripped.startswith("accounts:") or stripped.startswith("- ")


def load_accounts(path: str) -> List[Account]:
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()

    accounts: List[Account] = []

    if _looks_like_yaml(text):
        data = yaml.safe_load(text) or {}
        rows = data.get("accounts") if isinstance(data, dict) else data
        for row in rows or []:
            if not isinstance(row, dict) or not row.get("email"):
                continue
            accounts.append(Account(
                email=str(row["email"]).strip(),
                password=str(row.get("password", "")),
                mailbox=(str(row["mailbox"]) if row.get("mailbox") else None),
                host=(str(row["host"]) if row.get("host") else None),
            ))
    else:
        for raw in text.splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue

            host = None
            if "," in line or "|" in line:
                # Richer form: email | password [| mailbox [| host]]
                parts = re.split(r"\s*[,|]\s*", line, maxsplit=3)
                email = parts[0].strip()
                password = parts[1].strip() if len(parts) > 1 else ""
                mailbox = parts[2].strip() if len(parts) > 2 and parts[2].strip() else None
                host = parts[3].strip() if len(parts) > 3 and parts[3].strip() else None
            else:
                # Primary form: "email password" — the first whitespace splits
                # the email from the password; everything after it is the
                # password (kept verbatim, even if it contains spaces).
                bits = line.split(None, 1)
                email = bits[0].strip()
                password = bits[1] if len(bits) > 1 else ""
                mailbox = None

            if email:
                accounts.append(Account(email=email, password=password,
                                        mailbox=mailbox, host=host))

    # De-duplicate by email, keeping the first occurrence.
    seen = set()
    unique: List[Account] = []
    for a in accounts:
        key = a.email.lower()
        if key not in seen:
            seen.add(key)
            unique.append(a)
    return unique


def save_accounts(path: str, accounts: List[Account]) -> None:
    """Rewrite the accounts file in the simple 'email password[ mailbox]' form."""
    lines = ["# Your email accounts — one per line: email<space>password",
             "# Managed by the app; edits here are fine too.", ""]
    for a in accounts:
        if a.host or a.mailbox:
            # Fully pipe-delimited so mailbox/host round-trip cleanly:
            #   email | password | mailbox | host
            line = f"{a.email} | {a.password} | {a.mailbox or ''} | {a.host or ''}"
        else:
            line = f"{a.email} {a.password}"
        lines.append(line)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def add_or_update(path: str, email: str, password: str,
                  mailbox: Optional[str] = None, host: Optional[str] = None,
                  original_email: Optional[str] = None) -> None:
    """Add a new account, or update one in place (matched by original_email).

    `host` is the chosen provider's mail host ("" / None = auto-detect). It is
    only changed when explicitly provided, so edits that omit it keep it.
    """
    accounts = load_accounts(path) if os.path.exists(path) else []
    key = (original_email or email).lower()
    found = False
    for a in accounts:
        if a.email.lower() == key:
            a.email, a.password = email, password
            if mailbox is not None:
                a.mailbox = mailbox or None
            if host is not None:
                a.host = host or None
            found = True
            break
    if not found:
        accounts.append(Account(email=email, password=password,
                                mailbox=mailbox, host=host or None))
    save_accounts(path, accounts)


def delete_account(path: str, email: str) -> bool:
    """Remove an account by email. Returns True if something was removed."""
    if not os.path.exists(path):
        return False
    accounts = load_accounts(path)
    kept = [a for a in accounts if a.email.lower() != email.lower()]
    if len(kept) == len(accounts):
        return False
    save_accounts(path, kept)
    return True


def accounts_file_warning(path: str) -> str:
    return (f"Loaded credentials from {os.path.abspath(path)} — this file holds "
            f"your passwords. Keep it private and delete it when done.")
