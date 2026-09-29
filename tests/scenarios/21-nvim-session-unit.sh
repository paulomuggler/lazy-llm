#!/usr/bin/env bash
# Test: Unit test for nvim-session-plugin's lazy_llm.session module — rolling
# snapshots (one file, overwritten in place, never emptied by an empty nvim),
# restore (buffers back, deleted files dropped, a prompt nvim never left
# without a prompt file), the prompt role's separate persistence dir, and
# snapshot() over RPC (how `lazy-llm save` reaches already-running nvims).
# Headless nvim with --clean: no user config, only persistence.nvim (from the
# lazy.nvim install) and this repo's module on the runtimepath.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="nvim-session-unit"

REPO_ROOT="$TESTS_DIR/.."
MODULE_RTP="$REPO_ROOT/nvim-session-plugin/.config/nvim"
PERSISTENCE="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/persistence.nvim"

if [ ! -d "$PERSISTENCE" ]; then
    echo "SKIP: persistence.nvim not installed at $PERSISTENCE"
    exit 0
fi

sandbox=$(mktemp -d /tmp/lazy-llm-test-nvs-XXXXXX)
proj="$sandbox/proj"
mkdir -p "$proj/.lazy-llm/prompts" "$sandbox/state" "$sandbox/cfg/nvim/lua/lazy_llm"
ln -s "$MODULE_RTP/lua/lazy_llm/session.lua" "$sandbox/cfg/nvim/lua/lazy_llm/session.lua"
echo "one" > "$proj/.lazy-llm/prompts/prompt-20260101-000001.md"
echo "two" > "$proj/.lazy-llm/prompts/prompt-20260101-000002.md"
snap="$proj/.lazy-llm/sessions/prompt.vim"

# Run a Lua chunk in a clean headless nvim (cwd = the sandbox project);
# whatever it passes to out() is printed as key=value lines.
run_nvim() {
    local chunk="$1"
    shift
    cat > "$sandbox/t.lua" <<EOF
vim.opt.rtp:prepend("$PERSISTENCE")
vim.opt.rtp:prepend("$MODULE_RTP")
local lines = {}
function out(k, v) lines[#lines + 1] = k .. "=" .. tostring(v) end
local s = require("lazy_llm.session")
local ok, err = pcall(function()
$chunk
end)
if not ok then out("error", err) end
vim.fn.writefile(lines, "$sandbox/out")
vim.cmd("qa!")
EOF
    rm -f "$sandbox/out"
    (cd "$proj" && env -u TMUX -u TMUX_PANE XDG_STATE_HOME="$sandbox/state" "$@" \
        timeout 30 nvim --headless --clean -c "luafile $sandbox/t.lua" >/dev/null 2>&1)
    cat "$sandbox/out" 2>/dev/null
}

echo "Test 1: snapshot writes one rolling file..."
r=$(run_nvim '
out("empty", s.snapshot("'"$snap"'"))
out("empty_exists", vim.fn.filereadable("'"$snap"'"))
vim.cmd("edit .lazy-llm/prompts/prompt-20260101-000002.md")
vim.cmd("vsplit .lazy-llm/prompts/prompt-20260101-000001.md")
out("first", s.snapshot("'"$snap"'"))
out("second", s.snapshot("'"$snap"'"))
out("this_session", vim.v.this_session)
')
assert_contains "$r" "empty="$'\n'"empty_exists" "snapshot() with no file buffers returns empty"
assert_contains "$r" "empty_exists=0" "...and writes nothing"
assert_contains "$r" "first=$snap" "snapshot() returns the path"
assert_contains "$r" "second=$snap" "a second snapshot() succeeds too"
assert_equals "$(grep "^this_session=" <<< "$r")" "this_session=" "v:this_session is left alone"
assert_equals "$(ls "$proj/.lazy-llm/sessions")" "prompt.vim" "exactly one file in the sessions dir, no .tmp left"
assert_contains "$(cat "$snap")" "prompt-20260101-000001.md" "snapshot lists the open prompt files"

echo ""
echo "Test 2: an empty nvim never overwrites a good snapshot..."
before=$(cksum < "$snap")
run_nvim 'out("r", s.snapshot("'"$snap"'"))' >/dev/null
assert_equals "$(cksum < "$snap")" "$before" "snapshot file byte-identical after an empty snapshot()"

echo ""
echo "Test 3: restore brings buffers and layout back..."
r=$(run_nvim '
out("restored", s.restore("'"$snap"'"))
local names = {}
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[b].buflisted then names[#names + 1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t") end
end
out("bufs", table.concat(names, ","))
out("wins", #vim.api.nvim_tabpage_list_wins(0))
out("missing", s.restore("'"$sandbox"'/nope.vim"))
')
assert_contains "$r" "restored=true" "restore() returns true for a readable snapshot"
assert_contains "$r" "bufs=prompt-20260101-000002.md,prompt-20260101-000001.md" "both prompt buffers restored"
assert_contains "$r" "wins=2" "split layout restored"
assert_contains "$r" "missing=false" "restore() of a missing file is a no-op"

echo ""
echo "Test 4: deleted files are dropped; the prompt role gets a fresh prompt file..."
rm "$proj/.lazy-llm/prompts/prompt-20260101-000001.md"
r=$(run_nvim '
s.restore("'"$snap"'")
local names = {}
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) ~= "" then names[#names + 1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t") end
end
out("bufs", table.concat(names, ","))
')
assert_equals "$r" "bufs=prompt-20260101-000002.md" "buffer for a deleted file is wiped, the other stays"
rm "$proj/.lazy-llm/prompts/prompt-20260101-000002.md"
r=$(run_nvim '
s.restore("'"$snap"'")
out("cur", vim.fn.expand("%:t"))
' LAZY_LLM_NVIM_ROLE=prompt)
assert_contains "$r" "cur=prompt-[0-9]{8}-[0-9]{6}\.md" "prompt role with nothing left opens a new prompt file"
assert_not_contains "$r" "cur=prompt-20260101-00000" "...not one of the deleted ones"

echo ""
echo "Test 5: the prompt role uses its own persistence session dir..."
r=$(run_nvim '
require("persistence").setup({})
s.use_prompt_session_dir()
out("loaded_path", require("persistence").current())
' LAZY_LLM_NVIM_ROLE=prompt)
assert_contains "$r" "loaded_path=$sandbox/state/nvim/sessions/lazy-llm-prompt/" "already-loaded persistence is repointed"
r=$(run_nvim '
s.use_prompt_session_dir()
require("persistence").setup({})
vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "persistence.nvim" })
out("lazy_path", require("persistence").current())
' LAZY_LLM_NVIM_ROLE=prompt)
assert_contains "$r" "lazy_path=$sandbox/state/nvim/sessions/lazy-llm-prompt/" "persistence loaded later (User LazyLoad) is repointed"
r=$(run_nvim '
require("persistence").setup({})
out("plain_path", require("persistence").current())
')
assert_contains "$r" "plain_path=$sandbox/state/nvim/sessions/%" "without the call, persistence keeps its own dir"

echo ""
echo "Test 6: snapshot() over RPC, into an nvim that never had the module on its rtp..."
# That's the case llm-persist's RPC exists for (an nvim started before the
# plugin was installed): its loader can't find the module, so llm-persist
# loads it by path — mirror that call exactly.
echo "three" > "$proj/.lazy-llm/prompts/prompt-20260101-000003.md"
sock="$sandbox/n.sock"
rpc_snap="$proj/.lazy-llm/sessions/editor.vim"
(cd "$proj" && env -u TMUX -u TMUX_PANE XDG_STATE_HOME="$sandbox/state" \
    nvim --headless --clean --listen "$sock" \
    .lazy-llm/prompts/prompt-20260101-000003.md >/dev/null 2>&1 &)
for _ in $(seq 1 50); do [ -S "$sock" ] && break; sleep 0.1; done
rpc=$(timeout 5 nvim --server "$sock" --remote-expr "luaeval('dofile(_A[1]).snapshot(_A[2])', ['$MODULE_RTP/lua/lazy_llm/session.lua', '$rpc_snap'])" 2>&1)
timeout 5 nvim --server "$sock" --remote-send '<C-\><C-n>:qa!<CR>' >/dev/null 2>&1
assert_equals "$rpc" "$rpc_snap" "remote snapshot() returns the path"
assert_contains "$(cat "$rpc_snap" 2>/dev/null)" "prompt-20260101-000003.md" "remote snapshot holds that nvim's buffer"

echo ""
echo "Test 7: a save's snapshot skips an nvim blocked on input instead of waiting..."
# The case found live: after a reboot, a prompt nvim sat on nvim's
# "-- More --" pager over its swap-file message; every save waited out the
# 2s RPC timeout on it. A pane that's too short for the message forces the
# pager. Needs a terminal, hence tmux.
if command -v tmux >/dev/null 2>&1; then
    blk="$sandbox/blk"; mkdir -p "$blk"; echo hi > "$blk/f.md"
    bt() { env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$blk" tmux "$@"; }
    bt -f /dev/null new-session -d -s a -c "$blk" "nvim --clean --cmd 'set directory=$blk//' f.md"; sleep 1
    bt send-keys -t a ihi Escape; sleep 0.3
    kill -9 $(pgrep -P "$(bt display -t a -p '#{pane_pid}')") 2>/dev/null; sleep 0.5
    bt new-session -d -s b -x 80 -y 8 -c "$blk" "nvim --clean --cmd 'set directory=$blk//' --listen $blk/n.sock f.md"; sleep 1.5
    assert_contains "$(bt capture-pane -p -t b)" "More" "the reopened nvim is waiting in the pager"
    t0=$(date +%s%N)
    env XDG_CONFIG_HOME="$sandbox/cfg" "$REPO_ROOT/lazy-llm-bin/.local/bin/llm-persist" _snapshot-socket "$blk/n.sock" "$blk/snap.vim"
    ms=$(( ($(date +%s%N) - t0) / 1000000 ))
    assert_pattern "$ms" "^[0-9]{1,3}$" "snapshotting a blocked nvim returns at once (${ms}ms), not after the 2s timeout"
    assert_file_not_exists "$blk/snap.vim" "...and skips it"
    bt kill-server 2>/dev/null
fi

rm -rf "$sandbox"

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
