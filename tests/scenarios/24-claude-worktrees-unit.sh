#!/usr/bin/env bash
# Test: Claude Code's own worktrees through llm-wt (claude-subagent-worktrees,
# spec .agents/TODO/specs/claude-subagent-worktrees.md §12.1). Hook payloads
# on stdin to `llm-wt claude-hook` and the plugin shim; pure git, throwaway
# repos under /tmp. jq checks the JSON the hooks print (test-only dependency).

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="claude-worktrees-unit"

REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
LLMWT="$REPO_ROOT/llm-wt-bin/.local/bin/llm-wt"
SHIM="$REPO_ROOT/claude-plugin/hooks/worktree.sh"
CLAUDE_HOOK="$REPO_ROOT/llm-status-bin/.local/bin/llm-claude-hook"

# No tmux server here. llm-claude-hook (test 11) calls tmux: with $TMUX unset
# and a private TMUX_TMPDIR, those calls find no server instead of the user's.
unset TMUX TMUX_PANE CLAUDE_PROJECT_DIR LAZY_LLM_WORKTREE_DIR

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test"; exit 1; }

sandbox=$(mktemp -d /tmp/lazy-llm-test-claudewt-XXXXXX)
trap 'rm -rf "$sandbox"' EXIT
# Work from inside the sandbox: an empty path given to `git -C` means the
# current directory, which must never be the lazy-llm checkout.
cd "$sandbox" || exit 1
export GIT_CEILING_DIRECTORIES=/tmp
export HOME="$sandbox/home"
export TMUX_TMPDIR="$sandbox/tmux" LAZY_LLM_STATE_DIR="$sandbox/state"
mkdir -p "$HOME" "$TMUX_TMPDIR"
unset XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE
git config --global user.email test@test
git config --global user.name test
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# A repo on `feature`, one commit ahead of an origin whose default is `trunk`
# (Claude's own creation would branch from origin/trunk: spec S1).
mk_repo() {
    local d="$1"
    git init -q --bare "$d.git"
    git init -q -b trunk "$d"
    printf 'one\n' > "$d/a.txt"
    printf '.env*\n' > "$d/.gitignore"
    git -C "$d" add -A && git -C "$d" commit -qm init
    git -C "$d" remote add origin "$d.git"
    git -C "$d" push -q origin trunk
    git -C "$d.git" symbolic-ref HEAD refs/heads/trunk
    git -C "$d" fetch -q origin
    git -C "$d" remote set-head origin -a >/dev/null
    git -C "$d" checkout -q -b feature
    printf 'two\n' > "$d/b.txt"
    git -C "$d" add b.txt && git -C "$d" commit -qm feat
    printf 'SECRET=1\n' > "$d/.env"
}
commit_file() { printf '%s\n' "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2: $3"; }
cfg() { git -C "$1" config "branch.$2.$3" 2>/dev/null; }

# Payload builders. hook <json> runs llm-wt claude-hook; stdout captured,
# stderr to $sandbox/err.
hook() { printf '%s' "$1" | "$LLMWT" claude-hook 2>"$sandbox/err"; }
p_create() { printf '{"session_id":"%s","transcript_path":"/x.jsonl","cwd":"%s","prompt_id":"p","hook_event_name":"WorktreeCreate","name":"%s"}' "${3:-sess-1}" "$1" "$2"; }
p_remove() { printf '{"session_id":"sess-1","cwd":"%s","hook_event_name":"WorktreeRemove","worktree_path":"%s"}' "$1" "$1"; }
p_sstart() { printf '{"session_id":"sess-1","cwd":"%s","agent_id":"%s","agent_type":"general-purpose","hook_event_name":"SubagentStart"}' "$1" "$2"; }
p_sstop() { printf '{"session_id":"sess-1","cwd":"%s","agent_id":"%s","agent_type":"general-purpose","hook_event_name":"SubagentStop","stop_hook_active":false,"last_assistant_message":"done \\"quoted\\" name: \\"x\\""}' "$1" "$2"; }
p_post_agent() { printf '{"session_id":"sess-1","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"d","prompt":"say \\"status\\":\\"completed\\" and \\"worktreePath\\":\\"/nope\\"","isolation":"worktree"},"tool_response":{"status":"%s","agentId":"x","worktreePath":"%s"}}' "$1" "$2" "$3"; }
p_post_enter() { printf '{"session_id":"sess-1","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"EnterWorktree","tool_input":{},"tool_response":{"worktreePath":"%s","message":"Created"}}' "$1" "$2"; }
p_sessstart() { printf '{"session_id":"sess-1","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1"; }
ctx() { jq -r '.hookSpecificOutput.additionalContext' <<< "$1"; }
# Literal substring checks (assert_has matches a regex, and these
# needles carry "(s)", "{{" and paths).
assert_has() {
    if [[ "$1" == *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Looking for: '$2'"; echo "  In text: '${1:0:300}...'"; fi
}
assert_lacks() {
    if [[ "$1" != *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Unexpected: '$2'"; fi
}
is_json() { jq -e . >/dev/null 2>&1 <<< "$1" && echo ok; }
ctx_event() { jq -r '.hookSpecificOutput.hookEventName' <<< "$1"; }

# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: WorktreeCreate from a repo on feature, behind-origin trunk..."
R="$sandbox/r1"; mk_repo "$R"
out=$(hook "$(p_create "$R" agent-a1b2c3)"); rc=$?
assert_equals "$rc" "0" "create exits 0"
assert_equals "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1" "stdout is exactly one line"
assert_equals "$out" "$R/.worktrees/.claude/agent-a1b2c3" "path: .worktrees/.claude/<name>"
assert_dir_exists "$out" "the worktree directory exists"
assert_equals "$(git -C "$out" branch --show-current)" "lazy/agent-a1b2c3" "branch: lazy/<name>"
assert_equals "$(git -C "$out" rev-parse HEAD)" "$(git -C "$R" rev-parse feature)" "starts at the parent's HEAD (feature)..."
assert_lacks "$(git -C "$out" rev-parse HEAD)" "$(git -C "$R" rev-parse origin/trunk)" "...not origin's default branch"
b=lazy/agent-a1b2c3
assert_equals "$(cfg "$R" $b lazyLlmKind)" "claude" "kind=claude"
assert_equals "$(cfg "$R" $b lazyLlmName)" "agent-a1b2c3" "name recorded raw"
assert_equals "$(cfg "$R" $b lazyLlmSession)" "sess-1" "session recorded"
assert_equals "$(cfg "$R" $b lazyLlmBase)" "feature" "base = the parent's branch"
assert_equals "$(cfg "$R" $b lazyLlmPrimary)" "$R" "primary = the parent's directory"
assert_equals "$(cfg "$R" $b lazyLlmPane)" "" "no TMUX_PANE, no pane recorded"
assert_equals "$(readlink "$out/.env")" "$R/.env" ".env linked to the main copy (bootstrap)"
assert_has "$(cat "$R/.git/info/exclude")" "/.worktrees/" ".worktrees/ ignored through info/exclude"
assert_equals "$(git -C "$R" status --porcelain)" "" "main directory left clean (.gitignore untouched)"
assert_equals "$("$LLMWT" info "$out" | awk -F'\t' '$1=="base"{print $2}')" "feature" "llm-wt info sees it as an llm-wt worktree"
out_pane=$(printf '%s' "$(p_create "$R" agent-p1)" | TMUX_PANE=%42 "$LLMWT" claude-hook 2>/dev/null)
assert_equals "$(cfg "$R" lazy/agent-p1 lazyLlmPane)" "%42" "TMUX_PANE recorded as the owning pane"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: nested — the parent is itself a pane worktree..."
R="$sandbox/r2"; mk_repo "$R"
pane=$("$LLMWT" create "$R" pw 2>/dev/null)
assert_equals "$(git -C "$pane" branch --show-current)" "lazy/pw" "setup: pane worktree on lazy/pw"
out=$(hook "$(p_create "$pane" agent-n1)")
assert_equals "$out" "$R/.worktrees/.claude/agent-n1" "directory under the MAIN repo's .worktrees/.claude/, not inside the pane worktree"
assert_equals "$(cfg "$R" lazy/agent-n1 lazyLlmBase)" "lazy/pw" "base = the pane's branch"
assert_equals "$(cfg "$R" lazy/agent-n1 lazyLlmPrimary)" "$pane" "primary = the pane worktree"
assert_equals "$(git -C "$out" rev-parse HEAD)" "$(git -C "$pane" rev-parse HEAD)" "starts at the pane worktree's HEAD"
commit_file "$out" n.txt nested
"$LLMWT" integrate "$out" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "0" "integrate from the agent worktree succeeds"
assert_equals "$(git -C "$pane" log -1 --format=%s)" "n.txt: nested" "...landing on the pane's branch"
assert_lacks "$(git -C "$R" log --format=%s feature)" "nested" "...and nothing reached feature"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: name collision gets a suffix..."
R="$sandbox/r3"; mk_repo "$R"
o1=$(hook "$(p_create "$R" same)")
o2=$(hook "$(p_create "$R" same)")
assert_equals "$o1" "$R/.worktrees/.claude/same" "first: <name>"
assert_equals "$o2" "$R/.worktrees/.claude/same-2" "second: <name>-2"
assert_equals "$(git -C "$o2" branch --show-current)" "lazy/same-2" "...on lazy/<name>-2"
assert_equals "$(cfg "$R" lazy/same-2 lazyLlmName)" "same" "the raw name is still recorded"
o3=$(hook "$(p_create "$R" 'we!rd/../name')")
assert_equals "$o3" "$R/.worktrees/.claude/we-rd-.-name" "unsafe characters become -, and no '..' (invalid in a ref)"
o4=$(hook "$(p_create "$R" '')")
assert_equals "$o4" "$R/.worktrees/.claude/claude-wt" "no name: claude-wt"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: 8 parallel creates (the repo lock), 3 rounds..."
for round in 1 2 3; do
    R="$sandbox/r4-$round"; mk_repo "$R"
    for i in 1 2 3 4 5 6 7 8; do
        ( printf '%s' "$(p_create "$R" "agent-par$i")" | "$LLMWT" claude-hook > "$sandbox/par$i.out" 2> "$sandbox/par$i.err"; echo $? > "$sandbox/par$i.rc" ) &
    done
    wait
    fails=0 dirs=0 fullcfg=0
    for i in 1 2 3 4 5 6 7 8; do
        [[ "$(cat "$sandbox/par$i.rc")" == 0 ]] || { fails=$((fails + 1)); sed 's/^/    /' "$sandbox/par$i.err"; }
        [[ -d "$(cat "$sandbox/par$i.out")" ]] && dirs=$((dirs + 1))
        n=0
        for k in lazyLlmKind lazyLlmName lazyLlmSession lazyLlmBase lazyLlmPrimary; do
            [[ -n "$(cfg "$R" "lazy/agent-par$i" $k)" ]] && n=$((n + 1))
        done
        [[ $n -eq 5 ]] && fullcfg=$((fullcfg + 1))
    done
    distinct=$(sort -u "$sandbox"/par*.out | wc -l | tr -d ' ')
    excl=$(grep -cxF "/.worktrees/" "$R/.git/info/exclude")
    assert_equals "fails=$fails dirs=$dirs distinct=$distinct cfg=$fullcfg excl=$excl" \
        "fails=0 dirs=8 distinct=8 cfg=8 excl=1" "round $round: all 8 succeed, distinct, fully configured, one exclude line"
    rm -f "$sandbox"/par*
done
assert_file_not_exists "$R/.git/lazy-llm-wt.lock.d" "no lock directory left behind"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: detached HEAD..."
R="$sandbox/r5"; mk_repo "$R"
git -C "$R" checkout -q --detach HEAD
out=$(hook "$(p_create "$R" agent-d1)"); rc=$?
assert_equals "$rc" "0" "creation still succeeds"
assert_dir_exists "$out" "...with a worktree"
assert_equals "$(cfg "$R" lazy/agent-d1 lazyLlmBase)" "" "no base recorded"
assert_equals "$(cfg "$R" lazy/agent-d1 lazyLlmKind)" "claude" "kind recorded"
"$LLMWT" integrate "$out" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "2" "llm-wt integrate exits 2 (nothing to integrate into)"
assert_empty "$(hook "$(p_sstart "$out" d1)")" "SubagentStart prints nothing"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: not a repository..."
mkdir -p "$sandbox/plain"
out=$(hook "$(p_create "$sandbox/plain" agent-x)"); rc=$?
assert_equals "$rc" "1" "exit 1"
assert_empty "$out" "nothing on stdout"
assert_has "$(cat "$sandbox/err")" "not in a git repository" "stderr says why"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 7: SubagentStop cleanup..."
R="$sandbox/r7"; mk_repo "$R"
empty=$(hook "$(p_create "$R" agent-e1)")
work=$(hook "$(p_create "$R" agent-w1)")
dirty=$(hook "$(p_create "$R" agent-y1)")
other=$(hook "$(p_create "$R" agent-o1)")
commit_file "$work" w.txt work
printf 'uncommitted\n' > "$dirty/a.txt"
out=$(hook "$(p_sstop "$empty" e1)"); rc=$?
assert_equals "$rc" "0" "exit 0"
assert_empty "$out" "prints nothing (stdout would be read as a decision)"
assert_file_not_exists "$empty" "empty worktree removed"
assert_fails "git -C '$R' show-ref --verify --quiet refs/heads/lazy/agent-e1" "...and its branch"
hook "$(p_sstop "$work" w1)" >/dev/null
assert_dir_exists "$work" "a worktree with a commit is kept"
hook "$(p_sstop "$dirty" y1)" >/dev/null
assert_dir_exists "$dirty" "a worktree with only uncommitted changes is kept"
hook "$(p_sstop "$other" mismatch)" >/dev/null
assert_dir_exists "$other" "agent id mismatch: untouched"
hook "$(p_sstop "$R" e9)" >/dev/null; rc=$?
assert_equals "$rc" "0" "non-isolated subagent (cwd = main dir): exit 0"
assert_dir_exists "$other" "...and nothing removed"
# cwd elsewhere: found by scanning branches (CLAUDE_PROJECT_DIR)
printf '%s' "$(p_sstop "$sandbox" o1)" | CLAUDE_PROJECT_DIR="$R" "$LLMWT" claude-hook >/dev/null 2>&1
assert_file_not_exists "$other" "cwd elsewhere: found through CLAUDE_PROJECT_DIR and removed"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 8: WorktreeRemove..."
R="$sandbox/r8"; mk_repo "$R"
wt=$(hook "$(p_create "$R" agent-r1)")
commit_file "$wt" r.txt rem
hook "$(p_remove "$wt")" >/dev/null; rc=$?
assert_equals "$rc" "1" "unintegrated work: refused (exit 1)"
assert_dir_exists "$wt" "...and the worktree survives"
assert_has "$(cat "$sandbox/err")" "would be lost" "stderr says what would be lost"
"$LLMWT" integrate "$wt" >/dev/null 2>&1
hook "$(p_remove "$wt")" >/dev/null; rc=$?
assert_equals "$rc" "0" "after integrate: removed (exit 0)"
assert_file_not_exists "$wt" "...the worktree"
assert_fails "git -C '$R' show-ref --verify --quiet refs/heads/lazy/agent-r1" "...and its branch"
git -C "$R" worktree add -q -b plainbr "$sandbox/plainwt" 2>/dev/null
hook "$(p_remove "$sandbox/plainwt")" >/dev/null; rc=$?
assert_equals "$rc" "0" "a non-llm-wt worktree: plain removal"
assert_file_not_exists "$sandbox/plainwt" "...gone"
assert_success "git -C '$R' show-ref --verify --quiet refs/heads/plainbr" "...its branch kept"
hook "$(p_remove "$sandbox/does-not-exist")" >/dev/null; rc=$?
assert_equals "$rc" "0" "missing path: exit 0"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 9: SubagentStart guidance..."
R="$sandbox/r9"; mk_repo "$R"
wt=$(hook "$(p_create "$R" agent-g1)")
out=$(hook "$(p_sstart "$wt" g1)")
assert_equals "$(is_json "$out")" "ok" "valid JSON"
assert_equals "$(ctx_event "$out")" "SubagentStart" "hookEventName SubagentStart"
c=$(ctx "$out")
assert_has "$c" "<!-- lazy-llm:worktree-subagent -->" "worktree-subagent.md marker"
assert_has "$c" "$wt" "fills the path"
assert_has "$c" "lazy/agent-g1" "fills the branch"
assert_has "$c" "split from \`feature\`" "fills the base"
assert_lacks "$c" "{{" "no placeholder left"
assert_empty "$(hook "$(p_sstart "$wt" other)")" "agent id mismatch: nothing"
assert_empty "$(hook "$(p_sstart "$R" nonisolated)")" "a non-isolated subagent (main dir, no worktree for its id): nothing"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 10: PostToolUse Agent (the parent)..."
commit_file "$wt" g.txt one
commit_file "$wt" g2.txt two
printf 'x\n' > "$wt/a.txt"
out=$(hook "$(p_post_agent "$R" completed "$wt")")
assert_equals "$(is_json "$out")" "ok" "valid JSON"
assert_equals "$(ctx_event "$out")" "PostToolUse" "hookEventName PostToolUse"
c=$(ctx "$out")
assert_has "$c" "<!-- lazy-llm:worktree-parent -->" "worktree-parent.md marker"
assert_has "$c" "It has 2 commit(s) to integrate" "commit count"
assert_has "$c" "1 uncommitted change(s)" "uncommitted count"
assert_has "$c" "llm-wt integrate --remove $wt" "the land command"
assert_lacks "$c" "{{" "no placeholder left"
gone="$sandbox/r9/.worktrees/.claude/agent-gone"
c=$(ctx "$(hook "$(p_post_agent "$R" completed "$gone")")")
assert_has "$c" "changed nothing" "removed worktree: the 'changed nothing' line"
c=$(ctx "$(hook "$(p_post_agent "$R" async_launched "$wt")")")
assert_has "$c" "When it finishes" "not completed (background): the background line"
assert_lacks "$c" "lazy-llm:worktree-parent" "...not the full guidance"
out=$(hook '{"cwd":"/x","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"prompt":"p"},"tool_response":{"status":"completed"}}')
assert_empty "$out" "no worktreePath: nothing"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 11: SessionStart from git config (and not from llm-claude-hook)..."
R="$sandbox/r11"; mk_repo "$R"
pane=$("$LLMWT" create "$R" p11 2>/dev/null)
cw=$(hook "$(p_create "$R" sess-wt)")
c=$(ctx "$(hook "$(p_sessstart "$pane")")")
assert_has "$c" "<!-- lazy-llm:worktree-agent -->" "pane worktree: worktree-agent.md"
assert_has "$c" "branch \`lazy/p11\`" "...filled"
assert_lacks "$c" "{{" "...no placeholder left"
c=$(ctx "$(hook "$(p_sessstart "$cw")")")
assert_has "$c" "<!-- lazy-llm:worktree-agent -->" "claude worktree (claude -w): worktree-agent.md"
assert_empty "$(hook "$(p_sessstart "$R")")" "main dir: nothing"
out=$(cd "$pane" && printf '%s' "$(p_sessstart "$pane")" | TMUX_PANE=%1 LAZY_LLM_WORKTREE=1 bash "$CLAUDE_HOOK" 2>/dev/null)
assert_lacks "$out" "additionalContext" "llm-claude-hook no longer prints the guidance (no duplicate)"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 12: PostToolUse EnterWorktree..."
ew=$(hook "$(p_create "$R" wise-exploring-metcalfe)")
out=$(hook "$(p_post_enter "$ew" "$ew")")
assert_equals "$(ctx_event "$out")" "PostToolUse" "hookEventName PostToolUse"
assert_has "$(ctx "$out")" "<!-- lazy-llm:worktree-agent -->" "worktree-agent.md for the entered worktree"
assert_has "$(ctx "$out")" "$ew" "...filled with its path"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 13: llm-wt integrate --remove..."
R="$sandbox/r13"; mk_repo "$R"
wt=$(hook "$(p_create "$R" agent-l1)")
commit_file "$wt" l.txt land
"$LLMWT" integrate --remove "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "0" "lands"
assert_equals "$(git -C "$R" log -1 --format=%s)" "l.txt: land" "feature fast-forwarded"
assert_file_not_exists "$wt" "worktree removed"
assert_fails "git -C '$R' show-ref --verify --quiet refs/heads/lazy/agent-l1" "branch removed"
wt=$(hook "$(p_create "$R" agent-l2)")
commit_file "$wt" l2.txt x
printf 'dirty\n' >> "$wt/l2.txt"
"$LLMWT" integrate --remove "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "3" "uncommitted: exit 3"
assert_dir_exists "$wt" "...nothing removed"
git -C "$wt" checkout -q -- l2.txt
commit_file "$R" l2.txt conflict
"$LLMWT" integrate --remove "$wt" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "5" "conflict: exit 5"
assert_dir_exists "$wt" "...nothing removed"
git -C "$wt" rebase --abort 2>/dev/null

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 14: llm-wt list..."
R="$sandbox/r14"; mk_repo "$R"
a=$(hook "$(p_create "$R" agent-la)")
hook "$(p_create "$R" agent-lb)" >/dev/null
pane=$("$LLMWT" create "$R" p14 2>/dev/null)
nested=$(hook "$(p_create "$pane" agent-lc)")
commit_file "$a" la.txt x
list=$(cd "$R" && "$LLMWT" list --porcelain)
assert_line_count "$list" = 2 "two Claude worktrees integrate into the main dir"
assert_has "$list" "$a"$'\t'"lazy/agent-la"$'\t'"agent-la"$'\t0\t0\t1' "row: path branch name dirty untracked unintegrated"
assert_lacks "$list" "$pane" "pane worktrees aren't listed"
assert_lacks "$list" "$nested" "nor Claude worktrees of another primary"
assert_has "$("$LLMWT" list "$pane" --porcelain)" "$nested" "the pane worktree lists its own"
assert_has "$(cd "$sandbox/r1" && "$LLMWT" list)" "lazy/agent-a1b2c3" "human output names the branch"
R0="$sandbox/r14b"; mk_repo "$R0"
assert_has "$("$LLMWT" list "$R0")" "no Claude worktrees" "none: says so"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 15: .worktreeinclude is honored (copied)..."
R="$sandbox/r15"; mk_repo "$R"
mkdir -p "$R/conf"
printf 'k: v\n' > "$R/conf/local.yml"
printf 'L=1\n' > "$R/.env.local"
printf 'conf/\n' >> "$R/.gitignore"; git -C "$R" commit -qam "ignore conf"
printf '# copy these\nconf/local.yml\n/.env.local\n' > "$R/.worktreeinclude"
git -C "$R" add .worktreeinclude && git -C "$R" commit -qm wti
wt=$(hook "$(p_create "$R" agent-i1)")
assert_file_exists "$wt/conf/local.yml" "conf/local.yml is there"
assert_equals "$(readlink "$wt/conf/local.yml")" "" "...as a copy, not a link"
assert_equals "$(readlink "$wt/.env.local")" "$R/.env.local" "a path the default list links stays linked (first match wins)"
pane=$("$LLMWT" create "$R" p15 2>/dev/null)
assert_file_exists "$pane/conf/local.yml" "pane worktrees honor it too"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 16: the plugin shim..."
R="$sandbox/r16"; mk_repo "$R"
out=$(printf '%s' "$(p_create "$R" agent-s1)" | LAZY_LLM_WT_BIN="$LLMWT" bash "$SHIM" 2>/dev/null); rc=$?
assert_equals "$out" "$R/.worktrees/.claude/agent-s1" "with llm-wt: llm-wt's path"
assert_equals "$rc" "0" "...exit 0"
out=$(printf '%s' "$(p_create "$R" agent-s2)" | LAZY_LLM_WT_BIN="$sandbox/missing" bash "$SHIM" 2>"$sandbox/err"); rc=$?
assert_equals "$out" "$R/.claude/worktrees/agent-s2" "llm-wt missing: plain fallback path"
assert_equals "$(git -C "$out" branch --show-current)" "worktree-agent-s2" "...branch worktree-<name>"
assert_equals "$(git -C "$out" rev-parse HEAD)" "$(git -C "$R" rev-parse HEAD)" "...from HEAD"
assert_has "$(cat "$sandbox/err")" "not installed" "...and says why on stderr"
printf '#!/bin/sh\necho junk\nexit 1\n' > "$sandbox/failwt"; chmod +x "$sandbox/failwt"
out=$(printf '%s' "$(p_create "$R" agent-s3)" | LAZY_LLM_WT_BIN="$sandbox/failwt" bash "$SHIM" 2>"$sandbox/err"); rc=$?
assert_equals "$out" "$R/.claude/worktrees/agent-s3" "llm-wt failing: fallback, junk not passed through"
assert_has "$(cat "$sandbox/err")" "failed (exit 1)" "...stderr says llm-wt failed"
out=$(printf '%s' "$(p_create "$sandbox/plain" agent-s4)" | LAZY_LLM_WT_BIN="$sandbox/missing" bash "$SHIM" 2>/dev/null); rc=$?
assert_equals "$rc" "1" "fallback outside a repo: exit 1"
for ev in "$(p_sstart "$R" s1)" "$(p_sessstart "$R")" "$(p_remove "$sandbox/nope")"; do
    out=$(printf '%s' "$ev" | LAZY_LLM_WT_BIN="$sandbox/missing" bash "$SHIM" 2>&1); rc=$?
    assert_equals "rc=$rc out=<$out>" "rc=0 out=<>" "other event without llm-wt: silent no-op ($(jq -r .hook_event_name <<< "$ev"))"
done
wt=$(printf '%s' "$(p_create "$R" agent-s5)" | LAZY_LLM_WT_BIN="$LLMWT" bash "$SHIM" 2>/dev/null)
out=$(printf '%s' "$(p_sstart "$wt" s5)" | LAZY_LLM_WT_BIN="$LLMWT" bash "$SHIM" 2>/dev/null)
assert_equals "$(ctx_event "$out")" "SubagentStart" "shim passes other events through to llm-wt"
printf '%s' '{"hook_event_name":"Stop","cwd":"/"}' | LAZY_LLM_WT_BIN="$LLMWT" bash "$SHIM" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "0" "an event llm-wt doesn't handle: exit 0"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 17: hook exit codes never block (no exit 2)..."
R="$sandbox/r17"; mk_repo "$R"
for ev in "$(p_sstart "$sandbox/plain" z)" "$(p_sstop "$sandbox/plain" z)" "$(p_sessstart "$sandbox/plain")" \
    "$(p_post_agent "$sandbox/plain" completed "$sandbox/plain")" "$(p_post_enter "$sandbox/plain" "$sandbox/plain")"; do
    hook "$ev" >/dev/null; rc=$?
    assert_equals "$rc" "0" "$(jq -r '.hook_event_name + " " + (.tool_name // "")' <<< "$ev")outside any repo: exit 0"
done
# A pane worktree passed to SubagentStop's scan must never be removed
pane=$("$LLMWT" create "$R" p17 2>/dev/null)
git -C "$R" config branch.lazy/p17.lazyLlmName agent-zz
hook "$(p_sstop "$pane" zz)" >/dev/null
assert_dir_exists "$pane" "an empty PANE worktree with a matching name isn't removed by SubagentStop"

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
