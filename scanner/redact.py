"""Rendering of detected sensitive values.

The detail level controls how much of a value is shown in the report:
  - full   : show the whole value, exactly as found (default)
  - partial: show last 4 characters, e.g. "•••• 1234"
  - redact : show only the type and length, e.g. "•••• (16 digits)"

`full` shows everything, including passwords, keys, and crypto seed phrases.
This is your own data on your own machine; the tool does not hide it from you.
Just remember the report file then contains real secrets — keep it somewhere
safe (or use the encrypt_passphrase option), and delete it when you're done.
"""

from __future__ import annotations

from .patterns import Finding


def render_value(finding: Finding, detail: str) -> str:
    raw = finding.raw
    if raw is None:
        return "[detected — no value captured]"

    cleaned = raw.strip()

    if detail == "full":
        return cleaned

    if detail == "partial":
        tail = cleaned[-4:] if len(cleaned) > 4 else cleaned
        return f"•••• {tail}"

    # redact
    digits = sum(c.isdigit() for c in cleaned)
    if digits >= len(cleaned) - 2:
        return f"•••• ({digits} digits)"
    return f"•••• ({len(cleaned)} chars)"
