#!/usr/bin/env bash
# Test: Unit tests for the worktree bridge tab lib helpers + dashboard wiring.
# Uses disposable /tmp git repos; no live tmux.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="worktree-bridge-tab-unit"

# lazy_llm_gather_worktrees calls tmux. With $TMUX set, tmux ignores
# TMUX_TMPDIR and reaches the user's own server: unset it for the whole run.
unset TMUX TMUX_PANE

LIB_FILE="$TESTS_DIR/../llm-send-bin/.local/bin/lazy-llm-lib.sh"
DASHBOARD="$TESTS_DIR/../lazy-llm-bin/.local/bin/llm-dashboard"
# shellcheck source=/dev/null
source "$LIB_FILE"

mk_repo() {
    local d="$1"
    rm -rf "$d"
    mkdir -p "$d"
    (
      cd "$d" || exit 1
      git init -q -b main >/dev/null
      git config user.email test@test
      git config user.name test
      printf 'init\n' > README.md
      git add README.md
      git commit -q -m init >/dev/null
    )
}

cleanup_repos() {
    rm -rf /tmp/lazy-llm-wbt-test-*
}
trap cleanup_repos EXIT

# ──────────────────────────────────────────────────────────────────────────
# 1. lazy_llm_default_branch
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: lazy_llm_default_branch finds main..."
REPO=/tmp/lazy-llm-wbt-test-1
mk_repo "$REPO"
out=$(cd "$REPO" && lazy_llm_default_branch)
assert_equals "$out" "main" "fresh repo with main as init branch"

echo ""
echo "Test 2: lazy_llm_default_branch fallback to master..."
REPO=/tmp/lazy-llm-wbt-test-2
rm -rf "$REPO"
mkdir -p "$REPO"
(cd "$REPO" && git init -q -b master >/dev/null && git config user.email t@t && git config user.name t && printf x > a && git add a && git commit -q -m m)
out=$(cd "$REPO" && lazy_llm_default_branch)
assert_equals "$out" "master" "repo with only master returns master"

# ──────────────────────────────────────────────────────────────────────────
# 3. lazy_llm_gather_worktrees on repo with main + one extra worktree
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: gather_worktrees emits one row per worktree..."
REPO=/tmp/lazy-llm-wbt-test-3
mk_repo "$REPO"
# Add a second worktree
(cd "$REPO" && git worktree add /tmp/lazy-llm-wbt-test-3-wt -b feature-x >/dev/null 2>&1)

out=$(cd "$REPO" && lazy_llm_gather_worktrees)
row_count=$(echo "$out" | command grep -c .)
assert_equals "$row_count" "2" "two worktrees → two rows"

# Confirm columns: each row should be 8 \x1f-separated fields (OWNER added
# by worktree-concurrency-mode; \x1f because empty fields are common)
first_cols=$(echo "$out" | head -1 | awk -F$'\x1f' '{print NF}')
assert_equals "$first_cols" "8" "row has 8 columns"

# Branch column for the feature-x worktree
fx_branch=$(echo "$out" | command grep 'lazy-llm-wbt-test-3-wt' | awk -F$'\x1f' '{print $2}')
assert_equals "$fx_branch" "feature-x" "feature-x worktree branch correct"

# ──────────────────────────────────────────────────────────────────────────
# 4. Dirty marker
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: dirty marker present for dirty worktree..."
# Touch a file in the secondary worktree to make it dirty
(cd /tmp/lazy-llm-wbt-test-3-wt && printf 'dirty\n' > new-file)
out=$(cd "$REPO" && lazy_llm_gather_worktrees)
fx_dirty=$(echo "$out" | command grep 'lazy-llm-wbt-test-3-wt' | awk -F$'\x1f' '{print $3}')
assert_equals "$fx_dirty" "*" "dirty worktree shows '*'"

# Clean it up to keep test 5 reliable
rm -f /tmp/lazy-llm-wbt-test-3-wt/new-file

# ──────────────────────────────────────────────────────────────────────────
# 5. Skips detached-HEAD worktrees
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: detached-HEAD worktree skipped..."
HEAD_SHA=$(cd "$REPO" && git rev-parse HEAD)
(cd "$REPO" && git worktree add --detach /tmp/lazy-llm-wbt-test-3-detached "$HEAD_SHA" >/dev/null 2>&1)

out=$(cd "$REPO" && lazy_llm_gather_worktrees)
detached_present=$(echo "$out" | command grep -c 'detached' || true)
assert_equals "$detached_present" "0" "detached worktree NOT in output"

# ──────────────────────────────────────────────────────────────────────────
# 6. cleanup_worktree happy path (clean, no force)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: cleanup_worktree removes clean worktree + deletes branch..."
REPO=/tmp/lazy-llm-wbt-test-6
mk_repo "$REPO"
(cd "$REPO" && git worktree add /tmp/lazy-llm-wbt-test-6-wt -b feat-clean >/dev/null 2>&1)
assert_dir_exists "/tmp/lazy-llm-wbt-test-6-wt" "worktree dir present before cleanup"

lazy_llm_cleanup_worktree /tmp/lazy-llm-wbt-test-6-wt yes no 2>/dev/null
rc=$?
assert_equals "$rc" "0" "cleanup returns 0 on success"

# Worktree dir gone
if [ ! -d /tmp/lazy-llm-wbt-test-6-wt ]; then
    print_pass "worktree dir removed"
else
    print_fail "worktree dir still present"
fi

# Branch deleted
if (cd "$REPO" && git rev-parse --verify --quiet refs/heads/feat-clean >/dev/null 2>&1); then
    print_fail "branch should have been deleted"
else
    print_pass "branch deleted"
fi

# ──────────────────────────────────────────────────────────────────────────
# 7. cleanup_worktree preserves branch when delete_branch=no
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 7: cleanup_worktree preserves branch when delete_branch=no..."
REPO=/tmp/lazy-llm-wbt-test-7
mk_repo "$REPO"
(cd "$REPO" && git worktree add /tmp/lazy-llm-wbt-test-7-wt -b feat-keep >/dev/null 2>&1)

lazy_llm_cleanup_worktree /tmp/lazy-llm-wbt-test-7-wt no no 2>/dev/null

if (cd "$REPO" && git rev-parse --verify --quiet refs/heads/feat-keep >/dev/null 2>&1); then
    print_pass "branch preserved when delete_branch=no"
else
    print_fail "branch was deleted unexpectedly"
fi

# ──────────────────────────────────────────────────────────────────────────
# 8. cleanup_worktree force mode handles dirty
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 8: cleanup_worktree force=yes against dirty worktree..."
REPO=/tmp/lazy-llm-wbt-test-8
mk_repo "$REPO"
(cd "$REPO" && git worktree add /tmp/lazy-llm-wbt-test-8-wt -b feat-dirty >/dev/null 2>&1)
(cd /tmp/lazy-llm-wbt-test-8-wt && printf 'dirty\n' > extra)

lazy_llm_cleanup_worktree /tmp/lazy-llm-wbt-test-8-wt yes yes 2>/dev/null
rc=$?
assert_equals "$rc" "0" "force cleanup succeeds against dirty worktree"

if [ ! -d /tmp/lazy-llm-wbt-test-8-wt ]; then
    print_pass "dirty worktree removed with --force"
else
    print_fail "dirty worktree still present"
fi

# ──────────────────────────────────────────────────────────────────────────
# 9. Dashboard structural: render_worktrees_tab no longer placeholder
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 9: render_worktrees_tab uses gather_worktrees..."
if command grep -q 'lazy_llm_gather_worktrees' "$DASHBOARD"; then
    print_pass "dashboard calls lazy_llm_gather_worktrees"
else
    print_fail "dashboard does NOT call lazy_llm_gather_worktrees"
fi

# Placeholder string should be gone
if command grep -q 'Worktrees tab — coming soon' "$DASHBOARD"; then
    print_fail "placeholder text still present"
else
    print_pass "placeholder text removed"
fi

# ──────────────────────────────────────────────────────────────────────────
# 10. Dispatch verbs + main-loop allowlist
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 10: dispatch_action has worktree verbs..."
for verb in worktree-open worktree-new worktree-lazygit worktree-cleanup; do
    if command grep -q "action:$verb" "$DASHBOARD"; then
        print_pass "dispatch handles action:$verb"
    else
        print_fail "dispatch does NOT handle action:$verb"
    fi
done

echo ""
echo "Test 11: main loop allowlist includes worktree verbs..."
loop_arm=$(command grep -E 'action:switch:\*\|action:switch-pane' "$DASHBOARD")
assert_contains "$loop_arm" "worktree-open:" "loop arm includes worktree-open"
assert_contains "$loop_arm" "worktree-new" "loop arm includes worktree-new"
assert_contains "$loop_arm" "worktree-lazygit:" "loop arm includes worktree-lazygit"
assert_contains "$loop_arm" "worktree-cleanup:" "loop arm includes worktree-cleanup"

# ──────────────────────────────────────────────────────────────────────────
# 12. Help text mentions worktrees actions
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 12: help text documents Worktrees actions..."
help_out=$("$DASHBOARD" --help 2>&1)
assert_contains "$help_out" "Worktrees" "usage mentions Worktrees tab"
assert_contains "$help_out" "g" "usage documents g (lazygit) key"

# ──────────────────────────────────────────────────────────────────────────
# 13–15. Claude's worktrees (claude-subagent-worktrees-ui, spec
# claude-subagent-worktrees.md §10): owner values, the tab's tag, and `I`.
# A private sandbox: its own tmux socket, HOME and git identity; work from
# inside it so an empty path never reaches the lazy-llm checkout.
# ──────────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
LLMWT="$REPO_ROOT/llm-wt-bin/.local/bin/llm-wt"
sandbox=$(mktemp -d /tmp/lazy-llm-test-wbtclaude-XXXXXX)
cleanup_all() {
    env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$sandbox/tmux" tmux kill-server 2>/dev/null || true
    rm -rf "$sandbox"
    cleanup_repos
}
trap cleanup_all EXIT
cd "$sandbox" || exit 1
export GIT_CEILING_DIRECTORIES=/tmp
export HOME="$sandbox/home" TMUX_TMPDIR="$sandbox/tmux"
mkdir -p "$HOME/.local/bin" "$TMUX_TMPDIR"
unset XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE LAZY_LLM_WORKTREE_DIR
git config --global user.email test@test
git config --global user.name test
git config --global init.defaultBranch main
for f in llm-send-bin/.local/bin/lazy-llm-lib.sh llm-wt-bin/.local/bin/llm-wt \
         lazy-llm-bin/.local/bin/llm-dashboard; do
    ln -sf "$REPO_ROOT/$f" "$HOME/.local/bin/${f##*/}"
done
# Claude's WorktreeCreate, as the plugin runs it: payload on stdin, the
# owning pane in TMUX_PANE (empty = none). Stdout: the worktree's path.
claude_wt() {
    printf '{"session_id":"s1","cwd":"%s","hook_event_name":"WorktreeCreate","name":"%s"}' "$1" "$2" \
        | TMUX_PANE="$3" "$LLMWT" claude-hook 2>/dev/null
}
owner_of() { (cd "$R" && lazy_llm_gather_worktrees) | awk -F$'\x1f' -v p="$1" '$1 == p {print $8}'; }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
# Literal substring checks (assert_contains matches a regex, and these
# needles carry "(", ")" and "*").
assert_has() {
    if [[ "$1" == *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Looking for: '$2'"; echo "  In text: '${1:0:300}...'"; fi
}
assert_lacks() {
    if [[ "$1" != *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Unexpected: '$2'"; fi
}
# check <message> <command...>: passes when the command succeeds.
check() {
    local msg="$1"; shift
    if "$@"; then ((ASSERTIONS_PASSED++)); print_pass "$msg"; else print_fail "$msg"; fi
}

echo ""
echo "Test 13: gather_worktrees owners for Claude's worktrees..."
R="$sandbox/r13"
mkdir -p "$R" && git -C "$R" init -q && printf 'a\n' > "$R/a.txt" \
    && git -C "$R" add a.txt && git -C "$R" commit -qm init
tmux -f /dev/null new-session -d -s cws -c "$R" -x 220 -y 50 "exec sleep 300"
P=$(tmux display -t cws -p '#{pane_id}')
WT_LIVE=$(claude_wt "$R" agent-live "$P")
WT_GONE=$(claude_wt "$R" agent-gone "%9999")
WT_NOPANE=$(claude_wt "$R" agent-nopane "")
WT_PANE=$("$LLMWT" create "$R" pw 2>/dev/null)
assert_equals "$(git -C "$R" config branch.lazy/agent-live.lazyLlmPane)" "$P" "setup: the live one records the sandbox pane"
assert_equals "$(owner_of "$WT_LIVE")" "claude:cws:$P" "owning pane is live: claude:<session>:<pane>"
assert_equals "$(owner_of "$WT_GONE")" "claude:orphaned" "owning pane gone: claude:orphaned"
assert_equals "$(owner_of "$WT_NOPANE")" "claude:orphaned" "no pane recorded (made outside tmux): claude:orphaned"
assert_equals "$(owner_of "$WT_PANE")" "orphaned" "pane worktrees are unchanged: orphaned"
assert_equals "$(owner_of "$R")" "" "main checkout: no owner"
tmux set-option -p -t "$P" @lazy_llm_wt "$WT_PANE"
assert_equals "$(owner_of "$WT_PANE")" "pane:cws:$P" "...and pane:<session>:<pane> once a pane runs in it"
assert_equals "$(owner_of "$WT_LIVE")" "claude:cws:$P" "a pane can own both kinds at once"
cols=$( (cd "$R" && lazy_llm_gather_worktrees) | awk -F$'\x1f' '{print NF}' | sort -u)
assert_equals "$cols" "8" "rows still have 8 columns"

# Drive the real dashboard (fzf) in a sandbox pane. Rows are rendered in
# gather_worktrees order, so a row's index there is how far down it is.
dash_wait() {  # wait until the dashboard pane shows $1
    local i
    for i in $(seq 1 100); do
        tmux capture-pane -p -t dash 2>/dev/null | grep -qF -- "$1" && return 0
        sleep 0.1
    done
    return 1
}
dash_key_on() {  # press $2 on the row whose path is $1
    local n i
    n=$( (cd "$R" && lazy_llm_gather_worktrees) | awk -F$'\x1f' -v p="$1" '$1 == p {print NR - 1}')
    for ((i = 0; i < n; i++)); do tmux send-keys -t dash Down; done
    sleep 0.3
    tmux send-keys -t dash "$2"
}

echo ""
echo "Test 14: the Worktrees tab tags Claude's rows..."
# Wide: the list column (45%, beside the preview) must fit the owner column
# and the header's messages. Detached, there's no client width to wrap to.
tmux new-session -d -s dash -c "$R" -x 400 -y 50 \
    "HOME='$HOME' TMUX_TMPDIR='$TMUX_TMPDIR' GIT_CEILING_DIRECTORIES=/tmp '$HOME/.local/bin/llm-dashboard' --tab worktrees; sleep 300"
dash_wait "lazy/agent-nopane"
screen=$(tmux capture-pane -p -t dash | strip)
assert_has "$(grep -F 'lazy/agent-live' <<< "$screen")" "⎇ claude cws" "live: ⎇ claude + the owning workspace"
assert_has "$(grep -F 'lazy/agent-gone' <<< "$screen")" "⎇ claude orphaned" "owner gone: ⎇ claude orphaned"
assert_has "$(grep -F 'lazy/pw' <<< "$screen")" "⎇ cws" "pane worktree row unchanged: ⎇ <workspace>"
assert_lacks "$(grep -F 'lazy/pw' <<< "$screen")" "claude" "...with no claude tag"
assert_has "$(sed -n '/^render_worktrees_tab()/,/^}/p' "$DASHBOARD")" "I:integrate" "header advertises I"

echo ""
echo "Test 15: I integrates and removes, and explains a refusal..."
printf 'x\n' > "$WT_LIVE/x.txt" && git -C "$WT_LIVE" add x.txt && git -C "$WT_LIVE" commit -qm "agent work"
printf 'dirty\n' >> "$WT_GONE/a.txt"
dash_key_on "$WT_LIVE" I
dash_wait "worktree removed"
screen=$(tmux capture-pane -p -t dash | strip)
assert_has "$screen" "lazy/agent-live: integrated into main; worktree removed" "success is reported in the header"
assert_equals "$(git -C "$R" log -1 --format=%s main)" "agent work" "the commit landed on main"
check "the worktree is gone" test ! -d "$WT_LIVE"
check "its branch is gone" test -z "$(git -C "$R" branch --list lazy/agent-live)"
dash_key_on "$WT_GONE" I
dash_wait "not integrated"
screen=$(tmux capture-pane -p -t dash | strip)
assert_has "$screen" "lazy/agent-gone not integrated (exit 3): the worktree has uncommitted changes" "exit 3 is explained"
assert_dir_exists "$WT_GONE" "a refused worktree stays"
commit_before=$(git -C "$WT_PANE" rev-parse HEAD)
printf 'p\n' > "$WT_PANE/p.txt" && git -C "$WT_PANE" add p.txt && git -C "$WT_PANE" commit -qm "pane work"
dash_key_on "$WT_PANE" I
dash_wait "worktree kept"
screen=$(tmux capture-pane -p -t dash | strip)
assert_has "$screen" "lazy/pw: integrated into main; worktree kept (its pane is open)" "a live pane's worktree: integrated, kept"
assert_dir_exists "$WT_PANE" "...and still there for its pane"
assert_equals "$(git -C "$R" log -1 --format=%s main)" "pane work" "...its commit landed"
check "main moved" test "$commit_before" != "$(git -C "$R" rev-parse main)"
dash_key_on "$R" I
dash_wait "(exit 2)"
assert_has "$(tmux capture-pane -p -t dash | strip)" "not integrated (exit 2): not a pane or Claude worktree" "main checkout: exit 2, explained"

echo ""
echo "Test 16: Enter and K on a Claude row: adopt into a pane, the close dialog..."
dash_key_on "$WT_NOPANE" Enter
check "Enter offers to add a pane in it" dash_wait "add an AI pane in it"
assert_has "$(tmux capture-pane -p -t dash | strip)" "Worktree lazy/agent-nopane: add an AI pane in it" "...naming the worktree"
tmux send-keys -t dash Escape
dash_wait "I:integrate" >/dev/null || dash_wait "lazy/agent-nopane"
sleep 0.5
dash_key_on "$WT_NOPANE" K
check "K runs llm-wt close's dialog" dash_wait "Closing the last pane in worktree"
assert_has "$(tmux capture-pane -p -t dash | strip)" "Closing the last pane in worktree lazy/agent-nopane" "...for that worktree"
tmux send-keys -t dash Escape
sleep 0.5
assert_dir_exists "$WT_NOPANE" "cancelled: the worktree stays"

for rc in 1 2 3 4 5 6 7; do
    check "exit $rc has a reason" test -n "$(lazy_llm_wt_integrate_reason "$rc")"
done
DASHBOARD_LOOP=$(command grep -E 'action:switch:\*\|action:switch-pane' "$DASHBOARD")
assert_has "$DASHBOARD_LOOP" "worktree-integrate:" "main loop dispatches worktree-integrate"
help_tab=$(sed -n '/^render_help_tab()/,/^}/p' "$DASHBOARD")
assert_has "$help_tab" " I      ⎇: integrate into its base" "Help tab documents I"
assert_has "$help_tab" "⎇×N" "Help tab documents ⎇×N"
assert_has "$("$DASHBOARD" --help 2>&1)" "llm-wt integrate" "usage documents I"

# ──────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────
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
