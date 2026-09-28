# You are in an isolated git worktree (lazy-llm)

This session runs in its own worktree, `{{path}}`, on branch `{{branch}}`,
split from `{{base}}` in the main directory `{{primary}}`. Other agents and the
user work in the main directory at the same time. Your worktree keeps your
checkouts, staging and commits from colliding with theirs.

## Rules

- Work and commit only inside `{{path}}`. Never write files under `{{primary}}`,
  never `git checkout {{base}}` (it is checked out there), never force, stash
  or reset anything in the main directory.
- Commit in logical units. When a unit is finished, integrate it right away
  with `llm-wt integrate`. Don't hoard commits until the end: the longer your
  branch diverges, the more conflicts you'll resolve.
- `llm-wt status` shows what's uncommitted, untracked and not yet integrated.
  `llm-wt sync` brings in what others have integrated, without integrating
  anything.
- Branch hygiene is already settled: this branch is off `{{base}}` on purpose
  and integrates through `llm-wt integrate`. Don't ask the user about it, and
  don't push `{{branch}}`. After integrating a completed task, the usual push
  rule applies to `{{base}}`: scan `origin/{{base}}..{{base}}` for secrets, then
  `git push origin {{base}}`.
- Symlinked files (`.env*`, `.claude/settings.local.json`,
  `.agents/TODO/.work-state`) are the main directory's own, shared on purpose.
  Your file tools refuse to write through a symlink and name its target: write
  to that target in `{{primary}}`. It's the one exception to the rule above.
  Never replace the link with a file, and never `git add` it.

## `llm-wt integrate` exit codes

| Code | Meaning | Do |
|---|---|---|
| 0 | Fast-forwarded `{{base}}` (or nothing to integrate) | Carry on |
| 3 | Uncommitted changes | Commit them (or finish the unit), then rerun |
| 4 | The main directory isn't on `{{base}}` | Stop and tell the user |
| 5 | Rebase conflict; the rebase is left in progress | Resolve in `{{path}}`, `git add`, `git rebase --continue`, rerun |
| 6 | `{{base}}` kept moving | Rerun |
| 7 | The main directory has uncommitted changes to files you touch | Stop and tell the user which files; change nothing there |

## Task tracking (`.agents/TODO/`)

- `.work-state` is shared with every agent through the symlink, so the todo
  skill's multi-session rules apply as usual: an entry owned by a live pid is
  someone else's.
- Task files, `INDEX.md`, `REVIEW-QUEUE.md` and `CONTINUATION.md` are per
  branch. Your `[todo]` commits reach `{{base}}` through `llm-wt integrate`,
  like code commits.
- Claiming a task: `llm-wt sync` first, so you see what others have already
  claimed and integrated. Then commit the claim (status → in-progress) as its
  own `[todo]` commit, and `llm-wt integrate` it immediately so others see it.
- An `INDEX.md` conflict during a rebase: take either side, regenerate the
  index with the todo lint, `git add` it, and continue. Never hand-merge it.
