from __future__ import annotations

from pathlib import Path

from adlab_memory.ingest.registry import ingest_exports
from adlab_memory.pipeline.chunker import build_chunks
from adlab_memory.pipeline.triage import triage_chunks


def _load_events(tmp_path: Path):
    fixture_root = Path("tests/fixtures/providers")
    input_root = tmp_path / "input"
    normalized_root = tmp_path / "normalized"
    providers = ["claude", "chatgpt", "grok", "gemini"]

    for provider in providers:
        src = fixture_root / provider / "sample.json"
        dst_dir = input_root / provider
        dst_dir.mkdir(parents=True, exist_ok=True)
        (dst_dir / "sample.json").write_text(src.read_text(encoding="utf-8"), encoding="utf-8")

    events, _ = ingest_exports(
        input_root=input_root,
        normalized_root=normalized_root,
        providers=providers,
        include_globs=["*.json"],
    )
    return events


def test_chunking_and_triage(tmp_path: Path) -> None:
    events = _load_events(tmp_path)
    chunks = build_chunks(events, target_tokens=80, overlap_tokens=10)
    assert len(chunks) >= 4
    triage = triage_chunks(chunks)
    assert len(triage) == len(chunks)
    labels = {item.label for item in triage.values()}
    assert labels.issubset({"architecture", "client", "methodology", "ops", "noise"})

