from __future__ import annotations

from dataclasses import asdict
from pathlib import Path
from typing import Any

from adlab_memory.schema.wiki import WikiArticleRecord
from adlab_memory.wiki.article import WikiArticle as MarkdownWikiArticle
from adlab_memory.wiki.article import save_article
from adlab_memory.wiki.decay import apply_decay_to_article
from adlab_memory.wiki.supersession import mark_superseded


def _load_articles(wiki_dir: Path) -> list[MarkdownWikiArticle]:
    articles: list[MarkdownWikiArticle] = []
    for path in sorted(wiki_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        if not text.startswith("---\n"):
            continue
        articles.append(MarkdownWikiArticle.from_markdown(text))
    return articles


def memory_search(wiki_dir: Path, query: str, limit: int = 5) -> list[dict[str, Any]]:
    query_l = query.lower().strip()
    if not query_l:
        return []
    scored: list[tuple[int, MarkdownWikiArticle]] = []
    for article in _load_articles(wiki_dir):
        corpus = " ".join(
            [
                article.title,
                article.summary,
                *article.decisions,
                *article.open_questions,
                *article.links,
                *article.sources,
            ]
        ).lower()
        score = corpus.count(query_l)
        if score > 0:
            scored.append((score, article))
    scored.sort(key=lambda x: (-x[0], x[1].title))
    return [asdict(a) for _, a in scored[:limit]]


def memory_get_context(wiki_dir: Path, tag: str, limit: int = 10) -> list[dict[str, Any]]:
    tag_l = tag.lower().strip()
    if not tag_l:
        return []
    matches = [
        a
        for a in _load_articles(wiki_dir)
        if tag_l in a.category.lower() or any(tag_l in link.lower() for link in a.links)
    ]
    matches.sort(key=lambda a: (a.decay_date, -a.heat, a.title))
    return [asdict(a) for a in matches[:limit]]


def memory_add_note(wiki_dir: Path, article: WikiArticleRecord) -> Path:
    md = MarkdownWikiArticle(
        article_id=article.article_id,
        title=article.title,
        category=article.category,
        summary=article.body,
        decisions=[],
        open_questions=[],
        links=[f"tag:{tag}" for tag in article.tags],
        sources=["mcp:memory_add_note"],
        confidence=0.8,
        heat=article.heat,
        reinforced=article.reinforced,
        decay_date=article.decay_date,
        supersedes=[article.superseded_by] if article.superseded_by else [],
        contradicts=[],
        last_updated=article.updated_at,
    )
    return save_article(md, wiki_dir)


def memory_mark_superseded(wiki_dir: Path, old_article_id: str, new_article_id: str) -> None:
    articles = _load_articles(wiki_dir)
    updated = mark_superseded(articles, old_article_id=old_article_id, new_article_id=new_article_id)
    for article in updated:
        save_article(article, wiki_dir)


def memory_decay_run(wiki_dir: Path, on_date: str | None = None) -> None:
    now = None
    if on_date:
        from datetime import datetime

        now = datetime.fromisoformat(on_date)
    articles = _load_articles(wiki_dir)
    updated = [apply_decay_to_article(article, now=now) for article in articles]
    for article in updated:
        save_article(article, wiki_dir)

