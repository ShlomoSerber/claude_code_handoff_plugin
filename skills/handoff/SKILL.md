---
name: handoff
description: Write the compressed handoff of this session, then restart Claude Code with a fresh session that starts from the handoff and, if given, runs the user's next prompt. Manual only; never auto-invoke.
argument-hint: [-i "how to shape the handoff"] [-p "next prompt"]
disable-model-invocation: true
allowed-tools: Bash(mkdir *), Bash(cp *), Bash(ls *), Bash(rm *), Write
---
# /handoff

Context for this run (already computed, do not recompute):
- Handoff dir: !`"${CLAUDE_PLUGIN_ROOT}/scripts/handoff-paths.sh" "${CLAUDE_PROJECT_DIR:-$PWD}" "${CLAUDE_SESSION_ID}"`
- Timestamp: !`date +%Y%m%d-%H%M%S`
- Session id: ${CLAUDE_SESSION_ID}
- Cwd: !`pwd`
- Git: !`(git rev-parse --abbrev-ref HEAD 2>/dev/null && git status --porcelain 2>/dev/null | head -20) || echo "not a git repo"`
- Restart wrapper active: !`[ -n "${CLAUDE_HANDOFF_RUN:-}" ] && echo yes || echo no`
- Raw arguments: $ARGUMENTS

## Arguments

Parse the raw arguments like a shell command line:
- `-i "…"` or `--instructions "…"`: how to shape the handoff (what to emphasize, include or leave out).
- `-p "…"` or `--prompt "…"`: the user's next prompt, to run in the fresh session.
- Values may be in double or single quotes. Either flag may be absent. Strip the outer quotes, keep everything inside verbatim.
- No flags at all but some text: the whole text is the next prompt.

!`cat "${CLAUDE_PLUGIN_ROOT}/skills/_shared/FORMAT.md"`

## Steps

1. Compose the handoff following the rules above. The instructions, if any, override the format's defaults on emphasis, detail and cut order. If there is a next prompt, it is the first `NEXT` step, verbatim.
2. `mkdir -p` the handoff dir. Write the handoff to `<handoff dir>/latest.md`. Then `cp` it to `<handoff dir>/<timestamp>.md`.
3. If more than 10 timestamped files exist in the dir, `rm` the oldest so 10 remain. Never touch `latest.md`.
4. Last tool call: Write the next prompt verbatim, plain text with no additions, to `<handoff dir>/request-<session id>`. With no next prompt, write the file with empty content. This file is the restart signal: when your turn ends, the plugin's Stop hook reads it.
5. Reply with exactly one short line in the user's language and nothing else. Never write `/clear` alone on a line: it looks like it ran.
   - Restart wrapper active: "Handoff listo. Reinicio la sesión." The Stop hook ends this process and the `claude` shell wrapper starts the fresh one, with the handoff loaded and the prompt as its first message.
   - Not active: "Handoff listo. Escribí `/clear` y después `dale`. (Para que reinicie solo, cargá `scripts/claude-wrapper.sh` en tu shell: ver README.)" Without a prompt, say "Escribí `/clear`" only; the handoff loads on its own.
