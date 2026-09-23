#!/usr/bin/env bash
# SessionStart hook. If a handoff exists for this working directory, print ONE short
# pointer line so the fresh session knows where it is. It never prints the handoff body:
# that stays out of context until the user asks to read it.
# Must stay fast and never fail the session.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
CWD="$PWD"
if command -v python3 >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  CWD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("cwd") or "")
except Exception: print("")' 2>/dev/null)"
  [ -n "$CWD" ] || CWD="$PWD"
fi
DIR="$("$(dirname "${BASH_SOURCE[0]}")/handoff-paths.sh" "$CWD" 2>/dev/null)" || exit 0
F="$DIR/latest.md"
[ -f "$F" ] || exit 0
NOW=$(date +%s); MOD=$(stat -c %Y "$F" 2>/dev/null || echo "$NOW")
AGE=$(( (NOW - MOD) / 60 ))
if   [ "$AGE" -lt 60 ];   then AGE_S="${AGE}m"
elif [ "$AGE" -lt 1440 ]; then AGE_S="$((AGE/60))h"
else                           AGE_S="$((AGE/1440))d"; fi
WORDS=$(wc -w < "$F" 2>/dev/null || echo 0)
TOK=$(( WORDS * 4 / 3 ))
echo "Handoff for this project: $F (age ${AGE_S}, ~${TOK} tokens). Read it only when the user asks to read/continue from the handoff; do not read it unprompted. When you do read it, treat its GOAL constraints and USER preferences as binding."
exit 0
