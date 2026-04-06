#!/usr/bin/env bash
set -euo pipefail

echo "[smoke] CLI help"
python3 -m adlab_memory.cli --help >/dev/null

echo "[smoke] Running pytest"
python3 -m pytest -q

echo "[smoke] complete"
