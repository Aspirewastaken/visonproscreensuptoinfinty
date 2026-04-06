from __future__ import annotations

import base64
import os
from pathlib import Path


def ensure_key(path: Path) -> bytes:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return base64.urlsafe_b64decode(path.read_text(encoding="utf-8").strip())
    key = os.urandom(32)
    path.write_text(base64.urlsafe_b64encode(key).decode("utf-8"), encoding="utf-8")
    return key


__all__ = ["ensure_key"]
