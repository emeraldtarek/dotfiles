---
name: write-joud-pdf
description: Produces a branded Joud AI document (markdown + HTML + PDF) with the official Joud styling — deep-maroon palette (#3D1828) with rose accent (#B0506A), Inter / Plus Jakarta Sans fonts, gradient cover page, running header/footer with page numbers, SVG logo. Use this skill whenever the user wants any document that should look like it came from Joud AI — internal briefs, technical primers, memos, one-pagers, customer-facing reports, board updates — even if they don't explicitly say "branded PDF". Triggers on `/write-joud-pdf`, "joud doc/brief/memo", "branded joud doc", "make this look joud", or any context where a Joud AI document is being authored, updated, or regenerated.
---

# Write Joud PDF

Produces three artifacts from one markdown source: `<name>.md` (with YAML frontmatter), `<name>.html` (self-contained — logo embedded as base64), and `<name>.pdf` (Letter, with cover page and running header/footer).

## Quick start

```bash
uv run ~/.claude/skills/write-joud-pdf/scripts/render.py path/to/doc.md
# → writes path/to/doc.html and path/to/doc.pdf next to the source
```

`uv` provisions an ephemeral cached venv from the script's PEP 723 inline metadata — no `pip install`, no system pollution. First run is ~5–10s while it caches deps; subsequent runs are instant.

### macOS dependency note

WeasyPrint dlopens Pango/Cairo/GLib at runtime. On Apple Silicon Macs with Homebrew, set `DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib` so the C libs resolve:

```bash
DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib \
  uv run ~/.claude/skills/write-joud-pdf/scripts/render.py path/to/doc.md
```

If you hit `cannot load library 'libgobject-2.0-0'`, install the libs once with: `brew install pango cairo gdk-pixbuf glib harfbuzz`.

## Layout

```
write-joud-pdf/
├── SKILL.md                  # this file
├── scripts/
│   └── render.py             # md → html → pdf (deps via PEP 723)
├── assets/
│   ├── style.css             # Joud brand stylesheet
│   └── logo.svg              # Joud icon — embedded as base64 SVG in output
└── references/
    ├── example.md            # full frontmatter sample with all fields
    └── style-reference.md    # element styling table + raw-HTML components
```

## Workflow

1. **Confirm/infer with the user**: doc kind (technical primer, brief, memo…), title, subtitle, output dir + filename. Default output dir is the cwd; default filename is kebab-cased title.
2. **Write the markdown** with YAML frontmatter — see `references/example.md` for a copy-paste scaffold with every field. Frontmatter fields are all optional; sane defaults exist.
3. **Render**: `uv run ~/.claude/skills/write-joud-pdf/scripts/render.py <doc.md>` (with the `DYLD_FALLBACK_LIBRARY_PATH` prefix on macOS if needed).
4. **Confirm** with the user where the three files landed and offer tweaks.

## Markdown → output mapping

- `## Heading` → branded section header with rose left bar
- `### / ####` → secondary headings
- Tables → dark-maroon header row, zebra-striped rows
- Blockquotes, code blocks, links → all branded
- For raw-HTML components (`.callout`, `.terms-table`) and the full element styling reference, see [references/style-reference.md](references/style-reference.md).

## Common follow-ups

- **Drop the cover** — set `no_cover: true` in frontmatter
- **Add cover meta grid** — set `meta:` list of `{label, value}` items
- **Custom footer line** — set `confidential_line: "..."` in frontmatter (default "Confidential — Joud AI")
- **Change accent color** — edit `assets/style.css` (`--brand-primary`, `--brand-accent`)

## Notes

- The HTML output is **fully self-contained** (logo embedded as data-URI) — emailable / openable on any machine without the skill folder.
- Rendering uses **WeasyPrint** which faithfully supports CSS Paged Media (`@page`, running elements, `counter(page)`). Do **not** swap in Chrome headless — it doesn't render the running header/footer.
- The cover page (page 1) suppresses header/footer via `@page :first`. Page numbering starts at the cover but is hidden until page 2.
- Page header is intentionally minimal: logo + brand name + document kind on a single line, no separator rule. Designed to stay out of the way of the document content.
