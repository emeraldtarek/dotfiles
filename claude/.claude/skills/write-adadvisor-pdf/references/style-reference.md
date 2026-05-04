# Style Reference

Complete element styling for `write-adadvisor-pdf` outputs.

## Brand tokens (CSS custom properties in `assets/style.css`)

| Token | Value | Usage |
|---|---|---|
| `--brand-primary` | `#d946ef` | Magenta — eyebrows, section bars, accents |
| `--brand-accent` | `#f97316` | Orange — gradient pair with primary |
| `--ink` | `#0f172a` | Body text, table headers |
| `--ink-soft` | `#334155` | Secondary text, em |
| `--muted` | `#64748b` | Footnotes, labels, captions |
| `--line` | `#e2e8f0` | Borders and rules |
| `--bg-soft` | `#f8fafc` | Code blocks, callouts, table stripes |

## Element styling

| Element | Treatment |
|---|---|
| Cover title (h1) | 32pt, weight 800, ink, with magenta→orange accent bar |
| Cover eyebrow | 9.5pt uppercase magenta, letter-spaced |
| Cover meta grid | 2-col key/value, top + bottom hairline rules |
| Running header | Logo + brand name (left), audience (right), 8.5pt uppercase muted |
| Running footer | Magenta→orange stripe + "Confidential" (left), "Page N" (right) |
| Body H1 | 20pt bold |
| Body H2 | 14pt bold with magenta left bar |
| Body H3 | 11.5pt bold ink-soft |
| Body H4 | Magenta uppercase eyebrow style |
| Tables | Dark navy header row, zebra-striped rows |
| Blockquotes | Soft bg, magenta left border |
| Code blocks | Soft bg, hairline border |
| Links | Magenta with subtle underline |

## Raw-HTML components

The markdown body accepts raw HTML for branded components:

### Callout box

```html
<div class="callout">
  <strong>Heads up:</strong> Important takeaway here.
</div>
```

### Terms table (label/value, like the contractor agreement summary)

```html
<table class="terms-table">
  <tr><td class="label">Position</td><td class="value">AI-Enabled GTM Specialist</td></tr>
  <tr><td class="label">Start Date</td><td class="value">May 4, 2026</td></tr>
</table>
```

### Numbered legal-style section header

If you want the numbered section style from the contractor agreement (magenta number prefix), use:

```html
<h2 class="section"><span class="num">1.</span>Section Title</h2>
```

The `.section` and `.num` classes aren't in the default stylesheet — they live in the original contract HTML. To enable across the skill, add to `assets/style.css`:

```css
.body h2.section .num { color: var(--brand-primary); margin-right: 8px; font-weight: 800; }
```

## Frontmatter reference

| Field | Default | Purpose |
|---|---|---|
| `title` | first H1 in body | Cover-page big title |
| `subtitle` | (none) | Smaller line under title |
| `eyebrow` | "Ad Advisor AI" | Small uppercase magenta line above title |
| `brand_name` | "Ad Advisor AI" | Header brand name |
| `brand_tag` | "AI-Native Growth, on Autopilot" | Tagline under brand on cover |
| `document_kind` | "Document" | Header label, e.g. "Offer Letter" |
| `audience` | (none) | Top-right header label per body page |
| `meta` | (none) | List of `{label, value}` for cover key/value grid |
| `footer_note` | "Ad Advisor AI · Issued <today>" | Cover-page bottom line |
| `no_cover` | `false` | Skip the cover page entirely |
