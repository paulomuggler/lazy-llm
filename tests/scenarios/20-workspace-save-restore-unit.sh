#!/usr/bin/env bash
# Test: workspace save/restore (llm-persist) end to end, against an isolated
# tmux server. Builds two workspaces through the real launcher and llm-add,
# saves them, kills the server, restores, and checks every piece of state
# lazy-llm keeps in tmux options comes back — plus the retention rules
# (no-server no-op, same-server close grace, explicit kill), name
# collisions, find-dir, the dashboard's saved rows, and nvim snapshot and
# prompt-file handling.
#
# Isolation: a private tmux server (TMUX_TMPDIR), a private HOME with the
# repo's bins symlinked in stow's layout, a private manifest dir
# (LAZY_LLM_STATE_DIR), and fake `claude`/`nvim` on PATH that just log how
# they were launched. The sandbox HOME has no shell rc files, so the pane
# shells keep that PATH. Never touches the user's own server.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="workspace-save-restore-unit"

REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

# Short path: tmux socket paths are limited to ~108 bytes.
SB=$(mktemp -d /tmp/lazy-llm-test-persist-XXXXXX)
mkdir -p "$SB/home/.local/bin" "$SB/fake" "$SB/state" "$SB/a" "$SB/b"
for f in "$REPO_ROOT"/*-bin/.local/bin/*; do ln -s "$f" "$SB/home/.local/bin/"; done
for t in claude nvim; do
    cat > "$SB/fake/$t" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$t \$* ROLE=\${LAZY_LLM_NVIM_ROLE:-} SESSION=\${LAZY_LLM_NVIM_SESSION:-} RESTORE=\${LAZY_LLM_NVIM_RESTORE:-} PWD=\$PWD" >> "$SB/argv.log"
exec sleep 600
EOF
    chmod +x "$SB/fake/$t"
done

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

cleanup() {
    T kill-server 2>/dev/null
    rm -rf "$SB"
}
trap cleanup EXIT

echo "Test 1: build two workspaces..."
sbx lazy-llm -s wsA -d "$SB/a" -t claude >/dev/null 2>&1
sbx lazy-llm -s wsB -d "$SB/b" -t claude >/dev/null 2>&1
sleep 1
PP=$(wopt wsA @PROMPT_PANE_ID)
sbx env TMUX_PANE="$PP" llm-add -t claude >/dev/null
sbx env TMUX_PANE="$PP" llm-add -t claude >/dev/null
sbx env TMUX_PANE="$PP" llm-cycle 1
sleep 1
read -ra A <<< "$(wopt wsA @AI_PANES)"
for i in 0 1 2; do
    printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"conv-a%s"}' "$i" \
        | sbx env TMUX_PANE="${A[$i]}" llm-claude-hook
done
sbx bash -c "source \$HOME/.local/bin/lazy-llm-lib.sh; lazy_llm_set_pane_model ${A[1]} 'claude-opus-5-5[1m]'"
# wsB's pane: no hook record, only Claude Code's registry file.
PB=$(wopt wsB @AI_PANE_ID)
CPID=$(pgrep -P "$(T display-message -t "$PB" -p '#{pane_pid}')" | head -1)
mkdir -p "$SB/home/.claude/sessions"
echo "{\"pid\":$CPID,\"sessionId\":\"conv-b-registry\"}" > "$SB/home/.claude/sessions/$CPID.json"
T set-option -w -t "=wsA:$(first_win wsA)" @AI_PANE_NAMES "alpha beta gamma"
T set-option -t "=wsB:" @lazy_llm_collapsed 1
sbx bash -c 'source $HOME/.local/bin/lazy-llm-lib.sh; lazy_llm_move_ws_order wsB up'
# wsA has an editor snapshot to restore; wsB a prompt snapshot.
mkdir -p "$SB/a/.lazy-llm/sessions" "$SB/b/.lazy-llm/sessions"
echo '" editor' > "$SB/a/.lazy-llm/sessions/editor.vim"
echo '" prompt' > "$SB/b/.lazy-llm/sessions/prompt.vim"
PROMPT_A=$(wopt wsA @lazy_llm_prompt_file)
log=$(cat "$SB/argv.log")
assert_contains "$log" "nvim  ROLE=editor SESSION=$SB/a/.lazy-llm/sessions/editor.vim RESTORE= " "editor nvim launched with its role and snapshot path, no restore"
assert_contains "$log" "startinsert $PROMPT_A ROLE=prompt SESSION=$SB/a/.lazy-llm/sessions/prompt.vim RESTORE= " "prompt nvim on a new prompt file when there's no snapshot yet"

echo ""
echo "Test 2: save..."
out=$(sbx llm-persist save)
assert_equals "$out" "lazy-llm: saved 2 workspaces, 4/4 conversations" "save summary counts workspaces and conversations"
fA=$(entry wsA); fB=$(entry wsB)
assert_equals "$(jq -c '[.windows[0].panes[] | [.tool, .name, .conv]]' "$fA")" \
    '[["claude","alpha","conv-a0"],["claude","beta","conv-a1"],["claude","gamma","conv-a2"]]' "wsA panes: tools, names, hook-recorded conversations"
assert_equals "$(jq -r '.windows[0].panes[1].model' "$fA")" "claude-opus-5-5[1m]" "raw model id saved"
assert_equals "$(jq -r '.windows[0].visible' "$fA")" "1" "visible pane index saved"
assert_equals "$(jq -r '.windows[0].panes[0].conv' "$fB")" "conv-b-registry" "registry fallback supplies wsB's conversation"
assert_equals "$(jq -r '[.order, .collapsed] | @tsv' "$fB")" "0	true" "wsB saved first in order, folded"
assert_equals "$(jq -r .server "$fA")" "$(jq -r .server "$fB")" "both entries stamped with the same server"

echo ""
echo "Test 3: save with no server running changes nothing..."
T kill-server
sleep 0.5
before=$(cat "$SB"/state/workspaces/*.json | cksum)
sbx llm-persist save >/dev/null
assert_equals "$(cat "$SB"/state/workspaces/*.json | cksum)" "$before" "manifest byte-identical after a no-server save"
assert_contains "$(sbx llm-persist saved)" "◌ wsB" "saved lists entries as restorable with no server"

echo ""
echo "Test 4: restore..."
: > "$SB/argv.log"
out=$(sbx llm-persist restore 2>&1)
sleep 1
assert_contains "$out" "Restored wsB" "wsB restored"
assert_contains "$out" "Restored wsA" "wsA restored"
assert_equals "$(T show-option -qv -t '=wsA:' @lazy_llm_ws_id)" "$(jq -r .id "$fA")" "workspace id carried over"
assert_equals "$(T show-option -qv -t '=wsA:' @lazy_llm)" "1" "restored session is lazy-llm managed"
assert_equals "$(wopt wsA @AI_TOOLS)" "claude claude claude" "wsA tools"
assert_equals "$(wopt wsA @AI_PANE_NAMES)" "alpha beta gamma" "wsA display names"
assert_equals "$(wopt wsA @AI_PANE_IDX)" "1" "wsA visible pane"
read -ra RA <<< "$(wopt wsA @AI_PANES)"
assert_equals "${#RA[@]}" "3" "wsA has 3 AI panes"
assert_equals "$(T list-windows -t =wsA -F '#{window_name}:#{@lazy_llm_hold}' | grep -c '^_hold_.*:1$')" "1" "held panes live in a marked hold window"
assert_equals "$(T show-option -qv -t '=wsB:' @lazy_llm_collapsed)" "1" "wsB fold state"
assert_equals "$(T show-option -sv @lazy_llm_ws_order)" "wsB wsA" "dashboard order restored"
log=$(cat "$SB/argv.log")
assert_contains "$log" "claude --resume conv-a0 ROLE" "pane 0 resumes its conversation"
assert_contains "$log" "claude --resume conv-a1 --model claude-opus-5-5\[1m\] ROLE" "pane 1 resumes with its model"
assert_contains "$log" "claude --resume conv-a2 ROLE" "pane 2 resumes its conversation"
assert_contains "$log" "claude --resume conv-b-registry ROLE" "wsB resumes the registry-sourced conversation"
assert_contains "$log" "nvim  ROLE=editor SESSION=$SB/a/.lazy-llm/sessions/editor.vim RESTORE=1 " "wsA editor restores its snapshot"
assert_contains "$log" "startinsert $PROMPT_A ROLE=prompt" "wsA prompt nvim reopens the saved prompt file"
assert_contains "$log" "startinsert ROLE=prompt SESSION=$SB/b/.lazy-llm/sessions/prompt.vim RESTORE=1 " "wsB prompt nvim restores its snapshot, no file argument"
rows=$(sbx llm-dashboard --emit-rows 2>/dev/null | cut -f1)
assert_equals "$(head -1 <<< "$rows")" "ws:wsB" "dashboard lists wsB first"
assert_equals "$(grep -c '^pane:wsB:' <<< "$rows")" "0" "folded wsB shows no pane rows"
assert_equals "$(grep -c '^pane:wsA:' <<< "$rows")" "3" "wsA shows its 3 pane rows"
assert_equals "$(jq '[.windows[].panes[] | select(.conv != null)] | length' "$(entry wsA)")" "3" "post-restore save keeps the conversations"

echo ""
echo "Test 5: restore again is a no-op..."
out=$(sbx llm-persist restore 2>&1)
assert_contains "$out" "Nothing to restore" "nothing left to restore"
assert_equals "$(T list-sessions | wc -l | tr -d ' ')" "2" "still exactly two sessions"

echo ""
echo "Test 6: a prompt snapshot restores on a plain launch too..."
: > "$SB/argv.log"
sbx lazy-llm -s wsC -d "$SB/b" -t claude >/dev/null 2>&1
sleep 1
log=$(cat "$SB/argv.log")
assert_contains "$log" "startinsert ROLE=prompt SESSION=$SB/b/.lazy-llm/sessions/prompt.vim RESTORE=1 " "fresh launch in the dir restores the prompt snapshot"
assert_contains "$log" "nvim  ROLE=editor SESSION=[^ ]* RESTORE= " "...but not the editor's"
T kill-session -t =wsC

echo ""
echo "Test 7: closing a workspace in the same server..."
sbx llm-persist save >/dev/null
T kill-session -t =wsA
sbx llm-persist save >/dev/null
fA=$(entry wsA)
assert_not_empty "$(jq -r '.gone // empty' "$fA")" "a same-server close is only marked gone"
out=$(sbx llm-persist restore 2>&1)
assert_contains "$out" "skipped wsA \(closed in this tmux server" "default restore skips it"
assert_contains "$(sbx llm-dashboard --emit-saved-rows --closed 2>/dev/null)" "closed.*wsA" "Saved tab's closed view lists it"
jq '.gone -= 61' "$fA" > "$fA.x" && mv "$fA.x" "$fA"
sbx llm-persist save >/dev/null
assert_file_exists "$SB/state/closed/$(basename "$fA")" "closed for good once the grace has passed"
out=$(sbx llm-persist restore wsA 2>&1)
assert_contains "$out" "Restored wsA" "an explicit restore brings a closed entry back"
assert_equals "$(T show-option -qv -t '=wsA:' @lazy_llm_ws_id)" "$(jq -r .id "$(entry wsA)")" "...with the same id"

echo ""
echo "Test 8: lazy-llm kill forgets immediately..."
idB=$(T show-option -qv -t '=wsB:' @lazy_llm_ws_id)
sbx llm-sessions --kill wsB >/dev/null
assert_file_exists "$SB/state/closed/$idB.json" "killed workspace moved to closed/"
assert_file_not_exists "$SB/state/workspaces/$idB.json" "...and out of workspaces/"

echo ""
echo "Test 9: a name collision never merges..."
foreign="$SB/state/workspaces/foreign-id.json"
jq '.id = "foreign-id" | .server = "1-1" | .gone = null' "$SB/state/closed/$idB.json" > "$foreign"
T new-session -d -s wsB -c "$SB/b"
out=$(sbx llm-persist restore 2>&1)
assert_contains "$out" "Restored wsB as wsB-2" "restored under a de-duplicated name"
assert_equals "$(T show-option -qv -t '=wsB-2:' @lazy_llm_ws_id)" "foreign-id" "wsB-2 is the saved workspace"
assert_equals "$(T list-panes -t =wsB | wc -l | tr -d ' ')" "1" "the live wsB is untouched"

echo ""
echo "Test 10: find-dir..."
T kill-session -t =wsB-2
jq '.server = "1-1" | .gone = null' "$foreign" > "$SB/x" && mv "$SB/x" "$foreign"
assert_contains "$(sbx llm-persist find-dir "$SB/b")" "foreign-id	wsB-2	1 AI pane, 1 conversation" "find-dir reports a restorable entry for the dir"
assert_empty "$(sbx llm-persist find-dir "$SB/a")" "nothing for a dir whose workspace is live"

echo ""
echo "Test 11: the Saved tab's rows..."
rows=$(sbx llm-dashboard --emit-saved-rows --closed 2>/dev/null)
assert_contains "$(head -1 <<< "$rows")" "^saved:[^	]*	live" "live entries first"
assert_contains "$rows" "restorable.*wsB" "restorable entry listed"
assert_contains "$rows" "closed" "closed entries listed in the closed view"

echo ""
echo "Test 12: removing a pane keeps display names aligned..."
PP=$(wopt wsA @PROMPT_PANE_ID)
sbx env TMUX_PANE="$PP" llm-remove -f 1 >/dev/null
assert_equals "$(wopt wsA @AI_PANE_NAMES)" "alpha gamma" "the removed pane's name goes with it"

echo ""
echo "Test 13: retention keeps prompt files a snapshot references..."
mkdir -p "$SB/r/.lazy-llm/prompts" "$SB/r/.lazy-llm/sessions"
touch -d '20 days ago' "$SB/r/.lazy-llm/prompts/prompt-20200101-000001.md" "$SB/r/.lazy-llm/prompts/prompt-20200101-000002.md"
echo 'badd +1 .lazy-llm/prompts/prompt-20200101-000001.md' > "$SB/r/.lazy-llm/sessions/prompt.vim"
sbx lazy-llm -s wsR -d "$SB/r" -t claude >/dev/null 2>&1
assert_file_exists "$SB/r/.lazy-llm/prompts/prompt-20200101-000001.md" "referenced old prompt file kept"
assert_file_not_exists "$SB/r/.lazy-llm/prompts/prompt-20200101-000002.md" "unreferenced old prompt file removed"

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
