#!/usr/bin/env bash
# Assertion helpers for lazy-llm tests

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track assertion results
ASSERTIONS_PASSED=0
ASSERTIONS_FAILED=0

# Print colored messages
print_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Assert two values are equal
assert_equals() {
    local actual=$1
    local expected=$2
    local message=${3:-"Values should be equal"}

    if [ "$actual" = "$expected" ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 1
    fi
}

# Assert string contains substring
assert_contains() {
    local haystack=$1
    local needle=$2
    local message=${3:-"Should contain '$needle'"}

    if [[ "$haystack" =~ $needle ]]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        echo "  Looking for: '$needle'"
        echo "  In text: '${haystack:0:200}...'"
        return 1
    fi
}

# Assert string does not contain substring
assert_not_contains() {
    local haystack=$1
    local needle=$2
    local message=${3:-"Should not contain '$needle'"}

    if [[ ! "$haystack" =~ $needle ]]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        echo "  Should not contain: '$needle'"
        echo "  But found it in: '${haystack:0:200}...'"
        return 1
    fi
}

# Assert line count matches condition
assert_line_count() {
    local text=$1
    local operator=$2  # =, >, <, >=, <=
    local count=$3
    local message=${4:-"Line count should be $operator $count"}

    local actual_count=$(echo "$text" | wc -l)

    local pass=false
    case "$operator" in
        "=")  [ "$actual_count" -eq "$count" ] && pass=true ;;
        ">")  [ "$actual_count" -gt "$count" ] && pass=true ;;
        "<")  [ "$actual_count" -lt "$count" ] && pass=true ;;
        ">=") [ "$actual_count" -ge "$count" ] && pass=true ;;
        "<=") [ "$actual_count" -le "$count" ] && pass=true ;;
        *)
            print_fail "Invalid operator: $operator"
            return 1
            ;;
    esac

    if [ "$pass" = true ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message (actual: $actual_count)"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message (actual: $actual_count)"
        return 1
    fi
}

# Assert text matches regex pattern
assert_pattern() {
    local text=$1
    local pattern=$2
    local message=${3:-"Should match pattern"}

    if [[ "$text" =~ $pattern ]]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        echo "  Pattern: '$pattern'"
        echo "  Text: '${text:0:200}...'"
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local filepath=$1
    local message=${2:-"File should exist: $filepath"}

    if [ -f "$filepath" ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        return 1
    fi
}

# Assert file does not exist
assert_file_not_exists() {
    local filepath=$1
    local message=${2:-"File should not exist: $filepath"}

    if [ ! -f "$filepath" ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        return 1
    fi
}

# Assert directory exists
assert_dir_exists() {
    local dirpath=$1
    local message=${2:-"Directory should exist: $dirpath"}

    if [ -d "$dirpath" ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        return 1
    fi
}

# Assert command succeeds (exit code 0)
assert_success() {
    local cmd=$1
    local message=${2:-"Command should succeed: $cmd"}

    if eval "$cmd" > /dev/null 2>&1; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        return 1
    fi
}

# Assert command fails (non-zero exit code)
assert_fails() {
    local cmd=$1
    local message=${2:-"Command should fail: $cmd"}

    if ! eval "$cmd" > /dev/null 2>&1; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        return 1
    fi
}

# Assert string is empty
assert_empty() {
    local value=$1
    local message=${2:-"Value should be empty"}

    if [ -z "$value" ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        echo "  But got: '$value'"
        return 1
    fi
}

# Assert string is not empty
assert_not_empty() {
    local value=$1
    local message=${2:-"Value should not be empty"}

    if [ -n "$value" ]; then
        ((ASSERTIONS_PASSED++))
        print_pass "$message"
        return 0
    else
        ((ASSERTIONS_FAILED++))
        print_fail "$message"
        return 1
    fi
}

# Print assertion summary
print_assertion_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Assertion Results:"
    print_pass "Passed: $ASSERTIONS_PASSED"
    if [ $ASSERTIONS_FAILED -gt 0 ]; then
        print_fail "Failed: $ASSERTIONS_FAILED"
    else
        echo -e "${GREEN}Failed: 0${NC}"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    return $ASSERTIONS_FAILED
}
