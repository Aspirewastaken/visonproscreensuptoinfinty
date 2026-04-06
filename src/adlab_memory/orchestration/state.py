from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
import json
from pathlib import Path


@dataclass(slots=True)
class BatchAudit:
    batch_id: str
    status: str
    note: str = ""


@dataclass(slots=True)
class MissionState:
    mission_id: str
    stage: str = "init"
    started_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updated_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    completed_batches: list[str] = field(default_factory=list)
    failed_batches: list[str] = field(default_factory=list)
    audits: list[BatchAudit] = field(default_factory=list)

    def touch(self) -> None:
        self.updated_at = datetime.now(timezone.utc).isoformat()


def save_mission_state(path: Path, state: MissionState) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = asdict(state)
    path.write_text(json.dumps(payload, indent=2))


def load_mission_state(path: Path) -> MissionState | None:
    if not path.exists():
        return None
    payload = json.loads(path.read_text())
    audits = [BatchAudit(**item) for item in payload.get("audits", [])]
    return MissionState(
        mission_id=payload["mission_id"],
        stage=payload.get("stage", "init"),
        started_at=payload.get("started_at", datetime.now(timezone.utc).isoformat()),
        updated_at=payload.get("updated_at", datetime.now(timezone.utc).isoformat()),
        completed_batches=list(payload.get("completed_batches", [])),
        failed_batches=list(payload.get("failed_batches", [])),
        audits=audits,
    )
