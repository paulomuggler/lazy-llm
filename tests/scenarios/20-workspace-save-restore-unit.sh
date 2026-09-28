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
mkdir -p "$SB/home/.local/bin" "$SB/fake" "$SB/state" "$SB/a" "$SB/b" "$SB/k"
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
    # Background saves (save --async) still running would recreate $SB/state.
    sleep 1
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
assert_contains "$out" "^lazy-llm: saved 2 workspaces, 4/4 conversations · snapshot [0-9-]+ [0-9:]+ \(2 workspaces\)$" "save summary counts workspaces and conversations, and the manual save's snapshot"
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
echo "Test 7: a workspace that vanishes in the same server is closed, not dropped..."
sbx llm-persist save >/dev/null
T kill-session -t =wsA
sbx llm-persist save >/dev/null
fA=$(entry wsA)
assert_not_empty "$(jq -r '.gone // empty' "$fA")" "first it's only marked gone"
out=$(sbx llm-persist restore 2>&1)
assert_contains "$out" "skipped wsA \(closed; restore it by name" "default restore skips it"
assert_contains "$(sbx llm-dashboard --emit-saved-rows 2>/dev/null)" "closed.*wsA" "the Saved tab lists it as closed"
jq '.gone -= 61' "$fA" > "$fA.x" && mv "$fA.x" "$fA"
sbx llm-persist save >/dev/null
assert_equals "$(jq -r .closed "$fA")" "true" "once the grace has passed it's closed (kept)"
assert_file_exists "$fA" "...and still in workspaces/, not dropped"
out=$(sbx llm-persist restore wsA 2>&1)
assert_contains "$out" "Restored wsA" "an explicit restore brings a closed entry back"
assert_equals "$(T show-option -qv -t '=wsA:' @lazy_llm_ws_id)" "$(jq -r .id "$(entry wsA)")" "...with the same id"
assert_equals "$(jq -r .closed "$(entry wsA)")" "false" "...and it's no longer closed"

echo ""
echo "Test 8: lazy-llm close keeps it, lazy-llm kill drops it..."
sbx lazy-llm -s wsK -d "$SB/k" -t claude >/dev/null 2>&1
sleep 1
out=$(sbx llm-persist close wsK 2>&1)
assert_contains "$out" "Closed workspace wsK \(kept" "close reports it kept the workspace"
assert_fails "T has-session -t =wsK" "the session is gone"
fK=$(entry wsK)
assert_equals "$(jq -r .closed "$fK")" "true" "its entry is marked closed"
assert_contains "$(sbx llm-persist saved)" "◇ wsK" "saved lists it as closed"
assert_contains "$(sbx llm-persist find-dir "$SB/k")" "wsK" "the launcher would offer to restore it"
out=$(sbx llm-persist restore --dry-run 2>&1)
assert_equals "$(grep -c '^wsK  (' <<< "$out")" "0" "a plain restore leaves it alone"
assert_contains "$out" "skipped wsK \(closed" "...and says so"
out=$(sbx llm-persist restore wsK 2>&1)
assert_contains "$out" "Restored wsK" "restore by name reopens it"
idB=$(T show-option -qv -t '=wsB:' @lazy_llm_ws_id)
sbx llm-sessions --kill wsB >/dev/null
assert_file_exists "$SB/state/dropped/$idB.json" "a killed workspace is dropped"
assert_file_not_exists "$SB/state/workspaces/$idB.json" "...and out of workspaces/"
assert_not_contains "$(sbx llm-persist saved)" "✕ wsB" "saved hides dropped entries"
assert_contains "$(sbx llm-persist saved --dropped)" "✕ wsB" "...unless asked with --dropped"

echo ""
echo "Test 8b: closing or killing the workspace you're in keeps you in tmux..."
if script -qfc true /dev/null >/dev/null 2>&1; then
    sbx lazy-llm -s wsX -d "$SB/k" -t claude >/dev/null 2>&1
    sbx lazy-llm -s wsY -d "$SB/k" -t claude >/dev/null 2>&1 </dev/null
    sleep 1
    # Attach to wsY first, so it's the most recently used other session.
    ( sbx script -qfc "tmux attach -t =wsY" /dev/null </dev/null >/dev/null 2>&1 & )
    sleep 1
    T switch-client -c "$(T list-clients -F '#{client_name}' | head -1)" -t =wsX
    sleep 0.5
    assert_equals "$(T list-clients -F '#{client_session}')" "wsX" "a client is attached to wsX"
    sbx llm-persist close wsX >/dev/null
    assert_equals "$(T list-clients -F '#{client_session}')" "wsY" "closing wsX moves its client to the last-used session, not out of tmux"
    sbx llm-sessions --kill wsY >/dev/null
    assert_not_empty "$(T list-clients -F '#{client_session}')" "killing wsY moves it on again"
    T detach-client -a 2>/dev/null; T list-clients -F '#{client_name}' | while read -r c; do T detach-client -t "$c"; done
    sbx llm-persist forget wsX >/dev/null 2>&1
fi

echo ""
echo "Test 9: a name collision never merges..."
foreign="$SB/state/workspaces/foreign-id.json"
jq '.id = "foreign-id" | .server = "1-1" | .gone = null' "$SB/state/dropped/$idB.json" > "$foreign"
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
rows=$(sbx llm-dashboard --emit-saved-rows --dropped 2>/dev/null)
assert_contains "$(head -1 <<< "$rows")" "^saved:[^	]*	live" "live entries first"
assert_contains "$rows" "restorable.*wsB-2" "restorable entry listed"
assert_contains "$rows" "dropped.*wsB" "dropped entries listed in the dropped view"
assert_not_contains "$(sbx llm-dashboard --emit-saved-rows 2>/dev/null)" "	dropped	" "...and only there"
idA=$(jq -r .id "$(entry wsA)")
assert_equals "$(sbx llm-dashboard --emit-saved-rows 2>/dev/null | grep -c '^saved-pane:')" "0" "entries are folded by default"
out=$(sbx llm-dashboard --saved-fold-transform _ "saved:$idA" 2>/dev/null)
assert_contains "$out" "^reload-sync\(cat " "z answers with a reload"
assert_equals "$(T show-option -sqv @lazy_llm_saved_open)" "$idA" "z records the entry as open"
rows=$(sbx llm-dashboard --emit-saved-rows 2>/dev/null)
assert_equals "$(grep -c "^saved-pane:$idA:" <<< "$rows")" "3" "an open entry lists its 3 AI panes"
assert_contains "$rows" "↳ claude   alpha · conv conv-a0 · held" "a pane row shows tool, name, conversation, held/visible"
sbx llm-dashboard --saved-fold-transform _ "saved-pane:$idA:0:1" >/dev/null 2>&1
assert_equals "$(T show-option -sqv @lazy_llm_saved_open)" "" "z on a pane row folds its entry back"

echo ""
echo "Test 11b: manual saves write dated snapshots..."
rm -rf "$SB/state/snapshots"
sbx llm-persist save >/dev/null
nsnap() { find "$SB/state/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
assert_equals "$(nsnap)" "1" "a manual save writes a snapshot"
out=$(sbx llm-persist save)
assert_contains "$out" "no changes since the last snapshot" "an unchanged workspace isn't snapshotted again"
assert_equals "$(nsnap)" "1" "...so no second snapshot"
sbx llm-persist save --async; sleep 0.5
assert_equals "$(nsnap)" "1" "autosaves never snapshot"
ts1=$(find "$SB/state/snapshots" -mindepth 1 -maxdepth 1 -type d -exec basename {} ';')
idA=$(jq -r .id "$(entry wsA)")
assert_equals "$(jq -r '[.windows[].panes[]] | length' "$SB/state/snapshots/$ts1/$idA.json")" "3" "the snapshot has wsA's 3 panes"
# Drop a pane from the live wsA: the rolling entry follows, the snapshot doesn't.
sleep 1
PP=$(wopt wsA @PROMPT_PANE_ID)
sbx env TMUX_PANE="$PP" llm-remove -f 2 >/dev/null
sbx llm-persist save >/dev/null
assert_equals "$(nsnap)" "2" "a changed workspace gets a new snapshot"
assert_equals "$(jq -r '[.windows[].panes[]] | length' "$(entry wsA)")" "2" "the rolling entry has 2 panes now"
rows=$(sbx llm-dashboard --emit-saved-rows 2>/dev/null)
assert_contains "$rows" "snap-hdr:$ts1	snaphdr	" "the Saved tab has a divider per manual save"
assert_contains "$rows" "saved:$ts1/$idA	snapshot	" "...with its workspaces under it"
out=$(sbx llm-persist restore --snapshot "$ts1" wsA 2>&1)
assert_contains "$out" "as wsA-2 \(a copy: wsA is running\)" "restoring a snapshot of a running workspace makes a copy"
assert_equals "$(wopt wsA-2 @AI_PANE_NAMES)" "alpha beta gamma" "the copy has all 3 panes of that moment"
assert_equals "$(wopt wsA @AI_PANE_NAMES)" "alpha beta" "the live wsA is untouched"
assert_not_equals() { if [ "$1" != "$2" ]; then ((ASSERTIONS_PASSED++)); print_pass "$3"; else print_fail "$3"; fi; }
assert_not_equals "$(T show-option -qv -t '=wsA-2:' @lazy_llm_ws_id)" "$idA" "the copy has its own id"
# Not running: the snapshot comes back as that workspace itself.
T kill-session -t =wsA-2
out=$(sbx llm-persist close wsA 2>&1)
assert_contains "$out" "Closed workspace wsA" "close wsA before restoring its snapshot"
out=$(sbx llm-persist restore --snapshot "$ts1/$idA" 2>&1)
assert_contains "$out" "Restored wsA from the manual save of [0-9-]+ [0-9:]+$" "a closed workspace restores from its snapshot (not as a copy)"
assert_equals "$(T show-option -qv -t '=wsA:' @lazy_llm_ws_id)" "$idA" "...as itself (same id)"
assert_equals "$(wopt wsA @AI_PANE_NAMES)" "alpha beta gamma" "...with the snapshot's panes"
sbx llm-persist forget --snapshot "$ts1/$idA" >/dev/null
assert_file_not_exists "$SB/state/snapshots/$ts1/$idA.json" "forget --snapshot <ts>/<id> deletes one workspace from a manual save"
sbx llm-persist forget --snapshot "$ts1" >/dev/null
assert_file_not_exists "$SB/state/snapshots/$ts1" "forget --snapshot <ts> deletes the whole manual save"

echo ""
echo "Test 12: removing a pane keeps display names aligned..."
PP=$(wopt wsA @PROMPT_PANE_ID)
T set-option -w -t "=wsA:$(first_win wsA)" @AI_PANE_NAMES "alpha beta gamma"
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
