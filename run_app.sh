#!/usr/bin/env bash
# Double-click or run this to launch SpeedRunner (opens in your browser).
# It auto-updates to the latest version first (your accounts & scans are kept).
cd "$(dirname "$0")"
python3 -m pip install -q -r requirements.txt
echo "Checking for updates..."
python3 -m scanner.update || echo "(update skipped — offline is fine)"
python3 -m scanner.app
