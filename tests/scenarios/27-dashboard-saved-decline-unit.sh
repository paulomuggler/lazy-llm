#!/usr/bin/env bash
# Test: declining (or escaping) a Saved-tab prompt returns to the dashboard.
#
# The forget prompts (K on a saved entry, on a manual save's divider or on one
# of its workspaces) ended dispatch_action with `[[ yes ]] && …`: answering
# no made that the function's status, and set -e closed the whole dashboard.
# Same class of bug as the Worktrees tab's adopt / close dialogs (1feb369).
#
# Drives the real dashboard (fzf) in a sandbox tmux pane, answers no and Esc
# to every Saved-tab prompt, and checks it's still running, on the Saved tab.
# Also c, K and Enter on a live row whose workspace stopped after the tab was
# drawn (the same `[[ -n "$sname" ]] && …` ended the close/kill and switch
# arms).
#
# Isolation: a private tmux server (TMUX_TMPDIR), a private HOME with the
# repo's bins symlinked in stow's layout, a private manifest dir
# (LAZY_LLM_STATE_DIR), and fake `claude`/`nvim` on PATH. Never touches the
# user's own server.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="dashboard-saved-decline-unit"

unset TMUX TMUX_PANE
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

# Short path: tmux socket paths are limited to ~108 bytes.
SB=$(mktemp -d /tmp/lzs.XXXX)
mkdir -p "$SB/home/.local/bin" "$SB/fake" "$SB/state" "$SB/run" "$SB/a" "$SB/b" "$SB/c" "$SB/d" "$SB/e"
for f in "$REPO_ROOT"/*-bin/.local/bin/*; do ln -s "$f" "$SB/home/.local/bin/"; done
for t in claude nvim; do
    printf '#!/usr/bin/env bash\nexec sleep 600\n' > "$SB/fake/$t"
    chmod +x "$SB/fake/$t"
done
SBPATH="$SB/fake:$SB/home/.local/bin:$(dirname "$(command -v jq)"):$(dirname "$(command -v fzf)"):/usr/bin:/bin"

# Run a command inside the sandbox environment.
sbx() {
    env -u TMUX -u TMUX_PANE -u CLAUDECODE HOME="$SB/home" TMUX_TMPDIR="$SB" \
        LAZY_LLM_STATE_DIR="$SB/state" XDG_RUNTIME_DIR="$SB/run" PATH="$SBPATH" "$@"
}
T() { sbx tmux "$@"; }

cleanup() {
    T kill-server 2>/dev/null
    # Background saves (save --async) still running would recreate $SB/state.
    sleep 1
    rm -rf "$SB"
}
trap cleanup EXIT

strip() { sed 's/\x1b\[[0-9;]*m//g'; }
screen() { T capture-pane -p -t dash 2>/dev/null | strip; }
dash_wait() {  # wait until the dashboard pane shows $1
    local i
    for i in $(seq 1 100); do
        screen | grep -qF -- "$1" && return 0
        sleep 0.1
    done
    return 1
}
# check <message> <command...>: passes when the command succeeds.
check() {
    local msg="$1"; shift
    if "$@"; then ((ASSERTIONS_PASSED++)); print_pass "$msg"; else print_fail "$msg"; fi
}

# (Re)start the dashboard on the Saved tab. When it exits, the pane says so.
dash_start() {
    T respawn-pane -k -t dash \
        "env HOME='$SB/home' TMUX_TMPDIR='$SB' LAZY_LLM_STATE_DIR='$SB/state' XDG_RUNTIME_DIR='$SB/run' PATH='$SBPATH' llm-dashboard --tab saved; echo DASH-EXIT=\$?; sleep 600"
    dash_wait "── manual save"
}
# Move the cursor to the Saved-tab row whose id (fzf's {1}) is $1.
dash_goto() {
    local n i
    n=$(sbx llm-dashboard --emit-saved-rows 2>/dev/null | awk -F'\t' -v id="$1" '$1 == id {print NR - 1; exit}')
    for ((i = 0; i < ${n:-0}; i++)); do T send-keys -t dash Down; done
    sleep 0.3
}
# Press $2 on the row $1.
dash_key_on() { dash_goto "$1"; T send-keys -t dash "$2"; }
# The dashboard is still up, back on the Saved tab, after $1.
assert_back() {
    local i s
    # Give a dying dashboard time to print its exit line.
    for i in $(seq 1 10); do
        s=$(screen)
        [[ "$s" == *DASH-EXIT=* ]] && break
        [[ "$s" == *"── manual save"* && "$s" != *"confirm>"* ]] && break
        sleep 0.1
    done
    sleep 0.5
    s=$(screen)
    if [[ "$s" != *DASH-EXIT=* && "$s" == *"── manual save"* && "$s" != *"confirm>"* ]]; then
        ((ASSERTIONS_PASSED++)); print_pass "$1: the dashboard is back on the Saved tab"
    else
        print_fail "$1: the dashboard is back on the Saved tab"
        echo "  Screen: $(grep -E 'DASH-EXIT|confirm>|manual save' <<< "$s" | head -3)"
    fi
}
# Open the prompt $3 says appears with key $2 on row $1, answer no (Enter on
# its first choice) then Esc, and expect the dashboard back each time.
decline_both() {
    local row="$1" key="$2" prompt="$3" what="$4" answer
    for answer in Enter Escape; do
        dash_start || { print_fail "$what: the dashboard started"; continue; }
        dash_key_on "$row" "$key"
        if dash_wait "$prompt"; then
            T send-keys -t dash "$answer"
            assert_back "$what, $([[ $answer == Enter ]] && echo "answered no" || echo "Esc")"
        else
            print_fail "$what: the prompt '$prompt' appears"
        fi
    done
}

echo "Setup: a live workspace, a closed one, a manual save of both..."
sbx lazy-llm -s wsA -d "$SB/a" -t claude >/dev/null 2>&1
sbx lazy-llm -s wsB -d "$SB/b" -t claude >/dev/null 2>&1
for w in c d e; do sbx lazy-llm -s "ws${w^}" -d "$SB/$w" -t claude >/dev/null 2>&1; done
sleep 1
sbx llm-persist save >/dev/null
sbx llm-persist close wsB >/dev/null 2>&1
T new-session -d -s dash -x 300 -y 50 "sleep 600"
rows=$(sbx llm-dashboard --emit-saved-rows 2>/dev/null)
id_of() { jq -r .id "$(grep -l "\"name\": \"$1\"" "$SB"/state/workspaces/*.json | head -1)"; }
idA=$(id_of wsA); idB=$(id_of wsB); idC=$(id_of wsC); idD=$(id_of wsD); idE=$(id_of wsE)
ts=$(find "$SB/state/snapshots" -mindepth 1 -maxdepth 1 -type d -exec basename {} ';' | head -1)
assert_contains "$rows" "^saved:$idA	live	" "setup: wsA is live"
assert_contains "$rows" "saved:$idB	closed	" "setup: wsB is closed (kept)"
assert_contains "$rows" "snap-hdr:$ts	snaphdr	" "setup: a manual save's divider"
assert_contains "$rows" "saved:$ts/$idB	snapshot	" "setup: ...with wsB in it"
check "setup: the dashboard opens on the Saved tab" dash_start

echo ""
echo "Test 1: K (forget) on a saved entry..."
decline_both "saved:$idB" K "Drop this saved workspace?" "forget"
assert_file_exists "$SB/state/workspaces/$idB.json" "declined: wsB is still saved"

echo ""
echo "Test 2: K on a manual save's divider..."
decline_both "snap-hdr:$ts" K "Delete the manual save of" "forget a manual save"
assert_dir_exists "$SB/state/snapshots/$ts" "declined: the manual save is still there"

echo ""
echo "Test 3: K on a workspace of a manual save..."
decline_both "saved:$ts/$idB" K "Delete this workspace from the manual save?" "forget from a manual save"
assert_file_exists "$SB/state/snapshots/$ts/$idB.json" "declined: wsB is still in the manual save"

echo ""
echo "Test 4: A (restore all) on the rolling entries and on a manual save..."
decline_both "saved:$idB" A "Restore every workspace that died" "restore all"
decline_both "snap-hdr:$ts" A "workspace(s) of the manual save" "restore a manual save"
check "declined: wsB wasn't restored" test -z "$(T list-sessions -F '#S' | grep -x 'wsB.*')"

echo ""
echo "Test 5: c (close) and K (kill) on a live workspace..."
decline_both "saved:$idA" c "Close 'wsA', keeping it saved?" "close"
decline_both "saved:$idA" K "Kill 'wsA' and drop it from Saved?" "kill"
check "declined: wsA is still running" T has-session -t =wsA

echo ""
echo "Test 6: c, K and Enter on a live row whose workspace has stopped since..."
# Killed after the tab was drawn: the row still says live, but there's no
# session to close, kill or switch to.
assert_contains "$rows" "saved:$idE	live	" "setup: wsC, wsD and wsE are live"
dash_start
dash_goto "saved:$idC"
T kill-session -t =wsC
T send-keys -t dash c
assert_back "c on a workspace that stopped"
dash_start
dash_goto "saved:$idD"
T kill-session -t =wsD
T send-keys -t dash K
assert_back "K on a workspace that stopped"
# Enter on a live row switches, which ends the dashboard by design. With no
# session to switch to it still ends, but cleanly: set -e's exit is 1.
dash_start
dash_goto "saved:$idE"
T kill-session -t =wsE
T send-keys -t dash Enter
check "Enter on a workspace that stopped: the dashboard ends cleanly (exit 0)" dash_wait "DASH-EXIT=0"

echo ""
echo "Test 7: answering yes still acts, and comes back..."
dash_start
dash_key_on "saved:$ts/$idB" K
dash_wait "Delete this workspace from the manual save?"
T send-keys -t dash Down Enter
assert_back "forget from a manual save, answered yes"
assert_file_not_exists "$SB/state/snapshots/$ts/$idB.json" "yes: wsB is gone from the manual save"
dash_start
dash_key_on "saved:$idB" K
dash_wait "Drop this saved workspace?"
T send-keys -t dash Down Enter
assert_back "forget, answered yes"
assert_file_exists "$SB/state/dropped/$idB.json" "yes: wsB is dropped"

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
