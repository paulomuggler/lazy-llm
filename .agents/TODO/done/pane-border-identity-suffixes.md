---
slug: pane-border-identity-suffixes
title: AI pane border shows workspace - pane name - harness - model
priority: P2
status: done
human-validation: pending
created: 2026-09-25_00:00
updated: 2026-09-25_19:00
depends-on: []
tags: [ux, pane-border, status-detection]
commits: [a3c8e0e, 8281a38, 33bb87e, dev-env:0394034]
model: inline
---

# AI pane border shows workspace - pane name - harness - model

## Context

User request (2026-09-25): on the AI pane's border status ONLY (llm-pane-border — not
llm-status's status-right segment, not the dashboard), render the pane's identity as
`<workspace> - <pane name> - <harness> - <model>`, e.g.
`dev-env - dashboard-improvements - claude - sonnet5`. Also asked: can the model string
be obtained, and does it follow mid-session `/model` changes?

## Design

- Model source (claude): hooks, never scraping (user preference). SessionStart `model`,
  PostModelSwitch `to_model`, Stop transcript fallback. Stored per pane in
  `~/.cache/lazy-llm/model/<pane_id>` (pid-guarded).
- Scope grew mid-task (user request): lazy-llm now owns its Claude hooks as its own
  Claude Code plugin (`claude-plugin/`, marketplace at repo root, registered by
  install.sh from the GitHub remote) instead of a dev-env hook script + settings.json
  wiring. Target platforms: Linux + macOS (user: "as long as it works on linux and osx").
- Other harnesses: model segment omitted when unknown.
- Pane name segment omitted when the pane has no custom name (it would just repeat the
  harness).

## Acceptance Criteria

- [x] Border renders `ws - name - harness - model glyph` for a named claude pane
- [x] Unnamed pane / unknown model drop their segments instead of showing placeholders
- [x] Model follows a `/model` switch
- [x] llm-status and dashboard unchanged

## Work Report

**Date:** 2026-09-25

### What was done
- `lazy-llm-lib.sh`: per-pane model store (`lazy_llm_set_pane_model` / `lazy_llm_pane_model`,
  pid-guarded like unread markers) and `lazy_llm_short_model` (`claude-opus-5-5[1m]` ->
  `opus5.5[1m]`).
- `llm-pane-border`: `summary │ workspace - pane name - harness - model glyph`; pane name
  dropped when it'd repeat the harness, model dropped when unknown. llm-status unchanged.
- `llm-claude-hook` (stowed, in llm-status-bin): single handler for Notification / Stop /
  SessionStart / PostModelSwitch — merges dev-env's former `lazy-llm-status-notify.sh`
  and the new model tracking. Portable: no jq, `tac` falls back to `tail -r`,
  notification via notify-send or osascript.
- `claude-plugin/` + `.claude-plugin/marketplace.json`: lazy-llm's own Claude Code plugin;
  `hooks.json` -> `run.sh` shim -> `~/.local/bin/llm-claude-hook` (keeps logic live-editable
  rather than frozen in the plugin cache). `install.sh` registers the marketplace from the
  repo's GitHub remote (a local path would be baked into a dotfiles-managed
  settings.json and break on other machines) and installs/updates the plugin.
- dev-env: removed its lazy-llm hook script + settings.json hook entries; enables
  `lazy-llm@lazy-llm` from GitHub instead.
- README Status Detection section rewritten (unread, summary counts, border identity,
  plugin).

### Verification
- Tests 18 (13 assertions: shortening, store, border rendering) and 19 (11: every hook
  event path) new; 17 still green.
- Live, real Claude Code 2.1.282 on an isolated tmux server:
  - `claude -p` run: plugin hooks fired; Stop wrote idle + unread (pid-matched); found the
    transcript lacks the model at Stop time -> added retry; re-run recorded
    `haiku4.5` on attempt 2.
  - Interactive session: SessionStart payload DID carry `model`; `/model claude-sonnet-5`
    fired PostModelSwitch and updated the pane's model immediately.
- `install.sh` run end to end on this machine: stowed llm-claude-hook, registered the
  marketplace from GitHub, plugin shows enabled.

### Findings worth knowing
- Interactive `/model` (typed or picker) ALWAYS saves the pick to user settings
  (`~/.claude/settings.json` `model`), per the 2.1.282 source — only `claude -p` switches
  are session-only; `--model` at launch is session-only. Since dev-env stows that file,
  every `/model` dirties dev-env's working tree (this is what the earlier unexplained
  `"model"` diff was). My own live `/model` test also wrote to it; it was overwritten by a
  later `/model opus` of the user's before I could revert it — nothing left from the test.
- SessionStart's `model` is absent in `-p` mode, present interactively.

### Not verified
- macOS run (no Mac here) — the portable branches (`tail -r`, osascript) are untested.
- Existing Claude sessions pick up the plugin only on restart.
