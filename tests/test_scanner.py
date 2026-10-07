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


def test_netzero_juno_use_pop3():
    # NetZero/Juno have no IMAP server — they must route to POP3.
    s = resolve_imap("someone@netzero.net", allow_network=False)
    assert s.host == "pop.netzero.net" and s.protocol == "pop3" and s.port == 995
    j = resolve_imap("x@juno.com", allow_network=False)
    assert j.host == "pop.juno.com" and j.protocol == "pop3"
    # Normal providers stay on IMAP.
    assert resolve_imap("y@gmail.com", allow_network=False).protocol == "imap"


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


def test_accounts_loader_email_space_password():
    # The user's preferred format: "email password" (space separated).
    import tempfile
    from scanner.accounts import load_accounts
    d = tempfile.mkdtemp()
    p = os.path.join(d, "a.txt")
    with open(p, "w") as fh:
        fh.write("frank439@gmail.com 979password\n"
                 "jane@yahoo.com my pass with spaces\n")
    accts = load_accounts(p)
    assert accts[0].email == "frank439@gmail.com"
    assert accts[0].password == "979password"
    # Everything after the first space is the password, spaces preserved.
    assert accts[1].email == "jane@yahoo.com"
    assert accts[1].password == "my pass with spaces"


def test_accounts_add_update_delete():
    import tempfile
    from scanner.accounts import (add_or_update, delete_account, load_accounts)
    d = tempfile.mkdtemp()
    p = os.path.join(d, "accounts.txt")
    add_or_update(p, "a@gmail.com", "pw1")
    add_or_update(p, "b@yahoo.com", "pw2")
    assert [x.email for x in load_accounts(p)] == ["a@gmail.com", "b@yahoo.com"]
    # update in place (change email + password), keyed by original_email
    add_or_update(p, "a2@gmail.com", "pwX", original_email="a@gmail.com")
    accts = {x.email: x.password for x in load_accounts(p)}
    assert accts == {"a2@gmail.com": "pwX", "b@yahoo.com": "pw2"}, accts
    # delete
    assert delete_account(p, "b@yahoo.com") is True
    assert [x.email for x in load_accounts(p)] == ["a2@gmail.com"]
    assert delete_account(p, "missing@x.com") is False


def test_mailbox_sweep_logic():
    from scanner.sources.email_imap import EmailSource
    from scanner.config import EmailConfig

    class FakeConn:
        def __init__(self, lines): self._lines = lines
        def list(self): return ("OK", self._lines)

    def src_for(host, mailbox):
        cfg = EmailConfig(host=host, username="x", password="p", mailbox=mailbox)
        s = EmailSource.__new__(EmailSource)
        s.cfg = cfg
        s.total = None
        return s

    yahoo = [b'(\\HasNoChildren) "/" "INBOX"', b'(\\HasNoChildren) "/" "Sent"',
             b'(\\Noselect) "/" "[Folders]"']
    boxes = src_for("imap.mail.yahoo.com", "ALL")._list_mailboxes(FakeConn(yahoo))
    assert "INBOX" in boxes and "Sent" in boxes and "[Folders]" not in boxes

    gmail = [b'(\\All) "/" "[Gmail]/All Mail"', b'(\\Junk) "/" "[Gmail]/Spam"',
             b'(\\HasNoChildren) "/" "INBOX"']
    gb = src_for("imap.gmail.com", "ALL")._list_mailboxes(FakeConn(gmail))
    assert any("All Mail" in b for b in gb) and "INBOX" not in gb

    assert src_for("imap.gmail.com", "INBOX")._list_mailboxes(FakeConn([])) == ["INBOX"]


def test_identity_detectors_and_grouping():
    from scanner.report import Inventory
    sample = ("contact john.doe@example.com or (415) 555-0142; "
              "123 Oak Avenue; DOB: 03/14/1988; john.doe@example.com")
    kinds = {f.kind for f in scan_sensitive(sample)}
    assert {"email_address", "phone", "mailing_address", "date_of_birth"} <= kinds

    inv = Inventory(detail="full", account="me@x.com")
    inv.add_findings(scan_sensitive(sample), "loc")
    d = inv.to_dict()
    # Identity items live under personal_info, not sensitive_findings.
    assert d["personal_info"].get("email_address"), d["personal_info"]
    assert d["personal_info"]["email_address"][0]["count"] == 2  # deduped
    assert all(f["kind"] not in {"email_address", "phone"}
               for f in d["sensitive_findings"])


def test_phishing_analyzer():
    from scanner.phishing import analyze_email
    v = analyze_email("security@paypa1-alerts.com", "PayPal Security",
                      "Your account is suspended",
                      "Verify your account, click here to login and enter your "
                      "password http://185.23.1.9/login",
                      reply_to="x@random.ru", auth_results="spf=fail")
    assert v.label == "likely phishing" and v.reasons
    ok = analyze_email("ship@amazon.com", "Amazon.com", "Your order shipped",
                       "Track at https://amazon.com/track", auth_results="spf=pass")
    assert ok.label == "legit"


def test_best_guess_picks_most_frequent():
    from scanner.report import Inventory
    inv = Inventory(detail="full", account="me@x.com")
    inv.name_counts = {"Jane Q Public": 4, "Jane": 1}
    inv.add_findings(scan_sensitive("123 Oak Avenue"), "a")
    inv.add_findings(scan_sensitive("123 Oak Avenue"), "b")
    d = inv.to_dict()
    assert d["best_guess"]["name"]["value"] == "Jane Q Public"
    assert d["best_guess"]["address"]["count"] == 2


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
