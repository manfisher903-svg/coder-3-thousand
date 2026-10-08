# Host SpeedRunner free & always-on on an Oracle Cloud VM

End result: a permanent link like `https://yourname.duckdns.org`, always on,
your laptop off, $0.

## Step 1 — Get a free web name (DuckDNS)
1. Go to **duckdns.org**, sign in (Google/GitHub — free, no card).
2. Type a name (e.g. `650rio`) and click **add domain**. That gives you
   `650rio.duckdns.org`.
3. Copy the **token** shown near the top of the page. Keep this tab open.

## Step 2 — Prepare the setup script
Open `deploy/oracle-cloud-init.sh` from this repo and change the top two lines:
```
DUCKDNS_DOMAIN="650rio"        # the name you added (no .duckdns.org)
DUCKDNS_TOKEN="your-token"     # from the DuckDNS page
```
Copy the whole edited script — you'll paste it in Step 3.

## Step 3 — Create the VM (Oracle console)
1. **Create a VM instance**.
2. **Image & shape:** Ubuntu; shape **Always Free-eligible** — prefer
   `VM.Standard.A1.Flex` (Arm) with 1 OCPU / 6 GB, or `VM.Standard.E2.1.Micro`
   if Arm is unavailable. Make sure it says **Always Free**.
3. **Add SSH keys:** choose *Generate a key pair* and **Save the private key**
   (you may never need it, but keep it).
4. **Advanced options → Management → cloud-init script:** paste your edited
   script from Step 2.
5. **Create.** Note the instance's **public IP** when it appears.

## Step 4 — Open ports 80 and 443 (one time)
Oracle blocks inbound traffic by default. Open the two web ports:
1. On the instance page, click its **subnet** → its **Security List** (Default).
2. **Add Ingress Rules** (twice):
   - Source `0.0.0.0/0`, IP Protocol **TCP**, Destination port **80**
   - Source `0.0.0.0/0`, IP Protocol **TCP**, Destination port **443**
3. Save.

## Step 5 — Wait, then open your link
Give it ~3–5 minutes (it installs and fetches an HTTPS certificate), then open:

### `https://yourname.duckdns.org`

Register **`650rio`** (the owner, no code needed) → **▸ invite codes** →
generate a code → share **the link + a code** with people.

## Updating later
The service runs the code from this repo. To pick up new changes, SSH in (or use
the Oracle **Cloud Shell**) and run:
```
cd /opt/speedrunner && sudo git pull && sudo systemctl restart speedrunner
```
(Ask and I can turn this into a one-button update too.)

## If the link doesn't come up
- Make sure Step 4 ports are open AND DuckDNS points to the VM's public IP
  (the script sets it, but double-check on duckdns.org).
- Certificates need port 80 reachable; give it a few minutes on first boot.
