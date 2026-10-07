"""Personal Info Scanner — local app (opens in your browser).

Run it with:   python -m scanner.app
It starts a small web server on http://127.0.0.1:5000 and opens your browser.
Everything stays on your machine; the server only listens on localhost.

Pages:
  /            dashboard — add accounts, run a scan, see each profile
  /profile/... one account's profile: services, findings, saved files/pictures
  /recover     official password-reset links to get back into your accounts
"""

from __future__ import annotations

import json
import os
import threading
import webbrowser
from html import escape

from flask import (Flask, abort, redirect, request, send_from_directory,
                   url_for)

from .accounts import load_accounts
from .config import Config

ACCOUNTS_PATH = os.environ.get("PIS_ACCOUNTS", "accounts.txt")
OUTPUT_DIR = os.environ.get("PIS_OUTPUT", "inventory")

app = Flask(__name__)

# Scan progress state (single run at a time).
_scan_state = {"running": False, "log": [], "summaries": []}
_scan_lock = threading.Lock()


# --- tiny HTML helpers ----------------------------------------------------

PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title><style>
:root{{color-scheme:light dark}}
body{{font-family:system-ui,Segoe UI,Roboto,sans-serif;max-width:860px;margin:0 auto;
padding:16px;line-height:1.5}}
a{{color:#2563eb}} header{{display:flex;gap:16px;align-items:center;flex-wrap:wrap;
border-bottom:1px solid #8884;padding-bottom:10px;margin-bottom:16px}}
header a{{text-decoration:none;font-weight:600}}
h1{{font-size:1.4rem;margin:.2em 0}} h2{{font-size:1.1rem;margin-top:1.4em}}
table{{border-collapse:collapse;width:100%;margin:8px 0}}
th,td{{border:1px solid #8884;padding:6px 8px;text-align:left;font-size:.92rem;
vertical-align:top}} th{{background:#8881}}
.card{{border:1px solid #8884;border-radius:10px;padding:14px;margin:10px 0}}
input,select{{padding:8px;border:1px solid #8886;border-radius:8px;font-size:1rem;
background:transparent;color:inherit}}
button{{padding:9px 16px;border:0;border-radius:8px;background:#2563eb;color:#fff;
font-size:1rem;cursor:pointer}} button.secondary{{background:#6b7280}}
.badge{{display:inline-block;padding:1px 8px;border-radius:999px;background:#8882;
font-size:.8rem}} .muted{{color:#6b7280}} .warn{{color:#b45309}}
img.att{{max-width:220px;max-height:220px;border:1px solid #8884;border-radius:8px;
margin:4px}} code{{word-break:break-all}}
</style></head><body><header>
<a href="/">🏠 Accounts</a><a href="/recover">🔑 Recover access</a>
<span class="muted">Personal Info Scanner — all local</span>
</header>{body}</body></html>"""


def render(title: str, body: str) -> str:
    return PAGE.format(title=escape(title), body=body)


def _load_base_config() -> Config:
    if os.path.exists("config.yaml"):
        try:
            return Config.load("config.yaml")
        except Exception:
            pass
    cfg = Config()
    cfg.output.detail = "full"
    cfg.output.save_attachments = True
    return cfg


# --- routes ---------------------------------------------------------------

@app.route("/")
def index():
    accounts = []
    if os.path.exists(ACCOUNTS_PATH):
        try:
            accounts = load_accounts(ACCOUNTS_PATH)
        except Exception:
            accounts = []

    with _scan_lock:
        running = _scan_state["running"]
        log = list(_scan_state["log"])[-12:]

    rows = ""
    for a in accounts:
        folder = a.safe_name()
        report = os.path.join(OUTPUT_DIR, folder, "report.json")
        if os.path.exists(report):
            try:
                d = json.load(open(report))
                summary = (f'{d.get("service_count",0)} services · '
                           f'{d.get("sensitive_count",0)} findings')
            except Exception:
                summary = "scanned"
            link = f'<a href="{url_for("profile", folder=folder)}">Open profile →</a>'
        else:
            summary = '<span class="muted">not scanned yet</span>'
            link = ""
        rows += (f"<tr><td>{escape(a.email)}</td><td>{summary}</td>"
                 f"<td>{link}</td></tr>")
    if not rows:
        rows = '<tr><td colspan="3" class="muted">No accounts yet — add one below.</td></tr>'

    scan_box = (
        '<p class="warn">Scanning… this can take a few minutes per account.</p>'
        if running else
        '<form method="post" action="/scan"><button>Scan all accounts</button></form>')
    log_html = ""
    if log:
        log_html = "<pre class='card'>" + escape("\n".join(log)) + "</pre>"

    body = f"""
    <h1>Your email accounts</h1>
    <table><tr><th>Account</th><th>Summary</th><th></th></tr>{rows}</table>

    <div class="card"><h2>Add an account</h2>
    <form method="post" action="/accounts/add">
      <p><input name="email" type="email" placeholder="you@example.com" required
         style="min-width:240px"></p>
      <p><input name="password" type="text" placeholder="app password" required
         style="min-width:240px"></p>
      <p><button>Add account</button>
      <span class="muted">Saved to {escape(ACCOUNTS_PATH)} on this computer.</span></p>
    </form></div>

    <div class="card"><h2>Scan</h2>
    <p class="muted">Reads each inbox read-only and builds a profile with
    everything found — services, sensitive items, and saved files/pictures.</p>
    {scan_box}{log_html}
    </div>
    <p class="muted">Most providers need an <b>app password</b> (not your normal
    login). Each account's password lives in {escape(ACCOUNTS_PATH)} — keep it
    private.</p>
    """
    return render("Accounts", body)


@app.route("/accounts/add", methods=["POST"])
def add_account():
    email = (request.form.get("email") or "").strip()
    password = (request.form.get("password") or "").strip()
    if email and password:
        # Append in the simple "email password" format.
        line = f"{email} {password}\n"
        with open(ACCOUNTS_PATH, "a", encoding="utf-8") as fh:
            fh.write(line)
        try:
            os.chmod(ACCOUNTS_PATH, 0o600)
        except OSError:
            pass
    return redirect(url_for("index"))


def _run_scan():
    from .batch import run_batch

    base = _load_base_config()

    def progress(msg):
        with _scan_lock:
            _scan_state["log"].append(msg)

    try:
        summaries = run_batch(ACCOUNTS_PATH, base, OUTPUT_DIR, progress=progress)
        with _scan_lock:
            _scan_state["summaries"] = summaries
    finally:
        with _scan_lock:
            _scan_state["running"] = False


@app.route("/scan", methods=["POST"])
def scan():
    with _scan_lock:
        if not _scan_state["running"]:
            _scan_state["running"] = True
            _scan_state["log"] = []
            threading.Thread(target=_run_scan, daemon=True).start()
    return redirect(url_for("index"))


def _is_image(name: str) -> bool:
    return name.lower().rsplit(".", 1)[-1] in {"png", "jpg", "jpeg", "gif", "webp", "bmp"}


@app.route("/profile/<folder>")
def profile(folder):
    folder = os.path.basename(folder)  # prevent traversal
    acct_dir = os.path.join(OUTPUT_DIR, folder)
    report = os.path.join(acct_dir, "report.json")
    if not os.path.exists(report):
        abort(404)
    d = json.load(open(report))

    # Services by category
    svc_html = ""
    for cat in sorted(d.get("services_by_category", {})):
        entries = d["services_by_category"][cat]
        items = "".join(
            f"<li><b>{escape(e['brand'])}</b> "
            f"<span class='muted'>{escape(', '.join(e.get('domains', [])))}</span> "
            f"· {e['message_count']} msg</li>" for e in entries)
        svc_html += f"<h3>{escape(cat.title())} <span class='badge'>{len(entries)}</span></h3><ul>{items}</ul>"
    if not svc_html:
        svc_html = "<p class='muted'>No services detected.</p>"

    # Sensitive findings
    find_rows = ""
    for h in d.get("sensitive_findings", []):
        find_rows += (f"<tr><td>{escape(h['severity'].upper())}</td>"
                      f"<td>{escape(h['kind'])}</td>"
                      f"<td><code>{escape(str(h['value']))}</code></td>"
                      f"<td>{escape(h['location'])}</td>"
                      f"<td>{escape(h['advice'])}</td></tr>")
    find_html = (f"<table><tr><th>Severity</th><th>Type</th><th>Value</th>"
                 f"<th>Where</th><th>Advice</th></tr>{find_rows}</table>"
                 if find_rows else "<p class='muted'>No sensitive items found.</p>")

    # Attachments / pictures
    att_html = ""
    for rel in d.get("attachments_saved", []):
        safe_rel = rel.replace("\\", "/")
        file_url = url_for("serve_file", folder=folder, path=safe_rel)
        name = os.path.basename(safe_rel)
        if _is_image(name):
            att_html += f'<a href="{file_url}"><img class="att" src="{file_url}" alt="{escape(name)}"></a>'
        else:
            att_html += f'<p>📎 <a href="{file_url}">{escape(name)}</a></p>'
    if not att_html:
        att_html = "<p class='muted'>No files or pictures saved for this account.</p>"

    body = f"""
    <h1>{escape(d.get('account') or folder)}</h1>
    <p class="muted">Detail level: {escape(d.get('detail_level','full'))} ·
    {d.get('sources_scanned',0)} messages scanned ·
    <a href="{url_for('serve_file', folder=folder, path='report.md')}">raw report.md</a></p>

    <h2>Services &amp; accounts <span class="badge">{d.get('service_count',0)}</span></h2>
    {svc_html}

    <h2>Sensitive findings <span class="badge">{d.get('sensitive_count',0)}</span></h2>
    {find_html}

    <h2>Files &amp; pictures</h2>
    {att_html}
    """
    return render(f"Profile — {folder}", body)


@app.route("/file/<folder>/<path:path>")
def serve_file(folder, path):
    folder = os.path.basename(folder)
    directory = os.path.abspath(os.path.join(OUTPUT_DIR, folder))
    # send_from_directory guards against path traversal out of `directory`.
    return send_from_directory(directory, path)


@app.route("/recover")
def recover():
    from .recovery import recovery_url

    accounts = []
    if os.path.exists(ACCOUNTS_PATH):
        try:
            accounts = load_accounts(ACCOUNTS_PATH)
        except Exception:
            accounts = []

    rows = ""
    for a in accounts:
        url = recovery_url(a.email)
        if url:
            link = f'<a href="{escape(url)}" target="_blank" rel="noopener">Reset password →</a>'
        else:
            link = ('<span class="muted">Open your provider\'s sign-in page and '
                    'click “Forgot password”.</span>')
        rows += f"<tr><td>{escape(a.email)}</td><td>{link}</td></tr>"
    if not rows:
        rows = '<tr><td colspan="2" class="muted">Add accounts first.</td></tr>'

    body = f"""
    <h1>Recover access to your accounts</h1>
    <div class="card">
    <p>The safe, reliable way back into your own email is your provider's
    official password-reset flow. It verifies it's you (backup email, phone, or
    security questions) and lets you set a new password — and it works even when
    you've completely forgotten the old one.</p>
    <p class="muted">Guessing passwords by hand or with a tool doesn't work on
    modern email: a handful of wrong tries locks the account and can get your
    device blocked. Reset is faster and won't lock you out.</p>
    </div>
    <table><tr><th>Account</th><th>Official recovery</th></tr>{rows}</table>
    <p class="muted">Tip: after resetting, save the new password in a password
    manager and turn on two-factor authentication.</p>
    """
    return render("Recover access", body)


def main():
    url = "http://127.0.0.1:5000"
    print(f"Personal Info Scanner app running at {url}")
    print("Everything stays on this computer. Press Ctrl+C to stop.")
    try:
        threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    except Exception:
        pass
    app.run(host="127.0.0.1", port=5000, debug=False)


if __name__ == "__main__":
    main()
