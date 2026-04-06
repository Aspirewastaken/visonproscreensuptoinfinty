from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .tools import (
    memory_add_note,
    memory_decay_run,
    memory_get_context,
    memory_mark_superseded,
    memory_search,
)
from adlab_memory.schema.wiki import WikiArticleRecord


class MCPMemoryServer:
    """Minimal MCP-like server shell for local integration tests."""

    def __init__(self, wiki_root: Path) -> None:
        self.wiki_root = wiki_root

    def call(self, name: str, payload: dict[str, Any]) -> dict[str, Any]:
        if name == "memory_search":
            return {"results": memory_search(self.wiki_root, payload["query"], payload.get("limit", 10))}
        if name == "memory_get_context":
            return {"results": memory_get_context(self.wiki_root, payload["topic"])}
        if name == "memory_add_note":
            article = WikiArticleRecord(
                article_id=payload["article_id"],
                title=payload["title"],
                category=payload.get("category", "note"),
                body=payload["content"],
                tags=list(payload.get("tags", [])),
            )
            path = memory_add_note(self.wiki_root, article)
            return {"path": str(path)}
        if name == "memory_mark_superseded":
            memory_mark_superseded(self.wiki_root, payload["target_article_id"], payload["new_article_id"])
            return {"ok": True}
        if name == "memory_decay_run":
            memory_decay_run(self.wiki_root, payload.get("now_iso"))
            return {"ok": True}
        raise ValueError(f"Unknown tool: {name}")

    def describe_tools(self) -> list[dict[str, Any]]:
        return [
            {"name": "memory_search", "description": "Search wiki articles by text"},
            {"name": "memory_get_context", "description": "Get article by topic/slug"},
            {"name": "memory_add_note", "description": "Create wiki note article"},
            {"name": "memory_mark_superseded", "description": "Mark old article ID superseded by new article ID"},
            {"name": "memory_decay_run", "description": "Run decay scoring and archive cold articles"},
        ]

    def to_json(self) -> str:
        return json.dumps({"tools": self.describe_tools()}, indent=2)
