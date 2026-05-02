#!/usr/bin/env python3
"""Build all-urls.txt and all-urls.json from a docs sitemap.

Usage:
    build_url_list.py --root <root-url> [--prefix <url-prefix> ...] [--exclude <substring> ...] [--sitemap <url>]

Examples:
    # Whole docs tree under elevenlabs.io
    build_url_list.py --root https://elevenlabs.io/docs/eleven-agents/overview \\
        --prefix https://elevenlabs.io/docs/eleven-agents/

    # Multiple prefixes (agents docs + agent-relevant API ref)
    build_url_list.py --root https://elevenlabs.io/docs/eleven-agents/overview \\
        --prefix https://elevenlabs.io/docs/eleven-agents/ \\
        --prefix https://elevenlabs.io/docs/api-reference/agents/ \\
        --prefix https://elevenlabs.io/docs/api-reference/conversations/

If --prefix is omitted, the script falls back to "every URL in the sitemap that
shares the path prefix of --root up to the last `/`".

The sitemap URL is auto-discovered: `<host>/<docs-prefix>/sitemap.xml` first,
then `<host>/sitemap.xml`. Override with --sitemap.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request
from typing import Iterable

ROOT = pathlib.Path(__file__).resolve().parent.parent

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 docs-to-md-bot"
)


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8")


def candidate_sitemaps(root: str) -> list[str]:
    p = urllib.parse.urlparse(root)
    base = f"{p.scheme}://{p.netloc}"
    out: list[str] = []
    # /docs/sitemap.xml when root is /docs/...
    parts = [seg for seg in p.path.split("/") if seg]
    for i in range(len(parts), 0, -1):
        prefix = "/".join(parts[:i])
        out.append(f"{base}/{prefix}/sitemap.xml")
    out.append(f"{base}/sitemap.xml")
    out.append(f"{base}/sitemap_index.xml")
    # de-dupe preserving order
    seen: set[str] = set()
    uniq: list[str] = []
    for u in out:
        if u in seen:
            continue
        seen.add(u)
        uniq.append(u)
    return uniq


def discover_sitemap(root: str) -> tuple[str, str]:
    for url in candidate_sitemaps(root):
        try:
            body = fetch(url)
            if "<urlset" in body or "<sitemapindex" in body:
                return url, body
        except Exception:
            continue
    raise RuntimeError(
        "could not auto-discover sitemap; pass --sitemap <url> explicitly"
    )


def parse_sitemap(body: str) -> list[str]:
    """Extract `<loc>` URLs. Recurses into `<sitemap>` index files."""
    locs = re.findall(r"<loc>([^<]+)</loc>", body)
    if "<sitemapindex" in body:
        out: list[str] = []
        for sub in locs:
            try:
                out.extend(parse_sitemap(fetch(sub)))
            except Exception as e:
                print(f"  ! failed to fetch sub-sitemap {sub}: {e}", file=sys.stderr)
        return out
    return locs


def filter_urls(
    urls: Iterable[str],
    prefixes: list[str],
    excludes: list[str],
) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for u in urls:
        if not any(u.startswith(p) for p in prefixes):
            continue
        if any(x in u for x in excludes):
            continue
        if u in seen:
            continue
        seen.add(u)
        out.append(u)
    out.sort()
    return out


def default_prefix(root: str) -> str:
    """Fallback prefix when none supplied: everything sharing root's directory."""
    if root.endswith("/"):
        return root
    # Trim final path segment (e.g. "/overview")
    return root.rsplit("/", 1)[0] + "/"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="canonical docs root URL")
    ap.add_argument(
        "--prefix",
        action="append",
        default=[],
        help="only keep URLs starting with this prefix (repeatable)",
    )
    ap.add_argument(
        "--exclude",
        action="append",
        default=[],
        help="drop URLs containing this substring (repeatable)",
    )
    ap.add_argument("--sitemap", help="explicit sitemap URL (skip auto-discovery)")
    ap.add_argument(
        "--out",
        default=str(ROOT),
        help="output dir (default: parent of scripts/)",
    )
    args = ap.parse_args(argv)

    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.sitemap:
        print(f"Fetching {args.sitemap}", file=sys.stderr)
        body = fetch(args.sitemap)
        sm_url = args.sitemap
    else:
        sm_url, body = discover_sitemap(args.root)
        print(f"Auto-discovered sitemap: {sm_url}", file=sys.stderr)

    raw = parse_sitemap(body)
    print(f"Sitemap entries: {len(raw)}", file=sys.stderr)

    prefixes = args.prefix or [default_prefix(args.root)]
    print(f"Filter prefixes: {prefixes}", file=sys.stderr)

    urls = filter_urls(raw, prefixes, args.exclude)
    print(f"Filtered to: {len(urls)} URLs", file=sys.stderr)
    if not urls:
        print("⚠ no URLs matched — check --prefix / --exclude", file=sys.stderr)
        return 1

    (out_dir / "all-urls.txt").write_text("\n".join(urls) + "\n")
    payload = {"count": len(urls), "urls": [{"url": u, "text": ""} for u in urls]}
    (out_dir / "all-urls.json").write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Wrote {out_dir / 'all-urls.txt'}", file=sys.stderr)
    print(f"Wrote {out_dir / 'all-urls.json'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
