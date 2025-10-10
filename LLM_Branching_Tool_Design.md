
# Design Document: Git-Based LLM Conversation Branching Tool

## 1. Project Intent & Core Concept

The goal is to create a TUI-based tool that enables fluid, non-linear conversations with Large Language Models (LLMs). The core feature is the ability to "check out" any point in a conversation's history and "branch off" into a new line of inquiry.

This will be built on `git`, leveraging its robust branching and history management capabilities. The process of committing and branching the conversation history will be automated and transparent to the user, providing a seamless experience. A key component will be a clear, interactive visualization of the conversation tree.

## 2. UX Flow & User Interaction

### Core Loop
1.  **User sends a prompt.**
    -   The tool automatically commits the prompt.
2.  **LLM sends a response.**
    -   The tool automatically commits the response.
3.  The conversation continues linearly on the `main` branch.

### Branching a Conversation
1.  The user invokes a "history" or "graph" view (e.g., via a hotkey).
2.  The tool displays a visualization of the conversation history, similar to `git log --graph --oneline`.
3.  The user navigates this graph to a specific commit (either a prompt they sent or a response they received).
4.  The user selects "checkout" or "branch" from this point.

### Answering your UX Question
> **QUESTION:** when checking out at the point of a prompt, the expectation would be, the conversation is loaded up to the last response before the prompt, and then the last prompt at that checked out point is loaded into the prompt box, ready to be modified and sent again (which would of course cause the cration of a new branch). Does that sound like the most intuitive UX?

**Yes, this is the most intuitive and powerful UX.** When a user checks out a previous prompt, their intent is almost always to re-try, edit, or diverge from that specific point.

**Proposed Checkout Flow:**
1.  User selects a past prompt commit to "checkout".
2.  The tool clears the LLM's current context.
3.  It then replays the conversation history *up to the parent of the selected commit*, loading this state into the LLM.
4.  The content of the selected prompt commit is loaded into the user's prompt input box.
5.  The user can now edit and send this prompt.
6.  Upon sending, the tool automatically creates a new `git` branch (e.g., `branch-from-<short_hash>`) and commits the new prompt, starting a new conversation line.

## 3. Git Backend Design

-   **Repository:** A dedicated `.git` repository will be maintained in a designated folder (e.g., `~/.config/lazy-llm/history/my-project/`).
-   **Commits:** Each user prompt and each LLM response gets its own commit. This provides the finest-grained control.
-   **Commit Message Convention:** Messages must be structured for automated parsing and for clarity in the graph view.
    -   **Subject:** `[<TYPE>] <TIMESTAMP> - <SUMMARY>`
        -   `TYPE`: `PROMPT` or `RESPONSE`.
        -   `TIMESTAMP`: ISO 8601 format.
        -   `SUMMARY`: First ~70 characters of the content.
    -   **Body:** The full, unmodified content of the prompt or response.
-   **Branching:**
    -   The primary conversation lives on the `main` branch.
    -   When a user branches off, a new branch is created automatically. A good naming convention would be `chat-YYYYMMDD-HHMMSS` or `branch-from-<short-hash-of-parent>`.

## 4. Data Storage Strategy

> **QUESTION:** is it feasible to have the entire thing be contained in the git messages? The full prompts, and the full responses, always in the body of the git message? Why would this be a good vs. a bad idea?

This is a critical design choice. Let's analyze it.

### Approach A: Everything in Commit Messages

-   **How it works:** The commit subject holds metadata, and the entire prompt/response content is stored in the commit body. The git repository contains no tracked files.
-   **Good Ideas (Pros):**
    -   **Atomicity:** The history is entirely self-contained in the `.git` directory. There are no other files to manage.
    -   **Portability:** `git clone` or copying the `.git` folder is all that's needed to move the entire conversation history.
    -   **Simplicity:** No file I/O is needed for history; it's all `git commit` and `git log`.
-   **Bad Ideas (Cons):**
    -   **Not Git's Purpose:** `git` is optimized for tracking file changes (diffs), not for storing raw data in messages. While it can do this, it's not its primary design and may have performance implications.
    -   **Potential Size Limits:** While `git` commit messages can be large, extremely large prompts or responses (e.g., pasting a whole codebase) could push practical limits or slow down operations.
    -   **Searching & Analysis:** Querying the content would require parsing the bodies of all commit messages, which is less efficient than file-based searching.

### Approach B: Hybrid (Metadata in Commits, Content in Files)

-   **How it works:** Each commit still represents a prompt or response. The commit message contains metadata (type, timestamp, author). The actual content is written to a file (e.g., `data/<commit_hash>.md`), and that file is what's added and committed.
-   **Good Ideas (Pros):**
    -   **Idiomatic Git:** This is exactly how `git` is designed to be used. It will be highly efficient at storing and diffing the content files.
    -   **Scalability:** Handles very large content without issue.
    -   **Easy Access:** The conversation history is available as plain text files, which can be easily read, searched, and processed by other tools.
-   **Bad Ideas (Cons):**
    -   **Slightly More Complex:** Requires file I/O (write file, `git add`, `git commit`).
    -   **More Files:** The data directory could contain thousands of small files.

**Recommendation:** **Approach B (Hybrid)** is the more robust and scalable solution. It aligns with `git`'s strengths and avoids potential performance bottlenecks, while making the underlying data more accessible.

## 5. Handling Advanced TUI Features

> **QUESTION:** what happens to the context then? How should our tool behave in those situations? (e.g. interrupting reasoning, queuing prompts)

The key is to maintain a strict, linear, and auditable event log.
-   **Interrupted Reasoning:** When an LLM response is interrupted, the partial response received should be committed as a `RESPONSE_PARTIAL` type. The user's interrupting prompt is then committed as a new `PROMPT` commit. This perfectly captures the sequence of events.
-   **Queued Prompts:** This is an interface feature. The TUI can queue them, but they should only be committed once they are actually *sent* to the LLM. The history should reflect what was actually processed, not what was planned.

## 6. Workspace State Syncing

> **QUESTION:** how do we offer the option of managing both workspace state + chat history state in tandem?

This is a powerful feature. The "hands-off" approach is the safest and most flexible starting point.

-   **Implementation:**
    1.  When committing a `PROMPT`, the tool also runs `git rev-parse HEAD` in the user's workspace repository.
    2.  This workspace commit hash is stored as a metadata field in the chat commit message body (e.g., `Workspace-Commit: <hash>`).
    3.  When a user checks out a point in the chat history, the tool can read this metadata.
    4.  It can then **prompt the user**: "This chat point is linked to workspace commit `<short_hash>`. Do you want to check it out in your project?" This avoids surprising, destructive actions but provides the desired link.

> **QUESTION:** due to the repo-within-a-repo nature of our implementation... is just .gitignoreing the whole thing in the workspace repo enough? should we submodule it?

-   **.gitignore (Recommended):** This is the simplest and cleanest solution. The chat history repo should live in a directory (e.g., `.lazy-llm-chat/`) which is added to the main project's `.gitignore`. This treats the two as completely separate entities, which for this use case, is desirable. It prevents accidental commits of the chat history into the workspace project.
-   **Submodule (Not Recommended for this Use Case):** A submodule creates a formal link between the two repos. This is overly complex for this tool. It would require users to `git submodule update` and manage nested repo states in a way that is counter-intuitive for a simple conversation history.

## 7. What Else? Further Considerations

-   **Merging Branches:** What does it mean to merge two conversation branches? This is conceptually complex and likely not a priority. It could involve trying to "replay" one branch's prompts onto another, but the results would be unpredictable. Best to omit this for now.
-   **Tagging:** Allow users to `git tag` important commits with meaningful names (e.g., `v1.0-solution`, `refactor-idea`) through a simple TUI command.
-   **Exporting:** A feature to export a specific branch (or the whole history) to a single Markdown or JSON file would be very useful.
-   **Initial Setup:** The tool needs a `lazy-llm-chat init` command that creates the history directory and its internal `.git` repository.
