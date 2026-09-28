#!/usr/bin/env bash
# Test: per-pane worktree isolation (worktree-concurrency-mode).
# Covers the workspace-dir fix (spec §2). Isolated tmux server, throwaway
# git repos under /tmp.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="worktree-pane-unit"

REPO_ROOT="$TESTS_DIR/.."
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"

# When $TMUX is set, tmux uses ITS socket and ignores TMUX_TMPDIR: run from
# inside tmux, any bare `tmux` call here would hit the user's own server (a
# `kill-server` in the cleanup trap once killed it). Unset it for the whole
# script, and pin the sandbox socket explicitly as well.
unset TMUX TMUX_PANE

sandbox=$(mktemp -d /tmp/lazy-llm-test-wtpane-XXXXXX)
cleanup_sandbox() {
    env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$sandbox/tmux" tmux kill-server 2>/dev/null || true
    rm -rf "$sandbox"
}
trap cleanup_sandbox EXIT
mkdir -p "$sandbox/tmux" "$sandbox/home" "$sandbox/bin"

# ──────────────────────────────────────────────────────────────────────────
# 1. The workspace directory comes from @lazy_llm_dir, not the active pane
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: workspace dir ignores a focused pane whose cwd is elsewhere..."
mkdir -p "$sandbox/ws" "$sandbox/elsewhere"
output=$(TMUX_TMPDIR="$sandbox/tmux" HOME="$sandbox/home" bash <<EOF
unset TMUX TMUX_PANE
source "$LIB_FILE"
tmux -f /dev/null new-session -d -s myws -c "$sandbox/ws" -x 120 -y 30 "exec sleep 60"
tmux set-option -t myws @lazy_llm 1
tmux set-option -t myws @lazy_llm_dir "$sandbox/ws"
# A second pane in another directory, focused (the active pane)
tmux split-window -t myws -c "$sandbox/elsewhere" "exec sleep 60"
echo "active-path=\$(tmux display -t myws -p '#{pane_current_path}')"
echo "gather-dir=\$(lazy_llm_gather_sessions | cut -f2)"
echo "find-elsewhere=<\$(lazy_llm_find_session_for_path "$sandbox/elsewhere")>"
echo "find-ws=<\$(lazy_llm_find_session_for_path "$sandbox/ws")>"
echo "wsdir=\$(lazy_llm_workspace_dir myws)"
# A session from before @lazy_llm_dir: falls back to the active pane's path
tmux -f /dev/null new-session -d -s oldws -c "$sandbox/ws" "exec sleep 60"
tmux set-option -t oldws @lazy_llm 1
echo "wsdir-legacy=\$(lazy_llm_workspace_dir oldws)"
EOF
)
assert_contains "$output" "active-path=$sandbox/elsewhere" "setup: the focused pane is in the other dir"
assert_contains "$output" "gather-dir=$sandbox/ws" "gather_sessions reports @lazy_llm_dir"
assert_contains "$output" "find-elsewhere=<>" "find_session_for_path doesn't bind the workspace to the pane's cwd"
assert_contains "$output" "find-ws=<myws>" "find_session_for_path still finds the workspace by its dir"
assert_contains "$output" "wsdir=$sandbox/ws" "lazy_llm_workspace_dir reads @lazy_llm_dir"
assert_contains "$output" "wsdir-legacy=$sandbox/ws" "lazy_llm_workspace_dir falls back to the pane path"

# ──────────────────────────────────────────────────────────────────────────
# llm-wt (spec §4, §5, §7). Pure git; HOME and git identity sandboxed.
# ──────────────────────────────────────────────────────────────────────────
LLMWT="$REPO_ROOT/llm-wt-bin/.local/bin/llm-wt"
# shellcheck source=/dev/null
source "$LIB_FILE"
export HOME="$sandbox/home"
unset XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE
git config --global user.email test@test
git config --global user.name test
git config --global init.defaultBranch main
git config --global advice.detachedHead false

mk_repo() {
    local d="$1"
    mkdir -p "$d"
    git -C "$d" init -q
    printf 'one\n' > "$d/a.txt"
    printf 'readme\n' > "$d/README.md"
    printf '.env*\nconf/\n' > "$d/.gitignore"
    git -C "$d" add -A && git -C "$d" commit -qm init
}
commit_file() { printf '%s\n' "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2: $3"; }
porc() { "$LLMWT" status "$1" --porcelain | awk -F'\t' -v k="$2" '$1 == k {print $2}'; }

echo ""
echo "Test 2: lazy_llm_setup_worktree base_dir and start_point..."
R="$sandbox/r2"; mk_repo "$R"
git -C "$R" branch older
commit_file "$R" a.txt two
wt=$(cd "$R" && lazy_llm_setup_worktree feat/x "$sandbox/r2-wts" older 2>/dev/null)
assert_equals "$wt" "$sandbox/r2-wts/feat-x" "worktree goes under the given base_dir"
assert_equals "$(git -C "$wt" rev-parse HEAD)" "$(git -C "$R" rev-parse older)" "new branch starts at start_point"
wt=$(cd "$R" && lazy_llm_setup_worktree plain 2>/dev/null)
assert_equals "$wt" "$R/.worktrees/plain" "no extra args: default base, as before"

echo ""
echo "Test 3: llm-wt create with the default bootstrap list..."
R="$sandbox/r3"; mk_repo "$R"
printf 'SECRET=1\n' > "$R/.env"
wt=$("$LLMWT" create "$R" claude myws 2>/dev/null)
assert_equals "$wt" "$R/.worktrees/.panes/lazy-myws-claude-2" "worktree path"
assert_equals "$(git -C "$wt" branch --show-current)" "lazy/myws/claude-2" "branch name"
assert_equals "$(git -C "$R" config branch.lazy/myws/claude-2.lazyLlmBase)" "main" "base recorded in git config"
assert_equals "$(git -C "$R" config branch.lazy/myws/claude-2.lazyLlmPrimary)" "$R" "main directory recorded in git config"
assert_equals "$(readlink "$wt/.env")" "$R/.env" ".env is linked to the main copy"
assert_equals "$(readlink "$wt/.claude/settings.local.json")" "$R/.claude/settings.local.json" "missing literal path: dangling link"
assert_equals "$(readlink "$wt/.agents/TODO/.work-state")" "$R/.agents/TODO/.work-state" ".work-state is linked (shared)"
printf 'x' > "$wt/.claude/settings.local.json"
assert_file_exists "$R/.claude/settings.local.json" "writing through the dangling link creates the main copy"
assert_equals "$(git -C "$R" status --porcelain)" "" "main directory left clean (.gitignore untouched)"
assert_contains "$(cat "$R/.git/info/exclude")" "/.worktrees/" ".worktrees/ ignored via info/exclude"
assert_equals "$(git -C "$wt" status --porcelain)" "" "bootstrapped paths don't show as untracked in the worktree"
wt3=$("$LLMWT" create "$R" claude myws 2>/dev/null)
assert_equals "$(git -C "$wt3" branch --show-current)" "lazy/myws/claude-3" "second pane gets the next number"

echo ""
echo "Test 4: worktree-files config, copies, excludes, init hook..."
R="$sandbox/r4"; mk_repo "$R"
mkdir -p "$R/conf" "$R/.lazy-llm"
printf 'a: 1\n' > "$R/conf/local.yml"
printf 'X=1\n' > "$R/.env"
printf 'P=1\n' > "$R/.env.production"
cat > "$R/.lazy-llm/worktree-files" <<'CONF'
# per repo
.env*                      # link
copy: conf/local.yml
README.md
!.env.production
CONF
cat > "$R/.lazy-llm/worktree-init" <<'HOOK'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$PWD" "$LAZY_LLM_WORKTREE" "$LAZY_LLM_PRIMARY_DIR" "$LAZY_LLM_BASE_BRANCH" > .init-ran
HOOK
chmod +x "$R/.lazy-llm/worktree-init"
printf '.lazy-llm/\n.init-ran\n' >> "$R/.gitignore"; git -C "$R" commit -qam ignore
wt=$("$LLMWT" create "$R" codex ws 2>/dev/null)
assert_equals "$(readlink "$wt/.env")" "$R/.env" "glob link entry"
[ -e "$wt/.env.production" ] && r="present" || r="absent"
assert_equals "$r" "absent" "! excludes a match"
[ -L "$wt/conf/local.yml" ] && r="link" || r="file"
assert_equals "$r" "file" "copy: entry is a real copy"
assert_contains "$(cat "$R/.git/worktrees/lazy-ws-codex-2/lazy-llm-bootstrap")" "copy	conf/local.yml	" "copy recorded with its hash"
[ -L "$wt/README.md" ] && r="link" || r="tracked"
assert_equals "$r" "tracked" "a tracked file is never shadowed"
[ -e "$wt/.claude/settings.local.json" ] || [ -L "$wt/.claude/settings.local.json" ] && r="linked" || r="absent"
assert_equals "$r" "absent" "a repo config replaces the default list"
assert_equals "$(cat "$wt/.init-ran")" "$wt|1|$R|main" "init hook ran in the worktree with the env set"

echo ""
echo "Test 5: llm-wt status..."
assert_equals "$(porc "$wt" dirty) $(porc "$wt" untracked) $(porc "$wt" unintegrated) $(porc "$wt" copies-changed)" "0 0 0 0" "fresh worktree: nothing to lose"
printf 'changed\n' >> "$wt/a.txt"
printf 'new\n' > "$wt/new.txt"
printf 'b: 2\n' >> "$wt/conf/local.yml"
rm "$wt/.env"; printf 'X=2\n' > "$wt/.env"
assert_equals "$(porc "$wt" dirty)" "1" "tracked change counted"
assert_equals "$(porc "$wt" untracked)" "1" "untracked file counted (bootstrapped ones aren't)"
assert_equals "$(porc "$wt" copies-changed)" "2" "changed copy and replaced link counted"
assert_contains "$("$LLMWT" status "$wt" --porcelain)" "copy-changed	.env" "replaced link listed"
git -C "$wt" add a.txt new.txt && git -C "$wt" commit -qm work
assert_equals "$(porc "$wt" unintegrated)" "1" "commit not yet on base counted"

echo ""
echo "Test 6: llm-wt integrate..."
R="$sandbox/r6"; mk_repo "$R"
wt=$("$LLMWT" create "$R" claude ws 2>/dev/null)
commit_file "$wt" b.txt from-pane
"$LLMWT" integrate "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "0" "happy path exits 0"
assert_equals "$(git -C "$R" rev-parse HEAD)" "$(git -C "$wt" rev-parse HEAD)" "main directory fast-forwarded"
assert_file_exists "$R/b.txt" "the pane's file is in the main directory"

printf 'dirty\n' >> "$wt/a.txt"
"$LLMWT" integrate "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "3" "uncommitted changes -> 3"
git -C "$wt" checkout -q -- a.txt

commit_file "$R" c.txt from-main
commit_file "$wt" d.txt from-pane
"$LLMWT" integrate "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "0" "base moved: rebase, then integrate"
assert_equals "$(git -C "$R" log --format=%s -1)" "d.txt: from-pane" "rebased commit lands on top of base"

git -C "$R" checkout -qb elsewhere
commit_file "$wt" e.txt pane
"$LLMWT" integrate "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "4" "main directory on another branch -> 4"
git -C "$R" checkout -q main
"$LLMWT" integrate "$wt" >/dev/null 2>&1

commit_file "$R" a.txt main-edit
commit_file "$wt" a.txt pane-edit
"$LLMWT" integrate "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "5" "conflict -> 5"
[ -d "$(git -C "$wt" rev-parse --git-path rebase-merge)" ] && r=yes || r=no
assert_equals "$r" "yes" "the rebase is left in progress for the agent to resolve"
assert_equals "$(porc "$wt" rebasing)" "1" "status reports the rebase"
assert_equals "$(porc "$wt" branch)" "lazy/ws/claude-2" "status still knows the branch mid-rebase"
git -C "$wt" rebase --abort
git -C "$wt" reset -q --hard main

commit_file "$wt" f.txt pane
printf 'untracked in main\n' > "$R/f.txt"
before=$(git -C "$R" status --porcelain; git -C "$R" rev-parse HEAD)
"$LLMWT" integrate "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "7" "would overwrite a file in the main directory -> 7"
after=$(git -C "$R" status --porcelain; git -C "$R" rev-parse HEAD)
assert_equals "$after" "$before" "main directory untouched"
rm "$R/f.txt"

echo ""
echo "Test 7: llm-wt sync..."
commit_file "$R" g.txt main
"$LLMWT" sync "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "0" "sync exits 0"
git -C "$wt" merge-base --is-ancestor main HEAD && r=yes || r=no
assert_equals "$r" "yes" "worktree now contains base"
[ -e "$R/f.txt" ] && r=yes || r=no
assert_equals "$r" "no" "sync never touches the main directory"
printf 'x\n' >> "$wt/a.txt"
"$LLMWT" sync "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "3" "dirty worktree -> 3"
git -C "$wt" checkout -q -- a.txt

echo ""
echo "Test 8: refuses outside a pane worktree..."
"$LLMWT" status "$R" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "2" "the main directory itself -> 2"
"$LLMWT" integrate "$sandbox" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "2" "not a git repo -> 2"

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
