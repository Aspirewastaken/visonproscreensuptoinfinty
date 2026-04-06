from __future__ import annotations

from pathlib import Path
from typing import Any

from adlab_memory.ingest.base import ProviderAdapter, to_event
from adlab_memory.schema.events import NormalizedEvent


class GeminiAdapter(ProviderAdapter):
    provider_name = "gemini"

    def parse_export(self, export_file: Path, payload: dict[str, Any]) -> list[NormalizedEvent]:
        account_id = str(payload.get("account_id", "default"))
        conversations = payload.get("conversations", payload.get("chats", []))
        events: list[NormalizedEvent] = []

        for conv in conversations:
            conversation_id = str(conv.get("id", conv.get("conversationId", "unknown-conversation")))
            messages = conv.get("messages", conv.get("events", []))
            for msg in messages:
                message_id = str(msg.get("id", f"{conversation_id}-msg-{len(events)}"))
                role = str(msg.get("role", msg.get("author", "unknown"))).lower()
                content = self._extract_content(msg)
                timestamp = msg.get("timestamp", msg.get("createTime", 0))
                events.append(
                    to_event(
                        provider=self.provider_name,
                        account_id=account_id,
                        export_file=export_file,
                        conversation_id=conversation_id,
                        message_id=message_id,
                        role=role,
                        content=content,
                        timestamp=timestamp,
                        metadata={"title": conv.get("title", "")},
                    )
                )
        return events

    @staticmethod
    def _extract_content(message: dict[str, Any]) -> str:
        if isinstance(message.get("text"), str):
            return message["text"]
        content = message.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            return "\n".join(str(x) for x in content)
        if isinstance(content, dict):
            parts = content.get("parts")
            if isinstance(parts, list):
                return "\n".join(str(x) for x in parts)
        return ""
