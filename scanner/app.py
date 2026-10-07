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

from flask import (Flask, abort, redirect, request, send_file,
                   send_from_directory, session, url_for)

from .accounts import (add_or_update, delete_account, load_accounts,
                       save_accounts)
from .config import Config

USERS_PATH = os.environ.get("PIS_USERS", ".pis_users.json")
DATA_ROOT = os.environ.get("PIS_DATA", "data")   # per-user data lives here
SECRET_PATH = ".pis_secret"

app = Flask(__name__)


# --- per-user data paths (each signed-in user has private data) ------------

def _user():
    return session.get("user")


def _user_dir():
    from .users import user_dirname
    d = os.path.join(DATA_ROOT, user_dirname(_user() or "nobody"))
    os.makedirs(d, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def _acct_path():
    return os.path.join(_user_dir(), "accounts.txt")


def _out_dir():
    d = os.path.join(_user_dir(), "inventory")
    os.makedirs(d, exist_ok=True)
    return d


# --- app login (protects everything behind one password) ------------------

def _app_secret() -> bytes:
    """Stable signing key for sessions; created once, persisted locally."""
    import secrets
    try:
        with open(SECRET_PATH, "r", encoding="utf-8") as fh:
            return bytes.fromhex(fh.read().strip())
    except Exception:
        key = secrets.token_bytes(32)
        try:
            with open(SECRET_PATH, "w", encoding="utf-8") as fh:
                fh.write(key.hex())
            os.chmod(SECRET_PATH, 0o600)
        except OSError:
            pass
        return key


app.secret_key = _app_secret()
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")

# Endpoints reachable without being logged in.
_PUBLIC = {"login", "register", "static"}


@app.before_request
def _require_login():
    if request.endpoint in _PUBLIC:
        return None
    if session.get("user"):
        return None
    return redirect(url_for("login"))

# Scan progress state, kept PER USER so people don't see each other's scans.
# user -> {"running":bool, "accounts":{email:{...}}, "order":[email,...]}
_scan_states = {}
_scan_lock = threading.Lock()


def _state_for(user: str) -> dict:
    return _scan_states.setdefault(
        user, {"running": False, "accounts": {}, "order": []})


def _make_progress(user: str):
    """A batch progress callback that updates one user's scan state."""
    import time

    def cb(ev: dict) -> None:
        with _scan_lock:
            st = _state_for(user)
            accts = st["accounts"]
            email = ev.get("email")
            kind = ev.get("event")
            if email and email not in accts:
                accts[email] = {"done": 0, "total": None, "status": "pending",
                                "started": None, "services": 0, "findings": 0}
                st["order"].append(email)
            if kind == "start":
                accts[email].update(status="scanning", started=time.time())
            elif kind == "progress":
                accts[email].update(done=ev.get("done", 0),
                                    total=ev.get("total"), status="scanning")
            elif kind == "done":
                accts[email].update(status=ev.get("status", "ok"),
                                    services=ev.get("services", 0),
                                    findings=ev.get("sensitive", 0))
    return cb


# --- tiny HTML helpers ----------------------------------------------------

PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} :: SpeedRunner</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Orbitron:wght@600;800&display=swap" rel="stylesheet">
<style>
:root{{--bg:#05080a;--panel:#0b1210;--grn:#27ff99;--grn2:#13c074;--dim:#5c7d70;
--amber:#ffb347;--red:#ff4d5e;--line:#123;--glow:0 0 6px rgba(39,255,153,.55)}}
*{{box-sizing:border-box}}
html,body{{margin:0;background:var(--bg);color:var(--grn);
font-family:'Share Tech Mono',ui-monospace,Consolas,monospace}}
body{{max-width:960px;margin:0 auto;padding:16px 18px 60px;line-height:1.55;
position:relative;z-index:1}}
canvas#matrix{{position:fixed;inset:0;z-index:0;opacity:.14;pointer-events:none}}
/* scanline + flicker overlay */
body::after{{content:"";position:fixed;inset:0;z-index:2;pointer-events:none;
background:repeating-linear-gradient(rgba(0,0,0,0) 0 2px,rgba(0,0,0,.18) 2px 3px)}}
a{{color:var(--grn);text-decoration:none;text-shadow:var(--glow)}}
a:hover{{color:#eafff4;text-shadow:0 0 10px var(--grn)}}
header{{display:flex;gap:14px;align-items:center;flex-wrap:wrap;
border:1px solid var(--grn2);border-radius:8px;padding:10px 14px;margin-bottom:18px;
background:linear-gradient(180deg,rgba(19,192,116,.08),transparent);
box-shadow:var(--glow),inset 0 0 18px rgba(39,255,153,.05)}}
.brand{{font-family:'Orbitron',sans-serif;font-weight:800;font-size:1.25rem;
letter-spacing:3px;color:var(--grn);text-shadow:var(--glow);margin-right:auto}}
.brand .cur{{animation:blink 1s steps(1) infinite}}
@keyframes blink{{50%{{opacity:0}}}}
header a{{font-weight:600;border:1px solid transparent;padding:4px 8px;border-radius:6px}}
header a:hover{{border-color:var(--grn2);background:rgba(39,255,153,.06)}}
h1{{font-family:'Orbitron',sans-serif;font-size:1.35rem;letter-spacing:2px;
margin:.3em 0;text-shadow:var(--glow)}}
h1::before{{content:"> ";color:var(--grn2)}}
h2{{font-size:1.05rem;margin-top:1.5em;color:#9effcf;text-shadow:var(--glow)}}
h2::before{{content:"# ";color:var(--grn2)}}
h3{{color:#bfffe2;margin:.9em 0 .3em}}
table{{border-collapse:collapse;width:100%;margin:10px 0}}
th,td{{border:1px solid var(--grn2);padding:7px 9px;text-align:left;font-size:.9rem;
vertical-align:top}}
th{{background:rgba(39,255,153,.09);text-transform:uppercase;letter-spacing:1px;
font-size:.78rem;color:#9effcf}}
tr:hover td{{background:rgba(39,255,153,.04)}}
.card{{border:1px solid var(--grn2);border-radius:8px;padding:16px;margin:12px 0;
background:var(--panel);box-shadow:inset 0 0 20px rgba(39,255,153,.04)}}
input,select{{padding:9px 10px;border:1px solid var(--grn2);border-radius:6px;
font-size:.95rem;background:#02110b;color:var(--grn);font-family:inherit;
outline:none}}
input:focus{{box-shadow:var(--glow);border-color:var(--grn)}}
input::placeholder{{color:var(--dim)}}
button{{padding:9px 16px;border:1px solid var(--grn);border-radius:6px;
background:rgba(39,255,153,.12);color:var(--grn);font-size:.92rem;cursor:pointer;
font-family:inherit;letter-spacing:1px;text-transform:uppercase;transition:.15s}}
button:hover{{background:var(--grn);color:#02110b;box-shadow:0 0 14px var(--grn)}}
button.secondary{{border-color:var(--grn2);color:var(--grn2);
background:rgba(19,192,116,.08)}}
button.secondary:hover{{background:var(--grn2);color:#02110b;box-shadow:0 0 12px var(--grn2)}}
button:disabled{{opacity:.4;cursor:not-allowed;box-shadow:none}}
.badge{{display:inline-block;padding:1px 9px;border:1px solid var(--grn2);
border-radius:999px;background:rgba(39,255,153,.1);font-size:.78rem}}
.muted{{color:var(--dim)}} .warn{{color:var(--amber);text-shadow:0 0 6px rgba(255,179,71,.5)}}
img.att{{max-width:220px;max-height:220px;border:1px solid var(--grn2);border-radius:6px;
margin:4px;filter:saturate(.9)}}
img.att:hover{{box-shadow:0 0 14px var(--grn)}}
code{{word-break:break-all;color:#eaffb0;background:#02110b;padding:1px 5px;
border-radius:4px;border:1px solid #1d3a2c}}
pre.card{{white-space:pre-wrap;color:#9effcf;font-size:.85rem}}
footer{{margin-top:26px;color:var(--dim);font-size:.8rem;border-top:1px solid var(--grn2);
padding-top:10px}}
</style></head><body>
<canvas id="matrix"></canvas>
<header>
<span class="brand">◢ SPEEDRUNNER<span class="cur">_</span></span>
<a href="/">▸ accounts</a><a href="/master">▸ master</a>
<a href="/search">▸ search</a><a href="/export">▸ export</a>
<a href="/recover">▸ recover</a><a href="/logout">▸ lock</a>
</header>{body}
<footer>SpeedRunner // 100% local — nothing leaves this machine // read-only email access</footer>
<script>
// Lightweight matrix rain for background flavor.
(function(){{
 var c=document.getElementById('matrix');if(!c)return;var x=c.getContext('2d');
 var chars="01<>/\\|=+*#АБ01アカサ$€¥{{}};:".split("");var cols,drops;
 function size(){{c.width=innerWidth;c.height=innerHeight;cols=Math.floor(c.width/14);
  drops=Array(cols).fill(1);}}
 size();addEventListener('resize',size);
 function draw(){{x.fillStyle="rgba(5,8,10,0.08)";x.fillRect(0,0,c.width,c.height);
  x.fillStyle="#27ff99";x.font="14px monospace";
  for(var i=0;i<drops.length;i++){{var t=chars[Math.floor(Math.random()*chars.length)];
   x.fillText(t,i*14,drops[i]*14);
   if(drops[i]*14>c.height&&Math.random()>0.975)drops[i]=0;drops[i]++;}}}}
 setInterval(draw,60);
}})();
</script>
</body></html>"""


def render(title: str, body: str) -> str:
    return PAGE.format(title=escape(title), body=body)


def _load_base_config() -> Config:
    # Start from config.yaml if present (for encryption passphrase etc.), but the
    # APP always scans everything — a stale config.yaml can't limit it. (Power
    # users who want to limit the scope can use the command-line `scan` instead.)
    cfg = Config()
    if os.path.exists("config.yaml"):
        try:
            cfg = Config.load("config.yaml")
        except Exception:
            cfg = Config()
    cfg.output.detail = "full"
    cfg.output.save_attachments = True
    cfg.email.since_days = 0        # all time, not just the last 2 years
    cfg.email.mailbox = "ALL"       # every folder: inbox, sent, archive, spam…
    cfg.email.max_messages = 50000  # effectively "everything" for most mailboxes
    return cfg


# --- routes ---------------------------------------------------------------

@app.route("/")
def index():
    accounts = []
    if os.path.exists(_acct_path()):
        try:
            accounts = load_accounts(_acct_path())
        except Exception:
            accounts = []

    with _scan_lock:
        running = _state_for(_user())["running"]

    rows = ""
    for a in accounts:
        folder = a.safe_name()
        report = os.path.join(_out_dir(), folder, "report.json")
        if os.path.exists(report):
            try:
                d = json.load(open(report))
                if d.get("scan_error"):
                    summary = '<span style="color:var(--red)">⚠ scan failed — click profile</span>'
                elif d.get("service_count", 0) == 0 and d.get("sensitive_count", 0) == 0:
                    summary = '<span class="warn">0 found — see profile for why</span>'
                else:
                    summary = (f'{d.get("service_count",0)} services · '
                               f'{d.get("sensitive_count",0)} findings')
            except Exception:
                summary = "scanned"
            link = f'<a href="{url_for("profile", folder=folder)}">Open profile →</a>'
        else:
            summary = '<span class="muted">not scanned yet</span>'
            link = ""
        em = escape(a.email)
        disabled = "disabled" if running else ""
        actions = (
            f'{link} '
            f'<form method="post" action="/accounts/rescan" style="display:inline">'
            f'<input type="hidden" name="email" value="{em}">'
            f'<button class="secondary" {disabled}>Re-scan</button></form> '
            f'<button class="secondary" type="button" '
            f'onclick="document.getElementById(\'edit-{folder}\').style.display=\'block\'">'
            f'Edit</button> '
            f'<form method="post" action="/accounts/delete" style="display:inline" '
            f'onsubmit="return confirm(\'Remove {em}? This also deletes its scan folder.\')">'
            f'<input type="hidden" name="email" value="{em}">'
            f'<button class="secondary">Delete</button></form>'
            f'<div id="edit-{folder}" style="display:none;margin-top:8px">'
            f'<form method="post" action="/accounts/edit">'
            f'<input type="hidden" name="original_email" value="{em}">'
            f'<input name="email" value="{em}" style="min-width:200px"> '
            f'<input name="password" placeholder="new app password" style="min-width:180px"> '
            f'<button>Save</button></form></div>'
        )
        rows += (f"<tr><td>{em}</td><td>{summary}</td><td>{actions}</td></tr>")
    if not rows:
        rows = '<tr><td colspan="3" class="muted">No accounts yet — add one below.</td></tr>'

    scan_btn = ('<button id="scanbtn" %s>Scan all accounts</button>'
                % ("disabled" if running else ""))

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
      <span class="muted">Saved to {escape(_acct_path())} on this computer.</span></p>
    </form></div>

    <div class="card"><h2>Scan</h2>
    <p class="muted">Reads each inbox read-only and builds a profile with
    everything found — services, sensitive items, and saved files/pictures.</p>
    <form method="post" action="/scan" onsubmit="setTimeout(poll,400)">{scan_btn}</form>
    <div id="progress" style="margin-top:12px"></div>
    </div>

    <p><a href="/export">⇩ Export what you choose →</a> &nbsp;
    <form method="post" action="/update" style="display:inline"
      onsubmit="return confirm('Download and install the latest version? Your accounts and scans are kept.')">
      <button class="secondary">⟳ Update app</button></form>
    &nbsp;<span class="muted">Most providers need an <b>app password</b>.
    Credentials live in {escape(_acct_path())} — keep it private.</span></p>

    <script>
    function bar(a){{
      var pct = a.total ? Math.min(100, Math.round(100*a.done/a.total)) : (a.status==='scanning'?3:0);
      var eta = '';
      if(a.eta_s!=null && a.status==='scanning'){{
        var m=Math.floor(a.eta_s/60), s=Math.round(a.eta_s%60);
        eta = ' · ETA '+(m>0?m+'m ':'')+s+'s';
      }}
      var col = a.status && a.status.indexOf('failed')===0 ? 'var(--red)' :
                (a.status==='scanning'?'var(--amber)':'var(--grn)');
      var label = a.status && a.status.indexOf('failed')===0 ? a.status :
          (a.status==='scanning'
             ? (a.total? a.done+'/'+a.total+' msgs ('+pct+'%)'+eta : 'connecting…')
             : (a.status==='pending'?'queued':'done · '+a.services+' services, '+a.findings+' findings'));
      return '<div style="margin:8px 0"><div style="display:flex;justify-content:space-between">'
        +'<b>'+a.email+'</b><span class="muted">'+label+'</span></div>'
        +'<div style="height:12px;border:1px solid var(--grn2);border-radius:7px;overflow:hidden;background:#02110b">'
        +'<div style="height:100%;width:'+pct+'%;background:'+col+';box-shadow:0 0 10px '+col+';transition:width .4s"></div>'
        +'</div></div>';
    }}
    function poll(){{
      fetch('/scan/status').then(function(r){{return r.json()}}).then(function(d){{
        var el=document.getElementById('progress');
        if(!d.accounts.length){{el.innerHTML='';}}
        else{{el.innerHTML='<div class="card">'+d.accounts.map(bar).join('')+'</div>';}}
        var btn=document.getElementById('scanbtn'); if(btn) btn.disabled=d.running;
        if(d.running) setTimeout(poll,1000);
        else if(d.accounts.length) setTimeout(function(){{location.reload()}},1200);
      }}).catch(function(){{}});
    }}
    if({str(running).lower()}) poll();
    </script>
    """
    return render("Accounts", body)


@app.route("/scan/status")
def scan_status():
    import time
    from flask import jsonify
    with _scan_lock:
        st = _state_for(_user())
        running = st["running"]
        out = []
        for email in st["order"]:
            a = dict(st["accounts"][email])
            a["email"] = email
            eta = None
            if (a["status"] == "scanning" and a.get("total") and a.get("done")
                    and a.get("started")):
                elapsed = max(0.001, time.time() - a["started"])
                rate = a["done"] / elapsed            # msgs/sec
                if rate > 0:
                    eta = max(0, (a["total"] - a["done"]) / rate)
            a["eta_s"] = eta
            a.pop("started", None)
            out.append(a)
    return jsonify({"running": running, "accounts": out})


@app.route("/register", methods=["GET", "POST"])
def register():
    from .users import add_user, username_taken
    from .roasts import pick_roast
    msg = ""
    if request.method == "POST":
        u = request.form.get("username", "")
        pw = request.form.get("password", "")
        pw2 = request.form.get("password2", "")
        if pw != pw2:
            msg = "The two passwords don't match."
        elif username_taken(USERS_PATH, u):
            msg = pick_roast()          # rotating roast when the name is taken
        else:
            ok, m = add_user(USERS_PATH, u, pw)
            if ok:
                session["user"] = u.strip()
                session.permanent = True
                return redirect(url_for("index"))
            msg = m
    warn = f'<p class="warn">{escape(msg)}</p>' if msg else ""
    body = f"""
    <h1>Create your account</h1>
    <div class="card">
    <p class="muted">Each person gets their own private SpeedRunner — your own
    accounts and scans, locked to your login.</p>
    {warn}
    <form method="post" action="/register">
      <p><input name="username" placeholder="choose a username"
         style="min-width:260px" required></p>
      <p><input name="password" type="password" placeholder="password (min 6)"
         style="min-width:260px" required></p>
      <p><input name="password2" type="password" placeholder="repeat password"
         style="min-width:260px" required></p>
      <p><button>Create account</button></p>
    </form>
    <p class="muted">Already have one? <a href="/login">Sign in</a>.</p>
    <p class="muted">Usernames are unique — no two people can use the same one.</p>
    </div>"""
    return render("Create account", body)


@app.route("/login", methods=["GET", "POST"])
def login():
    from .users import verify
    msg = ""
    if request.method == "POST":
        name = verify(USERS_PATH, request.form.get("username", ""),
                      request.form.get("password", ""))
        if name:
            session["user"] = name
            session.permanent = True
            return redirect(url_for("index"))
        msg = "Wrong username or password."
    warn = f'<p class="warn">{escape(msg)}</p>' if msg else ""
    body = f"""
    <h1>Sign in</h1>
    <div class="card">
    {warn}
    <form method="post" action="/login">
      <p><input name="username" placeholder="username"
         style="min-width:260px" autofocus required></p>
      <p><input name="password" type="password" placeholder="password"
         style="min-width:260px" required></p>
      <p><button>Unlock</button></p>
    </form>
    <p class="muted">New here? <a href="/register">Create an account</a>. This is
    your SpeedRunner login — not your email password.</p></div>"""
    return render("Sign in", body)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/accounts/add", methods=["POST"])
def add_account():
    email = (request.form.get("email") or "").strip()
    password = (request.form.get("password") or "").strip()
    if email and password:
        add_or_update(_acct_path(), email, password)
    return redirect(url_for("index"))


@app.route("/accounts/edit", methods=["POST"])
def edit_account():
    original = (request.form.get("original_email") or "").strip()
    email = (request.form.get("email") or "").strip()
    password = (request.form.get("password") or "").strip()
    if original and email:
        # Keep the existing password if the field was left blank.
        if not password:
            for a in load_accounts(_acct_path()):
                if a.email.lower() == original.lower():
                    password = a.password
                    break
        add_or_update(_acct_path(), email, password, original_email=original)
    return redirect(url_for("index"))


@app.route("/accounts/delete", methods=["POST"])
def remove_account():
    import shutil
    email = (request.form.get("email") or "").strip()
    if email:
        # Remove the scan folder too, so stale data doesn't linger.
        from .accounts import Account
        folder = Account(email=email, password="").safe_name()
        delete_account(_acct_path(), email)
        shutil.rmtree(os.path.join(_out_dir(), folder), ignore_errors=True)
    return redirect(url_for("index"))


def _run_scan(accounts_path, output_dir, user, only_email=None):
    from .batch import run_batch, scan_one, write_index

    base = _load_base_config()
    progress = _make_progress(user)

    try:
        if only_email:
            accts = [a for a in load_accounts(accounts_path)
                     if a.email.lower() == only_email.lower()]
            for a in accts:
                acct_dir = os.path.join(output_dir, a.safe_name())
                scan_one(a, base, acct_dir, progress)
            # Rebuild the overview from every account's current report.
            summaries = []
            for a in load_accounts(accounts_path):
                rp = os.path.join(output_dir, a.safe_name(), "report.json")
                if os.path.exists(rp):
                    try:
                        d = json.load(open(rp))
                        summaries.append({"email": a.email, "folder": a.safe_name(),
                                          "services": d.get("service_count", 0),
                                          "sensitive": d.get("sensitive_count", 0),
                                          "status": "ok"})
                    except Exception:
                        pass
            write_index(output_dir, summaries)
        else:
            run_batch(accounts_path, base, output_dir, progress=progress)
    finally:
        with _scan_lock:
            _state_for(user)["running"] = False


def _start_scan(only_email=None):
    user = _user()
    accounts_path, output_dir = _acct_path(), _out_dir()
    with _scan_lock:
        st = _state_for(user)
        if not st["running"]:
            st["running"] = True
            st["accounts"] = {}
            st["order"] = []
            threading.Thread(
                target=_run_scan,
                args=(accounts_path, output_dir, user, only_email),
                daemon=True).start()


@app.route("/accounts/rescan", methods=["POST"])
def rescan_account():
    email = (request.form.get("email") or "").strip()
    if email:
        _start_scan(only_email=email)
    return redirect(url_for("index"))


@app.route("/scan", methods=["POST"])
def scan():
    _start_scan()
    return redirect(url_for("index"))


def _is_image(name: str) -> bool:
    return name.lower().rsplit(".", 1)[-1] in {"png", "jpg", "jpeg", "gif", "webp", "bmp"}


@app.route("/profile/<folder>")
def profile(folder):
    folder = os.path.basename(folder)  # prevent traversal
    acct_dir = os.path.join(_out_dir(), folder)
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

    # Personal info found (contact/identity), grouped and de-duplicated.
    pi = d.get("personal_info", {})
    labels = {"email_address": "Email addresses", "phone": "Phone numbers",
              "date_of_birth": "Dates of birth", "mailing_address": "Mailing addresses"}
    pi_html = ""
    for kind in ("email_address", "phone", "mailing_address", "date_of_birth"):
        items = pi.get(kind) or []
        if not items:
            continue
        lis = "".join(
            f"<li><code>{escape(str(it['value']))}</code>"
            + (f" <span class='muted'>×{it['count']}</span>" if it['count'] > 1 else "")
            + "</li>" for it in items)
        pi_html += f"<h3>{escape(labels.get(kind, kind))} <span class='badge'>{len(items)}</span></h3><ul>{lis}</ul>"
    if not pi_html:
        pi_html = ("<p class='muted'>No name/phone/address/DOB detected in this "
                   "inbox.</p>")

    # Best-guess "real" details (most-repeated value per field).
    bg = d.get("best_guess", {})
    def bg_row(lbl, item):
        if not item:
            return ""
        times = (f" <span class='muted'>(seen {item['count']}×)</span>"
                 if item.get("count", 0) > 1 else "")
        return (f"<tr><td>{escape(lbl)}</td>"
                f"<td><code>{escape(str(item['value']))}</code>{times}</td></tr>")
    bg_rows = (bg_row("Name", bg.get("name")) + bg_row("Email", bg.get("email"))
               + bg_row("Phone", bg.get("phone")) + bg_row("Home address", bg.get("address"))
               + bg_row("Date of birth", bg.get("dob")))
    bg_html = (f'<table><tr><th>Field</th><th>Most likely value</th></tr>{bg_rows}</table>'
               if bg_rows else "<p class='muted'>Not enough data to guess yet.</p>")

    # Email legitimacy (phishing/scam) section.
    susp = d.get("suspicious_emails", [])
    susp_html = ""
    for s in susp[:200]:
        color = "var(--red)" if s["verdict"] == "likely phishing" else "var(--amber)"
        reasons = "".join(f"<li>{escape(r)}</li>" for r in s.get("reasons", []))
        susp_html += (f'<div class="card" style="border-color:{color}">'
                      f'<b style="color:{color}">{escape(s["verdict"].upper())}</b> '
                      f'— from <code>{escape(s["from"])}</code>'
                      f'<div class="muted">{escape(s["subject"])}</div>'
                      f'<ul>{reasons}</ul></div>')
    if not susp_html:
        susp_html = "<p class='muted'>No suspicious or phishing emails detected.</p>"

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

    scanned_n = d.get("sources_scanned", 0)
    banner = ""
    if d.get("scan_error"):
        from .setup_help import get_setup_guide
        g = get_setup_guide(d.get("account") or folder)
        steps = "".join(f"<li>{escape(s)}</li>" for s in g["steps"])
        link = (f'<p>➜ <a href="{escape(g["url"])}" target="_blank" '
                f'rel="noopener">Open {escape(g["provider"])} settings</a></p>'
                if g.get("url") else "")
        note = f'<p class="muted">{escape(g["note"])}</p>' if g.get("note") else ""
        banner = (f'<div class="card" style="border-color:var(--red)">'
                  f'<b style="color:var(--red)">⚠ This scan failed.</b>'
                  f'<p>{escape(d["scan_error"])}</p>'
                  f'<hr style="border-color:var(--grn2)">'
                  f'<b>How to fix it for {escape(g["provider"])}:</b>'
                  f'{note}<ol>{steps}</ol>{link}'
                  f'<p class="muted">Then click <b>Re-scan</b> on the accounts '
                  f'page.</p></div>')
    elif scanned_n == 0:
        if d.get("protocol") == "pop3":
            banner = ('<div class="card" style="border-color:var(--amber)">'
                      '<b class="warn">Logged in, but the mailbox returned 0 '
                      'messages (POP3).</b>'
                      '<p class="muted">This account (NetZero/Juno-type) only '
                      'supports <b>POP3</b>, which can read <b>only the Inbox</b> '
                      '— not Sent, Archive, or any folders. So:</p>'
                      '<ul>'
                      '<li>If your mail is filed in <b>folders</b> or already read/'
                      'moved out of the Inbox, POP can\'t see it — only what\'s '
                      'sitting in the Inbox right now.</li>'
                      '<li>These free legacy providers often expose little or '
                      'nothing of stored webmail over POP.</li>'
                      '<li>Check the account\'s <b>webmail Inbox</b>: if it\'s empty '
                      '(mail is in folders), there\'s nothing for POP to return.</li>'
                      '</ul>'
                      '<p class="muted">A mainstream provider (Gmail/Yahoo/Outlook) '
                      'supports full-folder IMAP and scans completely.</p></div>')
        else:
            banner = ('<div class="card" style="border-color:var(--amber)">'
                      '<b class="warn">The login worked, but 0 messages were read.</b>'
                      '<p class="muted">The app already scans every folder and all '
                      'of time, so this usually means:</p>'
                      '<ul>'
                      '<li>This account genuinely has no mail in it, or</li>'
                      '<li>IMAP isn\'t fully enabled. For Gmail: Settings → '
                      'Forwarding and POP/IMAP → <b>Enable IMAP</b>. Yahoo/Outlook '
                      'need an <b>app password</b> too.</li>'
                      '</ul></div>')
    elif d.get("service_count", 0) == 0 and d.get("sensitive_count", 0) == 0:
        banner = (f'<div class="card" style="border-color:var(--amber)">'
                  f'<b class="warn">Read {scanned_n} messages but matched nothing.</b>'
                  f'<p class="muted">The detectors look for specific patterns. '
                  f'Try scanning more mail (mailbox <code>[Gmail]/All Mail</code> '
                  f'and <code>since_days: 0</code> in config.yaml).</p></div>')

    body = f"""
    <h1>{escape(d.get('account') or folder)}</h1>
    <p class="muted">Detail level: {escape(d.get('detail_level','full'))} ·
    {scanned_n} messages scanned ·
    <a href="{url_for('serve_file', folder=folder, path='report.md')}">raw report.md</a></p>
    {banner}

    <h2>Best guess — your real details</h2>
    <p class="muted">The value seen most consistently across this inbox wins, so
    you see the likely-real one first instead of a pile of candidates.</p>
    {bg_html}

    <h2>Email legitimacy <span class="badge">{d.get('suspicious_count',0)}</span></h2>
    <p class="muted">Every email was checked during the scan. These looked like
    phishing or spoofing — and their info was <b>excluded</b> from your profile
    below so fakes don't pollute it.</p>
    {susp_html}

    <h2>Personal info found <span class="badge">{d.get('personal_info_count',0)}</span></h2>
    <p class="muted">Contact &amp; identity details that appear in this inbox.
    Remove or secure anything you don't want stored in email.</p>
    {pi_html}

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
    directory = os.path.abspath(os.path.join(_out_dir(), folder))
    # send_from_directory guards against path traversal out of `directory`.
    return send_from_directory(directory, path)


def _all_reports():
    """Yield (account_email, folder, report_dict) for every scanned account."""
    if not os.path.isdir(_out_dir()):
        return
    for folder in sorted(os.listdir(_out_dir())):
        rp = os.path.join(_out_dir(), folder, "report.json")
        if os.path.isfile(rp):
            try:
                d = json.load(open(rp))
            except Exception:
                continue
            yield (d.get("account") or folder, folder, d)


@app.route("/master")
def master():
    accounts_seen = 0
    # Merge services across accounts, keyed by brand.
    services = {}   # key -> {brand, categories:set, accounts:set, messages:int}
    findings = []   # flattened, each tagged with its account
    sev_rank = {"high": 0, "medium": 1, "low": 2}

    for email, folder, d in _all_reports():
        accounts_seen += 1
        for cat, entries in (d.get("services_by_category") or {}).items():
            for e in entries:
                key = (e.get("brand") or "").lower() or f"{cat}:{id(e)}"
                s = services.setdefault(key, {"brand": e.get("brand", "?"),
                                              "categories": set(), "accounts": set(),
                                              "messages": 0})
                s["categories"].add(cat)
                s["accounts"].add(email)
                s["messages"] += e.get("message_count", 0)
        for h in d.get("sensitive_findings", []):
            findings.append({**h, "account": email})

    # Stats
    high = sum(1 for f in findings if f.get("severity") == "high")
    stats = (f'<div class="card" style="display:flex;gap:26px;flex-wrap:wrap">'
             f'<div><div class="badge">accounts</div><h2 style="margin:.2em 0">{accounts_seen}</h2></div>'
             f'<div><div class="badge">services</div><h2 style="margin:.2em 0">{len(services)}</h2></div>'
             f'<div><div class="badge">findings</div><h2 style="margin:.2em 0">{len(findings)}</h2></div>'
             f'<div><div class="badge">high-risk</div><h2 style="margin:.2em 0;color:var(--red)">{high}</h2></div>'
             f'</div>')

    if accounts_seen == 0:
        return render("Master", "<h1>Master view</h1>" + stats +
                      '<p class="muted">No scanned accounts yet. Add accounts and '
                      'run a scan first.</p>')

    # Services table (sorted by how many accounts use them, then name)
    svc_rows = ""
    for s in sorted(services.values(),
                    key=lambda v: (-len(v["accounts"]), v["brand"].lower())):
        accts = ", ".join(sorted(s["accounts"]))
        cats = ", ".join(sorted(s["categories"]))
        svc_rows += (f"<tr><td><b>{escape(s['brand'])}</b></td>"
                     f"<td>{escape(cats)}</td>"
                     f"<td>{s['messages']}</td>"
                     f"<td class='muted'>{escape(accts)}</td></tr>")
    svc_table = (f"<table><tr><th>Service</th><th>Category</th><th>Msgs</th>"
                 f"<th>Found in account(s)</th></tr>{svc_rows}</table>")

    # Findings table (sorted by severity)
    findings.sort(key=lambda f: sev_rank.get(f.get("severity"), 9))
    find_rows = ""
    for f in findings:
        color = {"high": "var(--red)", "medium": "var(--amber)"}.get(
            f.get("severity"), "var(--grn2)")
        find_rows += (f"<tr><td style='color:{color}'>{escape(f.get('severity','').upper())}</td>"
                      f"<td>{escape(f.get('kind',''))}</td>"
                      f"<td><code>{escape(str(f.get('value','')))}</code></td>"
                      f"<td>{escape(f.get('account',''))}</td>"
                      f"<td class='muted'>{escape(f.get('location',''))}</td></tr>")
    find_table = (f"<table><tr><th>Severity</th><th>Type</th><th>Value</th>"
                  f"<th>Account</th><th>Where</th></tr>{find_rows}</table>"
                  if find_rows else "<p class='muted'>No sensitive items found.</p>")

    body = f"""
    <h1>Master view — everything in one place</h1>
    {stats}
    <h2>All services &amp; accounts ({len(services)})</h2>
    <p class="muted">Merged across every email. "Found in account(s)" shows which
    inbox each service appeared in — handy for spotting the same store across
    multiple emails.</p>
    {svc_table}
    <h2>All sensitive findings ({len(findings)})</h2>
    {find_table}
    """
    return render("Master", body)


@app.route("/search")
def search():
    q = (request.args.get("q") or "").strip()
    results_html = ""
    total = 0

    if q:
        ql = q.lower()
        for email, folder, d in _all_reports():
            svc_hits, find_hits = [], []

            for cat, entries in (d.get("services_by_category") or {}).items():
                for e in entries:
                    hay = " ".join([e.get("brand", ""), cat,
                                    " ".join(e.get("domains", [])),
                                    " ".join(e.get("sample_subjects", []))]).lower()
                    if ql in hay:
                        svc_hits.append(f"{escape(e.get('brand',''))} "
                                        f"<span class='muted'>({escape(cat)})</span>")

            for h in d.get("sensitive_findings", []):
                hay = " ".join([h.get("kind", ""), str(h.get("value", "")),
                                h.get("location", ""), h.get("advice", "")]).lower()
                if ql in hay:
                    find_hits.append(
                        f"<tr><td>{escape(h['kind'])}</td>"
                        f"<td><code>{escape(str(h['value']))}</code></td>"
                        f"<td>{escape(h['location'])}</td></tr>")

            if svc_hits or find_hits:
                total += len(svc_hits) + len(find_hits)
                block = f'<h3><a href="{url_for("profile", folder=folder)}">{escape(email)}</a></h3>'
                if svc_hits:
                    block += "<p>Services: " + ", ".join(svc_hits) + "</p>"
                if find_hits:
                    block += ("<table><tr><th>Type</th><th>Value</th><th>Where</th></tr>"
                              + "".join(find_hits) + "</table>")
                results_html += f'<div class="card">{block}</div>'

        if not results_html:
            results_html = f'<p class="muted">No matches for “{escape(q)}”.</p>'
        else:
            results_html = (f'<p class="muted">{total} match(es) for '
                            f'“{escape(q)}”.</p>' + results_html)

    body = f"""
    <h1>Search everything</h1>
    <form method="get" action="/search">
      <input name="q" value="{escape(q)}" placeholder="card, address, a store name, SSN…"
        style="min-width:300px" autofocus>
      <button>Search</button>
    </form>
    <p class="muted">Searches every scanned account's services and findings.
    Try a store name, “card”, “password”, part of your address, etc.</p>
    {results_html}
    """
    return render("Search", body)


@app.route("/recover")
def recover():
    from .recovery import recovery_url

    accounts = []
    if os.path.exists(_acct_path()):
        try:
            accounts = load_accounts(_acct_path())
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


@app.route("/update", methods=["POST"])
def update_app():
    from .update import update
    ok, msg = update()
    note = ("Restart the app (close this window / press Ctrl+C in the black "
            "window, then open it again) to use the new version."
            if ok and "Updated" in msg else "")
    color = "var(--grn)" if ok else "var(--red)"
    body = f"""
    <h1>Update</h1>
    <div class="card">
      <p style="color:{color}">{escape(msg)}</p>
      <p class="muted">{escape(note)}</p>
      <p><a href="/">← back to accounts</a></p>
    </div>"""
    return render("Update", body)


@app.route("/analyze", methods=["GET", "POST"])
def analyze():
    from email import message_from_string
    from email.utils import parseaddr
    from .phishing import analyze_email

    pasted = ""
    result_html = ""
    if request.method == "POST":
        pasted = request.form.get("email", "")
        from_addr = from_name = subject = reply_to = auth = ""
        body = pasted
        # If it looks like a full email (has headers), parse them.
        if "\n" in pasted and (":" in pasted.split("\n", 1)[0]):
            try:
                msg = message_from_string(pasted)
                from_name, from_addr = parseaddr(msg.get("From", ""))
                _n, reply_to = parseaddr(msg.get("Reply-To", ""))
                auth = " ".join(msg.get_all("Authentication-Results") or [])
                subject = msg.get("Subject", "") or ""
                if msg.is_multipart():
                    parts = [p.get_payload(decode=True) or b"" for p in msg.walk()
                             if p.get_content_type() in ("text/plain", "text/html")]
                    body = b"\n".join(parts).decode("utf-8", "replace")
                else:
                    body = (msg.get_payload(decode=True) or b"").decode("utf-8", "replace") or pasted
            except Exception:
                pass
        # Also accept a simple "From: x@y.com" line even without full headers.
        if not from_addr:
            m = re.search(r"from[:\s]+([^\s<>]+@[^\s<>]+)", pasted, re.IGNORECASE)
            if m:
                from_addr = m.group(1)

        v = analyze_email(from_addr, from_name, subject, body,
                          reply_to=reply_to, auth_results=auth)
        color = {"likely phishing": "var(--red)", "suspicious": "var(--amber)",
                 "legit": "var(--grn)"}.get(v.label, "var(--grn)")
        reasons = "".join(f"<li>{escape(r)}</li>" for r in v.reasons)
        result_html = (f'<div class="card" style="border-color:{color}">'
                       f'<h2 style="color:{color};margin-top:0">{escape(v.label.upper())}</h2>'
                       f'<p class="muted">Sender: <code>{escape(from_addr or "unknown")}</code>'
                       f'{" · subject: " + escape(subject) if subject else ""}</p>'
                       f'<ul>{reasons}</ul></div>')

    body_html = f"""
    <h1>Analyze an email</h1>
    <p class="muted">Paste a whole email (best: use "Show original" / "View
    source" in your mail app to include the headers), or just the From address
    and text. It checks for phishing/spoofing signals — all offline.</p>
    <form method="post" action="/analyze">
      <textarea name="email" rows="12" style="width:100%;background:#02110b;
        color:var(--grn);border:1px solid var(--grn2);border-radius:8px;
        padding:10px;font-family:inherit">{escape(pasted)}</textarea>
      <p><button>Analyze</button></p>
    </form>
    {result_html}
    """
    return render("Analyze", body_html)


@app.route("/export")
def export_page():
    accts = [(email, folder) for email, folder, _d in _all_reports()]
    if not accts:
        return render("Export", "<h1>Export</h1>"
                      "<p class='muted'>Nothing to export yet — scan some "
                      "accounts first.</p>")
    checks = ""
    for email, folder in accts:
        checks += (f'<label style="display:block;margin:4px 0">'
                   f'<input type="checkbox" name="acct" value="{escape(folder)}" checked> '
                   f'{escape(email)}</label>')
    body = f"""
    <h1>Export</h1>
    <p class="muted">Pick exactly what you want to take out. You'll get one
    <code>.zip</code> file with your choices.</p>
    <form method="post" action="/export/download">
      <div class="card"><h2>Accounts</h2>{checks}</div>
      <div class="card"><h2>What to include</h2>
        <label style="display:block"><input type="checkbox" name="inc" value="services" checked> Services list (CSV)</label>
        <label style="display:block"><input type="checkbox" name="inc" value="findings" checked> Sensitive findings (CSV)</label>
        <label style="display:block"><input type="checkbox" name="inc" value="attachments" checked> Pictures &amp; files</label>
        <label style="display:block"><input type="checkbox" name="inc" value="reports"> Full reports (report.md + report.json)</label>
        <label style="display:block;margin-top:6px"><input type="checkbox" name="inc" value="combined" checked> Combined CSVs across all chosen accounts</label>
      </div>
      <button>⇩ Build &amp; download ZIP</button>
    </form>
    <p class="muted">The ZIP can contain real personal info and images — save it
    somewhere safe and delete it when you're done.</p>
    """
    return render("Export", body)


def _services_rows(d):
    rows = [("brand", "category", "domains", "messages")]
    for cat, entries in (d.get("services_by_category") or {}).items():
        for e in entries:
            rows.append((e.get("brand", ""), cat,
                         " ".join(e.get("domains", [])), e.get("message_count", 0)))
    return rows


def _findings_rows(d):
    rows = [("severity", "type", "value", "where", "advice")]
    for h in d.get("sensitive_findings", []):
        rows.append((h.get("severity", ""), h.get("kind", ""), h.get("value", ""),
                     h.get("location", ""), h.get("advice", "")))
    return rows


def _csv_bytes(rows):
    import csv
    import io
    buf = io.StringIO()
    csv.writer(buf).writerows(rows)
    return buf.getvalue().encode("utf-8")


@app.route("/export/download", methods=["POST"])
def export_download():
    import io
    import zipfile

    chosen = set(request.form.getlist("acct"))
    include = set(request.form.getlist("inc"))
    if not chosen or not include:
        return redirect(url_for("export_page"))

    mem = io.BytesIO()
    combined_find = [("account", "severity", "type", "value", "where")]
    combined_svc = [("account", "brand", "category", "domains", "messages")]

    with zipfile.ZipFile(mem, "w", zipfile.ZIP_DEFLATED) as z:
        for email, folder, d in _all_reports():
            if folder not in chosen:
                continue
            acct_dir = os.path.join(_out_dir(), folder)

            if "services" in include:
                z.writestr(f"{folder}/services.csv", _csv_bytes(_services_rows(d)))
            if "findings" in include:
                z.writestr(f"{folder}/findings.csv", _csv_bytes(_findings_rows(d)))
            if "reports" in include:
                for fn in ("report.md", "report.json"):
                    fp = os.path.join(acct_dir, fn)
                    if os.path.isfile(fp):
                        z.write(fp, f"{folder}/{fn}")
            if "attachments" in include:
                att_dir = os.path.join(acct_dir, "attachments")
                if os.path.isdir(att_dir):
                    for name in os.listdir(att_dir):
                        fp = os.path.join(att_dir, name)
                        if os.path.isfile(fp):
                            z.write(fp, f"{folder}/attachments/{name}")
            if "combined" in include:
                for r in _findings_rows(d)[1:]:
                    combined_find.append((email, r[0], r[1], r[2], r[3]))
                for r in _services_rows(d)[1:]:
                    combined_svc.append((email, r[0], r[1], r[2], r[3]))

        if "combined" in include:
            z.writestr("all_findings.csv", _csv_bytes(combined_find))
            z.writestr("all_services.csv", _csv_bytes(combined_svc))

    mem.seek(0)
    return send_file(mem, mimetype="application/zip", as_attachment=True,
                     download_name="speedrunner_export.zip")


def _lan_ip():
    """Best-effort local network IP of this machine (for phone access)."""
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))   # no packets sent; just picks the route
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return None


def _all_ipv4():
    """All IPv4 addresses on this machine, so the Tailscale/VPN one shows up."""
    import socket
    ips = set()
    primary = _lan_ip()
    if primary:
        ips.add(primary)
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except Exception:
        pass
    return [ip for ip in ips if not ip.startswith("127.")]


def _is_tailscale(ip):
    # Tailscale hands out addresses in the 100.64.0.0/10 CGNAT range.
    try:
        a, b = (int(x) for x in ip.split(".")[:2])
        return a == 100 and 64 <= b <= 127
    except Exception:
        return False


def main():
    print(r"""
   ___                   _ ___
  / __|_ __  ___ ___ __| | _ \_  _ _ _  _ _  ___ _ _
  \__ \ '_ \/ -_) -_) _` |   / || | ' \| ' \/ -_) '_|
  |___/ .__/\___\___\__,_|_|_\\_,_|_||_|_||_\___|_|
      |_|   SPEEDRUNNER  //  local personal-data recon
""")
    # Phone/LAN mode: set PIS_LAN=1 to let other devices on your Wi-Fi (your
    # phone) reach the app at http://<this-computer-ip>:5000.
    lan = os.environ.get("PIS_LAN", "").strip() in ("1", "true", "yes", "lan")
    host = "0.0.0.0" if lan else "127.0.0.1"
    local_url = "http://127.0.0.1:5000"

    if lan:
        print(f"  [+] on this computer: {local_url}")
        addrs = _all_ipv4()
        if addrs:
            print("  [+] on your PHONE, open one of these:")
            for ip in sorted(addrs, key=lambda x: (not _is_tailscale(x), x)):
                tag = ("  <- Tailscale: works from ANYWHERE (phone needs "
                       "Tailscale on)" if _is_tailscale(ip)
                       else "  (same Wi-Fi only)")
                print(f"        http://{ip}:5000{tag}")
        else:
            print("  [+] on your PHONE (same Wi-Fi): http://<this-computer-ip>:5000")
        print("  [!] Anyone who can reach that address can use the app (it holds")
        print("      your data). Keep it to your own devices; close it (Ctrl+C)")
        print("      when done.")
    else:
        print(f"  [+] console online at {local_url}")
        print("  [+] 100% local. To open it on your phone, set PIS_LAN=1.")
    print("  [+] Ctrl+C to stop.")

    try:
        threading.Timer(1.0, lambda: webbrowser.open(local_url)).start()
    except Exception:
        pass
    app.run(host=host, port=5000, debug=False)


if __name__ == "__main__":
    main()
