#!/usr/bin/env bash
# Test: Unit test for llm-jetski-hook (the logic behind lazy-llm's Jetski CLI
# plugin): each hook event's effect on the status file, unread marker, model
# and conversation stores, its JSON replies, and the jetski-cli tool adapters.
# Isolated tmux server + isolated HOME; payloads are fed on stdin exactly as
# Jetski would (camelCase protojson).

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="jetski-hook-unit"

REPO_ROOT="$TESTS_DIR/.."
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"
HOOK="$REPO_ROOT/llm-status-bin/.local/bin/llm-jetski-hook"
GUIDE="$REPO_ROOT/llm-status-bin/.local/share/lazy-llm/worktree-agent.md"

# llm-jetski-hook sources its lib as a sibling and finds the worktree guidance
# at ../share (the stowed ~/.local layout); recreate that layout in the sandbox.
sandbox=$(mktemp -d /tmp/lazy-llm-test-jhook-XXXXXX)
mkdir -p "$sandbox/tmux" "$sandbox/home" "$sandbox/local/bin" "$sandbox/local/share/lazy-llm"
ln -s "$LIB_FILE" "$sandbox/local/bin/lazy-llm-lib.sh"
ln -s "$HOOK" "$sandbox/local/bin/llm-jetski-hook"
ln -s "$GUIDE" "$sandbox/local/share/lazy-llm/worktree-agent.md"
BIN="$sandbox/local/bin/llm-jetski-hook"

# A pane whose screen shows Jetski's permission dialog, for the waiting check.
cat > "$sandbox/allow-screen.sh" <<'SCREEN'
printf '● run_command(git push)\n  Allow this command?\n  > Allow once   Always Allow   Deny\n'
exec sleep 60
SCREEN

output=$(TMUX_TMPDIR="$sandbox/tmux" HOME="$sandbox/home" bash <<EOF
unset TMUX TMUX_PANE LAZY_LLM_WORKTREE
source "$LIB_FILE"
tmux -f /dev/null new-session -d -s jk -x 120 -y 30 "exec sleep 60"
P=\$(tmux display -t jk -p '#{pane_id}')
hook() { printf '%s' "\$2" | TMUX_PANE=\$P "$BIN" \$1; echo "rc=\$?"; }
state() { cut -d' ' -f1 "\$HOME/.cache/lazy-llm/status/\$P" 2>/dev/null; }
unread() { lazy_llm_is_unread "\$P" && echo yes || echo no; }

echo "no-tmux-stop: \$(printf '{}' | TMUX_PANE= "$BIN" idle)"
echo "no-tmux-pre: \$(printf '{}' | TMUX_PANE= "$BIN" working)"

C1=aaaaaaaa-1111-4222-8333-000000000001
echo "pre1: \$(hook working '{"conversationId":"'\$C1'","modelName":"gemini-3-pro","invocationNum":0}' | tr '\n' ' ')"
echo "pre1: state=\$(state) unread=\$(unread) conv=<\$(lazy_llm_pane_conv \$P)> model=<\$(lazy_llm_pane_model \$P)>"

echo "stop: \$(hook idle '{"conversationId":"'\$C1'","terminationReason":"model_stop","fullyIdle":true}' | tr '\n' ' ')"
echo "stop: state=\$(state) unread=\$(unread)"

hook working '{"conversationId":"'\$C1'","invocationNum":3}' >/dev/null
hook idle '{"conversationId":"bbbbbbbb-2222-4333-8444-000000000002","parentConversationId":"'\$C1'"}' >/dev/null
echo "subagent-stop: state=\$(state) conv=<\$(lazy_llm_pane_conv \$P)>"
echo "pre3: state=\$(state) unread=\$(unread)"

hook working '{"conversationId":"'\$C1'","invocationNum":0}' >/dev/null
echo "pre1-again: unread=\$(unread)"

echo "shared-pane-guidance: \$(hook working '{"invocationNum":0}' | head -1)"
wt_reply=\$(printf '{"invocationNum":0}' | TMUX_PANE=\$P LAZY_LLM_WORKTREE=1 LAZY_LLM_BASE_BRANCH=main LAZY_LLM_PRIMARY_DIR=/src/repo "$BIN" working)
echo "wt-guidance-json: \$(printf '%s' "\$wt_reply" | jq -e '.injectSteps[0].ephemeralMessage | test("isolated git worktree")' 2>&1)"
echo "wt-guidance-base: \$(printf '%s' "\$wt_reply" | jq -r '.injectSteps[0].ephemeralMessage' | grep -c 'main' )"
echo "wt-guidance-later: \$(printf '{"invocationNum":1}' | TMUX_PANE=\$P LAZY_LLM_WORKTREE=1 "$BIN" working)"

echo "adapter-conv: <\$(lazy_llm_tool_conv jetski-cli \$P)>"
echo "adapter-launch-fresh: <\$(lazy_llm_tool_launch_cmd jetski-cli)>"
echo "adapter-launch-resume: <\$(lazy_llm_tool_launch_cmd jetski-cli \$C1 gemini-3-pro)>"
echo "normalize: <\$(lazy_llm_normalize_tool jetski)> <\$(lazy_llm_normalize_tool jetski-cli)> <\$(lazy_llm_normalize_tool claude)>"

# Fresh "working" from the hook, but the screen shows the permission dialog.
tmux new-window -d -t jk "bash '$sandbox/allow-screen.sh'"
Q=\$(tmux list-panes -t jk:1 -F '#{pane_id}')
sleep 0.5
printf 'working %s\n' "\$(date +%s)" > "\$HOME/.cache/lazy-llm/status/\$Q"
echo "prompt-over-working: \$(lazy_llm_detect_pane_status \$Q jetski-cli)"
printf 'working %s\n' "\$(date +%s)" > "\$HOME/.cache/lazy-llm/status/\$P"
echo "plain-working: \$(lazy_llm_detect_pane_status \$P jetski-cli)"
tmux kill-server 2>/dev/null
EOF
)
rm -rf "$sandbox"

echo "Test 1: replies with valid JSON and no-ops outside tmux..."
assert_contains "$output" 'no-tmux-stop: {"decision":"allow"}' "Stop outside tmux still allows the stop"
assert_contains "$output" "no-tmux-pre: {}" "PreInvocation outside tmux replies {}"
assert_contains "$output" 'stop: {"decision":"allow"} rc=0' "Stop never asks Jetski to continue"
assert_not_contains "$output" "rc=[1-9]" "every hook invocation exits 0"

echo ""
echo "Test 2: status + unread..."
assert_contains "$output" "pre1: state=working unread=no" "PreInvocation -> working"
assert_contains "$output" "stop: state=idle unread=yes" "Stop -> idle + unread"
assert_contains "$output" "pre3: state=working unread=yes" "a later model call in the same turn keeps unread"
assert_contains "$output" "pre1-again: unread=no" "a turn's first model call clears unread"
assert_contains "$output" "subagent-stop: state=working conv=<aaaaaaaa-1111-4222-8333-000000000001>" "a subagent's Stop changes neither status nor conversation"

echo ""
echo "Test 3: conversation + model tracking and adapters..."
assert_contains "$output" "conv=<aaaaaaaa-1111-4222-8333-000000000001>" "conversationId recorded as the pane's conversation"
assert_contains "$output" "model=<gemini-3-pro>" "modelName recorded as the pane's model"
assert_contains "$output" "adapter-conv: <aaaaaaaa-1111-4222-8333-000000000001>" "jetski-cli adapter returns the hook-recorded id"
assert_contains "$output" "adapter-launch-fresh: <jetski-cli>" "fresh launch runs the jetski-cli wrapper"
assert_contains "$output" "adapter-launch-resume: <jetski-cli --conversation 'aaaaaaaa-1111-4222-8333-000000000001'>" "restore resumes the conversation"
assert_contains "$output" "normalize: <jetski-cli> <jetski-cli> <claude>" "jetski is stored as jetski-cli"

echo ""
echo "Test 4: worktree guidance only in isolated panes, on a turn's first call..."
assert_contains "$output" "shared-pane-guidance: {}" "a shared pane gets nothing injected"
assert_contains "$output" "wt-guidance-json: true" "an isolated pane gets the guidance as an ephemeral message"
assert_not_contains "$output" "wt-guidance-base: 0" "the placeholders are filled in"
assert_contains "$output" "wt-guidance-later: {}" "later model calls in the turn inject nothing"

echo ""
echo "Test 5: a permission dialog wins over a fresh hook 'working'..."
assert_contains "$output" "prompt-over-working: waiting" "Allow dialog on screen -> waiting"
assert_contains "$output" "plain-working: working" "no dialog -> the hook's working stands"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Passed: $ASSERTIONS_PASSED"
echo "Failed: $ASSERTIONS_FAILED"

if [ "$ASSERTIONS_FAILED" -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
