from __future__ import annotations

from pathlib import Path
from typing import Any

from adlab_memory.ingest.base import ProviderAdapter, to_event
from adlab_memory.schema.events import NormalizedEvent


class ChatGPTAdapter(ProviderAdapter):
    provider_name = "chatgpt"

    def parse_export(self, export_file: Path, payload: dict[str, Any]) -> list[NormalizedEvent]:
        account_id = str(payload.get("account_id", "default"))
        conversations = payload.get("conversations", payload.get("chats", []))
        events: list[NormalizedEvent] = []

        for conv in conversations:
            conversation_id = str(conv.get("id", conv.get("conversation_id", "unknown-conversation")))
            mapping = conv.get("mapping")

            if isinstance(mapping, dict):
                for message_id, node in mapping.items():
                    message = (node or {}).get("message") or {}
                    role = str(((message.get("author") or {}).get("role", "unknown"))).lower()
                    content = self._extract_content(message)
                    timestamp = message.get("create_time", message.get("created_at", 0))
                    events.append(
                        to_event(
                            provider=self.provider_name,
                            account_id=account_id,
                            export_file=export_file,
                            conversation_id=conversation_id,
                            message_id=str(message_id),
                            role=role,
                            content=content,
                            timestamp=timestamp,
                            metadata={"title": conv.get("title", "")},
                        )
                    )
            else:
                messages = conv.get("messages", [])
                for msg in messages:
                    message_id = str(msg.get("id", f"{conversation_id}-msg-{len(events)}"))
                    role = str(msg.get("role", "unknown")).lower()
                    content = msg.get("content", msg.get("text", ""))
                    timestamp = msg.get("timestamp", msg.get("create_time", 0))
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

    @staticmethod
    def _extract_content(message: dict[str, Any]) -> str:
        content = message.get("content") or {}
        parts = content.get("parts") if isinstance(content, dict) else None
        if isinstance(parts, list):
            return "\n".join(str(p) for p in parts)
        if isinstance(content, str):
            return content
        return ""
