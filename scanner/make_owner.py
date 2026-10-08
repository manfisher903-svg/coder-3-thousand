"""Set up (or promote) the OWNER account on this machine.

The owner can generate invite codes and let other people register. Run:

    python -m scanner.make_owner 650rio

If the user already exists it is promoted to owner. If not, you'll be asked
to set a password (typed privately, never shown or stored in plain text).

Nothing here is committed to the repository — the account lives only in this
machine's local .pis_users.json file.
"""

from __future__ import annotations

import getpass
import os
import sys

from .users import add_user, load_users, set_owner

USERS_PATH = os.environ.get("PIS_USERS", ".pis_users.json")


def main(argv=None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if not argv:
        print("Usage: python -m scanner.make_owner <username>")
        return 2
    username = argv[0].strip()

    if username.lower() in load_users(USERS_PATH):
        ok, msg = set_owner(USERS_PATH, username, True)
        print(f"[+] {username} is now the OWNER." if ok else f"[!] {msg}")
        return 0 if ok else 1

    print(f"Creating owner account '{username}'.")
    pw = getpass.getpass("Choose a password (min 6 chars): ")
    pw2 = getpass.getpass("Repeat the password: ")
    if pw != pw2:
        print("[!] Passwords didn't match.")
        return 1
    ok, msg = add_user(USERS_PATH, username, pw, owner=True)
    print(f"[+] Owner account '{username}' created." if ok else f"[!] {msg}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
