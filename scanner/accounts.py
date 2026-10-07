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

            if "," in line or "|" in line:
                # Optional richer form: email,password[,mailbox]
                parts = re.split(r"\s*[,|]\s*", line, maxsplit=2)
                email = parts[0].strip()
                password = parts[1].strip() if len(parts) > 1 else ""
                mailbox = parts[2].strip() if len(parts) > 2 else None
            else:
                # Primary form: "email password" — the first whitespace splits
                # the email from the password; everything after it is the
                # password (kept verbatim, even if it contains spaces).
                bits = line.split(None, 1)
                email = bits[0].strip()
                password = bits[1] if len(bits) > 1 else ""
                mailbox = None

            if email:
                accounts.append(Account(email=email, password=password, mailbox=mailbox))

    # De-duplicate by email, keeping the first occurrence.
    seen = set()
    unique: List[Account] = []
    for a in accounts:
        key = a.email.lower()
        if key not in seen:
            seen.add(key)
            unique.append(a)
    return unique


def accounts_file_warning(path: str) -> str:
    return (f"Loaded credentials from {os.path.abspath(path)} — this file holds "
            f"your passwords. Keep it private and delete it when done.")
