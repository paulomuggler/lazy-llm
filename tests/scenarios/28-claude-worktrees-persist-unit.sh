#!/usr/bin/env bash
# Test: workspace persistence (llm-persist save / restore) with Claude Code's
# own worktrees (.worktrees/.claude/<name>, made by `llm-wt claude-hook`).
#   1. A restored session re-owns its worktrees: after save, a server kill and
#      restore, the pane resumes its conversation, its Claude worktrees count
#      as orphaned until Claude's SessionStart(resume) arrives from the new
#      pane, and then they're re-stamped with the new pane and server (border
#      ⎇×N, Worktrees tab owner) and the session is reminded of them.
#   2. A pane adopted into a Claude worktree (llm-add -w) comes back in it,
#      with the worktree env, and the worktree is recreated from its branch
#      when its directory was removed.
#   3. Nothing leaks or disappears: every worktree and branch survives.
#
# Isolation as in 20-workspace-save-restore-unit: a private tmux server
# (TMUX_TMPDIR), a private HOME with the repo's bins symlinked in stow's
# layout (so the per-pane caches under ~/.cache/lazy-llm are the sandbox's),
# a private manifest dir, and a fake `claude`/`nvim` that only log how they
# were launched. Claude's hooks are sent as payloads with TMUX/TMUX_PANE of a
# sandbox pane. Never touches the user's own server.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="claude-worktrees-persist-unit"

REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

# With $TMUX set, tmux ignores TMUX_TMPDIR and reaches the user's own server.
unset TMUX TMUX_PANE CLAUDE_PROJECT_DIR LAZY_LLM_WORKTREE_DIR GIT_DIR GIT_WORK_TREE

# Short path: tmux socket paths are limited to ~108 bytes.
SB=$(mktemp -d /tmp/lazy-llm-test-cwp-XXXXXX)
mkdir -p "$SB/home/.local/bin" "$SB/home/.local/share" "$SB/fake" "$SB/state"
for f in "$REPO_ROOT"/*-bin/.local/bin/*; do ln -s "$f" "$SB/home/.local/bin/"; done
# llm-wt's guidance texts (worktree-agent.md), as stow lays them out.
ln -s "$REPO_ROOT/llm-status-bin/.local/share/lazy-llm" "$SB/home/.local/share/lazy-llm"
for t in claude nvim; do
    cat > "$SB/fake/$t" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$t \$* PANE=\${TMUX_PANE:-} PWD=\$PWD WT=\${LAZY_LLM_WORKTREE:-} BASE=\${LAZY_LLM_BASE_BRANCH:-} PRIMARY=\${LAZY_LLM_PRIMARY_DIR:-}" >> "$SB/argv.log"
exec sleep 600
EOF
    chmod +x "$SB/fake/$t"
done
cat > "$SB/home/.gitconfig" <<EOF
[user]
	name = t
	email = t@t
[init]
	defaultBranch = main
EOF

# Work from inside the sandbox: an empty path given to `git -C` means the
# current directory, which must never be the lazy-llm checkout.
cd "$SB" || exit 1
export GIT_CEILING_DIRECTORIES=/tmp

# Run a command inside the sandbox environment.
sbx() {
    env -u TMUX -u TMUX_PANE -u CLAUDECODE HOME="$SB/home" TMUX_TMPDIR="$SB" \
        LAZY_LLM_STATE_DIR="$SB/state" XDG_RUNTIME_DIR="$SB/run" \
        PATH="$SB/fake:$SB/home/.local/bin:$(dirname "$(command -v jq)"):/usr/bin:/bin" "$@"
}
T() { sbx tmux "$@"; }
first_win() { T list-windows -t "=$1" -F '#{window_index}' | head -1; }
wopt() { T show-option -wqv -t "=$1:$(first_win "$1")" "$2"; }
entry() { grep -l "\"name\": \"$1\"" "$SB"/state/workspaces/*.json 2>/dev/null | head -1; }
cfg() { sbx git -C "$1" config "branch.$2.$3" 2>/dev/null; }
untag() { sed 's/#\[[^]]*\]//g'; }

# A Claude hook payload on stdin to `llm-wt claude-hook`, run as from pane $1
# (the TMUX a process in that pane gets: socket,pid,session). No pane: "".
hook_from() {
    local pane="$1" tmux_env=""
    [[ -n "$pane" ]] && tmux_env=$(T display -p -t "$pane" '#{socket_path},#{pid},0')
    sbx env TMUX="$tmux_env" TMUX_PANE="$pane" llm-wt claude-hook 2>/dev/null
}
p_create() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"WorktreeCreate","name":"%s"}' "$1" "$2" "$3"; }
p_resume() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"resume"}' "$1" "$2"; }
ctx() { jq -r '.hookSpecificOutput.additionalContext' <<< "$1" 2>/dev/null; }
border() { sbx llm-pane-border "$1" claude | untag; }
owner_of() {
    sbx bash -c "cd '$2' && source '$SB/home/.local/bin/lazy-llm-lib.sh' && lazy_llm_gather_worktrees" \
        | awk -F$'\x1f' -v p="$1" '$1 == p {print $8}'
}
launch_of() { grep " PANE=$1 " "$SB/argv.log" | grep '^claude ' | tail -1; }
# Literal substring checks (assert_contains matches a regex; these needles
# carry "×", "(", backquotes and paths).
assert_has() {
    if [[ "$1" == *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Looking for: '$2'"; echo "  In text: '${1:0:400}...'"; fi
}
assert_lacks() {
    if [[ "$1" != *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Unexpected: '$2'"; echo "  In text: '${1:0:400}...'"; fi
}
mk_repo() {
    mkdir -p "$1"
    sbx git -C "$1" init -q
    echo x > "$1/f"
    sbx git -C "$1" add f
    sbx git -C "$1" commit -qm init
}
branches() { sbx git -C "$1" for-each-ref --format='%(refname:short)' 'refs/heads/lazy/*' | sort | tr '\n' ' '; }
wt_paths() { sbx git -C "$1" worktree list --porcelain | sed -n 's/^worktree //p' | sort | tr '\n' ' '; }

cleanup() {
    T kill-server 2>/dev/null
    # Background saves (save --async) still running would recreate $SB/state.
    sleep 1
    rm -rf "$SB"
}
trap cleanup EXIT

# ──────────────────────────────────────────────────────────────────────────
echo "Setup: two workspaces, Claude worktrees made through the hook..."
C="$SB/c"; D="$SB/d"
mk_repo "$C"; mk_repo "$D"
sbx lazy-llm -s wsC -d "$C" -t claude >/dev/null 2>&1
sbx lazy-llm -s wsD -d "$D" -t claude >/dev/null 2>&1
sleep 1
P=$(wopt wsC @AI_PANE_ID)
S="conv-c1"
printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"%s"}' "$S" \
    | sbx env TMUX_PANE="$P" llm-claude-hook
# wsC's session makes a subagent worktree (one commit) and enters another.
WA=$(p_create "$S" "$C" agent-c1 | hook_from "$P")
WE=$(p_create "$S" "$C" wise-entered-c | hook_from "$P")
assert_equals "$WA" "$C/.worktrees/.claude/agent-c1" "setup: the subagent worktree is under .worktrees/.claude"
assert_equals "$WE" "$C/.worktrees/.claude/wise-entered-c" "setup: so is the entered one"
echo sub > "$WA/s.txt"; sbx git -C "$WA" add s.txt; sbx git -C "$WA" commit -qm sub
OLD_SERVER=$(T display -p -t "$P" '#{start_time}')
assert_equals "$(cfg "$C" lazy/agent-c1 lazyLlmKind) $(cfg "$C" lazy/agent-c1 lazyLlmSession) $(cfg "$C" lazy/agent-c1 lazyLlmPane) $(cfg "$C" lazy/agent-c1 lazyLlmPaneServer)" \
    "claude $S $P $OLD_SERVER" "setup: the worktree records kind, session, pane and server"
assert_has "$(border "$P")" "⎇×2" "setup: P's border shows ⎇×2 before the restart"

# wsD: a pane adopted into a Claude worktree (made by a session outside tmux).
WD=$(p_create "conv-maker" "$D" wise-adopted-d | hook_from "")
assert_equals "$WD" "$D/.worktrees/.claude/wise-adopted-d" "setup: wsD's Claude worktree"
DPP=$(wopt wsD @PROMPT_PANE_ID)
sbx env TMUX_PANE="$DPP" llm-add -t claude -w "$WD" >/dev/null 2>&1
sleep 0.5
read -ra Dp <<< "$(wopt wsD @AI_PANES)"
DQ="${Dp[1]:-}"
assert_equals "$(T show-option -pqv -t "${DQ:-%none}" @lazy_llm_wt)" "$WD" "setup: llm-add -w tags the pane with the Claude worktree"
printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"conv-d1"}' \
    | sbx env TMUX_PANE="$DQ" llm-claude-hook
DBASE=$(cfg "$D" lazy/wise-adopted-d lazyLlmBase)
DPRIM=$(cfg "$D" lazy/wise-adopted-d lazyLlmPrimary)
assert_equals "$DBASE $DPRIM" "main $D" "setup: its base and primary"

BRANCHES_C=$(branches "$C"); BRANCHES_D=$(branches "$D")
WTS_C=$(wt_paths "$C"); WTS_D=$(wt_paths "$D")

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 1: save, kill the server, restore..."
sbx llm-persist save >/dev/null
fC=$(entry wsC); fD=$(entry wsD)
assert_equals "$(jq -r '.windows[0].panes[0].conv' "$fC")" "$S" "wsC's pane saved with its conversation"
assert_equals "$(jq -c '.windows[0].panes[0].worktree' "$fC")" "null" "...and no worktree (it runs in the main directory)"
assert_equals "$(jq -c '.windows[0].panes[1].worktree' "$fD")" "{\"path\":\"$WD\",\"branch\":\"lazy/wise-adopted-d\"}" \
    "wsD's adopted pane saved with its Claude worktree"
assert_equals "$(jq -r '.windows[0].panes[1].conv' "$fD")" "conv-d1" "...and its conversation"
T kill-server
# A new server's start time (whole seconds) must differ from the old one's.
while [[ "$(date +%s)" -le "$OLD_SERVER" ]]; do sleep 0.2; done
sleep 1.1
: > "$SB/argv.log"
out=$(sbx llm-persist restore 2>&1)
sleep 1
assert_contains "$out" "Restored wsC" "wsC restored"
assert_contains "$out" "Restored wsD" "wsD restored"
RP=$(wopt wsC @AI_PANE_ID)
NEW_SERVER=$(T display -p -t "$RP" '#{start_time}')
assert_equals "$([[ "$NEW_SERVER" != "$OLD_SERVER" ]] && echo differ)" "differ" "setup: the restored server has another start time"
echo "  (old pane $P, restored pane $RP)"
assert_contains "$(launch_of "$RP")" "^claude --resume $S PANE=$RP PWD=$C WT= " "the restored pane resumes conversation $S in the main directory"

echo ""
echo "Test 2: before SessionStart, the worktrees are orphaned..."
assert_lacks "$(border "$RP")" "⎇×" "no ⎇× on the restored pane's border"
assert_equals "$(owner_of "$WA" "$C")" "claude:orphaned" "Worktrees tab: the subagent worktree is claude:orphaned"
assert_equals "$(owner_of "$WE" "$C")" "claude:orphaned" "...and so is the entered one"
assert_equals "$(branches "$C") $(wt_paths "$C")" "$BRANCHES_C $WTS_C" "restore with no SessionStart removes no worktree or branch"

echo ""
echo "Test 3: Claude's SessionStart(resume) from the restored pane re-owns them..."
out=$(p_resume "$S" "$C" | hook_from "$RP")
assert_equals "$(cfg "$C" lazy/agent-c1 lazyLlmPane) $(cfg "$C" lazy/agent-c1 lazyLlmPaneServer)" "$RP $NEW_SERVER" \
    "the subagent worktree names the restored pane and server"
assert_equals "$(cfg "$C" lazy/wise-entered-c lazyLlmPane) $(cfg "$C" lazy/wise-entered-c lazyLlmPaneServer)" "$RP $NEW_SERVER" \
    "...and so does the entered one"
assert_has "$(border "$RP")" "⎇×2" "the restored pane's border shows ⎇×2"
assert_equals "$(owner_of "$WA" "$C")" "claude:wsC:$RP" "Worktrees tab: the subagent worktree is owned by the restored pane"
assert_equals "$(owner_of "$WE" "$C")" "claude:wsC:$RP" "...and so is the entered one"
c=$(ctx "$out")
assert_has "$c" "1 subagent worktree(s) from this session are still waiting to land" "additionalContext: reminded of the subagent worktree"
assert_has "$c" "\`$WA\` (branch \`lazy/agent-c1\`, 1 commit(s) beyond \`main\`)" "...with its path, branch and commit count"
assert_has "$c" "entered the worktree \`$WE\` earlier (EnterWorktree)" "...and of the worktree it entered"
assert_has "$c" "<!-- lazy-llm:worktree-agent -->" "...with the worktree-agent rules"
assert_lacks "$c" "{{" "...no placeholder left"

echo ""
echo "Test 4: the adopted pane comes back in its Claude worktree..."
read -ra RDp <<< "$(wopt wsD @AI_PANES)"
RQ="${RDp[1]:-}"
assert_equals "$(T show-option -pqv -t "${RQ:-%none}" @lazy_llm_wt)" "$WD" "the restored pane gets @lazy_llm_wt back"
assert_has "$(launch_of "$RQ")" "claude --resume conv-d1 PANE=$RQ PWD=$WD WT=1 BASE=$DBASE PRIMARY=$DPRIM" \
    "...resumes in the worktree with LAZY_LLM_WORKTREE=1 and its base and primary"
assert_equals "$(owner_of "$WD" "$D")" "pane:wsD:$RQ" "Worktrees tab: owned by the pane running in it"

echo ""
echo "Test 5: its directory removed (branch kept), restore recreates it..."
sbx llm-persist close wsD >/dev/null 2>&1
dry=$(sbx llm-persist restore --dry-run wsD 2>&1)
assert_has "$dry" "LAZY_LLM_WORKTREE=1 LAZY_LLM_PRIMARY_DIR=$DPRIM LAZY_LLM_BASE_BRANCH=$DBASE claude --resume 'conv-d1'" \
    "closed: restore --dry-run shows the launch command with the worktree env (lazy_llm_wt_launch_cmd)"
sbx git -C "$D" worktree remove --force "$WD"
assert_equals "$([[ -d "$WD" ]] && echo yes || echo no)" "no" "setup: the worktree directory is gone"
: > "$SB/argv.log"
sbx llm-persist restore wsD >/dev/null 2>&1
sleep 1
read -ra RDp <<< "$(wopt wsD @AI_PANES)"
RQ="${RDp[1]:-}"
assert_equals "$(sbx git -C "$WD" rev-parse --show-toplevel 2>/dev/null)" "$WD" "recreated at the same .worktrees/.claude/ path"
assert_equals "$(sbx git -C "$WD" branch --show-current 2>/dev/null)" "lazy/wise-adopted-d" "...on its branch"
assert_equals "$(cfg "$D" lazy/wise-adopted-d lazyLlmKind)" "claude" "...still a Claude worktree"
assert_equals "$(T show-option -pqv -t "${RQ:-%none}" @lazy_llm_wt)" "$WD" "...and the pane is back in it"
assert_has "$(launch_of "$RQ")" "claude --resume conv-d1 PANE=$RQ PWD=$WD WT=1 BASE=$DBASE PRIMARY=$DPRIM" \
    "...resuming with the worktree env"

echo ""
echo "Test 6: nothing leaks..."
assert_equals "$(branches "$C")" "$BRANCHES_C" "wsC's Claude branches all survive the cycle ($BRANCHES_C)"
assert_equals "$(branches "$D")" "$BRANCHES_D" "wsD's too"
assert_equals "$(wt_paths "$C")" "$WTS_C" "wsC's worktrees all survive the cycle"
assert_equals "$(wt_paths "$D")" "$WTS_D" "wsD's too (the removed one recreated, nothing extra)"
assert_equals "$(sbx git -C "$WA" log -1 --format=%s 2>/dev/null)" "sub" "the subagent worktree keeps its commit"
assert_equals "$(T list-sessions -F '#S' | sort | tr '\n' ' ')" "wsC wsD " "exactly the two workspaces"

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
