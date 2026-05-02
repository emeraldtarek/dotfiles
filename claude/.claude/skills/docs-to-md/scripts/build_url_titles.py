#!/usr/bin/env python3
"""Update all-urls.json with titles harvested from each crawled file's frontmatter.

Looks at every `full/*.md` file, reads the `title:` line from its YAML
frontmatter, and rewrites `all-urls.json` with the `text` field populated.

Reconstruction of the URL→filename mapping uses the file's `url:` frontmatter
line (preferred) so it works regardless of the URL prefix the crawl was
configured with.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FULL = ROOT / "full"


def parse_frontmatter(body: str) -> dict[str, str]:
    out: dict[str, str] = {}
    if not body.startswith("---"):
        return out
    end = body.find("\n---", 3)
    if end < 0:
        return out
    block = body[3:end]
    for line in block.splitlines():
        m = re.match(r'^(\w+):\s*"?([^"]*?)"?\s*$', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def main() -> int:
    by_url: dict[str, str] = {}
    for p in sorted(FULL.glob("*.md")):
        fm = parse_frontmatter(p.read_text())
        url = fm.get("url", "")
        title = fm.get("title", "")
        if url:
            by_url[url] = title

    urls_file = ROOT / "all-urls.txt"
    if not urls_file.exists():
        print("missing all-urls.txt — run build_url_list.py first", file=sys.stderr)
        return 1
    urls = [u.strip() for u in urls_file.read_text().splitlines() if u.strip()]

    out = {
        "count": len(urls),
        "urls": [{"url": u, "text": by_url.get(u, "")} for u in urls],
    }
    (ROOT / "all-urls.json").write_text(json.dumps(out, indent=2) + "\n")
    populated = sum(1 for u in urls if by_url.get(u))
    print(f"Wrote all-urls.json with titles for {populated}/{len(urls)} URLs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
