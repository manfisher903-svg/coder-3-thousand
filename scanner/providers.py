"""Auto-detect IMAP server settings from an email address.

Goal: the user only has to supply their email address and an app password.
We figure out the IMAP host/port/security from the address domain, using:

  1. A built-in registry of common providers (works offline, instant).
  2. Mozilla's autoconfig database (ISPDB) over HTTPS — covers thousands of
     providers including most custom/business domains.
  3. Heuristic guesses (imap.<domain>, mail.<domain>, …) verified by actually
     opening a TLS/STARTTLS connection to the candidate.

Each resolver returns an ImapServer; `security` is "ssl" (port 993) or
"starttls" (port 143).
"""

from __future__ import annotations

import socket
import ssl
from dataclasses import dataclass
from typing import Dict, List, Optional
from urllib.request import urlopen


@dataclass
class ImapServer:
    host: str
    port: int
    security: str  # "ssl" | "starttls"
    source: str = ""        # where we got this from, for display
    protocol: str = "imap"  # "imap" | "pop3"


# --- 1. Built-in registry of common consumer providers --------------------
# Keyed by the mail domain. Values are (host, port, security).
_KNOWN: Dict[str, ImapServer] = {}


def _reg(domains: List[str], host: str, port: int = 993, security: str = "ssl") -> None:
    for d in domains:
        _KNOWN[d] = ImapServer(host, port, security, source="built-in")


_reg(["gmail.com", "googlemail.com"], "imap.gmail.com")
_reg(["yahoo.com", "yahoo.co.uk", "yahoo.ca", "yahoo.com.au", "ymail.com",
      "rocketmail.com"], "imap.mail.yahoo.com")
_reg(["aol.com"], "imap.aol.com")
_reg(["outlook.com", "hotmail.com", "live.com", "msn.com", "hotmail.co.uk",
      "outlook.co.uk", "windowslive.com"], "outlook.office365.com")
_reg(["icloud.com", "me.com", "mac.com"], "imap.mail.me.com")
_reg(["proton.me", "protonmail.com", "pm.me"], "127.0.0.1", 1143, "starttls")  # Proton Bridge
_reg(["gmx.com", "gmx.net", "gmx.de"], "imap.gmx.com")
_reg(["zoho.com", "zohomail.com"], "imap.zoho.com")
_reg(["fastmail.com", "fastmail.fm"], "imap.fastmail.com")
_reg(["mail.com"], "imap.mail.com")
_reg(["yandex.com", "yandex.ru"], "imap.yandex.com")
_reg(["comcast.net"], "imap.comcast.net")
_reg(["att.net", "sbcglobal.net", "bellsouth.net"], "imap.mail.att.net")
_reg(["verizon.net"], "imap.aol.com")  # Verizon mail is served by AOL
_reg(["cox.net"], "imap.cox.net")
_reg(["btinternet.com", "btopenworld.com", "talk21.com", "btconnect.com", "bt.com"],
     "mail.btinternet.com")
# NetZero & Juno (United Online) are POP3-only — they have no IMAP server.
_KNOWN["netzero.net"] = ImapServer("pop.netzero.net", 995, "ssl",
                                   source="built-in", protocol="pop3")
_KNOWN["netzero.com"] = ImapServer("pop.netzero.com", 995, "ssl",
                                   source="built-in", protocol="pop3")
_KNOWN["juno.com"] = ImapServer("pop.juno.com", 995, "ssl",
                                source="built-in", protocol="pop3")
_reg(["mail.ru", "bk.ru", "inbox.ru", "list.ru", "internet.ru"], "imap.mail.ru")
_reg(["my.com"], "imap.my.com")  # the myMail service by my.com / Mail.ru Group


# Curated list for the app's "choose provider" dropdown: (label, host).
# An empty host means auto-detect from the address.
PROVIDERS = [
    ("Auto-detect (recommended)", ""),
    ("Gmail", "imap.gmail.com"),
    ("Yahoo", "imap.mail.yahoo.com"),
    ("Outlook / Hotmail / Live", "outlook.office365.com"),
    ("iCloud", "imap.mail.me.com"),
    ("AOL", "imap.aol.com"),
    ("Comcast (Xfinity)", "imap.comcast.net"),
    ("AT&T / SBCGlobal / BellSouth", "imap.mail.att.net"),
    ("Verizon", "imap.aol.com"),
    ("Cox", "imap.cox.net"),
    ("BT Internet (UK)", "mail.btinternet.com"),
    ("GMX", "imap.gmx.com"),
    ("Zoho", "imap.zoho.com"),
    ("Fastmail", "imap.fastmail.com"),
    ("Yandex", "imap.yandex.com"),
    ("Mail.com", "imap.mail.com"),
    ("Mail.ru", "imap.mail.ru"),
    ("My.com / myMail (@my.com address)", "imap.my.com"),
    ("NetZero (POP3)", "pop.netzero.net"),
    ("Juno (POP3)", "pop.juno.com"),
    ("cPanel Webmail (your own domain)", "__cpanel__"),
    ("Other / webmail — type my mail server below", "__custom__"),
]


def resolve_by_host(host: str) -> Optional[ImapServer]:
    """If `host` is a known server, return its full settings (port, security,
    and protocol — e.g. POP3 for NetZero/Juno). Otherwise None."""
    if not host:
        return None
    h = host.strip().lower()
    for srv in _KNOWN.values():
        if srv.host.lower() == h:
            return ImapServer(srv.host, srv.port, srv.security,
                              source="chosen provider", protocol=srv.protocol)
    return None


def _domain_of(address: str) -> str:
    return address.split("@")[-1].strip().lower() if "@" in address else ""


# --- 2. Mozilla ISPDB autoconfig -----------------------------------------

def _from_ispdb(domain: str, timeout: float = 5.0) -> Optional[ImapServer]:
    url = f"https://autoconfig.thunderbird.net/v1.1/{domain}"
    try:
        with urlopen(url, timeout=timeout) as resp:  # noqa: S310 - fixed https host
            data = resp.read()
    except Exception:
        return None

    import xml.etree.ElementTree as ET

    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        return None

    for server in root.iter("incomingServer"):
        if server.get("type") != "imap":
            continue
        host = (server.findtext("hostname") or "").strip()
        port = int((server.findtext("port") or "993").strip() or 993)
        socket_type = (server.findtext("socketType") or "SSL").strip().upper()
        if not host:
            continue
        security = "starttls" if socket_type in ("STARTTLS", "PLAIN") else "ssl"
        return ImapServer(host, port, security, source="autoconfig (ISPDB)")
    return None


# --- 3. Heuristic guesses, verified by connecting ------------------------

def _can_connect_ssl(host: str, port: int, timeout: float = 4.0) -> bool:
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((host, port), timeout=timeout) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as ssock:
                banner = ssock.recv(64)
                return banner.startswith(b"* OK") or b"IMAP" in banner.upper()
    except Exception:
        return False


def _can_connect_starttls(host: str, port: int, timeout: float = 4.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            banner = sock.recv(64)
            return banner.startswith(b"* OK") or b"IMAP" in banner.upper()
    except Exception:
        return False


def _from_guess(domain: str) -> Optional[ImapServer]:
    ssl_candidates = [f"imap.{domain}", f"mail.{domain}", f"imap.mail.{domain}", domain]
    for host in ssl_candidates:
        if _can_connect_ssl(host, 993):
            return ImapServer(host, 993, "ssl", source="auto-guess")
    for host in ssl_candidates:
        if _can_connect_starttls(host, 143):
            return ImapServer(host, 143, "starttls", source="auto-guess")
    return None


# --- public API -----------------------------------------------------------

def known_providers() -> Dict[str, ImapServer]:
    return dict(_KNOWN)


def resolve_imap(address: str, allow_network: bool = True) -> ImapServer:
    """Resolve IMAP settings for an email address, or raise with guidance."""
    domain = _domain_of(address)
    if not domain:
        raise ValueError(f"'{address}' doesn't look like an email address.")

    if domain in _KNOWN:
        return _KNOWN[domain]

    if allow_network:
        found = _from_ispdb(domain)
        if found:
            return found
        found = _from_guess(domain)
        if found:
            return found

    raise LookupError(
        f"Couldn't auto-detect IMAP settings for '{domain}'. "
        f"Set email.host (and port) manually in config.yaml — check your "
        f"provider's help page for 'IMAP settings'."
    )
