[] Write preliminary design and implementation plan for conversational branching model (based on git at first)

[x] Implement two-way buffer piping. Right now, we can only send from nvim buffer -> LLM TUI. There are situations when it's desirable to be able to also do the opposite; we should check feasibility of implementing the opposite, getting the contents of the prompt box in the TUI into the nvim scratch buffer. This can be useful also for responses, come to think of it; I often feel the inclination to copy the whole of the response text and add notes to it in the nvim buffer. If we can pipe the response text into the nvim buffer, that would be a nice-to-have feature.

[x] given the features above and the chat branching planned feature, we should probably look to refactor and streamline our cross-pane text piping, around an easy simple to use set of utility functions 'API' that can be used in various places. This will help us avoid code duplication and make future maintenance easier.

[x] our leader bindings (llms) is clashing with Lazys own bindings sometimes, and sometimes doing weird TMUX stuff instead of what we want. We should investigate, and maybe change our leader bindings to something else, maybe <leader>la (for lazy-llm) or something like that. (WONT FIX, not actually a keybindings problem, skill issue and/or timing when first loading plugin?)

[x] sometimes our llms command is sending a bunch of weird commands to TMUX instead of piping, which result in a stack of TMUX command states I have to esc out of, here's the sequence after llms fails to work as intended: jump to backward -> (repeat) 5 -> (repeat) 1 -> (go to line) -> (repeat) 1 -> (go to line) -> (repeat) 8 , etc. ,the repeat sequences are not alweays the same... whats up?

[x] when piping in a large buffer into the LLM TUI prompt, the TUIs tend to receive it as pasted text, and the autosubmit that is sent afterwards fails to submit the prompt. We want to investigate and fix that.

[x] make buffer piping even smarter; from nvim, add bindings to pull in the latest response into buffer (for email-style inline replies)

[x] add option to lazy-llm tmux initialization to open a new workspace in a new window on existing session

[x] I want to add a 'context picker' feature to lazy-llm. Goes like this: when perusing the workspace editor, you can call a binding to send a reference to a specific line or block of code into the scratch prompt buffer. This will be a sort of 'lightweight' version of the @file reference feature, where instead of referencing a whole file, you can reference a specific line or block of code. The reference will be in the form of a comment, e.g. `# See line 42 in src/main.py`. The LLM can then use this reference to understand the context of the prompt better. This will be especially useful for code reviews and debugging sessions.

[x] fix and improve panel navigation, tmux <-> nvim panel seamless navigation
    - Ctrl+hjkl works perfectly everywhere (shell, nvim, all tmux panes)
    - Alt+Left/Right: sends shell commands 'b'/'f' (word navigation) instead of pane nav - NOT FIXED, leaving as-is
    - Alt+Up/Down: works for pane navigation
    - Inconsistent Alt behavior due to terminal/shell keybinding conflicts, but Ctrl+hjkl is reliable solution

[x] create custom prompt tool 'implement prompts': reads through a file, and implements every note/comment starting with an # AI: in the file

[x] Add raw mode variations for context reference insertion:
   - <leader>llmr: raw mode (no extra newlines, inline insertion)
   - <leader>llmR: wrapped mode (leading and trailing newlines for multiple refs)
   - Allows flexibility when inserting single refs or inline refs
   - Known issue: consecutive R insertions create double blank lines (cosmetic, low priority)

[] incorporate our claude 'implement-prompts' custom tool prompt into other LLM TUIs

[] promote some of the LLM (claude, etc) local settings to global, versionable settings. For example, auto approval of commands with no side effects (ls, tree, pwd, etc.)

[x] our @ workspace file reference picker is not allowing to insert folder paths, we need to have folder paths able to be inserted as a reference as well.

[] the send prompt feature is still getting hiccups when sending the last enter in order to autosubmit the prompt in the LLM TUI. Sometimes the enter is not sent, and the prompt is not submitted. Then we need to submit it manually. Increasing delay before sending final enter helped somewhat.
   UPDATE: Refactored to send single string with embedded newlines instead of multiple send-keys calls.
   - Claude: ✅ Works perfectly
   - Gemini: ✅ Works perfectly
   - Codex: ⚠️ Receives prompt but autosubmit (final Enter) not working
   - Grok: ❌ Mangles prompt string, ### END PROMPT marker not on own line (unofficial TUI, may not be worth fixing)

[] the feature to open new lazy-llm in new window of existing session wont work unless we can differentiate env vars AI_PANE and PROMPT_PANE, others, between different windows of the same session. We need to investigate if this is possible, and if so, implement it.

[] Remove the prompt box from the pulled lines in Response Pull

[] Enhance Response Pull to support pulling earlier responses:
   - Add `-n N` flag to pull the N-th response (counting backwards from most recent)
   - Add `-r START:END` flag to pull a range of responses
   - Examples:
     * `llm-pull` - current behavior (latest response)
     * `llm-pull -n 2` - pull 2nd most recent response
     * `llm-pull -r 1:3` - pull responses 1-3 (latest to 3rd most recent)
   - Implementation: Parse all ### END PROMPT markers, extract content between them
   - Update nvim keybinding to allow specifying which response(s) to pull
   - Useful for referencing earlier parts of conversation or comparing responses

[] Fix Codex autosubmit: Final Enter keypress not being received/processed. Need to investigate if Codex requires different submission mechanism (Ctrl+Enter?) or additional delay.

[x] Fix Prompt Send on Grok (appears to send prompt after first carriage return) - WONT FIX: Grok TUI is unofficial implementation and mangles multi-line pastes. Wait for official Grok TUI or try alternative implementation.

[x] Prompt Send and Response Pull tested on claude, gemini, codex, working, grok, Prompt Send broken, not possible to test Response Pull yet

[] Improve robustness rgarding use of env vars AI_PANE, PROMPT_PANE, etc., these seem to be flaky when having multiple sessions or windows in a session, I've seen the whole thinkg go a bit crazy. But could have been about old stale sessions and windows tmux-ressurrext was trying to restore, IDK. Investigate.
