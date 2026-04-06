from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from adlab_memory.schema.events import NormalizedEvent, SourceProvenance


def parse_timestamp(value: Any) -> datetime:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)

    if isinstance(value, (int, float)):
        if value > 10_000_000_000:
            value = value / 1000
        return datetime.fromtimestamp(float(value), tz=timezone.utc)

    if isinstance(value, str) and value:
        cleaned = value.replace("Z", "+00:00")
        return datetime.fromisoformat(cleaned)

    return datetime.fromtimestamp(0, tz=timezone.utc)


def to_event(
    *,
    provider: str,
    account_id: str,
    export_file: Path,
    conversation_id: str,
    message_id: str,
    role: str,
    content: str,
    timestamp: Any,
    tool_name: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> NormalizedEvent:
    return NormalizedEvent(
        conversation_id=conversation_id,
        message_id=message_id,
        role=role if role in {"system", "user", "assistant", "tool"} else "unknown",
        content=content or "",
        timestamp=parse_timestamp(timestamp),
        tool_name=tool_name,
        metadata=metadata or {},
        source=SourceProvenance(
            provider=provider,
            account_id=account_id or "default",
            export_file=export_file,
            raw_message_id=message_id,
        ),
    )


class ProviderAdapter(ABC):
    provider_name: str

    @abstractmethod
    def parse_export(self, export_file: Path, payload: dict[str, Any]) -> list[NormalizedEvent]:
        raise NotImplementedError
