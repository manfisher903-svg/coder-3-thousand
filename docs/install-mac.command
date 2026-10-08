#!/bin/bash
# ============================================================
#  SpeedRunner - one-click installer for macOS.
#  Give this ONE file to someone. They double-click it (in Finder)
#  and it downloads the latest SpeedRunner, installs it to their
#  home folder, and launches it. It auto-updates on every start.
#
#  First time only: if macOS says "unidentified developer", the
#  person right-clicks the file -> Open -> Open.
# ============================================================
set -u
APPDIR="$HOME/SpeedRunner"
URL="https://github.com/manfisher903-svg/coder-3-thousand/archive/refs/heads/claude/personal-info-scanner-rwixso.zip"

# --- find Python 3 ---
PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo
  echo "  SpeedRunner needs Python 3 (a free, one-time install)."
  echo "  Opening the download page..."
  open "https://www.python.org/downloads/" 2>/dev/null || true
  echo "  Install it, then double-click this installer again."
  read -n 1 -s -r -p "  Press any key to close."
  echo
  exit 1
fi

if [ ! -f "$APPDIR/scanner/app.py" ]; then
  echo
  echo "  Installing SpeedRunner to: $APPDIR"
  echo "  Downloading the latest version..."
  tmp="$(mktemp -d)"
  if ! curl -fsSL "$URL" -o "$tmp/speedrunner.zip"; then
    echo "  Download failed. Check the internet connection and try again."
    read -n 1 -s -r -p "  Press any key to close."
    exit 1
  fi
  unzip -q "$tmp/speedrunner.zip" -d "$tmp"
  inner="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
  mkdir -p "$APPDIR"
  cp -R "$inner"/* "$APPDIR"/
  rm -rf "$tmp"
  echo "  Installed."
fi

cd "$APPDIR" || exit 1
exec bash "$APPDIR/run_app.sh"
