#!/usr/bin/env bash
# statusLine command for Claude Code. Reads the status JSON on stdin and prints one line:
#   <model> · 5 hour <n>% · weekly <n>% · <model-scoped weekly> <n>% · <used>/<window> <pct>%   (+ red warning past HANDOFF_WARN_TOKENS)
# settings.json:
#   "statusLine": { "type": "command", "command": "\"/path/to/claude_code_handoff_plugin/scripts/statusline.sh\"" }
# 5 hour and weekly come from the status JSON. Per-model weekly limits (e.g. Fable) are not in it: a detached
# background fetch of /api/oauth/usage refreshes a cache at most every 5 min; this script only reads the cache.
# Env: HANDOFF_WARN_TOKENS (default 100000), HANDOFF_STATUSLINE_COLOR=0 to disable ANSI colors,
#      HANDOFF_STATUSLINE_USAGE=0 to skip the per-model fetch.
set -uo pipefail
WARN="${HANDOFF_WARN_TOKENS:-100000}"
COLOR="${HANDOFF_STATUSLINE_COLOR:-1}"
FETCH="${HANDOFF_STATUSLINE_USAGE:-1}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-handoff/usage.json"
INPUT="$(cat 2>/dev/null || true)"

read -r -d '' FETCHER <<'PY' || true
import json, os, sys, time, urllib.request
cache = sys.argv[1]
try:
    tok = json.load(open(os.path.expanduser("~/.claude/.credentials.json")))["claudeAiOauth"]["accessToken"]
    req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers={
        "Authorization": "Bearer " + tok, "anthropic-beta": "oauth-2025-04-20", "Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(req, timeout=10))
    scoped = []
    for l in d.get("limits") or []:
        name = (((l.get("scope") or {}).get("model") or {}).get("display_name"))
        if l.get("kind") == "weekly_scoped" and name and l.get("percent") is not None:
            scoped.append({"name": name, "percent": l["percent"]})
    tmp = cache + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"fetched_at": time.time(), "scoped": scoped}, f)
    os.replace(tmp, cache)
except Exception:
    pass
PY

if [ "$FETCH" != "0" ] && command -v python3 >/dev/null 2>&1; then
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null
  AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
  LOCK="$CACHE.lock"
  # One fetch at a time; a lock older than 60 s is stale.
  if [ "$AGE" -ge 300 ] && { [ ! -e "$LOCK" ] || [ $(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) )) -ge 60 ]; }; then
    touch "$LOCK" 2>/dev/null
    ( python3 -c "$FETCHER" "$CACHE"; rm -f "$LOCK" ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null
  fi
fi

read -r -d '' SCRIPT <<'PY' || true
import sys, json, os
warn = int(sys.argv[1]); color = sys.argv[2] != "0"; cache = sys.argv[3]
try:
    d = json.loads(sys.stdin.read() or "{}")
except Exception:
    print("context ?"); sys.exit(0)

def tokens(u):
    # Tokens in context = fresh input + cache writes + cache reads of one request.
    return sum(int(u.get(k) or 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))

def from_transcript(path):
    # Usage of the last main-thread reply in this session's transcript. None if unreadable, 0 if no reply yet.
    # The status JSON's current_usage can lag behind (stale or null around /clear); the transcript is the source of truth.
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END); size = f.tell()
            f.seek(max(0, size - 512 * 1024))
            lines = f.read().splitlines()
    except OSError:
        return None
    for raw in reversed(lines):
        if b'"usage"' not in raw:
            continue
        try:
            e = json.loads(raw)
        except Exception:
            continue
        if e.get("type") != "assistant" or e.get("isSidechain"):
            continue
        u = (e.get("message") or {}).get("usage")
        if isinstance(u, dict):
            return tokens(u)
    return 0

cw = d.get("context_window") or {}
size = int(cw.get("context_window_size") or 0)
used = from_transcript(d["transcript_path"]) if d.get("transcript_path") else None
if used is None:
    used = tokens(cw.get("current_usage") or {})
pct = used * 100 / size if size else None

def c(code): return code if color else ""
Y, R, G, B, X = c("\033[33m"), c("\033[31m"), c("\033[32m"), c("\033[1m"), c("\033[0m")

def k(n):
    n = int(n)
    if n >= 1_000_000: return f"{n/1_000_000:.1f}M"
    if n >= 1_000: return f"{n/1_000:.0f}k"
    return str(n)

def limit(label, p):
    p = float(p)
    col = G if p < 50 else (Y if p < 80 else R)
    return f"{label} {col}{p:.0f}%{X}"

parts = []
model = ((d.get("model") or {}).get("display_name") or "").strip()
if model:
    parts.append(f"{B}{model}{X}")
rl = d.get("rate_limits") or {}
for key, label in (("five_hour", "5 hour"), ("seven_day", "weekly")):
    p = (rl.get(key) or {}).get("used_percentage")
    if p is not None:
        parts.append(limit(label, p))
try:
    for s in json.load(open(cache)).get("scoped") or []:
        parts.append(limit(str(s["name"]).lower(), s["percent"]))
except Exception:
    pass
col = G if used < warn * 0.6 else (Y if used < warn else R)
parts.append(f"{col}{k(used)}{X}" + (f"/{k(size)}" if size else "") + (f" {col}{pct:.0f}%{X}" if pct is not None else ""))
line = " · ".join(parts)
if used >= warn:
    line += f"  {R}{B}⚠ > {k(warn)}  /handoff-clear <next prompt>{X}"
print(line)
PY
printf '%s' "$INPUT" | python3 -c "$SCRIPT" "$WARN" "$COLOR" "$CACHE" 2>/dev/null || echo "context ?"
exit 0
