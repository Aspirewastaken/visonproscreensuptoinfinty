from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from adlab_memory.wiki.article import WikiArticle


@dataclass(slots=True)
class LinkGraphReport:
    total_articles: int
    nodes: dict[str, list[str]]
    orphan_ids: list[str]


def build_link_graph(wiki_root: Path) -> LinkGraphReport:
    nodes: dict[str, list[str]] = {}
    for path in sorted(wiki_root.glob("*.md")):
        article = WikiArticle.from_markdown(path.read_text())
        nodes[article.article_id] = list(article.links)

    inbound_count = {article_id: 0 for article_id in nodes}
    for links in nodes.values():
        for link in links:
            if link in inbound_count:
                inbound_count[link] += 1

    orphan_ids = [article_id for article_id, count in inbound_count.items() if count == 0 and not nodes[article_id]]
    return LinkGraphReport(total_articles=len(nodes), nodes=nodes, orphan_ids=sorted(orphan_ids))
