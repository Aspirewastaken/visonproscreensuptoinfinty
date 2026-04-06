# Architecture

AdLab Memory is a local-first pipeline:

1. **Ingest** provider exports into normalized events.
2. **Chunk + triage** events into knowledge-bearing batches.
3. **Compile wiki** articles with deterministic IDs and metadata.
4. **Synthesize graph** links, supersession, and decay updates.
5. **Serve tools** using local MCP-style command server.
6. **Encrypt artifacts** and checkpoint mission progress.

## Modules

- `ingest/*`: provider adapters and normalization.
- `pipeline/*`: chunking, triage, compile, synthesis, checkpoints.
- `wiki/*`: article model, link graph, decay, supersession.
- `models/*`: local model profile + execution adapters.
- `orchestration/*`: mission loop and persisted state.
- `mcp/*`: memory tools and stdio server.
- `security/*`: key bootstrap and encryption helpers.

## Runtime

- Single-host process with resumable checkpoints.
- Config-driven model profiles (`minimax_m2_7_reap` + fallback).
- Deterministic outputs for repeatable runs and testing.
