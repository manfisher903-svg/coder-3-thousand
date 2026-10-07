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
3. **Sensitive values are redacted by default.** Card numbers show as
   `•••• 1234`, etc. You can raise the detail level, but:
4. **Crypto recovery/seed phrases are never written to output — ever.** The tool
   only tells you *that* one appears to be in a given message so you can go move
   it somewhere safe (ideally offline / a hardware wallet). If a seed phrase is
   sitting in your email, that is itself a problem worth fixing.
5. **Output is written with locked-down permissions** (`0700` dir, `0600`
   files) and can be encrypted.

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

For Gmail/most providers you must create an **app password** (not your normal
password) and, for Gmail, enable IMAP. Put it in the config, or better, in the
`PIS_EMAIL_PASSWORD` environment variable so it never touches disk.

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
