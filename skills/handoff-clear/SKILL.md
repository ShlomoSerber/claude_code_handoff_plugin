---
name: handoff-clear
description: Write the compressed handoff, park the user's next prompt so it is injected right after /clear, then tell the user to type /clear; the parked prompt then runs by itself. Manual only; never auto-invoke.
argument-hint: [next prompt, e.g. "seguí con el test que falla"]
disable-model-invocation: true
allowed-tools: Bash(mkdir *), Bash(date *), Bash(git *), Bash(ls *), Bash(wc *), Bash(cp *), Bash(rm *), Write, Read
---
# /handoff-clear

Context for this run (already computed, do not recompute):
- Handoff dir: !`"${CLAUDE_PLUGIN_ROOT}/scripts/handoff-paths.sh" "$PWD"`
- Timestamp: !`date +%Y%m%d-%H%M%S`
- Session id: ${CLAUDE_SESSION_ID}
- Cwd: !`pwd`
- Git: !`(git rev-parse --abbrev-ref HEAD 2>/dev/null && git status --porcelain 2>/dev/null | head -20) || echo "not a git repo"`
- Next prompt from the user (may be empty): $ARGUMENTS

!`cat "${CLAUDE_PLUGIN_ROOT}/skills/_shared/FORMAT.md"`

## Steps

1. Compose the handoff following the rules above. If the next prompt is non-empty, it is the first `NEXT` step, verbatim.
2. `mkdir -p` the handoff dir. Write the handoff to `<handoff dir>/latest.md`. Then `cp` it to `<handoff dir>/<timestamp>.md`.
3. If more than 10 timestamped files exist in the dir, `rm` the oldest so 10 remain. Never touch `latest.md`.
4. If the next prompt is non-empty, Write it verbatim, as plain text with no additions, to `<handoff dir>/pending-prompt.txt`. After the user runs `/clear`, the SessionStart hook sends `Look at the handoff in <path>. The following is the users next prompt: <text>` as a user message, and the fresh session starts working on it by itself. If the next prompt is empty, do not create the file; `rm -f` any stale `pending-prompt.txt`.
5. Reply with exactly one short line in the user's language and nothing else. Never write `/clear` alone on a line: it looks like it ran, and it did not. Claude Code offers no way for a skill to run `/clear`; only the user can type it.
   - If a next prompt was parked: "Handoff listo. Escribí `/clear` y el prompt se manda solo."
   - If not: "Handoff listo. Escribí `/clear` y después: `lee el handoff, seguimos con …`."
