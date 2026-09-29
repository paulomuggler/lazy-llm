#!/usr/bin/env bash
# Shim: hand the hook payload to lazy-llm's stowed llm-claude-hook, which holds
# all the logic (see its header). Kept this thin on purpose — Claude Code runs
# plugins from a cached copy, so anything here only updates on a plugin update,
# while ~/.local/bin/llm-claude-hook is a live symlink into the lazy-llm repo.
# No-op (exit 0) when lazy-llm's bins aren't installed: never fail Claude's flow.
hook="$HOME/.local/bin/llm-claude-hook"
[ -x "$hook" ] || exit 0
exec "$hook" "$@"
