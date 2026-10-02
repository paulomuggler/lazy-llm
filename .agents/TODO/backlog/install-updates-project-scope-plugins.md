---
slug: install-updates-project-scope-plugins
title: install.sh should update project-scope lazy-llm plugin installs, not just the user scope
priority: P2
status: backlog
created: 2026-10-02_19:46
updated: 2026-10-02_19:46
depends-on: []
tags: [claude-plugin, install]
---

# install.sh misses project-scope plugin installs

## Context
Found deploying `claude-subagent-worktrees` (2026-10-02). `claude plugin update lazy-llm@lazy-llm`
auto-detects one scope. dev-env enables the plugin in its checked-in `.claude/settings.json`, so
Claude recorded a **project-scope** install at 0.3.0 for dev-env and for every pane worktree path
it opened. It stayed at 0.3.0 after install.sh, until `claude plugin update … --scope project` was
run by hand in dev-env. Stale entries for deleted worktree paths remain in
`~/.claude/plugins/installed_plugins.json`.

## Acceptance Criteria
- [ ] install.sh updates every project-scope lazy-llm install whose project path exists (`--scope project`, run from that path)
- [ ] It says which ones it updated; it leaves entries for missing paths alone (or prunes them, if the CLI supports it)
