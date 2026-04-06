from __future__ import annotations

from datetime import datetime, timezone

from pydantic import BaseModel, Field


class WikiArticleRecord(BaseModel):
    article_id: str
    title: str
    category: str
    body: str
    tags: list[str] = Field(default_factory=list)
    heat: int = Field(default=50, ge=0, le=100)
    reinforced: int = Field(default=0, ge=0)
    decay_date: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    superseded_by: str | None = None
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


__all__ = ["WikiArticleRecord"]

