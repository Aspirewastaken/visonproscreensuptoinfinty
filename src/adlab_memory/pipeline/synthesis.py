from __future__ import annotations

from pathlib import Path

from adlab_memory.wiki import LinkGraphReport, build_link_graph, detect_conflicts


def synthesize_wiki(wiki_root: Path) -> tuple[LinkGraphReport, dict[str, list[str]]]:
    graph = build_link_graph(wiki_root)
    conflicts = detect_conflicts(wiki_root)

    (wiki_root / "CONTRADICTIONS.md").write_text(_format_conflicts(conflicts))
    (wiki_root / "ORPHANS.md").write_text(_format_orphans(graph))
    return graph, conflicts


def _format_conflicts(conflicts: dict[str, list[str]]) -> str:
    lines = ["# Contradictions", ""]
    if not conflicts:
        lines.append("- None detected")
        return "\n".join(lines) + "\n"
    for latest, superseded in sorted(conflicts.items()):
        lines.append(f"- {latest} supersedes: {', '.join(superseded)}")
    return "\n".join(lines) + "\n"


def _format_orphans(report: LinkGraphReport) -> str:
    lines = ["# Orphan Articles", ""]
    if not report.orphan_ids:
        lines.append("- None")
    else:
        lines.extend(f"- {article_id}" for article_id in report.orphan_ids)
    return "\n".join(lines) + "\n"
