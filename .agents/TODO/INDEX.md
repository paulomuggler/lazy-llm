# TODO Index

_Auto-maintained. Edits will be overwritten by `/todo lint`._

## Active

### P1 — High

| Slug | Title | Status | Updated | Depends |
|------|-------|--------|---------|---------|
| [dashboard-shell-and-sessions-tab](dashboard-shell-and-sessions-tab.md) | Dashboard shell + sessions tab (live preview) | pending | 2026-05-13 | pane-status-detection ✓ |
| [worktree-per-task-primitive](worktree-per-task-primitive.md) | Add worktree-per-task primitive to lazy-llm | pending | 2026-05-13 | — |

### P2 — Normal

| Slug | Title | Status | Updated | Depends |
|------|-------|--------|---------|---------|
| [dashboard-panes-tab-and-prefix-l-retire](dashboard-panes-tab-and-prefix-l-retire.md) | Dashboard panes tab + retire Prefix+L | pending | 2026-05-13 | dashboard-shell-and-sessions-tab |
| [worktree-bridge-tab](worktree-bridge-tab.md) | Worktree bridge tab in unified dashboard (lazy-llm ↔ worktree view + cleanup) | pending | 2026-05-13 | dashboard-shell-and-sessions-tab, worktree-per-task-primitive |

## Backlog

### P3 — Low

| Slug | Title | Status | Updated | Depends |
|------|-------|--------|---------|---------|
| [lazy-llm-refinement-pass](backlog/lazy-llm-refinement-pass.md) | Refinement pass over lazy-llm feature space and codebase | backlog | 2026-05-13 | — |

## Done

| Slug | Title | Completed |
|------|-------|-----------|
| [pane-status-detection](done/pane-status-detection.md) | Pane status detection helper + llm-status integration | 2026-05-13 |
| [fix-llm-sessions-marker-bug](done/fix-llm-sessions-marker-bug.md) | Fix llm-sessions @lazy_llm marker scope mismatch (Prefix+S broken) | 2026-05-13 |

## Closed

| Slug | Title | Reason |
|------|-------|--------|
| [unified-llm-dashboard](closed/unified-llm-dashboard.md) | Unified lazy-llm dashboard popup (sessions / panes / worktrees tabs) | Split into 3 smaller tasks |
| [dense-keybindings-popup-scopes](closed/dense-keybindings-popup-scopes.md) | Dense single-letter keybindings within lazy-llm popups (replace Ctrl+ chords) | Absorbed into the dashboard split (built dense from inception) |
