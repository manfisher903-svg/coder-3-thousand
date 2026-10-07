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
                   send_from_directory, url_for)

from .accounts import (add_or_update, delete_account, load_accounts,
                       save_accounts)
from .config import Config

ACCOUNTS_PATH = os.environ.get("PIS_ACCOUNTS", "accounts.txt")
OUTPUT_DIR = os.environ.get("PIS_OUTPUT", "inventory")

app = Flask(__name__)

# Scan progress state (single run at a time).
# accounts: email -> {done,total,status,started,services,findings}
_scan_state = {"running": False, "accounts": {}, "order": []}
_scan_lock = threading.Lock()


def _progress_event(ev: dict) -> None:
    """Update shared scan state from a batch progress event."""
    import time
    with _scan_lock:
        accts = _scan_state["accounts"]
        email = ev.get("email")
        kind = ev.get("event")
        if email and email not in accts:
            accts[email] = {"done": 0, "total": None, "status": "pending",
                            "started": None, "services": 0, "findings": 0}
            _scan_state["order"].append(email)
        if kind == "start":
            accts[email].update(status="scanning", started=time.time())
        elif kind == "progress":
            accts[email].update(done=ev.get("done", 0), total=ev.get("total"),
                                status="scanning")
        elif kind == "done":
            accts[email].update(status=ev.get("status", "ok"),
                                services=ev.get("services", 0),
                                findings=ev.get("sensitive", 0))


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
<a href="/recover">▸ recover</a>
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
      <span class="muted">Saved to {escape(ACCOUNTS_PATH)} on this computer.</span></p>
    </form></div>

    <div class="card"><h2>Scan</h2>
    <p class="muted">Reads each inbox read-only and builds a profile with
    everything found — services, sensitive items, and saved files/pictures.</p>
    <form method="post" action="/scan" onsubmit="setTimeout(poll,400)">{scan_btn}</form>
    <div id="progress" style="margin-top:12px"></div>
    </div>

    <p><a href="/export">⇩ Export what you choose →</a> &nbsp;
    <span class="muted">Most providers need an <b>app password</b>. Credentials
    live in {escape(ACCOUNTS_PATH)} — keep it private.</span></p>

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
        running = _scan_state["running"]
        out = []
        for email in _scan_state["order"]:
            a = dict(_scan_state["accounts"][email])
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


@app.route("/accounts/add", methods=["POST"])
def add_account():
    email = (request.form.get("email") or "").strip()
    password = (request.form.get("password") or "").strip()
    if email and password:
        add_or_update(ACCOUNTS_PATH, email, password)
    return redirect(url_for("index"))


@app.route("/accounts/edit", methods=["POST"])
def edit_account():
    original = (request.form.get("original_email") or "").strip()
    email = (request.form.get("email") or "").strip()
    password = (request.form.get("password") or "").strip()
    if original and email:
        # Keep the existing password if the field was left blank.
        if not password:
            for a in load_accounts(ACCOUNTS_PATH):
                if a.email.lower() == original.lower():
                    password = a.password
                    break
        add_or_update(ACCOUNTS_PATH, email, password, original_email=original)
    return redirect(url_for("index"))


@app.route("/accounts/delete", methods=["POST"])
def remove_account():
    import shutil
    email = (request.form.get("email") or "").strip()
    if email:
        # Remove the scan folder too, so stale data doesn't linger.
        from .accounts import Account
        folder = Account(email=email, password="").safe_name()
        delete_account(ACCOUNTS_PATH, email)
        shutil.rmtree(os.path.join(OUTPUT_DIR, folder), ignore_errors=True)
    return redirect(url_for("index"))


def _run_scan(only_email: str = None):
    from .batch import run_batch, scan_one, write_index

    base = _load_base_config()
    progress = _progress_event

    try:
        if only_email:
            accts = [a for a in load_accounts(ACCOUNTS_PATH)
                     if a.email.lower() == only_email.lower()]
            for a in accts:
                acct_dir = os.path.join(OUTPUT_DIR, a.safe_name())
                scan_one(a, base, acct_dir, progress)
            # Rebuild the overview from every account's current report.
            summaries = []
            for a in load_accounts(ACCOUNTS_PATH):
                rp = os.path.join(OUTPUT_DIR, a.safe_name(), "report.json")
                if os.path.exists(rp):
                    try:
                        d = json.load(open(rp))
                        summaries.append({"email": a.email, "folder": a.safe_name(),
                                          "services": d.get("service_count", 0),
                                          "sensitive": d.get("sensitive_count", 0),
                                          "status": "ok"})
                    except Exception:
                        pass
            write_index(OUTPUT_DIR, summaries)
        else:
            run_batch(ACCOUNTS_PATH, base, OUTPUT_DIR, progress=progress)
    finally:
        with _scan_lock:
            _scan_state["running"] = False


@app.route("/accounts/rescan", methods=["POST"])
def rescan_account():
    email = (request.form.get("email") or "").strip()
    with _scan_lock:
        if not _scan_state["running"] and email:
            _scan_state["running"] = True
            _scan_state["accounts"] = {}
            _scan_state["order"] = []
            threading.Thread(target=_run_scan, kwargs={"only_email": email},
                             daemon=True).start()
    return redirect(url_for("index"))


@app.route("/scan", methods=["POST"])
def scan():
    with _scan_lock:
        if not _scan_state["running"]:
            _scan_state["running"] = True
            _scan_state["accounts"] = {}
            _scan_state["order"] = []
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


def _all_reports():
    """Yield (account_email, folder, report_dict) for every scanned account."""
    if not os.path.isdir(OUTPUT_DIR):
        return
    for folder in sorted(os.listdir(OUTPUT_DIR)):
        rp = os.path.join(OUTPUT_DIR, folder, "report.json")
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
            acct_dir = os.path.join(OUTPUT_DIR, folder)

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


def main():
    url = "http://127.0.0.1:5000"
    print(r"""
   ___                   _ ___
  / __|_ __  ___ ___ __| | _ \_  _ _ _  _ _  ___ _ _
  \__ \ '_ \/ -_) -_) _` |   / || | ' \| ' \/ -_) '_|
  |___/ .__/\___\___\__,_|_|_\\_,_|_||_|_||_\___|_|
      |_|   SPEEDRUNNER  //  local personal-data recon
""")
    print(f"  [+] console online at {url}")
    print("  [+] 100% local — nothing leaves this machine. Ctrl+C to stop.")
    try:
        threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    except Exception:
        pass
    app.run(host="127.0.0.1", port=5000, debug=False)


if __name__ == "__main__":
    main()
