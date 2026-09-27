#!/usr/bin/env bash
# lazy-llm-lib.sh — Shared library for lazy-llm pane resolution
# Source this file: source "$(dirname "$0")/lazy-llm-lib.sh"

# Guard against double-sourcing
[[ -n "${_LAZY_LLM_LIB_LOADED:-}" ]] && return 0
_LAZY_LLM_LIB_LOADED=1

# Resolve current pane ID.
# TMUX_PANE is set in interactive shells but NOT in tmux run-shell context.
# Fallback to tmux display-message -p which works in both contexts.
# Sets: _CURRENT_PANE
lazy_llm_resolve_pane() {
  _CURRENT_PANE="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}' 2>/dev/null)}"
  if [[ -z "$_CURRENT_PANE" ]]; then
    echo "Error: Not inside a tmux session" >&2
    return 1
  fi
}

# Resolve session and window from current pane.
# Sets: _SESSION, _WINDOW
# Requires: _CURRENT_PANE (call lazy_llm_resolve_pane first)
lazy_llm_resolve_session_window() {
  if [[ -z "$_CURRENT_PANE" ]]; then
    echo "Error: _CURRENT_PANE not set. Call lazy_llm_resolve_pane first." >&2
    return 1
  fi
  _SESSION=$(tmux display-message -t "$_CURRENT_PANE" -p '#S' 2>/dev/null)
  _WINDOW=$(tmux display-message -t "$_CURRENT_PANE" -p '#I' 2>/dev/null)
  if [[ -z "$_SESSION" ]] || [[ -z "$_WINDOW" ]]; then
    echo "Error: Could not determine session/window" >&2
    return 1
  fi
}

# Get AI pane target.
# Prefer stable pane ID (@AI_PANE_ID), fall back to legacy index (@AI_PANE), then :.+
# Also sets AI_TOOL from window option.
# Echoes: target pane reference
# Requires: _SESSION, _WINDOW
lazy_llm_get_ai_target() {
  local ai_pane_id ai_pane
  ai_pane_id=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_PANE_ID 2>/dev/null) || true
  ai_pane=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_PANE 2>/dev/null) || true
  AI_TOOL=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_TOOL 2>/dev/null) || true
  echo "${ai_pane_id:-${ai_pane:-:.+}}"
}

# Get prompt pane target.
# Prefer stable pane ID (@PROMPT_PANE_ID), fall back to legacy index (@PROMPT_PANE), then :.2
# Echoes: target pane reference
# Requires: _SESSION, _WINDOW
lazy_llm_get_prompt_target() {
  local prompt_pane_id prompt_pane
  prompt_pane_id=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @PROMPT_PANE_ID 2>/dev/null) || true
  prompt_pane=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @PROMPT_PANE 2>/dev/null) || true
  echo "${prompt_pane_id:-${prompt_pane:-:.2}}"
}

# Read all multi-pane state into variables.
# Sets: AI_PANES, AI_TOOLS, AI_PANE_IDX, AI_HOLD_WIN, AI_TOOL, AI_PANE_NAMES
# Requires: _SESSION, _WINDOW
lazy_llm_read_multi_state() {
  AI_PANES=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_PANES 2>/dev/null) || true
  AI_TOOLS=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_TOOLS 2>/dev/null) || true
  AI_PANE_IDX=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_PANE_IDX 2>/dev/null) || true
  AI_HOLD_WIN=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_HOLD_WIN 2>/dev/null) || true
  AI_TOOL=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_TOOL 2>/dev/null) || true
  AI_PANE_NAMES=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_PANE_NAMES 2>/dev/null) || true
}

# Check if a tmux pane is still alive.
# Returns 0 if alive, 1 if dead. Doesn't trust the exit status: tmux 3.7c's
# display-message exits 0 with empty output for a pane that no longer exists
# (confirmed live). A %N id must echo back as itself; any other target form
# (legacy "session:win.idx", ":.+") must resolve to some pane.
lazy_llm_validate_pane() {
  local got
  got=$(tmux display-message -t "$1" -p '#{pane_id}' 2>/dev/null) || return 1
  if [[ "$1" == %* ]]; then
    [[ "$got" == "$1" ]]
  else
    [[ -n "$got" ]]
  fi
}

# Classify AI pane content into a status.
# Pure: no tmux side effects. Reads pane content from stdin.
# Args:   $1 tool_name (default: claude)
# Stdin:  pane content
# Stdout: working | idle | waiting | unknown
#
# Precedence: working (interrupt hint visible) > waiting (permission prompt)
# > idle (prompt glyph alone) > unknown.
#
# Per-tool overrides go in the case block below. Today only the default
# (claude-tuned) patterns are used; gemini/codex/grok/aider fall through
# because they typically use similar prompt + permission idioms.
lazy_llm_detect_status_from_content() {
  local content
  IFS= read -rd '' content || true
  _lazy_llm_classify_content "${1:-claude}" "$content"
  printf '%s\n' "$REPLY"
}

# The classifier itself. Fork-free (bash regex, no grep/tail): the status
# bar, pane borders and dashboard run it for every AI pane on every refresh,
# and each forked grep was a measurable share of the dashboard's open and
# fold/reorder latency. Sets REPLY instead of echoing.
# Args: $1 tool_name  $2 pane content
_lazy_llm_classify_content() {
  local tool="${1:-claude}" content="$2"

  # "ctrl+c to interrupt" was this pattern's original signal but current Claude
  # Code UI versions don't show it — confirmed live against a real busy session:
  # the actual "working" tells are the spinner/duration line ("Boondoggling…
  # (6m 42s · ↓ 22.4k tokens)", or "(42s · …" under a minute) always present
  # while generating, and "esc to interrupt" in the footer. Match all of them
  # so this survives future UI wording changes better than any single string.
  local interrupt_pat='ctrl\+c to interrupt|esc to interrupt|\([0-9]+m [0-9]+s|\([0-9]+s ·'
  local waiting_pat='\[[yY]/[yYnN]\]|^[[:space:]]*[1-9][.)][[:space:]]'
  local prompt_pat='❯'

  case "$tool" in
    claude|*)
      : # use defaults above
      ;;
  esac

  # Both patterns are scoped to the bottom of the capture — the current
  # frame (spinner, input box, footer) — never the whole 200-line capture.
  #
  # working: Claude Code's redraws (resizes, popups over the pane, a pane
  # too short for its frame) push stale frames into scrollback, spinner
  # line included. Matched over the full capture, one such remnant ("*
  # Perambulating… (9m 43s", 176 lines up in a pane that had finished) read
  # as "working" until it scrolled out — confirmed live; that's the "stuck
  # on working, never shows unread" report (unread only layers on idle).
  # The live spinner and the footer's "esc to interrupt" are always within
  # the last 15 lines.
  #
  # waiting: the numbered-option alternative (Claude Code's permission
  # prompt, "1. Yes  2. Yes, and don't ask again  3. No") is
  # indistinguishable from an ordinary markdown numbered list in a finished
  # response — confirmed live, a response ending in "1. … 2. … 3. …" read as
  # "waiting". A real prompt is at the bottom; tuned against that exact
  # false positive: a tail of 15 still caught 2 of its 3 list lines, 12 and
  # 10 caught none.
  local -a lines
  mapfile -t lines <<< "$content"
  local n=${#lines[@]} i working=false waiting=false
  for (( i = (n > 15 ? n - 15 : 0); i < n; i++ )); do
    [[ "${lines[i]}" =~ $interrupt_pat ]] && working=true
    (( i >= n - 10 )) && [[ "${lines[i]}" =~ $waiting_pat ]] && waiting=true
  done

  if $working; then
    REPLY=working
  elif $waiting; then
    REPLY=waiting
  elif [[ "$content" == *"$prompt_pat"* ]]; then
    REPLY=idle
  else
    REPLY=unknown
  fi
}

# Freshness window (seconds) for a hook-written status file to be trusted.
# Long enough to survive one status-bar refresh interval (status-interval
# default 15s), short enough that a status file from a since-closed pane, or
# one that's gone stale mid-generation, doesn't lie for long — see
# lazy_llm_detect_pane_status below.
_LAZY_LLM_HOOK_STATUS_MAX_AGE=30

# Read a Claude Code hook-written status for a pane, if fresh.
# Written by llm-claude-hook (via lazy-llm's Claude Code plugin) on the
# UserPromptSubmit (-> working), Notification:permission_prompt (-> waiting —
# genuinely blocked on a decision) and Notification:idle_prompt / Stop
# (-> idle) hook events.
# idle_prompt deliberately maps to "idle", not "waiting" — it's Claude
# Code's own delayed idle nudge, not a new blocking state; mapping it to
# "waiting" was overwriting Stop's correct "idle" and is why finished
# sessions used to get stuck showing waiting (see the hook script's own
# comment for the full story). "working" comes from UserPromptSubmit: without
# it, a prompt typed within 30s of the last Stop read as idle/unread until
# the Stop file aged out. Past the freshness window a long turn falls
# through to the content scrape, which sees the live spinner/footer.
# Args:   $1 pane_id
# Stdout: working | waiting | idle   (only if a fresh file says so)
# Returns 1 (nothing echoed) if no usable hook file exists.
_lazy_llm_read_hook_status() {
  local pane_id="$1"
  local status_file="$HOME/.cache/lazy-llm/status/$pane_id"
  [[ -f "$status_file" ]] || return 1

  local hook_state hook_ts
  read -r hook_state hook_ts < "$status_file" 2>/dev/null || return 1
  [[ "$hook_state" == "working" || "$hook_state" == "waiting" || "$hook_state" == "idle" ]] || return 1
  [[ "$hook_ts" =~ ^[0-9]+$ ]] || return 1

  local now age
  now=${EPOCHSECONDS:-$(date +%s)}
  age=$((now - hook_ts))
  [[ "$age" -ge 0 && "$age" -le "$_LAZY_LLM_HOOK_STATUS_MAX_AGE" ]] || return 1

  echo "$hook_state"
  return 0
}

# Capture a pane's recent content and classify it.
# Args:   $1 pane_id   (required, %N format)
#         $2 tool_name (optional, default: claude)
# Stdout: working | waiting | unread | idle | unknown
# Returns 0 always; emits "unknown" if capture fails.
#
# For tool=claude, prefers a fresh hook-written status (see
# _lazy_llm_read_hook_status) over the content scrape below — hooks are
# event-driven and don't suffer the scrape's timing/UI-text fragility.
# Every other tool (gemini/codex/grok/aider) always uses the scrape path.
#
# "unread" is layered on top of an "idle" result — see the unread-marker
# section below for what sets and clears it.
lazy_llm_detect_pane_status() {
  local pane_id="${1:?pane_id required}"
  local tool="${2:-claude}"
  local base

  if [[ "$tool" == "claude" ]] && base=$(_lazy_llm_read_hook_status "$pane_id"); then
    # `if cmd=$(...); then` (not `cmd=$(...) && ...`) — a bare `&&` here would
    # trip callers' `set -e` on the common case of no hook file existing yet.
    :
  else
    local content
    content=$(tmux capture-pane -p -t "$pane_id" -S -200 2>/dev/null) || { echo unknown; return 0; }
    _lazy_llm_classify_content "$tool" "$content"
    base="$REPLY"
  fi

  _lazy_llm_apply_unread "$pane_id" "$tool" "$base"
}

# ──────────────────────────────────────────────────────────────────────────
# Unread markers — "finished a turn, and you haven't looked at it since".
#
# Splits what used to be one "idle" state in two: a pane whose output is
# sitting there waiting for you to read it and respond ("unread", ◉) vs one
# you've already dealt with and that has nothing left to do ("idle", ○).
#
# A marker file ~/.cache/lazy-llm/unread/<pane_id> holds the pane's
# #{pane_pid} — tmux reuses %N ids after a server restart, and a marker for
# a dead pane must not light up whatever new pane inherits its id. No
# age-out: a turn that finished overnight is still unread in the morning.
#
# Set by:
#   - Claude's Stop hook (llm-claude-hook, via
#     lazy_llm_mark_unread) — event-driven, catches even sub-second turns.
#   - Every other tool: a working -> idle transition seen by the scrape (a
#     "busy" marker left by an earlier "working" observation). Only as fast
#     as the pollers (status-interval), so a turn shorter than that can be
#     missed. Not used for claude: the scrape's working pattern can flicker
#     on old scrollback, which would re-mark a pane right after you'd
#     cleared it; the hook has no such problem.
#   Both skip a pane that's focused in an attached client — you watched it
#   finish, there's nothing unread about it.
# Cleared by lazy_llm_clear_unread, called wherever you actually engage the
# pane: focusing it (llm-pane-focus-track), cycling it into view
# (lazy_llm_cycle_to_index), sending it a prompt (llm-send — the prompt
# buffer workflow never focuses the AI pane), or picking it in the
# dashboard tree. Deliberately NOT cleared by the pane starting to work
# again: that's always preceded by one of the above, or it's the agent
# resuming on its own, in which case it'll stop again and be unread again.
# ──────────────────────────────────────────────────────────────────────────
_LAZY_LLM_UNREAD_DIR="$HOME/.cache/lazy-llm/unread"
_LAZY_LLM_BUSY_DIR="$HOME/.cache/lazy-llm/busy"

_lazy_llm_pane_pid() {
  tmux display-message -t "$1" -p '#{pane_pid}' 2>/dev/null
}

# Is this the pane the user is looking at right now: the active pane of the
# active window of a session shown by a client whose terminal has focus?
# The terminal-focus part is tmux's own "focused" client flag (focus-events
# on; confirmed live that it drops on the terminal's focus-out and returns on
# focus-in). Without it, a turn that finished while you were in another app
# was never marked unread, because its pane was still tmux-active. tmux
# starts a client out as focused, so a terminal that never reports focus
# behaves as before.
# Returns 0 if so, 1 otherwise (including when the pane doesn't exist).
lazy_llm_pane_is_focused() {
  local flags client_flags
  flags=$(tmux display-message -t "$1" -p '#{pane_active}#{window_active}#{?session_attached,1,0} #{session_id}' 2>/dev/null) || return 1
  [[ "${flags%% *}" == "111" ]] || return 1
  client_flags=$(tmux list-clients -t "${flags#* }" -F ',#{client_flags},' 2>/dev/null) || return 1
  [[ "$client_flags" == *,focused,* ]]
}

# Mark a pane unread, unless it's focused right now. Always returns 0 — it's
# called from hooks and pollers that must never fail over it.
lazy_llm_mark_unread() {
  local pane_id="${1:-}" pid
  [[ -n "$pane_id" ]] || return 0
  lazy_llm_pane_is_focused "$pane_id" && return 0
  pid=$(_lazy_llm_pane_pid "$pane_id") || return 0
  [[ -n "$pid" ]] || return 0
  mkdir -p "$_LAZY_LLM_UNREAD_DIR" 2>/dev/null || return 0
  printf '%s\n' "$pid" > "$_LAZY_LLM_UNREAD_DIR/$pane_id" 2>/dev/null || true
  return 0
}

# Always returns 0 (safe as a fire-and-forget call under set -e).
lazy_llm_clear_unread() {
  [[ -n "${1:-}" ]] || return 0
  rm -f "$_LAZY_LLM_UNREAD_DIR/$1" 2>/dev/null || true
  return 0
}

# Returns 0 if the pane has a valid unread marker. A marker whose pid no
# longer matches the pane (dead pane, or %N reused after a server restart)
# is removed on the spot.
lazy_llm_is_unread() {
  local pane_id="${1:-}" marker saved="" pid=""
  marker="$_LAZY_LLM_UNREAD_DIR/$pane_id"
  [[ -n "$pane_id" && -f "$marker" ]] || return 1
  read -r saved < "$marker" 2>/dev/null || true
  pid=$(_lazy_llm_pane_pid "$pane_id") || pid=""
  if [[ -z "$pid" || "$saved" != "$pid" ]]; then
    rm -f "$marker" 2>/dev/null || true
    return 1
  fi
  return 0
}

# Layer the unread state onto a base status (see section header).
# Args: $1 pane_id  $2 tool  $3 base status   Stdout: final status
_lazy_llm_apply_unread() {
  local pane_id="$1" tool="$2" base="$3"
  local busy="$_LAZY_LLM_BUSY_DIR/$pane_id"

  if [[ "$tool" != "claude" ]]; then
    if [[ "$base" == "working" ]]; then
      { mkdir -p "$_LAZY_LLM_BUSY_DIR" && : > "$busy"; } 2>/dev/null || true
    elif [[ "$base" == "idle" && -f "$busy" ]]; then
      # rm first and only the caller whose rm succeeded marks — several
      # pollers (status bar, pane borders, dashboard) run this concurrently.
      rm "$busy" 2>/dev/null && lazy_llm_mark_unread "$pane_id" || true
    fi
  fi

  if [[ "$base" == "idle" ]] && lazy_llm_is_unread "$pane_id"; then
    echo unread
  else
    echo "$base"
  fi
  return 0
}

# ──────────────────────────────────────────────────────────────────────────
# Status glyphs + colors — one mapping for every surface (status-right
# tiles, pane borders, dashboard tree). Colors reuse dev-env's tmux theme
# palette (tmux.conf.local's tmux_conf_theme_colour_* table):
#   waiting  ◐  #ff00af pink    (colour_10) blocked on your decision
#   unread   ◉  #5fff00 green   (colour_11) finished; your turn
#   working  ●  #ffff00 yellow  (colour_5)  generating
#   idle     ○  #bcbcbc gray                dealt with; nothing to do
#   unknown  ?  #8a8a8a dim gray (colour_3)
# Idle is deliberately the calm one now: before "unread" existed it was
# green, but a pane you've already handled shouldn't compete for attention
# with one that's waiting on you.
# ──────────────────────────────────────────────────────────────────────────
lazy_llm_status_glyph() {
  case "$1" in
    waiting) printf '◐' ;;
    unread)  printf '◉' ;;
    working) printf '●' ;;
    idle)    printf '○' ;;
    *)       printf '?' ;;
  esac
}

lazy_llm_status_color() {
  case "$1" in
    waiting) printf '#ff00af' ;;
    unread)  printf '#5fff00' ;;
    working) printf '#ffff00' ;;
    idle)    printf '#bcbcbc' ;;
    *)       printf '#8a8a8a' ;;
  esac
}

# Prune stale (dead) panes from AI_PANES/AI_TOOLS lists.
# Updates tmux window options and global variables with cleaned-up state.
# Requires: _SESSION, _WINDOW, AI_PANES, AI_TOOLS, AI_PANE_IDX (call lazy_llm_read_multi_state first)
lazy_llm_prune_stale_panes() {
  [[ -z "$AI_PANES" ]] && return 0

  local -a pane_arr tool_arr name_arr=() valid_panes valid_tools valid_names
  read -ra pane_arr <<< "$AI_PANES"
  read -ra tool_arr <<< "$AI_TOOLS"
  [[ -n "${AI_PANE_NAMES:-}" ]] && read -ra name_arr <<< "$AI_PANE_NAMES"
  local total=${#pane_arr[@]}
  local current_idx="${AI_PANE_IDX:-0}"

  # @AI_PANE_NAMES is parallel to @AI_PANES by position: it must lose the
  # same slots, or every later name shifts onto the wrong pane.
  valid_panes=()
  valid_tools=()
  valid_names=()
  for i in "${!pane_arr[@]}"; do
    if lazy_llm_validate_pane "${pane_arr[$i]}"; then
      valid_panes+=("${pane_arr[$i]}")
      valid_tools+=("${tool_arr[$i]:-unknown}")
      valid_names+=("${name_arr[$i]:-_}")
    fi
  done

  # No stale entries — nothing to do
  if [[ "${#valid_panes[@]}" -eq "$total" ]]; then
    return 0
  fi

  # Update globals with pruned values
  AI_PANES="${valid_panes[*]}"
  AI_TOOLS="${valid_tools[*]}"
  total=${#valid_panes[@]}

  tmux set-option -w -t "$_SESSION:$_WINDOW" @AI_PANES "$AI_PANES"
  tmux set-option -w -t "$_SESSION:$_WINDOW" @AI_TOOLS "$AI_TOOLS"
  if [[ -n "${AI_PANE_NAMES:-}" ]]; then
    AI_PANE_NAMES="${valid_names[*]}"
    tmux set-option -w -t "$_SESSION:$_WINDOW" @AI_PANE_NAMES "$AI_PANE_NAMES"
  fi

  # Adjust current index if out of bounds
  if [[ "$current_idx" -ge "$total" ]] && [[ "$total" -gt 0 ]]; then
    current_idx=$((total - 1))
  fi
  AI_PANE_IDX="$current_idx"
  tmux set-option -w -t "$_SESSION:$_WINDOW" @AI_PANE_IDX "$AI_PANE_IDX"

  # Update active pane reference if any panes remain
  if [[ "$total" -gt 0 ]]; then
    tmux set-option -w -t "$_SESSION:$_WINDOW" @AI_PANE_ID "${valid_panes[$current_idx]}"
    tmux set-option -w -t "$_SESSION:$_WINDOW" @AI_TOOL "${valid_tools[$current_idx]}"
    AI_TOOL="${valid_tools[$current_idx]}"
  fi

  # Clean up empty holding window when only one pane remains
  if [[ -n "${AI_HOLD_WIN:-}" ]] && [[ "$total" -le 1 ]]; then
    tmux kill-window -t "$AI_HOLD_WIN" 2>/dev/null || true
    tmux set-option -wu -t "$_SESSION:$_WINDOW" @AI_HOLD_WIN 2>/dev/null || true
    AI_HOLD_WIN=""
  fi
}

# Append a pattern to a .gitignore file if not already present.
# Args: $1 repo_root, $2 pattern (e.g. ".worktrees/")
lazy_llm_ensure_gitignore() {
  local repo="$1" pat="$2"
  local gi="$repo/.gitignore"
  if [[ -f "$gi" ]] && command grep -qxF "$pat" "$gi" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$pat" >> "$gi"
  echo "Added $pat to $gi" >&2
}

# Find the lazy-llm session (if any) whose first-pane path equals the given path.
# Compares via realpath so symlinks don't fool the match.
# Args: $1 target_path
# Stdout: session name or empty
lazy_llm_find_session_for_path() {
  local target="$1" realtarget
  realtarget=$(realpath "$target" 2>/dev/null) || realtarget="$target"
  while IFS=$'\t' read -r name dir _ _ _; do
    local realdir
    realdir=$(realpath "$dir" 2>/dev/null) || realdir="$dir"
    if [[ "$realdir" == "$realtarget" ]]; then
      printf '%s\n' "$name"
      return 0
    fi
  done < <(lazy_llm_gather_sessions)
}

# Create or locate a git worktree for the given branch.
# - If branch exists: create worktree pointing at it (error if already checked out elsewhere)
# - If branch doesn't exist: create branch from HEAD and create the worktree
# - Worktree base path: $LAZY_LLM_WORKTREE_DIR or "$repo_root/.worktrees"
# - When using the in-repo default, ensure .worktrees/ is in .gitignore
# Args: $1 branch_name
# Stdout: absolute worktree path on success
# Exit: 0 success, non-zero failure (with message on stderr)
lazy_llm_setup_worktree() {
  local branch="$1"
  [[ -z "$branch" ]] && { echo "Error: branch name required" >&2; return 2; }

  local repo
  repo=$(git rev-parse --show-toplevel 2>/dev/null) \
    || { echo "Error: not inside a git repository" >&2; return 2; }

  local sanitized="${branch//\//-}"
  local base="${LAZY_LLM_WORKTREE_DIR:-$repo/.worktrees}"
  local wt="$base/$sanitized"

  # If the default in-repo path is in use, make sure .worktrees/ is gitignored
  if [[ "$base" == "$repo/.worktrees" ]]; then
    lazy_llm_ensure_gitignore "$repo" ".worktrees/"
  fi

  # Already exists as a registered worktree?
  if [[ -d "$wt" ]]; then
    if git -C "$repo" worktree list --porcelain 2>/dev/null | command grep -qxF "worktree $wt"; then
      printf '%s\n' "$wt"
      return 0
    fi
    echo "Error: $wt exists but is not a registered git worktree" >&2
    return 1
  fi

  mkdir -p "$base"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    # Branch exists — refuse if it's checked out elsewhere
    if git -C "$repo" worktree list --porcelain 2>/dev/null \
        | command grep -qxF "branch refs/heads/$branch"; then
      echo "Error: branch '$branch' is already checked out in another worktree" >&2
      echo "       Hint: remove the other worktree first, or create a new branch" >&2
      return 1
    fi
    git -C "$repo" worktree add "$wt" "$branch" >&2 \
      || { echo "Error: git worktree add failed" >&2; return 1; }
  else
    git -C "$repo" worktree add -b "$branch" "$wt" >&2 \
      || { echo "Error: git worktree add -b failed" >&2; return 1; }
  fi

  printf '%s\n' "$wt"
}

# Resolve the default branch for the given repo.
# Tries: refs/remotes/origin/HEAD → local main → local master → fallback "main"
# Args: $1 repo_root (default: cwd)
# Stdout: branch name (no remote prefix)
lazy_llm_default_branch() {
  local repo="${1:-$(pwd)}"
  local d
  d=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) \
    && printf '%s\n' "${d#origin/}" && return 0
  local cand
  for cand in main master; do
    if git -C "$repo" rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
      printf '%s\n' "$cand"; return 0
    fi
  done
  printf 'main\n'
}

# Internal helper for lazy_llm_gather_worktrees. Skip detached-HEAD worktrees.
_lazy_llm_emit_worktree_row() {
  local path="$1" branch="$2" default="$3" is_github="$4"
  [[ -z "$branch" ]] && return 0

  local dirty="" ahead="0" behind="0" session="" pr=""

  [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]] && dirty="*"

  local counts
  counts=$(git -C "$path" rev-list --left-right --count "origin/$default...HEAD" 2>/dev/null)
  if [[ -n "$counts" ]]; then
    behind=$(echo "$counts" | awk '{print $1}')
    ahead=$(echo "$counts"  | awk '{print $2}')
  fi

  session=$(lazy_llm_find_session_for_path "$path")

  if [[ "$is_github" == "true" ]]; then
    pr=$(gh -R "$(git -C "$path" remote get-url origin 2>/dev/null)" pr view "$branch" \
            --json state -q .state 2>/dev/null) || pr=""
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$path" "$branch" "$dirty" "$ahead" "$behind" "$session" "$pr"
}

# List worktrees with state. Tab-separated rows:
#   PATH<TAB>BRANCH<TAB>DIRTY<TAB>AHEAD<TAB>BEHIND<TAB>SESSION<TAB>PR_STATE
# DIRTY: "*" or ""; AHEAD/BEHIND: counts vs origin/<default>; SESSION: lazy-llm
# session attached; PR_STATE: OPEN/MERGED/CLOSED/"" (only when gh+github remote).
# Skips detached-HEAD worktrees.
lazy_llm_gather_worktrees() {
  local repo default has_gh is_github
  repo=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  default=$(lazy_llm_default_branch "$repo")

  has_gh=false; is_github=false
  command -v gh >/dev/null 2>&1 && has_gh=true
  if $has_gh; then
    git -C "$repo" remote get-url origin 2>/dev/null | command grep -qE 'github\.com' \
      && is_github=true
  fi

  local path="" branch=""
  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      path="${line#worktree }"
    elif [[ "$line" == branch\ * ]]; then
      branch="${line#branch refs/heads/}"
    elif [[ -z "$line" ]]; then
      _lazy_llm_emit_worktree_row "$path" "$branch" "$default" "$is_github"
      path=""; branch=""
    fi
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null)
  [[ -n "$path" ]] && _lazy_llm_emit_worktree_row "$path" "$branch" "$default" "$is_github"
  return 0
}

# Atomically tear down a worktree: kill attached lazy-llm session (if any),
# remove the worktree, optionally delete the branch.
# Args: $1 worktree_path, $2 delete_branch (yes/no, default no), $3 force (yes/no, default no)
# Returns 0 success, non-zero failure (messages on stderr).
lazy_llm_cleanup_worktree() {
  local path="$1" delete_branch="${2:-no}" force="${3:-no}"
  local repo branch session
  # Resolve the MAIN repo path (first entry in `git worktree list`). This survives
  # removal of the secondary worktree we're about to delete.
  repo=$(git -C "$path" worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
  if [[ -z "$repo" ]] || [[ ! -d "$repo" ]]; then
    echo "Error: $path not in a git repo" >&2
    return 1
  fi
  branch=$(git -C "$path" branch --show-current 2>/dev/null)

  session=$(lazy_llm_find_session_for_path "$path")
  if [[ -n "$session" ]]; then
    "$HOME/.local/bin/llm-sessions" --kill "$session" >&2 || true
  fi

  local rm_args=()
  [[ "$force" == "yes" ]] && rm_args+=(--force)
  if ! git -C "$repo" worktree remove "${rm_args[@]}" "$path" >&2; then
    echo "Error: failed to remove worktree '$path'" >&2
    return 1
  fi

  if [[ "$delete_branch" == "yes" ]] && [[ -n "$branch" ]]; then
    local d_flag="-d"
    [[ "$force" == "yes" ]] && d_flag="-D"
    git -C "$repo" branch "$d_flag" "$branch" >&2 \
      || echo "Warning: failed to delete branch '$branch'" >&2
  fi

  return 0
}

# Gather all lazy-llm-marked tmux sessions into a structured list.
# Each output line is tab-separated: NAME<tab>DIR<tab>TOOLS<tab>WINS<tab>ATTACHED
# (ATTACHED is "*" when attached, empty otherwise.)
# Lists nothing if no sessions exist or no tmux server is running.
lazy_llm_gather_sessions() {
  # One `tmux list-panes -a` for everything (user options resolve in -F
  # formats), instead of ~5 tmux calls per session: this runs on every
  # status-bar refresh and every dashboard render, and the per-call cost
  # (~7ms each on a busy server) was most of the dashboard's latency.
  # \x1f separates fields, not tabs: `read` collapses runs of a whitespace
  # IFS, which would shift every field after an empty one.
  local rows
  rows=$(tmux list-panes -a -F $'#{session_name}\x1f#{@lazy_llm}\x1f#{window_index}\x1f#{window_name}\x1f#{window_active}#{pane_active}\x1f#{pane_current_path}\x1f#{@AI_TOOLS}\x1f#{@AI_TOOL}\x1f#{session_attached}' 2>/dev/null) || return 0
  [[ -z "$rows" ]] && return 0

  # Per session, in tmux's own session order: DIR is the current window's
  # active pane's path, TOOLS the first window's @AI_TOOLS (or legacy
  # @AI_TOOL), WINS the window count minus holding windows (_hold_*).
  local cur="" dir tools wins attached first_win seen_wins
  local s mark win wname act path t_multi t_single att
  _lazy_llm_gather_emit() {
    [[ -n "$cur" ]] || return 0
    printf '%s\t%s\t%s\t%s\t%s\n' "$cur" "${dir:-?}" "${tools:-?}" "$wins" "$attached"
  }
  while IFS=$'\x1f' read -r s mark win wname act path t_multi t_single att; do
    [[ "$mark" == "1" ]] || continue
    if [[ "$s" != "$cur" ]]; then
      _lazy_llm_gather_emit
      cur="$s"; dir=""; tools=""; wins=0; first_win="$win"; seen_wins=" "
      attached=""; [[ "${att:-0}" -gt 0 ]] && attached="*"
    fi
    if [[ "$seen_wins" != *" $win "* ]]; then
      seen_wins+="$win "
      [[ "$wname" == _hold_* ]] || wins=$((wins + 1))
    fi
    [[ "$win" == "$first_win" && -z "$tools" ]] && tools="${t_multi:-$t_single}"
    [[ "$act" == "11" ]] && dir="$path"
  done <<< "$rows"
  _lazy_llm_gather_emit
  unset -f _lazy_llm_gather_emit
}

# Read the AI pane list for an ARBITRARY session:window, not just the current one.
# Unlike lazy_llm_read_multi_state (which requires _SESSION/_WINDOW to already be
# resolved from the current tmux context), this takes an explicit target — used by
# the dashboard's workspace tree to show every pane of every workspace, not just
# the one the popup happened to be launched from.
# Args:   $1 session, $2 window
# Sets:   REPLY_PANES, REPLY_TOOLS, REPLY_IDX (arrays/index for that window; empty
#         REPLY_PANES if the window isn't a lazy-llm multi-pane workspace)
lazy_llm_read_multi_state_for() {
  local session="$1" window="$2"
  REPLY_PANES=$(tmux show-option -wv -t "$session:$window" @AI_PANES 2>/dev/null) || REPLY_PANES=""
  REPLY_TOOLS=$(tmux show-option -wv -t "$session:$window" @AI_TOOLS 2>/dev/null) || REPLY_TOOLS=""
  REPLY_IDX=$(tmux show-option -wv -t "$session:$window" @AI_PANE_IDX 2>/dev/null) || REPLY_IDX="0"
  # Optional per-pane DISPLAY label override (space-separated, parallel to
  # @AI_TOOLS; "_" marks "no override, use the tool name"). Separate from
  # @AI_TOOLS itself so renaming a pane's display label can never break
  # tool-specific status detection.
  REPLY_PANE_NAMES=$(tmux show-option -wv -t "$session:$window" @AI_PANE_NAMES 2>/dev/null) || REPLY_PANE_NAMES=""
}

# Fold (collapse) state for a workspace's pane tree in the dashboard's
# Workspaces tab — a SESSION-scoped tmux option (parallel to how @lazy_llm
# itself marks a session, not the -w window-scoped pattern @AI_PANES et al.
# use), because fold state is a per-workspace property, not per-window.
# Stored externally (not in an in-process bash array) specifically so it can
# be read/written from a fresh subprocess with no access to the dashboard's
# own memory — e.g. fzf's reload() action, which runs its bound command as an
# independent process. See llm-dashboard's render_sessions_tab for the caller.
#
# Args:   $1 workspace/session name
# Stdout: "1" if collapsed, empty otherwise. Returns 0 always (never lets a
#         dead/renamed session under a caller's set -e take down the caller).
lazy_llm_read_collapsed() {
  local name="$1"
  tmux show-option -v -t "$name" @lazy_llm_collapsed 2>/dev/null || true
}

# Toggle a workspace's fold state (see lazy_llm_read_collapsed). Returns 0
# always, same reasoning as the reader.
# Args: $1 workspace/session name
lazy_llm_toggle_collapsed() {
  local name="$1"
  if [[ "$(lazy_llm_read_collapsed "$name")" == "1" ]]; then
    tmux set-option -u -t "$name" @lazy_llm_collapsed 2>/dev/null || true
  else
    tmux set-option -t "$name" @lazy_llm_collapsed 1 2>/dev/null || true
  fi
}

# ──────────────────────────────────────────────────────────────────────────
# Manual list reordering (dashboard-manual-list-reordering)
# ──────────────────────────────────────────────────────────────────────────

# Persisted custom order of workspace (session) names for the dashboard's
# Workspaces tree — a server-scoped tmux option (`-s`, no `-t target`
# needed; confirmed live that `-s` works for a `@`-prefixed user option and
# is genuinely server-wide, NOT readable via a session target), unlike fold
# state (@lazy_llm_collapsed, session-scoped): fold is a property of ONE
# workspace, but relative order is a relationship across every workspace,
# so it needs a scope broader than any single session. Value is a
# space-separated list of names — same convention @AI_PANES/@AI_TOOLS
# already use for parallel arrays; lazy-llm session names are
# directory-derived and don't contain spaces.
#
# Stdout: the raw order list (space-separated), "" if never set. Returns 0
# always (mirrors lazy_llm_read_collapsed's never-fail contract).
lazy_llm_read_ws_order() {
  tmux show-option -s -v @lazy_llm_ws_order 2>/dev/null || true
}

# Apply the persisted custom order to lazy_llm_gather_sessions's raw
# tab-separated data. Workspaces present in the order list are emitted in
# that order; any workspace NOT yet in the list (new, never explicitly
# moved) is appended afterward in gather_sessions's own natural order —
# never silently dropped. A stale order entry for a workspace that no
# longer exists is simply skipped (not emitted); lazy_llm_move_ws_order
# drops such entries from the persisted list itself the next time it
# writes, so they don't accumulate forever.
# Args:   $1 raw gather_sessions data (tab-separated lines, may be empty)
# Stdout: the same data, reordered (same tab-separated shape)
lazy_llm_apply_ws_order() {
  local data="$1"
  [[ -z "$data" ]] && return 0

  local order
  order=$(lazy_llm_read_ws_order)
  if [[ -z "$order" ]]; then
    printf '%s\n' "$data"
    return 0
  fi

  local -a order_arr
  read -ra order_arr <<< "$order"

  local -A line_of=()
  local name rest
  while IFS=$'\t' read -r name rest; do
    [[ -n "$name" && -z "${line_of[$name]+set}" ]] && line_of[$name]="$name"$'\t'"$rest"
  done <<< "$data"

  local out="" seen=" "
  local o
  for o in "${order_arr[@]}"; do
    [[ -n "${line_of[$o]+set}" ]] || continue
    [[ "$seen" == *" $o "* ]] && continue
    out+="${line_of[$o]}"$'\n'
    seen+="$o "
  done
  while IFS=$'\t' read -r name rest; do
    [[ -z "$name" ]] && continue
    [[ "$seen" == *" $name "* ]] && continue
    out+="$name"$'\t'"$rest"$'\n'
  done <<< "$data"

  out="${out%$'\n'}"
  printf '%s\n' "$out"
}

# Move a workspace up or down among its OWN sibling workspace rows and
# persist the result. Seeds the order list from the CURRENT natural
# workspace order (lazy_llm_gather_sessions) the first time it's called
# for a workspace not yet in the persisted list, so a swap always has a
# well-defined neighbor regardless of whether any prior reorder ever
# touched this workspace. Also drops persisted entries for workspaces that
# no longer exist (see lazy_llm_apply_ws_order's comment).
# Bounds: a no-op (not an error) at either end of the sibling list.
# Args: $1 workspace/session name, $2 direction ("up" or "down")
# Returns 0 always.
lazy_llm_move_ws_order() {
  local name="$1" dir="$2"

  local data
  data=$(lazy_llm_gather_sessions)
  [[ -z "$data" ]] && return 0

  local -a natural_arr=()
  local n
  while IFS=$'\t' read -r n _; do
    [[ -n "$n" ]] && natural_arr+=("$n")
  done <<< "$data"

  # Overlay: persisted order first (dropping any stale/dead names), then
  # append anything in natural order not already covered — same precedence
  # lazy_llm_apply_ws_order applies for display.
  local persisted
  persisted=$(lazy_llm_read_ws_order)
  local -a order_arr=()
  if [[ -n "$persisted" ]]; then
    local -a p_arr=()
    read -ra p_arr <<< "$persisted"
    local p seen=" " found
    for p in "${p_arr[@]}"; do
      found=""
      for n in "${natural_arr[@]}"; do
        [[ "$n" == "$p" ]] && { found=1; break; }
      done
      [[ -n "$found" ]] && { order_arr+=("$p"); seen+="$p "; }
    done
    for n in "${natural_arr[@]}"; do
      [[ "$seen" == *" $n "* ]] || order_arr+=("$n")
    done
  else
    order_arr=("${natural_arr[@]}")
  fi

  local idx=-1 i
  for i in "${!order_arr[@]}"; do
    [[ "${order_arr[$i]}" == "$name" ]] && { idx=$i; break; }
  done
  [[ $idx -lt 0 ]] && return 0

  local target=$idx
  [[ "$dir" == "up" ]] && target=$((idx - 1))
  [[ "$dir" == "down" ]] && target=$((idx + 1))

  if [[ $target -ge 0 && $target -lt ${#order_arr[@]} ]]; then
    local tmp="${order_arr[$idx]}"
    order_arr[$idx]="${order_arr[$target]}"
    order_arr[$target]="$tmp"
  fi

  tmux set-option -s @lazy_llm_ws_order "${order_arr[*]}" 2>/dev/null || true
}

# Swap a pane with its adjacent sibling (up = earlier index, down = later)
# within its OWN workspace's pane arrays and persist the result — the pane
# analog of lazy_llm_move_ws_order, but needs no separate order option: a
# workspace's pane order already IS its @AI_PANES/@AI_TOOLS/@AI_PANE_NAMES
# arrays (see lazy_llm_read_multi_state_for), so reordering a pane means
# swapping two adjacent entries across all three parallel arrays and
# re-setting them — same read/mutate/set pattern the dashboard's
# action:rename-pane (llm-dashboard's dispatch_action) already uses.
# Args: $1 session, $2 window, $3 pane index (0-based), $4 direction ("up"/"down")
# Bounds: a no-op (not an error) at either end of the pane list, or if idx
# is malformed/out of range.
# Returns 0 always.
lazy_llm_move_pane_order() {
  local session="$1" window="$2" idx="$3" dir="$4"

  [[ "$idx" =~ ^[0-9]+$ ]] || return 0

  lazy_llm_read_multi_state_for "$session" "$window"
  local -a pane_arr=() tool_arr=() name_arr=()
  [[ -n "$REPLY_PANES" ]] && read -ra pane_arr <<< "$REPLY_PANES"
  [[ -n "$REPLY_TOOLS" ]] && read -ra tool_arr <<< "$REPLY_TOOLS"
  [[ -n "$REPLY_PANE_NAMES" ]] && read -ra name_arr <<< "$REPLY_PANE_NAMES"

  [[ $idx -ge ${#pane_arr[@]} ]] && return 0

  # Pad name_arr out to pane_arr's length with "_" (no-override)
  # placeholders — same convention action:rename-pane uses — so the swap
  # below can't drop an unrelated pane's display-label override.
  local j
  for ((j = ${#name_arr[@]}; j < ${#pane_arr[@]}; j++)); do
    name_arr+=("_")
  done

  local target=$idx
  [[ "$dir" == "up" ]] && target=$((idx - 1))
  [[ "$dir" == "down" ]] && target=$((idx + 1))
  [[ $target -lt 0 || $target -ge ${#pane_arr[@]} ]] && return 0

  local tmp
  tmp="${pane_arr[$idx]}"; pane_arr[$idx]="${pane_arr[$target]}"; pane_arr[$target]="$tmp"
  tmp="${tool_arr[$idx]}"; tool_arr[$idx]="${tool_arr[$target]}"; tool_arr[$target]="$tmp"
  tmp="${name_arr[$idx]}"; name_arr[$idx]="${name_arr[$target]}"; name_arr[$target]="$tmp"

  tmux set-option -w -t "$session:$window" @AI_PANES "${pane_arr[*]}" 2>/dev/null || true
  tmux set-option -w -t "$session:$window" @AI_TOOLS "${tool_arr[*]}" 2>/dev/null || true
  tmux set-option -w -t "$session:$window" @AI_PANE_NAMES "${name_arr[*]}" 2>/dev/null || true

  # Keep @AI_PANE_IDX (the fallback active-pane pointer other tools like
  # llm-cycle read) pointing at the SAME physical pane after the swap, not
  # whichever pane now occupies the old index.
  local cur_idx
  cur_idx=$(tmux show-option -wv -t "$session:$window" @AI_PANE_IDX 2>/dev/null) || cur_idx=""
  if [[ "$cur_idx" == "$idx" ]]; then
    tmux set-option -w -t "$session:$window" @AI_PANE_IDX "$target" 2>/dev/null || true
  elif [[ "$cur_idx" == "$target" ]]; then
    tmux set-option -w -t "$session:$window" @AI_PANE_IDX "$idx" 2>/dev/null || true
  fi
}

# Swap the visible AI pane in <session:window> to the pane at <target_idx> in its
# @AI_PANES list. This is llm-cycle's core swap-pane logic, factored out so it can
# be driven with an EXPLICIT target instead of llm-cycle's ambient "current pane"
# resolution (lazy_llm_resolve_pane / lazy_llm_resolve_session_window) — needed by
# the dashboard, where "current pane" means the pane that launched the popup, not
# whatever workspace the user just picked from the tree. llm-cycle itself resolves
# ambient context, computes the target index, then calls this — single source of
# truth for the swap, per the two callers.
# Args:   $1 session, $2 window, $3 target_idx (0-based)
# No-op (silent, returns 0) if the window has <=1 AI pane, target_idx is out of
# range or malformed, or it's already the active pane.
lazy_llm_cycle_to_index() {
  local session="$1" window="$2" target_idx="$3"

  [[ "$target_idx" =~ ^[0-9]+$ ]] || return 0

  local ai_panes ai_tools ai_pane_idx
  ai_panes=$(tmux show-option -wv -t "$session:$window" @AI_PANES 2>/dev/null) || return 0
  [[ -z "$ai_panes" ]] && return 0
  ai_tools=$(tmux show-option -wv -t "$session:$window" @AI_TOOLS 2>/dev/null) || ai_tools=""
  ai_pane_idx=$(tmux show-option -wv -t "$session:$window" @AI_PANE_IDX 2>/dev/null) || ai_pane_idx="0"

  local -a pane_arr tool_arr
  read -ra pane_arr <<< "$ai_panes"
  read -ra tool_arr <<< "$ai_tools"
  local current_idx="${ai_pane_idx:-0}"
  local total=${#pane_arr[@]}

  [[ "$target_idx" -ge "$total" ]] && return 0
  [[ "$target_idx" -eq "$current_idx" ]] && return 0

  local current_pane="${pane_arr[$current_idx]}"
  local target_pane="${pane_arr[$target_idx]}"

  tmux swap-pane -d -s "$current_pane" -t "$target_pane" 2>/dev/null || return 0

  tmux set-option -w -t "$session:$window" @AI_PANE_IDX "$target_idx"
  tmux set-option -w -t "$session:$window" @AI_PANE_ID "$target_pane"
  tmux set-option -w -t "$session:$window" @AI_TOOL "${tool_arr[$target_idx]}"
  tmux set-option -w -t "$session:$window" @AI_PANE \
    "$session:$window.$(tmux display-message -t "$target_pane" -p '#{pane_index}')"

  local target_tool="${tool_arr[$target_idx]}"
  tmux select-pane -t "$target_pane" -T "AI: $target_tool [$((target_idx + 1))/$total]"
  # Cycling a pane into view is looking at it.
  lazy_llm_clear_unread "$target_pane"
}

# Validate that the holding window exists; recreate if missing.
# Requires: _SESSION, _WINDOW, AI_HOLD_WIN (call lazy_llm_read_multi_state first)
lazy_llm_validate_hold_win() {
  [[ -z "${AI_HOLD_WIN:-}" ]] && return 0

  # Check if window still exists
  if tmux display-message -t "$AI_HOLD_WIN" -p '#{window_id}' &>/dev/null; then
    return 0
  fi

  # Holding window is gone — recreate it
  local hold_win_name="_hold_${_WINDOW}"
  local target_dir
  target_dir=$(tmux display-message -t "$_SESSION:$_WINDOW" -p '#{pane_current_path}')
  tmux new-window -d -t "$_SESSION" -n "$hold_win_name" -c "$target_dir"
  AI_HOLD_WIN=$(tmux display-message -t "$_SESSION:$hold_win_name" -p '#{window_id}')
  tmux set-option -w -t "$_SESSION:$_WINDOW" @AI_HOLD_WIN "$AI_HOLD_WIN"
  tmux set-option -w -t "$AI_HOLD_WIN" @lazy_llm_hold "1"
}

# Get the pane list for a workspace's first window, in the same two-shape
# (modern @AI_PANES vs legacy single @AI_PANE_ID) render_sessions_tab
# already handles — one source of truth, shared by the dashboard tree,
# llm-status's cross-workspace summary, and llm-pane-border.
# Args: workspace_name  Sets: LAZY_LLM_SUMMARY_PANES, LAZY_LLM_SUMMARY_TOOLS
lazy_llm_panes_for_workspace() {
  local name="$1" first_win
  # Guarded: under a caller's set -e, an unguarded pipeline failing here
  # (e.g. the workspace got killed between listing it and this call) would
  # abort the whole caller, not just skip this one workspace.
  first_win=$(tmux list-windows -t "$name" -F '#{window_index}' 2>/dev/null | head -1) || first_win=""
  if [[ -z "$first_win" ]]; then
    LAZY_LLM_SUMMARY_PANES=()
    LAZY_LLM_SUMMARY_TOOLS=()
    return
  fi
  lazy_llm_read_multi_state_for "$name" "$first_win"
  if [[ -n "$REPLY_PANES" ]]; then
    read -ra LAZY_LLM_SUMMARY_PANES <<< "$REPLY_PANES"
    read -ra LAZY_LLM_SUMMARY_TOOLS <<< "$REPLY_TOOLS"
  else
    local single_pane_id
    single_pane_id=$(tmux show-option -wv -t "$name:$first_win" @AI_PANE_ID 2>/dev/null) || single_pane_id=""
    if [[ -n "$single_pane_id" ]]; then
      local single_tool
      single_tool=$(tmux show-option -wv -t "$name:$first_win" @AI_TOOL 2>/dev/null) || single_tool="claude"
      LAZY_LLM_SUMMARY_PANES=("$single_pane_id")
      LAZY_LLM_SUMMARY_TOOLS=("$single_tool")
    else
      LAZY_LLM_SUMMARY_PANES=()
      LAZY_LLM_SUMMARY_TOOLS=()
    fi
  fi
}

# Summary across every lazy-llm workspace, not just the caller's own
# window. Echoes "<workspaces> <waiting> <unread> <working> <idle>\n" —
# the last four are AI PANE counts by status (each pane is its own agent
# session, so that's the unit worth counting; unknown panes aren't counted).
# The trailing newline matters — see coding-standards/frameworks/tmux-fzf.md
# on `read var < <(cmd)` under set -e. Cheap enough at typical scale (a
# handful of workspaces) for the ~10s status-interval callers run this on.
lazy_llm_compute_summary() {
  local data
  data=$(lazy_llm_gather_sessions 2>/dev/null) || { printf '0 0 0 0 0\n'; return; }
  if [[ -z "$data" ]]; then
    printf '0 0 0 0 0\n'
    return
  fi
  local ws_count=0 n_waiting=0 n_unread=0 n_working=0 n_idle=0
  local name dir tools wins attached
  while IFS=$'\t' read -r name dir tools wins attached; do
    ws_count=$((ws_count + 1))
    local LAZY_LLM_SUMMARY_PANES=() LAZY_LLM_SUMMARY_TOOLS=()
    lazy_llm_panes_for_workspace "$name"
    local i st
    for i in "${!LAZY_LLM_SUMMARY_PANES[@]}"; do
      st=$(lazy_llm_detect_pane_status "${LAZY_LLM_SUMMARY_PANES[$i]}" "${LAZY_LLM_SUMMARY_TOOLS[$i]:-claude}")
      case "$st" in
        waiting) n_waiting=$((n_waiting + 1)) ;;
        unread)  n_unread=$((n_unread + 1)) ;;
        working) n_working=$((n_working + 1)) ;;
        idle)    n_idle=$((n_idle + 1)) ;;
      esac
    done
  done <<< "$data"
  printf '%s %s %s %s %s\n' "$ws_count" "$n_waiting" "$n_unread" "$n_working" "$n_idle"
}

# Render lazy_llm_compute_summary's output as tmux markup:
#   "3ws 1◐ 2◉ 1● 3○"
# One "<count><glyph>" per status, in attention order, each in its status
# color (bold for the two that want you: waiting, unread); zero counts are
# omitted so a quiet setup reads as just "3ws". Shared by llm-status and
# llm-pane-border so the two summaries can't drift.
# Args: $1 text color to restore after each colored count, then the five
#       numbers from lazy_llm_compute_summary.
lazy_llm_render_summary() {
  local text="$1" ws="$2" waiting="$3" unread="$4" working="$5" idle="$6"
  local out="${ws}ws" st n attr
  for st in waiting unread working idle; do
    case "$st" in
      waiting) n="$waiting" ;;
      unread)  n="$unread" ;;
      working) n="$working" ;;
      idle)    n="$idle" ;;
    esac
    [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] || continue
    attr=""
    [[ "$st" == "waiting" || "$st" == "unread" ]] && attr=",bold"
    out+=" #[fg=$(lazy_llm_status_color "$st")${attr}]${n}$(lazy_llm_status_glyph "$st")#[fg=${text},nobold]"
  done
  printf '%s' "$out"
}

# Resolve a pane's DISPLAY label: its custom rename from @AI_PANE_NAMES if
# one's set (and isn't the "_" no-override placeholder), else the plain
# tool name. Shared by llm-status and llm-pane-border so a pane rename
# (dashboard's 'r' on a pane row) shows up everywhere the pane's identity is
# rendered, not just in the dashboard tree it was set from. Deliberately
# never used for status DETECTION (that always keys off $tool) — renaming
# a pane's display must not change what it's detected as.
# Args:   $1 tool_name   $2 pane_names (space-separated, parallel to
#         @AI_PANES/@AI_TOOLS — pass "" if unavailable)   $3 index
# Stdout: the display label
lazy_llm_pane_display_label() {
  local tool="${1:-?}" pane_names="${2:-}" idx="${3:-0}"
  if [[ -n "$pane_names" ]]; then
    local -a _names=()
    read -ra _names <<< "$pane_names"
    local label="${_names[$idx]:-_}"
    [[ "$label" != "_" ]] && { printf '%s' "$label"; return; }
  fi
  printf '%s' "$tool"
}

# Clamp a label to at most N visible characters, appending a single "…" when
# truncated (so the result is still exactly N chars wide, not N+1) — for
# space-constrained single-line surfaces (llm-status tiles) where an
# arbitrary custom pane name could otherwise blow out the status line's
# layout. ${#s} counts CHARACTERS in a UTF-8 locale, not bytes — same
# reasoning as llm-dashboard's _help_pad (see coding-standards/frameworks/
# tmux-fzf.md on printf %-*s's byte-vs-character width bug).
# Args:   $1 label   $2 max_len (default 15)
lazy_llm_clamp_label() {
  local label="$1" max="${2:-15}"
  [[ "${#label}" -le "$max" ]] && { printf '%s' "$label"; return; }
  [[ "$max" -le 1 ]] && { printf '%s' "${label:0:$max}"; return; }
  printf '%s…' "${label:0:$((max - 1))}"
}

# ──────────────────────────────────────────────────────────────────────────
# Per-pane model — which model an agent pane is running right now, for the
# AI pane's border (llm-pane-border). Fed by the harness itself, never
# scraped: for claude, llm-claude-hook (lazy-llm's Claude Code plugin) writes it on
# SessionStart (payload's `model`), PostModelSwitch (`to_model` — fires on a
# /model switch), and Stop (last response's model in the transcript, for
# sessions whose SessionStart payload carried none). Other harnesses have no
# such feed yet, so they simply have no model.
#
# ~/.cache/lazy-llm/model/<pane_id> holds "<pane_pid> <model id>" — same
# pid guard as the unread markers, same reason (%N reuse after a restart).
# ──────────────────────────────────────────────────────────────────────────
_LAZY_LLM_MODEL_DIR="$HOME/.cache/lazy-llm/model"

# Args: $1 pane_id  $2 model id (as the harness reports it). Always returns 0.
lazy_llm_set_pane_model() {
  local pane_id="${1:-}" model="${2:-}" pid
  [[ -n "$pane_id" && -n "$model" ]] || return 0
  pid=$(_lazy_llm_pane_pid "$pane_id") || return 0
  [[ -n "$pid" ]] || return 0
  mkdir -p "$_LAZY_LLM_MODEL_DIR" 2>/dev/null || return 0
  printf '%s %s\n' "$pid" "$model" > "$_LAZY_LLM_MODEL_DIR/$pane_id" 2>/dev/null || true
  return 0
}

# Stdout: the pane's model id exactly as the harness reported it, or nothing
# if unknown. Always returns 0.
lazy_llm_pane_model_raw() {
  local pane_id="${1:-}" f saved="" model="" pid
  f="$_LAZY_LLM_MODEL_DIR/$pane_id"
  [[ -n "$pane_id" && -f "$f" ]] || return 0
  read -r saved model < "$f" 2>/dev/null || true
  pid=$(_lazy_llm_pane_pid "$pane_id") || pid=""
  if [[ -z "$pid" || "$saved" != "$pid" ]]; then
    rm -f "$f" 2>/dev/null || true
    return 0
  fi
  printf '%s' "$model"
  return 0
}

# Stdout: the pane's model, shortened (lazy_llm_short_model), or nothing if
# unknown. Always returns 0.
lazy_llm_pane_model() {
  lazy_llm_short_model "$(lazy_llm_pane_model_raw "${1:-}")"
  return 0
}

# Shorten a model id for a narrow border:
#   claude-sonnet-5            -> sonnet5
#   claude-opus-5-5[1m]        -> opus5.5[1m]
#   claude-haiku-4-5-20251001  -> haiku4.5
# Anything not shaped like <family>-<version parts> passes through as-is
# (minus a "claude-" prefix), so an unfamiliar id still shows up.
lazy_llm_short_model() {
  local m="${1:-}" suffix=""
  [[ -n "$m" ]] || return 0
  if [[ "$m" =~ ^(.*)(\[[^]]*\])$ ]]; then
    m="${BASH_REMATCH[1]}"; suffix="${BASH_REMATCH[2]}"
  fi
  m="${m#claude-}"
  [[ "$m" =~ ^(.*)-[0-9]{8}$ ]] && m="${BASH_REMATCH[1]}"
  if [[ "$m" =~ ^([a-z]+)-([0-9]+(-[0-9]+)*)$ ]]; then
    local ver="${BASH_REMATCH[2]}"
    m="${BASH_REMATCH[1]}${ver//-/.}"
  fi
  printf '%s%s' "$m" "$suffix"
}

# ──────────────────────────────────────────────────────────────────────────
# Per-pane conversation id — which conversation an agent pane is on, so
# `lazy-llm restore` can resume it. For claude, llm-claude-hook records the
# session_id every hook payload carries (SessionStart also fires after /clear,
# --resume and compaction, so this follows the current conversation).
#
# ~/.cache/lazy-llm/conv/<pane_id> holds "<pane_pid> <conversation id>" —
# same pid guard as the model store, same reason (%N reuse after a restart).
# ──────────────────────────────────────────────────────────────────────────
_LAZY_LLM_CONV_DIR="$HOME/.cache/lazy-llm/conv"

# Args: $1 pane_id  $2 conversation id
# Returns 0 if the recorded id changed, 1 if it was already recorded (or
# nothing could be recorded) — callers save the manifest only on a change.
lazy_llm_set_pane_conv() {
  local pane_id="${1:-}" conv="${2:-}" pid f saved="" old=""
  [[ -n "$pane_id" && -n "$conv" ]] || return 1
  pid=$(_lazy_llm_pane_pid "$pane_id") || return 1
  [[ -n "$pid" ]] || return 1
  f="$_LAZY_LLM_CONV_DIR/$pane_id"
  [[ -f "$f" ]] && read -r saved old < "$f" 2>/dev/null
  [[ "$saved" == "$pid" && "$old" == "$conv" ]] && return 1
  mkdir -p "$_LAZY_LLM_CONV_DIR" 2>/dev/null || return 1
  printf '%s %s\n' "$pid" "$conv" > "$f" 2>/dev/null || return 1
  return 0
}

# Stdout: the pane's recorded conversation id, or nothing. Always returns 0.
lazy_llm_pane_conv() {
  local pane_id="${1:-}" f saved="" conv="" pid
  f="$_LAZY_LLM_CONV_DIR/$pane_id"
  [[ -n "$pane_id" && -f "$f" ]] || return 0
  read -r saved conv < "$f" 2>/dev/null || true
  pid=$(_lazy_llm_pane_pid "$pane_id") || pid=""
  if [[ -z "$pid" || "$saved" != "$pid" ]]; then
    rm -f "$f" 2>/dev/null || true
    return 0
  fi
  printf '%s' "$conv"
  return 0
}

# Fallback for claude panes with no hook record (started before the hook
# learned to record ids, or with lazy-llm's plugin disabled): Claude Code's
# own registry, ~/.claude/sessions/<claude pid>.json, whose sessionId is the
# conversation that process is on. Internal to Claude Code, so best effort:
# the hook record always wins when there is one.
# Stdout: the conversation id, or nothing. Always returns 0.
_lazy_llm_claude_registry_conv() {
  local pane_id="$1" pid c f
  pid=$(_lazy_llm_pane_pid "$pane_id") || return 0
  [[ -n "$pid" ]] || return 0
  for c in $(pgrep -P "$pid" 2>/dev/null); do
    f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$c.json"
    [[ -f "$f" ]] || continue
    jq -r --argjson pid "$c" 'select(.pid == $pid) | .sessionId // empty' "$f" 2>/dev/null
    return 0
  done
  return 0
}

# ──────────────────────────────────────────────────────────────────────────
# Tool adapters — the ONLY place that knows how each AI tool is launched.
# Save/restore and the manifest treat a pane's conversation id and model as
# opaque strings; supporting resume for another tool means adding a branch
# here (and to lazy_llm_tool_conv, its capture side).
# ──────────────────────────────────────────────────────────────────────────

# The conversation an AI pane is on right now.
# Args: $1 tool  $2 pane_id   Stdout: the id, or nothing. Always returns 0.
lazy_llm_tool_conv() {
  local tool="$1" pane_id="$2" conv
  case "$tool" in
    claude)
      conv=$(lazy_llm_pane_conv "$pane_id")
      [[ -n "$conv" ]] || conv=$(_lazy_llm_claude_registry_conv "$pane_id")
      printf '%s' "$conv"
      ;;
  esac
  return 0
}

# The command line typed into an AI pane's shell.
# Args: $1 tool  $2 conversation id ("" for a fresh one)  $3 model ("" = default)
lazy_llm_tool_launch_cmd() {
  local tool="$1" conv="${2:-}" model="${3:-}"
  case "$tool" in
    claude)
      if [[ -n "$conv" ]]; then
        printf "claude --resume '%s'" "$conv"
        [[ -n "$model" ]] && printf " --model '%s'" "$model"
        printf '\n'
      else
        printf 'claude\n'
      fi
      ;;
    *)
      printf '%s\n' "$tool"
      ;;
  esac
}

# ──────────────────────────────────────────────────────────────────────────
# Workspace build — shared by the lazy-llm launcher and `lazy-llm restore`.
# ──────────────────────────────────────────────────────────────────────────

# Create a new, empty prompt backing file under <dir>/.lazy-llm/prompts.
# Stdout: its path.
lazy_llm_create_prompt_file() {
  local dir="$1" prompt_file
  mkdir -p "$dir/.lazy-llm/prompts"
  prompt_file="$dir/.lazy-llm/prompts/prompt-$(date +%Y%m%d-%H%M%S).md"
  touch "$prompt_file"
  printf '%s\n' "$prompt_file"
}

# Server-global hooks and key bindings. Idempotent; called whenever a
# workspace window is built, so a fresh server gets them with its first one.
lazy_llm_register_tmux_integration() {
  # Global hook: keep @AI_PANE_IDX pointing at the AI pane last given real
  # focus, even after focus later moves to the editor/prompt pane — see
  # llm-pane-focus-track's own header comment for why tmux's own
  # #{pane_active} alone isn't enough here. Set globally (fires for every
  # pane-focus change in every window) rather than per-window, since a
  # per-window hook would need re-registering on every new lazy-llm
  # workspace; the script itself no-ops instantly for any non-lazy-llm
  # window (one cheap show-option call).
  #
  # after-select-pane, NOT pane-focus-in: the tmux manual documents
  # pane-focus-in/pane-focus-out, but they don't actually exist as
  # registerable hooks in tmux 3.7c (`tmux set-hook -g pane-focus-in ...`
  # exits 0 and silently never fires — confirmed live; `show-hooks -g`'s
  # own reference list doesn't include them, only client-focus-in/out,
  # which are client-level, not per-pane). after-select-pane is the real,
  # firing hook for "the active pane in a window changed" — confirmed live
  # across mouse-click-equivalent and prefix-arrow-equivalent transitions.
  # No -b (backgrounding run-shell): tried first, but produced a real
  # non-deterministic race — sometimes the update lagged behind the very
  # next select-pane and got missed. This script is a couple of cheap
  # show-option/set-option calls; foreground is fast enough not to matter
  # and removes the race entirely (also confirmed live, repeatedly).
  tmux set-hook -g after-select-pane \
    "run-shell '$HOME/.local/bin/llm-pane-focus-track #{pane_id} #{session_name} #{window_index}'"

  # A pane can also come into view with no select-pane at all: switching
  # window or session, or the terminal window regaining focus. Each clears
  # the now-visible pane's unread mark if it's really in front of you (see
  # llm-pane-focus-track --if-viewed). Backgrounded: unlike the @AI_PANE_IDX
  # update above there's no ordering to protect, and a window switch
  # shouldn't wait on it.
  local _viewed_hook
  for _viewed_hook in session-window-changed client-session-changed client-focus-in; do
    tmux set-hook -g "$_viewed_hook" \
      "run-shell -b '$HOME/.local/bin/llm-pane-focus-track --if-viewed #{pane_id}'"
  done

  # Register keybindings — scoped to lazy-llm windows via if-shell check.
  # In non-lazy-llm windows, C-n/C-p fall back to next/previous-window;
  # other bindings are no-ops.
  tmux bind-key -N "Next AI pane (next window elsewhere)" -T prefix C-n if-shell \
    "tmux show-option -wqv @AI_PANES" \
    "run-shell '$HOME/.local/bin/llm-cycle next'" \
    "next-window"
  tmux bind-key -N "Previous AI pane (previous window elsewhere)" -T prefix C-p if-shell \
    "tmux show-option -wqv @AI_PANES" \
    "run-shell '$HOME/.local/bin/llm-cycle prev'" \
    "previous-window"
  tmux bind-key -N "Remove current AI pane" -T prefix C-x if-shell \
    "tmux show-option -wqv @AI_PANES" \
    "confirm-before -p 'Remove current AI pane? (y/n)' \"run-shell '$HOME/.local/bin/llm-remove current'\""
  tmux bind-key -N "Add AI pane" -T prefix A if-shell \
    "tmux show-option -wqv @AI_PANES" \
    "display-menu -T 'Add AI Pane' \
      claude '' \"run-shell '$HOME/.local/bin/llm-add -t claude'\" \
      gemini '' \"run-shell '$HOME/.local/bin/llm-add -t gemini'\" \
      codex  '' \"run-shell '$HOME/.local/bin/llm-add -t codex'\" \
      grok   '' \"run-shell '$HOME/.local/bin/llm-add -t grok'\" \
      aider  '' \"run-shell '$HOME/.local/bin/llm-add -t aider'\""
  # Unguarded, unlike the pane keys: the dashboard is useful from any window,
  # and from a fresh tmux with no workspace at all (its Saved tab restores
  # them; see llm-tmux-init for registering this at server start).
  tmux bind-key -N "lazy-llm dashboard" -T prefix S \
    run-shell "$HOME/.local/bin/llm-dashboard-open"
  tmux bind-key -N "Save lazy-llm workspaces" -T prefix C-s if-shell \
    "tmux show-option -wqv @AI_PANES" \
    "run-shell -b '$HOME/.local/bin/llm-persist save --notify'"

  # Re-save on a rename done outside the dashboard (Prefix+$). At its own
  # array index so a user's own session-renamed hook isn't replaced. No
  # session-closed hook, on purpose: at shutdown sessions close one by one
  # while the server is still up, which a save would read as "closed on
  # purpose" (see llm-persist's retention rule).
  tmux set-hook -g 'session-renamed[40]' \
    "run-shell -b '$HOME/.local/bin/llm-persist save --async'"
  # Prefix+L retired — its surface (Panes tab) lives inside llm-dashboard now,
  # reachable from any tab via the '3' key.
}

# Turn an existing (single-pane) window into a lazy-llm workspace window:
# AI pane (top-left) | editor (top-right) | prompt buffer (bottom).
# Args: $1 session  $2 window index  $3 dir  $4 tool  $5 AI pane launch command
#       $6 prompt file to open when there's no prompt snapshot ("" = new file)
#       $7 "restore" to also restore the editor's snapshot (workspace restore)
#
# nvim snapshots (nvim-session-plugin): one rolling file per nvim in
# <dir>/.lazy-llm/sessions/, keyed by this window's position among the
# session's lazy-llm windows, so a fresh launch in the same dir finds the
# prompt pane's last state. Paths already set on the window (restore sets
# the saved ones) are kept. The prompt pane restores its snapshot whenever
# one exists; the editor only on workspace restore.
lazy_llm_build_window() {
  local session="$1" win_idx="$2" target_dir="$3" ai_tool="$4" launch_cmd="$5"
  local prompt_file="${6:-}" restore_editor="${7:-}"
  local lazy_dir="$target_dir/.lazy-llm"
  mkdir -p "$lazy_dir/prompts" "$lazy_dir/swap" "$lazy_dir/undo" "$lazy_dir/sessions"

  local editor_session prompt_session
  editor_session=$(tmux show-option -wqv -t "$session:$win_idx" @lazy_llm_editor_session)
  prompt_session=$(tmux show-option -wqv -t "$session:$win_idx" @lazy_llm_prompt_session)
  if [[ -z "$editor_session" || -z "$prompt_session" ]]; then
    # Counted before this window gets @AI_PANES.
    local nth suffix=""
    nth=$(tmux list-windows -t "$session" -F '#{@AI_PANES}' | grep -c . || true)
    [[ "$nth" -gt 0 ]] && suffix="-$((nth + 1))"
    editor_session="$lazy_dir/sessions/editor${suffix}.vim"
    prompt_session="$lazy_dir/sessions/prompt${suffix}.vim"
  fi

  # Get tmux base indexes
  local pane_base_index
  pane_base_index=$(tmux show-options -gw | grep pane-base-index | awk '{print $2}')

  # Define pane variables
  local ai_pane=$pane_base_index
  local neovim_pane=$((pane_base_index + 1))
  local prompt_pane=$((pane_base_index + 2))

  # Split horizontally first (left/right)
  # Use -l percentage syntax for tmux 3.4+ compatibility (replaces -p)
  tmux split-window -h -l 50% -t "$session:$win_idx" -c "$target_dir"

  # Split vertically with -f flag to create full-width bottom pane
  tmux split-window -v -f -l 25% -t "$session:$win_idx.$ai_pane" -c "$target_dir"

  # Clear CLAUDECODE env var in the AI pane to prevent nested session detection
  # (when lazy-llm is invoked from within a Claude Code session)
  tmux send-keys -t "$session:$win_idx.$ai_pane" "unset CLAUDECODE" C-m
  tmux send-keys -t "$session:$win_idx.$ai_pane" "$launch_cmd" C-m

  # Configure Neovim pane (top-right)
  local editor_env="LAZY_LLM_NVIM_ROLE=editor LAZY_LLM_NVIM_SESSION='${editor_session}'"
  [[ "$restore_editor" == "restore" && -f "$editor_session" ]] && editor_env+=" LAZY_LLM_NVIM_RESTORE=1"
  tmux send-keys -t "$session:$win_idx.$neovim_pane" "${editor_env} nvim" C-m

  # Configure Prompt Buffer pane (bottom) with swap and undo persistence.
  # Explicitly cd to target directory to ensure shell and nvim are in sync
  local prompt_env="LAZY_LLM_NVIM_ROLE=prompt LAZY_LLM_NVIM_SESSION='${prompt_session}'"
  local prompt_arg=""
  if [[ -f "$prompt_session" ]]; then
    prompt_env+=" LAZY_LLM_NVIM_RESTORE=1"
    prompt_file=""
  else
    [[ -n "$prompt_file" && -f "$prompt_file" ]] || prompt_file=$(lazy_llm_create_prompt_file "$target_dir")
    prompt_arg=" '${prompt_file}'"
  fi
  tmux send-keys -t "$session:$win_idx.$prompt_pane" "cd '${target_dir}' && ${prompt_env} nvim --cmd 'set directory=${lazy_dir}/swap// | set undodir=${lazy_dir}/undo// | set undofile' --cmd 'autocmd VimEnter * ++once set filetype=markdown | set showtabline=0 | startinsert'${prompt_arg}" C-m

  # Set pane titles if supported
  tmux select-pane -t "$session:$win_idx.$ai_pane" -T "AI: $ai_tool"
  tmux select-pane -t "$session:$win_idx.$neovim_pane" -T "Editor"
  tmux select-pane -t "$session:$win_idx.$prompt_pane" -T "Prompt"

  # Capture stable pane IDs (survive swap-pane, unlike indices)
  local ai_pane_id prompt_pane_id
  ai_pane_id=$(tmux display-message -t "$session:$win_idx.$ai_pane" -p '#{pane_id}')
  prompt_pane_id=$(tmux display-message -t "$session:$win_idx.$prompt_pane" -p '#{pane_id}')

  # Set pane ID options (preferred by llm-send/llm-pull/llm-append)
  tmux set-option -w -t "$session:$win_idx" @AI_PANE_ID "$ai_pane_id"
  tmux set-option -w -t "$session:$win_idx" @PROMPT_PANE_ID "$prompt_pane_id"

  # Initialize multi-pane state (single-element lists)
  tmux set-option -w -t "$session:$win_idx" @AI_PANES "$ai_pane_id"
  tmux set-option -w -t "$session:$win_idx" @AI_TOOLS "$ai_tool"
  tmux set-option -w -t "$session:$win_idx" @AI_PANE_IDX "0"

  # nvim snapshot paths and the prompt file this window started on
  tmux set-option -w -t "$session:$win_idx" @lazy_llm_editor_session "$editor_session"
  tmux set-option -w -t "$session:$win_idx" @lazy_llm_prompt_session "$prompt_session"
  tmux set-option -w -t "$session:$win_idx" @lazy_llm_prompt_file "$prompt_file"

  # Keep legacy index-based options for backward compatibility
  tmux set-option -w -t "$session:$win_idx" @AI_PANE "$session:$win_idx.$ai_pane"
  tmux set-option -w -t "$session:$win_idx" @PROMPT_PANE "$session:$win_idx.$prompt_pane"
  tmux set-option -w -t "$session:$win_idx" @AI_TOOL "$ai_tool"

  # Per-pane status on each pane's own border — window-scoped (-w), so this
  # only affects lazy-llm windows, nothing else in the user's tmux setup.
  # The AI pane's border shows tool+glyph+workspace-summary (llm-pane-border
  # — deliberately separate from llm-status: a pane border is much narrower
  # than the full status-right segment). The prompt/editor panes get a
  # plain label. Every branch sets an EXPLICIT fg color (#e4e4e4, this
  # theme's default text color) — a pane border otherwise inherits
  # pane-border-style/pane-active-border-style, which dims un-styled text
  # for an unfocused pane to the point of being barely readable (confirmed
  # live, user-reported).
  tmux set-option -w -t "$session:$win_idx" pane-border-status top
  tmux set-option -w -t "$session:$win_idx" pane-border-format \
    "#{?#{==:#{pane_id},#{@AI_PANE_ID}},#($HOME/.local/bin/llm-pane-border #{pane_id} #{@AI_TOOL}),#{?#{==:#{pane_id},#{@PROMPT_PANE_ID}},#[fg=#e4e4e4] prompt #[default],#[fg=#e4e4e4] #{pane_current_command} #[default]}}"

  # Mark session as lazy-llm managed and enable mouse. Identity and dir are
  # set once, by the session's first lazy-llm window (restore presets them).
  tmux set-option -t "$session" @lazy_llm 1
  tmux set-option -t "$session" mouse on
  [[ -n "$(tmux show-option -qv -t "$session" @lazy_llm_ws_id)" ]] \
    || tmux set-option -t "$session" @lazy_llm_ws_id "$(date +%Y%m%d%H%M%S)-$(printf '%04x%04x' "$RANDOM" "$RANDOM")"
  [[ -n "$(tmux show-option -qv -t "$session" @lazy_llm_dir)" ]] \
    || tmux set-option -t "$session" @lazy_llm_dir "$target_dir"

  lazy_llm_register_tmux_integration

  # Set initial focus to prompt buffer pane
  tmux select-pane -t "$session:$win_idx.$prompt_pane"

  lazy_llm_save_async
}

# Add an AI pane to <session:window>'s pane list, parked in the window's
# hidden holding window (created on first use). Doesn't cycle it into view.
# Args: $1 session  $2 window index  $3 dir  $4 tool  $5 launch command
# Stdout: the new pane's id
lazy_llm_add_ai_pane() {
  local session="$1" window="$2" target_dir="$3" tool="$4" launch_cmd="$5"
  local hold_win panes tools names new_pane_id
  hold_win=$(tmux show-option -wqv -t "$session:$window" @AI_HOLD_WIN)
  if [[ -n "$hold_win" ]] && ! tmux display-message -t "$hold_win" -p '#{window_id}' &>/dev/null; then
    hold_win=""
  fi
  if [[ -z "$hold_win" ]]; then
    hold_win=$(tmux new-window -d -t "$session" -n "_hold_${window}" -c "$target_dir" -P -F '#{window_id}')
    tmux set-option -w -t "$session:$window" @AI_HOLD_WIN "$hold_win"
    tmux set-option -w -t "$hold_win" @lazy_llm_hold "1"
  fi

  # -d: don't steal focus; -P -F prints the new pane's id
  new_pane_id=$(tmux split-window -d -t "$hold_win" -c "$target_dir" -P -F '#{pane_id}')
  tmux send-keys -t "$new_pane_id" "$launch_cmd" C-m
  # select-pane -T also makes it the hold window's active pane; that window
  # is never displayed, so nothing visible changes.
  tmux select-pane -t "$new_pane_id" -T "AI: $tool"

  panes=$(tmux show-option -wqv -t "$session:$window" @AI_PANES)
  tools=$(tmux show-option -wqv -t "$session:$window" @AI_TOOLS)
  names=$(tmux show-option -wqv -t "$session:$window" @AI_PANE_NAMES)
  tmux set-option -w -t "$session:$window" @AI_PANES "$panes $new_pane_id"
  tmux set-option -w -t "$session:$window" @AI_TOOLS "$tools $tool"
  # @AI_PANE_NAMES is parallel to @AI_PANES by position ("_" = no override):
  # pad it to the old pane count before appending the new pane's slot.
  if [[ -n "$names" ]]; then
    local -a pane_arr name_arr
    read -ra pane_arr <<< "$panes"
    read -ra name_arr <<< "$names"
    while [[ ${#name_arr[@]} -lt ${#pane_arr[@]} ]]; do name_arr+=("_"); done
    tmux set-option -w -t "$session:$window" @AI_PANE_NAMES "${name_arr[*]:0:${#pane_arr[@]}} _"
  fi
  printf '%s\n' "$new_pane_id"
}

# Run a command, killing it after $1 seconds (macOS has no `timeout`).
# Returns the command's status, or 124 on timeout.
lazy_llm_with_timeout() {
  local secs="$1" pid ticks=0
  shift
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if (( ticks >= secs * 10 )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait "$pid"
}

# Before a session is killed: move every client attached to it onto the most
# recently used other session, so closing (or killing) the workspace you're
# in doesn't drop you out of tmux — tmux's default detach-on-destroy would.
# With no other session there's nowhere to go, and tmux detaches as usual.
# (No head/early-exit awk in the pipeline: callers run under pipefail.)
# Always returns 0.
lazy_llm_move_clients_off() {
  local target="$1" other client
  # session_last_attached is empty for a never-attached session: default 0.
  other=$(tmux list-sessions -F '#{?session_last_attached,#{session_last_attached},0}	#{session_name}' 2>/dev/null \
    | awk -F'\t' -v t="$target" '$2 != t && (n == "" || $1 + 0 > m + 0) {m = $1; n = $2} END {print n}') || other=""
  [[ -n "$other" ]] || return 0
  while IFS= read -r client; do
    [[ -n "$client" ]] && tmux switch-client -c "$client" -t "=$other" 2>/dev/null
  done < <(tmux list-clients -t "=$target" -F '#{client_name}' 2>/dev/null)
  return 0
}

# Fire-and-forget manifest save (`llm-persist save --async`). Every fd is
# redirected: the dashboard calls this from fzf transform() subprocesses, and
# fzf reads a transform's stdout until EOF, so a background child holding it
# open would stall the UI. Always returns 0.
lazy_llm_save_async() {
  [[ -x "$HOME/.local/bin/llm-persist" ]] || return 0
  ( "$HOME/.local/bin/llm-persist" save --async </dev/null >/dev/null 2>&1 & )
  return 0
}
