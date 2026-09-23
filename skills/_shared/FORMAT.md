## Task

Write the handoff file from what you already hold in this conversation. Do not re-read files. Do not run tools to "check" state beyond the bookkeeping steps below. Do not ask questions. One Write call plus bookkeeping.

The reader is a fresh Claude session with zero memory of this one. It is not a human. Optimize for the reader's ability to continue correctly with the fewest tokens, not for readability.

## Format rules

- Language: English, whatever language the conversation used. Exception: every user constraint, prohibition and the latest user request go verbatim, in the user's words. Summaries measurably drop constraints; quoting them is the fix.
- State, not narrative. Never tell what happened in order. Tell where things are now.
- Terse lines. Drop articles and filler. Use `path:line` references instead of pasting code. No code blocks unless a snippet under 3 lines is itself the decision (an exact flag, an exact command).
- Plain `KEY:` sections with `-` bullets. No JSON, no YAML, no tables, no extra headings.
- Do not invent shorthand. Standard abbreviations only (cfg, env, fn, PR, repo, DB).
- Never include: tool outputs, file contents, exploration that led nowhere unless it becomes a REJECTED item, anything the reader can recover from disk (git diff, file listings), greetings, comments about this handoff itself.
- Facts you verified (ran it, saw it): plain statements. Anything not verified: append `(unverified)`. Anything you inferred: append `(assumed)`.
- Size: aim for 300-800 words. Hard cap 1200 words. If over, cut FILES and STATE detail first. Never cut GOAL, CONSTRAINTS, REJECTED, LAST_REQUEST or NEXT.

## Sections, in this order (omit a section only if truly empty)

```
HANDOFF <timestamp> session=<session id> cwd=<cwd> git=<branch> dirty=<n files|clean|n/a>
GOAL: user's real objective in one or two lines. Then CONSTRAINTS: every hard constraint or prohibition the user stated, verbatim, one per bullet. Never paraphrase these.
USER: language and register the user writes in (e.g. es-AR, voseo); preferences discovered this session (style, tools to avoid, how they want to be told things); anything they got annoyed by.
STATE: done and verified; done but unverified; half-done and exactly where it stops.
FILES: path - one-line role and what changed (created/edited/important read-only). Only files the next session must know about.
DECISIONS: choice - why, one line each. Include decisions the user made explicitly.
REJECTED: approaches tried or considered and dropped - why. Purpose: never retry them.
OPEN: unresolved questions, blockers, things waiting on the user, known bugs.
ENV: exact commands that matter (test, run, build, deploy); services and ports; where credentials live (never the secret itself); external systems touched.
LAST_REQUEST: the user's most recent request, verbatim.
NEXT: the single next action, then the following 2-4 steps. If the user passed a note in $ARGUMENTS, it overrides your guess for the first step; include it verbatim.
```
