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
adlab-memory mission audit --state .adlab/state/mission_state.json
```

## 6) Serve memory tools

```bash
adlab-memory mcp serve --wiki-dir data/wiki
```
