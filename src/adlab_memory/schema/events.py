from __future__ import annotations

from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, Field, computed_field


RoleType = Literal["system", "user", "assistant", "tool", "unknown"]


class SourceProvenance(BaseModel):
    provider: str
    account_id: str = "default"
    export_file: Path
    raw_message_id: str


class NormalizedEvent(BaseModel):
    conversation_id: str
    message_id: str
    role: RoleType = "unknown"
    content: str = ""
    timestamp: datetime
    tool_name: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    source: SourceProvenance

    @computed_field
    @property
    def stable_hash(self) -> str:
        identity = "|".join(
            [
                self.source.provider,
                self.source.account_id,
                self.conversation_id,
                self.message_id,
                self.role,
                self.content.strip(),
                str(int(self.timestamp.timestamp())),
            ]
        )
        return sha256(identity.encode("utf-8")).hexdigest()


class NormalizedManifest(BaseModel):
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    total_events: int
    unique_events: int
    providers: dict[str, int]
    duplicates_removed: int


__all__ = [
    "RoleType",
    "SourceProvenance",
    "NormalizedEvent",
    "NormalizedManifest",
]
