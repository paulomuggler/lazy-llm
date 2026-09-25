#!/usr/bin/env bash
# Test: Unit test for llm-claude-hook (the logic behind lazy-llm's Claude Code
# plugin): each hook event's effect on the status file, unread marker and
# per-pane model store. Isolated tmux server + isolated HOME; payloads are
# fed on stdin exactly as Claude Code would.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="claude-hook-unit"

REPO_ROOT="$TESTS_DIR/.."
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"
HOOK="$REPO_ROOT/llm-status-bin/.local/bin/llm-claude-hook"

# llm-claude-hook sources its lib as a sibling (the stowed ~/.local/bin
# layout); recreate that layout in the sandbox.
sandbox=$(mktemp -d /tmp/lazy-llm-test-hook-XXXXXX)
mkdir -p "$sandbox/tmux" "$sandbox/home" "$sandbox/bin"
ln -s "$LIB_FILE" "$sandbox/bin/lazy-llm-lib.sh"
ln -s "$HOOK" "$sandbox/bin/llm-claude-hook"
printf '%s\n' \
    '{"type":"assistant","message":{"model":"claude-opus-5-5","content":[]}}' \
    '{"type":"assistant","message":{"model":"<synthetic>"}}' > "$sandbox/transcript.jsonl"

output=$(TMUX_TMPDIR="$sandbox/tmux" HOME="$sandbox/home" bash <<EOF
unset TMUX TMUX_PANE
source "$LIB_FILE"
tmux -f /dev/null new-session -d -s hk "exec sleep 60"
P=\$(tmux display -t hk -p '#{pane_id}')
hook() { printf '%s' "\$2" | TMUX_PANE=\$P "$sandbox/bin/llm-claude-hook" \$1; echo "rc=\$?"; }
state() { cut -d' ' -f1 "\$HOME/.cache/lazy-llm/status/\$P" 2>/dev/null; }
unread() { lazy_llm_is_unread "\$P" && echo yes || echo no; }

echo "no-tmux: \$(printf '{}' | TMUX_PANE= "$sandbox/bin/llm-claude-hook" idle; echo rc=\$?)"

hook waiting '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
echo "permission_prompt: state=\$(state) unread=\$(unread)"

hook idle '{"hook_event_name":"Notification","notification_type":"idle_prompt"}'
echo "idle_prompt: state=\$(state) unread=\$(unread)"

hook "" '{"hook_event_name":"Stop","transcript_path":"$sandbox/transcript.jsonl"}'
echo "stop: state=\$(state) unread=\$(unread) model=<\$(lazy_llm_pane_model \$P)>"

lazy_llm_clear_unread "\$P"
hook idle '{"hook_event_name":"Notification","notification_type":"idle_prompt"}'
echo "idle_prompt-after-clear: unread=\$(unread)"

hook "" '{"hook_event_name":"SessionStart","source":"startup","model":"claude-sonnet-5"}'
echo "sessionstart: model=<\$(lazy_llm_pane_model \$P)>"

hook "" '{"hook_event_name":"Stop","transcript_path":"$sandbox/transcript.jsonl"}'
echo "stop-no-overwrite: model=<\$(lazy_llm_pane_model \$P)>"

hook "" '{"hook_event_name":"PostModelSwitch","from_model":"claude-sonnet-5","to_model":"claude-opus-5-5[1m]"}'
echo "switch: model=<\$(lazy_llm_pane_model \$P)>"

hook "" '{"hook_event_name": "SessionStart", "model": {"id": "claude-haiku-4-5-20251001", "display_name": "Haiku"}}'
echo "sessionstart-object: model=<\$(lazy_llm_pane_model \$P)>"
tmux kill-server 2>/dev/null
EOF
)
rm -rf "$sandbox"

echo "Test 1: no-ops cleanly outside tmux..."
assert_contains "$output" "no-tmux: rc=0" "exits 0 with TMUX_PANE unset"

echo ""
echo "Test 2: Notification / Stop status + unread..."
assert_contains "$output" "permission_prompt: state=waiting unread=no" "permission_prompt -> waiting, not unread"
assert_contains "$output" "idle_prompt: state=idle unread=no" "idle_prompt -> idle, not unread"
assert_contains "$output" "stop: state=idle unread=yes" "Stop -> idle + unread"
assert_contains "$output" "idle_prompt-after-clear: unread=no" "idle_prompt does not re-mark a cleared pane"
assert_not_contains "$output" "rc=[1-9]" "every hook invocation exits 0"

echo ""
echo "Test 3: model tracking..."
assert_contains "$output" "stop: .* model=<opus5.5>" "Stop fills an empty model from the transcript, skipping <synthetic>"
assert_contains "$output" "sessionstart: model=<sonnet5>" "SessionStart records the payload model"
assert_contains "$output" "stop-no-overwrite: model=<sonnet5>" "Stop never overwrites a recorded model"
assert_contains "$output" "switch: model=<opus5.5\[1m\]>" "PostModelSwitch records to_model"
assert_contains "$output" "sessionstart-object: model=<haiku4.5>" "object-shaped SessionStart model is accepted"

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
