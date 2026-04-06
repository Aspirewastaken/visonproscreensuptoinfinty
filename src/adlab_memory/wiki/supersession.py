from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from adlab_memory.wiki.article import WikiArticle


def detect_conflicts(wiki_root: Path) -> dict[str, list[str]]:
    by_category: dict[str, list[WikiArticle]] = defaultdict(list)
    for path in sorted(wiki_root.glob("*.md")):
        article = WikiArticle.from_markdown(path.read_text())
        by_category[article.category].append(article)

    conflicts: dict[str, list[str]] = {}
    for category, articles in by_category.items():
        if len(articles) < 2:
            continue
        sorted_articles = sorted(articles, key=lambda a: a.last_updated)
        latest = sorted_articles[-1]
        superseded = [a.article_id for a in sorted_articles[:-1] if a.decisions and latest.decisions and a.decisions != latest.decisions]
        if superseded:
            conflicts[latest.article_id] = superseded
            latest.supersedes = sorted(set(latest.supersedes + superseded))
            for article in sorted_articles[:-1]:
                if article.article_id in superseded:
                    article.contradicts = sorted(set(article.contradicts + [latest.article_id]))
                (wiki_root / f"{article.article_id}.md").write_text(article.to_markdown())
            (wiki_root / f"{latest.article_id}.md").write_text(latest.to_markdown())
    return conflicts


def mark_superseded(
    articles: list[WikiArticle],
    *,
    old_article_id: str,
    new_article_id: str,
) -> list[WikiArticle]:
    by_id = {article.article_id: article for article in articles}
    old_article = by_id.get(old_article_id)
    new_article = by_id.get(new_article_id)
    if old_article is None or new_article is None:
        return articles

    now = datetime.now(timezone.utc)
    if new_article.article_id not in old_article.contradicts:
        old_article.contradicts.append(new_article.article_id)
    if old_article.article_id not in new_article.supersedes:
        new_article.supersedes.append(old_article.article_id)
    old_article.last_updated = now
    new_article.last_updated = now
    return articles
