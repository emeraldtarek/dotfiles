---
name: write-report
description: Generate a polished, consulting-quality research report as both Markdown and PDF. Produces a professional cover page, navy-blue typography, styled tables, blockquotes, source citations, and page-numbered output. Use when the user wants to create a report, research document, briefing, or any deliverable that should look like it came from McKinsey or Deloitte.
---

# Write Report Skill

Generate a professional, consulting-quality research report delivered as both a Markdown file and a styled PDF.

## When to Use

- User says "write a report", "create a report", "research report", "briefing document"
- User wants a polished PDF deliverable for sharing with stakeholders
- User wants research compiled into a professional document

## Prerequisites

- `npx md-to-pdf` must be available (it is via npx, no install needed)
- The bundled CSS asset `REPORT_STYLE.css` in this skill directory provides the styling

## Workflow

### Step 1: Determine Output Location and Topic

Ask the user (or infer from context):
1. **Topic** — What the report is about
2. **Output directory** — Where to save the files (default: current working directory)
3. **Filename** — Suggested based on topic, e.g. `ai-native-generalist-role-research`

### Step 2: Research (if needed)

If the user hasn't already provided the content, use WebSearch and/or agents to research the topic thoroughly. Gather:
- Key findings and data points
- Expert quotes and frameworks
- Sources with URLs
- Market data, statistics, comparisons

### Step 3: Write the Markdown File

Create the markdown file using the structure and frontmatter template below. The CSS file must be placed alongside the markdown file for `md-to-pdf` to resolve it.

**Before writing the markdown file:**
1. Copy the CSS asset from this skill's directory to the output directory:
   ```bash
   cp /path/to/skills/write-report/REPORT_STYLE.css <output-directory>/report-style.css
   ```
2. Write the markdown file referencing `report-style.css` in its frontmatter

### Step 4: Generate PDF

```bash
npx --yes md-to-pdf <filename>.md
```

This produces `<filename>.pdf` alongside the markdown file.

### Step 5: Confirm with User

Tell the user both files are ready and where they are. If they want layout adjustments, edit the markdown and regenerate.

---

## Markdown Template

Every report MUST use this frontmatter and structure. Adapt the content sections to the topic.

````markdown
---
pdf_options:
  format: Letter
  margin: 20mm 22mm 24mm 22mm
  printBackground: true
  displayHeaderFooter: true
  headerTemplate: "<span></span>"
  footerTemplate: "<div style='width:100%;text-align:center;font-size:9px;color:#888;font-family:Helvetica Neue,Helvetica,Arial,sans-serif;padding:0 22mm;'><span class='pageNumber'></span></div>"
stylesheet:
  - report-style.css
---

<div class="cover">
  <div class="accent-bar"></div>
  <h1>Report Title Here</h1>
  <p class="subtitle">A one-to-two sentence description of what this report covers and why it matters.</p>
</div>

## Executive Summary

A concise overview of the key findings. This should flow directly after the cover page with no empty page in between.

Key findings:

- **Finding 1** — Brief description
- **Finding 2** — Brief description
- **Finding 3** — Brief description

---

## Section Title

Content for this section. Use markdown normally — paragraphs, lists, bold, etc.

> Blockquotes for notable quotes or callouts.

### Subsection

More detailed content under the section.

| Column A | Column B |
|---|---|
| Data | Data |

<div class="sources">

- [Source Name — Description](https://example.com)

</div>

---

## Next Section

Use `---` (horizontal rules) between major sections to trigger page breaks. The CSS makes `hr` elements invisible and uses them as page-break triggers.

---

## References

Numbered list of all sources cited throughout the report.
````

## Structure Rules

1. **Cover page** — Always use the `<div class="cover">` block with accent bar, h1 title, and subtitle. NO metadata like "Prepared for" or "Date" unless the user explicitly asks for it.

2. **Executive Summary** — Always the first section after the cover. Flows on the same page or the next page naturally (no forced break between cover and executive summary).

3. **Section breaks** — Use `---` (horizontal rules) between major `## Sections` to force page breaks. Do NOT put a `---` between the cover and Executive Summary.

4. **Headings stay with content** — CSS uses `break-after: avoid` on h2/h3 so headings never appear orphaned at the bottom of a page.

5. **Tables don't split** — CSS uses `break-inside: avoid` on tables.

6. **Blockquotes don't split** — Same `break-inside: avoid`.

7. **Sources per section** — Wrap source lists in `<div class="sources">...</div>` for smaller, muted styling with a top border separator.

8. **No empty pages** — If you see empty pages in the output, check for double page breaks (e.g., a `---` followed by a heading that also has `break-before`).

## Styling Details

The CSS provides:
- **Navy blue** (`#1a3a5c`) accent color for headings, cover title, table headers, blockquote borders
- **Helvetica Neue** font family
- **11pt** body text, **16pt** section headings, **32pt** cover title
- **Tables** with navy header row, white text, alternating row stripes
- **Blockquotes** with light blue background and navy left border
- **Page numbers** centered in footer (hidden on cover page)
- **Sources** in 9pt muted text with a thin separator line

## Common Adjustments

- **Add Table of Contents**: Wrap in `<div class="toc">` with a numbered list, placed between cover and Executive Summary
- **Add cover metadata**: Add a `<div class="meta">` block inside the cover div with lines like `<strong>Date:</strong> ...`
- **Wider tables**: For 4+ column tables, consider using smaller font or abbreviations to prevent overflow
- **Callout boxes**: Use `<div class="callout"><p>Important stat or highlight here.</p></div>`
