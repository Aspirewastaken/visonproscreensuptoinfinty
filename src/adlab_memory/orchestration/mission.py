from __future__ import annotations

from dataclasses import asdict, dataclass
import json
from pathlib import Path
from uuid import uuid4

from adlab_memory.config import PipelineConfig
from adlab_memory.ingest.registry import ingest_exports
from adlab_memory.models.local_runner import LocalModelRunner
from adlab_memory.models.profile_resolver import load_model_profile
from adlab_memory.orchestration.state import BatchAudit, MissionState, load_mission_state, save_mission_state
from adlab_memory.pipeline.checkpoint import CheckpointState, load_checkpoint, save_checkpoint
from adlab_memory.pipeline.chunker import build_chunks
from adlab_memory.pipeline.compiler import compile_chunks_to_wiki
from adlab_memory.pipeline.synthesis import synthesize_wiki
from adlab_memory.pipeline.triage import triage_chunks
from adlab_memory.schema.events import NormalizedEvent


@dataclass(slots=True)
class MissionResult:
    mission_id: str
    state_path: Path
    checkpoint_path: Path
    processed_chunks: int
    processed_this_run: int
    failed_chunks: int
    wiki_dir: Path
    stage: str


class MissionRunner:
    def __init__(self, config: PipelineConfig):
        self.config = config
        self.state_path = config.paths.state_root / "mission_state.json"
        self.checkpoint_path = config.paths.checkpoints_root / "mission_checkpoint.json"

    def start(self) -> MissionResult:
        state = MissionState(mission_id=f"mission-{uuid4().hex[:10]}", stage="ingest")
        return self._run(state, max_chunks=None)

    def resume(self) -> MissionResult:
        state = load_mission_state(self.state_path)
        if state is None:
            return self.start()
        return self._run(state, max_chunks=None)

    def compile_once(self) -> MissionResult:
        state = load_mission_state(self.state_path)
        if state is None:
            state = MissionState(mission_id=f"mission-{uuid4().hex[:10]}", stage="ingest")
        return self._run(state, max_chunks=self.config.compile.max_batch_size)

    def status(self) -> MissionState | None:
        return load_mission_state(self.state_path)

    def checkpoint_status(self) -> CheckpointState | None:
        return load_checkpoint(self.checkpoint_path)

    def _run(self, state: MissionState, *, max_chunks: int | None) -> MissionResult:
        cfg = self.config
        cfg.paths.normalized_root.mkdir(parents=True, exist_ok=True)
        cfg.paths.wiki_root.mkdir(parents=True, exist_ok=True)
        cfg.paths.checkpoints_root.mkdir(parents=True, exist_ok=True)

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
        runners = self._load_runner_chain(cfg.model.profile)

        checkpoint = load_checkpoint(self.checkpoint_path)
        processed_from_checkpoint = set(checkpoint.processed_chunks) if checkpoint else set()
        failed_from_checkpoint = set(checkpoint.failed_chunks) if checkpoint else set()

        processed_ids = set(state.completed_batches) | processed_from_checkpoint
        pending = [chunk for chunk in chunks if chunk.id not in processed_ids]
        if max_chunks is not None:
            pending = pending[:max_chunks]

        processed_this_run = 0
        checkpoint_state = CheckpointState(
            run_id=state.mission_id,
            processed_chunks=sorted(processed_ids),
            failed_chunks=sorted(set(state.failed_batches) | failed_from_checkpoint),
            stage="compiling",
        )

        for chunk in pending:
            success = False
            last_error = ""
            for runner in runners:
                attempts = 0
                while attempts <= cfg.mission.retries:
                    attempts += 1
                    try:
                        compile_chunks_to_wiki(
                            chunks=[chunk],
                            triage_map=triage_map,
                            runner=runner,
                            wiki_root=cfg.paths.wiki_root,
                            low_signal_threshold=float(
                                runner.profile.adaptive_chunk.get("low_signal_skip_threshold", 0.15)
                            ),
                        )
                        success = True
                        break
                    except Exception as exc:  # noqa: BLE001
                        last_error = str(exc)
                if success:
                    break

            if success:
                state.completed_batches.append(chunk.id)
                checkpoint_state.processed_chunks.append(chunk.id)
                state.audits.append(BatchAudit(batch_id=chunk.id, status="completed"))
                processed_this_run += 1
            else:
                state.failed_batches.append(chunk.id)
                checkpoint_state.failed_chunks.append(chunk.id)
                state.audits.append(BatchAudit(batch_id=chunk.id, status="failed", note=last_error))
                if not cfg.mission.quarantine_failed_batches:
                    raise RuntimeError(f"Chunk {chunk.id} failed: {last_error}")

            state.touch()
            save_mission_state(self.state_path, state)
            if processed_this_run % max(1, cfg.mission.save_every_batches) == 0:
                save_checkpoint(self.checkpoint_path, checkpoint_state)

        all_processed = len(state.completed_batches) + len(state.failed_batches) >= len(chunks)
        if all_processed:
            state.stage = "synthesis"
            synthesize_wiki(cfg.paths.wiki_root)
            checkpoint_state.stage = "synthesis"
            save_checkpoint(self.checkpoint_path, checkpoint_state)
            state.stage = "completed"
        else:
            state.stage = "compiling"

        state.touch()
        save_mission_state(self.state_path, state)
        save_checkpoint(self.checkpoint_path, checkpoint_state)

        return MissionResult(
            mission_id=state.mission_id,
            state_path=self.state_path,
            checkpoint_path=self.checkpoint_path,
            processed_chunks=len(state.completed_batches),
            processed_this_run=processed_this_run,
            failed_chunks=len(state.failed_batches),
            wiki_dir=cfg.paths.wiki_root,
            stage=state.stage,
        )

    def _load_runner_chain(self, primary_profile_path: Path) -> list[LocalModelRunner]:
        runner_chain: list[LocalModelRunner] = []
        seen: set[Path] = set()
        queue: list[Path] = [primary_profile_path]

        while queue:
            current_path = queue.pop(0).resolve()
            if current_path in seen:
                continue
            seen.add(current_path)

            profile = load_model_profile(current_path)
            runner_chain.append(LocalModelRunner(profile=profile))
            for fallback in profile.fallback_chain:
                queue.append(self._resolve_fallback_path(current_path, fallback))

        return runner_chain

    @staticmethod
    def _resolve_fallback_path(current_profile_path: Path, fallback: str) -> Path:
        raw = Path(fallback)
        if raw.is_absolute():
            return raw.resolve()

        candidates = [
            (current_profile_path.parent / raw).resolve(),
            (Path.cwd() / raw).resolve(),
        ]
        if len(current_profile_path.parents) >= 3:
            candidates.append((current_profile_path.parents[2] / raw).resolve())

        for candidate in candidates:
            if candidate.exists():
                return candidate
        return candidates[0]


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
        "failures": [asdict(a) for a in state.audits if a.status == "failed"],
    }
    return json.dumps(payload, indent=2)
