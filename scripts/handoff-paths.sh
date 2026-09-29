#!/usr/bin/env bash
# Print the handoff directory, mirroring Claude Code's ~/.claude/projects/<encoded-cwd>/ layout.
# Usage: handoff-paths.sh [cwd] [session_id]
# With a session id, the directory is the one holding that session's transcript. That is the
# project Claude Code started in, even after the session cd'd into a subdirectory (the bug that
# broke 0.5.0: skill and hook computed different directories). Without one, or if the transcript
# is not found, every char of cwd outside [A-Za-z0-9] becomes '-' (observed in ~/.claude/projects).
set -euo pipefail
CWD="${1:-$PWD}"
SID="${2:-}"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -n "$SID" ]; then
  for t in "$CONFIG_DIR"/projects/*/"$SID".jsonl; do
    [ -f "$t" ] && { echo "$(dirname "$t")/handoff"; exit 0; }
  done
fi
ENCODED="$(printf '%s' "$CWD" | sed 's/[^A-Za-z0-9]/-/g')"
echo "$CONFIG_DIR/projects/$ENCODED/handoff"
