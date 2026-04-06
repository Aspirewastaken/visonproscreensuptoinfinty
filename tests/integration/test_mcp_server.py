from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from adlab_memory.mcp.server import MCPMemoryServer
from adlab_memory.schema.wiki import WikiArticleRecord
from adlab_memory.wiki.article import new_article, save_article


def test_mcp_server_memory_operations(tmp_path: Path) -> None:
    article = new_article(
        category="architecture",
        title="mission memory system",
        summary="This article discusses mission + MCP architecture.",
        decisions=["Use memory_search"],
        open_questions=["How many shards?"],
        links=["tool:mcp"],
        sources=["fixture:test"],
        confidence=0.9,
        now=datetime(2026, 4, 6, tzinfo=timezone.utc),
    )
    save_article(article, tmp_path)

    server = MCPMemoryServer(tmp_path)
    result = server.call("memory_search", {"query": "mission", "limit": 3})
    assert "results" in result
    assert len(result["results"]) >= 1

    new_note = WikiArticleRecord(
        article_id="note-1",
        title="Ops Note",
        category="ops",
        body="Backups run nightly",
        tags=["backup"],
    )
    add_result = server.call(
        "memory_add_note",
        {
            "article_id": new_note.article_id,
            "title": new_note.title,
            "category": new_note.category,
            "content": new_note.body,
            "tags": new_note.tags,
        },
    )
    assert Path(add_result["path"]).exists()

