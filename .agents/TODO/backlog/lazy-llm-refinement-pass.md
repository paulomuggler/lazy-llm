---
slug: lazy-llm-refinement-pass
title: Refinement pass over lazy-llm feature space and codebase
priority: P3
status: backlog
created: 2026-05-13
updated: 2026-05-13
depends-on: []
tags: [refactor, audit, architecture, testability, tech-debt]
commits: []
---

# Refinement pass over lazy-llm feature space and codebase

## Context

After the dashboard, worktree, and keybinding work lands, do a full audit of lazy-llm. The goal isn't to ship a single big PR — it's to *map* the project's current state across these axes and produce a prioritized list of follow-up tasks. This task's deliverable is **the audit report + the resulting backlog of granular tasks**, not a refactor in one shot.

### Axes to audit

**Architectural cleanup**
- Cohesion of `lazy-llm-lib.sh`: is it growing into a god-library? Should some helpers be split (e.g. worktree helpers, status detection helpers)?
- Boundary between `lazy-llm` orchestrator and the `llm-*` workers — is dispatch consistent? Any subcommands that should be promoted/demoted?
- Naming: are all `llm-*` scripts pulling their weight? Any with overlapping purpose?
- nvim plugin layout: `docs/TODO.md` already flags "Split the llm-send.lua stuff into multiple plugin files, per feature" — verify whether that has been done and what's left.

**Missing / broken / incomplete / superseded features**
- Cross-reference the legacy `docs/TODO.md` against actual code state — anything marked done but actually broken? Anything still pending that's been superseded by newer work?
- Codex autosubmit issues (P1 in legacy TODO) — current state?
- Open the lid on every `WONT FIX` entry — still WONT FIX, or is the underlying issue fixable now?

**Streamlining / consolidation**
- Features that can be rolled into one (e.g. could `llm-sessions` and `llm-panes` be one binary with a mode flag?)
- Features that should be broken down (e.g. is `lazy-llm` doing too much in `main`?)
- Duplicate logic between bash scripts and nvim plugins (each pane-resolution path should have exactly one source of truth)

**Optimization**
- Tmux-call hot paths in inner loops (e.g. `gather_sessions` shells out per-session; can it batch with format strings?)
- Status-line refresh cost once status detection lands
- Startup latency of `lazy-llm` (how many `tmux` invocations on the cold path?)

**Testability gaps**
- Coverage of the `tests/` suite vs. shipped features — list features with no test coverage
- Can the mock AI tool be extended to exercise more status states (working/idle/waiting/unknown)?
- Integration tests for worktree flows once they exist
- Headless test for the live-preview dashboard (likely hard — at minimum unit-test the detection regexes)

**Documentation drift**
- `docs/TODO.md` vs `.agents/TODO/INDEX.md` — pick one as canonical; migrate or retire the other
- README accuracy: every keymap and CLI documented matches actual code

## Key Files

- All of `lazy-llm-bin/.local/bin/*`
- All of `nvim-*-plugin/`
- `tests/`
- `docs/TODO.md` (legacy, may need to migrate or retire)
- `README.md`, `USAGE.md`, `CONTRIBUTING.md`

## Acceptance Criteria

- [ ] Produce a written audit report (could live in `docs/audit-2026-05.md` or similar) covering every axis above
- [ ] Cross-reference legacy `docs/TODO.md` and either migrate live items to `.agents/TODO/` or retire the doc
- [ ] For each finding, create a granular follow-up task file in `.agents/TODO/` with appropriate priority and tags
- [ ] No code changes in this task — output is the report + new task files
- [ ] Promote from `backlog` to `pending` only after the higher-priority feature tasks above this one have shipped
