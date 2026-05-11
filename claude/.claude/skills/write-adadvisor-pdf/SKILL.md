---
name: write-adadvisor-pdf
description: Produces a branded Ad Advisor AI document (markdown + HTML + PDF) with the official AdAdvisor styling — logo, magenta/orange accent palette, Helvetica Neue, gradient cover page, running header/footer with page numbers. Use this skill whenever the user wants any document that should look like it came from Ad Advisor AI — offer letters, contractor agreements, internal briefs, memos, one-pagers, proposals, statements of work, board updates — even if they don't explicitly say "branded PDF". Triggers on `/write-adadvisor-pdf`, "adadvisor letter/memo/brief", "offer letter", "branded doc", "make this look adadvisor", or any context where an existing AdAdvisor document is being authored, updated, or regenerated.
---

# Write AdAdvisor PDF

Produces three artifacts from one markdown source: `<name>.md` (with YAML frontmatter), `<name>.html` (self-contained — logo embedded as base64), and `<name>.pdf` (Letter, with cover page and running header/footer).

## Quick start

```bash
uv run ~/.claude/skills/write-adadvisor-pdf/scripts/render.py path/to/doc.md
# → writes path/to/doc.html and path/to/doc.pdf next to the source
```

`uv` provisions an ephemeral cached venv from the script's PEP 723 inline metadata — no `pip install`, no system pollution. First run is ~5–10s while it caches deps; subsequent runs are instant.

## Layout

```
write-adadvisor-pdf/
├── SKILL.md                  # this file
├── scripts/
│   └── render.py             # md → html → pdf (deps via PEP 723)
├── assets/
│   ├── style.css             # brand stylesheet
│   └── logo.png              # gets embedded as base64 in output
└── references/
    ├── example.md            # full frontmatter sample with all fields
    └── style-reference.md    # element styling table + raw-HTML components
```

## Workflow

1. **Confirm/infer with the user**: doc kind (offer letter, brief, memo…), title, subtitle, recipient, output dir + filename. Default output dir is the cwd; default filename is kebab-cased title.
2. **Write the markdown** with YAML frontmatter — see `references/example.md` for a copy-paste scaffold with every field. Frontmatter fields are all optional; sane defaults exist.
3. **Render**: `uv run ~/.claude/skills/write-adadvisor-pdf/scripts/render.py <doc.md>`
4. **Confirm** with the user where the three files landed and offer tweaks.

## Markdown → output mapping

- `## Heading` → branded section header with magenta left bar
- `### / ####` → secondary headings
- Tables → dark-navy header row, zebra-striped rows
- Blockquotes, code blocks, links → all branded
- For raw-HTML components (`.callout`, `.terms-table`) and the full element styling reference, see [references/style-reference.md](references/style-reference.md).

## Common follow-ups

- **Drop the cover** — set `no_cover: true` in frontmatter
- **Recipient on cover** — add to `meta:` (e.g. `- label: Issued To, value: <name>`); the header is intentionally minimal and doesn't render audience
- **Add cover meta grid** — set `meta:` list of `{label, value}` items
- **Change accent color** — edit `assets/style.css` (`--brand-primary`, `--brand-accent`)

## Writing style

- **No em dashes (`—`) in body copy, headings, callouts, or frontmatter.** They get overused and read as noisy. Replace with the punctuation that fits the actual relationship between the clauses:
  - Light pause / contrast → comma
  - Elaboration / list intro → colon
  - Strong sentence break → period + new sentence
  - Aside / parenthetical → parentheses
  - Closely related independent clauses → semicolon
  - Section-header divider (e.g. `Section One: Existing Partners`) → colon, not em dash
- Hyphens (`-`) and en-dashes (`–`, for numeric ranges like `1–2 years`) are fine. Reach for an em dash only if no other punctuation actually fits, and that should be rare.

## Notes

- The HTML output is **fully self-contained** (logo embedded as data-URI) — emailable / openable on any machine without the skill folder.
- Rendering uses **WeasyPrint** which faithfully supports CSS Paged Media (`@page`, running elements, `counter(page)`). Do **not** swap in Chrome headless — it doesn't render the running header/footer.
- The cover page (page 1) suppresses header/footer via `@page :first`. Page numbering starts at the cover but is hidden until page 2.
