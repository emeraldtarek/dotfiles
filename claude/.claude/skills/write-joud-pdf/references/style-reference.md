# Style Reference

Complete element styling for `write-joud-pdf` outputs.

## Brand tokens (CSS custom properties in `assets/style.css`)

| Token | Value | Usage |
|---|---|---|
| `--brand-primary` | `#B0506A` | Rose — eyebrows, section bars, links, accents |
| `--brand-accent` | `#3D1828` | Deep maroon — body H1/H2, table headers, strong text |
| `--brand-secondary` | `#7A4558` | Mauve — middle stop in cover stripe gradient |
| `--ink` | `#1A1C1C` | Body text |
| `--ink-soft` | `#3D1828` | Secondary text, em, blockquote text |
| `--muted` | `#7A6E74` | Footnotes, labels, captions, header text |
| `--line` | `#E8E0E3` | Borders and rules |
| `--bg-soft` | `#F7F5FA` | Code blocks, callouts, table stripes |
| `--bg-muted` | `#EDEAF4` | Cover background bottom |

## Element styling

| Element | Treatment |
|---|---|
| Cover title (h1) | 32pt, weight 800, deep maroon, with rose→maroon accent bar |
| Cover eyebrow | 9.5pt uppercase rose, letter-spaced |
| Cover meta grid | 2-col key/value, top + bottom hairline rules |
| Running header | Logo + brand name + document kind, single line, no separator rule |
| Running footer | Rose→maroon stripe + "Confidential" (left), "Page N" (right) |
| Body H1 | 20pt bold deep-maroon |
| Body H2 | 14pt bold deep-maroon with rose left bar |
| Body H3 | 11.5pt bold ink-soft |
| Body H4 | Rose uppercase eyebrow style |
| Tables | Deep-maroon header row, zebra-striped rows |
| Blockquotes | Soft bg, rose left border |
| Code blocks | Soft bg, hairline border, rose left rule |
| Links | Rose with subtle underline |

## Raw-HTML components

The markdown body accepts raw HTML for branded components.

### Callout box

```html
<div class="callout">
  <strong>Heads up:</strong> Important takeaway here.
</div>
```

### Terms table (label/value)

```html
<table class="terms-table">
  <tr><td class="label">Project</td><td class="value">Joud Voice Agents</td></tr>
  <tr><td class="label">Started</td><td class="value">May 8, 2026</td></tr>
</table>
```

## Frontmatter reference

| Field | Default | Purpose |
|---|---|---|
| `title` | first H1 in body | Cover-page big title |
| `subtitle` | (none) | Smaller line under title |
| `eyebrow` | "Joud AI" | Small uppercase rose line above title |
| `brand_name` | "Joud AI" | Header brand name |
| `brand_tag` | "Voice agents for healthcare" | Tagline under brand on cover |
| `document_kind` | "Document" | Header label, e.g. "Technical Primer" |
| `meta` | (none) | List of `{label, value}` for cover key/value grid |
| `footer_note` | "Joud AI · Issued <today>" | Cover-page bottom line |
| `confidential_line` | "Confidential — Joud AI" | Running-footer left text |
| `no_cover` | `false` | Skip the cover page entirely |

## Page header design intent

The running header is intentionally minimal — logo + brand name + document kind on a single line, no separator rule beneath. This keeps the header out of the way of dense body content. There is no `audience` field; recipient/audience info should live in the cover page `meta` grid instead.
