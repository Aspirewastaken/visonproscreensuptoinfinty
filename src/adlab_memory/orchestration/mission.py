from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
from uuid import uuid4

from adlab_memory.config import PipelineConfig
from adlab_memory.ingest.registry import ingest_exports
from adlab_memory.models.local_runner import LocalModelRunner
from adlab_memory.models.profile_resolver import load_model_profile
from adlab_memory.orchestration.state import BatchAudit, MissionState, load_mission_state, save_mission_state
from adlab_memory.pipeline.chunker import build_chunks
from adlab_memory.pipeline.compiler import compile_chunks_to_wiki
from adlab_memory.pipeline.synthesis import synthesize_wiki
from adlab_memory.pipeline.triage import triage_chunks
from adlab_memory.schema.events import NormalizedEvent


@dataclass(slots=True)
class MissionResult:
    mission_id: str
    state_path: Path
    processed_chunks: int
    failed_chunks: int
    wiki_dir: Path


class MissionRunner:
    def __init__(self, config: PipelineConfig):
        self.config = config
        self.state_path = config.paths.state_root / "mission_state.json"

    def start(self) -> MissionResult:
        state = MissionState(mission_id=f"mission-{uuid4().hex[:10]}", stage="ingest")
        return self._run(state)

    def resume(self) -> MissionResult:
        state = load_mission_state(self.state_path)
        if state is None:
            return self.start()
        return self._run(state)

    def status(self) -> MissionState | None:
        return load_mission_state(self.state_path)

    def _run(self, state: MissionState) -> MissionResult:
        cfg = self.config
        cfg.paths.normalized_root.mkdir(parents=True, exist_ok=True)
        cfg.paths.wiki_root.mkdir(parents=True, exist_ok=True)

        events, _ = ingest_exports(
            input_root=cfg.paths.input_root,
            normalized_root=cfg.paths.normalized_root,
            providers=cfg.ingest.providers,
            include_globs=cfg.ingest.include_globs,
        )
        state.stage = "chunking"
        state.touch()
        save_mission_state(self.state_path, state)

        events = _sort_events(events, cfg.compile.prioritize)
        chunks = build_chunks(
            events,
            target_tokens=cfg.compile.chunk_target_tokens,
            overlap_tokens=cfg.compile.chunk_overlap_tokens,
        )
        triage_map = triage_chunks(chunks)

        state.stage = "compiling"
        profile = load_model_profile(cfg.model.profile)
        runner = LocalModelRunner(profile=profile)

        pending = [chunk for chunk in chunks if chunk.id not in state.completed_batches]
        for chunk in pending:
            try:
                compile_chunks_to_wiki(
                    chunks=[chunk],
                    triage_map=triage_map,
                    runner=runner,
                    wiki_root=cfg.paths.wiki_root,
                    low_signal_threshold=float(profile.adaptive_chunk.get("low_signal_skip_threshold", 0.15)),
                )
                state.completed_batches.append(chunk.id)
                state.audits.append(BatchAudit(batch_id=chunk.id, status="completed"))
            except Exception as exc:  # noqa: BLE001
                state.failed_batches.append(chunk.id)
                state.audits.append(BatchAudit(batch_id=chunk.id, status="failed", note=str(exc)))
                if not cfg.mission.quarantine_failed_batches:
                    raise
            finally:
                state.touch()
                save_mission_state(self.state_path, state)

        state.stage = "synthesis"
        synthesize_wiki(cfg.paths.wiki_root)
        state.touch()
        save_mission_state(self.state_path, state)

        state.stage = "completed"
        state.touch()
        save_mission_state(self.state_path, state)

        return MissionResult(
            mission_id=state.mission_id,
            state_path=self.state_path,
            processed_chunks=len(state.completed_batches),
            failed_chunks=len(state.failed_batches),
            wiki_dir=cfg.paths.wiki_root,
        )


def _sort_events(events: list[NormalizedEvent], prioritize: str) -> list[NormalizedEvent]:
    reverse = prioritize == "newest_first"
    return sorted(events, key=lambda event: event.timestamp, reverse=reverse)


def mission_audit(state_path: Path) -> str:
    state = load_mission_state(state_path)
    if state is None:
        return "No mission state found."
    payload = {
        "mission_id": state.mission_id,
        "stage": state.stage,
        "completed_batches": len(state.completed_batches),
        "failed_batches": len(state.failed_batches),
        "updated_at": state.updated_at,
        "failures": [a.__dict__ for a in state.audits if a.status == "failed"],
    }
    return json.dumps(payload, indent=2)
