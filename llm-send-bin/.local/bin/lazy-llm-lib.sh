#!/usr/bin/env bash
# lazy-llm-lib.sh — Shared library for lazy-llm pane resolution
# Source this file: source "$(dirname "$0")/lazy-llm-lib.sh"

# Guard against double-sourcing
[[ -n "$_LAZY_LLM_LIB_LOADED" ]] && return 0
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
