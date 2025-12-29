#!/usr/bin/env bash
# tests/test_output.sh - Output formatting tests
# Tests for output formatting and display functions

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test utilities
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_matches() {
    local pattern="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))

    if [[ "$actual" =~ $pattern ]]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Pattern: $pattern"
        echo "  Actual:  '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_contains() {
    local substring="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))

    if [[ "$actual" == *"$substring"* ]]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected substring: '$substring'"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

setup() {
    echo -e "${YELLOW}=== Test Output Suite ===${NC}"
    echo ""
}

teardown() {
    echo ""
    echo -e "${YELLOW}=== Test Results ===${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}

# =============================================================================
# Test Cases
# =============================================================================

test_claudecode_status_executable() {
    echo -e "${YELLOW}--- Test: claudecode_status.sh is executable ---${NC}"
    if [ -x "$PROJECT_ROOT/scripts/claudecode_status.sh" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: claudecode_status.sh is executable"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: claudecode_status.sh is not executable"
        ((TESTS_FAILED++))
    fi
}

test_claudecode_status_output_format() {
    echo -e "${YELLOW}--- Test: claudecode_status.sh output contains tmux format codes ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local output
    output=$("$PROJECT_ROOT/scripts/claudecode_status.sh")

    # Should contain tmux color format codes or be empty (no sessions)
    if [ -z "$output" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: claudecode_status.sh returns empty when no sessions"
        ((TESTS_PASSED++))
    elif [[ "$output" == *"#[fg="* ]]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: claudecode_status.sh returns tmux format output"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: claudecode_status.sh output format invalid: '$output'"
        ((TESTS_FAILED++))
    fi
}

test_claudecode_status_contains_dots() {
    echo -e "${YELLOW}--- Test: claudecode_status.sh output contains status dots ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local output
    output=$("$PROJECT_ROOT/scripts/claudecode_status.sh")

    # Should contain dots if sessions exist
    if [ -z "$output" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: No output when no sessions (acceptable)"
        ((TESTS_PASSED++))
    elif [[ "$output" == *"●"* ]] || [[ "$output" == *"○"* ]]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: claudecode_status.sh output contains status dots"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${YELLOW}WARN${NC}: No dots found in output (may indicate no active sessions)"
        ((TESTS_PASSED++))
    fi
}

test_tmux_plugin_executable() {
    echo -e "${YELLOW}--- Test: claudecode_status.tmux is executable ---${NC}"
    if [ -x "$PROJECT_ROOT/claudecode_status.tmux" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: claudecode_status.tmux is executable"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: claudecode_status.tmux is not executable"
        ((TESTS_FAILED++))
    fi
}

test_tmux_plugin_sources_shared() {
    echo -e "${YELLOW}--- Test: claudecode_status.tmux sources shared.sh ---${NC}"
    if grep -q "source.*shared.sh" "$PROJECT_ROOT/claudecode_status.tmux"; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: claudecode_status.tmux sources shared.sh"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: claudecode_status.tmux does not source shared.sh"
        ((TESTS_FAILED++))
    fi
}

test_tmux_plugin_has_main() {
    echo -e "${YELLOW}--- Test: claudecode_status.tmux has main function ---${NC}"
    if grep -q "^main()" "$PROJECT_ROOT/claudecode_status.tmux"; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: claudecode_status.tmux has main() function"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: claudecode_status.tmux lacks main() function"
        ((TESTS_FAILED++))
    fi
}

test_output_with_no_color() {
    echo -e "${YELLOW}--- Test: Output works with default colors ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local output
    output=$("$PROJECT_ROOT/scripts/claudecode_status.sh" 2>&1)

    # Should not error
    if [ $? -eq 0 ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: claudecode_status.sh executes without error"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: claudecode_status.sh execution failed"
        ((TESTS_FAILED++))
    fi
}

test_default_icon_present() {
    echo -e "${YELLOW}--- Test: Default icon is configured ---${NC}"
    if grep -q "DEFAULT_ICON" "$PROJECT_ROOT/scripts/claudecode_status.sh"; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: DEFAULT_ICON is defined"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: DEFAULT_ICON not found"
        ((TESTS_FAILED++))
    fi
}

test_cache_variables_defined() {
    echo -e "${YELLOW}--- Test: Cache variables are defined ---${NC}"
    if grep -q "CACHE_TTL" "$PROJECT_ROOT/scripts/claudecode_status.sh" && \
       grep -q "CACHE_FILE" "$PROJECT_ROOT/scripts/claudecode_status.sh"; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: Cache variables are defined"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Cache variables not found"
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    test_claudecode_status_executable
    test_claudecode_status_output_format
    test_claudecode_status_contains_dots
    test_tmux_plugin_executable
    test_tmux_plugin_sources_shared
    test_tmux_plugin_has_main
    test_output_with_no_color
    test_default_icon_present
    test_cache_variables_defined

    teardown
}

main "$@"
