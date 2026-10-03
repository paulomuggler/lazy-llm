#!/usr/bin/env bash
# Test: Claude's worktrees shown by lazy-llm (claude-subagent-worktrees-ui,
# spec .agents/TODO/specs/claude-subagent-worktrees.md §10): the AI pane
# border's ⎇×N, the dashboard tree row's, and <leader>llmw's candidates.
# The Worktrees tab (owners, I) is covered in 14-worktree-bridge-tab-unit.
# Claude worktrees come from `llm-wt claude-hook` payloads with TMUX_PANE set
# to a sandbox pane: no Claude needed.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="claude-worktrees-ui-unit"

REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"
LLMWT="$REPO_ROOT/llm-wt-bin/.local/bin/llm-wt"

# With $TMUX set, tmux ignores TMUX_TMPDIR and reaches the user's own server.
unset TMUX TMUX_PANE CLAUDE_PROJECT_DIR LAZY_LLM_WORKTREE_DIR

sandbox=$(mktemp -d /tmp/lazy-llm-test-claudeui-XXXXXX)
cleanup_sandbox() {
    env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$sandbox/tmux" tmux kill-server 2>/dev/null || true
    rm -rf "$sandbox"
}
trap cleanup_sandbox EXIT
# Work from inside the sandbox: an empty path given to `git -C` means the
# current directory, which must never be the lazy-llm checkout.
cd "$sandbox" || exit 1
export GIT_CEILING_DIRECTORIES=/tmp
export HOME="$sandbox/home" TMUX_TMPDIR="$sandbox/tmux" LAZY_LLM_STATE_DIR="$sandbox/state"
HOME_BIN="$HOME/.local/bin"
mkdir -p "$HOME_BIN" "$TMUX_TMPDIR"
unset XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE
git config --global user.email test@test
git config --global user.name test
git config --global init.defaultBranch main
for f in llm-send-bin/.local/bin/lazy-llm-lib.sh llm-wt-bin/.local/bin/llm-wt \
         lazy-llm-bin/.local/bin/llm-dashboard lazy-llm-bin/.local/bin/llm-pane-border; do
    ln -sf "$REPO_ROOT/$f" "$HOME_BIN/${f##*/}"
done
# shellcheck source=/dev/null
source "$LIB_FILE"

# Claude's WorktreeCreate as the plugin runs it; $3 = the owning pane.
# The TMUX a process in pane $1 gets (socket,pid,session) — llm-wt asks the
# pane's server only through it. Empty for no pane or one that doesn't exist.
_pane_tmux_env() {
    [[ -n "$1" ]] || return 0
    tmux display -p -t "$1" '#{socket_path},#{pid},0' 2>/dev/null || true
}
claude_wt() {
    printf '{"session_id":"s1","cwd":"%s","hook_event_name":"WorktreeCreate","name":"%s"}' "$1" "$2" \
        | TMUX="$(_pane_tmux_env "$3")" TMUX_PANE="$3" "$LLMWT" claude-hook 2>/dev/null
}
untag() { sed 's/#\[[^]]*\]//g'; }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
# Literal substring checks (assert_contains matches a regex; these needles
# carry "×", "(" and paths).
assert_has() {
    if [[ "$1" == *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Looking for: '$2'"; echo "  In text: '${1:0:300}...'"; fi
}
assert_lacks() {
    if [[ "$1" != *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Unexpected: '$2'"; fi
}

R="$sandbox/repo"
mkdir -p "$R/src"
git -C "$R" init -q
printf 'l1\nl2\nl3\nl4\n' > "$R/src/x.lua"
git -C "$R" add -A && git -C "$R" commit -qm init

# A workspace with two AI panes, P and Q, both in the main directory.
tmux -f /dev/null new-session -d -s cws -c "$R" -x 200 -y 50 "exec sleep 300"
P=$(tmux display -t cws -p '#{pane_id}')
Q=$(tmux split-window -t "$P" -c "$R" -P -F '#{pane_id}' "exec sleep 300")
tmux set-option -t cws @lazy_llm 1
tmux set-option -t cws @lazy_llm_dir "$R"
tmux set-option -w -t cws @AI_PANE_ID "$P"
tmux set-option -w -t cws @AI_PANES "$P $Q"
tmux set-option -w -t cws @AI_TOOLS "claude claude"
tmux set-option -w -t cws @AI_PANE_IDX 0

# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: lazy_llm_claude_worktree_owners..."
assert_equals "$(lazy_llm_claude_worktree_owners "$R")" "" "none yet: nothing"
WA=$(claude_wt "$R" agent-a "$P")
WB=$(claude_wt "$R" agent-b "$P")
WC=$(claude_wt "$R" agent-c "$Q")
WN=$(claude_wt "$R" agent-n "")
WP=$("$LLMWT" create "$R" pw 2>/dev/null)
printf 'l1\nl2\nl3\nl4\nfrom-a\n' > "$WA/src/x.lua"
owners=$(lazy_llm_claude_worktree_owners "$R" | sort)
assert_equals "$owners" "$(printf '%s\t%s\n%s\t%s\n%s\t%s' "$P" "$WA" "$P" "$WB" "$Q" "$WC" | sort)" \
    "one row per Claude worktree with a pane: pane<TAB>path (none for agent-n or the pane worktree)"
assert_dir_exists "$WN" "setup: agent-n (made outside tmux) exists"
assert_equals "$(lazy_llm_claude_worktree_owners "$WP" | sort)" "$owners" "same answer from inside a worktree (shared config)"
assert_equals "$(lazy_llm_claude_worktree_owners "$sandbox")" "" "not a repo: nothing"
assert_equals "$(lazy_llm_claude_worktree_owners "")" "" "empty dir: nothing (never the current directory)"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: border git segment ends with ⎇×N for the owning pane..."
seg() { lazy_llm_git_segment "$1" T D "${2:-}" | untag; }
sha=$(git -C "$R" rev-parse --short=7 HEAD)
assert_equals "$(seg "$R" "$P")" "main $sha local ⎇×2" "pane P owns two"
assert_equals "$(seg "$R" "$Q")" "main $sha local ⎇×1" "pane Q owns one"
assert_equals "$(seg "$R" "%9999")" "main $sha local" "a pane that owns none: unchanged"
assert_equals "$(seg "$R")" "main $sha local" "no pane id: unchanged"
assert_equals "$(seg "$WP" "$P")" "⎇ pw→main $sha ⎇×2" "from a pane worktree too (the repo's config is shared)"
# Cost: one git config for the whole repo, plus one for-each-ref when some
# worktree records a pane. Never a git call per worktree.
mkdir -p "$sandbox/gitshim"
real_git=$(command -v git)
printf '#!/bin/sh\necho "$*" >> "%s/gitcalls"\nexec "%s" "$@"\n' "$sandbox" "$real_git" > "$sandbox/gitshim/git"
chmod +x "$sandbox/gitshim/git"
: > "$sandbox/gitcalls"; PATH="$sandbox/gitshim:$PATH" lazy_llm_git_segment "$R" T D "$P" >/dev/null
assert_equals "$(grep -c '' "$sandbox/gitcalls")" "4" "4 git calls with Claude worktrees (rev-parse, status, config, for-each-ref)"
assert_equals "$(grep -c -- '--get-regexp' "$sandbox/gitcalls")" "1" "...one of them a single config --get-regexp"
assert_has "$(cat "$sandbox/gitcalls")" "for-each-ref" "...and one for-each-ref for all of them"
R0="$sandbox/plain"; mkdir -p "$R0"; git -C "$R0" init -q; git -C "$R0" commit -q --allow-empty -m i
: > "$sandbox/gitcalls"; PATH="$sandbox/gitshim:$PATH" lazy_llm_git_segment "$R0" T D "$P" >/dev/null
assert_equals "$(grep -c '' "$sandbox/gitcalls")" "3" "3 git calls in a repo without any (no for-each-ref)"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: llm-pane-border and the dashboard tree row..."
border() { "$HOME_BIN/llm-pane-border" "$1" claude | untag; }
assert_has "$(border "$P")" "│ main $sha local ⎇×2 " "P's border ends with ⎇×2"
assert_has "$(border "$Q")" "│ main $sha local ⎇×1 " "Q's border ends with ⎇×1"
rows=$("$HOME_BIN/llm-dashboard" --emit-rows cws 2>/dev/null | strip)
assert_has "$(grep "pane:cws:0:$P" <<< "$rows" | cut -f2)" "⎇×2" "tree row for P carries ⎇×2"
assert_has "$(grep "pane:cws:1:$Q" <<< "$rows" | cut -f2)" "⎇×1" "tree row for Q carries ⎇×1"
# A worktree whose directory is gone no longer counts.
rm -rf "$WB"
assert_has "$(border "$P")" "│ main $sha local ⎇×1 " "a deleted directory stops counting"
"$LLMWT" remove "$WC" >/dev/null 2>&1
assert_lacks "$(border "$Q")" "⎇×" "removed through llm-wt: no ⎇× at all"
rows=$("$HOME_BIN/llm-dashboard" --emit-rows cws 2>/dev/null | strip)
assert_lacks "$(grep "pane:cws:1:$Q" <<< "$rows" | cut -f2)" "⎇×" "...on the tree row either"
tmux set-option -g @lazy_llm_border_git off
assert_lacks "$(border "$P")" "⎇×" "@lazy_llm_border_git off drops it with the git segment"
tmux set-option -g @lazy_llm_border_git on
git -C "$R" worktree prune

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: <leader>llmw candidates and picker..."
WD=$(claude_wt "$R" agent-d "$P")
cat > "$sandbox/nvim-test.lua" <<LUA
local out = {}
local function log(k, v) table.insert(out, k .. "=" .. tostring(v)) end
local M = require("lazy_llm_worktree")
local pane_wt = ""
M.visible_ai_pane = function() return "$P" end
M.visible_pane_worktree = function() return pane_wt end
local picked, notes = nil, {}
vim.notify = function(msg) table.insert(notes, msg) end
vim.ui.select = function(items, opts, cb)
  local labels = {}
  for _, c in ipairs(items) do table.insert(labels, opts.format_item(c)) end
  log("select", table.concat(labels, "|"))
  cb(items[picked])
end
local function names(list) local t = {} for _, c in ipairs(list) do table.insert(t, c.dir) end return table.concat(t, "|") end

local cw = M.claude_worktrees("$R", "$P")
log("claude", #cw)
log("claude1", cw[1] and (cw[1].branch .. "@" .. cw[1].path))
log("claude-q", #M.claude_worktrees("$R", "$Q"))
log("claude-none", #M.claude_worktrees("$R", ""))

vim.cmd("edit src/x.lua")
local list, rel = M.candidates(vim.api.nvim_buf_get_name(0), cw)
log("cands-main", names(list))
log("rel", rel)
pane_wt = "$WP"
list = M.candidates(vim.api.nvim_buf_get_name(0), cw)
log("cands-iso", names(list))

vim.api.nvim_win_set_cursor(0, { 3, 0 })
picked = 2
M.toggle()
log("picked-2", vim.api.nvim_buf_get_name(0))
log("cursor", vim.api.nvim_win_get_cursor(0)[1])
list = M.candidates(vim.api.nvim_buf_get_name(0), cw)
log("cands-from-a", names(list))
picked = nil
M.toggle()
log("cancel-stays", vim.api.nvim_buf_get_name(0))

pane_wt = ""
vim.cmd("edit $R/src/x.lua")
log("before-one", "x")
M.claude_worktrees = function() return { cw[1] } end
M.toggle()
log("one-direct", vim.api.nvim_buf_get_name(0))
log("lines", vim.api.nvim_buf_line_count(0))

M.claude_worktrees = function() return {} end
vim.cmd("edit $R/src/x.lua")
M.toggle()
log("none-stays", vim.api.nvim_buf_get_name(0))
log("none-note", notes[#notes])
vim.fn.writefile(out, "$sandbox/nvim-out.txt")
vim.cmd("qa!")
LUA
(cd "$R" && nvim --headless --clean \
    --cmd "set rtp^=$REPO_ROOT/nvim-llm-send-plugin/.config/nvim" \
    -c "luafile $sandbox/nvim-test.lua" >/dev/null 2>&1)
nv=$(cat "$sandbox/nvim-out.txt" 2>/dev/null)
assert_has "$nv" "claude=2" "the pane's live Claude worktrees: agent-a and agent-d (agent-b deleted, agent-c removed)"
assert_has "$nv" "claude1=lazy/agent-a@$WA" "{ branch, path }, sorted by path"
assert_has "$nv" "claude-q=0" "another pane's: none left"
assert_has "$nv" "claude-none=0" "no AI pane: none"
assert_has "$nv" "cands-main=$WA|$WD"$'\n' "from the main copy: the Claude worktrees (main is the current side)"
assert_has "$nv" "rel=/src/x.lua" "the repo-relative path"
assert_has "$nv" "cands-iso=$WP|$WA|$WD"$'\n' "isolated pane: its worktree first, then Claude's"
assert_has "$nv" "select=⎇ pw (this pane's worktree)|⎇ lazy/agent-a (Claude worktree)|⎇ lazy/agent-d (Claude worktree)" "more than one other side: a picker, labelled"
assert_has "$nv" "picked-2=$WA/src/x.lua" "picking opens that worktree's copy"
assert_has "$nv" "cursor=3" "...on the same line"
assert_has "$nv" "cands-from-a=$R|$WP|$WD"$'\n' "from a Claude worktree: main, the pane's, the other Claude one"
assert_has "$nv" "cancel-stays=$WA/src/x.lua" "cancelling the picker stays put"
assert_has "$nv" "one-direct=$WA/src/x.lua" "only one other side: opened directly, no picker"
assert_has "$nv" "lines=5" "...the worktree's own copy"
assert_has "$nv" "none-stays=$R/src/x.lua" "no Claude worktrees: unchanged (shared pane: stays)"
assert_has "$nv" "none-note=The AI pane in view shares the main directory" "...with today's message"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: a pane id from another tmux server owns nothing (lazyLlmPaneServer)..."
# tmux numbers panes from %0 again in each new server: after a restart, a
# leftover worktree's lazyLlmPane can name an unrelated new pane. Three
# worktrees recording pane Q: one made under another server (a forged
# start time), one under this one, one from before lazyLlmPaneServer.
started=$(tmux display -t cws -p '#{start_time}')
WS=$(claude_wt "$R" agent-stale "$Q")
WM=$(claude_wt "$R" agent-match "$Q")
WL=$(claude_wt "$R" agent-legacy "$Q")
assert_equals "$(git -C "$R" config branch.lazy/agent-match.lazyLlmPaneServer)" "$started" \
    "setup: the hook recorded this server's start time"
git -C "$R" config branch.lazy/agent-stale.lazyLlmPaneServer "$((started - 3600))"
git -C "$R" config --unset branch.lazy/agent-legacy.lazyLlmPaneServer
q_owned() { awk -F'\t' -v p="$Q" '$1 == p {print $2}' | sort | tr '\n' ' '; }
want_q="$(printf '%s\n' "$WL" "$WM" | sort | tr '\n' ' ')"
assert_equals "$(lazy_llm_claude_worktree_owners "$R" | q_owned)" "$want_q" \
    "owners: the matching and the legacy one, not the stale one"
assert_equals "$(lazy_llm_claude_worktree_owners "$R" "$started" | q_owned)" "$want_q" \
    "...the same with the start time passed in"
assert_equals "$(lazy_llm_claude_worktree_owners "$R" "1" | q_owned)" "$(printf '%s\n' "$WL" | tr '\n' ' ')" \
    "...and only the legacy one under a server that started at another time"
assert_equals "$(seg "$R" "$Q")" "main $sha local ⎇×2" "border segment: the stale one doesn't count"
assert_equals "$(lazy_llm_git_segment "$R" T D "$Q" "$started" | untag)" "main $sha local ⎇×2" "...nor with the start time passed in"
assert_has "$(border "$Q")" "│ main $sha local ⎇×2 " "llm-pane-border: Q's border ends with ⎇×2"
rows=$("$HOME_BIN/llm-dashboard" --emit-rows cws 2>/dev/null | strip)
assert_has "$(grep "pane:cws:1:$Q" <<< "$rows" | cut -f2)" "⎇×2" "dashboard tree row for Q carries ⎇×2"
# Border cost: llm-pane-border passes the start time, so no tmux call is
# added; given only a pane id, at most one.
mkdir -p "$sandbox/tmuxshim"
real_tmux=$(command -v tmux)
printf '#!/bin/sh\necho "$*" >> "%s/tmuxcalls"\nexec "%s" "$@"\n' "$sandbox" "$real_tmux" > "$sandbox/tmuxshim/tmux"
chmod +x "$sandbox/tmuxshim/tmux"
: > "$sandbox/tmuxcalls"; PATH="$sandbox/tmuxshim:$PATH" lazy_llm_git_segment "$R" T D "$Q" "$started" >/dev/null
assert_equals "$(grep -c '' "$sandbox/tmuxcalls")" "0" "segment with the start time passed: no tmux call"
: > "$sandbox/tmuxcalls"; PATH="$sandbox/tmuxshim:$PATH" lazy_llm_git_segment "$R" T D "$Q" >/dev/null
assert_equals "$(grep -c '' "$sandbox/tmuxcalls")" "1" "segment without it: one tmux call"

owner_of() { (cd "$R" && lazy_llm_gather_worktrees) | awk -F$'\x1f' -v p="$1" '$1 == p {print $8}'; }
assert_equals "$(owner_of "$WS")" "claude:orphaned" "Worktrees tab: the stale one is claude:orphaned"
assert_equals "$(owner_of "$WM")" "claude:cws:$Q" "...the matching one is owned by Q"
assert_equals "$(owner_of "$WL")" "claude:cws:$Q" "...the legacy one too (pane id alone)"
assert_equals "$(owner_of "$WA")" "claude:cws:$P" "...and P's still P's"
tmux split-window -d -t cws -c "$WS" "exec sleep 300"
P3=$(tmux list-panes -t cws -F '#{pane_id}' | grep -vxF -e "$P" -e "$Q" | head -1)
tmux set-option -p -t "$P3" @lazy_llm_wt "$WS"
assert_equals "$(owner_of "$WS")" "pane:cws:$P3" "a live pane running in the stale one still owns it"
tmux kill-pane -t "$P3"

cat > "$sandbox/nvim-test5.lua" <<LUA
local M = require("lazy_llm_worktree")
local out = {}
for _, c in ipairs(M.claude_worktrees("$R", "$Q")) do table.insert(out, c.path) end
vim.fn.writefile({ "q=" .. table.concat(out, "|") }, "$sandbox/nvim-out5.txt")
vim.cmd("qa!")
LUA
(cd "$R" && nvim --headless --clean \
    --cmd "set rtp^=$REPO_ROOT/nvim-llm-send-plugin/.config/nvim" \
    -c "luafile $sandbox/nvim-test5.lua" >/dev/null 2>&1)
assert_equals "$(cat "$sandbox/nvim-out5.txt" 2>/dev/null)" "q=$(printf '%s\n' "$WL" "$WM" | sort | paste -sd'|')" \
    "<leader>llmw candidates: the matching and the legacy one, not the stale one"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: a Claude worktree mid-rebase still shows (Worktrees tab, ⎇×N)..."
# What a conflicted `llm-wt integrate` leaves: HEAD detached, the branch
# only in rebase-merge/head-name, so `worktree list` and %(worktreepath)
# show no branch for it.
WR=$(claude_wt "$R" agent-rebase "$Q")
for n in 1 2; do
    echo "r$n" > "$WR/r$n.txt"; git -C "$WR" add "r$n.txt"; git -C "$WR" commit -qm "r$n"
done
assert_equals "$(seg "$R" "$Q")" "main $sha local ⎇×3" "setup: Q owns three before the rebase"
GIT_SEQUENCE_EDITOR="sed -i '1i break'" git -C "$WR" rebase -i main >/dev/null 2>&1
assert_equals "$(git -C "$WR" branch --show-current)" "" "setup: HEAD is detached mid-rebase"
assert_dir_exists "$(git -C "$WR" rev-parse --path-format=absolute --git-path rebase-merge)" "setup: a rebase is in progress"
assert_equals "$(git -C "$R" for-each-ref --format='%(worktreepath)' refs/heads/lazy/agent-rebase)" "" \
    "setup: %(worktreepath) is empty for its branch"
assert_has "$(lazy_llm_claude_worktree_owners "$R")" "$Q"$'\t'"$WR" "owners: the mid-rebase worktree is still Q's"
assert_equals "$(seg "$R" "$Q")" "main $sha local ⎇×3" "border segment: it still counts (⎇×3)"
assert_has "$(border "$Q")" "│ main $sha local ⎇×3 " "llm-pane-border: Q's border still ends with ⎇×3"
row=$( (cd "$R" && lazy_llm_gather_worktrees) | awk -F$'\x1f' -v p="$WR" '$1 == p {print $2 "|" $8}')
assert_equals "$row" "lazy/agent-rebase|claude:cws:$Q" "Worktrees tab: its row is there, on its branch, owned by Q"
# Cost: given the common dir (as the segment passes it), the rebase lookup
# reads files only: the same 4 git calls as with no rebase.
: > "$sandbox/gitcalls"; PATH="$sandbox/gitshim:$PATH" lazy_llm_git_segment "$R" T D "$Q" >/dev/null
assert_equals "$(grep -c '' "$sandbox/gitcalls")" "4" "segment mid-rebase: still 4 git calls (none per worktree)"
# A plain detached HEAD (no rebase) stays skipped, as before.
git -C "$WR" rebase --abort
git -C "$WR" checkout -q --detach
assert_equals "$( (cd "$R" && lazy_llm_gather_worktrees) | awk -F$'\x1f' -v p="$WR" '$1 == p' | grep -c '')" "0" \
    "a plain detached HEAD: no Worktrees tab row"
assert_equals "$(seg "$R" "$Q")" "main $sha local ⎇×2" "...and it doesn't count in ⎇×N"
git -C "$WR" checkout -q lazy/agent-rebase

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
