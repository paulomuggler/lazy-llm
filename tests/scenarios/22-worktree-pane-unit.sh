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
# Work from inside the sandbox: `git -C "$var"` with an empty $var means the
# CURRENT directory, and one failed step once left a path empty and ran
# `git reset --hard` in the lazy-llm checkout itself. From here, an empty
# path hits a scratch dir that isn't a repository.
cd "$sandbox" || exit 1
export GIT_CEILING_DIRECTORIES=/tmp
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
assert_equals "$("$LLMWT" default-name "$R")" "r3-wt-1" "default name: <repo>-wt-<n>"
wt=$("$LLMWT" create "$R" 2>/dev/null)
assert_equals "$wt" "$R/.worktrees/.panes/r3-wt-1" "worktree path is .panes/<name>"
assert_equals "$(git -C "$wt" branch --show-current)" "lazy/r3-wt-1" "branch is lazy/<name>"
assert_equals "$(git -C "$R" config branch.lazy/r3-wt-1.lazyLlmBase)" "main" "base recorded in git config"
assert_equals "$(git -C "$R" config branch.lazy/r3-wt-1.lazyLlmPrimary)" "$R" "main directory recorded in git config"
assert_equals "$(readlink "$wt/.env")" "$R/.env" ".env is linked to the main copy"
assert_equals "$(readlink "$wt/.claude/settings.local.json")" "$R/.claude/settings.local.json" "missing literal path: dangling link"
assert_equals "$(readlink "$wt/.agents/TODO/.work-state")" "$R/.agents/TODO/.work-state" ".work-state is linked (shared)"
printf 'x' > "$wt/.claude/settings.local.json"
assert_file_exists "$R/.claude/settings.local.json" "writing through the dangling link creates the main copy"
assert_equals "$(git -C "$R" status --porcelain)" "" "main directory left clean (.gitignore untouched)"
assert_contains "$(cat "$R/.git/info/exclude")" "/.worktrees/" ".worktrees/ ignored via info/exclude"
assert_equals "$(git -C "$wt" status --porcelain)" "" "bootstrapped paths don't show as untracked in the worktree"
assert_equals "$(porc "$wt" ignored-extra)" "0" "...nor as extra ignored paths (their parent dirs included)"
wt3=$("$LLMWT" create "$R" 2>/dev/null)
assert_equals "$(git -C "$wt3" branch --show-current)" "lazy/r3-wt-2" "the next default takes the next number"
wtn=$("$LLMWT" create "$R" "auth refactor!" 2>/dev/null)
assert_equals "$wtn" "$R/.worktrees/.panes/auth-refactor-" "a given name is made safe, and names the directory"
assert_equals "$(git -C "$wtn" branch --show-current)" "lazy/auth-refactor-" "...and the branch"
"$LLMWT" create "$R" "auth-refactor-" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "1" "a taken name is refused, not suffixed"

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
wt=$("$LLMWT" create "$R" 2>/dev/null)
assert_equals "$(readlink "$wt/.env")" "$R/.env" "glob link entry"
[ -e "$wt/.env.production" ] && r="present" || r="absent"
assert_equals "$r" "absent" "! excludes a match"
[ -L "$wt/conf/local.yml" ] && r="link" || r="file"
assert_equals "$r" "file" "copy: entry is a real copy"
assert_contains "$(cat "$R/.git/worktrees/r4-wt-1/lazy-llm-bootstrap")" "copy	conf/local.yml	" "copy recorded with its hash"
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
wt=$("$LLMWT" create "$R" 2>/dev/null)
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
assert_equals "$(porc "$wt" branch)" "lazy/r6-wt-1" "status still knows the branch mid-rebase"
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
echo "Test 9: git segment for the AI pane border (spec §12.1)..."
seg() { lazy_llm_git_segment "$1" T D | sed 's/#\[[^]]*\]//g'; }
R="$sandbox/r9"; mk_repo "$R"
sha() { git -C "$1" rev-parse --short=7 HEAD; }
assert_equals "$(seg "$R")" "main $(sha "$R") local" "main tree, no upstream"
git clone -q "$R" "$sandbox/r9c"
C="$sandbox/r9c"
assert_equals "$(seg "$C")" "main $(sha "$C") origin" "upstream in sync: just the remote"
commit_file "$C" x.txt 1; commit_file "$C" y.txt 2
commit_file "$R" z.txt 3; git -C "$C" fetch -q
printf 'd\n' >> "$C/a.txt"
assert_equals "$(seg "$C")" "main* $(sha "$C") origin ↑2↓1" "dirty, ahead and behind"
git -C "$C" checkout -q -- a.txt
git -C "$C" checkout -qb other
git -C "$C" branch -q --set-upstream-to=origin/main
assert_equals "$(seg "$C")" "other $(sha "$C") origin/main ↑2↓1" "upstream with another name is spelled out"
wt=$("$LLMWT" create "$R" 2>/dev/null)
commit_file "$wt" p.txt 1; commit_file "$R" q.txt 2
assert_equals "$(seg "$wt")" "⎇ r9-wt-1→main $(sha "$wt") ↑1↓1" "pane worktree: counts against base"
twt=$(cd "$R" && lazy_llm_setup_worktree feat/x 2>/dev/null)
assert_equals "$(seg "$twt")" "⎇ feat-x feat/x $(sha "$twt") local" "task worktree: dir name, then branch"
git -C "$C" checkout -q --detach
assert_equals "$(seg "$C")" "(detached) $(sha "$C")" "detached HEAD"
assert_equals "$(seg "$sandbox")" "" "not a git repo: nothing"

echo ""
echo "Test 10: llm-pane-border shows the segment, and @lazy_llm_border_git off drops it..."
ln -sf "$LIB_FILE" "$sandbox/bin/lazy-llm-lib.sh"
ln -sf "$REPO_ROOT/lazy-llm-bin/.local/bin/llm-pane-border" "$sandbox/bin/llm-pane-border"
output=$(TMUX_TMPDIR="$sandbox/tmux" bash <<EOF
unset TMUX TMUX_PANE
tmux -f /dev/null new-session -d -s bws -c "$wt" -x 200 -y 20 "exec sleep 60"
P=\$(tmux display -t bws -p '#{pane_id}')
tmux set-option -t bws @lazy_llm 1
tmux set-option -w -t bws @AI_PANES "\$P"
tmux set-option -w -t bws @AI_TOOLS claude
echo "on=<\$("$sandbox/bin/llm-pane-border" "\$P" claude | sed 's/#\[[^]]*\]//g')>"
tmux set-option -g @lazy_llm_border_git off
echo "off=<\$("$sandbox/bin/llm-pane-border" "\$P" claude | sed 's/#\[[^]]*\]//g')>"
tmux kill-server 2>/dev/null
EOF
)
assert_contains "$output" "│ ⎇ r9-wt-1→main $(sha "$wt") ↑1↓1 >" "border ends with the git segment"
assert_not_contains "$(printf '%s\n' "$output" | grep '^off=')" "⎇" "off switch drops it"

echo ""
echo "Test 11: llm-add --isolate / --worktree, and plain adds stay in the main directory..."
# The stowed ~/.local/bin layout, in the sandbox HOME. `-t cat` stands in
# for a real tool: nothing is ever launched.
mkdir -p "$HOME/.local/bin"
for f in llm-send-bin/.local/bin/lazy-llm-lib.sh llm-add-bin/.local/bin/llm-add \
         llm-cycle-bin/.local/bin/llm-cycle llm-wt-bin/.local/bin/llm-wt; do
    ln -sf "$REPO_ROOT/$f" "$HOME/.local/bin/$(basename "$f")"
done
R="$sandbox/r11"; mk_repo "$R"
output=$(TMUX_TMPDIR="$sandbox/tmux" bash <<EOF
unset TMUX
tmux -f /dev/null new-session -d -s aws -c "$R" -x 200 -y 50 "exec sleep 120"
P=\$(tmux display -t aws -p '#{pane_id}')
tmux set-option -t aws @lazy_llm 1
tmux set-option -t aws @lazy_llm_dir "$R"
tmux set-option -w -t aws @AI_PANE_ID "\$P"
tmux set-option -w -t aws @AI_PANES "\$P"
tmux set-option -w -t aws @AI_TOOLS cat
tmux set-option -w -t aws @AI_PANE_IDX 0
# llm-add runs from the prompt pane, which (unlike an AI pane) never moves
# into the hold window.
Q=\$(tmux split-window -t "\$P" -c "$R" -P -F '#{pane_id}' "exec sleep 120")
tmux set-option -w -t aws @PROMPT_PANE_ID "\$Q"
export TMUX_PANE="\$Q"
"$HOME/.local/bin/llm-add" -t cat -i >/dev/null 2>&1; echo "isolate-rc=\$?"
read -ra panes <<< "\$(tmux show-option -wqv -t aws @AI_PANES)"
N=\${panes[1]}
sleep 0.5
echo "npanes=\${#panes[@]}"
echo "wt-opt=\$(tmux show-option -pqv -t "\$N" @lazy_llm_wt)"
echo "wt-cwd=\$(tmux display -t "\$N" -p '#{pane_current_path}')"
echo "typed=\$(tmux capture-pane -p -t "\$N" | grep -m1 LAZY_LLM_WORKTREE)"
echo "label=\$(tmux show-option -wqv -t aws @AI_PANE_NAMES)"
# With the isolated pane focused (the visible AI pane), add plain and joined panes
tmux select-pane -t "\$N"
"$HOME/.local/bin/llm-add" -t cat >/dev/null 2>&1; echo "plain-rc=\$?"
read -ra panes <<< "\$(tmux show-option -wqv -t aws @AI_PANES)"
echo "plain-cwd=\$(tmux display -t "\${panes[2]}" -p '#{pane_current_path}')"
echo "plain-opt=<\$(tmux show-option -pqv -t "\${panes[2]}" @lazy_llm_wt)>"
WT=\$(tmux show-option -pqv -t "\$N" @lazy_llm_wt)
"$HOME/.local/bin/llm-add" -t cat -w "\$WT" >/dev/null 2>&1; echo "join-rc=\$?"
read -ra panes <<< "\$(tmux show-option -wqv -t aws @AI_PANES)"
echo "join-opt=\$(tmux show-option -pqv -t "\${panes[3]}" @lazy_llm_wt)"
echo "join-cwd=\$(tmux display -t "\${panes[3]}" -p '#{pane_current_path}')"
"$HOME/.local/bin/llm-add" -t cat -w "$R" >/dev/null 2>&1; echo "join-bad-rc=\$?"
"$HOME/.local/bin/llm-add" -t cat -i -w "\$WT" >/dev/null 2>&1; echo "both-rc=\$?"
"$HOME/.local/bin/llm-add" -t cat -i -n my-task >/dev/null 2>&1; echo "named-rc=\$?"
read -ra panes <<< "\$(tmux show-option -wqv -t aws @AI_PANES)"
echo "named-wt=\$(tmux show-option -pqv -t "\${panes[-1]}" @lazy_llm_wt)"
echo "named-labels=\$(tmux show-option -wqv -t aws @AI_PANE_NAMES)"
"$HOME/.local/bin/llm-add" -t cat -n x >/dev/null 2>&1; echo "name-alone-rc=\$?"
tmux kill-server 2>/dev/null
EOF
)
WT="$R/.worktrees/.panes/r11-wt-1"
assert_contains "$output" "isolate-rc=0" "llm-add -i succeeds"
assert_contains "$output" "npanes=2" "the pane is added to the workspace"
assert_contains "$output" "wt-opt=$WT" "the pane is tagged with its worktree"
assert_contains "$output" "wt-cwd=$WT" "the pane starts in its worktree"
assert_contains "$output" "LAZY_LLM_WORKTREE=1 LAZY_LLM_PRIMARY_DIR=$R LAZY_LLM_BASE_BRANCH=main cat" "the tool is launched with the worktree env"
assert_contains "$output" "plain-cwd=$R" "a plain add with the isolated pane focused stays in the main directory"
assert_contains "$output" "plain-opt=<>" "a plain pane isn't tagged"
assert_contains "$output" "join-rc=0" "llm-add -w succeeds"
assert_contains "$output" "join-opt=$WT" "the joined pane shares the worktree"
assert_contains "$output" "join-cwd=$WT" "the joined pane starts there"
assert_equals "$(git -C "$R" branch --list 'lazy/*' --format='%(refname:short)' | tr '\n' ' ')" "lazy/my-task lazy/r11-wt-1 " "joining creates no branch; -i -n makes lazy/<name>"
assert_contains "$output" "join-bad-rc=1" "-w on a non-pane-worktree is refused"
assert_contains "$output" "both-rc=1" "-i and -w together are refused"
assert_contains "$output" "label=_ r11-wt-1" "the isolated pane is labelled with its worktree's name"
assert_contains "$output" "named-rc=0" "llm-add -i -n <name> succeeds"
assert_contains "$output" "named-wt=$R/.worktrees/.panes/my-task" "...in a worktree of that name"
assert_contains "$output" "named-labels=_ r11-wt-1 _ _ my-task" "...labelled with it"
assert_contains "$output" "name-alone-rc=1" "-n without -i is refused"

echo ""
echo "Test 12: close flow — preselection, remove, last-pane rule (spec §8)..."
R="$sandbox/r12"; mk_repo "$R"
wt=$("$LLMWT" create "$R" 2>/dev/null)
assert_equals "$("$LLMWT" close "$wt" --default)" "remove" "nothing to lose: Remove is preselected"
commit_file "$wt" w.txt 1
assert_equals "$("$LLMWT" close "$wt" --default)" "keep" "unintegrated work: Keep is preselected"
# setsid: no controlling terminal, so nothing can prompt even when the suite
# runs from a real terminal.
assert_equals "$(setsid -w "$LLMWT" close "$wt" 2>/dev/null)" "keep" "no terminal to ask on: keep"
"$LLMWT" remove "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "1" "remove refuses when work would be lost"
[ -d "$wt" ] && r="kept" || r="gone"
assert_equals "$r" "kept" "...and leaves the worktree alone"

HOME_BIN="$HOME/.local/bin"
ln -sf "$REPO_ROOT/llm-remove-bin/.local/bin/llm-remove" "$HOME_BIN/llm-remove"
R="$sandbox/r12b"; mk_repo "$R"
output=$(TMUX_TMPDIR="$sandbox/tmux" bash <<EOF
unset TMUX
tmux -f /dev/null new-session -d -s rws -c "$R" -x 200 -y 50 "exec sleep 120"
P=\$(tmux display -t rws -p '#{pane_id}')
tmux set-option -t rws @lazy_llm 1
tmux set-option -t rws @lazy_llm_dir "$R"
tmux set-option -w -t rws @AI_PANE_ID "\$P"
tmux set-option -w -t rws @AI_PANES "\$P"
tmux set-option -w -t rws @AI_TOOLS cat
tmux set-option -w -t rws @AI_PANE_IDX 0
Q=\$(tmux split-window -t "\$P" -c "$R" -P -F '#{pane_id}' "exec sleep 120")
export TMUX_PANE="\$Q"
"$HOME_BIN/llm-add" -t cat -i >/dev/null 2>&1
read -ra panes <<< "\$(tmux show-option -wqv -t rws @AI_PANES)"
WT=\$(tmux show-option -pqv -t "\${panes[1]}" @lazy_llm_wt)
echo "wt=\$WT"
"$HOME_BIN/llm-add" -t cat -w "\$WT" >/dev/null 2>&1
echo "first=\$(setsid -w "$HOME_BIN/llm-remove" -f 1 2>&1 | tr '\n' ' ')"
[ -d "\$WT" ] && echo "after-first=kept" || echo "after-first=gone"
echo "last=\$(setsid -w "$HOME_BIN/llm-remove" -f 1 2>&1 | tr '\n' ' ')"
[ -d "\$WT" ] && echo "after-last=kept" || echo "after-last=gone"
# Remove with a pane of the worktree focused: the workspace must survive
# (spec §2 end to end).
"$HOME_BIN/llm-add" -t cat -i >/dev/null 2>&1
read -ra panes <<< "\$(tmux show-option -wqv -t rws @AI_PANES)"
N=\${panes[-1]}
tmux select-pane -t "\$N"
WT2=\$(tmux show-option -pqv -t "\$N" @lazy_llm_wt)
"$HOME_BIN/llm-wt" remove "\$WT2" --force >/dev/null 2>&1; echo "force-rc=\$?"
tmux has-session -t rws 2>/dev/null && echo "session=alive" || echo "session=killed"
[ -d "\$WT2" ] && echo "wt2=kept" || echo "wt2=gone"
echo "branches=\$(git -C "$R" branch --list 'lazy/*' --format='%(refname:short)' | tr '\n' ' ')"
tmux kill-server 2>/dev/null
EOF
)
assert_not_contains "$(printf '%s\n' "$output" | grep '^first=')" "worktree" "closing a pane that shares its worktree doesn't ask about it"
assert_contains "$output" "after-first=kept" "...and the worktree stays"
assert_contains "$output" "Kept worktree" "last pane, no terminal: the worktree is kept and it says so"
assert_contains "$output" "after-last=kept" "...and it's still there"
assert_contains "$output" "force-rc=0" "llm-wt remove --force succeeds"
assert_contains "$output" "session=alive" "removing a worktree whose pane is focused leaves the workspace alive"
assert_contains "$output" "wt2=gone" "the worktree is gone"
assert_contains "$output" "branches=lazy/r12b-wt-1 " "its branch is deleted; the kept one remains"

echo ""
echo "Test 13: dashboard tree marker, worktree owners (spec §9, §12.2)..."
ln -sf "$REPO_ROOT/lazy-llm-bin/.local/bin/llm-dashboard" "$HOME_BIN/llm-dashboard"
R="$sandbox/r13"; mk_repo "$R"
(cd "$R" && lazy_llm_setup_worktree task-x >/dev/null 2>&1)
output=$(TMUX_TMPDIR="$sandbox/tmux" bash <<EOF
unset TMUX
source "$LIB_FILE"
tmux -f /dev/null new-session -d -s dws -c "$R" -x 200 -y 50 "exec sleep 120"
P=\$(tmux display -t dws -p '#{pane_id}')
tmux set-option -t dws @lazy_llm 1
tmux set-option -t dws @lazy_llm_dir "$R"
tmux set-option -w -t dws @AI_PANE_ID "\$P"
tmux set-option -w -t dws @AI_PANES "\$P"
tmux set-option -w -t dws @AI_TOOLS cat
tmux set-option -w -t dws @AI_PANE_IDX 0
Q=\$(tmux split-window -t "\$P" -c "$R" -P -F '#{pane_id}' "exec sleep 120")
export TMUX_PANE="\$Q"
"$HOME_BIN/llm-add" -t cat -i >/dev/null 2>&1
read -ra panes <<< "\$(tmux show-option -wqv -t dws @AI_PANES)"
N=\${panes[1]}
WT=\$(tmux show-option -pqv -t "\$N" @lazy_llm_wt)
echo "rows=\$("$HOME_BIN/llm-dashboard" --emit-rows dws 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep "pane:dws:1:" | cut -f2)"
echo "wt-panes=\$(lazy_llm_wt_panes "\$WT" | tr '\t\n' '| ')"
g() { (cd "$R" && lazy_llm_gather_worktrees) | awk -F\$'\x1f' -v p="\$1" '\$1 == p {print \$8}'; }
echo "owner-live=\$(g "\$WT")"
echo "owner-task=<\$(g "$R/.worktrees/task-x")>"
echo "owner-main=<\$(g "$R")>"
echo "pid=\$N"
tmux kill-pane -t "\$N"
echo "owner-orphan=\$(g "\$WT")"
tmux kill-server 2>/dev/null
EOF
)
N=$(printf '%s\n' "$output" | sed -n 's/^pid=//p')
assert_contains "$output" "rows=    ↳ r13-wt-1" "tree row for the isolated pane"
assert_contains "$(printf '%s\n' "$output" | grep '^rows=')" "r13-wt-1" "...labelled with its worktree's name"
assert_contains "$(printf '%s\n' "$output" | grep '^rows=')" "⎇" "...and carries the ⎇ marker"
assert_contains "$output" "wt-panes=dws|$N " "lazy_llm_wt_panes finds the tagged pane"
assert_contains "$output" "owner-live=pane:dws:$N" "gather_worktrees: owner is the live pane"
assert_contains "$output" "owner-task=<>" "task worktree has no owner"
assert_contains "$output" "owner-main=<>" "main checkout has no owner"
assert_contains "$output" "owner-orphan=orphaned" "pane gone: orphaned"

echo ""
echo "Test 14: nvim — counterpart toggle, reference paths, buffer marks (spec §10)..."
R="$sandbox/r14"; mk_repo "$R"
mkdir -p "$R/src"; printf 'l1\nl2\nl3\nl4\n' > "$R/src/x.lua"
git -C "$R" add src && git -C "$R" commit -qm src
wt=$("$LLMWT" create "$R" 2>/dev/null)
printf 'l1\nl2\nl3\nl4\npane-only\n' > "$wt/src/x.lua"
cat > "$sandbox/nvim-test.lua" <<LUA
local out = {}
local function log(k, v) table.insert(out, k .. "=" .. tostring(v)) end
local M = require("lazy_llm_worktree")
vim.cmd("edit src/x.lua")
log("ref-main", M.reference_path(0))
M.visible_pane_worktree = function() return "$wt" end
vim.api.nvim_win_set_cursor(0, { 3, 0 })
M.toggle()
log("after-toggle", vim.api.nvim_buf_get_name(0))
log("cursor", vim.api.nvim_win_get_cursor(0)[1])
log("ref-wt", M.reference_path(0))
M.mark(0)
log("mark", vim.b.lazy_llm_wt)
log("lines", vim.api.nvim_buf_line_count(0))
M.toggle()
log("back", vim.api.nvim_buf_get_name(0))
M.mark(0)
log("mark-main", vim.b.lazy_llm_wt)
vim.fn.writefile(out, "$sandbox/nvim-out.txt")
vim.cmd("qa!")
LUA
(cd "$R" && nvim --headless --clean \
    --cmd "set rtp^=$REPO_ROOT/nvim-llm-send-plugin/.config/nvim" \
    -c "luafile $sandbox/nvim-test.lua" >/dev/null 2>&1)
nv=$(cat "$sandbox/nvim-out.txt" 2>/dev/null)
assert_contains "$nv" "ref-main=src/x.lua" "a main-directory buffer's reference is unchanged"
assert_contains "$nv" "after-toggle=$wt/src/x.lua" "toggle opens the visible pane's worktree copy"
assert_contains "$nv" "cursor=3" "...on the same line"
assert_contains "$nv" "ref-wt=src/x.lua" "a worktree buffer's reference is the repo-relative path the agent sees"
assert_contains "$nv" "mark=lazy/r14-wt-1" "worktree buffers are marked with their branch"
assert_contains "$nv" "lines=5" "the worktree copy is its own file (editable)"
assert_contains "$nv" "back=$R/src/x.lua" "toggle again goes back to the main copy"
assert_contains "$nv" "mark-main=nil" "main buffers aren't marked"

echo ""
echo "Test 15: SessionStart hook injects the worktree guidance only in isolated panes (spec §6)..."
ln -sf "$REPO_ROOT/llm-status-bin/.local/bin/llm-claude-hook" "$HOME_BIN/llm-claude-hook"
mkdir -p "$HOME/.local/share"
ln -sfn "$REPO_ROOT/llm-status-bin/.local/share/lazy-llm" "$HOME/.local/share/lazy-llm"
R="$sandbox/r15"; mk_repo "$R"
wt=$("$LLMWT" create "$R" 2>/dev/null)
payload='{"hook_event_name":"SessionStart","source":"startup","session_id":"s1","model":"claude-opus-5-5"}'
output=$(TMUX_TMPDIR="$sandbox/tmux" bash <<EOF
unset TMUX
tmux -f /dev/null new-session -d -s hws -c "$wt" "exec sleep 60"
export TMUX_PANE=\$(tmux display -t hws -p '#{pane_id}')
cd "$wt"
echo "iso=\$(printf '%s' '$payload' | LAZY_LLM_WORKTREE=1 LAZY_LLM_PRIMARY_DIR="$R" LAZY_LLM_BASE_BRANCH=main "$HOME_BIN/llm-claude-hook")"
echo "shared=<\$(printf '%s' '$payload' | "$HOME_BIN/llm-claude-hook")>"
tmux kill-server 2>/dev/null
EOF
)
json=$(printf '%s\n' "$output" | sed -n 's/^iso=//p')
ctx=$(printf '%s' "$json" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
assert_equals "$(printf '%s' "$json" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "SessionStart" "valid hook JSON"
assert_contains "$ctx" "own worktree, \`$wt\`, on branch \`lazy/r15-wt-1\`" "guidance names the worktree and branch"
assert_contains "$ctx" "split from \`main\` in the main directory \`$R\`" "...and the base branch and main directory"
assert_contains "$ctx" "| 7 | The main directory has uncommitted changes" "...and carries the integrate exit codes"
[[ "$ctx" == *"{{"* ]] && r="left" || r="none"
assert_equals "$r" "none" "no placeholder left"
assert_contains "$output" "shared=<>" "a shared pane's session gets nothing"

echo ""
echo "Test 16: many adds fit the hold window; a failed add changes nothing..."
R="$sandbox/r16"; mk_repo "$R"
output=$(TMUX_TMPDIR="$sandbox/tmux" bash <<EOF
unset TMUX
tmux -f /dev/null new-session -d -s mws -c "$R" -x 120 -y 40 "exec sleep 120"
P=\$(tmux display -t mws -p '#{pane_id}')
tmux set-option -t mws @lazy_llm 1
tmux set-option -t mws @lazy_llm_dir "$R"
tmux set-option -w -t mws @AI_PANE_ID "\$P"
tmux set-option -w -t mws @AI_PANES "\$P"
tmux set-option -w -t mws @AI_TOOLS cat
tmux set-option -w -t mws @AI_PANE_IDX 0
Q=\$(tmux split-window -t "\$P" -c "$R" -P -F '#{pane_id}' "exec sleep 120")
export TMUX_PANE="\$Q"
fails=0
for i in \$(seq 1 14); do "$HOME_BIN/llm-add" -t cat >/dev/null 2>&1 || fails=\$((fails + 1)); done
read -ra panes <<< "\$(tmux show-option -wqv -t mws @AI_PANES)"
read -ra tools <<< "\$(tmux show-option -wqv -t mws @AI_TOOLS)"
echo "fails=\$fails panes=\${#panes[@]} tools=\${#tools[@]}"
# Force a failure: a hold window too small to split.
H=\$(tmux show-option -wqv -t mws @AI_HOLD_WIN)
tmux set-option -w -t "\$H" window-size manual
tmux resize-window -t "\$H" -x 2 -y 2
tmux kill-pane -a -t "\$(tmux list-panes -t "\$H" -F '#{pane_id}' | head -1)"
tmux set-option -w -t mws @AI_PANES "\$P"
tmux set-option -w -t mws @AI_TOOLS cat
tmux select-pane -t "\$Q"
before="\$(tmux show-option -wqv -t mws @AI_PANES)|\$(tmux show-option -wqv -t mws @AI_TOOLS)"
for i in 1 2 3 4 5 6; do "$HOME_BIN/llm-add" -t cat -i >/dev/null 2>&1; done; echo "rc=\$?"
after="\$(tmux show-option -wqv -t mws @AI_PANES)|\$(tmux show-option -wqv -t mws @AI_TOOLS)"
[ "\$before" = "\$after" ] && echo "lists=unchanged" || echo "lists=changed <\$before> <\$after>"
echo "typed-into-focus=\$(tmux capture-pane -p -t "\$Q" | grep -c 'cat' || true)"
echo "focus-tag=<\$(tmux show-option -pqv -t "\$Q" @lazy_llm_wt)>"
tmux kill-server 2>/dev/null
EOF
)
assert_contains "$output" "fails=0 panes=15 tools=15" "14 adds in a small window all succeed, lists aligned"
assert_contains "$output" "rc=1" "an add that can't get a pane fails"
assert_contains "$output" "lists=unchanged" "...leaving the pane and tool lists alone"
assert_contains "$output" "typed-into-focus=0" "...typing nothing into the focused pane"
assert_contains "$output" "focus-tag=<>" "...and tagging no other pane"

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
