
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
  │ See all AI panes and their status        │ Prefix+S → 3 — opens the Panes tab in the dashboard                                              │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Manage lazy-llm sessions                 │ Prefix+S — opens the dashboard (Sessions=1, Worktrees=2, Panes=3 tabs)                           │
  ├──────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Spawn session bound to a worktree        │ lazy-llm -W <branch> — creates branch+worktree if needed, always spawns a new session            │
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
