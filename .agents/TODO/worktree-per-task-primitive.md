---
slug: worktree-per-task-primitive
title: Add worktree-per-task primitive to lazy-llm
priority: P1
status: pending
created: 2026-05-13
updated: 2026-05-13
depends-on: []
tags: [enhancement, git, worktree, lazy-llm]
commits: []
---

# Add worktree-per-task primitive to lazy-llm

## Context

Inspired by `nielsgroen/claude-tmux`'s worktree workflow: spawning a fresh tmux session pointed at a per-branch git worktree so multiple parallel agent attempts on different branches don't step on each other.

Today, the only way to get there with lazy-llm is to manually run `git worktree add` and then `lazy-llm -d <path> -s <name>`. We want a first-class one-shot primitive.

### Worktree binding is session-scoped

Worktree association is a property of a **lazy-llm session**, not of individual panes. All panes in a session share the same working directory:
- The AI pane, editor pane, and prompt pane all start in the worktree path
- `@` path completion, code references (`<leader>llmr`), and NOTE collection all rooted at the worktree
- Within one session, you can still add multiple AI panes (existing multi-AI tabbing) — they all share the worktree

Mixing scopes (e.g. AI pane in worktree, nvim pane in repo root) would break the path-rooting assumptions all over the codebase. Session = one working directory, full stop.

This implies: **adding a worktree-bound pane to an existing session that's rooted elsewhere is not supported.** The way to work on a worktree is to spawn (or attach to) a session bound to it.

### CLI surface

```
lazy-llm -W <branch>             # spawn session bound to <branch>'s worktree (create branch + worktree if needed)
lazy-llm -W <branch> -t gemini   # combined with tool selection
lazy-llm worktree <branch>       # alias subcommand form
```

Behavior:
- If the branch exists: create a worktree for it (error if it's checked out elsewhere; suggest attaching to the existing session if one is found there)
- If the branch doesn't exist: create the branch from current HEAD, then create the worktree
- If a lazy-llm session already exists pointing at that worktree path: attach to it instead of spawning a duplicate
- Worktree location: project-relative convention — default `.worktrees/<branch>/` inside the repo, with override via env var or flag
- Spawn the lazy-llm session inside that worktree using existing `-d`/`-s` plumbing
- Session name auto-derives from the branch name (sanitized; collision resolution by suffix counter, same pattern existing code already uses)
- **Inside-tmux behavior**: even when invoked from inside an existing tmux session, `-W` always spawns a *new* session (not a new window in the current one), because the worktree binding is session-scoped. Document this clearly so it doesn't surprise users who expect `-W` to compose with the existing "auto-add window in tmux" behavior.

Companion lifecycle management lives in [[worktrees-dashboard]].

## Key Files

- `lazy-llm-bin/.local/bin/lazy-llm` — argparse, subcommand dispatch (already has `list`, `kill`, `sessions` subcommands), add worktree path
- `lazy-llm-bin/.local/bin/lazy-llm-lib.sh` — shared helpers for branch/worktree validation
- Possibly a new `lazy-llm-bin/.local/bin/llm-worktree` if the logic warrants extraction (mirrors existing `llm-*` script pattern)

## Acceptance Criteria

- [ ] `lazy-llm -W <branch>` (or equivalent) creates a worktree if needed and opens a lazy-llm **session** bound to it
- [ ] Worktree binding is session-scoped: all panes in the spawned session start in the worktree path
- [ ] When invoked from inside an existing tmux session, `-W` still spawns a new session (does not add a window to the current one) — and this is documented in help text and README
- [ ] If a lazy-llm session already exists pointing at the same worktree, attach to it instead of duplicating
- [ ] If the branch is new, the branch is created from current HEAD; if it exists, the existing branch is used
- [ ] Refuses gracefully if the branch is already checked out in another worktree (with an actionable message — e.g. "session `<name>` is already running there; attach with `lazy-llm -s <name>`")
- [ ] Worktree base path is configurable (env var or flag); has a sensible default (e.g. `.worktrees/<branch>/`)
- [ ] Worktree path is added to `.gitignore` automatically if using the in-repo default, OR the default lives outside the repo — decide during planning and document the choice
- [ ] Help text (`lazy-llm -h`) documents the new flag/subcommand and the session-scoped behavior
- [ ] Manual verify: from a clean repo with `main` checked out, run `lazy-llm -W feature/foo` from inside an existing tmux session — a new session is created (not a new window), worktree exists at the default location, all panes are rooted there
