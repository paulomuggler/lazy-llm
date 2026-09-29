---
slug: claude-notify-detail
title: Permission notifications name the conversation, the pending command, and the pane
priority: P2
status: done
created: 2026-09-28_14:12
updated: 2026-09-28_14:30
depends-on: []
tags: [hooks, notifications, claude-only]
commits: [c48e639]
model: inline
human-validation: pending
---

# Permission notifications with detail

## Context

`llm-claude-hook`'s desktop notification on a permission prompt read
"lazy-llm: <session>:<window> / Claude needs your input": no way to tell which
conversation or what it wanted. The Notification payload carries `message`
(e.g. "Claude needs your permission to use Bash"), `cwd` and `transcript_path`;
the transcript carries `customTitle` (/rename) and `aiTitle` entries and the
pending `tool_use`.

## Done

- Title `Claude: <custom title | ai title | cwd basename>`.
- Body: payload message; pending command/path/URL from the latest unanswered
  tool_use (jq, optional, 4×0.25s retry for transcript lag; 140 chars);
  `<S:I> · <pane rename> · <cwd>`.
- Built in a detached subshell. notify-send body markup-escaped (Quickshell
  advertises body-markup; bash 5.2 needs the `&` replacements quoted),
  osascript strings quote-escaped.

## Verify

Sandbox tmux server (own HOME, stub notify-send): escaped body, debounce on a
repeated waiting, fallbacks with no transcript/label; one real notification.

## Follow-ups (not done)

- Other matchers (elicitation_dialog, agent_needs_input) aren't wired in the
  plugin's hooks.json, so those prompts don't notify.
- A click action to focus the pane (the daemon supports actions).
