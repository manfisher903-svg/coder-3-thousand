# Getting a shareable link

Two ways: a **free** one that runs on your own laptop, or a **paid, always-on**
one in the cloud.

## Free option — your laptop + a public link (no cost)

Run SpeedRunner on your computer and expose it with a free Cloudflare tunnel.
Your laptop does the work; the tunnel just gives it a public web address.

- **Windows:** double-click **`run_app_public.bat`**
- **Mac:** run **`run_app_public.sh`**

It starts the app, then prints a link like **`https://something.trycloudflare.com`**.
Share **that link + an invite code** with people. First run also registers your
owner account `650rio` (visit the link and sign up).

**Trade-off:** the link only works while that window stays open and your laptop
is on. Close it / shut the laptop → the link goes down (and the address changes
next time). Your accounts, codes and scans are saved on your laptop, so they
persist between runs.

If you want a link that's up 24/7 even when your laptop is off, use the paid
cloud option below.

---

# Always-on hosting in the cloud (Render)

This gives you a permanent web address like `https://speedrunner-xxxx.onrender.com`
that you can share. People open it, enter an **invite code** you generate, and
sign in — no install. It stays up even when your laptop is off.

> **Why not Netlify?** Netlify only hosts static sites and short serverless
> functions. SpeedRunner is a long-running Python server that holds email
> connections open and stores data on disk, so it needs a real Python host with
> a **persistent disk**. Render (used here), Railway, Fly.io, or any small VPS
> all work. Render is the most beginner-friendly.

## Steps (Render)

1. **Repo is public** — already done. ✔
2. Create a free account at **render.com** and connect your GitHub.
3. Click **New + → Blueprint**, pick the `coder-3-thousand` repo. Render reads
   `render.yaml` and sets everything up (server command, env vars, disk).
4. The blueprint uses the **Starter** plan because it needs a **persistent
   disk** (a few $/month). Without a disk, every restart would wipe all
   accounts, invite codes, and scans. Confirm/accept the plan.
5. Click **Apply / Create**. First build takes a few minutes.
6. When it's live, Render shows your URL: `https://speedrunner-xxxx.onrender.com`.

## First-time setup (once it's live)

1. Open your URL and go to **Create account**. Register **`650rio`** (the owner
   account — it's the only one that doesn't need an invite code). Pick a strong
   password; it's stored only as a salted hash on the server's disk.
2. You'll see the **▸ invite codes** tab. Generate a code.
3. **Share with people:** send them

   > the URL `https://speedrunner-xxxx.onrender.com` **+** an invite code like `SR-ABCD-EFGH`

   They register with the code and they're in. Turn a code off anytime to block it.

## What link do I share?

- **To let people use it (what you want):** your Render URL above, plus a code.
- You do **not** share the GitHub link for this mode — that's only for people
  who'd install their own separate copy.

## Important, because this handles real secrets

You'd be running a service that logs into people's email and can surface their
SSNs, cards, etc. Treat it accordingly:

- **HTTPS** is automatic on Render, and `PIS_SECURE_COOKIES=1` is set so logins
  only travel over HTTPS. Keep it on.
- **Only hand out invite codes to people you trust**; revoke them when done.
- Use a **strong owner password**, and consider turning on report encryption
  (`encrypt_passphrase` in `config.yaml`) if you store scan output.
- Keep the service updated (Render auto-deploys when you push changes).

## Local use is unchanged

Running it on your own machine still works exactly as before
(`run_app.bat` / `python -m scanner.app`); the hosting setup is additive.

## Other hosts

The `Procfile` (`gunicorn scanner.app:app ...`) also works on Railway and
Heroku-style platforms. Any of them needs a **persistent disk/volume** mounted,
with these env vars pointed at it: `PIS_DATA`, `PIS_USERS`, `PIS_INVITES`, plus
`PIS_SECRET` (random), `PIS_SECURE_COOKIES=1`, and `PIS_OWNER=650rio`. Always run
a **single worker** (`--workers 1`), since scan progress is kept in memory.
