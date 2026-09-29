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
# (LAZY_LLM_STATE_DIR), and fake `jetski-cli`/`nvim` on PATH that just log how
# they were launched. (osx-google-corp: the AI tool is jetski-cli; this host's
# policy refuses to run anything named `claude`, fakes included, so the
# claude-only adapter cases — registry fallback, --model on resume — are
# covered on main.) The sandbox HOME has no shell rc files, so the pane
# shells keep that PATH. Never touches the user's own server.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="workspace-save-restore-unit"

REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

# Short path: tmux socket paths are limited to ~108 bytes.
# Physical path: on macOS /tmp is a symlink, and git reports worktrees by their real path.
SB=$(cd "$(mktemp -d /tmp/lazy-llm-test-persist-XXXXXX)" && pwd -P)
mkdir -p "$SB/home/.local/bin" "$SB/fake" "$SB/state" "$SB/a" "$SB/b" "$SB/k"
for f in "$REPO_ROOT"/*-bin/.local/bin/*; do ln -s "$f" "$SB/home/.local/bin/"; done
for t in jetski-cli nvim; do
    cat > "$SB/fake/$t" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$t \$* ROLE=\${LAZY_LLM_NVIM_ROLE:-} SESSION=\${LAZY_LLM_NVIM_SESSION:-} RESTORE=\${LAZY_LLM_NVIM_RESTORE:-} PWD=\$PWD WT=\${LAZY_LLM_WORKTREE:-}" >> "$SB/argv.log"
exec sleep 600
EOF
    chmod +x "$SB/fake/$t"
done

# Run a command inside the sandbox environment. The real tools the scripts need
# (tmux, bash 4+, jq, git) come after the fakes, from wherever they're installed:
# on macOS jq is /usr/bin/jq but tmux and bash are Homebrew's (a PATH without
# /opt/homebrew/bin makes lazy-llm-lib.sh prepend it, ahead of the fakes), and
# /usr/bin/git may be an Xcode shim, so /usr/bin and /bin go last.
SYS_PATH=""
for b in tmux bash jq git; do
    d=$(dirname "$(command -v "$b")")
    [[ "$d" == /usr/bin || "$d" == /bin || ":$SYS_PATH:" == *":$d:"* ]] || SYS_PATH="$SYS_PATH:$d"
done
sbx() {
    env -u TMUX -u TMUX_PANE -u CLAUDECODE HOME="$SB/home" TMUX_TMPDIR="$SB" \
        LAZY_LLM_STATE_DIR="$SB/state" XDG_RUNTIME_DIR="$SB/run" \
        PATH="$SB/fake:$SB/home/.local/bin$SYS_PATH:/usr/bin:/bin" "$@"
}
T() { sbx tmux "$@"; }
# Tripwire: never let a launch reach a real AI tool, even after the lib's own
# PATH additions (sourcing it is what the launchers do).
got=$(sbx bash -c "source '$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh' && command -v jetski-cli")
[[ "$got" == "$SB/fake/jetski-cli" ]] || { echo "ABORT: sandbox jetski-cli resolves to '$got', not the fake"; rm -rf "$SB"; exit 1; }
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
sbx lazy-llm -s wsA -d "$SB/a" -t jetski-cli >/dev/null 2>&1
sbx lazy-llm -s wsB -d "$SB/b" -t jetski-cli >/dev/null 2>&1
sleep 1
PP=$(wopt wsA @PROMPT_PANE_ID)
sbx env TMUX_PANE="$PP" llm-add -t jetski-cli >/dev/null
sbx env TMUX_PANE="$PP" llm-add -t jetski-cli >/dev/null
sbx env TMUX_PANE="$PP" llm-cycle 1
sleep 1
read -ra A <<< "$(wopt wsA @AI_PANES)"
for i in 0 1 2; do
    printf '{"conversationId":"conv-a%s","invocationNum":0}' "$i" \
        | sbx env TMUX_PANE="${A[$i]}" llm-jetski-hook working >/dev/null
done
sbx bash -c "source \$HOME/.local/bin/lazy-llm-lib.sh; lazy_llm_set_pane_model ${A[1]} 'claude-opus-5-5[1m]'"
PB=$(wopt wsB @AI_PANE_ID)
printf '{"conversationId":"conv-b","invocationNum":0}' | sbx env TMUX_PANE="$PB" llm-jetski-hook working >/dev/null
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
    '[["jetski-cli","alpha","conv-a0"],["jetski-cli","beta","conv-a1"],["jetski-cli","gamma","conv-a2"]]' "wsA panes: tools, names, hook-recorded conversations"
assert_equals "$(jq -r '.windows[0].panes[1].model' "$fA")" "claude-opus-5-5[1m]" "raw model id saved"
assert_equals "$(jq -r '.windows[0].visible' "$fA")" "1" "visible pane index saved"
assert_equals "$(jq -r '.windows[0].panes[0].conv' "$fB")" "conv-b" "wsB's hook-recorded conversation"
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
assert_equals "$(wopt wsA @AI_TOOLS)" "jetski-cli jetski-cli jetski-cli" "wsA tools"
assert_equals "$(wopt wsA @AI_PANE_NAMES)" "alpha beta gamma" "wsA display names"
assert_equals "$(wopt wsA @AI_PANE_IDX)" "1" "wsA visible pane"
read -ra RA <<< "$(wopt wsA @AI_PANES)"
assert_equals "${#RA[@]}" "3" "wsA has 3 AI panes"
assert_equals "$(T list-windows -t =wsA -F '#{window_name}:#{@lazy_llm_hold}' | grep -c '^_hold_.*:1$')" "1" "held panes live in a marked hold window"
assert_equals "$(T show-option -qv -t '=wsB:' @lazy_llm_collapsed)" "1" "wsB fold state"
assert_equals "$(T show-option -sv @lazy_llm_ws_order)" "wsB wsA" "dashboard order restored"
log=$(cat "$SB/argv.log")
assert_contains "$log" "jetski-cli --conversation conv-a0 ROLE" "pane 0 resumes its conversation"
assert_contains "$log" "jetski-cli --conversation conv-a1 ROLE" "pane 1 resumes its conversation (no --model: jetski keeps the conversation's own)"
assert_contains "$log" "jetski-cli --conversation conv-a2 ROLE" "pane 2 resumes its conversation"
assert_contains "$log" "jetski-cli --conversation conv-b ROLE" "wsB resumes its conversation"
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
sbx lazy-llm -s wsC -d "$SB/b" -t jetski-cli >/dev/null 2>&1
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
sbx lazy-llm -s wsK -d "$SB/k" -t jetski-cli >/dev/null 2>&1
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
    sbx lazy-llm -s wsX -d "$SB/k" -t jetski-cli >/dev/null 2>&1
    sbx lazy-llm -s wsY -d "$SB/k" -t jetski-cli >/dev/null 2>&1 </dev/null
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
assert_contains "$rows" "↳ jetski-cli alpha · conv conv-a0 · held" "a pane row shows tool, name, conversation, held/visible"
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
# A whole manual save at once (the Saved tab's A on it): every workspace in
# it; the running ones come back as copies, the live ones stay untouched.
before=$(T list-sessions -F '#S' | sort | tr '\n' ' ')
nts1=$(find "$SB/state/snapshots/$ts1" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')
out=$(sbx llm-persist restore --snapshot "$ts1" 2>&1)
assert_equals "$(grep -c '^Restored' <<< "$out")" "$nts1" "restore --snapshot <ts> restores every workspace of that save ($nts1)"
after=$(T list-sessions -F '#S' | sort | tr '\n' ' ')
assert_equals "$(( $(wc -w <<< "$after") - $(wc -w <<< "$before") ))" "$nts1" "...each as a new session, since they're all running"
assert_contains "$out" "a copy" "...as copies, never merged into the live ones"
for s_ in $after; do [[ " $before " == *" $s_ "* ]] || T kill-session -t "=$s_"; done
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
touch -t "$(date -d '20 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-20d +%Y%m%d%H%M)" "$SB/r/.lazy-llm/prompts/prompt-20200101-000001.md" "$SB/r/.lazy-llm/prompts/prompt-20200101-000002.md"
echo 'badd +1 .lazy-llm/prompts/prompt-20200101-000001.md' > "$SB/r/.lazy-llm/sessions/prompt.vim"
sbx lazy-llm -s wsR -d "$SB/r" -t jetski-cli >/dev/null 2>&1
assert_file_exists "$SB/r/.lazy-llm/prompts/prompt-20200101-000001.md" "referenced old prompt file kept"
assert_file_not_exists "$SB/r/.lazy-llm/prompts/prompt-20200101-000002.md" "unreferenced old prompt file removed"

echo ""
echo "Test 14: an isolated pane's worktree is saved and restored (worktree-concurrency-mode)..."
G="$SB/g"; mkdir -p "$G"
gitq() { sbx git -c user.name=t -c user.email=t@t "$@"; }
gitq -C "$G" init -q -b main; echo x > "$G/f"; gitq -C "$G" add f; gitq -C "$G" commit -qm init
sbx lazy-llm -s wsG -d "$G" -t jetski-cli >/dev/null 2>&1
sleep 1
sbx env TMUX_PANE="$(wopt wsG @PROMPT_PANE_ID)" llm-add -t jetski-cli -i >/dev/null 2>&1
sleep 0.5
WTG="$G/.worktrees/.panes/g-wt-1"
read -ra Gp <<< "$(wopt wsG @AI_PANES)"
assert_equals "$(T show-option -pqv -t "${Gp[1]}" @lazy_llm_wt)" "$WTG" "setup: an isolated pane"
printf '{"conversationId":"conv-g1","invocationNum":0}' \
    | sbx env TMUX_PANE="${Gp[1]}" llm-jetski-hook working >/dev/null
sbx llm-persist save >/dev/null
assert_equals "$(jq -c '.windows[0].panes[1].worktree' "$(entry wsG)")" "{\"path\":\"$WTG\",\"branch\":\"lazy/g-wt-1\"}" "the manifest records the pane's worktree"
assert_equals "$(jq -c '.windows[0].panes[0].worktree' "$(entry wsG)")" "null" "a shared pane has none"
reopen_g() {
    sbx llm-persist restore wsG >/dev/null 2>&1
    sleep 1
    read -ra Gp <<< "$(wopt wsG @AI_PANES)"
}
last_g1() { grep "conv-g1\|^jetski-cli  " "$SB/argv.log" | tail -1; }
sbx llm-persist close wsG >/dev/null 2>&1
reopen_g
assert_equals "$(T show-option -pqv -t "${Gp[1]}" @lazy_llm_wt)" "$WTG" "restored: the pane is tagged with its worktree"
assert_contains "$(last_g1)" "jetski-cli --conversation conv-g1 .* PWD=$WTG WT=1" "...resumes its conversation there, with the worktree env"

gsnap=$(find "$SB/state/snapshots" -mindepth 1 -maxdepth 1 -type d -exec basename {} ';' | sort | tail -1)
out=$(sbx llm-persist restore --snapshot "$gsnap" wsG 2>&1)
assert_contains "$out" "as wsG-2 \(a copy: wsG is running\)" "a snapshot of the running workspace comes back as a copy"
read -ra G2 <<< "$(wopt wsG-2 @AI_PANES)"
assert_equals "$(T show-option -pqv -t "${G2[1]}" @lazy_llm_wt)" "$WTG" "...whose isolated pane joins the same worktree"
T kill-session -t =wsG-2

sbx llm-persist close wsG >/dev/null 2>&1
sbx git -C "$G" worktree remove --force "$WTG"
reopen_g
[ -d "$WTG" ] && r="yes" || r="no"
assert_equals "$r" "yes" "worktree deleted, branch kept: recreated on restore"
assert_equals "$(T show-option -pqv -t "${Gp[1]}" @lazy_llm_wt)" "$WTG" "...and the pane is back in it"

sbx llm-persist close wsG >/dev/null 2>&1
sbx git -C "$G" worktree remove --force "$WTG"
sbx git -C "$G" branch -qD lazy/g-wt-1
reopen_g
assert_equals "$(T show-option -pqv -t "${Gp[1]}" @lazy_llm_wt)" "" "worktree and branch gone: the pane comes back shared"
assert_contains "$(grep "^jetski-cli " "$SB/argv.log" | tail -1)" "PWD=$G WT=$" "...fresh, in the workspace dir (its conversation can't resume elsewhere)"

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
