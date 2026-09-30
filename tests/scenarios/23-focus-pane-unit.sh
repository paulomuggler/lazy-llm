#!/usr/bin/env bash
# Test: Unit test for llm-focus-pane (the click action of llm-claude-hook's
# desktop notifications). A clicked AI pane sitting in the workspace's holding
# window must be swapped into the three-pane layout before the client is
# switched to it, not visited in the holding window. Isolated tmux server with
# a real attached client (script(1) gives it a pty); run with no $TMUX, as the
# notification daemon runs it, so only the socket argument finds the server.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="focus-pane-unit"

REPO_ROOT="$TESTS_DIR/.."
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"
FOCUS="$REPO_ROOT/llm-status-bin/.local/bin/llm-focus-pane"

if ! command -v script >/dev/null 2>&1; then
    echo "SKIP: script(1) not available to attach a tmux client"
    exit 0
fi

# llm-focus-pane sources its lib as a sibling (the stowed ~/.local/bin layout);
# recreate that layout. A failing hyprctl stub keeps it off the real desktop.
sandbox=$(mktemp -d /tmp/lazy-llm-test-focus-XXXXXX)
mkdir -p "$sandbox/tmux" "$sandbox/home" "$sandbox/bin"
ln -s "$LIB_FILE" "$sandbox/bin/lazy-llm-lib.sh"
ln -s "$FOCUS" "$sandbox/bin/llm-focus-pane"
printf '#!/bin/sh\nexit 1\n' > "$sandbox/bin/hyprctl"
chmod +x "$sandbox/bin/hyprctl"

output=$(env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$sandbox/tmux" HOME="$sandbox/home" \
    PATH="$sandbox/bin:$PATH" bash <<EOF
tmux -f /dev/null new-session -d -s ws -x 120 -y 40 "exec sleep 60"
tmux set-option -g base-index 0
SOCK=\$(tmux display -t ws -p '#{socket_path}')
AI1=\$(tmux display -t ws:0 -p '#{pane_id}')
tmux split-window -h -t "\$AI1" "exec sleep 60"
tmux split-window -v -t ws:0 "exec sleep 60"
tmux new-window -d -t ws:9 -n _hold_0 "exec sleep 60"
HOLD=\$(tmux display -t ws:9 -p '#{window_id}')
AI2=\$(tmux display -t ws:9 -p '#{pane_id}')
tmux set-option -w -t ws:9 @lazy_llm_hold 1
tmux set-option -w -t ws:0 @AI_PANES "\$AI1 \$AI2"
tmux set-option -w -t ws:0 @AI_TOOLS "claude claude"
tmux set-option -w -t ws:0 @AI_PANE_IDX 0
tmux set-option -w -t ws:0 @AI_PANE_ID "\$AI1"
tmux set-option -w -t ws:0 @AI_HOLD_WIN "\$HOLD"
tmux new-session -d -s other "exec sleep 60"
PLAIN=\$(tmux display -t other -p '#{pane_id}')

# A real client, parked on the unrelated session.
script -qfc "tmux attach -t other" /dev/null </dev/null >/dev/null 2>&1 &
for _ in \$(seq 1 50); do [ -n "\$(tmux list-clients 2>/dev/null)" ] && break; sleep 0.1; done
echo "clients: \$(tmux list-clients 2>/dev/null | wc -l)"

win_of() { tmux display -t "\$1" -p '#{window_index}'; }
at() { tmux display -c "\$(tmux list-clients -F '#{client_name}' | head -1)" -p '#{session_name}:#{window_index}.#{pane_id}'; }

llm-focus-pane "\$AI2" "\$SOCK"; echo "held-click rc=\$?"
echo "held: ai2-win=\$(win_of \$AI2) ai1-win=\$(win_of \$AI1) idx=\$(tmux show -wv -t ws:0 @AI_PANE_IDX) id-ok=\$([ "\$(tmux show -wv -t ws:0 @AI_PANE_ID)" = "\$AI2" ] && echo yes)"
echo "held-client: \$(at | sed "s/\$AI2\\\$/AI2/")"

llm-focus-pane "\$AI2" "\$SOCK"; echo "visible-click rc=\$?"
echo "visible: ai2-win=\$(win_of \$AI2) idx=\$(tmux show -wv -t ws:0 @AI_PANE_IDX)"

llm-focus-pane "\$PLAIN" "\$SOCK"; echo "plain-click rc=\$?"
echo "plain-client: \$(at | sed "s/\$PLAIN\\\$/PLAIN/")"

llm-focus-pane "%999" "\$SOCK"; echo "dead-click rc=\$?"
echo "dead-client: \$(at | sed "s/\$PLAIN\\\$/PLAIN/")"

tmux kill-server 2>/dev/null
EOF
)
rm -rf "$sandbox"

echo "Test 1: a held pane is swapped into the layout before switching..."
assert_contains "$output" "clients: 1" "sandbox has an attached client"
assert_contains "$output" "held-click rc=0" "exits 0"
assert_contains "$output" "held: ai2-win=0 ai1-win=9 idx=1 id-ok=yes" "clicked pane swapped into the workspace window, state updated"
assert_contains "$output" "held-client: ws:0.AI2" "client lands on the workspace window, on the clicked pane"

echo ""
echo "Test 2: the pane already in view stays put..."
assert_contains "$output" "visible-click rc=0" "exits 0"
assert_contains "$output" "visible: ai2-win=0 idx=1" "no swap when already visible"

echo ""
echo "Test 3: a pane outside any workspace, and a gone pane..."
assert_contains "$output" "plain-client: other:0.PLAIN" "plain pane is still focused"
assert_contains "$output" "dead-click rc=0" "gone pane exits 0"
assert_contains "$output" "dead-client: other:0.PLAIN" "gone pane leaves the client where it was"

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
