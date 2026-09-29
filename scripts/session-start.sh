#!/usr/bin/env bash
# SessionStart hook (startup|resume|clear).
# 1. Restarted by the `claude` wrapper after /handoff (source startup, $CLAUDE_HANDOFF_LOAD
#    names a one-shot file holding the handoff path): print the handoff body as context. The
#    user's -p prompt, if any, arrives as the session's first message.
# 2. /clear fallback (no wrapper): if <handoff dir>/pending-prompt.txt is fresh (< 2 h), print
#    the handoff body plus the parked prompt, once. The user's next message starts the turn.
# 3. Else, if latest.md exists, print ONE pointer line (path, age, ~tokens). Never the body.
# The body enters context only in 1 and 2, i.e. right after the user's own /handoff.
# Must stay fast and never fail the session.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
CWD="$PWD"; SOURCE=""; SESSION_ID=""; TRANSCRIPT_PATH=""
if command -v python3 >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  eval "$(printf '%s' "$INPUT" | python3 -c 'import sys,json,shlex
try:
    d=json.load(sys.stdin)
    for k in ("cwd","source","session_id","transcript_path"):
        print(k.upper()+"="+shlex.quote(d.get(k) or ""))
except Exception: pass' 2>/dev/null)"
  [ -n "$CWD" ] || CWD="$PWD"
fi

print_body() { # $1 = handoff file, $2 = how the session got here
  echo "Handoff from the previous session in this project, written by the user's /handoff ($2). It is this session's starting state: treat its CONSTRAINTS and USER sections as binding, and do not re-read it from disk ($1)."
  echo
  cat "$1"
}

LOAD="${CLAUDE_HANDOFF_LOAD:-}"
if [ "$SOURCE" = "startup" ] && [ -n "$LOAD" ] && [ -f "$LOAD" ]; then
  H="$(cat "$LOAD" 2>/dev/null)"; rm -f "$LOAD"
  if [ -f "$H" ]; then print_body "$H" "the session was restarted right after it"; exit 0; fi
fi

if [ -n "$TRANSCRIPT_PATH" ]; then DIR="$(dirname "$TRANSCRIPT_PATH")/handoff"
else DIR="$("$(dirname "${BASH_SOURCE[0]}")/handoff-paths.sh" "$CWD" "$SESSION_ID" 2>/dev/null)" || exit 0; fi
F="$DIR/latest.md"; PEND="$DIR/pending-prompt.txt"
NOW=$(date +%s)

if [ -f "$PEND" ]; then
  PMOD=$(stat -c %Y "$PEND" 2>/dev/null || echo 0)
  if [ $(( NOW - PMOD )) -ge 7200 ]; then
    rm -f "$PEND"
  elif [ "$SOURCE" != "resume" ] && [ -f "$F" ]; then
    TEXT="$(cat "$PEND" 2>/dev/null)"
    rm -f "$PEND"
    print_body "$F" "then /clear"
    if [ -n "$TEXT" ]; then
      echo
      echo "PENDING REQUEST, typed by the user with /handoff before this session started: $TEXT"
      echo "When the user's next message arrives, carry out that pending request as their own. A short go-ahead (\"dale\", \"go\", \"ok\") means exactly that: do the pending request, do not just acknowledge. If the message asks for something else instead, do that."
    fi
    exit 0
  fi
fi

[ -f "$F" ] || exit 0
MOD=$(stat -c %Y "$F" 2>/dev/null || echo "$NOW")
AGE=$(( (NOW - MOD) / 60 ))
if   [ "$AGE" -lt 60 ];   then AGE_S="${AGE}m"
elif [ "$AGE" -lt 1440 ]; then AGE_S="$((AGE/60))h"
else                           AGE_S="$((AGE/1440))d"; fi
WORDS=$(wc -w < "$F" 2>/dev/null || echo 0)
TOK=$(( WORDS * 4 / 3 ))
echo "Handoff for this project: $F (age ${AGE_S}, ~${TOK} tokens). Read it only when the user asks to read/continue from the handoff; do not read it unprompted. When you do read it, treat its CONSTRAINTS and USER sections as binding."
exit 0
