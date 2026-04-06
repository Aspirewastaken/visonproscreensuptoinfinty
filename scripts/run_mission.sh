#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="${1:-configs/pipeline.default.yaml}"

echo "Starting mission with config: ${CONFIG_PATH}"
python3 -m adlab_memory.cli --config "${CONFIG_PATH}" mission start
