"""Read-only IMAP email source.

Connects to the user's own mail server over TLS, fetches messages, and yields
a normalized record per message. We only ever read (SELECT in readonly mode);
nothing is marked, moved, or deleted.
"""

from __future__ import annotations

import email
import imaplib
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from email.header import decode_header, make_header
from email.utils import parseaddr, parsedate_to_datetime
from typing import Iterator, List, Optional, Tuple

from ..config import EmailConfig
from ..providers import resolve_imap


@dataclass
class Attachment:
    filename: str
    content_type: str
    data: bytes


@dataclass
class MessageRecord:
    uid: str
    date: Optional[datetime]
    sender_name: str
    sender_email: str
    sender_domain: str
    subject: str
    body_text: str
    attachments: List[Attachment] = field(default_factory=list)

    @property
    def attachment_names(self) -> List[str]:
        return [a.filename for a in self.attachments]

    @property
    def snippet(self) -> str:
        return " ".join(self.body_text.split())[:400]


# Don't hold more than this per attachment in memory (bytes).
_MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024


def _decode(value: Optional[str]) -> str:
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def _extract_body(msg: email.message.Message) -> Tuple[str, List[Attachment]]:
    text_parts: List[str] = []
    attachments: List[Attachment] = []

    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            disp = str(part.get("Content-Disposition") or "")
            filename = part.get_filename()
            if filename:
                try:
                    data = part.get_payload(decode=True) or b""
                except Exception:
                    data = b""
                if len(data) <= _MAX_ATTACHMENT_BYTES:
                    attachments.append(Attachment(_decode(filename), ctype, data))
                continue
            if ctype == "text/plain" and "attachment" not in disp:
                text_parts.append(_payload_to_text(part))
            elif ctype == "text/html" and "attachment" not in disp and not text_parts:
                text_parts.append(_strip_html(_payload_to_text(part)))
    else:
        if msg.get_content_type() == "text/html":
            text_parts.append(_strip_html(_payload_to_text(msg)))
        else:
            text_parts.append(_payload_to_text(msg))

    return "\n".join(t for t in text_parts if t), attachments


def _payload_to_text(part: email.message.Message) -> str:
    try:
        payload = part.get_payload(decode=True)
        if payload is None:
            return ""
        charset = part.get_content_charset() or "utf-8"
        return payload.decode(charset, errors="replace")
    except Exception:
        return ""


def _strip_html(html: str) -> str:
    import re
    text = re.sub(r"(?is)<(script|style).*?>.*?</\1>", " ", html)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = (text.replace("&nbsp;", " ").replace("&amp;", "&")
                .replace("&lt;", "<").replace("&gt;", ">").replace("&#39;", "'"))
    return text


class EmailSource:
    def __init__(self, cfg: EmailConfig):
        self.cfg = cfg
        self.total = None  # set once the mailbox is searched
        self._resolve_server()

    def _resolve_server(self) -> None:
        """Fill in host/port/security from the address when not set explicitly."""
        if self.cfg.host:
            if not self.cfg.port:
                self.cfg.port = 143 if self.cfg.security == "starttls" else 993
            return
        server = resolve_imap(self.cfg.username)
        self.cfg.host = server.host
        self.cfg.port = server.port
        self.cfg.security = server.security
        self.detected = server  # for the CLI to report what it found

    def _connect(self, timeout: float = 30.0) -> imaplib.IMAP4:
        # A timeout keeps an unreachable server from hanging forever — important
        # in batch mode so one bad account can't stall the whole run.
        if self.cfg.security == "starttls":
            conn = imaplib.IMAP4(self.cfg.host, self.cfg.port, timeout=timeout)
            conn.starttls()
            return conn
        return imaplib.IMAP4_SSL(self.cfg.host, self.cfg.port, timeout=timeout)

    def _search_criteria(self) -> str:
        if self.cfg.since_days and self.cfg.since_days > 0:
            since = datetime.now(timezone.utc) - timedelta(days=self.cfg.since_days)
            return f'(SINCE "{since.strftime("%d-%b-%Y")}")'
        return "ALL"

    def _is_gmail(self) -> bool:
        return "gmail" in (self.cfg.host or "").lower() or \
               "google" in (self.cfg.host or "").lower()

    def _list_mailboxes(self, conn) -> List[str]:
        """Return the folders to scan. 'ALL' means sweep every folder."""
        want = (self.cfg.mailbox or "INBOX").strip()
        if want and want.upper() != "ALL":
            return [want]

        typ, data = conn.list()
        names: List[str] = []
        if typ == "OK":
            for line in data:
                if not line:
                    continue
                text = line.decode(errors="replace") if isinstance(line, bytes) else str(line)
                if "\\Noselect" in text:
                    continue  # container, not a real folder
                # The mailbox name is the last quoted string, or last token.
                if '"' in text:
                    name = text.rsplit('"', 2)[-2]
                else:
                    name = text.split()[-1]
                if name:
                    names.append(name)

        if self._is_gmail():
            # Gmail duplicates every message across labels; "All Mail" already
            # holds Inbox + Sent + Archived, so scan it plus Spam and Trash.
            preferred = [n for n in names
                         if n.endswith("All Mail") or n.endswith("Spam")
                         or n.endswith("Trash")]
            return preferred or ["[Gmail]/All Mail"]

        return names or ["INBOX"]

    def iter_messages(self) -> Iterator[MessageRecord]:
        conn = self._connect()
        try:
            conn.login(self.cfg.username, self.cfg.password)
            mailboxes = self._list_mailboxes(conn)

            # First pass: search every folder so we know the true total (ETA).
            plan = []  # (mailbox, [ids])
            for mbox in mailboxes:
                try:
                    typ, _ = conn.select(f'"{mbox}"', readonly=True)
                    if typ != "OK":
                        continue
                    typ, data = conn.search(None, self._search_criteria())
                    if typ != "OK" or not data or data[0] is None:
                        continue
                    ids = data[0].split()
                    if ids:
                        plan.append((mbox, ids))
                except Exception:
                    continue

            all_total = sum(len(ids) for _m, ids in plan)
            if self.cfg.max_messages and all_total > self.cfg.max_messages:
                all_total = self.cfg.max_messages
            self.total = all_total

            emitted = 0
            for mbox, ids in plan:
                try:
                    typ, _ = conn.select(f'"{mbox}"', readonly=True)
                    if typ != "OK":
                        continue
                except Exception:
                    continue
                for msg_id in reversed(ids):  # newest first within each folder
                    if self.cfg.max_messages and emitted >= self.cfg.max_messages:
                        return
                    typ, msg_data = conn.fetch(msg_id, "(RFC822)")
                    if typ != "OK" or not msg_data or not msg_data[0]:
                        continue
                    raw = msg_data[0][1]
                    msg = email.message_from_bytes(raw)

                    name, addr = parseaddr(msg.get("From", ""))
                    domain = addr.split("@")[-1].lower() if "@" in addr else ""
                    body, attachments = _extract_body(msg)

                    date = None
                    try:
                        date = parsedate_to_datetime(msg.get("Date"))
                    except Exception:
                        pass

                    emitted += 1
                    yield MessageRecord(
                        uid=f"{mbox}:{msg_id.decode() if isinstance(msg_id, bytes) else msg_id}",
                        date=date,
                        sender_name=_decode(name),
                        sender_email=addr.lower(),
                        sender_domain=domain,
                        subject=_decode(msg.get("Subject")),
                        body_text=body,
                        attachments=attachments,
                    )
        finally:
            try:
                conn.close()
            except Exception:
                pass
            try:
                conn.logout()
            except Exception:
                pass
