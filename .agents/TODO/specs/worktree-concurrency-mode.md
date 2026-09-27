# Spec: per-pane worktree isolation

Companion to the task `../backlog/worktree-concurrency-mode.md`. The task file holds the brief
and the acceptance criteria. This file holds the design. Every decision here was made with the
user on 2026-09-28, so an executor implements it as written. If a premise proves false, stop and
report it. Don't redesign.

Grounded in a read of the code at `1d98cd8` (lazy-llm `main`), git 2.55.0, tmux 3.7c, Claude
Code 2.1.283.

## 1. Goal and scope

Two or more agents in one workspace currently share one working tree, so their checkouts,
staging and commits collide. This adds an **opt-in, per-pane** isolated AI pane. It runs in its
own git worktree, on its own branch, and merges its work back into the branch the workspace is
on.

- **Explicit non-default.** A pane added the usual way (`a`, `llm-add`) behaves exactly as
  today. No worktree is created and nothing extra is checked.
- **Easy to back out.** Everything new sits behind the `--isolate` flag and the `A` key. The
  only change to existing behavior is the prerequisite fix in §2, which is a bug fix either way.

Out of scope for v1: an editor that follows the visible pane automatically, isolated panes for
tools other than Claude beyond the env vars and helper (§7.3), and an isolate-by-default setting
per workspace.

### 1.1 The invariant this relaxes

`worktree-per-task-primitive` said a workspace has exactly one working directory. That still
holds for the **workspace**: `@lazy_llm_dir`, the editor and prompt nvims, nvim sessions, notes
and prompt files all stay rooted in the main directory. Only an isolated AI pane's own process
runs somewhere else. nvim's cwd never changes.

Two kinds of worktree, kept distinct:

| | Task worktree (existing) | Pane worktree (new) |
|---|---|---|
| Created by | `lazy-llm -W`, Worktrees tab `n` | `llm-add --isolate`, dashboard `A` |
| Bound to | a whole workspace | one AI pane in a workspace |
| Branch | named by the user | generated, `lazy/<ws>/<tool>-<n>` |
| Lifetime | managed by the user | ends when the pane closes, after asking (§8) |
| Work goes back | however the user likes | agent runs `llm-wt integrate` in logical units (§7) |

## 2. Prerequisite fix: the workspace directory comes from `@lazy_llm_dir`

Three places treat the active pane's `#{pane_current_path}` as the workspace directory. Once a
pane can live in a worktree, all three go wrong:

- `lazy_llm_gather_sessions` (`lazy-llm-lib.sh`, `[[ "$act" == "11" ]] && dir="$path"`).
  `lazy_llm_find_session_for_path` builds on it, and so does `lazy_llm_cleanup_worktree`. With
  an isolated pane focused, cleaning up that pane's worktree would match **the whole workspace**
  and kill it. The Worktrees tab and `-W` dedup would also treat the workspace as bound to the
  pane's worktree.
- `llm-add` (`target_dir=$(tmux display-message … '#{pane_current_path}')`). A shared pane added
  while an isolated one is focused would start inside that worktree.
- The same pattern in `lazy-llm-lib.sh` near line 1000.

Fix: read `@lazy_llm_dir` (session option), and fall back to the current behavior only when it's
unset. For `gather_sessions`, add `#{@lazy_llm_dir}` to the single `list-panes -a -F` format, so
it costs no extra tmux call. Land this first, in its own commit, with a test that focuses a pane
whose cwd is elsewhere.

## 3. User surface

| Where | Surface |
|---|---|
| CLI | `llm-add --isolate [-t tool]` (short form `-i`) |
| Dashboard, Workspaces tab | `A`: same tool picker as `a`, then creates an isolated pane. `a` is unchanged. |
| Tree row, pane border | `⎇ <branch-suffix>` after the pane label, e.g. `claude-2 ⎇ claude-2` |
| Worktrees tab | pane worktrees are tagged `pane: <ws>/<label>`, or `orphaned` when the pane is gone (§9) |
| nvim | `<leader>llmw`: toggle the current buffer between the main copy and the visible pane's worktree copy (§10) |
| Agent | `llm-wt status`, `llm-wt integrate` (§7), plus the Claude skill and session context |

## 4. Creating an isolated pane

`llm-add --isolate` does the following, in order. Any failure aborts before a pane is created.

1. Resolve `primary=@lazy_llm_dir`. Require a git repo there. Require a branch to be checked
   out (not a detached HEAD); call it `base`.
2. If `git -C "$primary" status --porcelain` isn't empty, warn but don't block: "The isolated
   pane starts from `<base>` HEAD and won't see your uncommitted changes."
3. Pick `n`: the smallest integer ≥ 2 such that branch `lazy/<ws>/<tool>-<n>` doesn't exist.
   `<ws>` is the session name, with `/` and spaces made safe.
4. Create the worktree with `lazy_llm_setup_worktree`, extended with two optional args:
   `lazy_llm_setup_worktree <branch> [base_dir] [start_point]`.
   - `base_dir` is `${LAZY_LLM_WORKTREE_DIR:-$repo/.worktrees}/.panes`.
   - `start_point` is `base`.
   - Existing callers pass neither and see no change.
   - The `.gitignore` guard still covers `.worktrees/`.
   - The directory is `.worktrees/.panes/lazy-<ws>-<tool>-<n>`.
5. Record ownership in **git config**, so it outlives tmux and is readable from inside the
   worktree:
   - `branch.<branch>.lazyLlmBase <base>`
   - `branch.<branch>.lazyLlmPrimary <primary>`
6. Bootstrap untracked files (§5), then run the init hook if there is one (§5.3). If the hook
   fails: warn, keep the pane, and report the hook's exit code.
7. Create the pane with `lazy_llm_add_ai_pane`, passing the worktree as `target_dir` and a launch
   command with an env prefix:
   `LAZY_LLM_WORKTREE=1 LAZY_LLM_PRIMARY_DIR='<primary>' LAZY_LLM_BASE_BRANCH='<base>' claude`.
   A prefix instead of `split-window -e` means the same string works for restore (§11) and for
   pane 0 of a restored window, and `lazy_llm_add_ai_pane` keeps its signature.
8. Set the pane option `@lazy_llm_wt <worktree path>` (`set-option -p`). The border, tree, close
   flow and persist all read it.
9. Cycle to the new pane, as `llm-add` does today.

## 5. Untracked files in a fresh worktree

A new worktree holds tracked files only. Untracked files fall into three kinds:

| Kind | Example | At creation | At close |
|---|---|---|---|
| Shared config | `.env*`, `.claude/settings.local.json` | **link**: symlink to the main copy | nothing, unless the link was replaced (§5.4) |
| Per-pane copy | a local config the agent may change | **copy**, checksum recorded | changed → copy back / diff / discard (§8) |
| Generated | `node_modules`, build output | init hook | disposable; counted in the warning only |

### 5.1 Config file

gitignore-style, one entry per line, parsed in pure bash:

```gitignore
# ~/.config/lazy-llm/worktree-files      (global)
# <repo>/.lazy-llm/worktree-files        (per repo, appended after the global list)

.env*                          # no prefix = link
.claude/settings.local.json
copy: config/local.yml         # own copy per pane
copy: .venv/
!.env.production               # exclude paths matching this glob from anything above
```

- Patterns are bash globs relative to the repo root, with `dotglob` and `nullglob` on. A trailing
  `/` means a directory.
- Blank lines and `#` comments are ignored, including trailing ` # …` comments.
- If neither file exists, the default list is `.env*` and `.claude/settings.local.json`, both
  linked.
- `<repo>/.lazy-llm/` is already lazy-llm's gitignored per-project state directory, so this
  config is personal and imposes nothing on other people who use the repo.

### 5.2 Eligibility

Each glob is expanded in the **main directory**. A match is linked or copied only if it is **not
tracked**, meaning `git -C "$primary" ls-files --error-unmatch -- <path>` fails. Linking over a
checked-out file would corrupt the worktree. A pattern that matches nothing is skipped silently.
Parent directories are created as needed.

### 5.3 Init hook

This is the executable `<repo>/.lazy-llm/worktree-init`. It runs with cwd set to the new
worktree, after step 5.2, with `LAZY_LLM_PRIMARY_DIR`, `LAZY_LLM_BASE_BRANCH` and
`LAZY_LLM_WORKTREE` exported. Whether it runs `npm ci` or symlinks `node_modules` is the repo's
choice. Its output goes to the dashboard's stderr, so it shows in the popup.

### 5.4 Bootstrap manifest

Written to `<git-dir of the worktree>/lazy-llm-bootstrap`, which is inside
`.git/worktrees/<name>/` and so is never in the working tree. One line per entry:
`link<TAB><path>` or `copy<TAB><path><TAB><sha256>`. For a copied directory the hash is the
sha256 of its sorted `find -type f -exec sha256sum` output.

A tool that saves by writing a temp file and renaming it replaces a symlink with a regular file.
At close, a `link` entry that is no longer a symlink is treated as a **changed copy**, so its
contents aren't lost silently.

## 6. Agent awareness

- **Detection.** `LAZY_LLM_WORKTREE=1` in the tool's environment (§4 step 7). The helper reads
  everything else from git config, so it doesn't depend on the env.
- **Claude, session context.** `llm-claude-hook` on `SessionStart`: when `LAZY_LLM_WORKTREE=1`,
  print hook JSON with `hookSpecificOutput.additionalContext`. Keep it short: "You are in an
  isolated git worktree `<path>` on branch `<branch>`, split from `<base>` in `<primary>`. Commit
  here. Integrate finished logical units with `llm-wt integrate`. Don't edit files under
  `<primary>` directly." It must still do its existing status work, and stay a no-op otherwise.
- **Claude, skill.** `claude-plugin/skills/lazy-llm-worktree/SKILL.md`. It triggers when working
  in a lazy-llm isolated worktree, or when `LAZY_LLM_WORKTREE` is set. Content:
  - where the agent is and why (other agents share the main directory);
  - commit in logical units, and integrate each finished unit rather than hoarding them until
    the end, since short-lived divergence means fewer conflicts;
  - how to read `llm-wt status`;
  - what each `llm-wt integrate` exit code means and what to do about it (§7);
  - never check out `<base>`, never write under `<primary>`, never force.

  The plugin runs from a cached copy, so the skill ships with a plugin version bump, the same
  way `hooks.json` changes do.
- **Other tools.** They get the env vars and `llm-wt`. v1 has no injected guidance for them.
  That's a follow-up (§15).

## 7. `llm-wt`: status and integrate

A new stow package, `llm-wt-bin/.local/bin/llm-wt`, added to `STOW_PACKAGES` in `install.sh`. It
sources `lazy-llm-lib.sh` the same way `llm-add` does. Every subcommand takes an optional
worktree path and defaults to the cwd's worktree. It refuses with exit 2 when the branch has no
`lazyLlmBase` config.

### 7.1 `llm-wt status [path] [--porcelain]`

Reports the loss categories the close flow uses:

- `dirty`: tracked changes, count;
- `untracked`: untracked, non-ignored files, count;
- `unintegrated`: `git rev-list --count <base>..<branch>`;
- `copies-changed`: manifest entries whose hash changed, or links that were replaced;
- `ignored-extra`: ignored files not in the manifest, count only.

`--porcelain` prints `key<TAB>value` lines. The close flow and the tests use that.

### 7.2 `llm-wt integrate [path]`

1. **Dirty?** If the worktree has uncommitted changes, exit 3: "commit first". Only committed
   units are integrated.
2. **Main directory moved?** If `git -C <primary> branch --show-current` isn't `<base>`, exit 4:
   "the main directory is on X now; ask the user".
3. **Rebase.** Run `git rebase <base>` in the worktree. On conflict, leave the rebase in
   progress and exit 5 with the conflicted files: "resolve, `git rebase --continue`, run
   integrate again". Conflicts are resolved in the isolated tree, which is the point of the
   feature.
4. **Fast-forward.** Run `git -C <primary> merge --ff-only <branch>`.
   - If `<base>` moved in the meantime (another agent integrated), go back to step 3. Give up
     after 3 attempts with exit 6.
   - If git refuses because uncommitted changes in the main directory would be overwritten, exit
     7 and list the files: "tell the user; don't touch the main directory".
5. **Report.** Print the commits integrated (`--oneline`). Exit 0.

Never used: `--force`, `stash`, `update-ref`, `reset`, or `checkout` in the main directory.
Fast-forwarding does update files in the main directory while another agent or the editor may be
using them. That's the same kind of concurrent change the shared mode already has, and nvim's
autoread covers the editor.

## 8. Closing an isolated pane

This covers `llm-remove` (dashboard `K`, CLI) on a pane with `@lazy_llm_wt`. The user chose
**always ask**.

1. Run `llm-wt status --porcelain` and show a summary:
   - uncommitted changes (N files);
   - untracked files (N);
   - commits not integrated into `<base>` (N), with a hint to run `llm-wt integrate` first;
   - changed or replaced bootstrap copies (list);
   - ignored files that will be deleted (N).
2. Ask, using fzf the same way `pane-remove` does today. Options:
   - **Remove worktree and branch**
   - **Keep worktree** (it stays in the Worktrees tab)
   - **Cancel** (the pane isn't removed)

   The first option is the preselected one only when every category that loses work is zero.
   Otherwise **Keep** is.
3. If "Remove" and any copies changed: for each one, choose **copy back** (overwrite the main
   copy), **show diff** (then ask again), or **discard**.
4. Kill the pane (existing `llm-remove` path). On "Remove", call
   `lazy_llm_cleanup_worktree <path> yes <force>`. `force` is `yes` only when the summary showed
   uncommitted or untracked files and the user still chose Remove. §2 is what makes this call
   safe.

Also:
- **The tool exits, or the pane is pruned** (`lazy_llm_prune_stale_panes`). There's nobody to
  ask, so the worktree is left in place and the Worktrees tab shows it as `orphaned` (§9).
- **Workspace close** keeps the workspace, and restore brings the pane back (§11).
- **Workspace kill** leaves the worktrees as orphans. Listing them in the kill confirmation is a
  follow-up (§15).

## 9. Worktrees tab

`lazy_llm_gather_worktrees` gets one more column: the owner, taken from the `lazyLlmBase`
config. Its value is `pane:<session>/<label>` when some live pane's `@lazy_llm_wt` matches the
path, `orphaned` when none does, and empty for task worktrees. Rows render the tag. Actions on
pane worktrees:

- **Enter** on a live one focuses the owning pane (switch to the session, cycle to its index)
  instead of `lazy-llm -W`. On an orphan, Enter asks: "re-attach as an isolated pane in
  `<session>`" if that workspace is open, or "open as a task workspace" (`-W`).
- **`K`** runs the §8 flow (summary, copy reconciliation, cleanup). This reuses the existing
  warnings.
- **`g`** (lazygit) is unchanged. It's the review path for an agent's work.

## 10. nvim: `<leader>llmw` counterpart toggle

This goes in `nvim-llm-send-plugin`. nvim's cwd is never changed.

- Resolve the visible AI pane: the window's `@AI_PANE_ID`, then that pane's `@lazy_llm_wt`.
- If the current buffer is under the main directory, open the same repo-relative path under the
  worktree with `:edit`. It's a normal, **editable** buffer.
- If the buffer is under any pane worktree, open the main-directory counterpart.
- If the visible pane isn't isolated, notify and do nothing. If the counterpart doesn't exist
  (the file is new on one side), notify.
- Keep the cursor line.
- Marker: set `b:lazy_llm_wt = <branch>` and show `⎇ <branch>` in the winbar. Check whether
  dropbar can take a custom segment. If not, use a `WinBar` fallback just for those buffers.

**Required fix to references.** Code references (`<leader>llmr` / `R`, `expand("%:.")`) and the
note plugin's `get_relative_path` build paths relative to nvim's cwd or its git root. For a buffer
inside a pane worktree, that yields `.worktrees/.panes/…/src/x`, which doesn't resolve from the
agent's cwd. Both must compute the path relative to **the buffer's own git toplevel**
(`git -C <buffer dir> rev-parse --show-toplevel`, cached per buffer). References from buffers in
the main directory don't change.

`@` path completion in the prompt pane stays rooted at the main directory. A relative path sent to
an isolated agent then resolves to that agent's copy, which is correct.

## 11. Persistence (`llm-persist`)

- **Save.** When a pane has `@lazy_llm_wt`, add
  `worktree: {path, branch, base, primary}` to its manifest entry. The existing `cwd` field
  already holds the worktree path.
- **Restore.** For a pane with `worktree`:
  - if the path is a registered worktree, launch there as today;
  - else, if the branch exists, recreate it with `lazy_llm_setup_worktree <branch> <base_dir>`,
    then rerun the bootstrap (§5);
  - else, restore it as a **shared** pane in the main directory, and log a warning.

  Either way, prefix the launch command with the §4 env vars and set `@lazy_llm_wt` on the new
  pane id.
- `claude --resume` finds the conversation because the pane relaunches in the same cwd.

## 12. Display

- `llm-pane-border`: when the pane has `@lazy_llm_wt`, append `⎇ <branch minus lazy/<ws>/>`.
- Dashboard tree row: the same marker. The data comes from the one `list-panes` call the tree
  already makes (add `#{@lazy_llm_wt}` to its format). No extra tmux calls.

## 13. Files and coordination

| File | Change |
|---|---|
| `llm-send-bin/.local/bin/lazy-llm-lib.sh` | §2 fixes; `setup_worktree` args; owner column in `gather_worktrees`; bootstrap helpers |
| `llm-add-bin/.local/bin/llm-add` | `--isolate`, §2 target dir |
| `llm-remove-bin/.local/bin/llm-remove` | §8 flow for isolated panes |
| `lazy-llm-bin/.local/bin/llm-dashboard` | `A`, tree marker, Worktrees tab owner/Enter/K |
| `lazy-llm-bin/.local/bin/llm-persist` | §11 |
| `lazy-llm-bin/.local/bin/llm-pane-border` | §12 |
| `llm-status-bin/.local/bin/llm-claude-hook` | §6 SessionStart context |
| `claude-plugin/skills/lazy-llm-worktree/SKILL.md`, `plugin.json`, `marketplace.json` | skill, version bump |
| `llm-wt-bin/.local/bin/llm-wt` (new), `install.sh` | §7 |
| `nvim-llm-send-plugin/…/llm-send.lua`, `nvim-note-plugin/…/note.lua` | §10 |
| `README.md`, `docs/USAGE.md` | user surface, config file, `llm-wt` |

As of 2026-09-28 the workspace-save-restore session is editing `llm-persist`, `llm-dashboard` and
`lazy-llm-lib.sh`. Coordinate with it (or wait) before touching those three files.

Suggested commit order: §2 fix → lib helpers + `llm-wt` → `llm-add --isolate` + border → close
flow → dashboard → persist → nvim → Claude hook + skill → docs.

## 14. Tests (`tests/scenarios/22-…`, the next free number)

Unit tests, sandboxed (temporary repo, private tmux socket):

- **§2 regression.** A pane focused with its cwd elsewhere: `gather_sessions` still reports
  `@lazy_llm_dir`, and `find_session_for_path <that cwd>` returns nothing.
- **`setup_worktree`.** With `base_dir` and `start_point`: the path is right and the branch
  starts at the start point. Existing call sites are unchanged.
- **Bootstrap.**
  - A link entry becomes a symlink.
  - A copy entry becomes a copy, and its hash is in the manifest.
  - A pattern matching a tracked file is skipped.
  - `!` negation excludes.
  - The default list applies when there's no config file.
  - The init hook runs in the worktree with the env set.
- **`llm-wt status --porcelain`.** Each category is counted, including a link that was replaced.
- **`llm-wt integrate`.**
  - Fast-forward happy path.
  - A dirty worktree → 3.
  - The main directory on another branch → 4.
  - A conflict → 5, with the rebase left in progress.
  - Base moved → retries, then succeeds.
  - Dirty overlap in the main directory → 7, with the main directory untouched (compare the
    `git status` output before and after).
- **Close flow.** The preselected choice follows the loss categories. Remove deletes the worktree
  and branch and leaves the workspace alive.
- **Persist.** A worktree field round-trips. Restore recreates a missing worktree from its
  branch, and falls back to shared when the branch is gone.

Manual:
- In a real workspace: `A` → claude. Ask it to make two commits and integrate. The main
  directory fast-forwards.
- Close the pane with unintegrated work: the warning shows it, and Keep leaves the pane in the
  Worktrees tab as orphaned.
- `<leader>llmw` both ways, and a reference sent from a worktree buffer.

## 15. Follow-ups (not in v1)

- Guidance for non-Claude tools: a git-excluded guidance file, or a first message sent to the
  pane.
- Workspace kill lists the pane worktrees it will orphan.
- An automatic "follow" mode for `<leader>llmw` on cycle.
- An isolate-by-default setting per workspace.

## 16. Checks to run during execution

- Claude Code's `SessionStart` hook accepts `hookSpecificOutput.additionalContext` in the version
  installed. Confirm against the current hooks docs.
- Whether Claude Code rewrites `.claude/settings.local.json` in a way that replaces the symlink
  (write to a temp file, then rename). §5.4 handles either case. Record which one happens.
- dropbar custom winbar segment support (§10).
- `set-option -p` pane options survive `swap-pane` into and out of the hold window. They should,
  since they belong to the pane and not to its position. Verify.
