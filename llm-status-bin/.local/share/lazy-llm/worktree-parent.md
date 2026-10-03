<!-- lazy-llm:worktree-parent -->
lazy-llm: {{intro}} Its work reaches `{{base}}` here (`{{primary}}`) only when you integrate it.

- Land it: `llm-wt integrate --remove {{path}}` rebases it onto `{{base}}`, fast-forwards `{{base}}` here, then deletes the worktree and branch. It never forces, stashes or resets. Land one worktree at a time; review first with `git -C <worktree> log --oneline {{base}}..` and `git -C <worktree> diff {{base}}...`.
- Drop it: `llm-wt remove --force <worktree>`.
- Exit codes: 3, the worktree has uncommitted changes (commit them there, or drop) · 4, this directory left `{{base}}`: stop and tell the user · 5, rebase conflict left in progress in the worktree (resolve, `git add`, `git rebase --continue` there, rerun) · 6, `{{base}}` kept moving: rerun · 7, your own uncommitted changes here overlap: commit them, rerun. If `--remove` refuses (untracked files left), see `llm-wt status <worktree>`.

`llm-wt list` shows what's still waiting to land. Subagent worktrees start from this directory's last commit: commit your own work before launching ones that need it.
