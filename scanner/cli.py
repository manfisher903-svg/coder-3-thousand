"""Command-line interface for the Personal Info Scanner."""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import List

from .classify import classify
from .config import Config
from .patterns import SENSITIVE_DETECTORS, scan_sensitive
from .report import Inventory, write_reports


def _print_banner() -> None:
    print("Personal Info Scanner — local, read-only. Nothing leaves this machine.\n",
          file=sys.stderr)


def cmd_providers(args) -> int:
    from .providers import known_providers, resolve_imap

    if args.email:
        try:
            s = resolve_imap(args.email)
            print(f"{args.email}  ->  {s.host}:{s.port} ({s.security}) [{s.source}]")
            return 0
        except Exception as exc:  # noqa: BLE001
            print(f"Could not resolve '{args.email}': {exc}", file=sys.stderr)
            return 1

    print("Built-in providers (any other domain is auto-detected online):\n")
    seen = {}
    for domain, s in sorted(known_providers().items()):
        seen.setdefault((s.host, s.port, s.security), []).append(domain)
    for (host, port, sec), domains in sorted(seen.items()):
        print(f"  {host}:{port} ({sec})")
        print(f"      {', '.join(sorted(domains))}")
    print("\nFor any address not listed, settings are detected automatically "
          "from the address when you scan (pass --email ADDR here to preview).")
    return 0


def cmd_detectors(_args) -> int:
    from .classify import CATEGORY_KEYWORDS
    print("Service categories:")
    for cat in sorted(CATEGORY_KEYWORDS):
        print(f"  - {cat}")
    print("\nSensitive detectors:")
    for name, _fn in SENSITIVE_DETECTORS:
        print(f"  - {name}")
    print("\nAt detail level 'full' (the default) every detected value is shown "
          "exactly as found, including passwords, keys, and seed phrases.")
    return 0


def _scan_email(cfg: Config, inv: Inventory, save_attachments: bool, out_dir: str) -> None:
    from .sources.email_imap import EmailSource

    src = EmailSource(cfg.email)
    detected = getattr(src, "detected", None)
    if detected is not None:
        print(f"  using {detected.host}:{detected.port} ({detected.security}, "
              f"via {detected.source})", file=sys.stderr)
    count = 0
    for rec in src.iter_messages():
        count += 1
        category, brand = classify(rec.sender_domain, rec.subject, rec.snippet)
        inv.add_service(brand, category, rec.sender_domain, rec.subject)

        text = f"{rec.subject}\n{rec.body_text}"
        findings = scan_sensitive(text)
        if findings:
            loc = f"email: {rec.sender_email} — {rec.subject[:60]!r}"
            inv.add_findings(findings, loc)

        if save_attachments and rec.attachments and (findings or category != "other"):
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
                    inv.attachments.append(f"{att.filename} (from {rec.sender_email})")

        if count % 250 == 0:
            print(f"  …scanned {count} messages", file=sys.stderr)
    inv.sources_scanned += count
    print(f"  email: {count} messages scanned", file=sys.stderr)


def _scan_files(cfg: Config, inv: Inventory) -> None:
    from .sources.files import FileSource

    src = FileSource(cfg.files)
    count = 0
    for rec in src.iter_files():
        count += 1
        findings = scan_sensitive(rec.text)
        if findings:
            inv.add_findings(findings, f"file: {rec.path}")
    inv.sources_scanned += count
    print(f"  files: {count} files scanned", file=sys.stderr)


def cmd_scan(args) -> int:
    _print_banner()
    cfg = Config.load(args.config)

    # CLI overrides.
    if args.files:
        cfg.files.enabled = True
        cfg.files.paths = list(args.files)
    if args.output:
        cfg.output.directory = args.output
    if args.detail:
        cfg.output.detail = args.detail
    if args.save_attachments:
        cfg.output.save_attachments = True

    problems = cfg.validate_for_scan()
    if problems:
        print("Cannot start scan:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 2

    inv = Inventory(detail=cfg.output.detail)

    if cfg.email.enabled:
        print("Scanning email (read-only)…", file=sys.stderr)
        try:
            _scan_email(cfg, inv, cfg.output.save_attachments, cfg.output.directory)
        except Exception as exc:  # noqa: BLE001 - surface a friendly message
            print(f"  email scan failed: {exc}", file=sys.stderr)
            print("  (check host/username/app-password and IMAP access)", file=sys.stderr)

    if cfg.files.enabled:
        print("Scanning local files…", file=sys.stderr)
        _scan_files(cfg, inv)

    written = write_reports(inv, cfg.output.directory)

    if cfg.output.encrypt_passphrase:
        try:
            from .crypto_store import encrypt_bundle
            enc = encrypt_bundle(written, cfg.output.directory,
                                 cfg.output.encrypt_passphrase)
            print(f"\nEncrypted bundle written: {enc}", file=sys.stderr)
        except Exception as exc:  # noqa: BLE001
            print(f"  encryption skipped: {exc}", file=sys.stderr)

    print("\nDone. Reports written:", file=sys.stderr)
    for w in written:
        print(f"  - {w}", file=sys.stderr)
    print(f"\n{len(inv.services)} services, {len(inv.sensitive)} sensitive "
          f"findings. Open {os.path.join(cfg.output.directory, 'report.md')}.",
          file=sys.stderr)
    return 0


def cmd_scan_all(args) -> int:
    """Scan many accounts from a credentials file; one report folder each."""
    from .accounts import accounts_file_warning, load_accounts
    from .batch import run_batch

    _print_banner()

    # A base config supplies defaults (detail level, since_days, encryption…).
    if args.config and os.path.exists(args.config):
        base = Config.load(args.config)
    else:
        base = Config()
    if args.output:
        base.output.directory = args.output
    if args.detail:
        base.output.detail = args.detail
    if args.save_attachments:
        base.output.save_attachments = True

    try:
        accounts = load_accounts(args.accounts)
    except FileNotFoundError:
        print(f"Accounts file not found: {args.accounts}", file=sys.stderr)
        return 2
    if not accounts:
        print(f"No accounts found in {args.accounts}.", file=sys.stderr)
        return 2

    print(accounts_file_warning(args.accounts), file=sys.stderr)
    print(f"Scanning {len(accounts)} account(s)…\n", file=sys.stderr)

    summaries = run_batch(args.accounts, base, base.output.directory,
                          progress=lambda m: print(f"  {m}", file=sys.stderr))

    ok = sum(1 for s in summaries if s["status"] == "ok")
    print(f"\nDone. {ok}/{len(summaries)} account(s) scanned cleanly.", file=sys.stderr)
    print(f"Per-account reports under {base.output.directory}/<address>/report.md",
          file=sys.stderr)
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="personal-info-scanner",
        description="Local-only inventory of your personal info in email and files.",
    )
    sub = p.add_subparsers(dest="command", required=True)

    scan = sub.add_parser("scan", help="Scan configured sources and write a report.")
    scan.add_argument("--config", default="config.yaml", help="Path to config.yaml")
    scan.add_argument("--files", nargs="*", help="Local paths to scan (enables file scan)")
    scan.add_argument("--output", help="Output directory for reports")
    scan.add_argument("--detail", choices=["redact", "partial", "full"],
                      help="How much of sensitive values to keep")
    scan.add_argument("--save-attachments", action="store_true",
                      help="Save attachments from personal-looking messages")
    scan.set_defaults(func=cmd_scan)

    scan_all = sub.add_parser(
        "scan-all",
        help="Scan many accounts from a credentials file; one report each.")
    scan_all.add_argument("--accounts", default="accounts.yaml",
                          help="Path to the accounts file (email + password per account)")
    scan_all.add_argument("--config", default="config.yaml",
                          help="Optional base config for defaults (detail, since_days…)")
    scan_all.add_argument("--output", help="Output directory root for all reports")
    scan_all.add_argument("--detail", choices=["redact", "partial", "full"],
                          help="How much of sensitive values to keep")
    scan_all.add_argument("--save-attachments", action="store_true",
                          help="Save attachments from personal-looking messages")
    scan_all.set_defaults(func=cmd_scan_all)

    det = sub.add_parser("detectors", help="List categories and detectors.")
    det.set_defaults(func=cmd_detectors)

    prov = sub.add_parser("providers",
                          help="List built-in providers or preview detection for an address.")
    prov.add_argument("--email", help="Preview the IMAP settings detected for this address")
    prov.set_defaults(func=cmd_providers)

    return p


def main(argv: List[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
