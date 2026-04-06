from __future__ import annotations

from pathlib import Path
from typing import Any

from adlab_memory.ingest.base import ProviderAdapter, to_event
from adlab_memory.schema.events import NormalizedEvent


class GrokAdapter(ProviderAdapter):
    provider_name = "grok"

    def parse_export(self, export_file: Path, payload: dict[str, Any]) -> list[NormalizedEvent]:
        account_id = str(payload.get("account_id", "default"))
        conversations = payload.get("conversations", payload.get("threads", []))
        events: list[NormalizedEvent] = []

        for conv in conversations:
            conversation_id = str(conv.get("id", conv.get("thread_id", "unknown-conversation")))
            messages = conv.get("messages", conv.get("turns", []))
            for msg in messages:
                message_id = str(msg.get("id", f"{conversation_id}-msg-{len(events)}"))
                role = str(msg.get("role", msg.get("speaker", "unknown"))).lower()
                content = msg.get("text", msg.get("content", ""))
                timestamp = msg.get("created_at", msg.get("timestamp", 0))
                events.append(
                    to_event(
                        provider=self.provider_name,
                        account_id=account_id,
                        export_file=export_file,
                        conversation_id=conversation_id,
                        message_id=message_id,
                        role=role,
                        content=content if isinstance(content, str) else str(content),
                        timestamp=timestamp,
                        metadata={"title": conv.get("title", "")},
                    )
                )
        return events
