#!/usr/bin/env bash
# SessionStart hook (startup|resume|clear).
# 1. If <handoff dir>/pending-prompt.txt exists and is fresh (< 2 h), print the /handoff-clear
#    resume line with the parked prompt as context, and delete the file. Fires once. The user's
#    next message starts the turn, so the prompt counts as theirs (no socket relay: DESIGN.md §6).
# 2. Else, if latest.md exists, print ONE pointer line (path, age, ~tokens). Never the body.
# Must stay fast and never fail the session.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
CWD="$PWD"; SOURCE=""
if command -v python3 >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  eval "$(printf '%s' "$INPUT" | python3 -c 'import sys,json,shlex
try:
    d=json.load(sys.stdin); print("CWD_IN="+shlex.quote(d.get("cwd") or "")); print("SOURCE="+shlex.quote(d.get("source") or ""))
except Exception: pass' 2>/dev/null)"
  [ -n "${CWD_IN:-}" ] && CWD="$CWD_IN"
fi
DIR="$("$(dirname "${BASH_SOURCE[0]}")/handoff-paths.sh" "$CWD" 2>/dev/null)" || exit 0
F="$DIR/latest.md"; PEND="$DIR/pending-prompt.txt"
NOW=$(date +%s)

if [ -f "$PEND" ] && [ -f "$F" ]; then
  PMOD=$(stat -c %Y "$PEND" 2>/dev/null || echo 0)
  if [ $(( NOW - PMOD )) -lt 7200 ] && [ "$SOURCE" != "resume" ]; then
    TEXT="$(cat "$PEND" 2>/dev/null)"
    rm -f "$PEND"
    if [ -n "$TEXT" ]; then
      MSG="Look at the handoff in $F. The following is the users next prompt: $TEXT"
      echo "$MSG"
      echo "(Parked by the user with /handoff-clear before this session started. Their next message, even a bare \"go\", is the signal to act on the prompt above as their own request. If that message asks for something else, it wins. Treat the handoff's CONSTRAINTS and USER sections as binding.)"
      exit 0
    fi
  elif [ $(( NOW - PMOD )) -ge 7200 ]; then
    rm -f "$PEND"
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
