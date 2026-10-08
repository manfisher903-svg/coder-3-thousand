#!/bin/bash
# ============================================================
#  SpeedRunner — Oracle Cloud "cloud-init" setup script.
#  Paste this into the VM's  Advanced options → Management →
#  "Paste cloud-init script"  box when you create the instance.
#  It runs ONCE on first boot and sets everything up:
#    - installs SpeedRunner as an always-on service,
#    - points your DuckDNS name at this server,
#    - gets a free HTTPS certificate (via Caddy),
#    - opens the firewall.
#  When it finishes (a few minutes), your app is live at:
#        https://YOURNAME.duckdns.org
#
#  >>> EDIT THE TWO LINES BELOW before pasting. <<<
# ============================================================
DUCKDNS_DOMAIN="CHANGE_ME"     # just the name you picked, e.g. 650rio  (NOT the full .duckdns.org)
DUCKDNS_TOKEN="CHANGE_ME"      # the token shown on your duckdns.org account page
OWNER="650rio"                 # the single owner account username
# ------------------------------------------------------------

set -e
FQDN="${DUCKDNS_DOMAIN}.duckdns.org"
APP_DIR=/opt/speedrunner
DATA_DIR="$APP_DIR/data"
REPO="https://github.com/manfisher903-svg/coder-3-thousand.git"
BRANCH="claude/personal-info-scanner-rwixso"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-venv python3-pip git curl \
    debian-keyring debian-archive-keyring apt-transport-https iptables-persistent

# 1) Point DuckDNS at this server's public IP (and keep it fresh).
PUBIP="$(curl -s https://api.ipify.org || true)"
curl -s "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=${PUBIP}" || true
cat >/etc/cron.d/duckdns <<CRON
*/15 * * * * root curl -s "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=" >/dev/null 2>&1
CRON

# 2) Install the app.
git clone --depth 1 -b "$BRANCH" "$REPO" "$APP_DIR"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip -q
"$APP_DIR/venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"
mkdir -p "$DATA_DIR"
SECRET="$(head -c 48 /dev/urandom | base64 | tr -d '\n/+=')"

# 3) Run it as an always-on service (restarts on crash / reboot).
cat >/etc/systemd/system/speedrunner.service <<SVC
[Unit]
Description=SpeedRunner
After=network.target

[Service]
WorkingDirectory=$APP_DIR
Environment=PIS_DATA=$DATA_DIR/data
Environment=PIS_USERS=$DATA_DIR/.pis_users.json
Environment=PIS_INVITES=$DATA_DIR/.pis_invites.json
Environment=PIS_SECRET=$SECRET
Environment=PIS_SECURE_COOKIES=1
Environment=PIS_OWNER=$OWNER
ExecStart=$APP_DIR/venv/bin/gunicorn scanner.app:app --workers 1 --threads 8 --timeout 600 --bind 127.0.0.1:5000
Restart=always

[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable --now speedrunner

# 4) Free automatic HTTPS via Caddy, reverse-proxying to the app.
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    >/etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy
cat >/etc/caddy/Caddyfile <<CADDY
${FQDN} {
    reverse_proxy 127.0.0.1:5000
}
CADDY
systemctl restart caddy

# 5) Open the server's own firewall for web traffic.
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT || true
iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT || true
netfilter-persistent save || true

echo "SpeedRunner setup finished. Live at https://${FQDN}" >/var/log/speedrunner-setup.done
