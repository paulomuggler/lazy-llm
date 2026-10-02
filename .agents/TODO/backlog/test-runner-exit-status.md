---
slug: test-runner-exit-status
title: tests/test-runner.sh exits 1 even when every scenario passes
priority: P3
status: backlog
created: 2026-10-02_19:09
updated: 2026-10-02_19:09
depends-on: []
tags: [tests]
---

# test-runner.sh exits 1 when everything passes

## Context
Found during `claude-subagent-worktrees` verification (2026-10-02): a full run reports
"Total tests run: 25, Passed: 25" and still exits 1. A single untouched scenario (12) does the
same. CI-style use (`tests/test-runner.sh && …`) can't trust the status.

## Acceptance Criteria
- [ ] The runner exits 0 when all run scenarios pass, non-zero otherwise
- [ ] A skipped (opt-in) scenario doesn't fail the run
