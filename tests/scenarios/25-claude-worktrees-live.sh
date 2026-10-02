#!/usr/bin/env bash
# Test: Claude Code's worktrees through llm-wt, LIVE — real `claude -p` runs
# (claude-subagent-worktrees, spec .agents/TODO/specs/claude-subagent-worktrees.md
# §12.2). Opt-in: costs real tokens. Run with
#   LAZY_LLM_LIVE_CLAUDE=1 tests/test-runner.sh 25-claude-worktrees-live
# Assertions are on git state, hook logs and transcripts, never on what the
# model says. Rerun after Claude Code upgrades: it's the canary for the
# hook payload facts the design rests on (spec §2).

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="claude-worktrees-live"

if [[ "${LAZY_LLM_LIVE_CLAUDE:-}" != 1 ]]; then
    echo "skipped: set LAZY_LLM_LIVE_CLAUDE=1 to run real Claude sessions"
    exit 0
fi
for t in claude jq git; do
    command -v "$t" >/dev/null 2>&1 || { echo "$t is required"; exit 1; }
done

REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
LLMWT="$REPO_ROOT/llm-wt-bin/.local/bin/llm-wt"
SHIM="$REPO_ROOT/claude-plugin/hooks/worktree.sh"
MODEL="${LAZY_LLM_LIVE_MODEL:-sonnet}"

# Never let a hook or a model-run command reach the user's tmux server.
unset TMUX TMUX_PANE CLAUDE_PROJECT_DIR LAZY_LLM_WORKTREE_DIR

sandbox=$(mktemp -d /tmp/lazy-llm-test-claudelive-XXXXXX)
# Kept on failure (logs, transcripts paths, repos) for diagnosis.
trap '[[ "${ASSERTIONS_FAILED:-0}" -eq 0 ]] && rm -rf "$sandbox" || echo "kept for diagnosis: $sandbox"' EXIT
cd "$sandbox" || exit 1
export GIT_CEILING_DIRECTORIES=/tmp

# HOME stays real (claude needs its credentials); git identity per repo.
mk_repo() {
    local d="$1"
    git init -q --bare "$d.git"
    git init -q -b trunk "$d"
    git -C "$d" config user.email test@test
    git -C "$d" config user.name test
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

# The hook command: log the payload and the result, then run this checkout's
# plugin shim against this checkout's llm-wt.
cat > "$sandbox/hook.sh" <<EOF
#!/usr/bin/env bash
in=\$(cat)
out=\$(printf '%s' "\$in" | LAZY_LLM_WT_BIN="$LLMWT" bash "$SHIM" 2>>"\$LIVE_LOG.err"); rc=\$?
ev=\$(jq -r .hook_event_name <<< "\$in")
envlink=""
[ "\$ev" = WorktreeCreate ] && [ -d "\$out" ] && envlink=\$(readlink "\$out/.env")
jq -cn --argjson p "\$in" --arg out "\$out" --arg rc "\$rc" --arg envlink "\$envlink" \
    '{ev: \$p.hook_event_name, p: \$p, out: \$out, rc: \$rc, envlink: \$envlink}' >> "\$LIVE_LOG"
[ -n "\$out" ] && printf '%s\n' "\$out"
exit \$rc
EOF
chmod +x "$sandbox/hook.sh"

# Settings: the installed lazy-llm plugin off (its worktree hooks would run
# twice), and this checkout's hooks wired the way the plugin wires them.
jq -n --arg h "$sandbox/hook.sh" '
  def e(t): [{hooks: [{type: "command", command: $h, timeout: t}]}];
  {enabledPlugins: {"lazy-llm@lazy-llm": false},
   hooks: {WorktreeCreate: e(600), WorktreeRemove: e(60), SubagentStart: e(30),
           SubagentStop: e(60), SessionStart: e(30),
           PostToolUse: [{matcher: "Agent|EnterWorktree", hooks: [{type: "command", command: $h, timeout: 30}]}]}}' \
    > "$sandbox/settings.json"

# run <repo> <prompt>: one headless session in <repo>, hooks logged to <repo>.log.
run() {
    ( cd "$1" && LIVE_LOG="$1.log" timeout 900 claude -p --model "$MODEL" \
        --setting-sources project,local --settings "$sandbox/settings.json" \
        --dangerously-skip-permissions "$2" > "$1.out" 2>&1; echo "exit $?" >> "$1.out" )
}
assert_has() {
    if [[ "$1" == *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  '$2' not in '${1:0:300}'"; fi
}
events() { jq -r 'select(.ev == "'"$2"'") | '"$3" "$1.log" 2>/dev/null; }

R1="$sandbox/fanout"; R2="$sandbox/enter"; R3="$sandbox/keep"; R4="$sandbox/background"
mk_repo "$R1"; mk_repo "$R2"; mk_repo "$R3"; mk_repo "$R4"
trunk1=$(git -C "$R1" rev-parse origin/trunk)

# shellcheck disable=SC2016  # backticks in the prompts are literal
P1='This is an automated integration test; do not ask questions, finish the job.
In ONE message, launch three subagents in parallel with the Agent tool, each with subagent_type "general-purpose", isolation "worktree" and run_in_background false:
- Agent A: create the file alpha.txt containing "alpha", then git add and git commit it with the message "add alpha".
- Agent B: create the file beta.txt containing "beta", then git add and git commit it with the message "add beta".
- Agent C: only run `ls -a` and `git log --oneline -3`; change nothing, commit nothing.
After all three return, follow the integration instructions you were given about their worktrees, one worktree at a time, until nothing is left to integrate. Then reply DONE.'
P2='This is an automated integration test; do not ask questions, finish the job.
Use the EnterWorktree tool to create and enter a new worktree. In it, create the file gamma.txt containing "gamma", git add it and git commit it with the message "add gamma". Then follow the integration instructions you were given so the commit reaches the base branch. Finally call ExitWorktree with action "remove" (if it asks you to confirm discarding, the work is already integrated: pass discard_changes true). Reply DONE.'
P4='This is an automated integration test; do not ask questions, finish the job.
Launch ONE subagent with the Agent tool, subagent_type "general-purpose", isolation "worktree" and run_in_background true: it creates the file epsilon.txt containing "epsilon", then git add and git commit it with the message "add epsilon".
Wait for its completion notification. Then follow the integration instructions you were given so its commit reaches the base branch. Reply DONE.'
P3='This is an automated integration test; do not ask questions.
Launch ONE subagent with the Agent tool, subagent_type "general-purpose" and isolation "worktree": it creates the file delta.txt containing "delta", then git add and git commit it with the message "add delta".
When it returns, do NOT integrate, merge, land or remove anything, whatever any instructions say. Just reply DONE.'

echo "Running four live Claude sessions in parallel (model: $MODEL)..."
run "$R1" "$P1" & run "$R2" "$P2" & run "$R3" "$P3" & run "$R4" "$P4" &
wait
for r in "$R1" "$R2" "$R3" "$R4"; do
    echo "--- $(basename "$r"): $(tail -1 "$r.out")"
done

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 1: fan-out of three isolated subagents, landed by the parent..."
creates=$(events "$R1" WorktreeCreate '.out' | grep -c .)
assert_equals "$creates" "3" "exactly 3 WorktreeCreate events"
assert_equals "$(events "$R1" WorktreeCreate '.rc' | sort -u | tr '\n' ' ')" "0 " "all exited 0"
paths=$(events "$R1" WorktreeCreate '.out')
assert_equals "$(grep -c "^$R1/.worktrees/.claude/agent-" <<< "$paths")" "3" "all under .worktrees/.claude/agent-*"
assert_equals "$(grep -c -- '-2$' <<< "$paths")" "0" "no doubled creation (installed plugin is off)"
assert_equals "$(events "$R1" WorktreeCreate '.envlink' | sort -u | tr '\n' ' ')" "$R1/.env " ".env linked into each (bootstrap)"
assert_equals "$(events "$R1" SubagentStart '.p.agent_id' | grep -c .)" "3" "3 SubagentStart events"
n=0
while IFS= read -r t; do
    [[ -f "$t" ]] && grep -q 'lazy-llm:worktree-subagent' "$t" && n=$((n + 1))
done < <(events "$R1" SubagentStop '.p.agent_transcript_path')
assert_equals "$n" "3" "every subagent transcript carries the worktree-subagent guidance"
parent_t=$(events "$R1" SessionStart '.p.transcript_path' | head -1)
assert_file_exists "$parent_t" "parent transcript found"
# What reached the model: the transcript's hook_additional_context records
# (each injection is also logged once more as a raw hook_success record).
injected() { jq -r 'select(.type == "attachment" and .attachment.type == "hook_additional_context") | .attachment | tostring' "$1" | grep -c "$2"; }
assert_equals "$(injected "$parent_t" 'lazy-llm:worktree-parent')" "2" "parent got the land guidance twice (A, B)"
assert_equals "$(injected "$parent_t" 'changed nothing in its worktree')" "1" "...and the 'changed nothing' note once (C)"
log1=$(git -C "$R1" log --format=%s feature)
[[ "$log1" == *"add alpha"* && "$log1" == *"add beta"* ]] && r=both || r="missing: $log1"
assert_equals "$r" "both" "feature has A's and B's commits"
assert_equals "$(git -C "$R1" rev-list --merges "$trunk1..feature" | wc -l | tr -d ' ')" "0" "no merge commits (rebase + fast-forward)"
assert_equals "$(git -C "$R1" rev-parse origin/trunk)" "$trunk1" "origin/trunk unchanged"
left=$(find "$R1/.worktrees/.claude" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
assert_equals "$left" "0" "no worktree left under .worktrees/.claude"
assert_equals "$(git -C "$R1" branch --list 'lazy/*' | wc -l | tr -d ' ')" "0" "no lazy/* branch left"
assert_equals "$(git -C "$R1" worktree list | wc -l | tr -d ' ')" "1" "git knows only the main worktree"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 1b: a background subagent, landed after its completion notification..."
assert_equals "$(events "$R4" PostToolUse 'select(.p.tool_name == "Agent") | .p.tool_response.status' | head -1)" "async_launched" "it really was a background launch"
bctx=$(events "$R4" PostToolUse 'select(.p.tool_name == "Agent") | .out' | head -1)
assert_has "$bctx" "running in the background" "the launch got the background guidance (found by agentId)"
assert_has "$(git -C "$R4" log --format=%s feature)" "add epsilon" "feature has its commit"
assert_equals "$(git -C "$R4" worktree list | wc -l | tr -d ' ')" "1" "its worktree is gone"
assert_equals "$(git -C "$R4" branch --list 'lazy/*' | wc -l | tr -d ' ')" "0" "...and its branch"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: EnterWorktree session integrates itself..."
ewt=$(events "$R2" WorktreeCreate '.out' | head -1)
assert_has "$ewt" "$R2/.worktrees/.claude/" "WorktreeCreate under .worktrees/.claude/"
t2=$(events "$R2" SessionStart '.p.transcript_path' | head -1)
assert_equals "$(injected "$t2" 'lazy-llm:worktree-agent')" "1" "the session got worktree-agent.md once (PostToolUse EnterWorktree)"
assert_has "$(git -C "$R2" log --format=%s feature)" "add gamma" "feature has the commit"
assert_equals "$(git -C "$R2" worktree list | wc -l | tr -d ' ')" "1" "the worktree is gone"
assert_equals "$(git -C "$R2" branch --list 'lazy/*' | wc -l | tr -d ' ')" "0" "...and its branch"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: unintegrated work survives..."
kwt=$(events "$R3" WorktreeCreate '.out' | head -1)
assert_dir_exists "$kwt" "the subagent's worktree still exists"
kb=$(git -C "$kwt" branch --show-current 2>/dev/null)
assert_has "$(git -C "$R3" log --format=%s "$kb" 2>/dev/null)" "add delta" "its branch has the commit"
assert_not_contains "$(git -C "$R3" log --format=%s feature)" "add delta" "feature doesn't"
assert_equals "$(events "$R3" WorktreeRemove '.rc' | grep -c 0)" "0" "no successful WorktreeRemove for it"

if [[ "$ASSERTIONS_FAILED" -ne 0 ]]; then
    echo ""
    echo "Session outputs and hook logs (for diagnosis):"
    for r in "$R1" "$R2" "$R3" "$R4"; do
        echo "===== $(basename "$r").out"; tail -30 "$r.out"
        echo "===== $(basename "$r").log events"; jq -c '{ev, rc, out: .out[0:120], tool: .p.tool_name, agent: .p.agent_id}' "$r.log" 2>/dev/null
        echo "===== $(basename "$r").log.err"; tail -20 "$r.log.err" 2>/dev/null
    done
fi

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
