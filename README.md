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
adlab-memory mission status --state .adlab/state/mission_state.json
```

## Project layout

- `src/adlab_memory/`: package source.
- `configs/`: pipeline + model profiles.
- `docs/`: architecture, operations, and security notes.
- `tests/`: unit/integration/e2e tests with fixtures.
- `scripts/`: bootstrap + smoke scripts.
