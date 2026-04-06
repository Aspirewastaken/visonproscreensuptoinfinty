from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from adlab_memory.pipeline.chunker import EventChunk


TriageLabel = Literal["architecture", "client", "methodology", "ops", "noise"]


KEYWORDS: dict[TriageLabel, tuple[str, ...]] = {
    "architecture": ("schema", "pipeline", "mcp", "model", "design", "api", "backend"),
    "client": ("client", "campaign", "ryan", "evan", "deliverable", "content"),
    "methodology": ("protocol", "rosetta", "loop", "validation", "hypothesis"),
    "ops": ("server", "deploy", "router", "network", "backup", "nas"),
    "noise": ("lol", "thanks", "cool", "ok", "yep"),
}


@dataclass(slots=True)
class TriageResult:
    chunk_id: str
    label: TriageLabel
    score: float


def classify_chunk(chunk: EventChunk) -> TriageResult:
    text = "\n".join(event.content.lower() for event in chunk.events)
    counts: dict[TriageLabel, int] = {label: 0 for label in KEYWORDS}
    for label, words in KEYWORDS.items():
        counts[label] = sum(text.count(word) for word in words)
    label = max(counts, key=counts.get)
    total = sum(counts.values()) or 1
    score = counts[label] / total
    return TriageResult(chunk_id=chunk.id, label=label, score=score)


def triage_chunks(chunks: list[EventChunk]) -> dict[str, TriageResult]:
    return {chunk.id: classify_chunk(chunk) for chunk in chunks}
