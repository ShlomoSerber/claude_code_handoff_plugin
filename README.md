# Handoff — a Claude Code plugin

`/handoff-clear <next prompt>` writes a compressed, AI-only note of the current session's state to disk and parks your next prompt. You type `/clear` and any short message. The fresh session acts on the parked prompt and starts with a few hundred tokens instead of the whole history.

## Flow

```
… you work in a session …
/handoff-clear seguí con el test que falla   # writes latest.md, parks the prompt
/clear                                       # you type this; nothing can do it for you
dale                                         # any message starts the parked prompt
```

After `/clear`, the SessionStart hook adds this to the fresh session's context, once:

```
Look at the handoff in <path>/latest.md. The following is the users next prompt: <your text>
```

Your next message, even just `dale`, starts the turn, and Claude treats the parked prompt as your own request. An earlier version sent the prompt through Claude Code's messaging socket so it ran with no extra message. Claude Code labels every socket message as coming from another Claude session, so the prompt no longer counted as yours (DESIGN.md §6). Claude Code has no way for a skill or hook to run `/clear` (DESIGN.md §6), so that one keystroke stays yours. Parked prompts expire after 2 hours and are never consumed on `--resume`.

Without an argument, `/handoff-clear` writes the handoff only. After `/clear`, say "lee el handoff, seguimos con X".

### Status line

`scripts/statusline.sh` shows the model, your plan limits and the live context size, and turns red past 100k tokens:

```
Opus 5.5 (1M context) · 5 hour 25% (Today 14:00) · Weekly 5% (25/9/26 01:00) · Fable 3% (25/9/26 01:00) · 87k/1.0M 9%
Opus 5.5 (1M context) · 5 hour 25% (Today 14:00) · Weekly 5% (25/9/26 01:00) · Fable 3% (25/9/26 01:00) · 148k/1.0M 15% /handoff-clear <Next prompt>
```

- `5 hour` and `Weekly` come from the status JSON Claude Code passes in. That JSON has no limits until the session's first reply, so the status line falls back to the cached values described below.
- Per-model weekly limits (`Fable` above) are not in that JSON. A detached background process fetches `https://api.anthropic.com/api/oauth/usage` with your Claude Code OAuth token at most every 5 minutes and caches the result in `~/.cache/claude-handoff/usage.json`. The status line only reads the cache, so it never waits on the network. `HANDOFF_STATUSLINE_USAGE=0` turns the fetch off.
- Each limit shows when it resets, in local time: `Today HH:MM`, `Tomorrow HH:MM`, else `d/m/yy HH:MM`.
- The context count is the last reply's usage, read from the session transcript, so it drops to 0 right after `/clear`.

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

`hooks/hooks.json` runs `scripts/session-start.sh` on `startup`, `resume` and `clear`. If a fresh `pending-prompt.txt` exists, it prints the resume line above as context and deletes the file. Otherwise, if `latest.md` exists, it prints one pointer line: path, age, approximate size, read only when asked. It never injects the body. Cost: about 40 tokens when a handoff exists, zero otherwise.

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
skills/handoff-clear/SKILL.md    /handoff-clear: handoff + parked next prompt (manual only)
skills/_shared/FORMAT.md         handoff format rules, included by the skill via !`cat`
hooks/hooks.json                 SessionStart hook
scripts/handoff-paths.sh         cwd -> handoff dir
scripts/session-start.sh         pointer line, or the parked prompt after /clear
scripts/statusline.sh            model + context size in the status line, /handoff-clear hint past 100k
```
