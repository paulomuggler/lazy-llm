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
# Sets: AI_PANES, AI_TOOLS, AI_PANE_IDX, AI_HOLD_WIN, AI_TOOL
# Requires: _SESSION, _WINDOW
lazy_llm_read_multi_state() {
  AI_PANES=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_PANES 2>/dev/null) || true
  AI_TOOLS=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_TOOLS 2>/dev/null) || true
  AI_PANE_IDX=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_PANE_IDX 2>/dev/null) || true
  AI_HOLD_WIN=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_HOLD_WIN 2>/dev/null) || true
  AI_TOOL=$(tmux show-option -wv -t "$_SESSION:$_WINDOW" @AI_TOOL 2>/dev/null) || true
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

  local interrupt_pat='ctrl\+c to interrupt'
  local waiting_pat='\[[yY]/[yYnN]\]|^[[:space:]]*[1-9][.)][[:space:]]'
  local prompt_pat='❯'

  case "$tool" in
    claude|*)
      : # use defaults above
      ;;
  esac

  if grep -qE "$interrupt_pat" <<< "$content"; then
    echo working
  elif grep -qE "$waiting_pat" <<< "$content"; then
    echo waiting
  elif grep -qF "$prompt_pat" <<< "$content"; then
    echo idle
  else
    echo unknown
  fi
}

# Capture a pane's recent content and classify it.
# Args:   $1 pane_id   (required, %N format)
#         $2 tool_name (optional, default: claude)
# Stdout: working | idle | waiting | unknown
# Returns 0 always; emits "unknown" if capture fails.
lazy_llm_detect_pane_status() {
  local pane_id="${1:?pane_id required}"
  local tool="${2:-claude}"
  local content
  content=$(tmux capture-pane -p -t "$pane_id" -S -200 2>/dev/null) || { echo unknown; return 0; }
  printf '%s' "$content" | lazy_llm_detect_status_from_content "$tool"
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
