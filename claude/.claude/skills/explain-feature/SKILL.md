---
name: explain-feature
description: Explain how a feature works end to end as a published artifact of clickable flow diagrams traced from the code. Use when the user wants to understand a feature, pipeline or request path in a codebase and asks for an artifact, flow diagrams or a visual walkthrough.
user-invocable: true
disable-model-invocation: false
argument-hint: "[feature to explain]"
---

Produce one page that lets the user follow a feature **hop by hop**, from its trigger to its result, and see **who** does each hop.

- A **hop** is one step where data changes hands or changes form.
- An **actor** is who performs a hop: a person, our own code, a database, a queue, an outside service, a model. On the page, colour means actor and nothing else.

Every claim on the page comes from the **trace** in step 2. The diagrams are the trace drawn; they add nothing to it.

## 1. Fix the path

Write the feature as one sentence: "from *trigger* to *result*". Name each **variant** (two modes, versions or providers that share a path and then fork). Ask the user only when their words fit two different features; otherwise go.

Done when the sentence and the variants are written down.

## 2. Trace

Read the code along the path: the entry point (route, handler, job, CLI command, UI event), every function that moves or changes the data, and what is finally stored, returned or shown. Read the function bodies. Read the repo's ADRs, glossary and docs for the reasons behind them and for the words the project uses.

For every hop, record:

1. the actor
2. what it receives
3. what it produces
4. each condition under which the path leaves it another way (branch, retry, failure)
5. its limits: caps, thresholds, timeouts, concurrency, by constant name and value
6. the file and function

When the path crosses many modules, hand the reading out to subagents by module, then open for yourself every hop a diagram will hinge on.

A number reaches the page with its source: a named constant in the code, a measurement you can point to (a log, a test run), or the user's own report. Say which, next to the number. Describe real data by its shape and counts ("a 40,000-row export"), never by its contents.

Done when you can walk trigger to result with no gap, every hop has its six facts, and every fork has its condition.

## 3. Plan the diagrams

- **The first diagram is the whole path**, trigger at the top, result at the bottom. Variants appear as a fork, each edge labelled with its condition.
- **One more diagram for each fork or stage whose inside matters.** A single node in the first diagram stands for it.
- **5 to 12 nodes per diagram.** Merge neighbouring hops by one actor that the reader need not tell apart. Split wherever the actor, the data or the path changes.
- **3 to 6 actors**: the ones whose difference the reader should see.
- **Loops, retries and skips are edges** with their condition as the label.
- **Flag the hop the user's question is about** (the slow one, the costly one, the one that fails).

Below the diagrams, add only what this feature has:

| The feature has | Add |
|---|---|
| variants | a side-by-side table: who decides, who checks, what it grows with, cost, known faults |
| measured numbers | bars, each with where the number came from |
| outside parties | a table of which party receives which data |

## 4. Write the page

Copy [`assets/flow-page.html`](assets/flow-page.html) to the scratchpad and fill it in. The comment at the top of its script is the reference for the spec (actors, nodes, the four edge kinds). Its renderer stays as it is. Retune the colour and font tokens only to match a design system the project already has.

- **Node title**: what happens, in the user's words ("Look up the account").
- **Node sub line**: the one detail that sets this hop apart.
- **Inspector**: one to three short paragraphs on what happens and why, then facts in this order: Sent, Returns, Limit, Code.
- **Caption**: the one claim the figure makes.
- **Lede**: the path in two sentences and what differs between the variants.

Done when the file has no `EXAMPLE` left (`grep -c EXAMPLE` prints 0) and every node that is not a person or a note has a Code fact.

## 5. Check and publish

Look at the rendered page once. The page checks its own spec: every problem appears in red above its diagram and as a console error starting `flow-check`. Fix each one, and click two or three nodes to see the inspector fill.

Publish it with the Artifact tool, following that tool's own instructions; the template already meets its page contract. With no Artifact tool, put `<!doctype html>` and a `<meta charset="utf-8">` in front of the file, save it where the user can open it, and give the full path.

Reply with the link, one line per diagram saying what it shows, and what you did not verify: numbers taken from the user, hops you did not open, views you did not look at.
