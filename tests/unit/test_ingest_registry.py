from __future__ import annotations

import json
from pathlib import Path

from adlab_memory.ingest.registry import ingest_exports


def test_ingest_exports_parses_all_providers(tmp_path: Path) -> None:
    fixture_root = Path("tests/fixtures/providers")
    input_root = tmp_path / "input"
    normalized_root = tmp_path / "normalized"
    providers = ["claude", "chatgpt", "grok", "gemini"]

    for provider in providers:
        src = fixture_root / provider / "sample.json"
        dst_dir = input_root / provider
        dst_dir.mkdir(parents=True, exist_ok=True)
        dst = dst_dir / "sample.json"
        dst.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")

    events, manifest = ingest_exports(
        input_root=input_root,
        normalized_root=normalized_root,
        providers=providers,
        include_globs=["*.json"],
    )

    assert len(events) == 8
    assert manifest.total_events == 8
    assert manifest.unique_events == 8
    assert manifest.duplicates_removed == 0
    assert manifest.providers["claude"] == 2
    assert manifest.providers["chatgpt"] == 2
    assert manifest.providers["grok"] == 2
    assert manifest.providers["gemini"] == 2

    manifest_file = normalized_root / "manifest.json"
    assert manifest_file.exists()
    payload = json.loads(manifest_file.read_text(encoding="utf-8"))
    assert payload["total_events"] == 8

