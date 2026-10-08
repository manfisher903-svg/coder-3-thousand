#!/usr/bin/env bash
# Double-click or run this to launch SpeedRunner (opens in your browser).
# It auto-updates to the latest version first (your accounts & scans are kept).
cd "$(dirname "$0")" || exit 1

PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo "Python 3 is not installed. Opening the download page..."
  open "https://www.python.org/downloads/" 2>/dev/null || \
    xdg-open "https://www.python.org/downloads/" 2>/dev/null || true
  echo "Install Python 3, then run this again."
  exit 1
fi

"$PY" -m pip install -q -r requirements.txt
echo "Checking for updates..."
"$PY" -m scanner.update || echo "(update skipped - offline is fine)"
"$PY" -m scanner.app
