from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import re

from adlab_memory.models.local_runner import LocalModelRunner
from adlab_memory.pipeline.chunker import EventChunk
from adlab_memory.pipeline.triage import TriageResult
from adlab_memory.wiki.article import WikiArticle, new_article, save_article


def compile_chunks_to_wiki(
    *,
    chunks: list[EventChunk],
    triage_map: dict[str, TriageResult],
    runner: LocalModelRunner,
    wiki_root: Path,
    low_signal_threshold: float = 0.15,
) -> list[WikiArticle]:
    compiled: list[WikiArticle] = []
    now = datetime.now(timezone.utc)
    for chunk in chunks:
        triage = triage_map[chunk.id]
        if triage.label == "noise" and triage.score >= low_signal_threshold:
            continue

        prompt = build_prompt(chunk, triage)
        summary = runner.generate(prompt).strip() or "No summary produced."
        title = infer_title(chunk, triage)
        decisions = extract_decisions(chunk)
        open_questions = extract_questions(chunk)
        links = infer_links(chunk)
        sources = [f"{event.source.provider}:{event.source.export_file}:{event.message_id}" for event in chunk.events]
        confidence = min(0.99, max(0.2, triage.score + 0.2))

        article = new_article(
            category=triage.label,
            title=title,
            summary=summary,
            decisions=decisions,
            open_questions=open_questions,
            links=links,
            sources=sources,
            confidence=confidence,
            now=now,
        )
        save_article(article, wiki_root)
        compiled.append(article)
    return compiled


def build_prompt(chunk: EventChunk, triage: TriageResult) -> str:
    transcript = "\n".join(
        f"[{event.timestamp.isoformat()}] {event.role}: {event.content}" for event in chunk.events
    )
    return (
        "You are compiling a private wiki article.\n"
        f"Category: {triage.label}\n"
        "Summarize key points, decisions, and unresolved items.\n\n"
        f"Conversation:\n{transcript}"
    )


def infer_title(chunk: EventChunk, triage: TriageResult) -> str:
    corpus = " ".join(event.content for event in chunk.events)
    tokens = re.findall(r"[a-zA-Z][a-zA-Z0-9_-]{3,}", corpus.lower())
    stop = {"this", "that", "with", "from", "have", "will", "your", "about", "into"}
    ranked = [token for token in tokens if token not in stop]
    head = "-".join(ranked[:4]) if ranked else chunk.conversation_id
    return f"{triage.label}-{head[:64]}".replace("--", "-")


def extract_decisions(chunk: EventChunk) -> list[str]:
    decisions: list[str] = []
    markers = ("we will", "decision", "choose", "should", "must", "plan")
    for event in chunk.events:
        content = event.content.strip()
        lower = content.lower()
        if any(marker in lower for marker in markers):
            decisions.append(content[:240])
    return decisions[:6]


def extract_questions(chunk: EventChunk) -> list[str]:
    questions: list[str] = []
    for event in chunk.events:
        for line in event.content.splitlines():
            line = line.strip()
            if line.endswith("?"):
                questions.append(line[:240])
    return questions[:6]


def infer_links(chunk: EventChunk) -> list[str]:
    links: set[str] = set()
    for event in chunk.events:
        lower = event.content.lower()
        if "mcp" in lower:
            links.add("tool:mcp")
        if "mission" in lower:
            links.add("concept:mission")
        if "model" in lower:
            links.add("concept:model-profile")
        if "wiki" in lower:
            links.add("artifact:wiki")
    return sorted(links)
