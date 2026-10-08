#!/usr/bin/env bash
# ============================================================
#  Launch SpeedRunner AND create a FREE public link to share.
#  Uses a Cloudflare tunnel -> a public https://something.trycloudflare.com
#  address. The link works while this window stays open and your laptop is on.
# ============================================================
cd "$(dirname "$0")" || exit 1

PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo "Python 3 is not installed. Opening the download page..."
  open "https://www.python.org/downloads/" 2>/dev/null || \
    xdg-open "https://www.python.org/downloads/" 2>/dev/null || true
  exit 1
fi

"$PY" -m pip install -q -r requirements.txt
echo "Checking for updates..."
"$PY" -m scanner.update || true

# Download the tunnel tool once (matches this Mac's chip).
if [ ! -x "./cloudflared" ]; then
  echo "Downloading the tunnel tool (one time)..."
  if [ "$(uname -m)" = "arm64" ]; then
    url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz"
  else
    url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz"
  fi
  curl -fsSL "$url" -o cloudflared.tgz && tar -xzf cloudflared.tgz && rm -f cloudflared.tgz
  chmod +x cloudflared
fi

# Start the app in the background; stop it when this window closes.
"$PY" -m scanner.app &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null' EXIT

echo
echo "============================================================"
echo "  Your PUBLIC LINK is starting. Look for a line with an"
echo "  address ending in  .trycloudflare.com"
echo
echo "  Share THAT link (plus an invite code) with people."
echo "  Keep this window OPEN - closing it takes the link down."
echo "============================================================"
echo
./cloudflared tunnel --url http://localhost:5000
