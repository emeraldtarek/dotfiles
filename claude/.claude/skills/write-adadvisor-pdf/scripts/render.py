#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "markdown>=3.5",
#   "weasyprint>=60",
#   "pyyaml>=6",
# ]
# ///
"""
Render an Ad Advisor AI-branded document.

Input:  a markdown file with optional YAML frontmatter for the cover page.
Output: <name>.html (self-contained, logo embedded as base64) and <name>.pdf
        next to the input (or in -o <dir>).

Frontmatter fields (all optional):
  title          Big title on the cover (defaults to first H1 in the body)
  subtitle       Smaller line under the title
  eyebrow        Small uppercase magenta line above the title (default "Ad Advisor AI")
  brand_name     Header brand name (default "Ad Advisor AI")
  brand_tag      Tagline under brand name (default "AI-Native Growth, on Autopilot")
  document_kind  Header label, e.g. "Offer Letter" (default "Document")
  audience       Top-right header label (e.g. recipient name)
  meta           List of {label, value} dicts for the cover key/value grid
  footer_note    Cover footer line (default "Ad Advisor AI · Issued <today>")
  no_cover       If true, skip the cover page entirely

Usage:
  uv run scripts/render.py path/to/input.md
  uv run scripts/render.py path/to/input.md -o out/
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import html
import re
import sys
from pathlib import Path
from typing import Any

import markdown
import weasyprint
import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
LOGO_PATH = SKILL_DIR / "assets" / "logo.png"
CSS_PATH = SKILL_DIR / "assets" / "style.css"


def split_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    """Pull leading --- ... --- YAML block off a markdown string."""
    if not text.startswith("---"):
        return {}, text
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n?", text, re.DOTALL)
    if not m:
        return {}, text
    try:
        data = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        data = {}
    return data, text[m.end():]


def extract_first_h1(md_body: str) -> str | None:
    m = re.search(r"^#\s+(.+?)\s*$", md_body, re.MULTILINE)
    return m.group(1).strip() if m else None


def encode_logo() -> str:
    if not LOGO_PATH.exists():
        return ""
    data = base64.b64encode(LOGO_PATH.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{data}"


def render_body(md_body: str) -> str:
    md = markdown.Markdown(
        extensions=[
            "extra",          # tables, fenced code, attr_list, etc.
            "sane_lists",
            "smarty",
            "toc",
        ],
        output_format="html5",
    )
    return md.convert(md_body)


def render_meta_grid(meta: list[dict[str, Any]]) -> str:
    if not meta:
        return ""
    fields = []
    for item in meta:
        label = html.escape(str(item.get("label", "")))
        value = html.escape(str(item.get("value", "")))
        fields.append(
            f'<div class="field"><div class="label">{label}</div>'
            f'<div class="value">{value}</div></div>'
        )
    return f'<div class="meta">{"".join(fields)}</div>'


def render_cover(fm: dict[str, Any], md_body: str, logo_uri: str) -> tuple[str, str]:
    title = fm.get("title") or extract_first_h1(md_body) or "Untitled"
    subtitle = fm.get("subtitle", "")
    eyebrow = fm.get("eyebrow", "Ad Advisor AI")
    brand_name = fm.get("brand_name", "Ad Advisor AI")
    brand_tag = fm.get("brand_tag", "AI-Native Growth, on Autopilot")
    today = dt.date.today().strftime("%B %d, %Y")
    footer_note = fm.get(
        "footer_note",
        f"Ad Advisor AI · Issued {today}",
    )
    meta_html = render_meta_grid(fm.get("meta") or [])

    cover_html = f"""
<section class="cover">
  <div class="top">
    <img src="{logo_uri}" alt="Ad Advisor AI logo">
    <div class="brand">
      <div class="name">{html.escape(brand_name)}</div>
      <div class="tag">{html.escape(brand_tag)}</div>
    </div>
  </div>

  <div class="middle">
    <div class="eyebrow">{html.escape(eyebrow)}</div>
    <h1><span class="accent-bar"></span>{html.escape(title)}</h1>
    {f'<h2 class="subtitle">{html.escape(subtitle)}</h2>' if subtitle else ''}
    {meta_html}
  </div>

  <div class="bottom">
    <div class="stripe"></div>
    {html.escape(footer_note)}
  </div>
</section>
""".strip()
    return cover_html, title


def build_html(md_text: str, css: str, logo_uri: str) -> tuple[str, str]:
    fm, md_body = split_frontmatter(md_text)
    body_html = render_body(md_body)

    no_cover = bool(fm.get("no_cover"))
    document_kind = html.escape(str(fm.get("document_kind", "Document")))
    audience = html.escape(str(fm.get("audience", "")))
    brand_name = html.escape(str(fm.get("brand_name", "Ad Advisor AI")))

    if no_cover:
        cover_html = ""
        title = fm.get("title") or extract_first_h1(md_body) or "Document"
    else:
        cover_html, title = render_cover(fm, md_body, logo_uri)

    page_header = f"""
<div class="page-header">
  <div class="left">
    <img src="{logo_uri}" alt="">
    <span><strong>{brand_name}</strong> &nbsp;·&nbsp; {document_kind}</span>
  </div>
  <div>{audience}</div>
</div>
""".strip()

    page_footer = f"""
<div class="page-footer">
  <div><span class="accent"></span>Confidential — Ad Advisor AI</div>
  <div>Page <span class="pageno"></span></div>
</div>
""".strip()

    full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>{html.escape(title)}</title>
<style>{css}</style>
</head>
<body>
{page_header}
{page_footer}
{cover_html}
<section class="body">
{body_html}
</section>
</body>
</html>
"""
    return full_html, title


def main() -> int:
    ap = argparse.ArgumentParser(description="Render an AdAdvisor-branded markdown doc to HTML+PDF.")
    ap.add_argument("input", help="Path to markdown file")
    ap.add_argument("-o", "--out-dir", help="Output directory (default: alongside input)")
    args = ap.parse_args()

    in_path = Path(args.input).expanduser().resolve()
    if not in_path.exists():
        print(f"error: {in_path} not found", file=sys.stderr)
        return 1

    out_dir = Path(args.out_dir).expanduser().resolve() if args.out_dir else in_path.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = in_path.stem
    html_path = out_dir / f"{stem}.html"
    pdf_path = out_dir / f"{stem}.pdf"

    md_text = in_path.read_text(encoding="utf-8")
    css = CSS_PATH.read_text(encoding="utf-8")
    logo_uri = encode_logo()

    full_html, title = build_html(md_text, css, logo_uri)
    html_path.write_text(full_html, encoding="utf-8")

    weasyprint.HTML(string=full_html, base_url=str(out_dir)).write_pdf(str(pdf_path))

    print(f"wrote {html_path}")
    print(f"wrote {pdf_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
