
  What You Can Do Now with lazy-llm

  ┌──────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────┐
  │               I want to...               │                                               How                                                │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Start a workspace                        │ lazy-llm (claude) or lazy-llm -t gemini / codex / grok / aider                                   │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Start in existing tmux session           │ Just run lazy-llm from inside tmux — it auto-adds a new window                                   │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Write and send a prompt                  │ Type in bottom pane, <leader>llms to send (visual mode sends selection only)                     │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Send a slash command                     │ <leader>llmc (wraps content as /command) or <leader>llm/ for interactive input                   │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Forward a keypress (e.g. confirm y/n)    │ <leader>llmk then press the key                                                                  │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Pull the AI's latest response into nvim  │ <leader>llmp — response text lands in your buffer for annotation                                 │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Reference a file in your prompt          │ Type @ in insert mode → fuzzy picker for files and folders                                       │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Reference specific code lines            │ Cursor on line (or visual select), <leader>llmr (inline) or <leader>llmR (wrapped with newlines) │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Scatter notes for the AI to find         │ <leader>ni inserts [NOTE: ] marker at cursor                                                     │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Collect all notes and send them          │ <leader>np (whole project) or <leader>nb (current file)                                          │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Add a second AI tool                     │ Prefix+A (tmux menu picker) or <leader>llma (nvim, prompts for tool name)                        │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Cycle between AI panes                   │ Prefix+C-n / Prefix+C-p (tmux) or <leader>llm] / <leader>llm[ (nvim)                             │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Remove an AI pane                        │ Prefix+C-x (tmux) or <leader>llmx (nvim) — both ask for confirmation                             │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Remove without confirmation              │ llm-remove -f from the shell                                                                     │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ See all AI panes and their status        │ Prefix+S — opens the Workspaces tree; every AI pane is nested under its workspace                │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Manage lazy-llm workspaces               │ Prefix+S — opens the dashboard (Workspaces=1, Worktrees=2, Saved=3, Help=? tabs)                 │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Save workspaces now                      │ Automatic on every change; on demand: Prefix+C-s, s in the dashboard, or lazy-llm save           │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Bring workspaces back after tmux died    │ lazy-llm restore (or Prefix+S → 3 → Enter / A) — panes resume their conversations                │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ See what's saved                         │ lazy-llm saved [-v] or Prefix+S → 3 (● live, ◌ died, ◇ closed; d / --dropped: ✕ dropped)         │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Close a workspace but keep it saved      │ lazy-llm close <name>, or K on it in Prefix+S (choose "close"), or c in the Saved tab            │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Keep a dated version to go back to       │ Save manually (Prefix+C-s, s, lazy-llm save); Prefix+S → 3 lists it under a dated divider        │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ See what panes a saved workspace had     │ Prefix+S → 3, then z on it (folded by default)                                                   │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Drop a saved workspace                   │ lazy-llm kill <name> (running) / lazy-llm forget <name>, or Prefix+S → 3 → K                     │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Spawn workspace bound to a worktree      │ lazy-llm -W <branch> — creates branch+worktree if needed, always spawns a new workspace          │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Tear down a worktree (atomic)            │ Prefix+S → 2 → highlight → K — kills attached workspace, removes worktree, optionally branch     │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Run an AI pane in its own worktree       │ Prefix+S → A (asks a name; default <repo>-wt-<n>), or llm-add -i [-n name]; branch lazy/<name>   │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Merge an isolated pane's work back       │ the agent runs llm-wt integrate per unit (rebase, fast-forward); llm-wt status shows what's left │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Edit a file's copy in a pane worktree    │ <leader>llmw toggles the main copy ⇄ the visible AI pane's worktree copy (editable)              │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Close an isolated pane                   │ K on its row / llm-remove; the last pane in a worktree asks: keep / remove / cancel              │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Pipe text into the prompt buffer         │ echo "add tests" | llm-append or llm-append "some context" from any shell                        │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Clear the prompt buffer                  │ <leader>llmd                                                                                     │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Use nvim normally outside lazy-llm       │ All lazy-llm keymaps are invisible when not inside tmux — zero interference                      │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Use C-n/C-p in non-lazy-llm tmux windows │ They fall back to next-window/previous-window automatically                                      │
  └──────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────┘

  Things that happen automatically (you don't need to do anything):

  - Dead AI panes are cleaned up — if a pane crashes, it's pruned from the list next time you cycle or add
  - Holding window recovers — if you accidentally close the hidden window that stores inactive AI panes, it's recreated automatically
  - Error notifications — if any background operation fails (send, pull, append, cycle), you get a nvim notification with the error
  - Temp files are cleaned up — prompt temp files are managed in Lua, not left as shell artifacts
  - Workspaces are saved — every launch, pane add/remove/cycle, rename, fold, reorder and new Claude conversation
    rewrites the manifest (~/.local/state/lazy-llm/workspaces/), so `lazy-llm restore` has them after a crash
  - The prompt pane comes back as you left it — every prompt file it had open, in the same layout, each time you open
    a workspace in that directory; prompt files a snapshot still has open are exempt from the 7-day cleanup
