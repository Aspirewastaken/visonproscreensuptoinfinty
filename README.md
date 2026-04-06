# AdLab Memory — MiniMax M2.7 REAP Optimized

Local-first, private memory infrastructure for long-running AI research loops.

## What it does

- Ingests exported conversation history (Claude, ChatGPT, Grok, Gemini).
- Normalizes data into a single canonical event schema.
- Compiles a markdown wiki with backlinks, decay, and supersession metadata.
- Runs autonomous resumable missions for multi-day processing.
- Exposes memory tools through an MCP-style local server.
- Encrypts outputs at rest with local keys.

## Quick start

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
adlab-memory --help
```

## Mission run

```bash
adlab-memory mission start --config configs/pipeline.default.yaml
adlab-memory mission status --config configs/pipeline.default.yaml
adlab-memory mission audit --config configs/pipeline.default.yaml
adlab-memory compile --config configs/pipeline.default.yaml
```

## Run tests

```bash
python3 -m pytest -q
./scripts/smoke_test.sh
```

## Scripts

- `scripts/run_mission.sh`: start full mission.
- `scripts/bootstrap_keys.sh`: create local key file.
- `scripts/smoke_test.sh`: CLI + pytest smoke checks.

## Project layout

- `src/adlab_memory/`: package source.
- `configs/`: pipeline + model profiles.
- `docs/`: architecture, operations, and security notes.
- `tests/`: unit/integration/e2e tests with fixtures.
- `scripts/`: bootstrap + smoke scripts.
