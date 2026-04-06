from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from hashlib import sha1
from pathlib import Path

import yaml


@dataclass(slots=True)
class WikiArticle:
    article_id: str
    title: str
    category: str
    summary: str
    decisions: list[str]
    open_questions: list[str]
    links: list[str]
    sources: list[str]
    confidence: float
    heat: int
    reinforced: int
    decay_date: datetime
    supersedes: list[str]
    contradicts: list[str]
    last_updated: datetime

    def to_markdown(self) -> str:
        frontmatter = {
            "id": self.article_id,
            "title": self.title,
            "category": self.category,
            "last_updated": self.last_updated.isoformat(),
            "heat": self.heat,
            "reinforced": self.reinforced,
            "decay_date": self.decay_date.isoformat(),
            "sources": self.sources,
            "confidence": round(self.confidence, 4),
            "links": self.links,
            "supersedes": self.supersedes,
            "contradicts": self.contradicts,
        }
        decisions = [f"- {item}" for item in self.decisions] or ["- None"]
        questions = [f"- {item}" for item in self.open_questions] or ["- None"]
        links = [f"- {item}" for item in self.links] or ["- None"]
        sections = [
            "---",
            yaml.safe_dump(frontmatter, sort_keys=False).strip(),
            "---",
            "",
            "## Summary",
            self.summary.strip() or "No summary.",
            "",
            "## Decisions",
            *decisions,
            "",
            "## Open Questions",
            *questions,
            "",
            "## Links",
            *links,
            "",
        ]
        return "\n".join(sections)

    @classmethod
    def from_markdown(cls, markdown: str) -> "WikiArticle":
        _, fm, body = markdown.split("---", 2)
        frontmatter = yaml.safe_load(fm.strip())

        body_lines = [line.rstrip() for line in body.strip().splitlines()]
        summary = _extract_section(body_lines, "Summary")
        decisions = _extract_list_section(body_lines, "Decisions")
        open_questions = _extract_list_section(body_lines, "Open Questions")
        links = _extract_list_section(body_lines, "Links")

        return cls(
            article_id=frontmatter["id"],
            title=frontmatter["title"],
            category=frontmatter["category"],
            summary=summary,
            decisions=decisions,
            open_questions=open_questions,
            links=links,
            sources=list(frontmatter.get("sources", [])),
            confidence=float(frontmatter.get("confidence", 0.0)),
            heat=int(frontmatter.get("heat", 0)),
            reinforced=int(frontmatter.get("reinforced", 0)),
            decay_date=_ensure_timezone(datetime.fromisoformat(frontmatter["decay_date"])),
            supersedes=list(frontmatter.get("supersedes", [])),
            contradicts=list(frontmatter.get("contradicts", [])),
            last_updated=_ensure_timezone(datetime.fromisoformat(frontmatter["last_updated"])),
        )


def build_article_id(category: str, title: str) -> str:
    slug = title.lower().replace(" ", "-")
    digest = sha1(f"{category}:{slug}".encode("utf-8")).hexdigest()[:8]
    return f"{category}-{slug[:48]}-{digest}"


def default_decay(last_updated: datetime, heat: int) -> datetime:
    days = max(7, 120 - heat)
    return last_updated + timedelta(days=days)


def save_article(article: WikiArticle, wiki_root: Path) -> Path:
    wiki_root.mkdir(parents=True, exist_ok=True)
    path = wiki_root / f"{article.article_id}.md"
    path.write_text(article.to_markdown())
    return path


def _extract_section(lines: list[str], section: str) -> str:
    header = f"## {section}"
    in_section = False
    captured: list[str] = []
    for line in lines:
        if line.startswith("## ") and line != header and in_section:
            break
        if line == header:
            in_section = True
            continue
        if in_section:
            captured.append(line)
    return "\n".join(x for x in captured if x).strip()


def _extract_list_section(lines: list[str], section: str) -> list[str]:
    body = _extract_section(lines, section)
    if not body:
        return []
    entries = [line[2:].strip() for line in body.splitlines() if line.startswith("- ")]
    return [entry for entry in entries if entry and entry.lower() != "none"]


def new_article(
    *,
    category: str,
    title: str,
    summary: str,
    decisions: list[str],
    open_questions: list[str],
    links: list[str],
    sources: list[str],
    confidence: float,
    now: datetime | None = None,
) -> WikiArticle:
    now = now or datetime.now(timezone.utc)
    article_id = build_article_id(category, title)
    heat = int(max(1, min(100, round(confidence * 100))))
    return WikiArticle(
        article_id=article_id,
        title=title,
        category=category,
        summary=summary,
        decisions=decisions,
        open_questions=open_questions,
        links=links,
        sources=sources,
        confidence=confidence,
        heat=heat,
        reinforced=0,
        decay_date=default_decay(now, heat),
        supersedes=[],
        contradicts=[],
        last_updated=now,
    )


def _ensure_timezone(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value
