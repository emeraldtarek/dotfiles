---
name: md-to-x
description: Convert a Markdown file to HTML rich text and put it on the macOS clipboard, ready for one-shot Cmd+V into X (Twitter) Articles, Notion, Google Docs, or any rich-text editor. Preserves H1/H2/H3, bold, italic, links, bullets, numbered lists, blockquotes. Use when user says "publish to X", "post X article", "md to X", "X long-form from markdown", "paste my markdown into X", or wants to skip the manual toolbar formatting in any rich-text web editor.
user-invocable: true
disable-model-invocation: false
argument-hint: "[path/to/article.md]"
---

# md-to-x

One-shot rich-text paste from Markdown. The trick: macOS's clipboard can carry HTML, and most rich-text web editors (X Articles, Notion, Google Docs, Linear, Slack composer) accept HTML paste and apply formatting in one Cmd+V.

This collapses what is normally a 15–20 minute "click each H2 in the toolbar, click each bold span, etc." routine into a single paste.

## Prerequisites

- macOS (uses `osascript` and `textutil` — both stock).
- Stock Python 3 (no pip installs needed).
- For X Articles specifically: user needs Premium / Premium Plus to access `x.com/compose/articles`.

## Quick start

Text mode (Markdown body → HTML rich text on clipboard):

```bash
python3 ~/.claude/skills/md-to-x/scripts/md_to_x_clipboard.py /path/to/article.md
```

Image mode (any image format → PNG on clipboard):

```bash
python3 ~/.claude/skills/md-to-x/scripts/md_to_x_clipboard.py /path/to/screenshot.png --image
```

Then tell the user to click the target editor and press Cmd+V.

## Workflow

1. **Confirm the input path** to the markdown file. If the user gave the file content inline rather than a path, write it to a temp file first (e.g. `/tmp/article.md`) before running the script.

2. **Decide whether to strip the H1.**
   - X Articles, Substack, and other platforms set the article title in a *separate* field. If the markdown has a `# Title` line and the user is targeting one of those, pass `--strip-h1` so the title doesn't double-print in the body.
   - Notion, Google Docs, Linear comments → leave H1 in.

3. **Run the script.**
   ```bash
   python3 ~/.claude/skills/md-to-x/scripts/md_to_x_clipboard.py /path/to/article.md [--strip-h1]
   ```

4. **Tell the user to paste.** Click the target editor's body, press Cmd+V. The body content lands fully formatted.

5. **Handle images via image mode.** After the text body is pasted, insert images one at a time:

   ```bash
   python3 ~/.claude/skills/md-to-x/scripts/md_to_x_clipboard.py /path/to/screenshot.png --image
   ```

   The script accepts any common format (PNG, JPG, JPEG, HEIC, TIFF, GIF, WebP). Non-PNG inputs get converted via `sips` automatically — output is always PNG on the clipboard.

   For each image:
   - Tell the user the paragraph it should follow (e.g., "click at the end of the line ending in `…with the assets you just uploaded.`, press Enter to start a new line").
   - Run image mode for that screenshot.
   - User clicks the new line and Cmd+V.
   - Repeat for the next image — re-running the script overwrites the clipboard.

   Fallback: if image-clipboard paste doesn't work in the target editor, fall back to the editor's native upload flow (Insert → Media in X Articles, drag-drop in Notion, etc.).

## Fallback: HTML paste lands as plain text

A few editors don't accept HTML clipboard. If the paste came in unformatted, re-run with `--rtf`:

```bash
python3 ~/.claude/skills/md-to-x/scripts/md_to_x_clipboard.py /path/to/article.md --rtf
```

This routes through `textutil` to produce RTF, which has wider editor support but slightly less faithful styling.

## Supported Markdown

| Syntax | Becomes |
|---|---|
| `# H1` | `<h1>` (or stripped with `--strip-h1`) |
| `## H2` | `<h2>` |
| `### H3` | `<h3>` |
| `**bold**` | `<strong>` |
| `*italic*` | `<em>` |
| `` `code` `` | `<code>` |
| `[text](url)` | `<a href="url">` |
| `- item` | `<ul><li>` |
| `1. item` | `<ol><li>` |
| `> quote` | `<blockquote>` |
| Blank line | Paragraph break |

Not handled (yet): tables, code fences (` ``` `), images (`![](...)`), nested lists, footnotes, horizontal rules. If the source has these, warn the user before running and offer to convert tables/diagrams to PNG separately.

## Editor-specific notes

### X Articles (`x.com/compose/articles`)
- Always use `--strip-h1`. The title goes in the header field separately.
- Dividers (`---` in markdown) don't survive. If the source has them, tell the user to add them in-editor via Insert → Divider after pasting.
- Code fences don't render as code blocks; they paste as plain paragraphs. Convert to blockquotes in the source if you want any visual separation.

### Notion / Google Docs
- Leave H1 in. Both render H1 in body fine.
- Tables in source markdown won't paste as tables (this script doesn't emit `<table>`). Tell the user beforehand if the source has tables.

## Critical rules

- **Never invoke the editor's publish/send button.** This skill ends at "clipboard is loaded." User reviews and publishes manually.
- **Confirm the file exists** before running. The script will throw on a missing path.
- **Don't paste into the WRONG focused window.** Before telling the user to Cmd+V, confirm the target editor is in focus. Pasting a 5KB HTML blob into a Slack message or terminal is annoying.
