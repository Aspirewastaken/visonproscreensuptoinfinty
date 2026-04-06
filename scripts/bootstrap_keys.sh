#!/usr/bin/env bash
set -euo pipefail

KEY_PATH="${1:-.adlab/keys/local.key}"

echo "Bootstrapping key at: ${KEY_PATH}"
python3 -m adlab_memory.cli keys bootstrap --output "${KEY_PATH}"
