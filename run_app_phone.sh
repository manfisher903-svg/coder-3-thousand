#!/usr/bin/env bash
# Launch SpeedRunner so your PHONE can open it over Wi-Fi.
# Watch the output - it prints the http://...:5000 address to type on your phone.
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
"$PY" -m scanner.update || true
PIS_LAN=1 "$PY" -m scanner.app
