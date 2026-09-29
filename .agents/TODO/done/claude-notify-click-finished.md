---
slug: claude-notify-click-finished
title: Notifications — click to jump to the pane, "finished" notices, elicitation/subagent prompts
priority: P2
status: done
created: 2026-09-28_14:40
updated: 2026-09-28_15:00
depends-on: [claude-notify-detail]
tags: [hooks, notifications, claude-only, plugin]
commits: [11755cc]
model: inline
human-validation: pending
---

# Click-to-focus, finished notifications, more prompt types

## Done

- `llm-focus-pane <pane> [socket]`: switch the most recently active tmux
  client to the pane; on Hyprland focus the terminal window hosting that client
  (walk the client's parent pids to a Hyprland window; with several windows
  per process, as Ghostty has, prefer the one whose title names the client's
  session).
- Click wiring in `notify()`: Omarchy shell's `omarchy-exec-argv` hint (JSON
  argv; runs from history too, see /usr/share/omarchy/shell/plugins/
  notifications/Service.qml invokePopupDefault), plus a `default` action via
  `notify-send --wait` (capped 10m) for other daemons.
- Stop: "Claude finished: <title>" with the reply's opening line (jq, else
  field()), only when `lazy_llm_pane_is_focused` is false.
- Plugin 0.3.0: elicitation_dialog|elicitation_url_dialog|agent_needs_input →
  waiting.

## Verify

Sandbox tmux server + stub notify-send: hint/action args, headline stripping
and escaping, waiting path unchanged. llm-focus-pane on the live server
(own pane, 0.1s). Click test notification sent to the user.

## Known limits

- A Stop that another Stop hook blocks (work-loop continuation) still notifies
  "finished" once.
- macOS: osascript notifications have no click action.
