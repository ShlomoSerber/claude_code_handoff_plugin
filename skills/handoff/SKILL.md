---
name: handoff
description: Write a compressed, AI-only handoff of this session to disk, then tell the user to /clear and say "read the handoff". Manual only; never auto-invoke.
argument-hint: [optional note for the next session, e.g. "next: fix the failing test"]
disable-model-invocation: true
allowed-tools: Bash(mkdir *), Bash(date *), Bash(git *), Bash(ls *), Bash(wc *), Bash(cp *), Bash(rm *), Write, Read
---
# /handoff

Context for this run (already computed, do not recompute):
- Handoff dir: !`"${CLAUDE_PLUGIN_ROOT}/scripts/handoff-paths.sh" "$PWD"`
- Timestamp: !`date +%Y%m%d-%H%M%S`
- Session id: ${CLAUDE_SESSION_ID}
- Cwd: !`pwd`
- Git: !`(git rev-parse --abbrev-ref HEAD 2>/dev/null && git status --porcelain 2>/dev/null | head -20) || echo "not a git repo"`
- User note: $ARGUMENTS

!`cat "${CLAUDE_PLUGIN_ROOT}/skills/_shared/FORMAT.md"`

## Steps

1. Compose the handoff following the rules above.
2. `mkdir -p` the handoff dir. Write the handoff to `<handoff dir>/latest.md`. Then `cp` it to `<handoff dir>/<timestamp>.md` so history is kept.
3. If more than 10 timestamped files exist in the dir, `rm` the oldest so 10 remain. Never touch `latest.md`.
4. Count words of `latest.md` with `wc -w`.
5. Reply to the user in their language with exactly three short lines and nothing else:
   - path of `latest.md` and its size as `~N tokens` (words × 4/3);
   - `/clear`;
   - the resume phrase to type next, e.g. `lee el handoff, seguimos con <NEXT first step>`.
   Do not restate the handoff content in the reply.
