# claude_code_handoff_plugin — harness notes

Start here: `README.md` (what it does, layout), `DESIGN.md` (why each choice was made, with sources), then the component the task touches. Update `DESIGN.md` when a design decision changes and `README.md` when behaviour changes. If a handoff exists for this directory (the SessionStart hook prints its path), read it when the user asks.

## Facts a new session needs

| Thing | Where / value |
|---|---|
| Purpose | `/handoff` writes a compressed AI-only state note; user does `/clear`; next session reads it on request. Goal: keep sessions small. |
| Skill | `skills/handoff/SKILL.md`, invoked as `/handoff [note]`. `disable-model-invocation: true` (manual only). Runs in the main conversation on the session model: no `model:`, no `context: fork`. |
| Skill 2 | `skills/handoff-clear/SKILL.md`, `/handoff-clear <next prompt>`: same handoff + parks the prompt in `<handoff dir>/pending-prompt.txt`. Both skills include `skills/_shared/FORMAT.md` via `` !`cat "${CLAUDE_PLUGIN_ROOT}/skills/_shared/FORMAT.md"` ``. Edit the format there, once. |
| Status line | `scripts/statusline.sh`, referenced by absolute repo path from `~/.claude/settings.json` `statusLine` (not a plugin component, no cache copy, no version bump needed). Prints `context <used>/<window> <pct>%`, red + `/handoff-clear` hint past 100k (`HANDOFF_WARN_TOKENS`). |
| No auto-/clear | Nothing in Claude Code lets a skill/hook run `/clear` or submit a prompt (docs + binary checked, DESIGN.md §6). Do not try again. The hook injects the parked prompt on `startup|clear` (< 2 h old), never on `resume`. |
| Hook | `hooks/hooks.json` → `scripts/session-start.sh` on `startup|resume|clear`. Prints ONE pointer line (path, age, ~tokens). Never prints the handoff body. |
| Storage | `~/.claude/projects/<encoded-cwd>/handoff/latest.md` + `<YYYYmmdd-HHMMSS>.md` (keep 10) + `pending-prompt.txt` (transient). Encoding: every non-alphanumeric char → `-`, computed by `scripts/handoff-paths.sh`. Verified against real dirs. |
| Install | Local directory marketplace `handoff` → plugin `handoff@handoff`, user scope. Claude Code copies the plugin to `~/.claude/plugins/cache/handoff/handoff/<version>/`. Repo edits do NOT apply until `version` in `.claude-plugin/plugin.json` is bumped, then: `claude plugin marketplace update handoff && claude plugin update handoff@handoff`, then restart Claude Code. |
| Remote | `git@github.com:ShlomoSerber/claude_code_handoff_plugin.git`, branch `main`. Public install: `/plugin marketplace add ShlomoSerber/claude_code_handoff_plugin` then `/plugin install handoff@handoff`. |
| Sibling plugins | `../claude_code_clear_language_plugin`, `../claude_code_archive_plugin`, `../vm-tunnels/plugin` follow the same layout (`.claude-plugin/plugin.json` + `marketplace.json`, `hooks/hooks.json`, `scripts/`). Match them. |
| Testing | Non-interactive: `claude -p --model haiku --permission-mode bypassPermissions "<prompt>" < /dev/null` in a scratch dir, then `claude -p -c ... "/handoff note"` or `"/handoff-clear <prompt>"`, then a fresh `claude -p ... "dale"` to see the parked prompt fire (`startup` counts). A leading `/handoff` in `-p` works; mid-prompt it does not. Clean up the scratch dir's `~/.claude/projects/...` afterwards. |

## Invariants

1. **The handoff body never enters context unprompted.** Pointer only, on request only. A stale handoff must not be able to hijack an unrelated session. Do not move storage into `…/memory/MEMORY.md` (auto-loaded).
2. **Same model, in-context.** A `model:` override without fork invalidates the cache and re-reads the whole history uncached; a fork has no history. Both cost more and lose fidelity (DESIGN.md §1).
3. **Verbatim, never cut:** `CONSTRAINTS`, `LAST_REQUEST`, `REJECTED`, `NEXT`. Summaries measurably drop constraints (ConstraintRot, DESIGN.md §2). Cut `FILES`/`STATE` detail first.
4. **Terse markdown, standard words.** No JSON/YAML, no invented abbreviations (BPE makes them longer), `path:line` instead of code. 300-800 words, cap 1200.
5. **Hooks are fast and never fail the session.** `set -uo pipefail`, `exit 0` on every path, timeout 5 s, no network.
6. **Nothing project- or company-specific in the plugin text.** Everything comes from cwd, stdin JSON and the conversation.

## Conventions

Bash scripts with `set -euo pipefail` (hooks: `-uo`, see invariant 5); python3 only for JSON parsing on stdin; docs in English, terse; user writes in Spanish (es-AR, voseo) and prefers autonomy: do the work, ask only before destructive or outward-facing actions. Commit and push only when asked.
