"""Optional at-rest encryption of the output bundle.

Uses a passphrase-derived key (scrypt) with AES-GCM via the `cryptography`
package. This is opt-in: if you ask for an encrypted bundle, the plaintext
reports are encrypted into a single `.pis` file and then removed.
"""

from __future__ import annotations

import json
import os
import struct
from typing import List

MAGIC = b"PIS1"


def _derive_key(passphrase: str, salt: bytes) -> bytes:
    from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

    kdf = Scrypt(salt=salt, length=32, n=2 ** 15, r=8, p=1)
    return kdf.derive(passphrase.encode("utf-8"))


def encrypt_bundle(paths: List[str], out_dir: str, passphrase: str) -> str:
    """Encrypt the given files into one bundle; delete the plaintext originals."""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    payload = {}
    for p in paths:
        with open(p, "rb") as fh:
            payload[os.path.basename(p)] = fh.read().decode("utf-8", "replace")
    plaintext = json.dumps(payload).encode("utf-8")

    salt = os.urandom(16)
    nonce = os.urandom(12)
    key = _derive_key(passphrase, salt)
    ct = AESGCM(key).encrypt(nonce, plaintext, MAGIC)

    out_path = os.path.join(out_dir, "report.pis")
    with open(out_path, "wb") as fh:
        fh.write(MAGIC)
        fh.write(struct.pack("B", len(salt)))
        fh.write(salt)
        fh.write(struct.pack("B", len(nonce)))
        fh.write(nonce)
        fh.write(ct)
    os.chmod(out_path, 0o600)

    # Remove plaintext now that it is safely encrypted.
    for p in paths:
        try:
            os.remove(p)
        except OSError:
            pass
    return out_path


def decrypt_bundle(path: str, passphrase: str) -> dict:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != MAGIC:
        raise ValueError("Not a PIS bundle.")
    pos = 4
    salt_len = data[pos]; pos += 1
    salt = data[pos:pos + salt_len]; pos += salt_len
    nonce_len = data[pos]; pos += 1
    nonce = data[pos:pos + nonce_len]; pos += nonce_len
    ct = data[pos:]
    key = _derive_key(passphrase, salt)
    plaintext = AESGCM(key).decrypt(nonce, ct, MAGIC)
    return json.loads(plaintext.decode("utf-8"))
