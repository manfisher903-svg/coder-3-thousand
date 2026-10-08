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
    reply_to: str = ""
    auth_results: str = ""
    to_names: List[str] = field(default_factory=list)  # display names on To/Cc

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
        self.cfg.protocol = getattr(server, "protocol", "imap")
        self.detected = server  # for the CLI to report what it found

    def _connect(self, timeout: float = 30.0) -> imaplib.IMAP4:
        # A timeout keeps an unreachable server from hanging forever — important
        # in batch mode so one bad account can't stall the whole run.
        if self.cfg.security == "starttls":
            conn = imaplib.IMAP4(self.cfg.host, self.cfg.port, timeout=timeout)
            conn.starttls()
            return conn
        return imaplib.IMAP4_SSL(self.cfg.host, self.cfg.port, timeout=timeout)

    def _record(self, msg, uid: str) -> MessageRecord:
        from email.utils import getaddresses

        name, addr = parseaddr(msg.get("From", ""))
        domain = addr.split("@")[-1].lower() if "@" in addr else ""
        body, attachments = _extract_body(msg)

        date = None
        try:
            date = parsedate_to_datetime(msg.get("Date"))
        except Exception:
            pass

        _rn, reply_to = parseaddr(msg.get("Reply-To", ""))
        auth = " ".join(msg.get_all("Authentication-Results") or [])

        # Display names addressed to the account owner (from To/Cc).
        to_names: List[str] = []
        me = (self.cfg.username or "").lower()
        for disp, a in getaddresses(msg.get_all("To", []) + msg.get_all("Cc", [])):
            if a and a.lower() == me and disp:
                to_names.append(_decode(disp))

        return MessageRecord(
            uid=uid, date=date, sender_name=_decode(name),
            sender_email=addr.lower(), sender_domain=domain,
            subject=_decode(msg.get("Subject")), body_text=body,
            attachments=attachments, reply_to=reply_to.lower(),
            auth_results=auth, to_names=to_names,
        )

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

        # Always make sure INBOX is attempted (some servers list it oddly).
        if not any(n.upper() == "INBOX" for n in names):
            names.insert(0, "INBOX")
        return names or ["INBOX"]

    @staticmethod
    def _select(conn, mbox):
        """SELECT a mailbox, tolerating servers picky about quoting."""
        for name in (f'"{mbox}"', mbox):
            try:
                typ, _ = conn.select(name, readonly=True)
                if typ == "OK":
                    return True
            except Exception:
                continue
        return False

    def iter_messages(self) -> Iterator[MessageRecord]:
        if getattr(self.cfg, "protocol", "imap") == "pop3":
            yield from self._iter_pop3()
            return
        yield from self._iter_imap()

    def _iter_pop3(self) -> Iterator[MessageRecord]:
        """Read messages over POP3 (used by providers without IMAP)."""
        import poplib

        if self.cfg.security == "starttls":
            m = poplib.POP3(self.cfg.host, self.cfg.port or 110, timeout=30)
            try:
                m.stls()
            except Exception:
                pass
        else:
            m = poplib.POP3_SSL(self.cfg.host, self.cfg.port or 995, timeout=30)
        try:
            m.user(self.cfg.username)
            m.pass_(self.cfg.password)
            count = len(m.list()[1])
            if self.cfg.max_messages:
                count = min(count, self.cfg.max_messages)
            self.total = count
            # POP3 numbers 1..N oldest→newest; fetch newest first.
            total_msgs = len(m.list()[1])
            for i in range(total_msgs, total_msgs - count, -1):
                try:
                    _resp, lines, _oct = m.retr(i)
                except Exception:
                    continue
                msg = email.message_from_bytes(b"\r\n".join(lines))
                yield self._record(msg, f"pop:{i}")
        finally:
            try:
                m.quit()
            except Exception:
                pass

    def _iter_imap(self) -> Iterator[MessageRecord]:
        conn = self._connect()
        try:
            conn.login(self.cfg.username, self.cfg.password)
            mailboxes = self._list_mailboxes(conn)

            # First pass: search every folder so we know the true total (ETA).
            plan = []  # (mailbox, [ids])
            for mbox in mailboxes:
                try:
                    if not self._select(conn, mbox):
                        continue
                    typ, data = conn.search(None, self._search_criteria())
                    # Some servers reject SINCE/charset — fall back to ALL.
                    if typ != "OK":
                        typ, data = conn.search(None, "ALL")
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
            BATCH = 40  # fetch many messages per round-trip (big speedup)
            for mbox, ids in plan:
                if not self._select(conn, mbox):
                    continue
                order = list(reversed(ids))  # newest first within each folder
                if self.cfg.max_messages:
                    remaining = self.cfg.max_messages - emitted
                    if remaining <= 0:
                        return
                    order = order[:remaining]
                for i in range(0, len(order), BATCH):
                    chunk = order[i:i + BATCH]
                    id_set = b",".join(
                        c if isinstance(c, bytes) else str(c).encode() for c in chunk)
                    try:
                        typ, msg_data = conn.fetch(id_set, "(BODY.PEEK[])")
                    except Exception:
                        continue
                    if typ != "OK" or not msg_data:
                        continue
                    for part in msg_data:
                        if not isinstance(part, tuple) or not part[1]:
                            continue
                        try:
                            msg = email.message_from_bytes(part[1])
                        except Exception:
                            continue
                        emitted += 1
                        yield self._record(msg, f"{mbox}:{emitted}")
        finally:
            try:
                conn.close()
            except Exception:
                pass
            try:
                conn.logout()
            except Exception:
                pass
