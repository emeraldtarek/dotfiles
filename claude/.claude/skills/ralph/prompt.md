# RALPH — Autonomous Task Loop

## CONTEXT

Issues JSON and previous RALPH commits have been provided at the start of context. Parse them to understand the current backlog and what work has already been done.

IMPORTANT: ONLY work on issues from the provided JSON. Do NOT run `gh issue list` or fetch issues yourself. The provided issues have already been filtered to the ones assigned to you. If the provided issues JSON is empty (`[]`), there is nothing to do — output <promise>COMPLETE</promise> immediately.

## TASK SELECTION

Pick ONE task. Prioritize in this order:

1. Critical bugfixes
2. Tracer bullets for new features

   Tracer bullets (from The Pragmatic Programmer): build a tiny, end-to-end slice
   of the feature first that goes through all layers of the system, then expand.
   This gives fast feedback and validates the architecture early.

3. Polish and quick wins
4. Refactors

If the provided issues JSON is empty (`[]`), output <promise>COMPLETE</promise>. Otherwise, pick a task and work on it. Do NOT output the completion promise after finishing a task — there may be more tasks in the next iteration.

## EXPLORATION

Explore the repo and fill your context window with relevant information to complete the task.

## EXECUTION

Complete the task. Run tests and type checks if the project has them.

## COMMIT

Make a git commit. The commit message must:

1. Start with `RALPH:` prefix
2. Include task completed + issue reference
3. Key decisions made
4. Files changed
5. Blockers or notes for next iteration

Keep it concise.

## THE ISSUE

If the task is complete, close the original GitHub issue.

If the task is not complete, leave a comment on the GitHub issue describing what was done.

## FINAL RULES

ONLY WORK ON A SINGLE TASK.
