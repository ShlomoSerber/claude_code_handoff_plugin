#!/usr/bin/env bash
# Stop hook. Runs every time the model ends a turn; does nothing unless /handoff wrote
# <handoff dir>/request-<session id> in this turn (its content: the next prompt, maybe empty).
#
# Under the `claude` shell function (scripts/claude-wrapper.sh, which exports
# CLAUDE_HANDOFF_RUN and CLAUDE_HANDOFF_SHELL): hand the prompt, the permission mode and the
# handoff path to the wrapper, then end this Claude Code process. The wrapper starts a fresh
# session in the same terminal (DESIGN.md §6).
# Without the wrapper: park the request as pending-prompt.txt for the /clear fallback.
# Must stay fast and never fail the session.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] && command -v python3 >/dev/null 2>&1 || exit 0
eval "$(printf '%s' "$INPUT" | python3 -c 'import sys,json,shlex
try:
    d=json.load(sys.stdin)
    for k in ("session_id","transcript_path","cwd","permission_mode"):
        print(k.upper()+"="+shlex.quote(d.get(k) or ""))
except Exception: pass' 2>/dev/null)"
[ -n "${SESSION_ID:-}" ] || exit 0
if [ -n "${TRANSCRIPT_PATH:-}" ]; then DIR="$(dirname "$TRANSCRIPT_PATH")/handoff"
else DIR="$("$(dirname "${BASH_SOURCE[0]}")/handoff-paths.sh" "${CWD:-$PWD}" "$SESSION_ID" 2>/dev/null)" || exit 0; fi
REQ="$DIR/request-$SESSION_ID"
[ -f "$REQ" ] || exit 0

# A request left by an interrupted turn must not restart a later one.
AGE=$(( $(date +%s) - $(stat -c %Y "$REQ" 2>/dev/null || echo 0) ))
if [ "$AGE" -gt 600 ]; then rm -f "$REQ"; exit 0; fi

RUN="${CLAUDE_HANDOFF_RUN:-}"; SHELL_PID="${CLAUDE_HANDOFF_SHELL:-}"
TARGET=""
if [ -n "$RUN" ] && [ -d "$RUN" ] && [ -n "$SHELL_PID" ]; then
  # Claude Code exports CLAUDE_PID (its own pid) to hooks. End it only if the wrapper's shell is
  # its parent: a claude started from inside another session inherits the wrapper's variables,
  # and must never end the outer one.
  CPID="${CLAUDE_PID:-}"
  if [ -n "$CPID" ] && [ "$(ps -o ppid= -p "$CPID" 2>/dev/null | tr -d ' ')" = "$SHELL_PID" ]; then
    TARGET=$CPID
  fi
fi

if [ -n "$TARGET" ]; then
  mv -f "$REQ" "$RUN/prompt"
  case "${PERMISSION_MODE:-}" in default|"") : > "$RUN/mode" ;; *) printf '%s' "$PERMISSION_MODE" > "$RUN/mode" ;; esac
  printf '%s' "$DIR/latest.md" > "$RUN/load"
  : > "$RUN/restart"
  # Half a second lets Claude Code finish the turn (transcript, screen), then end the session.
  (setsid sh -c "sleep 0.5; kill -TERM $TARGET" </dev/null >/dev/null 2>&1 &) 2>/dev/null
else
  mv -f "$REQ" "$DIR/pending-prompt.txt"
fi
exit 0
