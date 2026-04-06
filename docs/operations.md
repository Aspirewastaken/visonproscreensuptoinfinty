# Operations

## 1) Bootstrap

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

## 2) Prepare input exports

Drop provider files into:

- `data/input/claude/`
- `data/input/chatgpt/`
- `data/input/grok/`
- `data/input/gemini/`

## 3) Start mission

```bash
adlab-memory mission start --config configs/pipeline.default.yaml
```

## 4) Resume mission

```bash
adlab-memory mission resume --config configs/pipeline.default.yaml
```

## 5) Audit

```bash
adlab-memory mission audit --config configs/pipeline.default.yaml
```

## 6) One-pass compile (bounded by config max_batch_size)

```bash
adlab-memory compile --config configs/pipeline.default.yaml
```

## 7) Inspect memory tools

```bash
adlab-memory mcp-tools --config configs/pipeline.default.yaml
adlab-memory mcp-tools --config configs/pipeline.default.yaml --json
```

## 8) Scripts

```bash
./scripts/bootstrap_keys.sh
./scripts/run_mission.sh
./scripts/smoke_test.sh
```
