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
    # Needs crypto context nearby (otherwise 12 prose words would false-positive).
    findings = scan_sensitive("my wallet recovery phrase " + phrase)
    seed = [f for f in findings if f.kind == "seed_phrase"]
    assert seed, "seed phrase should be flagged"
    # Full detail shows the matched phrase; redact masks it.
    assert render_value(seed[0], "full") == phrase
    assert render_value(seed[0], "redact").startswith("••••")
    # And prose WITHOUT crypto context is NOT flagged as a seed phrase.
    assert "seed_phrase" not in _kinds(phrase + " and more random words here now")


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


def test_labeled_plain_language_detection():
    # Info written in plain English, not standard formats, is still caught.
    def kinds(t):
        return {f.kind: f.raw for f in scan_sensitive(t)}
    assert kinds("my card number is 5424189090238457 09/30 943")["credit_card"] \
        == "5424189090238457"
    assert kinds("my ssn is 34398543")["ssn"] == "34398543"
    seed = kinds("coinbase seed key: oniuniubiuebiufbeiufbeiufeiuf").get("seed_phrase")
    assert seed and "oniuni" in seed
    assert "pin_or_cvv" in kinds("my pin is 4821")
    # But an unlabeled random number is NOT a false-positive card.
    assert "credit_card" not in kinds("order 1234 5678 9012 3456 shipped")


def test_tax_detection():
    kinds = {}
    for f in scan_sensitive("Your W-2 for tax year 2024. EIN: 12-3456789. "
                            "1099-INT attached. IRS refund pending."):
        kinds.setdefault(f.kind, set()).add(f.raw)
    assert "ein" in kinds and "12-3456789" in kinds["ein"]
    assert "tax_document" in kinds
    from scanner.classify import classify
    assert classify("mail.turbotax.com", "Your W-2 is ready", "")[0] == "tax"


def test_identity_detectors_and_grouping():
    from scanner.report import Inventory
    sample = ("contact john.doe@example.com or (415) 555-0142; "
              "123 Oak Avenue; DOB: 03/14/1988; john.doe@example.com")
    kinds = {f.kind for f in scan_sensitive(sample)}
    assert {"email_address", "phone", "mailing_address", "date_of_birth"} <= kinds

    inv = Inventory(detail="full", account="me@x.com")
    # Same email across two messages → counted twice (within one message it's
    # de-duplicated, so simulate two messages).
    inv.add_findings(scan_sensitive("write john.doe@example.com"), "msg1")
    inv.add_findings(scan_sensitive("again john.doe@example.com"), "msg2")
    d = inv.to_dict()
    assert d["personal_info"].get("email_address"), d["personal_info"]
    assert d["personal_info"]["email_address"][0]["count"] == 2
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


def test_profile_uses_only_legit_mail():
    import tempfile, json
    import scanner.sources.email_imap as es
    from scanner.sources.email_imap import MessageRecord
    from scanner.config import Config
    from scanner.accounts import Account
    import scanner.batch as batch

    class FakeSource:
        def __init__(self, cfg):
            self.cfg = cfg; self.cfg.protocol = "imap"; self.total = 2
        def iter_messages(self):
            yield MessageRecord("1", None, "Amazon", "ship@amazon.com", "amazon.com",
                                "Your order shipped",
                                "Shipping to 500 Real Home St.",
                                auth_results="spf=pass", to_names=["Chris Martinez"])
            yield MessageRecord("2", None, "PayPal", "paypal@scammer.ru", "scammer.ru",
                                "Verify your account now",
                                "Urgent verify your account enter your password "
                                "http://1.2.3.4/x office 999 Fake Scam Ave.",
                                reply_to="x@evil.ru", auth_results="spf=fail",
                                to_names=["Victim Name"])

    orig = es.EmailSource
    es.EmailSource = FakeSource
    try:
        out = tempfile.mkdtemp()
        batch.scan_one(Account(email="me@test.com", password="x"), Config(), out)
        d = json.load(open(os.path.join(out, "report.json")))
    finally:
        es.EmailSource = orig

    assert d["suspicious_count"] == 1
    addrs = [a["value"] for a in d["personal_info"].get("mailing_address", [])]
    assert any("Real Home" in a for a in addrs)
    assert not any("Fake Scam" in a for a in addrs)  # phishing info excluded
    assert d["best_guess"]["name"]["value"] == "Chris Martinez"


def test_setup_guides_are_provider_specific():
    from scanner.setup_help import get_setup_guide
    assert get_setup_guide("x@yahoo.com")["provider"] == "Yahoo"
    assert "login.yahoo.com" in get_setup_guide("x@yahoo.com")["url"]
    assert get_setup_guide("x@gmail.com")["provider"] == "Gmail"
    assert get_setup_guide("x@icloud.com")["provider"] == "iCloud"
    assert get_setup_guide("x@netzero.net")["provider"] == "NetZero / Juno"
    # Unknown domain still returns usable generic steps.
    g = get_setup_guide("x@weirdmail.io")
    assert g["steps"] and "weirdmail.io" in g["provider"]


def test_roasts_pool_is_clean_and_rotates():
    from scanner.roasts import ROASTS, LOGIN_ROASTS, pick_roast, pick_login_roast
    assert len(ROASTS) == 100 and len(LOGIN_ROASTS) >= 30
    bad = ["nigg", "fag", "retard", "rape", "kys", "tranny", "spic", "chink",
           "kike", "suicide", "kill yourself"]
    joined = (" ".join(ROASTS) + " " + " ".join(LOGIN_ROASTS)).lower()
    assert not [b for b in bad if b in joined], "roast pools must stay slur-free"
    assert pick_roast().startswith("⚠️") and pick_login_roast().startswith("⚠️")


def test_auto_logout_on_inactivity():
    import tempfile, importlib, shutil, time
    work = tempfile.mkdtemp(); cwd = os.getcwd(); os.chdir(work)
    os.environ["PIS_USERS"] = work + "/.pis_users.json"
    os.environ["PIS_DATA"] = work + "/data"
    os.environ["PIS_OWNER"] = "user1"      # this test's account is the owner
    os.environ["PIS_TIMEOUT_MIN"] = "30"
    try:
        import scanner.app as a
        importlib.reload(a)
        c = a.app.test_client()
        r = c.post("/register", data={"username": "user1", "password": "abc123",
                                      "password2": "abc123"}, follow_redirects=True)
        assert b"Your email accounts" in r.data        # registered + logged in
        assert c.get("/").status_code == 200           # active
        with c.session_transaction() as s:
            s["last"] = time.time() - 31 * 60          # 31 min idle
        assert "/login" in c.get("/").headers.get("Location", "")   # kicked out
    finally:
        os.chdir(cwd); shutil.rmtree(work, ignore_errors=True)
        for k in ("PIS_USERS", "PIS_DATA", "PIS_OWNER", "PIS_TIMEOUT_MIN"):
            os.environ.pop(k, None)
        import scanner.app as a
        importlib.reload(a)


def test_multiuser_login_and_isolation():
    import tempfile, json, importlib, shutil, re
    work = tempfile.mkdtemp()
    cwd = os.getcwd()
    os.chdir(work)
    os.environ["PIS_USERS"] = work + "/.pis_users.json"
    os.environ["PIS_DATA"] = work + "/data"
    os.environ["PIS_INVITES"] = work + "/.pis_invites.json"
    os.environ["PIS_OWNER"] = "alice"      # alice is the designated owner here
    try:
        import scanner.app as a
        importlib.reload(a)
        # Not logged in → everything redirects to login.
        anon = a.app.test_client()
        for p in ["/", "/master", "/export", "/file/x/y", "/scan/status"]:
            assert "/login" in anon.get(p).headers.get("Location", ""), p

        # Register alice.
        alice = a.app.test_client()
        r = alice.post("/register", data={"username": "alice", "password": "secret1",
                                          "password2": "secret1"}, follow_redirects=True)
        assert b"Your email accounts" in r.data
        # Username uniqueness enforced (now shown via a rotating roast).
        bobdup = a.app.test_client()
        r = bobdup.post("/register", data={"username": "ALICE", "password": "x123456",
                                           "password2": "x123456"})
        assert "⚠️".encode() in r.data and b"Create account" in r.data  # rejected
        assert b"Your email accounts" not in r.data                     # not logged in
        # Password mismatch + too short rejected.
        assert b"match" in a.app.test_client().post(
            "/register", data={"username": "bob", "password": "a", "password2": "b"}).data
        assert b"at least 6" in a.app.test_client().post(
            "/register", data={"username": "bob", "password": "123", "password2": "123"}).data

        # alice adds an account → lands in HER data dir only.
        alice.post("/accounts/add", data={"email": "a@x.com", "password": "pw"})

        # alice is the first user → owner, and can reach the invite page.
        assert b"Invite codes" in alice.get("/invites").data
        # Someone WITHOUT a code cannot register now.
        nocode = a.app.test_client().post(
            "/register", data={"username": "carol", "password": "secret3",
                               "password2": "secret3"})
        assert b"invite code" in nocode.data and b"Your email accounts" not in nocode.data
        # Owner generates a code; bob registers with it.
        gen = alice.post("/invites", data={"action": "generate", "uses": "1"})
        m = re.search(rb"SR-[A-Z2-9]{4}-[A-Z2-9]{4}", gen.data)
        assert m, "invite code not shown"
        code = m.group(0).decode()

        bob = a.app.test_client()
        bob.post("/register", data={"username": "bob", "password": "secret2",
                                    "password2": "secret2", "code": code},
                 follow_redirects=True)
        assert b"a@x.com" not in bob.get("/").data          # isolation
        assert b"a@x.com" in alice.get("/").data
        # bob is NOT the owner → no invite/users pages for him.
        assert bob.get("/invites").status_code == 403
        assert bob.get("/users").status_code == 403

        # Owner can list users and look through bob's (empty) data read-only.
        assert b"bob" in alice.get("/users").data
        alice.get("/users/bob/view")                       # start viewing bob
        home = alice.get("/").data
        assert b"Viewing bob" in home                       # banner shown
        assert b"a@x.com" not in home                       # shows bob's data, not alice's
        # While viewing, the owner cannot change the viewed account.
        alice.post("/accounts/add", data={"email": "x@y.com", "password": "pw"})
        assert b"x@y.com" not in alice.get("/").data         # add was blocked
        alice.get("/stopview")                               # back to own data
        assert b"a@x.com" in alice.get("/").data

        # Wrong login rejected (shown via a rotating roast), right login works.
        wrong = a.app.test_client().post(
            "/login", data={"username": "alice", "password": "nope"})
        assert "⚠️".encode() in wrong.data and b"Your email accounts" not in wrong.data
        assert b"a@x.com" in a.app.test_client().post(
            "/login", data={"username": "alice", "password": "secret1"},
            follow_redirects=True).data

        # Passwords stored hashed, never plaintext.
        users = json.load(open(os.environ["PIS_USERS"]))
        assert "secret1" not in json.dumps(users) and users["alice"]["hash"]
    finally:
        os.chdir(cwd)
        shutil.rmtree(work, ignore_errors=True)
        for k in ("PIS_USERS", "PIS_DATA", "PIS_INVITES", "PIS_OWNER"):
            os.environ.pop(k, None)
        import scanner.app as a
        importlib.reload(a)


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


def test_owner_and_invite_flow():
    import tempfile, os
    from scanner.users import add_user, is_owner, user_count, set_owner
    from scanner import invites
    d = tempfile.mkdtemp()
    users = os.path.join(d, "users.json")
    codes = os.path.join(d, "invites.json")

    # First user is set up as owner.
    assert user_count(users) == 0
    ok, _ = add_user(users, "650rio", "Luna223$", owner=True)
    assert ok and is_owner(users, "650rio")

    # Owner generates a single-use code; it validates, then is used up.
    code = invites.create_code(codes, "650rio", label="for Sam", max_uses=1)
    assert code.startswith("SR-")
    assert invites.check_valid(codes, code)[0] is True
    ok, _ = invites.redeem(codes, code, "sam")
    assert ok
    assert invites.check_valid(codes, code)[0] is False  # used up

    # A bogus code is rejected; a revoked code stops working.
    assert invites.check_valid(codes, "SR-XXXX-YYYY")[0] is False
    code2 = invites.create_code(codes, "650rio", max_uses=5)
    invites.revoke(codes, code2)
    assert invites.check_valid(codes, code2)[0] is False

    # Promotion of an existing user works.
    add_user(users, "helper", "pw1234")
    assert not is_owner(users, "helper")
    set_owner(users, "helper", True)
    assert is_owner(users, "helper")


def test_filepass_literal_password():
    from scanner.filepass import find_password
    txt = "Your statement is attached. The password to open the PDF is Smith1985."
    assert find_password(txt) == "Smith1985"


def test_filepass_hint_password():
    from scanner.filepass import find_password
    txt = ("This document is password protected. "
           "Your password is your date of birth.")
    assert find_password(txt).startswith("(hint)")


def test_filepass_ignores_reset_links():
    from scanner.filepass import find_password
    txt = "Click here to reset your password: https://example.com/reset"
    assert find_password(txt, require_context=True) is None


def test_filepass_detects_encrypted_pdf():
    from scanner.filepass import is_encrypted
    assert is_encrypted("doc.pdf", b"%PDF-1.7 /Encrypt 5 0 R trailer")
    assert not is_encrypted("doc.pdf", b"%PDF-1.7 plain content")


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
