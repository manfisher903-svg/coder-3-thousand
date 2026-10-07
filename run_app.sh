#!/usr/bin/env bash
# Double-click or run this to open the Personal Info Scanner app.
cd "$(dirname "$0")"
python3 -m pip install -q -r requirements.txt
python3 -m scanner.app
