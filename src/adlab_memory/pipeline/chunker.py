from __future__ import annotations

from dataclasses import dataclass
from math import ceil

from adlab_memory.schema.events import NormalizedEvent


def estimate_tokens(text: str) -> int:
    if not text:
        return 0
    return ceil(len(text) / 4)


@dataclass(slots=True)
class EventChunk:
    id: str
    conversation_id: str
    event_ids: list[str]
    events: list[NormalizedEvent]
    token_estimate: int


def build_chunks(
    events: list[NormalizedEvent],
    *,
    target_tokens: int,
    overlap_tokens: int,
) -> list[EventChunk]:
    grouped: dict[str, list[NormalizedEvent]] = {}
    for event in sorted(events, key=lambda e: (e.conversation_id, e.timestamp)):
        grouped.setdefault(event.conversation_id, []).append(event)

    chunks: list[EventChunk] = []
    for conversation_id, items in grouped.items():
        start = 0
        chunk_index = 0
        while start < len(items):
            token_total = 0
            end = start
            while end < len(items):
                candidate = estimate_tokens(items[end].content)
                if token_total + candidate > target_tokens and end > start:
                    break
                token_total += candidate
                end += 1
            chunk_events = items[start:end]
            chunks.append(
                EventChunk(
                    id=f"{conversation_id}:{chunk_index}",
                    conversation_id=conversation_id,
                    event_ids=[e.message_id for e in chunk_events],
                    events=chunk_events,
                    token_estimate=token_total,
                )
            )
            chunk_index += 1
            if end == len(items):
                break

            overlap_budget = overlap_tokens
            overlap_start = end
            while overlap_start > start and overlap_budget > 0:
                overlap_start -= 1
                overlap_budget -= estimate_tokens(items[overlap_start].content)
            start = max(overlap_start, start + 1)
    return chunks
