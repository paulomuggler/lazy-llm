#!/usr/bin/env bash
# Test: Unit test for the AI pane border's identity suffixes
# (pane-border-identity-suffixes): "workspace - pane name - harness - model".
# Covers lazy_llm_short_model, the per-pane model store (pid guard), and
# llm-pane-border's rendered text. Isolated tmux server + isolated HOME.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="pane-border-identity-unit"

REPO_ROOT="$TESTS_DIR/.."
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"
BORDER="$REPO_ROOT/lazy-llm-bin/.local/bin/llm-pane-border"

# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: lazy_llm_short_model..."
source "$LIB_FILE"
cases=(
    "claude-sonnet-5=sonnet5"
    "claude-opus-5-5[1m]=opus5.5[1m]"
    "claude-haiku-4-5-20251001=haiku4.5"
    "claude-fable-5-1=fable5.1"
    "gpt-5-codex=gpt-5-codex"
    "=")
for c in "${cases[@]}"; do
    assert_equals "$(lazy_llm_short_model "${c%%=*}")" "${c#*=}" "'${c%%=*}' shortens to '${c#*=}'"
done

# ──────────────────────────────────────────────────────────────────────────
# llm-pane-border sources its lib as a sibling (the stowed ~/.local/bin
# layout); recreate that layout in the sandbox.
sandbox=$(mktemp -d /tmp/lazy-llm-test-identity-XXXXXX)
mkdir -p "$sandbox/tmux" "$sandbox/home" "$sandbox/bin"
ln -s "$LIB_FILE" "$sandbox/bin/lazy-llm-lib.sh"
ln -s "$BORDER" "$sandbox/bin/llm-pane-border"

output=$(TMUX_TMPDIR="$sandbox/tmux" HOME="$sandbox/home" bash <<EOF
unset TMUX TMUX_PANE
source "$LIB_FILE"
strip() { sed 's/#\[[^]]*\]//g'; }
tmux -f /dev/null new-session -d -s myws -x 120 -y 20 "exec sleep 60"
P=\$(tmux display -t myws -p '#{pane_id}')
tmux set-option -t myws @lazy_llm 1
tmux set-option -w -t myws @AI_PANES "\$P"
tmux set-option -w -t myws @AI_TOOLS claude

echo "store-empty=<\$(lazy_llm_pane_model "\$P")>"
lazy_llm_set_pane_model "\$P" claude-sonnet-5
echo "store-set=<\$(lazy_llm_pane_model "\$P")>"

echo "unnamed=<\$("$sandbox/bin/llm-pane-border" "\$P" claude | strip)>"
tmux set-option -w -t myws @AI_PANE_NAMES "dash-work"
echo "named=<\$("$sandbox/bin/llm-pane-border" "\$P" claude | strip)>"

rm -f "\$HOME/.cache/lazy-llm/model/\$P"
echo "nomodel=<\$("$sandbox/bin/llm-pane-border" "\$P" claude | strip)>"

echo "999999 claude-opus-5-5" > "\$HOME/.cache/lazy-llm/model/\$P"
echo "stale=<\$(lazy_llm_pane_model "\$P")>"
[ -f "\$HOME/.cache/lazy-llm/model/\$P" ] && echo "stale-file=kept" || echo "stale-file=gone"
tmux kill-server 2>/dev/null
EOF
)
rm -rf "$sandbox"

echo ""
echo "Test 2: per-pane model store..."
assert_contains "$output" "store-empty=<>" "no model recorded -> empty"
assert_contains "$output" "store-set=<sonnet5>" "recorded model is returned shortened"
assert_contains "$output" "stale=<>" "model recorded under another pid is ignored"
assert_contains "$output" "stale-file=gone" "stale model file is cleaned up"

echo ""
echo "Test 3: llm-pane-border identity..."
assert_contains "$output" "│ myws - claude - sonnet5 " "unnamed pane: pane-name segment dropped"
assert_contains "$output" "│ myws - dash-work - claude - sonnet5 " "named pane: full workspace - name - harness - model"
# The bare test pane has no prompt, so its glyph is "?" (unknown) — match any
# single glyph right after the harness, then the line's end delimiter.
assert_contains "$output" "nomodel=<.*│ myws - dash-work - claude [^ -]+ >" "unknown model: model segment dropped"

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
