# Handoff — a Claude Code plugin

`/handoff` writes a compressed, AI-only note of the current session's state to disk. You then `/clear` and start the next prompt with "read the handoff, continue with X". The new session starts with a few hundred tokens instead of the whole history.

## Flow

```
… you work in a session …
/handoff                      # writes latest.md, replies with 3 lines
/clear
lee el handoff, seguimos con X  # new session reads ~150-800 tokens and continues
```

`/handoff next: fix the failing test` — the optional note becomes the first NEXT step, verbatim.

## Where the file goes

Next to Claude Code's own session transcripts, per project:

```
~/.claude/projects/<encoded-cwd>/handoff/latest.md          # always the newest
~/.claude/projects/<encoded-cwd>/handoff/<YYYYmmdd-HHMMSS>.md  # history, last 10 kept
```

`<encoded-cwd>` is the same encoding Claude Code uses for transcripts (every non-alphanumeric character becomes `-`), computed by `scripts/handoff-paths.sh`. The header of each handoff carries the session id, so `claude --resume <id>` recovers the full transcript if the note is not enough.

## How the fresh session finds it

`hooks/hooks.json` runs `scripts/session-start.sh` on `startup`, `resume` and `clear`. If a `latest.md` exists for the current directory, the hook prints one line: path, age, approximate size, and an instruction to read it only when asked. It never injects the body. Cost: about 40 tokens when a handoff exists, zero otherwise.

## What the handoff contains

Ten fixed sections, terse English, `path:line` references, no code, no narrative, 300-800 words (hard cap 1200):

`HANDOFF` header · `GOAL` (objective + hard constraints, verbatim) · `USER` (language, register, preferences, irritants) · `STATE` (done/verified, done/unverified, half-done) · `FILES` · `DECISIONS` · `REJECTED` (so the next session never retries them) · `OPEN` · `ENV` (exact commands, ports, where credentials live) · `NEXT`.

Everything unverified is tagged `(unverified)`, everything inferred `(assumed)`.

## Design notes

See `DESIGN.md` for the research behind the choices: why the main model writes the handoff in-context instead of a cheaper model, why the format is terse markdown and not JSON, and when clearing pays off versus when it costs you.

## Install

```
/plugin marketplace add ShlomoSerber/claude_code_handoff_plugin
/plugin install handoff@handoff
```

Or from a local checkout, without the interactive session:

```
claude plugin marketplace add /path/to/claude_code_handoff_plugin
claude plugin install handoff@handoff
```

After editing the plugin, bump `version` in `.claude-plugin/plugin.json`, then `claude plugin marketplace update handoff && claude plugin update handoff@handoff`. Claude Code installs a copy under `~/.claude/plugins/cache/`, so edits to the repo do not apply until the version changes.

## Layout

```
.claude-plugin/plugin.json       manifest
.claude-plugin/marketplace.json  single-plugin marketplace
skills/handoff/SKILL.md          the /handoff skill (manual only, disable-model-invocation)
hooks/hooks.json                 SessionStart pointer hook
scripts/handoff-paths.sh         cwd -> handoff dir
scripts/session-start.sh         prints the pointer line
```
