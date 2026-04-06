from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from adlab_memory.wiki.article import WikiArticle


def apply_decay_to_article(article: WikiArticle, *, now: datetime | None = None) -> WikiArticle:
    now = now or datetime.now(timezone.utc)
    age_days = max(0, int((now - article.last_updated).days))
    decay_factor = max(0.15, 1 - age_days / 120)
    article.heat = max(1, int(article.heat * decay_factor))
    article.decay_date = now + timedelta(days=max(7, 120 - article.heat))
    article.last_updated = now
    return article


def decay_wiki_directory(wiki_root: Path, *, now: datetime | None = None) -> int:
    count = 0
    for path in sorted(wiki_root.glob("*.md")):
        article = WikiArticle.from_markdown(path.read_text())
        updated = apply_decay_to_article(article, now=now)
        path.write_text(updated.to_markdown())
        count += 1
    return count


def apply_decay(articles: list[WikiArticle], on_date: str | None = None) -> list[WikiArticle]:
    now = datetime.now(timezone.utc)
    if on_date:
        now = datetime.fromisoformat(on_date)
    return [apply_decay_to_article(article, now=now) for article in articles]
