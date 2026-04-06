from __future__ import annotations

from pathlib import Path
from typing import Any

from adlab_memory.ingest.base import ProviderAdapter, to_event
from adlab_memory.schema.events import NormalizedEvent


class ClaudeAdapter(ProviderAdapter):
    provider_name = "claude"

    def parse_export(self, export_file: Path, payload: dict[str, Any]) -> list[NormalizedEvent]:
        account_id = str(payload.get("account_id", "default"))
        conversations = payload.get("conversations", payload.get("chats", []))
        events: list[NormalizedEvent] = []

        for conv in conversations:
            conversation_id = str(conv.get("id", conv.get("uuid", "unknown-conversation")))
            messages = conv.get("messages", conv.get("chat_messages", []))
            for msg in messages:
                message_id = str(msg.get("id", msg.get("uuid", f"{conversation_id}-msg-{len(events)}")))
                role = str(msg.get("role", msg.get("sender", "unknown"))).lower()
                content = self._extract_content(msg)
                timestamp = msg.get("created_at", msg.get("timestamp", msg.get("createdAt")))
                tool_name = msg.get("tool_name")
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
                        tool_name=tool_name,
                        metadata={"title": conv.get("title", ""), "raw_role": msg.get("role")},
                    )
                )
        return events

    @staticmethod
    def _extract_content(message: dict[str, Any]) -> str:
        if isinstance(message.get("content"), str):
            return message["content"]
        if isinstance(message.get("text"), str):
            return message["text"]
        content = message.get("content", [])
        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                if isinstance(item, dict):
                    text = item.get("text")
                    if isinstance(text, str):
                        parts.append(text)
                elif isinstance(item, str):
                    parts.append(item)
            return "\n".join(parts)
        return ""
