from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from adlab_memory.wiki.article import new_article, save_article
from adlab_memory.wiki.decay import apply_decay_to_article
from adlab_memory.wiki.link_graph import build_link_graph
from adlab_memory.wiki.supersession import detect_conflicts, mark_superseded


def test_article_round_trip_and_graph(tmp_path: Path) -> None:
    now = datetime(2026, 4, 6, tzinfo=timezone.utc)
    article_a = new_article(
        category="architecture",
        title="local memory pipeline",
        summary="First summary.",
        decisions=["Use local ingestion."],
        open_questions=["How to scale?"],
        links=["concept:mission"],
        sources=["test:a"],
        confidence=0.8,
        now=now,
    )
    article_b = new_article(
        category="architecture",
        title="local memory pipeline v2",
        summary="Second summary.",
        decisions=["Use local ingestion with checkpoints."],
        open_questions=[],
        links=[],
        sources=["test:b"],
        confidence=0.85,
        now=now + timedelta(minutes=1),
    )

    save_article(article_a, tmp_path)
    save_article(article_b, tmp_path)

    graph = build_link_graph(tmp_path)
    assert graph.total_articles == 2
    assert article_b.article_id in graph.orphan_ids

    conflicts = detect_conflicts(tmp_path)
    assert article_b.article_id in conflicts


def test_mark_superseded_and_decay() -> None:
    now = datetime(2026, 4, 6, tzinfo=timezone.utc)
    old = new_article(
        category="ops",
        title="backup strategy",
        summary="old",
        decisions=["Use manual backups."],
        open_questions=[],
        links=[],
        sources=["s1"],
        confidence=0.5,
        now=now - timedelta(days=20),
    )
    new = new_article(
        category="ops",
        title="backup strategy update",
        summary="new",
        decisions=["Use automated backups."],
        open_questions=[],
        links=[],
        sources=["s2"],
        confidence=0.9,
        now=now,
    )

    updated = mark_superseded([old, new], old_article_id=old.article_id, new_article_id=new.article_id)
    assert len(updated) == 2
    assert new.article_id in old.contradicts
    assert old.article_id in new.supersedes

    old_heat = old.heat
    decayed = apply_decay_to_article(old, now=now + timedelta(days=30))
    assert decayed.heat <= old_heat

