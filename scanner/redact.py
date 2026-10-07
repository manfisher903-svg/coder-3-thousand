"""Redaction of detected sensitive values.

The detail level controls how much of a value is preserved in the report:
  - redact : show only the type and length, e.g. "•••• (16 digits)"
  - partial: show last 4 characters, e.g. "•••• 1234"
  - full   : show the whole value  (still NEVER for seed phrases / keys)

Seed phrases and raw private keys are never written out at any level.
"""

from __future__ import annotations

from .patterns import Finding

_NEVER_REVEAL = {"seed_phrase", "private_key", "crypto_private_key"}


def render_value(finding: Finding, detail: str) -> str:
    kind = finding.kind
    raw = finding.raw

    if kind in _NEVER_REVEAL or raw is None:
        return "[detected — value withheld by design]"

    cleaned = raw.strip()

    if detail == "full":
        return cleaned

    if detail == "partial":
        tail = cleaned[-4:] if len(cleaned) > 4 else cleaned
        return f"•••• {tail}"

    # redact (default)
    digits = sum(c.isdigit() for c in cleaned)
    if digits >= len(cleaned) - 2:
        return f"•••• ({digits} digits)"
    return f"•••• ({len(cleaned)} chars)"
