# Personal Info Scanner

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

## Install

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
