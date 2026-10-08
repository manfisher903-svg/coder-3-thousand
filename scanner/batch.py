"""Reusable multi-account scan, shared by the CLI and the app."""

from __future__ import annotations

import copy
import os
from typing import Callable, List, Optional

from .accounts import Account, load_accounts
from .config import Config, EmailConfig
from .report import Inventory, write_reports

# A progress callback receives structured event dicts, e.g.
#   {"event":"start","email":..}
#   {"event":"progress","email":..,"done":k,"total":T}
#   {"event":"done","email":..,"status":..,"services":..,"findings":..}
ProgressFn = Optional[Callable[[dict], None]]


def _friendly_error(raw: str, email: str) -> str:
    """Translate a raw IMAP/login error into plain, actionable advice."""
    low = raw.lower()
    if any(k in low for k in ("authentication", "auth", "login", "credentials",
                              "invalid", "username", "password", "web login")):
        return (f"Login was rejected. For {email} you almost certainly need an "
                f"APP PASSWORD (not your normal password), and IMAP must be "
                f"turned on in your email settings. Raw error: {raw}")
    if any(k in low for k in ("11001", "getaddrinfo", "gaierror",
                              "no such host", "name or service not known",
                              "nodename nor servname", "resolve")):
        return (f"Your computer couldn't find the mail server (a DNS lookup "
                f"failed — Windows calls this error 11001). Usually it's one of: "
                f"(1) you're not connected to the internet, (2) the email address "
                f"'{email}' is misspelled (check the part after the @), or (3) a "
                f"VPN/firewall is blocking it. Raw error: {raw}")
    if any(k in low for k in ("timed out", "timeout", "refused", "unreachable",
                              "connection")):
        return (f"Couldn't reach the mail server. Check your internet, or set "
                f"the IMAP host manually if this is an unusual provider. "
                f"Raw error: {raw}")
    if "select" in low or "mailbox" in low or "does not exist" in low:
        return (f"That mailbox/folder wasn't found. Try mailbox 'INBOX' or, for "
                f"Gmail, '[Gmail]/All Mail'. Raw error: {raw}")
    return raw


def _emit(cb: ProgressFn, **event) -> None:
    if cb:
        try:
            cb(event)
        except Exception:
            pass


def scan_one(account: Account, base: Config, out_dir: str,
             progress: ProgressFn = None) -> dict:
    """Scan a single account into out_dir; return a summary dict."""
    from .classify import classify
    from .patterns import IDENTITY_KINDS, scan_sensitive
    from .phishing import analyze_email
    from .sources.email_imap import EmailSource
    import re

    email_cfg = EmailConfig(
        enabled=True,
        host=account.host or "",
        username=account.email,
        password=account.password,
        mailbox=account.mailbox or base.email.mailbox,
        since_days=base.email.since_days,
        max_messages=base.email.max_messages,
    )
    inv = Inventory(detail=base.output.detail, account=account.email)
    status = "ok"
    _emit(progress, event="start", email=account.email)
    try:
        src = EmailSource(email_cfg)
        src.fetch_full = base.output.save_attachments  # full only when saving files
        inv.protocol = getattr(src.cfg, "protocol", "imap")
        count = 0
        for rec in src.iter_messages():
            count += 1
            category, brand = classify(rec.sender_domain, rec.subject, rec.snippet)
            inv.add_service(brand, category, rec.sender_domain, rec.subject, rec.date)

            # Analyze legitimacy FIRST, then build the profile only from
            # trustworthy mail so phishing/spoofed emails can't inject fake
            # names, addresses, etc. into "your real details".
            v = analyze_email(rec.sender_email, rec.sender_name, rec.subject,
                              rec.body_text, reply_to=rec.reply_to,
                              auth_results=rec.auth_results,
                              attachment_names=rec.attachment_names)
            is_legit = v.label == "legit"
            if not is_legit:
                inv.suspicious.append({
                    "from": rec.sender_email, "name": rec.sender_name,
                    "subject": rec.subject[:120], "verdict": v.label,
                    "score": v.score, "reasons": v.reasons,
                })

            loc = f"{rec.sender_email} — {rec.subject[:60]!r}"
            findings = scan_sensitive(f"{rec.subject}\n{rec.body_text}")
            # Security exposures (SSN, cards, keys…) count from ALL mail so you
            # see everything leaking. Identity details that build the profile
            # (name/email/phone/address/DOB) come only from legit emails.
            security = [f for f in findings if f.kind not in IDENTITY_KINDS]
            identity = [f for f in findings if f.kind in IDENTITY_KINDS]
            if security:
                inv.add_findings(security, loc)
            if is_legit:
                if identity:
                    inv.add_findings(identity, loc)
                for nm in rec.to_names:
                    nm = nm.strip()
                    if nm and "@" not in nm:
                        inv.name_counts[nm] = inv.name_counts.get(nm, 0) + 1

            if base.output.save_attachments and rec.attachments and (
                    findings or category != "other"):
                att_dir = os.path.join(out_dir, "attachments")
                os.makedirs(att_dir, exist_ok=True)
                for att in rec.attachments:
                    safe = re.sub(r"[^A-Za-z0-9._-]", "_", att.filename or "file")
                    dest = os.path.join(att_dir, f"{count:05d}_{safe}")
                    try:
                        with open(dest, "wb") as fh:
                            fh.write(att.data)
                        os.chmod(dest, 0o600)
                        inv.attachments.append(os.path.relpath(dest, out_dir))
                    except OSError:
                        pass
            # Report progress often enough for a smooth bar, cheaply.
            if count == 1 or count % 10 == 0:
                _emit(progress, event="progress", email=account.email,
                      done=count, total=src.total)
        inv.sources_scanned += count
        _emit(progress, event="progress", email=account.email,
              done=count, total=count)
    except Exception as exc:  # noqa: BLE001
        status = f"failed: {exc}"
        inv.error = _friendly_error(str(exc), account.email)

    write_reports(inv, out_dir)
    if base.output.encrypt_passphrase:
        try:
            from .crypto_store import encrypt_bundle
            encrypt_bundle([os.path.join(out_dir, "report.json"),
                            os.path.join(out_dir, "report.md")],
                           out_dir, base.output.encrypt_passphrase)
        except Exception:  # noqa: BLE001
            pass

    summary = {
        "email": account.email,
        "folder": account.safe_name(),
        "services": len(inv.services),
        "sensitive": len(inv.sensitive),
        "status": status,
    }
    _emit(progress, event="done", **summary)
    return summary


def run_batch(accounts_path: str, base: Config, out_root: str,
              progress: ProgressFn = None) -> List[dict]:
    accounts = load_accounts(accounts_path)
    os.makedirs(out_root, exist_ok=True)
    try:
        os.chmod(out_root, 0o700)
    except OSError:
        pass

    summaries: List[dict] = []
    for i, acct in enumerate(accounts, 1):
        _emit(progress, event="account", index=i, total_accounts=len(accounts),
              email=acct.email)
        acct_dir = os.path.join(out_root, acct.safe_name())
        acct_base = copy.deepcopy(base)
        summaries.append(scan_one(acct, acct_base, acct_dir, progress))

    write_index(out_root, summaries)
    return summaries


def write_index(out_root: str, summaries: List[dict]) -> None:
    lines = ["# Personal Info — all accounts", ""]
    lines.append(f"Scanned **{len(summaries)}** account(s).\n")
    lines.append("| Account | Services | Sensitive findings | Report | Status |")
    lines.append("|---|---|---|---|---|")
    for s in summaries:
        link = f"[{s['folder']}/report.md]({s['folder']}/report.md)"
        lines.append(f"| {s['email']} | {s['services']} | {s['sensitive']} | "
                     f"{link} | {s['status']} |")
    path = os.path.join(out_root, "index.md")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
