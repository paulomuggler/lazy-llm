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

# No tmux server here (test 1 starts a private one briefly, and stops it).
# llm-claude-hook (test 11) calls tmux: with $TMUX unset and a private
# TMUX_TMPDIR, those calls find no server instead of the user's.
unset TMUX TMUX_PANE CLAUDE_PROJECT_DIR LAZY_LLM_WORKTREE_DIR

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test"; exit 1; }

sandbox=$(mktemp -d /tmp/lazy-llm-test-claudewt-XXXXXX)
trap 'env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$sandbox/tmux" tmux kill-server 2>/dev/null; rm -rf "$sandbox"' EXIT
# Work from inside the sandbox: an empty path given to `git -C` means the
# current directory, which must never be the lazy-llm checkout.
cd "$sandbox" || exit 1
export GIT_CEILING_DIRECTORIES=/tmp
export HOME="$sandbox/home"
export TMUX_TMPDIR="$sandbox/tmux" LAZY_LLM_STATE_DIR="$sandbox/state"
mkdir -p "$HOME" "$TMUX_TMPDIR"
unset XDG_CONFIG_HOME XDG_STATE_HOME GIT_DIR GIT_WORK_TREE
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
assert_equals "$(cfg "$R" lazy/agent-p1 lazyLlmPaneServer)" "" "no tmux server to ask: no server start time recorded"
assert_equals "$(cfg "$R" $b lazyLlmPaneServer)" "" "no TMUX_PANE: no server start time either"
# With a tmux server (a private one, stopped right after: later tests expect
# none), its #{start_time} is recorded next to the pane: pane ids restart at
# %0 with each server, so the id alone can't tell this server's pane from a
# later one's.
tmux -f /dev/null new-session -d -s t24 "exec sleep 300"
tp=$(tmux display -t t24 -p '#{pane_id}')
started=$(tmux display -t t24 -p '#{start_time}')
# As in a real pane: tmux sets both TMUX (socket,pid,session) and TMUX_PANE.
tenv=$(tmux display -t t24 -p '#{socket_path},#{pid},0')
printf '%s' "$(p_create "$R" agent-p2)" | TMUX="$tenv" TMUX_PANE="$tp" "$LLMWT" claude-hook >/dev/null 2>&1
# TMUX_PANE without TMUX (not a real pane): the server isn't asked, even
# though the default socket would reach one here.
printf '%s' "$(p_create "$R" agent-p3)" | TMUX_PANE="$tp" "$LLMWT" claude-hook >/dev/null 2>&1
env -u TMUX -u TMUX_PANE tmux kill-server 2>/dev/null
assert_equals "$(cfg "$R" lazy/agent-p3 lazyLlmPaneServer)" "" "TMUX_PANE without TMUX: no server asked, none recorded"
assert_equals "$(cfg "$R" lazy/agent-p2 lazyLlmPane)" "$tp" "with a server: the pane recorded"
assert_equals "$([[ "$started" =~ ^[0-9]+$ ]] && echo number)" "number" "setup: the sandbox server reported a start time"
assert_equals "$(cfg "$R" lazy/agent-p2 lazyLlmPaneServer)" "$started" "...and the server's #{start_time} as lazyLlmPaneServer"

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
assert_has "$c" "land this with llm-wt integrate --remove $wt" "asks for the land line in the final message (reaches a background parent)"
assert_empty "$(hook "$(p_sstart "$wt" other)")" "agent id mismatch: nothing"
assert_empty "$(hook "$(p_sstart "$R" nonisolated)")" "a non-isolated subagent (main dir, no worktree for its id): nothing"
RA="$sandbox/r9&amp"; mk_repo "$RA"
wa=$(hook "$(p_create "$RA" agent-amp)")
assert_has "$(ctx "$(hook "$(p_sstart "$wa" amp)")")" "You run in \`$wa\`" "a path with & is filled verbatim (bash 5.2 patsub)"

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
assert_has "$c" "worked in its own worktree" "completed: the finished intro"
assert_has "$c" "1 uncommitted change(s)" "uncommitted count"
assert_has "$c" "llm-wt integrate --remove $wt" "the land command"
assert_lacks "$c" "{{" "no placeholder left"
gone="$sandbox/r9/.worktrees/.claude/agent-gone"
c=$(ctx "$(hook "$(p_post_agent "$R" completed "$gone")")")
assert_has "$c" "changed nothing" "removed worktree: the 'changed nothing' line"
c=$(ctx "$(hook "$(p_post_agent "$R" async_launched "$wt")")")
assert_has "$c" "running in the background" "async_launched: the background intro"
assert_has "$c" "llm-wt integrate --remove $wt" "...with the land procedure"
assert_lacks "$c" "commit(s) to integrate" "...and no counts (it hasn't finished)"
# The real async launch payload (spec §2, S11): agentId, no worktreePath.
async=$(printf '{"session_id":"sess-1","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"d","prompt":"p","run_in_background":true,"isolation":"worktree"},"tool_response":{"isAsync":true,"status":"async_launched","agentId":"g1","description":"d","outputFile":"/tmp/x.output"}}' "$R")
c=$(ctx "$(hook "$async")")
assert_has "$c" "lazy-llm:worktree-parent" "async launch without worktreePath: found by agentId"
assert_has "$c" "llm-wt integrate --remove $wt" "...naming its worktree"
async_none=${async//\"g1\"/\"nosuch\"}
assert_empty "$(hook "$async_none")" "an agentId with no worktree (not isolated): nothing"
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
assert_empty "$(hook "$(printf '{"session_id":"fresh-session","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$R")")" "main dir, a new session: nothing"
out=$(cd "$pane" && printf '%s' "$(p_sessstart "$pane")" | TMUX_PANE=%1 LAZY_LLM_WORKTREE=1 bash "$CLAUDE_HOOK" 2>/dev/null)
assert_lacks "$out" "additionalContext" "llm-claude-hook no longer prints the guidance (no duplicate)"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 11b: a resumed session (lazy-llm restore) re-owns and is reminded of its worktrees..."
R="$sandbox/r11b"; mk_repo "$R"
p_sess() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$1" "$2" "$3"; }
# The original pane, on a first tmux server.
tmux -f /dev/null new-session -d -s orig "exec sleep 300"
P1=$(tmux display -t orig -p '#{pane_id}'); T1=$(tmux display -t orig -p '#{socket_path},#{pid},0')
mk() { printf '%s' "$(p_create "$R" "$1" sess-R)" | TMUX="$T1" TMUX_PANE="$P1" "$LLMWT" claude-hook 2>/dev/null; }
sa=$(mk agent-r11b); commit_file "$sa" s.txt sub
se=$(mk wise-entered-r11b)
s1=$(cfg "$R" lazy/agent-r11b lazyLlmPaneServer)
env -u TMUX -u TMUX_PANE tmux kill-server 2>/dev/null
sleep 1.1   # a new server's start time (seconds) must differ
# lazy-llm restore: a new server, a new pane, `claude --resume` → SessionStart(resume)
tmux -f /dev/null new-session -d -s restored "exec sleep 300"
P2=$(tmux display -t restored -p '#{pane_id}'); T2=$(tmux display -t restored -p '#{socket_path},#{pid},0')
s2=$(tmux display -t restored -p '#{start_time}')
out=$(printf '%s' "$(p_sess sess-R "$R" resume)" | TMUX="$T2" TMUX_PANE="$P2" "$LLMWT" claude-hook 2>/dev/null)
assert_equals "$([[ "$s1" != "$s2" ]] && echo differ)" "differ" "setup: the restored server has another start time"
assert_equals "$(cfg "$R" lazy/agent-r11b lazyLlmPane) $(cfg "$R" lazy/agent-r11b lazyLlmPaneServer)" "$P2 $s2" "the subagent worktree is re-stamped with the restored pane and server"
assert_equals "$(cfg "$R" lazy/wise-entered-r11b lazyLlmPaneServer)" "$s2" "...and so is the entered one"
assert_equals "$(is_json "$out")" "ok" "valid JSON"
c=$(ctx "$out")
assert_has "$c" "1 subagent worktree(s) from this session aren't landed yet" "reminded of the subagent worktree"
assert_has "$c" "\`$sa\` (branch \`lazy/agent-r11b\`): 1 commit(s) beyond \`feature\`, 0 uncommitted, 0 untracked" "...with its path, branch and commits"
assert_has "$c" "this session created the worktree \`$se\` with EnterWorktree" "reminded of the worktree it entered"
assert_has "$c" "<!-- lazy-llm:worktree-agent -->" "...with the isolated-worktree rules (resume's cwd is the main dir)"
assert_lacks "$c" "{{" "no placeholder left"
out=$(printf '%s' "$(p_sess other-session "$R" resume)" | TMUX="$T2" TMUX_PANE="$P2" "$LLMWT" claude-hook 2>/dev/null)
assert_empty "$out" "another session: nothing"
env -u TMUX -u TMUX_PANE tmux kill-server 2>/dev/null
before=$(cfg "$R" lazy/agent-r11b lazyLlmPane)
out=$(printf '%s' "$(p_sess sess-R "$R" compact)" | "$LLMWT" claude-hook 2>/dev/null)
assert_has "$(ctx "$out")" "aren't landed yet" "outside tmux (or after a compact): still reminded"
assert_equals "$(cfg "$R" lazy/agent-r11b lazyLlmPane)" "$before" "...but ownership is left alone without a pane"
out=$(printf '%s' "$(p_sess sess-R "$se" resume)" | "$LLMWT" claude-hook 2>/dev/null)
c=$(ctx "$out")
assert_equals "$(grep -o 'lazy-llm:worktree-agent' <<< "$c" | wc -l | tr -d ' ')" "1" "started inside the entered worktree: the rules once, not twice"
assert_lacks "$c" "this session created the worktree \`$se\`" "...without the 'created with EnterWorktree' preface"
echo ""
echo "Test 11c: persistence edge cases (verification round on 232931f)..."
XS="$sandbox/xs11c"; mkdir -p "$XS"
R="$sandbox/r11c"; mk_repo "$R"
tmux -f /dev/null new-session -d -s a11c "exec sleep 300"
PA=$(tmux display -t a11c -p '#{pane_id}'); TA=$(tmux display -t a11c -p '#{socket_path},#{pid},0')
tmux split-window -d -t a11c "exec sleep 300"
PB=$(tmux list-panes -t a11c -F '#{pane_id}' | grep -vxF "$PA" | head -1)
SA=$(tmux display -t a11c -p '#{start_time}')
hk() { printf '%s' "$1" | XDG_STATE_HOME="$XS" TMUX="$TA" TMUX_PANE="$2" "$LLMWT" claude-hook 2>/dev/null; }
w1=$(hk "$(p_create "$R" agent-c11 sess-C)" "$PA")
commit_file "$w1" c1.txt one
printf 'wip\n' >> "$w1/c1.txt"
# 1. A second pane resuming the same conversation (restore --snapshot,
#    claude -c elsewhere) must not take a worktree from the live pane.
out=$(hk "$(p_sess sess-C "$R" resume)" "$PB")
assert_equals "$(cfg "$R" lazy/agent-c11 lazyLlmPane)" "$PA" "a second pane resuming: the live owner keeps it"
c=$(ctx "$out")
assert_has "$c" "1 commit(s) beyond \`feature\`, 1 uncommitted, 0 untracked" "the reminder counts uncommitted work too"
assert_has "$c" "may have been cut off" "...and warns a subagent may be cut off or still running"
# Owner pane gone (closed) on the same server: re-owned.
tmux kill-pane -t "$PA"
hk "$(p_sess sess-C "$R" resume)" "$PB" >/dev/null
assert_equals "$(cfg "$R" lazy/agent-c11 lazyLlmPane)" "$PB" "owner pane closed: re-owned by the resuming pane"
# 2. Mid-rebase (a conflicted integrate leaves this): still found.
git -C "$w1" checkout -q -- c1.txt
commit_file "$w1" c2.txt two
GIT_SEQUENCE_EDITOR="sed -i '1i break'" git -C "$w1" rebase -q -i feature >/dev/null 2>&1
assert_equals "$(git -C "$w1" branch --show-current)" "" "setup: detached mid-rebase"
c=$(ctx "$(hk "$(p_sess sess-C "$R" compact)" "$PB")")
assert_has "$c" "\`$w1\` (branch \`lazy/agent-c11\`)" "a worktree mid-rebase is still in the reminder"
assert_has "$c" "a rebase is in progress there" "...saying so"
assert_has "$(cd "$R" && "$LLMWT" list --porcelain)" "$w1" "...and llm-wt list shows it"
git -C "$w1" rebase --abort 2>/dev/null
# 3. Registry: a worktree in another repo than the resumed session's cwd
#    (launched in a superproject, worked in a submodule) is found.
SUP="$sandbox/r11c-super"; mk_repo "$SUP"
c=$(ctx "$(printf '%s' "$(p_sess sess-C "$SUP" resume)" | XDG_STATE_HOME="$XS" CLAUDE_PROJECT_DIR="$SUP" TMUX="$TA" TMUX_PANE="$PB" "$LLMWT" claude-hook 2>/dev/null)")
assert_has "$c" "\`$w1\`" "cwd and project dir in another repo: found through the session registry"
c=$(ctx "$(printf '%s' "$(p_sess sess-C "$SUP" resume)" | XDG_STATE_HOME="$sandbox/xs-empty" CLAUDE_PROJECT_DIR="$SUP" "$LLMWT" claude-hook 2>/dev/null)")
assert_empty "$c" "...(without the registry it can't be: the registry is what finds it)"
# 4. /clear: the pane's new conversation inherits the pane's worktrees.
c=$(ctx "$(hk "$(p_sess sess-D "$R" clear)" "$PB")")
assert_has "$c" "\`$w1\`" "after /clear, the new conversation is told about the pane's worktree"
assert_equals "$(cfg "$R" lazy/agent-c11 lazyLlmSession)" "sess-C" "...its recorded session stays the old one"
assert_has "$(ctx "$(hk "$(p_sess sess-C "$R" resume)" "$PB")")" "\`$w1\`" "...so resuming the old conversation still finds it"
assert_empty "$(ctx "$(hk "$(p_sess sess-E "$R" startup)" "$PB")")" "a new conversation (not /clear) inherits nothing"
mkdir -p "$XS/lazy-llm/claude-sessions"
for i in $(seq 1 51); do printf '%s\tsess-dead%s\n' "$sandbox/gone-wt$i" "$i" > "$XS/lazy-llm/claude-sessions/sess-dead$i"; done
hk "$(p_sess sess-H "$R" startup)" "$PB" >/dev/null
assert_equals "$(find "$XS/lazy-llm/claude-sessions" -name 'sess-dead*' | wc -l | tr -d ' ')" "0" "over 50 registries: those whose worktrees are all gone are dropped"
assert_file_exists "$XS/lazy-llm/claude-sessions/sess-C" "...live ones are kept"
# A path reused after a landing by another session's worktree isn't claimed
# through a stale registry entry (verification round 2, D1).
wr=$(hk "$(p_create "$R" reuse-c11 sess-J)" "$PB")
"$LLMWT" remove "$wr" >/dev/null 2>&1
wr2=$(hk "$(p_create "$R" reuse-c11 sess-K)" "$PB")
assert_equals "$wr2" "$wr" "setup: the second session's worktree reuses the path"
assert_lacks "$(ctx "$(hk "$(p_sess sess-J "$R" compact)" "$PB")")" "$wr" "the first session isn't told about the second's worktree at that path"
assert_has "$(ctx "$(hk "$(p_sess sess-K "$R" compact)" "$PB")")" "$wr" "...the second session is"
# /clear cost stays flat: it reads the pane's index, not every registry (each
# /clear adds one: the cost grew with every clear, verification round 2 D3).
for i in 1 2 3 4; do hk "$(p_create "$R" "agent-flat$i" sess-F0)" "$PB" >/dev/null; done
clear_ms() { local t0 t1; t0=$(date +%s%N); hk "$(p_sess "$1" "$R" clear)" "$PB" >/dev/null; t1=$(date +%s%N); echo $(( (t1 - t0) / 1000000 )); }
first=$(clear_ms sess-flat0)
for i in $(seq 1 25); do hk "$(p_sess "sess-flat$i" "$R" clear)" "$PB" >/dev/null; done
last=$(clear_ms sess-flat26)
[[ $last -lt $((2 * first + 150)) ]] && r=flat || r="grew: first ${first}ms, 27th ${last}ms"
assert_equals "$r" "flat" "/clear cost doesn't grow with each clear (first ${first}ms, 27th ${last}ms)"
env -u TMUX -u TMUX_PANE tmux kill-server 2>/dev/null
# 5. An isolated pane whose session also entered a worktree: the rules once.
pane=$("$LLMWT" create "$R" p11c 2>/dev/null)
ew=$(printf '%s' "$(p_create "$pane" ent-c11 sess-F)" | XDG_STATE_HOME="$XS" "$LLMWT" claude-hook 2>/dev/null)
c=$(ctx "$(printf '%s' "$(p_sess sess-F "$pane" resume)" | XDG_STATE_HOME="$XS" "$LLMWT" claude-hook 2>/dev/null)")
assert_equals "$(grep -o 'lazy-llm:worktree-agent' <<< "$c" | wc -l | tr -d ' ')" "1" "isolated pane + an entered worktree: the rules once"
assert_has "$c" "also created the worktree \`$ew\`" "...the entered one as a short line"
# 6. Control characters never break the JSON.
CR="$sandbox/r11c-ctl$(printf '\001')x"; mk_repo "$CR"
ws=$(printf '{"session_id":"sess-G","cwd":"%s","hook_event_name":"WorktreeCreate","name":"agent-g"}' "$(printf '%s' "$CR" | sed 's/\x01/\\u0001/')")
out=$(printf '%s' "$(p_sess sess-G "$CR" resume)" | XDG_STATE_HOME="$XS" "$LLMWT" claude-hook 2>/dev/null)
if [[ -z "$out" ]]; then r=ok; else r=$(is_json "$out"); fi
assert_equals "$r" "ok" "a path with a control character: valid JSON (or nothing)"
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

# ──────────────────────────────────────────────────────────────────────────
# Regressions from the first verification round (each was a real defect).
echo ""
echo "Test 18: nested parent — removal deletes the branch too..."
R="$sandbox/r18"; mk_repo "$R"
pane=$("$LLMWT" create "$R" p18 2>/dev/null)
commit_file "$pane" pane.txt own
n1=$(hook "$(p_create "$pane" agent-n18)")
commit_file "$n1" n.txt nested
"$LLMWT" integrate --remove "$n1" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "0" "integrate --remove from a pane-parented worktree: exit 0"
assert_file_not_exists "$n1" "...worktree removed"
assert_fails "git -C '$R' show-ref --verify --quiet refs/heads/lazy/agent-n18" "...branch deleted (merged into the pane's branch, not main's HEAD)"
assert_empty "$(git -C "$R" config --get-regexp '^branch\.lazy/agent-n18\.' 2>/dev/null)" "...and its lazyLlm* config"
n2=$(hook "$(p_create "$pane" agent-m18)")
hook "$(p_sstop "$n2" m18)" >/dev/null
assert_file_not_exists "$n2" "SubagentStop removes an empty nested worktree"
assert_fails "git -C '$R' show-ref --verify --quiet refs/heads/lazy/agent-m18" "...with its branch"

echo ""
echo "Test 19: a renamed/deleted base never lets work be removed..."
R="$sandbox/r19"; mk_repo "$R"
w=$(hook "$(p_create "$R" agent-b19)")
commit_file "$w" w.txt work
git -C "$R" branch -m feature feature2
assert_equals "$("$LLMWT" status "$w" --porcelain | awk -F'\t' '$1=="base-missing"{print $2}')" "1" "status reports base-missing"
assert_equals "$("$LLMWT" status "$w" --porcelain | awk -F'\t' '$1=="unintegrated"{print $2}')" "1" "...and counts the commit no other branch has"
hook "$(p_sstop "$w" b19)" >/dev/null
assert_dir_exists "$w" "SubagentStop keeps it"
hook "$(p_remove "$w")" >/dev/null; rc=$?
assert_equals "$rc" "1" "WorktreeRemove refuses"
assert_dir_exists "$w" "...it survives"
# Mid-rebase: HEAD can sit at the base while the branch holds the commits.
rb=$(hook "$(p_create "$R" agent-rb19)")
git -C "$R" branch -m feature3 feature 2>/dev/null; git -C "$R" branch -m feature2 feature 2>/dev/null
commit_file "$rb" r1.txt one
commit_file "$rb" r2.txt two
GIT_SEQUENCE_EDITOR="sed -i '1i break'" git -C "$rb" rebase -q -i feature >/dev/null 2>&1
assert_equals "$("$LLMWT" status "$rb" --porcelain | awk -F'	' '$1=="rebasing"{print $2}')" "1" "setup: a rebase is stopped in progress"
assert_equals "$("$LLMWT" status "$rb" --porcelain | awk -F'	' '$1=="unintegrated"{print $2}')" "2" "unintegrated counts the branch's commits, not the detached HEAD's"
hook "$(p_remove "$rb")" >/dev/null; rc=$?
assert_equals "$rc" "1" "WorktreeRemove refuses mid-rebase"
"$LLMWT" remove "$rb" >/dev/null 2>&1; rc=$?
assert_equals "$rc" "1" "llm-wt remove refuses mid-rebase"
assert_success "git -C '$R' show-ref --verify --quiet refs/heads/lazy/agent-rb19" "the branch and its commits survive"
git -C "$rb" rebase --abort 2>/dev/null
git -C "$R" branch -m feature feature2
e=$(hook "$(p_create "$R" agent-c19)")
git -C "$R" branch -m feature2 feature3
hook "$(p_sstop "$e" c19)" >/dev/null
assert_file_not_exists "$e" "an empty one (its commits are on another branch) is still cleaned up"

echo ""
echo "Test 20: git hooks that leave a process running don't hold the repo lock..."
R="$sandbox/r20"; mk_repo "$R"
printf '#!/bin/sh\n(sleep 6) >/dev/null 2>&1 &\nexit 0\n' > "$R/.git/hooks/post-checkout"; chmod +x "$R/.git/hooks/post-checkout"
start=$(date +%s)
hook "$(p_create "$R" agent-h1)" >/dev/null
hook "$(p_create "$R" agent-h2)" >/dev/null
elapsed=$(( $(date +%s) - start ))
[[ $elapsed -lt 5 ]] && r=fast || r="slow (${elapsed}s)"
assert_equals "$r" "fast" "two creates don't wait on the hook's background job"
rm -f "$R/.git/hooks/post-checkout"

echo ""
echo "Test 21: a bootstrap failure still yields exactly one worktree..."
R="$sandbox/r21"; mk_repo "$R"
printf 'secret\n' > "$R/locked.conf"; chmod 000 "$R/locked.conf"
printf 'locked.conf\n' > "$R/.worktreeinclude"
out=$(printf '%s' "$(p_create "$R" agent-f1)" | LAZY_LLM_WT_BIN="$LLMWT" bash "$SHIM" 2>"$sandbox/err"); rc=$?
chmod 600 "$R/locked.conf"
assert_equals "$rc" "0" "exit 0"
assert_equals "$out" "$R/.worktrees/.claude/agent-f1" "llm-wt's worktree, not the fallback's"
assert_file_not_exists "$R/.claude/worktrees" "no second (fallback) worktree"
assert_equals "$(git -C "$R" worktree list | wc -l | tr -d ' ')" "2" "git knows main + one"
assert_has "$(cat "$sandbox/err")" "bootstrapping" "stderr says the bootstrap failed"

echo ""
echo "Test 22: paths with a quote, a backslash or & ..."
R="$sandbox/r22 \"q\\b&"; mk_repo "$R"
cwdj=$(jq -Rn --arg c "$R" '$c')
payload=$(printf '{"session_id":"s","cwd":%s,"hook_event_name":"WorktreeCreate","name":"agent-q1"}' "$cwdj")
out=$(hook "$payload"); rc=$?
assert_equals "$rc" "0" "llm-wt: create succeeds"
assert_equals "$out" "$R/.worktrees/.claude/agent-q1" "...at the decoded path"
c=$(ctx "$(hook "$(printf '{"cwd":%s,"agent_id":"q1","hook_event_name":"SubagentStart"}' "$(jq -Rn --arg c "$out" '$c')")")")
assert_has "$c" "You run in \`$out\`" "guidance carries the path verbatim"
payload2=$(printf '{"session_id":"s","cwd":%s,"hook_event_name":"WorktreeCreate","name":"agent-q2"}' "$cwdj")
out=$(printf '%s' "$payload2" | LAZY_LLM_WT_BIN="$sandbox/missing" bash "$SHIM" 2>/dev/null); rc=$?
assert_equals "$out" "$R/.claude/worktrees/agent-q2" "shim fallback decodes it too"

echo ""
echo "Test 23: WorktreeRemove only takes a Claude worktree's top directory..."
R="$sandbox/r23"; mk_repo "$R"
pane=$("$LLMWT" create "$R" p23 2>/dev/null)
hook "$(p_remove "$pane")" >/dev/null; rc=$?
assert_equals "$rc" "1" "a pane's worktree: refused"
assert_dir_exists "$pane" "...it survives"
w=$(hook "$(p_create "$R" agent-t23)")
mkdir -p "$w/sub"
hook "$(p_remove "$w/sub")" >/dev/null; rc=$?
assert_equals "$rc" "1" "a subdirectory path: refused"
assert_dir_exists "$w" "...the worktree survives"

echo ""
echo "Test 23b: WorktreeRemove never drops commits on a detached HEAD (verify round 3)..."
R="$sandbox/r23b"; mk_repo "$R"
w=$(hook "$(p_create "$R" agent-d23)")
git -C "$w" checkout -q --detach
commit_file "$w" det.txt precious
hook "$(p_remove "$w")" >/dev/null; rc=$?
assert_equals "$rc" "1" "detached HEAD with commits no branch has: refused"
assert_dir_exists "$w" "...the worktree (and its commits) survive"
out=$(printf '%s' "$(p_remove "$w")" | LAZY_LLM_WT_BIN="$LLMWT" bash "$SHIM" 2>/dev/null); rc=$?
assert_equals "$rc" "1" "...through the plugin shim too"
git -C "$w" checkout -q lazy/agent-d23 2>/dev/null
git -C "$w" checkout -q --detach
GIT_SEQUENCE_EDITOR=true git -C "$w" rebase -q -i --exec true HEAD~1 >/dev/null 2>&1
commit_file "$w" det2.txt also
GIT_SEQUENCE_EDITOR="sed -i '1i break'" git -C "$w" rebase -q -i HEAD~1 >/dev/null 2>&1
hook "$(p_remove "$w")" >/dev/null; rc=$?
assert_equals "$rc" "1" "detached HEAD with a rebase stopped in progress: refused"
git -C "$w" rebase --abort 2>/dev/null
git -C "$w" checkout -q --detach lazy/agent-d23
hook "$(p_remove "$w")" >/dev/null; rc=$?
assert_equals "$rc" "0" "detached HEAD whose commits a branch has: removed"
assert_file_not_exists "$w" "...gone"
echo ""
echo "Test 23c: background launch in a submodule-like layout, while WorktreeCreate is still running..."
# Found live (2026-10-03): the session's cwd was the lazy-llm submodule and
# CLAUDE_PROJECT_DIR the superproject, so the agentId lookup scanned the wrong
# repo; and the async launch's PostToolUse fires as WorktreeCreate runs.
R="$sandbox/r23c"; mk_repo "$R"
SUPER="$sandbox/r23c-super"; mk_repo "$SUPER"
async_payload() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"d","prompt":"p","isolation":"%s"},"tool_response":{"isAsync":true,"status":"async_launched","agentId":"%s"}}' "$1" "$2" "$3"; }
w=$(hook "$(p_create "$R" agent-sub1)")
out=$(printf '%s' "$(async_payload "$R" worktree sub1)" | CLAUDE_PROJECT_DIR="$SUPER" "$LLMWT" claude-hook 2>/dev/null)
assert_has "$(ctx "$out")" "running in the background in its own worktree \`$w\`" "cwd's repo is scanned even when CLAUDE_PROJECT_DIR is another repo"
( printf '%s' "$(async_payload "$R" worktree late1)" | CLAUDE_PROJECT_DIR="$SUPER" "$LLMWT" claude-hook > "$sandbox/late.out" 2>/dev/null ) &
bg=$!
sleep 1.5
wl=$(hook "$(p_create "$R" agent-late1)")
wait "$bg"
assert_has "$(ctx "$(cat "$sandbox/late.out")")" "\`$wl\`" "a launch hook that fires before the worktree exists waits for it"
start=$(date +%s)
out=$(hook "$(async_payload "$R" "" nosuchagent)")
elapsed=$(( $(date +%s) - start ))
assert_empty "$out" "a non-isolated background launch: nothing"
[[ $elapsed -lt 4 ]] && r=quick || r="took ${elapsed}s"
assert_equals "$r" "quick" "...without waiting long"
echo ""
echo "Test 23d: the opt-in hook log never changes output or exit status..."
R="$sandbox/r23d"; mk_repo "$R"
XS="$sandbox/xstate"; mkdir -p "$XS/lazy-llm"; : > "$XS/lazy-llm/claude-hook.log"
out=$(printf '%s' "$(p_create "$R" agent-log1)" | XDG_STATE_HOME="$XS" "$LLMWT" claude-hook 2>/dev/null); rc=$?
assert_equals "rc=$rc out=$out" "rc=0 out=$R/.worktrees/.claude/agent-log1" "writable log: same stdout and status"
assert_has "$(cat "$XS/lazy-llm/claude-hook.log")" "WorktreeCreate rc=0" "...and the event is logged"
chmod 0444 "$XS/lazy-llm/claude-hook.log"
out=$(printf '%s' "$(p_create "$R" agent-log2)" | XDG_STATE_HOME="$XS" "$LLMWT" claude-hook 2>/dev/null); rc=$?
chmod 0644 "$XS/lazy-llm/claude-hook.log"
assert_equals "rc=$rc out=$out" "rc=0 out=$R/.worktrees/.claude/agent-log2" "unwritable log (verify finding): still the path and rc 0"
fg=$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"d","prompt":"p"},"tool_response":{"status":"completed","agentId":"fg1"}}' "$R")
t0=$(date +%s%N); out=$(hook "$fg"); t1=$(date +%s%N)
assert_empty "$out" "a finished, non-isolated (foreground) launch: nothing"
[[ $(( (t1 - t0) / 1000000 )) -lt 800 ]] && r=instant || r="took $(( (t1 - t0) / 1000000 ))ms"
assert_equals "$r" "instant" "...and no wait for a worktree"
echo ""
echo "Test 23e: registry writes wait for the registry lock (a prune can't drop an append)..."
R="$sandbox/r23e"; mk_repo "$R"
XR="$sandbox/xs23e"; mkdir -p "$XR/lazy-llm"
# flock mode: hold the lock 2s from outside; a create's registry append waits.
( flock 9; sleep 2 ) 9>>"$XR/lazy-llm/registry.lock" &
holder=$!
sleep 0.3
t0=$(date +%s%N)
w=$(printf '%s' "$(p_create "$R" agent-l23e sess-L)" | XDG_STATE_HOME="$XR" "$LLMWT" claude-hook 2>/dev/null)
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
wait "$holder"
assert_dir_exists "$w" "the create still succeeds under a held registry lock"
[[ $ms -ge 1500 ]] && r=waited || r="didn't wait (${ms}ms)"
assert_equals "$r" "waited" "...after waiting for it (${ms}ms)"
assert_has "$(cat "$XR/lazy-llm/claude-sessions/sess-L")" "$w" "...and its registry entry is there"
# Portable (symlink) mode: a lock held by a live process.
sleep 30 & live=$!
ln -s "$live" "$XR/lazy-llm/registry.lock.l"
( sleep 2; rm -f "$XR/lazy-llm/registry.lock.l" ) &
t0=$(date +%s%N)
w2=$(printf '%s' "$(p_create "$R" agent-l23e2 sess-L)" | env LAZY_LLM_WT_LOCK=link XDG_STATE_HOME="$XR" "$LLMWT" claude-hook 2>/dev/null)
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
kill "$live" 2>/dev/null; wait 2>/dev/null
[[ $ms -ge 1500 ]] && r=waited || r="didn't wait (${ms}ms)"
assert_equals "$r" "waited" "symlink lock: the append waits too (${ms}ms)"
assert_has "$(cat "$XR/lazy-llm/claude-sessions/sess-L")" "$w2" "...and records its entry"
echo ""
echo "Test 24: the portable (symlink) lock..."
R="$sandbox/r24"; mk_repo "$R"
common=$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)
L="$common/lazy-llm-wt.lock.l"
for i in 1 2 3 4 5 6; do
    ( printf '%s' "$(p_create "$R" "agent-mk$i")" | env LAZY_LLM_WT_LOCK=link "$LLMWT" claude-hook > "$sandbox/mk$i.out" 2>/dev/null; echo $? > "$sandbox/mk$i.rc" ) &
done
wait
ok=0; for i in 1 2 3 4 5 6; do [[ "$(cat "$sandbox/mk$i.rc")" == 0 && -d "$(cat "$sandbox/mk$i.out")" ]] && ok=$((ok + 1)); done
assert_equals "$ok" "6" "6 parallel creates under the symlink lock all succeed"
assert_equals "$(find "$common" -maxdepth 1 -name 'lazy-llm-wt.lock*' | wc -l | tr -d ' ')" "0" "...and leave no lock behind"
ln -s 999999 "$L"
out=$(printf '%s' "$(p_create "$R" agent-dead)" | env LAZY_LLM_WT_LOCK=link "$LLMWT" claude-hook 2>/dev/null)
assert_dir_exists "$out" "a lock held by a dead pid is broken"
ln -s 999999 "$L"; mkdir "$L.break"
start=$(date +%s)
out=$(printf '%s' "$(p_create "$R" agent-brk)" | env LAZY_LLM_WT_LOCK=link "$LLMWT" claude-hook 2>/dev/null)
elapsed=$(( $(date +%s) - start ))
assert_dir_exists "$out" "a dead breaker's leftover mutex is cleared..."
[[ $elapsed -lt 15 ]] && r=ok || r="took ${elapsed}s"
assert_equals "$r" "ok" "...within seconds, not the 60s timeout"
# The round-2 verifier's race: many waiters find the same dead owner.
fails=0
for round in 1 2 3 4 5 6 7 8; do
    R="$sandbox/r24-race$round"; mk_repo "$R"
    ln -s 999999 "$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)/lazy-llm-wt.lock.l"
    for i in 1 2 3 4 5 6 7 8 9 10; do
        ( printf '%s' "$(p_create "$R" "agent-race$i")" | env LAZY_LLM_WT_LOCK=link "$LLMWT" claude-hook > "$sandbox/race$i.out" 2> "$sandbox/race$i.err"; echo $? > "$sandbox/race$i.rc" ) &
    done
    wait
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if [[ "$(cat "$sandbox/race$i.rc")" != 0 ]] || [[ -z "$(cfg "$R" "lazy/agent-race$i" lazyLlmPrimary)" ]]; then
            fails=$((fails + 1)); sed 's/^/    /' "$sandbox/race$i.err" | tail -2
        fi
    done
done
assert_equals "$fails" "0" "8 rounds x 10 waiters on a dead owner's lock: every create succeeds, fully configured"

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
