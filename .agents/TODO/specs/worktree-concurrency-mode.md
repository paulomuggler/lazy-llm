# Spec: per-pane worktree isolation

Companion to the task `../backlog/worktree-concurrency-mode.md`. The task file holds the brief
and the acceptance criteria. This file holds the design. Every decision here was made with the
user on 2026-09-28, so an executor implements it as written. If a premise proves false, stop and
report it. Don't redesign.

Grounded in a read of the code at `1d98cd8` (lazy-llm `main`), git 2.55.0, tmux 3.7c, Claude
Code 2.1.283.

Revision 2 (2026-09-28, after the user's review):
- The agent guidance loads **only in isolated panes**. It's injected by the `SessionStart` hook,
  not shipped as a plugin skill that every session would list (§6).
- TODO-system integration is spelled out. `.agents/TODO/.work-state` is **shared** by linking,
  while task files travel with each branch (§6.1).
- `a` with an isolated pane visible offers to add into that same worktree, with a confirm
  dialog (§3.1). A worktree can have several panes; only the last one to close asks about the
  worktree (§8).
- The AI pane's border gets a git segment: branch, commit, upstream, ahead/behind, dirty, and
  which worktree (§12).
- A literal-path link entry is linked even when the main directory lacks the file, so the first
  write creates it there (§5.2).
- New `llm-wt sync` subcommand (§7.3).

Implementation notes (2026-09-28, `e30c8bb`..`010be85`). Where the code differs from the text below:
- **`llm-wt` subcommands.** `close <path> [--default]` asks, reconciles changed copies, and
  prints `remove` / `keep` / `cancel`. `remove <path> [--force]` deletes the worktree and branch.
  `llm-remove` kills the pane between the two calls. Also added: `info` (worktree, branch, base,
  primary). `close` answers `keep` when there's no terminal to ask on.
- **Ignoring.** `.worktrees/` and bootstrapped paths go to `.git/info/exclude`, each under a
  `# lazy-llm worktree bootstrap` line. Creating a pane never edits the tracked `.gitignore`,
  and an agent can't `git add` a link.
- **Save/restore.** The manifest stores `worktree: {path, branch}`. Base and main directory are
  read from the branch's git config. When the pane comes back shared because its branch is gone,
  it also starts a fresh conversation, since `--resume` can't find it from another directory.
- **Worktrees tab.** Enter on an orphan offers only "add a pane in it, in the current workspace".
  Opening it as a task workspace (`-W`) can't work: its branch is already checked out at the
  pane-worktree path. K on a pane worktree whose pane is still open says to close the pane first.
- **nvim.** The module is `nvim-llm-send-plugin/.config/nvim/lua/lazy_llm_worktree.lua`, at the
  top level, because `lua/lazy_llm/` is a stow-folded symlink into the session plugin. The
  winbar marker is a dropbar source that reads `b:lazy_llm_wt`. References from a worktree
  buffer carry the main copy's cwd-relative path, which matches the pane's subdirectory offset.
- **Bugs fixed on the way.**
  - The Worktrees tab truncated long paths and then used the truncated text as the path
    (Enter/g/K silently did nothing). It now carries the full path in a hidden field.
  - `lazy_llm_gather_worktrees` rows were tab-separated, so empty fields shifted the columns
    after them. Rows are now `\x1f`-separated, with the new OWNER column.
- **§16 results.**
  - `SessionStart` `additionalContext`: confirmed against the docs. It fires on startup, resume,
    clear, compact and fork. The limit is 10k characters; the guidance is about 3k.
  - Pane options survive `swap-pane`: confirmed (scenario 22, test 11).
  - Claude Code's Edit/Write **refuse** to write through a symlink and name its target, so they
    never replace a link. The guidance tells the agent to write to the target.
  - Whether granting a permission rewrites a symlinked `.claude/settings.local.json` is **not
    verified**. The close flow catches a replaced link either way (§5.4).
  - dropbar custom source: implemented, but the winbar rendering is untested headless.

Revision 3 (2026-09-28 evening, with the user): **naming.** This replaces the naming in §4
steps 3–4 and in §3.
- `A` asks for a name, pre-filled with `<repo>-wt-<n>`, where `<repo>` is the basename of the
  workspace's repo root. `llm-add -i [-n name]` works the same way.
- That one name is the worktree's directory (`.worktrees/.panes/<name>`), its branch
  (`lazy/<name>`) and the pane's label.
- It's set once. A pane rename changes only the label: the branch stays a stable identifier,
  and a running agent's directory never moves. Moving it would break its cwd, Claude's resume
  lookup and the saved state.
- A name that's already taken is refused, not suffixed.
- The name carries no tool or commit hash. A hash is stale after the first sync; the base
  branch lives in git config and shows on the border.
- Existing `lazy-<ws>-<tool>-<n>` worktrees keep their names.

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
| Dashboard, Workspaces tab | `A`: same tool picker as `a`, then creates a new isolated pane. `a`: unchanged, except when the visible AI pane is isolated (§3.1). |
| CLI | `llm-add --worktree <path>`: add a pane into an existing pane worktree. `--isolate` and `--worktree` are mutually exclusive. |
| Tree row | `⎇ <branch-suffix>` after the pane label, e.g. `claude-2 ⎇ claude-2` |
| AI pane border | git segment (§12) |
| Worktrees tab | pane worktrees are tagged `pane: <ws>/<label>`, or `orphaned` when the pane is gone (§9) |
| nvim | `<leader>llmw`: toggle the current buffer between the main copy and the visible pane's worktree copy (§10) |
| Agent | `llm-wt status`, `llm-wt integrate` (§7), plus the Claude skill and session context |

### 3.1 `a` while an isolated pane is visible

In the dashboard, `a` checks the current window's visible AI pane (`@AI_PANE_ID`). If that pane
has `@lazy_llm_wt`, then after the tool picker it asks, via fzf like the other confirmations:

- **Add in worktree `<branch>`** (shared with `<label>`) — preselected
- **Add in the main directory**
- **Cancel**

The first choice calls `llm-add --worktree <path>`, the second plain `llm-add`. If the visible
pane isn't isolated, `a` behaves exactly as today, with no dialog. Plain `llm-add` from the CLI
never asks and always means the main directory, so scripts see no change.

A pane added with `--worktree` gets the same launch env prefix and `@lazy_llm_wt` as the
pane that created the worktree (§4 steps 7–8). It skips steps 1–6, because the worktree and its
bootstrap already exist.

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
- If neither file exists, the default list is `.env*`, `.claude/settings.local.json` and
  `.agents/TODO/.work-state`, all linked (the last one is explained in §6.1).
- `<repo>/.lazy-llm/` is already lazy-llm's gitignored per-project state directory, so this
  config is personal and imposes nothing on other people who use the repo.

### 5.2 Eligibility

Each glob is expanded in the **main directory**. A match is linked or copied only if it is **not
tracked**, meaning `git -C "$primary" ls-files --error-unmatch -- <path>` fails. Linking over a
checked-out file would corrupt the worktree. A glob that matches nothing is skipped silently.
Parent directories are created as needed.

A **link** entry that is a literal path (no `*`, `?` or `[`) is linked even when the main
directory doesn't have the file. The result is a dangling symlink, and the first write through it
creates the file in the main directory. That's what `.claude/settings.local.json` and
`.work-state` need. A literal **copy** entry that's missing is skipped.

Bootstrapped paths are listed in the manifest (§5.4), and `llm-wt status` doesn't count them as
untracked work.

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
- **Claude: guidance injected only in isolated panes.** A plugin skill would be listed in every
  Claude session, isolated or not, and plugin skills can't be enabled per environment. So the
  guidance is a Markdown file, `llm-status-bin/.local/share/lazy-llm/worktree-agent.md`, which
  stows to `~/.local/share/lazy-llm/`. `llm-claude-hook` on `SessionStart`: when
  `LAZY_LLM_WORKTREE=1`, it fills in the placeholders (`{{path}}`, `{{branch}}`, `{{base}}`,
  `{{primary}}`) and prints hook JSON with `hookSpecificOutput.additionalContext`. It still does
  its existing status work, and outputs nothing extra otherwise. `SessionStart` also fires on
  resume and after compaction, so the guidance comes back after a compact. Because the file is
  live in the repo (not in the plugin's cached copy), editing it needs no plugin bump.

  The guidance covers:
  - where the agent is and why (other agents share the main directory);
  - commit in logical units, and integrate each finished unit rather than hoarding them until
    the end, since short-lived divergence means fewer conflicts;
  - how to read `llm-wt status`;
  - what each `llm-wt integrate` exit code means and what to do about it (§7);
  - never check out `<base>`, never write under `<primary>`, never force;
  - the TODO rules in §6.1;
  - **branch hygiene is already answered**: the branch is intentionally off `<base>`, and it
    integrates via `llm-wt integrate`. Don't ask the user about it. Don't push the `lazy/`
    branch. After integrating a completed task, the usual push rule applies to `<base>`: run
    `git push origin <base>` after the secrets scan over `origin/<base>..<base>`.
- **Other tools.** They get the env vars and `llm-wt`. v1 has no injected guidance for them.
  That's a follow-up (§15). The same `worktree-agent.md` is the source to feed them later.

### 6.1 TODO work tracking (`.agents/TODO/`)

The todo skill keeps `.work-state` gitignored and **keyed per session**. It already handles
several live sessions in one file: it leaves entries owned by live pids alone and offers to adopt
orphaned ones. So the two kinds of state get different treatment:

| State | In an isolated worktree | Why |
|---|---|---|
| `.work-state` | **linked** to the main directory's file (default bootstrap list) | All agents, isolated or not, see each other's in-flight tasks through the concurrency model the todo skill already has. Resume after compaction reads the same file. |
| Task files, `INDEX.md`, `REVIEW-QUEUE.md`, `CONTINUATION.md` | **per branch** (tracked, part of the checkout) | They are committed history. `[todo]` commits travel back with `llm-wt integrate` like code commits do. |

Rules in the guidance:
- **Claiming a task.** Before picking, run `llm-wt sync` (§7.3) so the task files reflect what
  has already been integrated. Commit the claim (status → in-progress) as its own `[todo]`
  commit, then run `llm-wt integrate` right away so other agents see it. The remaining race is
  two agents claiming the same task between one's sync and the other's integrate. The shared
  `.work-state` narrows it further, because an entry for that task under a live pid means it's
  taken.
- **`INDEX.md` conflicts during a rebase.** `INDEX.md` is regenerated by the todo lint.
  Resolve by taking either side, then regenerate, then continue the rebase. Never hand-merge it
  line by line.
- **The `[todo]` / code commit split** is unchanged. Both streams integrate the same way.

## 7. `llm-wt`: status, integrate, sync

A new stow package, `llm-wt-bin/.local/bin/llm-wt`, added to `STOW_PACKAGES` in `install.sh`. It
sources `lazy-llm-lib.sh` the same way `llm-add` does. Every subcommand takes an optional
worktree path and defaults to the cwd's worktree. It refuses with exit 2 when the branch has no
`lazyLlmBase` config.

### 7.1 `llm-wt status [path] [--porcelain]`

Reports the loss categories the close flow uses:

- `dirty`: tracked changes, count;
- `untracked`: untracked, non-ignored files not in the bootstrap manifest, count;
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

### 7.3 `llm-wt sync [path]`

Brings the worktree up to date with `<base>` without integrating anything. It's step 3 of
integrate on its own: rebase onto `<base>`, with the same exit 5 on conflict. With a dirty
worktree it exits 3, the same as integrate. The main directory is never touched. It's used
before claiming a task (§6.1), and whenever the agent wants other agents' integrated work.

### 7.4 Other subcommands (used by the tooling, not the agent)

- `llm-wt create <primary> <tool> <ws>`: §4 steps 1–6. Prints the worktree path.
- `llm-wt close <path> [--pane <id>]`: §8 steps 1–4 for the last pane in a worktree.

These live in `llm-wt` rather than the lib, so `llm-add`, `llm-remove`, the dashboard and
persist all share one implementation and the lib only gains the small edits listed in §13.

## 8. Closing an isolated pane

This covers `llm-remove` (dashboard `K`, CLI) on a pane with `@lazy_llm_wt`. The user chose
**always ask**.

If another live pane (in any window or workspace) has the same `@lazy_llm_wt`, the worktree
stays in use. The pane is removed with the ordinary confirm, and the worktree isn't mentioned.
The steps below apply only to the **last** pane in a worktree.

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
  already holds the worktree path. Manual saves copy entries into `snapshots/<ts>/<id>.json`, so
  the field carries into snapshots without extra work.
- **Reading it back.** `restore_one` reads each entry in **one** jq pass as `\x1f`-separated
  E / W / P records. Tabs would collapse empty fields, so don't switch to them. Add the
  worktree fields to the `P` record and to the `P)` branch's `read`. Keep `saved_rows_fast` in
  step with `entry_state` if either changes. Don't use `awk '… {print; exit}'` on a pipeline:
  under `pipefail` and `set -e` it silently killed `close` once.
- **Restore.** For a pane with `worktree`:
  - if the path is a registered worktree, launch there as today;
  - else, if the branch exists, recreate it with `lazy_llm_setup_worktree <branch> <base_dir>`,
    then rerun the bootstrap (§5);
  - else, restore it as a **shared** pane in the main directory, and log a warning.

  Either way, prefix the launch command with the §4 env vars and set `@lazy_llm_wt` on the new
  pane id.
- `claude --resume` finds the conversation because the pane relaunches in the same cwd.
- **Restoring a copy of a live workspace** (`cmd_restore_snapshot` rewrites the entry with a new
  id when the original is live). An isolated pane in the copy joins the **same** worktree as a
  second pane (§3.1 semantics), because the conversation can only be resumed from that cwd. The
  close flow's "last pane" rule (§8) keeps the copy's panes from tearing the worktree down under
  the original.

## 12. Display

### 12.1 AI pane border: git segment

A new segment is appended to every AI pane's border (isolated or not), after the status glyph:

```
 <summary> │ <workspace - label - tool - model> <glyph> │ <git>
```

| Pane is in… | `<git>` renders as |
|---|---|
| the main tree, with an upstream | `main* 1b3dafc origin ↑2↓1` |
| the main tree, no upstream | `feat/x 1b3dafc local` |
| a pane worktree | `⎇ claude-2→main* 1b3dafc ↑3↓1` (counts are against `<base>`, not an upstream) |
| a task worktree (`-W`) | `⎇ feat-x feat/x 1b3dafc origin ↑1` (worktree dir name, then branch) |
| a detached HEAD | `(detached) 1b3dafc` |
| not a git repo | segment omitted, along with its `│` |

Rules:
- `*` means tracked changes only (`-uno`). Scanning for untracked files is too slow for a border.
- Zero counts are omitted. An upstream with nothing ahead or behind shows just the remote name.
  The remote is shown as `origin` when the upstream branch has the same name as the local one,
  otherwise as `origin/<name>`.
- Branch and worktree names are clamped with `lazy_llm_clamp_label` (24 columns).
- Colors: the `⎇` marker in an accent color, ahead in green, behind in yellow, dirty `*` in
  yellow, the sha and remote dim. Every piece gets an explicit fg, as the existing header comment
  requires.
- The border is cut from the right on narrow panes, so the git segment is the first thing to go,
  and identity and status survive.

Data, at most four git calls, all run with `GIT_OPTIONAL_LOCKS=0` so the border never takes
`index.lock` while an agent is committing:

1. `git rev-parse --show-toplevel --absolute-git-dir --git-common-dir`: repo check, and linked
   worktree when the git dir isn't the common dir.
2. `git status --porcelain=v2 --branch -uno`: the `branch.oid`, `branch.head`,
   `branch.upstream` and `branch.ab` headers, and dirty if any other line appears.
3. For a pane worktree only: `git config branch.<b>.lazyLlmBase`, then
   4. `git rev-list --left-right --count <base>...HEAD`.

The pane's cwd comes from `#{pane_current_path}`, fetched in the same `display-message` call the
script already makes for `#S` and `#S:#I`, so there's no extra tmux call. tmux runs `#()`
asynchronously and caches it per `status-interval`, so git latency never blocks drawing.

Off switch: the global tmux option `@lazy_llm_border_git` (default on). Setting it to `off` drops
the segment. It's a tmux option rather than an env var, because `#()` runs in the tmux server's
environment, not the user's shell.

### 12.2 Dashboard tree

- Dashboard tree row: `⎇ <suffix>` after the pane label. The data comes from the one `list-panes` call the tree
  already makes (add `#{@lazy_llm_wt}` to its format). No extra tmux calls.

## 13. Files and coordination

| File | Change |
|---|---|
| `llm-send-bin/.local/bin/lazy-llm-lib.sh` | §2 fixes; `setup_worktree` args; owner column in `gather_worktrees`; bootstrap helpers |
| `llm-add-bin/.local/bin/llm-add` | `--isolate`, `--worktree <path>`, §2 target dir |
| `llm-remove-bin/.local/bin/llm-remove` | §8 flow for isolated panes |
| `lazy-llm-bin/.local/bin/llm-dashboard` | Workspaces-tab `A` (the Saved tab's `A` is taken, and stays), the §3.1 `a` dialog, tree marker, Worktrees tab owner/Enter/K |
| `lazy-llm-bin/.local/bin/llm-persist` | §11 |
| `lazy-llm-bin/.local/bin/llm-pane-border` | §12.1 git segment |
| `llm-status-bin/.local/bin/llm-claude-hook` | §6 SessionStart context, only when `LAZY_LLM_WORKTREE=1` |
| `llm-status-bin/.local/share/lazy-llm/worktree-agent.md` (new) | §6 guidance text, including §6.1 |
| `llm-wt-bin/.local/bin/llm-wt` (new), `install.sh` | §7: `status`, `integrate`, `sync`, `create`, `close` |
| `nvim-llm-send-plugin/…/llm-send.lua`, `nvim-note-plugin/…/note.lua` | §10 |
| `README.md`, `docs/USAGE.md` | user surface, config file, `llm-wt` |

The workspace-save-restore session released `llm-persist`, `llm-dashboard` and
`lazy-llm-lib.sh` at `e977a3b` (2026-09-28).

Commit order: §2 fix → lib `setup_worktree` args + `llm-wt` → border git segment → `llm-add`
`--isolate`/`--worktree` → close flow → dashboard → persist → nvim → hook + guidance → docs.

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
- **`llm-wt sync`.** Rebases onto a moved base, → 3 when dirty, → 5 on conflict, and never
  touches the main directory.
- **Bootstrap, revision 2.** A literal-path link that's missing becomes a dangling link, and a
  write through it creates the file in the main directory. The default list links
  `.work-state`. Manifest paths aren't counted as untracked.
- **Close flow.** The preselected choice follows the loss categories. Remove deletes the worktree
  and branch and leaves the workspace alive. With two panes in one worktree, closing the first
  one leaves the worktree untouched and doesn't ask about it.
- **`a` dialog decision.** The helper that decides whether to offer the worktree returns the path
  when the visible pane is isolated, and nothing otherwise.
- **Border git segment.** Fixture repos, one per row of the §12.1 table: the rendered text
  (colors stripped) matches. `@lazy_llm_border_git off` drops the segment.
- **Hook.** `SessionStart` prints `additionalContext` with the placeholders filled when
  `LAZY_LLM_WORKTREE=1`, and prints nothing new without it. It extends scenario 19.
- **Persist** (extend scenario 20). A worktree field round-trips, including through a manual
  snapshot. Restore recreates a missing worktree from its branch, and falls back to shared when
  the branch is gone. Restoring a copy of a live workspace puts the isolated pane into the same
  worktree.

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
- Whether Claude Code's Write/Edit tools follow a symlinked `.work-state` or replace it. If they
  replace it, the sharing in §6.1 silently stops. The close flow still catches the replaced link
  (§5.4), but the todo concurrency benefit is lost, so record the result and report it.
- `set-option -p` pane options survive `swap-pane` into and out of the hold window. They should,
  since they belong to the pane and not to its position. Verify.
