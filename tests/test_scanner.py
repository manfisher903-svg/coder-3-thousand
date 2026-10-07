"""Tests for detection, classification, and redaction.

Run with:  python -m pytest -q    (or: python tests/test_scanner.py)
All test data below is synthetic — no real personal information.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scanner.classify import brand_from_domain, classify  # noqa: E402
from scanner.patterns import scan_sensitive  # noqa: E402
from scanner.providers import resolve_imap  # noqa: E402
from scanner.redact import render_value  # noqa: E402
from scanner.report import Inventory  # noqa: E402


def _kinds(text):
    return {f.kind for f in scan_sensitive(text)}


def test_valid_card_detected():
    # 4242 4242 4242 4242 is a well-known Luhn-valid test number.
    assert "credit_card" in _kinds("my card is 4242 4242 4242 4242 ok")


def test_invalid_card_rejected():
    assert "credit_card" not in _kinds("order 1234 5678 9012 3456 shipped")


def test_ssn_detected():
    assert "ssn" in _kinds("SSN: 123-45-6789")


def test_seed_phrase_flagged_and_visible_at_full():
    phrase = ("legal winner thank year wave sausage worth useful legal "
              "winner thank yellow")
    findings = scan_sensitive(phrase)
    seed = [f for f in findings if f.kind == "seed_phrase"]
    assert seed, "seed phrase should be flagged"
    # Full detail shows the whole phrase; redact masks it.
    assert render_value(seed[0], "full") == phrase
    assert render_value(seed[0], "redact").startswith("••••")


def test_password_label_detected():
    assert "password" in _kinds("Username: bob\nPassword: hunter2secret")


def test_redaction_levels():
    findings = scan_sensitive("card 4242 4242 4242 4242")
    card = next(f for f in findings if f.kind == "credit_card")
    assert render_value(card, "redact").startswith("••••")
    assert render_value(card, "partial") == "•••• 4242"
    assert render_value(card, "full") == "4242424242424242"


def test_brand_from_domain():
    assert brand_from_domain("email.chase.com") == "chase"
    assert brand_from_domain("mail.netflix.com") == "netflix"


def test_classify_categories():
    cat, brand = classify("email.chase.com", "Your statement is ready", "")
    assert cat == "banking"
    assert brand == "chase"

    cat, _ = classify("news.coinbase.com", "Your wallet activity", "bitcoin deposit")
    assert cat == "crypto"


def test_provider_detection_builtin():
    # Built-in registry resolves offline (allow_network=False).
    assert resolve_imap("someone@gmail.com", allow_network=False).host == "imap.gmail.com"
    assert resolve_imap("a@yahoo.com", allow_network=False).host == "imap.mail.yahoo.com"
    assert resolve_imap("b@hotmail.com", allow_network=False).host == "outlook.office365.com"
    icloud = resolve_imap("c@icloud.com", allow_network=False)
    assert icloud.host == "imap.mail.me.com" and icloud.security == "ssl"


def test_provider_detection_unknown_offline_raises():
    try:
        resolve_imap("x@nonexistent-weird-domain.example", allow_network=False)
        assert False, "should raise for unknown domain with no network"
    except LookupError:
        pass


def test_accounts_loader_yaml(tmp_path=None):
    import tempfile
    from scanner.accounts import load_accounts
    d = tempfile.mkdtemp()
    p = os.path.join(d, "a.yaml")
    with open(p, "w") as fh:
        fh.write("accounts:\n"
                 "  - email: a@gmail.com\n    password: pw1\n"
                 "  - email: b@yahoo.com\n    password: pw2\n    mailbox: INBOX\n")
    accts = load_accounts(p)
    assert [a.email for a in accts] == ["a@gmail.com", "b@yahoo.com"]
    assert accts[0].password == "pw1"
    assert accts[1].mailbox == "INBOX"
    assert accts[0].safe_name() == "a_gmail.com"


def test_accounts_loader_plain_and_dedup():
    import tempfile
    from scanner.accounts import load_accounts
    d = tempfile.mkdtemp()
    p = os.path.join(d, "a.txt")
    with open(p, "w") as fh:
        fh.write("# my accounts\n"
                 "a@gmail.com,pw1\n"
                 "b@yahoo.com | pw2 | INBOX\n"
                 "a@gmail.com,dupe\n")  # duplicate dropped
    accts = load_accounts(p)
    assert [a.email for a in accts] == ["a@gmail.com", "b@yahoo.com"]
    assert accts[1].password == "pw2" and accts[1].mailbox == "INBOX"


def test_inventory_roundtrip():
    inv = Inventory(detail="redact")
    inv.add_service("chase", "banking", "chase.com", "Statement ready")
    inv.add_findings(scan_sensitive("SSN: 123-45-6789"), "email: test")
    d = inv.to_dict()
    assert d["service_count"] == 1
    assert d["sensitive_count"] == 1
    assert "banking" in d["services_by_category"]
    md = inv.to_markdown()
    assert "Personal Information Inventory" in md


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"ok   {name}")
            except AssertionError as exc:
                failures += 1
                print(f"FAIL {name}: {exc}")
    sys.exit(1 if failures else 0)
