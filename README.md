# SpeedRunner

_(a.k.a. Personal Info Scanner)_

A **local-only** tool that scans your own email and files to build an
**inventory** of your personal information: which stores and services you have
accounts with, your insurances, subscriptions, and where sensitive items
(bank, card, ID numbers, possible crypto recovery phrases) are sitting.

It is built for **personal data hygiene**: knowing what you have and where, so
you can clean it up, secure it, or hand it to someone in an emergency.

## Design principles (read these)

This tool is deliberately conservative about secrets:

1. **Everything runs on your machine.** The only network connection it makes is
   a read-only IMAP login to *your* mail server with *your* credentials. Nothing
   is uploaded anywhere.
2. **It inventories, it does not hoard.** The goal is a map of *what* you have
   and *where* it lives — not a single file containing all your secrets. A file
   like that is the single most dangerous thing you could create: lose the
   laptop and you lose everything at once.
3. **It shows you everything by default.** At the default `full` detail level
   the report contains every detected value exactly as found — card numbers,
   passwords, keys, and crypto seed phrases included. It's your data; the tool
   does not hide it from you. (You can set `--detail partial` or `redact` if you
   ever want masked output, e.g. to share a report.)
4. **Because the report holds real secrets, protect it.** Output is written with
   locked-down permissions (`0700` dir, `0600` files), can be AES-GCM encrypted
   with `encrypt_passphrase`, and should be deleted when you're done. If a seed
   phrase shows up in your email, consider moving it offline afterward.

## SpeedRunner — the app (easiest way to use it)

Instead of typing commands, you can open it like an app in your browser:

```bash
pip install -r requirements.txt
python -m scanner.app
```

…or just double-click **`run_app.sh`** (Mac/Linux) or **`run_app.bat`**
(Windows). It opens `http://127.0.0.1:5000` in your browser. Everything runs on
your own computer — the server only listens on localhost, nothing is uploaded.

In the app you can:

- **Manage accounts** — add with a form, **edit** an email/password in place,
  **delete** an account (its scan folder is removed too), and **re-scan a single
  account** without redoing the others.
- **Scan all accounts** with one button.
- **Search everything** — one box searches every scanned account's services and
  findings at once (a store name, "card", "password", part of your address…)
  and links each hit to the account it came from.
- **Master view** — all accounts merged into one page: every service
  de-duplicated (with which inboxes it appeared in) and every sensitive finding
  in one table sorted by risk, with a stats row (accounts / services / findings
  / high-risk).
- **Open each account's profile** to see its services, all findings (shown in
  full), and the actual **pictures/files** it saved, right on the page.
- **Recover access** — a page with the official password-reset link for each of
  your providers, to get back into accounts you're locked out of.

> Note on getting back into old accounts: the app does **not** try to guess or
> brute-force passwords — that doesn't work on modern email (a few wrong tries
> locks the account) and is how account-takeover attacks work. The **Recover
> access** page uses each provider's official reset flow instead, which is the
> reliable way back in even when you've forgotten the password entirely.

## Install (command-line use)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## Configure

Copy the example config and fill in your own mail account:

```bash
cp config.example.yaml config.yaml
$EDITOR config.yaml
```

### Works with any email provider

You only need two things: your **email address** and an **app password**. The
tool figures out the IMAP server for you — Gmail, Yahoo, Outlook/Hotmail,
iCloud, AOL, Proton (via Bridge), GMX, Zoho, Fastmail, Yandex, Comcast, AT&T,
and basically any other provider or custom domain. Detection happens in this
order:

1. A built-in list of common providers (instant, offline).
2. Mozilla's autoconfig database (covers thousands of providers / business
   domains).
3. Smart guesses (`imap.<domain>`, `mail.<domain>`) verified by connecting.

So in `config.yaml` you normally leave `host` blank and just set `username`.
Preview what it will use for your address without scanning:

```bash
python -m scanner.cli providers --email you@somewhere.com
python -m scanner.cli providers              # list the built-in ones
```

**App passwords:** most providers (Gmail, Yahoo, Outlook, iCloud, AOL…) require
an *app password* rather than your normal login, and Gmail also needs IMAP
turned on. Create one in your provider's account-security settings, then put it
in `config.yaml` as `password:` — or better, in the `PIS_EMAIL_PASSWORD`
environment variable so it never touches disk. (Proton requires the Proton
Bridge app running locally.)

Then run:

```bash
python -m scanner.cli scan --config config.yaml --output ./inventory
```

## Run

```bash
# Scan email only, last 2 years, write a redacted inventory report
python -m scanner.cli scan --config config.yaml --output ./inventory

# Also scan a folder of local files
python -m scanner.cli scan --config config.yaml --files ~/Documents --output ./inventory

# See what categories/detectors exist
python -m scanner.cli detectors
```

Open `inventory/report.md` (human-readable) or `inventory/report.json`
(machine-readable) when it finishes.

## Scanning many accounts at once (batch mode)

If you have several email accounts, list them in one file and scan them all in
one go — each account gets its own profile folder and report.

```bash
cp accounts.example.yaml accounts.yaml   # then fill in your accounts
python -m scanner.cli scan-all --accounts accounts.yaml --output ./inventory
```

The accounts file can be YAML or plain lines (`email,password` per line). Each
account needs its own app password. Output looks like:

```
inventory/
  index.md                     # overview table of every account
  you_at_gmail.com/report.md   # full profile for this account
  you_at_yahoo.com/report.md
  you_at_netzero.net/report.md
```

`index.md` is a summary table (accounts × services × findings) linking to each
report. One account failing (wrong password, IMAP off) doesn't stop the rest —
its status is shown in the table.

> The accounts file contains your passwords. It is git-ignored, but keep it
> private and delete it when done — or set `encrypt_passphrase` in `config.yaml`
> to encrypt each account's report.

## What it produces

- **Services & accounts index** — grouped by category (shopping, banking,
  insurance, crypto, subscriptions, utilities, travel, health, government…),
  with the sender and a sample subject line so you can recognize each one.
- **Sensitive findings** — redacted, with location (which message/file) and a
  recommended action.
- **Attachments of interest** — optionally saved to the output directory when
  `--save-attachments` is passed and the message looks personal.

## Scope & safety

Only point this at accounts and machines **you own or are authorized to
access**. It is a personal auditing tool, not a surveillance tool.
