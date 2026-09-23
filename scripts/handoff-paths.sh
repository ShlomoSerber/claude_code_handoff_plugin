#!/usr/bin/env bash
# Print the handoff directory for a working directory, mirroring Claude Code's
# ~/.claude/projects/<encoded-cwd>/ layout. Usage: handoff-paths.sh [cwd]
# Encoding observed in ~/.claude/projects: every char outside [A-Za-z0-9] becomes '-'.
set -euo pipefail
CWD="${1:-$PWD}"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ENCODED="$(printf '%s' "$CWD" | sed 's/[^A-Za-z0-9]/-/g')"
echo "$CONFIG_DIR/projects/$ENCODED/handoff"
