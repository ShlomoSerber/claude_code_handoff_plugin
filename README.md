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

### `/handoff-clear <next prompt>`

Same handoff, plus the next prompt is parked on disk. You type `/clear`, then any message (`dale`). The SessionStart hook injects, once:

```
Look at the handoff in <path>/latest.md. The following is the users next prompt: <your text>
```

and the fresh session acts on it. Claude Code has no way for a skill or hook to run `/clear` or to submit a prompt for you (verified against the docs, see DESIGN.md §6), so those two keystrokes stay yours. Parked prompts expire after 2 hours and are never consumed on `--resume`.

### Status line

`scripts/statusline.sh` shows the live context size and turns red past 100k tokens:

```
context 87k/1.0M 9%
context 110k/1.0M 11%  ⚠ context > 100k  /handoff-clear <next prompt>  or  /handoff
```

Enable it in `~/.claude/settings.json` (the plugin cannot do this for you; `statusLine` is not a plugin component):

```json
"statusLine": { "type": "command", "command": "\"/path/to/claude_code_handoff_plugin/scripts/statusline.sh\"", "padding": 0 }
```

`HANDOFF_WARN_TOKENS` changes the threshold; `HANDOFF_STATUSLINE_COLOR=0` disables colors.

## Where the file goes

Next to Claude Code's own session transcripts, per project:

```
~/.claude/projects/<encoded-cwd>/handoff/latest.md          # always the newest
~/.claude/projects/<encoded-cwd>/handoff/<YYYYmmdd-HHMMSS>.md  # history, last 10 kept
~/.claude/projects/<encoded-cwd>/handoff/pending-prompt.txt   # parked by /handoff-clear, consumed once
```

`<encoded-cwd>` is the same encoding Claude Code uses for transcripts (every non-alphanumeric character becomes `-`), computed by `scripts/handoff-paths.sh`. The header of each handoff carries the session id, so `claude --resume <id>` recovers the full transcript if the note is not enough.

## How the fresh session finds it

`hooks/hooks.json` runs `scripts/session-start.sh` on `startup`, `resume` and `clear`. If a fresh `pending-prompt.txt` exists (from `/handoff-clear`), it prints the resume line above and deletes the file. Otherwise, if `latest.md` exists, it prints one pointer line: path, age, approximate size, read only when asked. It never injects the body. Cost: about 40 tokens when a handoff exists, zero otherwise.

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
skills/handoff/SKILL.md          /handoff (manual only, disable-model-invocation)
skills/handoff-clear/SKILL.md    /handoff-clear: handoff + parked next prompt
skills/_shared/FORMAT.md         handoff format rules, included by both skills via !`cat`
hooks/hooks.json                 SessionStart hook
scripts/handoff-paths.sh         cwd -> handoff dir
scripts/session-start.sh         pointer line, or the parked prompt after /clear
scripts/statusline.sh            context size in the status line, warning past 100k
```
