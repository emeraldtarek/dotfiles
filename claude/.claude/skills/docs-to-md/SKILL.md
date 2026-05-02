---
name: docs-to-md
description: Mirror a documentation site into a local Markdown corpus that AI coding agents can grep. Given a root docs URL, harvest every sidebar/sitemap page, crawl with headless Playwright, convert each page to verbatim Markdown, then dispatch parallel sub-agents to write 200–500 word summaries. Output is a repo with full/, summarized/, all-urls.txt, all-urls.json, README.md, and a refreshable scripts/ pipeline. Use when user says "docs to md", "mirror these docs", "crawl this docs site", "I want offline markdown of [docs URL]", "build a docs repo for [product]", or supplies a docs root URL with intent to dump it.
user-invocable: true
disable-model-invocation: false
argument-hint: "<root docs URL> [output-dir]"
---

# docs-to-md

Build an offline Markdown mirror of a documentation site so AI coding agents can `grep` real docs instead of hallucinating endpoints, parameters, or SDK methods. Outputs a self-contained repo with `full/`, `summarized/`, manifest files, and a refreshable Playwright pipeline — same shape as `meta-ads-api-docs-md` and `elevenlabs-docs-md`.

The user gives a root URL like `https://elevenlabs.io/docs/eleven-agents/overview`; the skill discovers all related pages, crawls them in parallel, and ships a finished repo.

## Inputs

1. **Root docs URL** — required. Used to (a) identify the site and (b) compute the URL prefix used for filtering and filename slugging.
2. **Output directory** — optional. If the cwd is empty (greenfield) use it; otherwise create a sibling dir like `<product>-docs-md`. Confirm with the user before creating.

## Output shape

```
<output-dir>/
├── full/                ~N verbatim Markdown pages (frontmatter + body)
├── summarized/          ~N 200–500 word summaries 1:1 with full/
├── all-urls.txt         flat URL list
├── all-urls.json        URL list with H1-derived titles
├── README.md            usage instructions for AI agents
├── .gitignore
└── scripts/             refresh pipeline copied from this skill
    ├── build_url_list.py
    ├── build_url_titles.py
    ├── crawl.js
    ├── extract.js
    ├── package.json
    ├── package-lock.json   (after npm install)
    ├── split_summary_batches.py
    └── summarizer_prompt.md
```

Filename convention: take the URL portion after the *site root* (`https://example.com/docs/`), replace `/` with `__`, append `.md`. So `/docs/eleven-agents/customization/voice` → `eleven-agents__customization__voice.md`. The same name is used in `full/` and `summarized/`.

Frontmatter on every file:
```yaml
---
url: https://example.com/docs/eleven-agents/customization/voice
title: "Voice & language"
---
```

## Playbook

Drive the pipeline in this order. Don't skip steps; each one's output feeds the next.

### 1. Bootstrap the output directory

If cwd is empty, use it. Otherwise pick `<product>-docs-md` (e.g. `stripe-docs-md`) and confirm with the user before mkdir'ing. Then:

```bash
cp -R ~/.claude/skills/docs-to-md/scripts <output-dir>/scripts
mkdir -p <output-dir>/full <output-dir>/summarized
cd <output-dir>/scripts && npm install --silent && npx playwright install chromium
```

Write a minimal `.gitignore` (`node_modules/`, `batches/`, `.playwright-mcp/`, `.DS_Store`).

### 2. Discover URLs

**Always try `<site-root>/sitemap.xml` first** — it's the canonical list and skips the painful expand-every-sidebar dance. ElevenLabs docs ship `https://elevenlabs.io/docs/sitemap.xml`; Mintlify, Fern, Docusaurus, Nextra, GitBook, ReadMe — almost all of them publish one.

```bash
python3 scripts/build_url_list.py --root <root-url> [--prefix <url-prefix>]
```

Pass `--prefix` when you want to narrow to a sub-tree. Example: root `https://elevenlabs.io/docs/eleven-agents/overview` → use `--prefix https://elevenlabs.io/docs/eleven-agents/` plus any related sub-trees the user cares about (e.g. matching API reference sections).

If sitemap is missing or sparse, fall back to **sidebar crawl**: open the root URL with Playwright MCP, iteratively click every collapsed group button until the link count stops growing, then harvest `<a href>`s. Be careful — clicking the same button twice toggles. Track clicked buttons by stable identifier.

### 3. Pick an extractor strategy

Open one representative page with Playwright MCP and inspect the DOM to detect the platform. Common signatures:

| Platform | Detection signal | Strategy |
|---|---|---|
| **Fern** | `aside.fern-layout-reference-aside`, `.fern-prose`, `.fern-api-property-*` spans | Use bundled `extract.js` — already Fern-aware (renders parameter trees, code blocks, method+URL line) |
| **Mintlify** | `[class*="mint-"]`, `<main id="content-area">` | Use `extract.js` generic walker; tweak the article selector if needed |
| **Docusaurus** | `<article class="theme-doc-markdown">`, `.markdown` | Generic walker on `article.theme-doc-markdown` |
| **Nextra** | `article.nextra-content`, `<main class="nextra-body">` | Generic walker on `main.nextra-body` |
| **GitBook** | `<main id="content"><div class="page-inner">` | Generic walker, target `.page-inner` |
| **Meta DMC** | `json_cms_content` Relay payload embedded in HTML | Use the JSON-tree extractor from `meta-ads-api-docs-md/scripts/build_retry_js.py` (in the meta-ads repo) — it walks DMC component types directly |
| **Custom / SSR** | none of the above | Inspect the article container, override `extract.js` selectors, fall through to generic walker |

If the detected platform isn't Fern, edit `extract.js` to add the new article selector to `findArticle()` near the top of the file. Don't rewrite the walker.

### 4. Crawl every page

```bash
CONCURRENCY=8 node scripts/crawl.js
```

The crawler is **resumable** — if `full/<slug>.md` exists it's skipped. So you can ctrl-C and restart safely. Use `--force` to re-crawl.

It blocks images/media/fonts to keep things fast. Auto-expands "Show ..." disclosure buttons before extraction so nested API schema fields render. Writes `<slug>.failed` markers for any URL that errored and prints a summary at the end.

Run this in the **background** (Bash `run_in_background: true`) and continue with steps 5–6 in parallel — the crawl finishes in 2–10 min depending on page count.

If failures > 0, inspect a couple of the `.failed` files, adjust the extractor or selectors, then re-run the crawler (it'll only retry the missing pages).

### 5. Refresh titles in `all-urls.json`

After crawl is done:

```bash
python3 scripts/build_url_titles.py
```

This walks `full/*.md`, harvests each page's `title:` field from frontmatter, and rewrites `all-urls.json` with `text` populated.

### 6. Generate summaries via parallel sub-agents

```bash
python3 scripts/split_summary_batches.py 10   # writes batches/sumbatch_NN.txt
```

Then **dispatch 10 parallel `general-purpose` sub-agents** (one per batch) using the Agent tool with `run_in_background: true`. Each agent's prompt is the contents of `scripts/summarizer_prompt.md` with the batch number substituted in. Each agent uses Read + Write only.

Agents write to `summarized/` independently. Total wall-clock: 10–15 min. You'll get one completion notification per agent.

When all 10 are done, run `diff <(ls full | sort) <(ls summarized | sort)` to confirm 1:1 coverage.

### 7. Write README.md

Use the README template at the bottom of this skill (or copy from `meta-ads-api-docs-md` / `elevenlabs-docs-md`). Substitute the product name, root URL, page counts, and section list.

### 8. Cleanup

Remove `batches/` (gitignored anyway). Don't commit `node_modules/` or `.playwright-mcp/`.

## Hard-won lessons

These come from running this pipeline twice (Meta Ads docs → 980 pages, ElevenLabs Agents → 407 pages). Don't re-discover them.

- **Sitemap > sidebar.** Almost every docs site has one. The sidebar dance with collapsed groups is fragile — buttons toggle, fingerprints drift, click ordering matters. Skip it whenever possible.
- **Use the in-page DOM, not raw `fetch()`**, for any docs site that uses interactive widgets (Fern's API ref tabs, "Show ..." disclosures, code-language tabs). Static HTML often lacks the rendered parameter list. Playwright `page.goto` + `waitForSelector` + `page.evaluate` gets you the hydrated tree.
- **Auto-expand disclosure buttons** before extracting. Look for buttons whose text starts with "Show ", or matches `/properties$/i` / `/attributes$/i`. Loop a few passes — clicking some buttons reveals new buttons.
- **Strip Fern's syntax-highlighted line-number tables.** Code lives in `<table class="code-block-line-group">` with a gutter `<td>` (line number / `$`) and a content `<td>`. Take only the content cells, join with `\n`. Don't just `textContent` the whole `<pre>` — you'll get `1curl ...2{...3}` glued lines.
- **Block heavy resources.** `page.route('**/*', route => ['image','media','font'].includes(route.request().resourceType()) ? route.abort() : route.continue())`. Cuts crawl time roughly in half.
- **Make the crawler resumable.** Skip URLs whose target file exists. Lets you iterate on the extractor and re-run without re-crawling everything.
- **Concurrency 8 is the sweet spot** for a single Chromium context on a Mac. More than that and pages start getting throttled. Less and the crawl drags.
- **Summarization is sub-agent fodder.** It's pure Read + Write per file, embarrassingly parallel. 10 `general-purpose` agents in parallel finish 400 files in ~10 min wall-clock. Don't try to summarize from the orchestrator agent — context bloats fast.
- **Don't try to extract every code-language tab.** Fern hides cURL/Python/JS/Go behind tabs that only render one at a time. Capturing the active tab + the example response is enough for an LLM to understand the API. Trying to click each tab to capture all languages is brittle and the marginal value is low.
- **Avoid duplicate URL-tree captures.** Some docs publish the same content under two URL paths (e.g. ElevenLabs has both `/docs/api-reference/agents/list` AND `/docs/eleven-agents/api-reference/agents/list`). If both are in the sitemap, just crawl both — they're each a real page from the site's perspective and dedup'ing risks losing edge cases.
- **For Meta-style CMS sites**, the embedded `json_cms_content` Relay payload is a cleaner extraction surface than the rendered DOM. See `meta-ads-api-docs-md/scripts/build_retry_js.py` for the component-type walker.

## When NOT to use this skill

- The user wants a few pages of docs, not the whole site → just use jina `read_url` or WebFetch.
- The site requires login / session cookies → Playwright can do this but the skill doesn't handle auth out of the box; ask the user for the cookie or login flow first.
- The user wants the docs as a single PDF → use a different tool.
- The site has < 30 pages → the orchestration overhead isn't worth it; loop jina `read_url` calls instead.

## README template (substitute placeholders)

```markdown
# <Product> Documentation in Markdown

**Offline, AI-ready mirror of the entire [<Product> docs](<root-url>) — N pages of …, in plain Markdown.**

Built so AI coding agents — Claude Code, Cursor, Aider, Codex, Cline, Continue, and friends — can ground their answers in the real docs instead of hallucinating <product-specific footguns> when you ask them to write <Product> code.

## Why this exists

<2–3 sentences on why the product's training-data-derived recall is unreliable>

This repo flattens the whole `<root-url>` tree into one searchable Markdown corpus so you can:

- Drop it next to your project and tell your agent: *"use these docs as ground truth for anything <Product>."*
- Reference it from `CLAUDE.md` / `.cursorrules` / `AGENTS.md`.
- `grep` / `rg` for an endpoint, parameter name, or SDK method locally — no flaky JS-rendered docs site, no rate limits.

## What's inside

```
full/         N verbatim Markdown pages
summarized/   N 200–500 word summaries, 1:1 with full/
all-urls.txt  flat URL list
all-urls.json URL list with display titles
scripts/      Playwright-based refresh pipeline
```

Filename rule: take the URL portion after `<site-root>/`, replace `/` with `__`, append `.md`.

### Coverage

Captured YYYY-MM-DD.

| Section | Pages |
| --- | --- |
| <list main sections + counts> | … |
| **Total** | **N** |

## Using it with Claude Code / Cursor / Aider / etc.

```bash
git clone https://github.com/<you>/<repo>.git
```

In `CLAUDE.md` / `.cursorrules` / `AGENTS.md`:

```markdown
## <Product> reference
Authoritative offline docs live in `<repo-name>/`.
- Browse `summarized/` first to find the right page.
- Read the matching `full/` file for verbatim docs.
- For ANY question about <Product>: prefer these docs over training-data recall.
```

## Refreshing the mirror

```bash
cd scripts
npm install && npx playwright install chromium
python3 build_url_list.py --root <root-url>
CONCURRENCY=8 node crawl.js
python3 build_url_titles.py
```

## Attribution

Documentation content © <Product> Inc. — sourced from `<root-url>`. Unofficial Markdown mirror, provided as-is. Not affiliated with <Product>.
```
