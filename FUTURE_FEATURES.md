# lazy-llm Feature Roadmap

This document outlines potential features for lazy-llm, prioritized by impact and alignment with the tool's philosophy of seamless AI-assisted development workflows.

---

## 1. Response Code Block Actions
**Priority:** High
**Complexity:** Medium
**Impact:** High - Huge time saver for the core use case

### Concept
Parse AI responses for code blocks and provide quick actions to apply, run, or copy them directly from the AI pane.

### Features
- **Apply code block** (`<leader>llmca`) - Apply code block under cursor to target file
  - Detect filename from AI response context (e.g., "Here's the updated `src/main.py`:")
  - Parse code fence language for target file when explicit
  - Prompt for target file when ambiguous
  - Show diff before applying (with confirm/reject option)

- **Run command** (`<leader>llmcr`) - Execute shell command from code block
  - Detect bash/shell code fences
  - Show command preview with confirmation prompt
  - Execute in workspace pane or new pane
  - Capture and display output

- **Copy code block** (`<leader>llmcc`) - Copy code block to system clipboard
  - Quick extraction without manual selection
  - Strip code fence markers automatically

- **Visual indicators** - Show which blocks have been applied
  - Mark applied blocks in AI pane (virtual text or highlight)
  - Persist state across conversation to avoid double-applies

### Implementation Notes
- Parse response text for code fences (```)
- Store code blocks with metadata (language, line range, applied status)
- Use treesitter or simple regex for fence detection
- Integrate with git diff for preview before applying
- Consider storing blocks in buffer-local variables for current response

### UX Flow
```
1. AI responds with code in left pane
2. User navigates cursor to code block
3. <leader>llmca
4. Tool detects filename or prompts user
5. Shows diff preview in split
6. User confirms (y) or rejects (n)
7. Code applied, block marked as applied
```

---

## 2. Parallel AI Comparison Mode
**Priority:** High
**Complexity:** High
**Impact:** Medium-High - Valuable for critical decisions

### Concept
Query multiple AI tools simultaneously with the same prompt and compare responses side-by-side.

### Features
- **Multi-tool launch** - Start session with multiple AI panes
  ```bash
  lazy-llm --compare claude,gemini
  lazy-llm --compare claude,gemini,codex
  ```

- **Layout adaptation** - Intelligent pane arrangement
  - 2 tools: Left split (AI1 | AI2) + Editor + Prompt
  - 3 tools: Grid layout or tabs

- **Synchronized sending** - Send prompt to all tools simultaneously
  - `<leader>llms` broadcasts to all AI panes
  - Visual feedback showing which tools are responding

- **Comparison view** (`<leader>llmC`) - Toggle comparison mode
  - Align responses for side-by-side reading
  - Highlight differences (if feasible)
  - Quick navigation between responses

### Implementation Notes
- Extend lazy-llm script to parse comma-separated tool list
- Create dynamic tmux layouts based on tool count
- Track multiple `AI_PANE` environment variables (e.g., `AI_PANE_1`, `AI_PANE_2`)
- Update llm-send script to broadcast to multiple panes
- Consider tmux window/pane synchronization features

### UX Flow
```
1. Launch: lazy-llm --compare claude,gemini
2. Tmux creates split AI panes
3. User writes prompt in bottom pane
4. <leader>llms sends to both AI tools
5. Responses appear side-by-side
6. User reviews and chooses best response/approach
```

### Use Cases
- Critical architectural decisions
- Comparing code generation quality
- Validating factual information
- Getting diverse perspectives on complex problems
- Testing prompt effectiveness across models

---

## 3. Workspace State Capture
**Priority:** Medium-High
**Complexity:** Medium
**Impact:** Medium - Useful for debugging and reproducibility

### Concept
Capture and include workspace context automatically in prompts, making it easier for AI to understand the current state.

### Features
- **State snapshot** (`<leader>llmS`) - Capture current workspace state
  - Git status (branch, dirty/clean, recent commits)
  - Open buffers with file paths
  - Directory tree of relevant paths
  - Active LSP diagnostics/errors

- **Auto-include in prompt** - Append snapshot to prompt buffer
  - Formatted as collapsible markdown sections
  - Option to review/edit before sending

- **Smart context gathering** - Detect and suggest relevant context
  - Detect imports/requires in current file, offer to include referenced files
  - Suggest files changed in recent git commits
  - Identify related test files

- **Before/after comparison** - Track changes during AI session
  - Snapshot at session start
  - Easy comparison after AI makes changes
  - Generate summary of modifications

### Implementation Notes
- Create `llm-snapshot` bash script to gather state
  - `git status --short --branch`
  - `git log -5 --oneline`
  - `nvim` API to query open buffers
  - Selective `tree` output (exclude node_modules, .git, etc.)
- Format output as markdown for readability
- Store snapshot in temp file or session variable
- Integrate with llm-append for non-intrusive insertion

### UX Flow
```
1. User encounters bug or unexpected behavior
2. <leader>llmS captures workspace state
3. State appended to prompt buffer:

   <details>
   <summary>Workspace State</summary>

   Branch: feature/new-api
   Status: Modified: 3 files
   Open Files:
   - src/api/client.py
   - tests/test_client.py
   ...
   </details>

4. User adds specific question/prompt
5. Send complete context to AI
```

---

## 4. Prompt Refinement Loop
**Priority:** Medium
**Complexity:** Low
**Impact:** Medium - Meta-prompting for better results

### Concept
Use AI to improve your prompts before sending them to get better results.

### Features
- **Prompt critique** (`<leader>llmx`) - Ask AI to improve current prompt
  - Sends prompt to AI with meta-question: "How could this prompt be improved for clarity, specificity, and better results?"
  - Displays suggestions in split or replaces prompt buffer

- **Refinement workflow**
  1. User writes initial prompt
  2. Invokes refinement
  3. Reviews AI suggestions
  4. Edits prompt based on suggestions
  5. Sends refined prompt

- **Templates for meta-prompting**
  - "Make this prompt more specific"
  - "Add missing context to this prompt"
  - "Break this prompt into sub-tasks"

### Implementation Notes
- Simple wrapper around existing send functionality
- Could use same AI pane or open temp pane for critique
- Store original prompt for easy restoration
- Consider having dedicated "critique" mode that doesn't affect conversation history

### UX Flow
```
1. User writes: "Fix the bug"
2. <leader>llmx
3. AI responds: "This prompt could be improved by:
   - Specifying which bug (file/line/behavior)
   - Including error messages or symptoms
   - Describing expected vs actual behavior"
4. User refines: "Fix the NullPointerException in src/api/client.py:42
   when calling fetch() with null params. Expected: handle null gracefully."
5. Send refined prompt
```

---

## 5. Prompt Templates/Snippets System
**Priority:** Medium
**Complexity:** Low
**Impact:** Medium - Quality of life improvement

### Concept
Quick insertion of common prompt patterns and templates.

### Features
- **Template command** (`:LLMTemplate <name>`) - Insert predefined template
  - Templates stored as markdown files in `~/.config/lazy-llm/templates/`
  - Support for placeholders/variables

- **Default templates**
  - `review` - Code review checklist
  - `bug` - Bug report template
  - `refactor` - Refactoring request structure
  - `docs` - Documentation generation prompt
  - `test` - Test case generation prompt
  - `explain` - Code explanation request

- **Custom templates** - Users can create their own
  - Simple markdown files with `{{placeholders}}`
  - Load from `~/.config/lazy-llm/templates/custom/`

- **Snippet expansion** - Vim snippet-style shortcuts
  - Type trigger + `<Tab>` in prompt buffer
  - E.g., `@rev<Tab>` expands to review template

### Implementation Notes
- Create template directory structure during install
- Ship with default templates in `dotfiles/nvim-lazy-llm/templates/`
- Simple file read + placeholder substitution
- Integrate with nvim completion or custom expansion
- Consider using existing snippet engine (UltiSnips, LuaSnip) if available

### Template Example
```markdown
# templates/review.md

Please review the following code for:

- [ ] Logic errors or bugs
- [ ] Performance issues
- [ ] Security vulnerabilities
- [ ] Code style and readability
- [ ] Test coverage gaps
- [ ] Documentation needs

{{file_or_selection}}

Provide specific, actionable feedback.
```

---

## 6. Multi-Shot Prompting Helper
**Priority:** Medium
**Complexity:** Low-Medium
**Impact:** Medium - Improves complex prompting workflows

### Concept
Build complex, multi-part prompts iteratively without sending until ready.

### Features
- **Queue addition** (`<leader>llm+`) - Add current buffer/selection to queue
  - Doesn't clear buffer
  - Doesn't send to AI
  - Visual indicator of queued items

- **Queue review** (`<leader>llm?`) - Show what's queued
  - Display queued sections in preview window
  - Allow editing or removing items

- **Send queued** (`<leader>llm=`) - Send all queued sections as single prompt
  - Concatenates sections with clear delimiters
  - Clears queue after sending

- **Queue management**
  - Persist queue across buffer switches
  - Clear queue command (`<leader>llm-`)
  - Reorder queue items

### Implementation Notes
- Store queue in buffer or session variable
- Simple list of text snippets with metadata (source, timestamp)
- Format concatenation with clear section markers
- Could be file-based or in-memory depending on persistence needs

### UX Flow
```
1. User working on refactoring task
2. Opens file1.py, selects class A
3. <leader>llm+ (queues class A)
4. Opens file2.py, selects class B
5. <leader>llm+ (queues class B)
6. Opens prompt buffer, writes context
7. <leader>llm+ (queues written prompt)
8. <leader>llm? (reviews all 3 queued items)
9. <leader>llm= (sends combined prompt):

   --- Section 1 (file1.py) ---
   [class A code]

   --- Section 2 (file2.py) ---
   [class B code]

   --- Section 3 (prompt) ---
   How can I refactor these classes to share common logic?
```

---

## 7. Conversation Journal/History
**Priority:** Medium-Low
**Complexity:** Low
**Impact:** Medium - Long-term value for reference

### Concept
Lightweight logging and search of conversation history.

### Features
- **Auto-save conversations** - Background logging
  - Save prompts and responses to dated files
  - Location: `~/.config/lazy-llm/history/YYYY-MM-DD/session-HH-MM-SS.md`
  - Organized by date and session

- **History browser** (`<leader>llmh`) - Fuzzy finder for past conversations
  - Search by date, session name, or content
  - Preview conversation in split
  - Jump to specific conversation point

- **Conversation search** (`:LLMSearch <query>`) - Full-text search
  - Search across all saved conversations
  - Results show context snippets
  - Open full conversation from results

- **Resume conversation** - Continue from history
  - Load previous conversation state
  - Append new prompts to existing log
  - Useful for long-running projects

### Implementation Notes
- Hook into send/receive to capture conversation
- Simple markdown format with timestamps
- Use grep/ripgrep for search functionality
- Integrate with fzf for browsing
- Keep logs organized and rotatable (e.g., archive after 90 days)

### Log Format Example
```markdown
# Conversation: 2025-10-18 14:30:15
Session: lazy-llm-myproject
Tool: claude

## [14:30:22] User Prompt
Fix authentication bug in login handler

## [14:30:45] AI Response
I'll help fix the authentication bug. First, let me examine the login handler...

[Response content]

## [14:35:10] User Prompt
[Next prompt...]
```

---

## Implementation Priority

### Phase 1 - High Impact, Medium Effort
1. **Response Code Block Actions** - Core workflow enhancement
2. **Prompt Templates** - Quick win, low complexity

### Phase 2 - Advanced Workflows
3. **Multi-Shot Prompting** - Natural extension of existing features
4. **Workspace State Capture** - Context improvement
5. **Prompt Refinement Loop** - Meta-prompting capability

### Phase 3 - Comparison & History
6. **Parallel AI Comparison** - Complex but valuable for critical work
7. **Conversation Journal** - Long-term value, low urgency

---

## Cross-Feature Considerations

### Keybinding Organization
All features under `<leader>llm` prefix:
- Core: `s` (send), `d` (delete), `k` (keypress)
- Code blocks: `c` prefix (`ca`, `cr`, `cc`)
- Queue: `+` (add), `=` (send), `-` (clear), `?` (review)
- Meta: `x` (refine), `S` (snapshot), `h` (history)
- Templates: `:LLMTemplate` command or snippet expansion

### Data Storage
- Templates: `~/.config/lazy-llm/templates/`
- History: `~/.config/lazy-llm/history/`
- State: Session/buffer variables or temp files

### Integration Points
- All features should work with existing send/receive infrastructure
- Respect `clear_on_send` configuration
- Compatible with multi-window/multi-session setups
- Work across different AI tools (claude, gemini, etc.)

---

## Future Exploration

Features not prioritized but worth keeping in mind:
- Response diff viewer (comparing iterations)
- Response bookmarking/starring
- Export conversations to different formats
- Collaborative conversation sharing
- Integration with git-based conversation branching (see `LLM_Branching_Tool_Design.md`)
