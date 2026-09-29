# Handoff — a Claude Code plugin

`/handoff` writes a compressed, AI-only note of the current session's state to disk and restarts Claude Code in the same terminal. The fresh session starts with the note in context, a few hundred tokens instead of the whole history, and runs your next prompt if you gave one.

## Usage

```
/handoff                                                  # note, restart, fresh session waits for you
/handoff -p "seguí con el test que falla"                 # ...and the fresh session runs this prompt
/handoff -i "detallá bien el tema de los permisos" -p "arrancá con la migración"
/handoff --instructions "…" --prompt "…"                  # long forms
```

- `-i` / `--instructions`: how to shape the note (what to emphasize, include or leave out).
- `-p` / `--prompt`: your next prompt. It arrives in the fresh session as your first message, typed by you.
- Both are optional. Text with no flags counts as the prompt.

When you press Enter, the current session writes the note and ends. The `claude` shell function starts a new session right away, in the same terminal, directory and permission mode. The new session gets the note as context before its first turn.

## Setup: the `claude` shell function

Nothing inside a live session can run `/clear` (DESIGN.md §6), so the restart is a new process. A shell function named `claude` wraps the real binary and starts the next session when the old one ends after `/handoff`. Add one line to `~/.bashrc` or `~/.zshrc`:

```bash
source "/path/to/claude_code_handoff_plugin/scripts/claude-wrapper.sh"
```

For a marketplace install, the path is `~/.claude/plugins/marketplaces/handoff/scripts/claude-wrapper.sh`. Without a restart request the function behaves exactly like `claude`, with the same arguments and exit code.

Without the function, `/handoff` still works: it tells you to type `/clear` and then any short message (`dale`). After `/clear`, the note and the parked prompt enter the fresh session's context, and your message starts it.

The restarted session keeps the permission mode (bypass, auto, plan…) and uses your default model. Other launch flags (`--model`, `--add-dir`, `--mcp-config`) are not repeated.

### Status line

`scripts/statusline.sh` shows the model, your plan limits and the live context size, and turns red past 150k tokens, the size `/usage` counts as a large session:

```
Opus 5.5 (1M context) · 5 hour 25% (Today 14:00) · Weekly 5% (25/9/26 01:00) · Fable 3% (25/9/26 01:00) · 87k/1.0M 9%
Opus 5.5 (1M context) · 5 hour 25% (Today 14:00) · Weekly 5% (25/9/26 01:00) · Fable 3% (25/9/26 01:00) · 158k/1.0M 16% /handoff -i "handoff instructions" -p "next prompt"
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
~/.claude/projects/<encoded-cwd>/handoff/request-<session id>  # restart signal, written by /handoff, consumed by the Stop hook
~/.claude/projects/<encoded-cwd>/handoff/pending-prompt.txt   # no-wrapper fallback, consumed once after /clear
```

`<encoded-cwd>` is the directory that holds the session's transcript: the directory Claude Code started in, with every non-alphanumeric character turned into `-`. `scripts/handoff-paths.sh` finds it from the session id, so a session that `cd`'d into a subdirectory still writes to the right place. The header of each handoff carries the session id, so `claude --resume <id>` recovers the full transcript if the note is not enough.

## How the restart works

1. `/handoff` writes `latest.md`, then `request-<session id>` with the prompt (empty without `-p`).
2. When the turn ends, the `Stop` hook (`scripts/stop.sh`) finds the request. Under the shell function, it passes the prompt, the permission mode and the note's path to the function, and ends the Claude Code process half a second later.
3. The function starts `claude [--permission-mode <mode>] ["<prompt>"]`.
4. The `SessionStart` hook sees the one-shot load file the function passed and prints the note as context.

Without the function, step 2 parks the request as `pending-prompt.txt` instead, and the `SessionStart` hook on `/clear` prints the note and the prompt.

At any other session start, if `latest.md` exists, the hook prints one pointer line: path, age, approximate size, read only when asked. It never injects the body then. Cost: about 40 tokens when a handoff exists, zero otherwise.

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
skills/handoff/SKILL.md          /handoff: note + restart request (manual only)
skills/_shared/FORMAT.md         handoff format rules, included by the skill via !`cat`
hooks/hooks.json                 SessionStart and Stop hooks
scripts/handoff-paths.sh         cwd -> handoff dir
scripts/session-start.sh         pointer line, or the note after /handoff
scripts/stop.sh                  after /handoff: hand the restart to the shell function, or park for /clear
scripts/claude-wrapper.sh        `claude` shell function that starts the next session
scripts/statusline.sh            model + context size in the status line, /handoff hint past 150k
```
