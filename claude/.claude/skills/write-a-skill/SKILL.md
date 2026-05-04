---
name: write-a-skill
description: Create new agent skills with proper structure, progressive disclosure, and bundled resources. Use when user wants to create, write, or build a new skill.
source: https://github.com/mattpocock/skills/tree/main/write-a-skill
---

# Writing Skills

## Process

1. **Gather requirements** - ask user about:
- What task/domain does the skill cover?
- What specific use cases should it handle?
- Does it need executable scripts or just instructions?
- Any reference materials to include?

2. **Draft the skill** - create:
- SKILL.md with concise instructions
- Additional reference files if content exceeds 500 lines
- Utility scripts if deterministic operations needed

3. **Review with user** - present draft and ask:
- Does this cover your use cases?
- Anything missing or unclear?
- Should any section be more/less detailed?

## Skill Structure

Use Anthropic's recommended three-tier layout from [skill-creator](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md):

```
skill-name/
├── SKILL.md           # Main instructions (required)
├── scripts/           # Executable utility scripts
│   └── helper.py
├── assets/            # Templates, icons, fonts, stylesheets — files used in output
│   └── template.css
└── references/        # Docs loaded into context as needed
    ├── example.md
    └── advanced.md
```

Domain variants go under `references/` (e.g. `references/aws.md`, `references/gcp.md`) with selection logic kept in SKILL.md.

## SKILL.md Template

```md
---
name: skill-name
description: Brief description of capability. Use when [specific triggers].
---

# Skill Name

## Quick start

[Minimal working example]

## Workflows

[Step-by-step processes with checklists for complex tasks]

## Advanced features

[Link to separate files: See [REFERENCE.md](REFERENCE.md)]
```

## Description Requirements

The description is **the only thing your agent sees** when deciding which skill to load. It's surfaced in the system prompt alongside all other installed skills. Your agent reads these descriptions and picks the relevant skill based on the user's request.

**Goal**: Give your agent just enough info to know:

1. What capability this skill provides
2. When/why to trigger it (specific keywords, contexts, file types)

**Format**:

- Max 1024 chars
- Write in third person
- First sentence: what it does
- Second sentence: "Use when [specific triggers]"

**Good example**:

```
Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when user mentions PDFs, forms, or document extraction.
```

**Bad example**:

```
Helps with documents.
```

The bad example gives your agent no way to distinguish this from other document skills.

## When to Add Scripts

Add utility scripts when:

- Operation is deterministic (validation, formatting)
- Same code would be generated repeatedly
- Errors need explicit handling

Scripts save tokens and improve reliability vs generated code.

## Python Dependencies — always use `uv` + PEP 723

For Python scripts in `scripts/`, declare dependencies inline using [PEP 723](https://peps.python.org/pep-0723/) and run with `uv run`. **Never** require `pip install` against the system Python or a project venv — every skill script must be self-contained and run in an ephemeral, cached venv that uv manages automatically.

Script header template:

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "package-a>=X.Y",
#   "package-b",
# ]
# ///
"""Module docstring..."""
```

Invoke from SKILL.md as:

```bash
uv run ~/.claude/skills/<skill>/scripts/<name>.py <args>
```

Why this is the rule:

- Self-contained: nothing to install before the skill works on a new machine (only `uv` itself, which is universal).
- No system Python pollution and no PEP 668 "externally managed environment" friction on macOS/Homebrew Python.
- Dependencies are versioned alongside the script — the source of truth lives in the skill repo, not a global site-packages.
- uv caches resolved environments per dep-set, so subsequent runs are instant.

Do **not** use: `pip install --user`, `--break-system-packages`, `requirements.txt` outside a `pyproject.toml`, or assumptions that any Python package is preinstalled.

For non-Python languages, follow the equivalent local-only convention (Node: `npx`; Bash: bundle the binary or check for it; etc.) — never mutate global state.

## When to Split Files

Split into separate files when:

- SKILL.md exceeds 100 lines
- Content has distinct domains (finance vs sales schemas)
- Advanced features are rarely needed

## Review Checklist

After drafting, verify:

- [ ] Description includes triggers ("Use when...") and is slightly "pushy" to combat undertriggering
- [ ] SKILL.md under 100 lines (Anthropic's official ceiling is 500 — stay well under)
- [ ] Layout uses `scripts/`, `assets/`, `references/` subdirs (not flat) when there's more than just SKILL.md
- [ ] Any Python script in `scripts/` declares deps via PEP 723 and is run with `uv run` — no `pip install`
- [ ] No time-sensitive info
- [ ] Consistent terminology
- [ ] Concrete examples included
- [ ] References one level deep
