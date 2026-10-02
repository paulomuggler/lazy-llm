<!-- lazy-llm:worktree-parent -->
lazy-llm: that subagent worked in its own worktree `{{path}}`, branch
`{{branch}}`, split from `{{base}}`. It has {{commits}} commit(s) to integrate,
{{dirty}} uncommitted change(s) and {{untracked}} untracked file(s). Its work
reaches `{{base}}` here (`{{primary}}`) only when you integrate it:

1. Review: `git -C {{path}} log --oneline {{base}}..` and
   `git -C {{path}} diff {{base}}...`
2. Land it: `llm-wt integrate --remove {{path}}`. That rebases the branch onto
   `{{base}}`, fast-forwards `{{base}}` here, then deletes the worktree and
   branch. It never forces, stashes or resets. Land one worktree at a time.
3. Or drop it: `llm-wt remove --force {{path}}`.

`llm-wt integrate` exit codes: 0 landed (or nothing to land) · 3 the worktree
has uncommitted changes: commit them there (`git -C {{path}} commit`) or drop
them · 4 this directory isn't on `{{base}}` any more: stop and tell the user
· 5 rebase conflict, left in progress in `{{path}}`: resolve there, `git -C
{{path}} add`, `git -C {{path}} rebase --continue`, rerun · 6 `{{base}}` kept
moving: rerun · 7 your own uncommitted changes here overlap the files it
touches: commit your own work first, then rerun. `--remove` refuses if
something would still be lost (untracked files): `llm-wt status {{path}}`.

`llm-wt list` shows every subagent worktree still waiting to land here. A
subagent's worktree starts from this directory's last commit, so commit your
own work before launching isolated subagents that need it.
