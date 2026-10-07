"""Self-update: fetch the latest SpeedRunner code from GitHub.

No Git required. Downloads the branch as a ZIP, extracts it, and copies the
CODE files over your current install — while never touching your personal
data (accounts file, config, scan output). Run it with:

    python -m scanner.update

or use the "Update" button in the app, or let run_app.sh/bat run it on launch.
"""

from __future__ import annotations

import io
import os
import shutil
import zipfile
from urllib.request import urlopen

REPO = "manfisher903-svg/coder-3-thousand"
BRANCH = "claude/personal-info-scanner-rwixso"
ZIP_URL = f"https://github.com/{REPO}/archive/refs/heads/{BRANCH}.zip"

# Files/dirs that hold YOUR data — never overwritten or deleted by an update.
PROTECTED = {
    "accounts.txt", "accounts.yaml", "config.yaml", "config.local.yaml",
}
PROTECTED_PREFIXES = ("inventory", ".git", ".venv", "venv")
PROTECTED_SUFFIXES = (".pis",)


def _repo_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _is_protected(rel: str) -> bool:
    rel = rel.replace("\\", "/")
    top = rel.split("/", 1)[0]
    name = os.path.basename(rel)
    if name in PROTECTED:
        return True
    if top in PROTECTED_PREFIXES:
        return True
    if rel.endswith(PROTECTED_SUFFIXES):
        return True
    return False


def update(root: str = None, timeout: float = 30.0):
    """Download latest code and copy it into `root`. Returns (ok, message)."""
    root = root or _repo_root()
    try:
        with urlopen(ZIP_URL, timeout=timeout) as resp:  # noqa: S310 fixed https
            data = resp.read()
    except Exception as exc:  # noqa: BLE001
        return False, f"Could not download update: {exc}"

    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        return False, "Downloaded file was not a valid ZIP."

    names = zf.namelist()
    if not names:
        return False, "Update archive was empty."
    # GitHub wraps everything in a single top-level folder.
    top = names[0].split("/", 1)[0] + "/"

    changed = 0
    for info in zf.infolist():
        if info.is_dir():
            continue
        if not info.filename.startswith(top):
            continue
        rel = info.filename[len(top):]
        if not rel or _is_protected(rel):
            continue
        dest = os.path.join(root, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with zf.open(info) as src, open(dest, "wb") as out:
            new = src.read()
            # Skip unchanged files so the count reflects real updates.
            if os.path.exists(dest):
                try:
                    with open(dest, "rb") as cur:
                        if cur.read() == new:
                            continue
                except OSError:
                    pass
            out.write(new)
        changed += 1

    if changed == 0:
        return True, "Already up to date."
    return True, f"Updated {changed} file(s) to the latest version."


def main():
    ok, msg = update()
    print(("[+] " if ok else "[!] ") + msg)
    if ok and "Updated" in msg:
        print("    Restart the app for changes to take effect.")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
