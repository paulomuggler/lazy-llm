#!/usr/bin/env bash
# Integration test specific assertions

# Source base assertions from unit tests
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

# Assert autosubmit worked (response appears without manual intervention)
assert_autosubmit_success() {
    local ai_output=$1
    local message=${2:-"Autosubmit should work (response appears after END PROMPT)"}

    # Extract content after ### END PROMPT
    local after_marker=$(echo "$ai_output" | sed -n '/### END PROMPT/,$p' | tail -n +2)

    # Check if there's substantial content (not just whitespace)
    local content_length=$(echo "$after_marker" | tr -d '[:space:]' | wc -c)

    if [ "$content_length" -gt 10 ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        echo "  No response found after END PROMPT marker"
        echo "  This suggests autosubmit failed and manual Enter would be needed"
        echo "  Content length: $content_length chars"
        return 1
    fi
}

# Assert response contains code block
assert_contains_code_block() {
    local response=$1
    local language=${2:-""}  # Optional language specifier
    local message=${3:-"Response should contain code block"}

    if [ -n "$language" ]; then
        # Check for specific language code fence
        if echo "$response" | grep -q "\`\`\`$language"; then
            ((ASSERTIONS_PASSED++))
            print_pass "$message (language: $language)"
            return 0
        else
            ((ASSERTIONS_FAILED++))
            print_fail "$message (language: $language)"
            return 1
        fi
    else
        # Check for any code fence
        if echo "$response" | grep -q "\`\`\`"; then
            ((ASSERTIONS_PASSED++))
            print_pass "$message"
            return 0
        else
            ((ASSERTIONS_FAILED++))
            print_fail "$message"
            return 1
        fi
    fi
}

# Assert response doesn't have the Gemini truncation bug
assert_no_prompt_repetition() {
    local ai_output=$1
    local message=${2:-"Should not repeat prompt multiple times (Gemini bug)"}

    # Count how many times ### PROMPT appears
    local prompt_count=$(echo "$ai_output" | grep -c "^### PROMPT")

    if [ "$prompt_count" -eq 1 ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        echo "  Found $prompt_count PROMPT markers (expected 1)"
        echo "  This indicates the Gemini truncation/repetition bug"
        return 1
    fi
}

# Assert markers have proper line breaks
assert_markers_have_line_breaks() {
    local ai_output=$1
    local message=${2:-"Markers should have proper line breaks"}

    local has_issues=false

    # Check if PROMPT marker is on its own line
    if ! echo "$ai_output" | grep -E "^### PROMPT" > /dev/null; then
        echo "  WARNING: PROMPT marker not at start of line"
        has_issues=true
    fi

    # Check if END PROMPT marker is on its own line
    if ! echo "$ai_output" | grep -E "^### END PROMPT$" > /dev/null; then
        echo "  WARNING: END PROMPT marker not on its own line"
        has_issues=true
    fi

    if [ "$has_issues" = false ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        return 1
    fi
}

# Assert response time is reasonable
assert_response_time() {
    local start_time=$1
    local end_time=$2
    local max_seconds=${3:-30}
    local message=${4:-"Response time should be reasonable"}

    local elapsed=$((end_time - start_time))

    if [ $elapsed -le $max_seconds ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message (${elapsed}s, max: ${max_seconds}s)"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message (${elapsed}s, max: ${max_seconds}s)"
        return 1
    fi
}

# Assert response is not empty or error message
assert_valid_response() {
    local response=$1
    local message=${2:-"Response should be valid (not error or empty)"}

    # Remove whitespace for empty check
    local trimmed=$(echo "$response" | tr -d '[:space:]')

    if [ -z "$trimmed" ]; then
        ((ASSERTIONS_FAILED++))
        print_fail "$message - Response is empty"
        return 1
    fi

    # Check for common error indicators
    if echo "$response" | grep -qi "error\|exception\|failed\|forbidden\|unauthorized"; then
        ((ASSERTIONS_FAILED++))
        print_fail "$message - Response contains error"
        echo "  Response: ${response:0:200}..."
        return 1
    fi

    ((ASSERTIONS_PASSED++))
    print_pass "$message"
    return 0
}

# Log known bug
log_known_bug() {
    local bug_description=$1
    print_info "KNOWN BUG: $bug_description"
}
