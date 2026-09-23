---
name: handoff-clear
description: Write the compressed handoff, park the user's next prompt so it is injected right after /clear, then tell the user to /clear. Manual only; never auto-invoke.
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
4. If the next prompt is non-empty, Write it verbatim, as plain text with no additions, to `<handoff dir>/pending-prompt.txt`. The SessionStart hook injects it after `/clear` as: `Look at the handoff in <path>. The following is the users next prompt: <text>`. If the next prompt is empty, do not create the file; `rm -f` any stale `pending-prompt.txt`.
5. Reply with exactly two short lines in the user's language and nothing else:
   - `/clear`
   - if a next prompt was parked: "después del clear mandá cualquier mensaje (ej. `dale`): el prompt pendiente se inyecta solo". If not: "después: `lee el handoff, seguimos con …`".
   Claude Code offers no way for a skill to run `/clear` itself; the user types it.
