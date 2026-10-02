#!/usr/bin/env bash
# Shim: Claude Code's worktree, subagent and session hooks → `llm-wt
# claude-hook` (stowed into ~/.local/bin, a live symlink into the lazy-llm
# repo, so its logic updates without a plugin update; see run.sh). It creates
# and removes Claude's worktrees through llm-wt and injects the worktree
# guidance. Unlike run.sh's events, these aren't tied to a tmux pane: they run
# outside tmux and for a `claude -p` started by an agent too.
#
# WorktreeCreate replaces Claude's own worktree creation: the hook's stdout IS
# the worktree path, and no path means the subagent (or EnterWorktree) fails.
# So it never comes up empty while git works: if llm-wt is missing or fails,
# this makes a plain worktree from HEAD, where Claude would, and says why on
# stderr. Every other event is a no-op (exit 0) without llm-wt.
#
# LAZY_LLM_WT_BIN overrides the llm-wt path (tests).

input=$(cat)

field() {
  printf '%s' "$input" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/'
}

wt_bin="${LAZY_LLM_WT_BIN:-$HOME/.local/bin/llm-wt}"
event=$(field hook_event_name)

if [ "$event" != WorktreeCreate ]; then
  [ -x "$wt_bin" ] || exit 0
  exec "$wt_bin" claude-hook <<< "$input"
fi

if [ -x "$wt_bin" ]; then
  out=$("$wt_bin" claude-hook <<< "$input")
  rc=$?
  path=$(printf '%s\n' "$out" | tail -n 1)
  if [ "$rc" -eq 0 ] && [ -n "$path" ] && [ -d "$path" ]; then
    printf '%s\n' "$path"
    exit 0
  fi
  why="llm-wt claude-hook failed (exit $rc)"
else
  why="llm-wt is not installed at $wt_bin"
fi

cwd=$(field cwd)
name=$(field name)
name=$(printf '%s' "${name:-worktree}" | tr -c 'A-Za-z0-9._-' '-')
top=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || {
  echo "lazy-llm: $why, and ${cwd:-$PWD} is not in a git repository" >&2
  exit 1
}
wt="$top/.claude/worktrees/$name"
echo "lazy-llm: $why; creating a plain worktree at $wt" >&2
git -C "$top" worktree add -b "worktree-$name" "$wt" HEAD >&2 || exit 1
printf '%s\n' "$wt"
