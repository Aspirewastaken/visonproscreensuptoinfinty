from __future__ import annotations

from dataclasses import dataclass, asdict
import json
from pathlib import Path


@dataclass(slots=True)
class CheckpointState:
    run_id: str
    processed_chunks: list[str]
    failed_chunks: list[str]
    stage: str


def load_checkpoint(path: Path) -> CheckpointState | None:
    if not path.exists():
        return None
    payload = json.loads(path.read_text())
    return CheckpointState(
        run_id=payload["run_id"],
        processed_chunks=list(payload.get("processed_chunks", [])),
        failed_chunks=list(payload.get("failed_chunks", [])),
        stage=payload.get("stage", "init"),
    )


def save_checkpoint(path: Path, state: CheckpointState) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(state), indent=2))
