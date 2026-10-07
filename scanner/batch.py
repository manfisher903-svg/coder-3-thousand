"""Reusable multi-account scan, shared by the CLI and the app."""

from __future__ import annotations

import copy
import os
from typing import Callable, List, Optional

from .accounts import Account, load_accounts
from .config import Config, EmailConfig
from .report import Inventory, write_reports

ProgressFn = Optional[Callable[[str], None]]


def _emit(cb: ProgressFn, msg: str) -> None:
    if cb:
        cb(msg)


def scan_one(account: Account, base: Config, out_dir: str,
             progress: ProgressFn = None) -> dict:
    """Scan a single account into out_dir; return a summary dict."""
    from .classify import classify
    from .patterns import scan_sensitive
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
    try:
        src = EmailSource(email_cfg)
        detected = getattr(src, "detected", None)
        if detected is not None:
            _emit(progress, f"{account.email}: using {detected.host} "
                            f"({detected.security})")
        count = 0
        for rec in src.iter_messages():
            count += 1
            category, brand = classify(rec.sender_domain, rec.subject, rec.snippet)
            inv.add_service(brand, category, rec.sender_domain, rec.subject)

            findings = scan_sensitive(f"{rec.subject}\n{rec.body_text}")
            if findings:
                inv.add_findings(findings, f"{rec.sender_email} — {rec.subject[:60]!r}")

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
            if count % 250 == 0:
                _emit(progress, f"{account.email}: {count} messages…")
        inv.sources_scanned += count
        _emit(progress, f"{account.email}: {count} messages scanned")
    except Exception as exc:  # noqa: BLE001
        status = f"failed: {exc}"
        _emit(progress, f"{account.email}: {status}")

    write_reports(inv, out_dir)
    if base.output.encrypt_passphrase:
        try:
            from .crypto_store import encrypt_bundle
            encrypt_bundle([os.path.join(out_dir, "report.json"),
                            os.path.join(out_dir, "report.md")],
                           out_dir, base.output.encrypt_passphrase)
        except Exception:  # noqa: BLE001
            pass

    return {
        "email": account.email,
        "folder": account.safe_name(),
        "services": len(inv.services),
        "sensitive": len(inv.sensitive),
        "status": status,
    }


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
        _emit(progress, f"[{i}/{len(accounts)}] {acct.email}")
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
