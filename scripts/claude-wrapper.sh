# Source from ~/.bashrc or ~/.zshrc:
#   source "/path/to/claude_code_handoff_plugin/scripts/claude-wrapper.sh"
#
# Defines `claude` as a shell function around the real binary. When /handoff finishes, the
# plugin's Stop hook (scripts/stop.sh) leaves a restart request in this function's run dir
# and ends the Claude Code process; this function then starts a fresh session in the same
# terminal, with the same permission mode and the /handoff -p prompt as its first message.
# The SessionStart hook loads the handoff into that session. Nothing can run /clear inside a
# live session (DESIGN.md §6), so a new process is the only clean context without a keystroke.
# Without a restart request, it behaves exactly like `claude`.
claude() {
  local run rc prompt mode
  run="$(mktemp -d "${TMPDIR:-/tmp}/claude-handoff.XXXXXX" 2>/dev/null)" || { command claude "$@"; return; }
  CLAUDE_HANDOFF_RUN="$run" CLAUDE_HANDOFF_SHELL=$$ command claude "$@"
  rc=$?
  while [ -f "$run/restart" ]; do
    prompt="$(cat "$run/prompt" 2>/dev/null)"
    mode="$(cat "$run/mode" 2>/dev/null)"
    rm -f "$run/restart" "$run/prompt" "$run/mode"
    set --
    [ -n "$mode" ] && set -- --permission-mode "$mode"
    [ -n "$prompt" ] && set -- "$@" "$prompt"
    printf '\n\033[1;36m[handoff]\033[0m fresh session, handoff loaded%s\n\n' "${prompt:+, running your prompt}"
    CLAUDE_HANDOFF_RUN="$run" CLAUDE_HANDOFF_SHELL=$$ CLAUDE_HANDOFF_LOAD="$run/load" command claude "$@"
    rc=$?
  done
  rm -rf "$run"
  return $rc
}
