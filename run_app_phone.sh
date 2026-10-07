#!/usr/bin/env bash
# Launch SpeedRunner so your PHONE can open it over Wi-Fi.
# Watch the output — it prints the http://...:5000 address to type on your phone.
cd "$(dirname "$0")"
python3 -m pip install -q -r requirements.txt
python3 -m scanner.update || true
PIS_LAN=1 python3 -m scanner.app
