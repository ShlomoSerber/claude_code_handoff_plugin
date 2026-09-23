#!/usr/bin/env bash
# statusLine command for Claude Code. Reads the status JSON on stdin and prints one line:
#   context <used>/<window> <pct>%   (+ red warning past HANDOFF_WARN_TOKENS)
# settings.json:
#   "statusLine": { "type": "command", "command": "\"/path/to/claude_code_handoff_plugin/scripts/statusline.sh\"" }
# Env: HANDOFF_WARN_TOKENS (default 100000), HANDOFF_STATUSLINE_COLOR=0 to disable ANSI colors.
set -uo pipefail
WARN="${HANDOFF_WARN_TOKENS:-100000}"
COLOR="${HANDOFF_STATUSLINE_COLOR:-1}"
INPUT="$(cat 2>/dev/null || true)"
read -r -d '' SCRIPT <<'PY' || true
import sys, json
warn = int(sys.argv[1]); color = sys.argv[2] != "0"
try:
    d = json.loads(sys.stdin.read() or "{}")
except Exception:
    print("context ?"); sys.exit(0)

cw = d.get("context_window") or {}
cu = cw.get("current_usage") or {}
# Tokens in context now = last request's fresh input + cache writes + cache reads.
used = sum(int(cu.get(k) or 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
size = int(cw.get("context_window_size") or 0)
pct = cw.get("used_percentage")
if pct is None and size and used:
    pct = used * 100 / size
if not used and pct is not None and size:
    used = int(size * float(pct) / 100)

def k(n):
    n = int(n)
    if n >= 1_000_000: return f"{n/1_000_000:.1f}M"
    if n >= 1_000: return f"{n/1_000:.0f}k"
    return str(n)

def c(code): return code if color else ""
Y, R, G, DIM, B, X = c("\033[33m"), c("\033[31m"), c("\033[32m"), c("\033[2m"), c("\033[1m"), c("\033[0m")

col = G if used < warn * 0.6 else (Y if used < warn else R)
line = f"context {col}{k(used)}{X}" + (f"/{k(size)}" if size else "") + (f" {col}{float(pct):.0f}%{X}" if pct is not None else "")
if used >= warn:
    line += f"  {R}{B}\u26a0 context > {k(warn)}  /handoff-clear <next prompt>{X}"
print(line)
PY
printf '%s' "$INPUT" | python3 -c "$SCRIPT" "$WARN" "$COLOR" 2>/dev/null || echo "context ?"
exit 0
