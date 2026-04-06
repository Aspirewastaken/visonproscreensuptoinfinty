from __future__ import annotations

import base64
from pathlib import Path


def xor_encrypt(plaintext: str, key: bytes) -> str:
    """Deterministic symmetric placeholder encryption for local bootstrap.

    NOTE: This is intentionally simple for initial phase testing and should be
    replaced by age/sops/libsodium in production hardening.
    """
    data = plaintext.encode("utf-8")
    out = bytes(b ^ key[i % len(key)] for i, b in enumerate(data))
    return base64.b64encode(out).decode("utf-8")


def xor_decrypt(ciphertext_b64: str, key: bytes) -> str:
    data = base64.b64decode(ciphertext_b64.encode("utf-8"))
    out = bytes(b ^ key[i % len(key)] for i, b in enumerate(data))
    return out.decode("utf-8")


def encrypt_file(path: Path, key: bytes) -> Path:
    data = path.read_text(encoding="utf-8")
    encrypted = xor_encrypt(data, key)
    target = path.with_suffix(path.suffix + ".enc")
    target.write_text(encrypted, encoding="utf-8")
    return target


def decrypt_file(path: Path, key: bytes) -> Path:
    data = path.read_text(encoding="utf-8")
    decrypted = xor_decrypt(data, key)
    if path.suffix == ".enc":
        target = path.with_suffix("")
    else:
        target = path.with_suffix(path.suffix + ".dec")
    target.write_text(decrypted, encoding="utf-8")
    return target
