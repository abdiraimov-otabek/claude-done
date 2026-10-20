#!/bin/bash
# Runs claude-done against fixture hook input and a throwaway settings.json. Never touches your real files.
cd "$(dirname "$0")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/" CLAUDE_DONE_DRY=1 CLAUDE_DONE_CONFIG="$T/none" CLAUDE_DONE_SETTINGS="$T/settings.json"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "     want: $3"; echo "     got:  $2"; fail=1; fi; }
run() { printf '%s' "$1" | ./claude-done hook; }

S='"session_id":"abc-123","cwd":"/Users/me/code/halo"'

# A turn shorter than MIN_SECONDS stays quiet.
run "{$S,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}"
check "quick turn is silent" "$(run "{$S,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"Hi!\"}")" ""

# A long turn pings with the project, the duration and the first line of the reply.
echo $(( $(date +%s) - 252 )) > "$T/claude-done/abc-123"
check "long turn pings" "$(run "{$S,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"Refactored the auth middleware.\\nAll tests pass.\"}")" \
  "NOTIFY|✅ halo is done|in 4m 12s|Refactored the auth middleware. All tests pass.|Glass"

# A Stop that Claude Code is continuing from another stop hook doesn't ping twice.
check "stop_hook_active is silent" "$(run "{$S,\"hook_event_name\":\"Stop\",\"stop_hook_active\":true}")" ""

# Permission prompts ping; idle prompts don't by default.
check "permission pings" "$(run "{$S,\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"message\":\"Claude needs your permission to use Bash\"}")" \
  "NOTIFY|✋ halo needs you|Claude needs your permission to use Bash||Ping"
check "idle is silent" "$(run "{$S,\"hook_event_name\":\"Notification\",\"notification_type\":\"idle_prompt\",\"message\":\"Claude is waiting for your input\"}")" ""

# A message with quotes reaches the notification intact.
check "quotes survive" "$(run "{$S,\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"message\":\"Run \\\"rm -rf build\\\"?\"}")" \
  "NOTIFY|✋ halo needs you|Run \"rm -rf build\"?||Ping"

# install keeps the user's own hooks and is idempotent; uninstall removes only ours.
cat > "$T/settings.json" <<'EOF'
{ "model": "opus", "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "afplay /System/Library/Sounds/Hero.aiff" } ] } ] } }
EOF
./claude-done install >/dev/null; ./claude-done install >/dev/null
count=$(grep -c "claude-done' hook" "$T/settings.json")
check "install adds 4 hooks once" "$count" "4"
check "install keeps user hook" "$(grep -c Hero.aiff "$T/settings.json")" "1"
check "install keeps other keys" "$(plutil -extract model raw -o - "$T/settings.json")" "opus"
./claude-done uninstall >/dev/null
check "uninstall removes ours" "$(grep -c "claude-done" "$T/settings.json")" "0"
check "uninstall keeps user hook" "$(grep -c Hero.aiff "$T/settings.json")" "1"

exit $fail
