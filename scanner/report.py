"""Aggregate findings into an inventory and render reports."""

from __future__ import annotations

import json
import os
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, List, Optional

from .patterns import Finding
from .redact import render_value


@dataclass
class ServiceEntry:
    brand: str
    category: str
    domains: set = field(default_factory=set)
    sample_subjects: List[str] = field(default_factory=list)
    message_count: int = 0
    purposes: set = field(default_factory=set)
    last_seen: Optional[str] = None   # ISO date of the most recent message

    def observe(self, domain: str, subject: str, date=None) -> None:
        from .classify import purpose as _purpose
        self.message_count += 1
        if domain:
            self.domains.add(domain)
        if subject and len(self.sample_subjects) < 3 and subject not in self.sample_subjects:
            self.sample_subjects.append(subject)
        p = _purpose(subject)
        if p:
            self.purposes.add(p)
        if date is not None:
            try:
                iso = date.date().isoformat()
                if self.last_seen is None or iso > self.last_seen:
                    self.last_seen = iso
            except Exception:
                pass


@dataclass
class SensitiveHit:
    kind: str
    severity: str
    location: str
    rendered: str
    advice: str
    context: str = ""
    lang: str = ""          # non-English language name, else ""
    context_en: str = ""    # offline English translation of context, if available


class Inventory:
    def __init__(self, detail: str, account: str = ""):
        self.detail = detail
        self.account = account
        self.error = ""        # set when the scan failed (e.g. login error)
        self.services: Dict[str, ServiceEntry] = {}
        self.sensitive: List[SensitiveHit] = []
        self.attachments: List[str] = []
        self.attachment_passwords: List[dict] = []  # {file,encrypted,password,from,subject}
        self.sources_scanned: int = 0
        self.suspicious: List[dict] = []          # flagged phishing/scam emails
        self.name_counts: Dict[str, int] = {}     # candidate owner names
        self.protocol: str = "imap"               # imap | pop3 (how it connected)

    def add_service(self, brand: Optional[str], category: str, domain: str,
                    subject: str, date=None):
        key = (brand or domain or category).lower()
        if key not in self.services:
            self.services[key] = ServiceEntry(brand=brand or domain or "(unknown)",
                                              category=category)
        self.services[key].observe(domain, subject, date)

    def add_findings(self, findings: List[Finding], location: str):
        from .translate import detect_language, translate_to_english
        for f in findings:
            # Full context only at 'full' detail (it contains the value).
            ctx = f.context if self.detail == "full" else ""
            lang_label = ""
            ctx_en = ""
            if ctx:
                code, name = detect_language(ctx)
                if code and not code.startswith("en"):
                    lang_label = name
                    tr = translate_to_english(ctx, code)  # offline; None if N/A
                    if tr:
                        ctx_en = tr
            self.sensitive.append(
                SensitiveHit(
                    kind=f.kind,
                    severity=f.severity,
                    location=location,
                    rendered=render_value(f, self.detail),
                    advice=f.advice,
                    context=ctx,
                    lang=lang_label,
                    context_en=ctx_en,
                )
            )

    # --- serialization ----------------------------------------------------

    def to_dict(self) -> dict:
        from datetime import date as _date, timedelta
        recent_cutoff = (_date.today() - timedelta(days=90)).isoformat()
        by_category: Dict[str, list] = defaultdict(list)
        for svc in self.services.values():
            by_category[svc.category].append({
                "brand": svc.brand,
                "domains": sorted(svc.domains),
                "message_count": svc.message_count,
                "sample_subjects": svc.sample_subjects,
                "purposes": sorted(svc.purposes),
                "last_seen": svc.last_seen,
                "recent": bool(svc.last_seen and svc.last_seen >= recent_cutoff),
            })
        for cat in by_category:
            by_category[cat].sort(key=lambda s: -s["message_count"])

        from .patterns import IDENTITY_KINDS

        sev_order = {"high": 0, "medium": 1, "low": 2}
        sensitive = sorted(
            ({
                "kind": h.kind, "severity": h.severity, "location": h.location,
                "value": h.rendered, "advice": h.advice, "context": h.context,
                "lang": h.lang, "context_en": h.context_en,
            } for h in self.sensitive if h.kind not in IDENTITY_KINDS),
            key=lambda h: sev_order.get(h["severity"], 9),
        )

        # Personal info (contact/identity) grouped by kind, de-duplicated by
        # value, with how many times each appeared and where it was first seen.
        pi: Dict[str, Dict[str, dict]] = {}
        for h in self.sensitive:
            if h.kind not in IDENTITY_KINDS:
                continue
            bucket = pi.setdefault(h.kind, {})
            key = h.rendered.strip().lower()
            if key in bucket:
                bucket[key]["count"] += 1
            else:
                bucket[key] = {"value": h.rendered, "count": 1,
                               "location": h.location}
        personal_info = {
            kind: sorted(vals.values(), key=lambda v: -v["count"])
            for kind, vals in pi.items()
        }
        personal_info_count = sum(len(v) for v in personal_info.values())

        # Best-guess "real" details: the most-repeated value wins.
        def top(kind):
            items = personal_info.get(kind) or []
            return items[0] if items else None
        best_name = None
        if self.name_counts:
            n, c = max(self.name_counts.items(), key=lambda kv: kv[1])
            best_name = {"value": n, "count": c}
        best_guess = {
            "name": best_name,
            "email": top("email_address"),
            "phone": top("phone"),
            "address": top("mailing_address"),
            "dob": top("date_of_birth"),
        }

        suspicious = sorted(self.suspicious,
                            key=lambda s: -s.get("score", 0))

        return {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "account": self.account,
            "scan_error": self.error,
            "protocol": self.protocol,
            "detail_level": self.detail,
            "sources_scanned": self.sources_scanned,
            "services_by_category": dict(by_category),
            "service_count": len(self.services),
            "sensitive_findings": sensitive,
            "sensitive_count": len(sensitive),
            "personal_info": personal_info,
            "personal_info_count": personal_info_count,
            "best_guess": best_guess,
            "suspicious_emails": suspicious,
            "suspicious_count": len(suspicious),
            "attachments_saved": self.attachments,
            "attachment_passwords": self.attachment_passwords,
        }

    def to_markdown(self) -> str:
        d = self.to_dict()
        lines: List[str] = []
        lines.append("# Personal Information Inventory")
        lines.append("")
        lines.append(f"_Generated {d['generated_at']} · detail level: "
                     f"`{d['detail_level']}` · {d['sources_scanned']} items scanned_")
        lines.append("")
        note = ("Values are shown in full — this file contains real secrets, so "
                "keep it somewhere safe (or encrypt it) and delete it when done."
                if d["detail_level"] == "full"
                else "Sensitive values are partially masked at this detail level.")
        lines.append(f"> This is a map of where your personal information lives. "
                     f"{note}")
        lines.append("")

        lines.append("## Services & accounts")
        lines.append(f"\nFound **{d['service_count']}** distinct services across "
                     f"{len(d['services_by_category'])} categories.\n")
        for category in sorted(d["services_by_category"]):
            entries = d["services_by_category"][category]
            lines.append(f"### {category.title()}  ({len(entries)})")
            for e in entries:
                dom = f" · {', '.join(e['domains'])}" if e["domains"] else ""
                lines.append(f"- **{e['brand']}**{dom} — {e['message_count']} message(s)")
                for subj in e["sample_subjects"]:
                    lines.append(f"    - _{subj}_")
            lines.append("")

        lines.append("## Sensitive findings")
        if not d["sensitive_findings"]:
            lines.append("\nNo sensitive values detected. 🎉\n")
        else:
            lines.append(f"\n**{d['sensitive_count']}** item(s) flagged. "
                         "Address the high-severity ones first.\n")
            lines.append("| Severity | Type | Where | Value | Recommended action |")
            lines.append("|---|---|---|---|---|")
            for h in d["sensitive_findings"]:
                loc = h["location"].replace("|", "\\|")
                advice = h["advice"].replace("|", "\\|")
                lines.append(
                    f"| {h['severity'].upper()} | {h['kind']} | {loc} | "
                    f"`{h['value']}` | {advice} |"
                )
            lines.append("")

        if d["attachments_saved"]:
            lines.append("## Attachments saved")
            for a in d["attachments_saved"]:
                lines.append(f"- {a}")
            lines.append("")

        lines.append("---")
        lines.append("### Next steps")
        lines.append("1. Move any passwords/cards into a password manager; remove them from email.")
        lines.append("2. If a **seed phrase** was flagged, migrate the funds and retire that phrase.")
        lines.append("3. Enable 2FA on banking, email, and crypto accounts.")
        lines.append("4. Delete this inventory, or keep it only in an encrypted vault.")
        return "\n".join(lines)


def write_reports(inv: Inventory, out_dir: str) -> List[str]:
    os.makedirs(out_dir, exist_ok=True)
    try:
        os.chmod(out_dir, 0o700)
    except OSError:
        pass

    written: List[str] = []
    json_path = os.path.join(out_dir, "report.json")
    md_path = os.path.join(out_dir, "report.md")

    with open(json_path, "w", encoding="utf-8") as fh:
        json.dump(inv.to_dict(), fh, indent=2)
    _lock(json_path)
    written.append(json_path)

    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write(inv.to_markdown())
    _lock(md_path)
    written.append(md_path)
    return written


def _lock(path: str) -> None:
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
