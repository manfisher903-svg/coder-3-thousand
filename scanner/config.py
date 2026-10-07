"""Configuration loading and validation."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import List

import yaml


@dataclass
class EmailConfig:
    enabled: bool = True
    host: str = ""          # leave blank to auto-detect from the address
    port: int = 0           # 0 = auto (993 for SSL, 143 for STARTTLS)
    security: str = "ssl"   # ssl | starttls
    protocol: str = "imap"  # imap | pop3 (auto-detected; NetZero/Juno use pop3)
    username: str = ""
    password: str = ""
    mailbox: str = "INBOX"
    since_days: int = 730
    max_messages: int = 5000


@dataclass
class FilesConfig:
    enabled: bool = False
    paths: List[str] = field(default_factory=list)
    extensions: List[str] = field(
        default_factory=lambda: [".txt", ".md", ".csv", ".json", ".eml", ".log", ".rtf"]
    )
    max_file_mb: int = 10


@dataclass
class OutputConfig:
    directory: str = "./inventory"
    detail: str = "full"  # full | partial | redact
    save_attachments: bool = False
    encrypt_passphrase: str = ""


@dataclass
class Config:
    email: EmailConfig = field(default_factory=EmailConfig)
    files: FilesConfig = field(default_factory=FilesConfig)
    output: OutputConfig = field(default_factory=OutputConfig)

    @classmethod
    def load(cls, path: str) -> "Config":
        with open(path, "r", encoding="utf-8") as fh:
            raw = yaml.safe_load(fh) or {}

        email = EmailConfig(**(raw.get("email") or {}))
        files = FilesConfig(**(raw.get("files") or {}))
        output = OutputConfig(**(raw.get("output") or {}))

        # Environment variable always wins for the password so it can stay off disk.
        env_pw = os.environ.get("PIS_EMAIL_PASSWORD")
        if env_pw:
            email.password = env_pw

        if output.detail not in ("redact", "partial", "full"):
            raise ValueError(
                f"output.detail must be redact|partial|full, got {output.detail!r}"
            )
        return cls(email=email, files=files, output=output)

    def validate_for_scan(self) -> List[str]:
        """Return a list of human-readable problems, empty if good to go."""
        problems: List[str] = []
        if not self.email.enabled and not self.files.enabled:
            problems.append("Nothing to scan: enable email and/or files in the config.")
        if self.email.enabled:
            # host may be blank — it is auto-detected from the address at scan time.
            if not self.email.username:
                problems.append("email.username is required.")
            if not self.email.password:
                problems.append(
                    "No email password. Set PIS_EMAIL_PASSWORD or email.password "
                    "(use an app password, not your normal login)."
                )
        if self.files.enabled and not self.files.paths:
            problems.append("files.enabled is true but files.paths is empty.")
        return problems
