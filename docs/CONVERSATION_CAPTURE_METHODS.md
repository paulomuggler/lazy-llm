# Conversation Capture Methods: Technical Analysis

**Auxiliary document to:** `LLM_Branching_Tool_Design.md`

## Purpose

This document analyzes the technical approaches for capturing LLM conversation data (prompts and responses) for automated git-based conversation branching, with emphasis on structured data access over terminal buffer scraping.

---

## Executive Summary

**Key Finding:** Full structured conversation data is accessible without terminal scraping via multiple methods, with Claude Code's native JSONL storage being the most immediately viable.

**Recommended Strategy:** Hybrid approach
1. **Phase 1:** Parse Claude's `~/.claude/projects/` JSONL files (immediate wins)
2. **Phase 2:** Add mitmproxy interception for real-time capture and multi-provider support
3. **Phase 3:** Consider direct SDK integration for custom features

---

## Approach 1: Network Proxy Interception

### Overview
Intercept HTTPS traffic between LLM CLI tool and API endpoints (e.g., `api.anthropic.com`) using a transparent proxy.

### Tools

#### mitmproxy (Open Source, Cross-Platform)
```bash
# Install
brew install mitmproxy

# Run transparent proxy
mitmproxy --mode transparent

# Or automated capture
mitmdump -w conversation.flow "~d api.anthropic.com"
```

**Features:**
- Intercepts HTTPS with custom CA certificate
- Supports Server-Sent Events (SSE) streaming
- Python addon API for custom processing
- Real-time or batch capture modes

#### Proxyman (macOS Native, Commercial)
```bash
# Configure for Node.js apps
source ~/.proxyman/proxyman_env_setup.sh && claude
```

**Features:**
- GUI interface for macOS
- Node.js application support built-in
- Filter traffic by domain/endpoint
- Export to various formats

### Implementation Pattern

```python
# mitmproxy addon: conversation_capture.py
from mitmproxy import http
import json
import subprocess

class ConversationCapture:
    def __init__(self):
        self.current_prompt = None
        self.response_chunks = []

    def request(self, flow: http.HTTPFlow):
        """Capture outgoing prompts"""
        if "api.anthropic.com/v1/messages" in flow.request.pretty_url:
            body = json.loads(flow.request.content)
            self.current_prompt = body.get("messages", [])[-1]

            # Auto-commit prompt to git
            self._git_commit(
                type="PROMPT",
                content=self.current_prompt["content"],
                metadata={"model": body.get("model")}
            )

    def response(self, flow: http.HTTPFlow):
        """Capture streaming responses"""
        if "api.anthropic.com" in flow.request.pretty_host:
            content_type = flow.response.headers.get("content-type", "")

            if "text/event-stream" in content_type:
                # Parse Server-Sent Events stream
                for line in flow.response.text.split('\n'):
                    if line.startswith('data: '):
                        try:
                            chunk = json.loads(line[6:])
                            if chunk.get("type") == "content_block_delta":
                                self.response_chunks.append(
                                    chunk["delta"]["text"]
                                )
                        except json.JSONDecodeError:
                            pass

                # Commit complete response
                full_response = ''.join(self.response_chunks)
                self._git_commit(
                    type="RESPONSE",
                    content=full_response,
                    metadata={"model": "claude-sonnet-4-5"}
                )
                self.response_chunks = []
            else:
                # Non-streaming response
                body = json.loads(flow.response.content)
                content = body["content"][0]["text"]
                self._git_commit(type="RESPONSE", content=content)

    def _git_commit(self, type, content, metadata=None):
        """Auto-commit to conversation git repo"""
        # Implementation per LLM_Branching_Tool_Design.md approach
        pass

# Run with: mitmdump -s conversation_capture.py
```

### Usage with Claude Code

```bash
# Set proxy environment variables
export HTTP_PROXY=http://localhost:8080
export HTTPS_PROXY=http://localhost:8080

# Install mitmproxy CA certificate (one-time)
# Follow: https://docs.mitmproxy.org/stable/concepts-certificates/

# Start mitmproxy in background
mitmdump -q -s conversation_capture.py &

# Run Claude Code normally
claude
```

### Advantages
- ✅ **Complete data capture** - Full request/response including metadata, token counts, model info
- ✅ **Real-time streaming** - Process Server-Sent Events as they arrive
- ✅ **Tool-agnostic** - Works with any HTTP-based LLM CLI (Claude, Gemini, GPT, etc.)
- ✅ **Structured JSON** - Direct access to API format, no parsing
- ✅ **No buffer scraping** - Bypass all terminal rendering complexities

### Challenges
- 🔴 **SSL certificate trust** - Must install and trust mitmproxy CA cert
- 🔴 **Proxy configuration** - CLI tool must honor `HTTP_PROXY`/`HTTPS_PROXY` env vars
- 🔴 **Corporate proxies** - May conflict with existing enterprise proxy setup
- 🟡 **Maintenance** - Addon must adapt to API changes

### Use Cases
- Multi-provider support (capture from Claude, Gemini, GPT simultaneously)
- Real-time git commits during conversation
- Development/debugging of LLM interactions
- Audit trail of all API calls

---

## Approach 2: Node.js Runtime Monkey-Patching

### Overview
Intercept `fetch` and Node.js HTTP modules at runtime by injecting patching code before Claude Code executes.

### Implementation

```javascript
// interceptor-loader.js
const originalFetch = global.fetch;
const fs = require('fs');
const { execSync } = require('child_process');

// Patch global fetch
global.fetch = async function(...args) {
  const [url, options] = args;
  const response = await originalFetch(...args);

  // Intercept Claude API calls
  if (url.includes('anthropic.com/v1/messages')) {
    // Capture request
    if (options && options.body) {
      const requestBody = JSON.parse(options.body);
      const prompt = requestBody.messages[requestBody.messages.length - 1];

      // Auto-commit prompt
      commitToGit('PROMPT', prompt.content);
    }

    // Capture response (requires cloning to avoid consuming stream)
    const clone = response.clone();

    if (response.headers.get('content-type')?.includes('text/event-stream')) {
      // Handle streaming response
      const reader = clone.body.getReader();
      const decoder = new TextDecoder();
      let chunks = [];

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value);
        // Parse SSE and accumulate content
        for (const line of chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            try {
              const data = JSON.parse(line.slice(6));
              if (data.type === 'content_block_delta') {
                chunks.push(data.delta.text);
              }
            } catch (e) {}
          }
        }
      }

      // Commit complete response
      commitToGit('RESPONSE', chunks.join(''));
    } else {
      // Non-streaming response
      const json = await clone.json();
      const content = json.content[0].text;
      commitToGit('RESPONSE', content);
    }
  }

  return response;
};

function commitToGit(type, content) {
  const timestamp = new Date().toISOString();
  const summary = content.substring(0, 70).replace(/\n/g, ' ');
  const message = `[${type}] ${timestamp} - ${summary}\n\n${content}`;

  // Write to temp file and commit
  fs.writeFileSync('/tmp/llm-commit-msg.txt', message);
  execSync('git commit --allow-empty -F /tmp/llm-commit-msg.txt', {
    cwd: process.env.LLM_CHAT_REPO || '~/.lazy-llm-chat'
  });
}

// Also patch http/https modules for non-fetch requests
const http = require('http');
const https = require('https');
// ... similar patching logic
```

### Usage

```bash
# Create wrapper script: ~/bin/claude-tracked
#!/bin/bash
node --require ~/bin/interceptor-loader.js $(which claude) "$@"

# Use as normal
claude-tracked
```

### Advantages
- ✅ **No proxy needed** - Direct runtime patching, zero network config
- ✅ **Transparent to user** - Just use `claude-tracked` instead of `claude`
- ✅ **Streaming support** - Can intercept ReadableStream chunks
- ✅ **Full control** - Modify requests/responses, add retry logic, etc.

### Challenges
- 🟡 **Node.js specific** - Only works for Node-based LLM CLIs (Claude Code ✓, others ?)
- 🟡 **Fragile** - May break with Claude Code internal refactors
- 🟡 **Stream handling complexity** - Must carefully clone responses to avoid consuming

### Use Cases
- Single-provider setup (Claude Code only)
- Minimal configuration overhead
- Development environments where proxy setup is problematic

---

## Approach 3: Claude Code's Native JSONL Storage (RECOMMENDED FOR PHASE 1)

### Overview
Claude Code automatically stores all conversation history as JSONL (JSON Lines) files in `~/.claude/projects/`. Parse these files instead of intercepting network traffic.

### Claude Directory Structure Analysis

```
~/.claude/
├── settings.json              # User preferences (e.g., alwaysThinkingEnabled)
├── ide/                       # IDE integration metadata (empty if CLI-only)
├── plugins/
│   ├── config.json           # Plugin repository configuration
│   └── repos/                # Cloned plugin repositories
└── projects/
    └── -<escaped-project-path>/     # One folder per workspace directory
        ├── <session-uuid-1>.jsonl   # Conversation 1
        ├── <session-uuid-2>.jsonl   # Conversation 2
        └── ...                      # Multiple sessions per project

Example:
~/.claude/projects/-Users-paulomoreira-Projects-dev-env/
├── 67390699-92cc-4b0d-83ed-47fc226da7d1.jsonl  # 1038 lines (long conversation)
├── 17c1c574-94b0-443c-b9a3-8f12f13f5ff6.jsonl  # 1 line (summary only)
└── ...
```

**Project folder naming:** Workspace path with `/` replaced by `-` and leading `-` added
- `/Users/paulomoreira/Projects/dev-env` → `-Users-paulomoreira-Projects-dev-env`
- `/home/user/.config/nvim` → `-home-user-.config-nvim`

### JSONL File Format

Each line is a complete JSON object representing one conversation event.

#### Entry Types

**1. User Prompt**
```json
{
  "parentUuid": "previous-message-uuid-or-null",
  "isSidechain": true,
  "userType": "external",
  "cwd": "/Users/paulomoreira/Projects/dev-env",
  "sessionId": "67390699-92cc-4b0d-83ed-47fc226da7d1",
  "version": "2.0.19",
  "gitBranch": "osx",
  "type": "user",
  "message": {
    "role": "user",
    "content": "Warmup"
  },
  "uuid": "901f5212-2d62-4d96-a35b-3febc3dab6ec",
  "timestamp": "2025-10-16T09:34:04.701Z"
}
```

**2. Assistant Response**
```json
{
  "parentUuid": "901f5212-2d62-4d96-a35b-3febc3dab6ec",
  "isSidechain": true,
  "userType": "external",
  "cwd": "/Users/paulomoreira/Projects/dev-env",
  "sessionId": "67390699-92cc-4b0d-83ed-47fc226da7d1",
  "version": "2.0.19",
  "gitBranch": "osx",
  "message": {
    "model": "claude-haiku-4-5-20251001",
    "id": "msg_012soavSHy7KDyPCSW5hvEMd",
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "text",
        "text": "I'm ready to assist..."
      }
    ],
    "stop_reason": null,
    "stop_sequence": null,
    "usage": {
      "input_tokens": 4,
      "cache_creation_input_tokens": 4602,
      "cache_read_input_tokens": 0,
      "cache_creation": {
        "ephemeral_5m_input_tokens": 4602,
        "ephemeral_1h_input_tokens": 0
      },
      "output_tokens": 209,
      "service_tier": "standard"
    }
  },
  "requestId": "req_011CUAeYpeqbsoxi81PvA5jf",
  "type": "assistant",
  "uuid": "bac85984-81c8-46bf-8ca4-6d8f89adc1de",
  "timestamp": "2025-10-16T09:34:10.553Z"
}
```

**3. File History Snapshot**
```json
{
  "type": "file-history-snapshot",
  "messageId": "e02893dd-b28a-417c-a118-2fd73549f4b1",
  "snapshot": {
    "messageId": "e02893dd-b28a-417c-a118-2fd73549f4b1",
    "trackedFileBackups": {},
    "timestamp": "2025-10-16T09:36:01.487Z"
  },
  "isSnapshotUpdate": false
}
```

**4. Summary (First Line)**
```json
{
  "type": "summary",
  "summary": "Development Environment Setup Assistant Ready",
  "leafUuid": "bac85984-81c8-46bf-8ca4-6d8f89adc1de"
}
```

#### Key Fields

- **uuid**: Unique identifier for this message
- **parentUuid**: Links to previous message (builds conversation tree)
- **sessionId**: Groups all messages in one conversation
- **timestamp**: ISO 8601 format
- **gitBranch**: Workspace git branch at time of message
- **cwd**: Current working directory
- **message.content**: The actual prompt/response text
  - For user: string
  - For assistant: array of content blocks (text, tool use, etc.)
- **message.usage**: Token counts (input, output, cache hits)

### Implementation: File System Watcher

```bash
#!/bin/bash
# lazy-llm/libs/claude-jsonl-watcher.sh

CLAUDE_PROJECTS_DIR="${HOME}/.claude/projects"
LLM_CHAT_REPO="${HOME}/.lazy-llm-chat"

# Watch for file changes
fswatch -0 "${CLAUDE_PROJECTS_DIR}" | while read -d "" event; do
  # Only process .jsonl files
  if [[ "$event" == *.jsonl ]]; then
    # Get the last line (most recent entry)
    last_entry=$(tail -n1 "$event")

    # Parse JSON
    type=$(echo "$last_entry" | jq -r '.type')

    case "$type" in
      user)
        content=$(echo "$last_entry" | jq -r '.message.content')
        timestamp=$(echo "$last_entry" | jq -r '.timestamp')
        uuid=$(echo "$last_entry" | jq -r '.uuid')

        # Commit to git
        commit_to_git "PROMPT" "$content" "$timestamp" "$uuid"
        ;;

      assistant)
        content=$(echo "$last_entry" | jq -r '.message.content[0].text')
        timestamp=$(echo "$last_entry" | jq -r '.timestamp')
        uuid=$(echo "$last_entry" | jq -r '.uuid')

        # Commit to git
        commit_to_git "RESPONSE" "$content" "$timestamp" "$uuid"
        ;;

      file-history-snapshot)
        # Optionally track file changes as separate commits
        ;;
    esac
  fi
done

commit_to_git() {
  local type="$1"
  local content="$2"
  local timestamp="$3"
  local uuid="$4"

  local summary="${content:0:70}"
  local message="[${type}] ${timestamp} - ${summary}

${content}

UUID: ${uuid}"

  cd "${LLM_CHAT_REPO}"
  git commit --allow-empty -m "$message"
}
```

### Advantages
- ✅ **Already structured** - Native JSON format, no parsing complexity
- ✅ **No interception** - Use Claude's own storage mechanism
- ✅ **Reliable** - Official storage format, unlikely to break
- ✅ **Rich metadata** - Token counts, model info, git branch, cwd all included
- ✅ **Parent tracking** - `parentUuid` provides conversation tree structure
- ✅ **Zero configuration** - Works out of the box, no proxy/patching

### Challenges
- 🔴 **Claude-specific** - Won't work with Gemini CLI, GPT CLI, etc.
- 🔴 **Write delay** - File updates may lag behind real-time TUI display (seconds?)
- 🔴 **Incomplete data for interruptions** - Interrupted responses may not be written
- 🟡 **File watching overhead** - `fswatch` monitors entire projects directory

### Use Cases
- **Phase 1 implementation** - Quickest path to working branching tool
- Single-provider setup (Claude Code only)
- Post-conversation analysis and export
- Offline conversation replay

### Existing Community Tools

**claude-conversation-extractor** (Python)
```bash
pip install claude-conversation-extractor
claude-extract --format json --extract 1
```

**claude-code-exporter** (Node.js)
```bash
npm install -g claude-code-exporter
claude-prompts --json /path/to/project
```

**claude-history** (Custom parser)
```bash
claude-history ~/.claude/projects/<project>/*.jsonl > conversation.md
```

---

## Approach 4: Direct SDK Integration

### Overview
Instead of using Claude Code CLI as-is, build a custom TUI using Anthropic's SDK directly, giving full control over request/response lifecycle.

### Implementation Sketch

```python
# lazy-llm/tui.py
import anthropic
from git import Repo
from rich.console import Console

client = anthropic.Anthropic()
repo = Repo('.lazy-llm-chat')
console = Console()

def send_prompt(prompt, context_messages):
    """Send prompt and auto-commit to git"""

    # Commit user prompt first
    commit_message(repo, "PROMPT", prompt)

    # Send to Claude with streaming
    response_chunks = []

    with client.messages.stream(
        model="claude-sonnet-4-5-20250929",
        max_tokens=8192,
        messages=context_messages + [{"role": "user", "content": prompt}]
    ) as stream:
        for chunk in stream:
            if chunk.type == "content_block_delta":
                text = chunk.delta.text
                response_chunks.append(text)

                # Display in real-time
                console.print(text, end="")

    # Commit complete response
    full_response = ''.join(response_chunks)
    commit_message(repo, "RESPONSE", full_response)

    return full_response

def commit_message(repo, type, content):
    """Commit per LLM_Branching_Tool_Design.md spec"""
    timestamp = datetime.now().isoformat()
    summary = content[:70].replace('\n', ' ')

    message = f"[{type}] {timestamp} - {summary}\n\n{content}"
    repo.index.commit(message, allow_empty=True)
```

### Advantages
- ✅ **Full control** - Complete lifecycle management of conversations
- ✅ **Structured data** - Native SDK types, no parsing
- ✅ **Multi-provider** - Easy to abstract (Claude, GPT, Gemini)
- ✅ **Custom features** - Add retry logic, prompt templates, multi-model, etc.
- ✅ **Guaranteed commits** - No reliance on file writes or network capture

### Challenges
- 🔴 **Re-implement TUI** - Lose Claude Code's features (tool use, MCP servers, etc.)
- 🔴 **Maintenance burden** - Must track API changes across providers
- 🔴 **Feature parity** - Significant effort to match Claude Code's capabilities

### Use Cases
- Custom LLM workflows requiring features Claude Code doesn't offer
- Multi-provider abstraction layer
- Long-term goal after validating branching tool concept

---

## Recommended Implementation Strategy

### Phase 1: Immediate Value (Week 1)
**Use Approach 3: Claude JSONL Storage**

```bash
# Implementation steps:
1. Write JSONL parser (parse ~/.claude/projects/)
2. Set up fswatch monitoring
3. Auto-commit to git on each new message
4. Basic TUI for viewing conversation graph
```

**Why start here:**
- ✅ Zero configuration overhead
- ✅ Already have structured data
- ✅ Validate git-based branching concept quickly
- ✅ Learn conversation structure before building complex capture

**Limitations accepted:**
- Claude Code only (okay for MVP)
- Slight lag between TUI and commits (acceptable)
- No interrupted response capture (edge case)

### Phase 2: Robustness (Month 1)
**Add Approach 1: mitmproxy Interception**

```bash
# Implementation steps:
1. Create mitmproxy addon for real-time capture
2. Handle streaming responses properly
3. Support multiple LLM providers (Claude, Gemini)
4. Fallback to JSONL if proxy fails
```

**Why add this:**
- ✅ Real-time capture (no file write lag)
- ✅ Multi-provider support
- ✅ Captures interruptions and edge cases
- ✅ Fallback provides resilience

### Phase 3: Advanced Features (Month 2+)
**Consider Approach 4: Direct SDK**

Only if:
- Need features Claude Code doesn't offer
- Want truly unified multi-provider experience
- Willing to invest in custom TUI development

---

## Technical Considerations

### Git Commit Strategy (from LLM_Branching_Tool_Design.md)

**Per the design doc, use Approach B (Hybrid):**
- Commit message contains metadata (type, timestamp)
- Commit body contains summary
- Full content in tracked file: `data/<commit_hash>.md`

**Example:**
```bash
# Prompt commit
git commit -m "[PROMPT] 2025-10-23T15:34:00Z - How do I implement..."

# Creates file: data/abc123.md
# Content: full prompt text

# Response commit
git commit -m "[RESPONSE] 2025-10-23T15:34:15Z - To implement this feature..."

# Creates file: data/def456.md
# Content: full response text
```

### Workspace State Syncing

From design doc decision: Store workspace git hash in chat commit metadata.

**Enhancement for JSONL approach:**
Claude already provides `gitBranch` in each JSONL entry! Also capture:
- `cwd`: Current working directory
- `version`: Claude Code version

```json
{
  "gitBranch": "osx",
  "cwd": "/Users/paulomoreira/Projects/dev-env"
}
```

Add to commit message:
```
[PROMPT] 2025-10-23T15:34:00Z - How do I implement...

Workspace-Commit: <hash from git rev-parse HEAD>
Workspace-Branch: osx
CWD: /Users/paulomoreira/Projects/dev-env
Claude-Version: 2.0.19
```

### Handling Interrupted Responses

**Network capture (Approaches 1, 2):** Commit partial response with `RESPONSE_PARTIAL` type

**JSONL storage (Approach 3):** May not have partial data if Claude didn't write before interruption. Accept this limitation for Phase 1.

### Multi-Provider Considerations

**JSONL approach:** Claude-specific, need different parsers for Gemini, GPT

**Network capture:** Provider-agnostic, works with any HTTP-based LLM

**Long-term:** Abstraction layer that supports both:
```python
class ConversationCapture:
    def __init__(self, provider="claude"):
        if provider == "claude":
            self.capturer = ClaudeJSONLCapturer()
        elif provider == "gemini":
            self.capturer = GeminiNetworkCapturer()
        # ...
```

---

## Security & Privacy Considerations

### Network Interception Risks
- Proxy captures ALL traffic, not just LLM (filter carefully)
- mitmproxy CA cert is trusted root (revoke after testing)
- Corporate networks may block/detect proxying

### Storage Security
- `~/.claude/projects/` contains full conversation history
- JSONL files are plaintext (consider encryption at rest)
- Git repos should be in user-only directories (0700 permissions)

### API Keys & Secrets
- Ensure git commits don't include accidentally pasted secrets
- Add pre-commit hooks to scan for common secret patterns

---

## Performance Characteristics

### JSONL File Watching
- **CPU:** Minimal (fswatch is efficient)
- **Disk I/O:** Low (tails files, doesn't re-read entire history)
- **Latency:** ~1-3 seconds after message appears in TUI

### Network Interception
- **CPU:** Moderate (SSL decryption + JSON parsing)
- **Memory:** Low (streaming processing, not buffering)
- **Latency:** Near-zero (captures as request/response happens)

### Git Operations
- **Commit overhead:** ~10-50ms per commit (acceptable for conversational cadence)
- **Repository size growth:** ~1KB per message (manageable)
- **Graph visualization:** Fast (<1s for 1000+ commits with git log --graph)

---

## Testing Strategy

### Phase 1 Validation
1. Start Claude Code conversation
2. Verify JSONL file appears in `~/.claude/projects/`
3. Send 3 prompts, verify 6 entries (3 user + 3 assistant)
4. Parse JSONL and commit to test git repo
5. View git log --graph and verify structure

### Phase 2 Validation
1. Start mitmproxy with addon
2. Send conversation through proxy
3. Verify captures match JSONL file contents
4. Test with interrupted response (Ctrl+C mid-generation)
5. Compare capture fidelity vs JSONL

### Edge Case Testing
- Empty prompts
- Very long responses (>10K tokens)
- Rapid-fire prompts (queue handling)
- Network failures mid-response
- Claude Code crashes/restarts

---

## Open Questions & Future Research

1. **Can we detect when Claude auto-compacts context?**
   - Impact: Would affect conversation replay accuracy
   - Solution: Monitor token usage fields in JSONL

2. **How to handle tool use (bash, file edits)?**
   - Option A: Commit as separate entry type (TOOL_USE)
   - Option B: Embed in response commit message as metadata

3. **Should file-history-snapshots trigger git commits?**
   - Pro: Complete audit trail
   - Con: Noisy history with many file change commits

4. **Real-time vs. batch commit strategy?**
   - Real-time: Immediate, but interrupts if git is slow
   - Batch: Queue commits, flush every 5s or on conversation end

5. **How to handle multi-turn tool use loops?**
   - Claude sends response → uses tool → updates response
   - Git structure: Linear chain of commits or tree with tool branches?

---

## References & Further Reading

- [mitmproxy Documentation](https://docs.mitmproxy.org/stable/)
- [Anthropic API Reference](https://docs.anthropic.com/en/api)
- [Server-Sent Events Specification](https://html.spec.whatwg.org/multipage/server-sent-events.html)
- [claude-conversation-extractor GitHub](https://github.com/ZeroSumQuant/claude-conversation-extractor)
- [LLM_Branching_Tool_Design.md](./LLM_Branching_Tool_Design.md) - Parent design document

---

**Document Version:** 1.0
**Created:** 2025-10-23
**Status:** Research Complete
**Next Steps:** Implement Phase 1 (JSONL parsing + git commits)
