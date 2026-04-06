from __future__ import annotations

import json
from pathlib import Path

from adlab_memory.ingest.base import ProviderAdapter
from adlab_memory.ingest.chatgpt import ChatGPTAdapter
from adlab_memory.ingest.claude import ClaudeAdapter
from adlab_memory.ingest.gemini import GeminiAdapter
from adlab_memory.ingest.grok import GrokAdapter
from adlab_memory.schema.events import NormalizedEvent, NormalizedManifest


def build_registry() -> dict[str, ProviderAdapter]:
    adapters: list[ProviderAdapter] = [
        ClaudeAdapter(),
        ChatGPTAdapter(),
        GrokAdapter(),
        GeminiAdapter(),
    ]
    return {adapter.provider_name: adapter for adapter in adapters}


def ingest_exports(
    *,
    input_root: Path,
    normalized_root: Path,
    providers: list[str],
    include_globs: list[str],
) -> tuple[list[NormalizedEvent], NormalizedManifest]:
    registry = build_registry()
    normalized_root.mkdir(parents=True, exist_ok=True)

    events: list[NormalizedEvent] = []
    provider_counts: dict[str, int] = {}

    for provider in providers:
        adapter = registry.get(provider)
        if adapter is None:
            continue
        provider_dir = input_root / provider
        if not provider_dir.exists():
            provider_counts[provider] = 0
            continue

        files: list[Path] = []
        for pattern in include_globs:
            files.extend(provider_dir.rglob(pattern))

        count_for_provider = 0
        for file in sorted(set(files)):
            payload = json.loads(file.read_text())
            parsed = adapter.parse_export(file, payload)
            events.extend(parsed)
            count_for_provider += len(parsed)
        provider_counts[provider] = count_for_provider

    deduped: list[NormalizedEvent] = []
    seen: set[str] = set()
    for event in sorted(events, key=lambda e: e.timestamp):
        if event.stable_hash in seen:
            continue
        seen.add(event.stable_hash)
        deduped.append(event)

    for provider in providers:
        provider_events = [e for e in deduped if e.source.provider == provider]
        output = normalized_root / f"{provider}.jsonl"
        lines = [event.model_dump_json() for event in provider_events]
        output.write_text("\n".join(lines) + ("\n" if lines else ""))

    manifest = NormalizedManifest(
        total_events=len(events),
        unique_events=len(deduped),
        providers=provider_counts,
        duplicates_removed=len(events) - len(deduped),
    )
    (normalized_root / "manifest.json").write_text(manifest.model_dump_json(indent=2))

    return deduped, manifest
