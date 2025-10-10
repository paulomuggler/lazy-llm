[] Implement two-way buffer piping. Right now, we can only send from nvim buffer -> LLM TUI. There are situations when it's desirable to be able to also do the opposite; we should check feasibility of implementing the opposite, getting the contents of the prompt box in the TUI into the nvim scratch buffer. This can be useful also for responses, come to think of it; I often feel the inclination to copy the whole of the response text and add notes to it in the nvim buffer. If we can pipe the response text into the nvim buffer, that would be a nice-to-have feature.

[] given the features above and the chat branching planned feature, we should probably look to refactor and streamline our cross-pane text piping, around an easy simple to use set of utility functions 'API' that can be used in various places. This will help us avoid code duplication and make future maintenance easier.

[] our leader bindings (llms) is clashing with Lazys own bindings sometimes, and sometimes doing weird TMUX stuff instead of what we want. We should investigate, and maybe change our leader bindings to something else, maybe <leader>la (for lazy-llm) or something like that.

[] when piping in a large buffer into the LLM TUI prompt, the TUIs tend to receive it as pasted text, and the autosubmit that is sent afterwards fails to submit the prompt. We want to investigate and fix that.

[] make buffer piping even smarter; from nvim, add bindings to pull in the latest response into buffer (for email-style inline replies)

[] add option to lazy-llm tmux initialization to open a new workspace in a new window on existing session

[] I want to add a 'context picker' feature to lazy-llm. Goes like this: when perusing the workspace editor, you can call a binding to send a reference to a specific line or block of code into the scratch prompt buffer. This will be a sort of 'lightweight' version of the @file reference feature, where instead of referencing a whole file, you can reference a specific line or block of code. The reference will be in the form of a comment, e.g. `# See line 42 in src/main.py`. The LLM can then use this reference to understand the context of the prompt better. This will be especially useful for code reviews and debugging sessions.

[] fix and improve panel navigation, tmux <-> nvim panel seamless navigation, alt+<^> shortcuts not working often in certain situations (i.e. moving out of the TUI panel int othe workspace editor panel)

[x] create custom prompt tool 'implement prompts': reads through a file, and implements every note/comment starting with an # AI: in the file

[] incorporate our claude 'implement-prompts' custom tool prompt into other LLM TUIs

[] promote some of the LLM (claude, etc) local settings to global, versionable settings. For example, auto approval of commands with no side effects (ls, tree, pwd, etc.)
