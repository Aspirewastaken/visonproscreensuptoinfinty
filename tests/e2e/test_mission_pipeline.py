from __future__ import annotations

import json
from pathlib import Path

from adlab_memory.config import load_pipeline_config
from adlab_memory.orchestration.mission import MissionRunner


def _prepare_input_tree(tmp_path: Path) -> Path:
    fixture_root = Path("tests/fixtures/providers")
    input_root = tmp_path / "input"
    for provider_dir in fixture_root.iterdir():
        if not provider_dir.is_dir():
            continue
        dst = input_root / provider_dir.name
        dst.mkdir(parents=True, exist_ok=True)
        for file in provider_dir.glob("*.json"):
            (dst / file.name).write_text(file.read_text(encoding="utf-8"), encoding="utf-8")
    return input_root


def test_end_to_end_mission_run(tmp_path: Path) -> None:
    cfg = load_pipeline_config(Path("configs/pipeline.default.yaml"))
    cfg.paths.input_root = _prepare_input_tree(tmp_path)
    cfg.paths.normalized_root = tmp_path / "normalized"
    cfg.paths.wiki_root = tmp_path / "wiki"
    cfg.paths.state_root = tmp_path / "state"
    cfg.paths.checkpoints_root = tmp_path / "checkpoints"
    cfg.compile.max_batch_size = 2

    runner = MissionRunner(cfg)
    partial = runner.compile_once()
    assert partial.processed_this_run >= 1
    assert partial.stage in {"compiling", "completed"}

    final = runner.resume()
    assert final.stage == "completed"
    assert final.processed_chunks >= partial.processed_chunks
    assert final.checkpoint_path.exists()
    assert final.state_path.exists()

    manifest = cfg.paths.normalized_root / "manifest.json"
    assert manifest.exists()
    payload = json.loads(manifest.read_text(encoding="utf-8"))
    assert payload["unique_events"] >= 8

    wiki_files = list(cfg.paths.wiki_root.glob("*.md"))
    assert wiki_files, "expected at least one wiki article"
    assert (cfg.paths.wiki_root / "CONTRADICTIONS.md").exists()
    assert (cfg.paths.wiki_root / "ORPHANS.md").exists()

