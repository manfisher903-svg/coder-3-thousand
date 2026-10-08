"""Check / set up the OWNER account on this machine.

Ownership is decided by USERNAME alone: only the owner username (``650rio`` by
default, or whatever ``PIS_OWNER`` is set to) is ever the owner, and no other
account can be — so usually there's nothing to do here. Running:

    python -m scanner.make_owner

tells you whether the owner account exists yet on this machine. If it doesn't,
you'll be offered to create it (password typed privately, stored only hashed in
the local .pis_users.json — never in the code or the repo).
"""

from __future__ import annotations

import getpass
import os
import sys

from .users import add_user, load_users

USERS_PATH = os.environ.get("PIS_USERS", ".pis_users.json")
OWNER_USERNAME = os.environ.get("PIS_OWNER", "650rio").strip()


def main(argv=None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    # An explicit username is accepted but must match the designated owner.
    requested = (argv[0].strip() if argv else OWNER_USERNAME)
    if requested.lower() != OWNER_USERNAME.lower():
        print(f"[!] Only '{OWNER_USERNAME}' can be the owner. "
              f"Other accounts are always normal users.")
        return 1

    if OWNER_USERNAME.lower() in load_users(USERS_PATH):
        print(f"[+] The owner account '{OWNER_USERNAME}' already exists here — "
              f"just sign in as '{OWNER_USERNAME}' and you're the owner.")
        return 0

    print(f"The owner account '{OWNER_USERNAME}' doesn't exist on this machine yet.")
    print("Create it now? (just press Enter at the password prompt to skip)")
    pw = getpass.getpass("Choose a password (min 6 chars): ")
    if not pw:
        print("    Skipped. You can also just register "
              f"'{OWNER_USERNAME}' from the app's Create-account page.")
        return 0
    pw2 = getpass.getpass("Repeat the password: ")
    if pw != pw2:
        print("[!] Passwords didn't match.")
        return 1
    ok, m = add_user(USERS_PATH, OWNER_USERNAME, pw, owner=True)
    print(f"[+] Owner account '{OWNER_USERNAME}' created." if ok else f"[!] {m}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
