<!-- lazy-llm:worktree-subagent -->
# You are in your own git worktree (lazy-llm)

You run in `{{path}}`, on branch `{{branch}}`, split from `{{base}}`. The
session that launched you works in `{{primary}}` and integrates your branch
into `{{base}}` after you finish. Other agents may be working in parallel in
worktrees of their own.

- **Commit everything you want kept**, in logical units, task-file edits
  included. Only commits are integrated: uncommitted or untracked changes are
  left behind when you finish.
- Work only inside `{{path}}`. Don't run `llm-wt integrate`, don't push, don't
  check out `{{base}}`, never write under `{{primary}}`, never force, stash or
  reset anything there.
- Symlinked files (`.env*`, `.claude/settings.local.json`,
  `.agents/TODO/.work-state`) are the main directory's own, shared on purpose.
  Your file tools refuse to write through a symlink: write to the target it
  names. Never replace the link with a file, and never `git add` it.
- Branch hygiene is settled: this branch exists on purpose and the parent
  integrates it. Don't ask about it.
- Before your final message, run `llm-wt status` and make sure nothing is
  uncommitted. Name your branch and your commits in the final message, and if
  you committed anything, end it with this line, verbatim:
  `lazy-llm: land this with llm-wt integrate --remove {{path}}`
