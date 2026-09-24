#!/usr/bin/env bash
# lazy-llm-lib.sh — Shared library for lazy-llm pane resolution
# Source this file: source "$(dirname "$0")/lazy-llm-lib.sh"

# Guard against double-sourcing
[[ -n "${_LAZY_LLM_LIB_LOADED:-}" ]] && return 0
_LAZY_LLM_LIB_LOADED=1

# On macOS, tmux run-shell / display-popup or non-login subshells may have a
# minimal PATH where system tools precede Homebrew.
if [[ "$(uname -s)" == "Darwin" ]]; then
  [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]] && [[ -d /opt/homebrew/bin ]] && export PATH="/opt/homebrew/bin:$PATH"
  [[ ":$PATH:" != *":/usr/local/bin:"* ]] && [[ -d /usr/local/bin ]] && export PATH="/usr/local/bin:$PATH"
fi

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
# Returns 0 if alive, 1 if dead.
lazy_llm_validate_pane() {
  tmux display-message -t "$1" -p '#{pane_id}' &>/dev/null
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
  local tool="${1:-claude}"
  local content
  content=$(cat)

  # "ctrl+c to interrupt" was this pattern's original signal but current Claude
  # Code UI versions don't show it — confirmed live against a real busy session:
  # the actual "working" tells are the spinner/duration line ("Boondoggling…
  # (6m 42s · ↓ 22.4k tokens)") always present while generating, and "esc to
  # interrupt" specifically while a tool call is running. Match all three so
  # this survives future UI wording changes better than any single string.
  local interrupt_pat='ctrl\+c to interrupt|esc to interrupt|\([0-9]+m [0-9]+s'
  local waiting_pat='\[[yY]/[yYnN]\]|^[[:space:]]*[1-9][.)][[:space:]]'
  local prompt_pat='❯'

  local tail_content
  tail_content=$(tail -n 12 <<< "$content")

  case "$tool" in
    jetski|jetski-cli)
      # Jetski CLI prints "▸ Thought for 1m 26s, 89 tokens" in permanent scrollback,
      # so matching "\([0-9]+m [0-9]+s" across -S -200 would falsely classify finished
      # sessions as "working" forever. Instead, inspect the live bottom area (tail_content)
      # for the active braille spinner or the "esc to cancel" footer (when no background
      # task is keeping the footer visible), and match Jetski's "> " prompt box for idle.
      if grep -qE '^[[:space:]]*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⣾⣽⣻⢿⡿⣟⣯⣷][[:space:]]+' <<< "$tail_content"; then
        echo working
        return 0
      elif grep -qE '^esc to cancel' <<< "$tail_content" && ! grep -qE 'task\(s\) · /tasks' <<< "$tail_content"; then
        echo working
        return 0
      elif grep -qE '\[[yY]/[yYnN]\]|Allow|Always Allow' <<< "$tail_content"; then
        echo waiting
        return 0
      elif grep -qE '^>([[:space:]]|$)|^───' <<< "$tail_content"; then
        echo idle
        return 0
      else
        echo unknown
        return 0
      fi
      ;;
    claude|*)
      : # use defaults above
      ;;
  esac

  # waiting_pat's numbered-option alternative (matches Claude Code's actual
  # permission-prompt UI, e.g. "1. Yes  2. Yes, and don't ask again  3. No")
  # is indistinguishable from an ordinary markdown numbered list in Claude's
  # own RESPONSE text — confirmed live against a real idle pane: a
  # completed response ending in "1. A Variant primitive... 2. ... 3. ..."
  # was misclassified as "waiting" purely from old scrollback, long after
  # the turn had actually finished (this is why finished sessions kept
  # showing waiting — not just the hook mapping bug fixed earlier, THIS
  # too). A genuine interactive prompt is always near the CURRENT input
  # line at the bottom of the pane; old scrollback several screens up never
  # is. Scope this specific check to the last ~10 lines instead of the full
  # capture, so a real prompt still matches but a numbered list left over
  # from a finished response doesn't — tuned against the exact
  # false-positive content above: a tail of 15 still caught 2 of its 3 list
  # lines, 12 and 10 caught none.
  local claude_tail
  claude_tail=$(tail -n 10 <<< "$content")

  if grep -qE "$interrupt_pat" <<< "$content"; then
    echo working
  elif grep -qE "$waiting_pat" <<< "$claude_tail"; then
    echo waiting
  elif grep -qF "$prompt_pat" <<< "$content"; then
    echo idle
  else
    echo unknown
  fi
}

# Freshness window (seconds) for a hook-written status file to be trusted.
# Long enough to survive one status-bar refresh interval (status-interval
# default 15s), short enough that a status file from a since-closed pane, or
# one that's gone stale mid-generation, doesn't lie for long — see
# lazy_llm_detect_pane_status below.
_LAZY_LLM_HOOK_STATUS_MAX_AGE=30

# Read a Claude Code / Jetski CLI hook-written status for a pane, if fresh.
# Written by dev-env's ~/.claude/hooks/lazy-llm-status-notify.sh (and
# ~/.gemini/config/hooks/lazy-llm-jetski-hook.sh for Jetski CLI).
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
  now=$(date +%s)
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
# For tool=claude|jetski|jetski-cli, prefers a fresh hook-written status (see
# _lazy_llm_read_hook_status) over the content scrape below — hooks are
# event-driven and don't suffer the scrape's timing/UI-text fragility.
# Every other tool (gemini/opencode/codex/grok/aider) always uses the scrape path.
#
# "unread" is layered on top of an "idle" result — see the unread-marker
# section below for what sets and clears it.
lazy_llm_detect_pane_status() {
  local pane_id="${1:?pane_id required}"
  local tool="${2:-claude}"
  local base

  if [[ "$tool" == "claude" || "$tool" == "jetski" || "$tool" == "jetski-cli" ]] && base=$(_lazy_llm_read_hook_status "$pane_id"); then
    # `if cmd=$(...); then` (not `cmd=$(...) && ...`) — a bare `&&` here would
    # trip callers' `set -e` on the common case of no hook file existing yet.
    :
  else
    local content
    content=$(tmux capture-pane -p -t "$pane_id" -S -200 2>/dev/null) || { echo unknown; return 0; }
    base=$(printf '%s' "$content" | lazy_llm_detect_status_from_content "$tool")
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
#   - Claude's Stop hook (dev-env's lazy-llm-status-notify.sh, via
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
# active window of a session with a client attached?
# Returns 0 if so, 1 otherwise (including when the pane doesn't exist).
lazy_llm_pane_is_focused() {
  local flags
  flags=$(tmux display-message -t "$1" -p '#{pane_active}#{window_active}#{?session_attached,1,0}' 2>/dev/null) || return 1
  [[ "$flags" == "111" ]]
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

  local -a pane_arr tool_arr valid_panes valid_tools
  read -ra pane_arr <<< "$AI_PANES"
  read -ra tool_arr <<< "$AI_TOOLS"
  local total=${#pane_arr[@]}
  local current_idx="${AI_PANE_IDX:-0}"

  valid_panes=()
  valid_tools=()
  for i in "${!pane_arr[@]}"; do
    if lazy_llm_validate_pane "${pane_arr[$i]}"; then
      valid_panes+=("${pane_arr[$i]}")
      valid_tools+=("${tool_arr[$i]:-unknown}")
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
  local sessions
  sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null) || return 0
  [[ -z "$sessions" ]] && return 0

  while IFS= read -r session; do
    # Only include lazy-llm-marked sessions (session-scoped @lazy_llm option)
    local marker
    marker=$(tmux show-option -v -t "$session" @lazy_llm 2>/dev/null) || true
    [[ "$marker" != "1" ]] && continue

    # Directory from first pane of first window
    local dir
    dir=$(tmux display-message -t "$session:" -p '#{pane_current_path}' 2>/dev/null) || dir="?"

    # AI tools from the first window's @AI_TOOLS (or legacy @AI_TOOL)
    local first_win tools
    first_win=$(tmux list-windows -t "$session" -F '#{window_index}' 2>/dev/null | head -1)
    tools=$(tmux show-option -wv -t "$session:$first_win" @AI_TOOLS 2>/dev/null) || true
    [[ -z "$tools" ]] && tools=$(tmux show-option -wv -t "$session:$first_win" @AI_TOOL 2>/dev/null) || true
    [[ -z "$tools" ]] && tools="?"

    # Workspace window count (exclude holding windows named _hold_*)
    local win_count
    win_count=$(tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null | grep -cv '^_hold_' || echo 0)

    # Attached marker
    local attached
    attached=$(tmux display-message -t "$session" -p '#{session_attached}' 2>/dev/null) || attached=0
    if [[ "$attached" -gt 0 ]]; then
      attached="*"
    else
      attached=""
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$session" "$dir" "$tools" "$win_count" "$attached"
  done <<< "$sessions"
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

  local out="" seen=" "
  local o line
  for o in "${order_arr[@]}"; do
    line=$(printf '%s\n' "$data" | awk -F'\t' -v n="$o" '$1==n{print; exit}')
    [[ -z "$line" ]] && continue
    out+="$line"$'\n'
    seen+="$o "
  done
  local name rest
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
