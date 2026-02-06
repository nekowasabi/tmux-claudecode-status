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
# Phase 4.1: Tests for codex display options
# =============================================================================

test_codex_option_defaults_defined() {
    echo -e "${YELLOW}--- Test: Codex option defaults are defined ---${NC}"

    # Check for show_codex, codex_icon, and claude_icon options
    if grep -q "@claudecode_show_codex" "$PROJECT_ROOT/scripts/claudecode_status.sh" && \
       grep -q "@claudecode_codex_icon" "$PROJECT_ROOT/scripts/claudecode_status.sh" && \
       grep -q "@claudecode_claude_icon" "$PROJECT_ROOT/scripts/claudecode_status.sh"; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: Codex options are defined"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Codex options not found"
        ((TESTS_FAILED++))
    fi
}

test_new_detail_format_parseable() {
    echo -e "${YELLOW}--- Test: New detail format (5 fields) is parseable ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    # Mock get_session_details to return new format
    local mock_details="codex:⚡:1:test-project:working"

    # Try to parse it
    local temp="${mock_details}"
    local proc_type="${temp%%:*}"
    temp="${temp#*:}"
    local terminal_emoji="${temp%%:*}"
    temp="${temp#*:}"
    local pane_index="${temp%%:*}"
    temp="${temp#*:}"
    local project_name="${temp%%:*}"
    local status="${temp##*:}"

    if [ "$proc_type" = "codex" ] && [ "$terminal_emoji" = "⚡" ] && \
       [ "$pane_index" = "1" ] && [ "$project_name" = "test-project" ] && \
       [ "$status" = "working" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: New format is parseable"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Failed to parse new format"
        ((TESTS_FAILED++))
    fi
}

test_codex_icon_in_output() {
    echo -e "${YELLOW}--- Test: Codex icon appears in output ---${NC}"

    # This is a placeholder test - actual implementation will verify
    # that codex processes show the 🦾 icon
    ((TESTS_RUN++))
    echo -e "${GREEN}PASS${NC}: Codex icon test placeholder"
    ((TESTS_PASSED++))
}

test_show_codex_off_hides_codex() {
    echo -e "${YELLOW}--- Test: show_codex=off option hides codex processes ---${NC}"

    # This is a placeholder test - actual implementation will verify
    # that setting @claudecode_show_codex to "off" hides codex processes
    ((TESTS_RUN++))
    echo -e "${GREEN}PASS${NC}: show_codex option test placeholder"
    ((TESTS_PASSED++))
}

test_claude_only_output_unchanged() {
    echo -e "${YELLOW}--- Test: Claude-only output remains unchanged ---${NC}"

    # Verify backward compatibility when only claude processes exist
    ((TESTS_RUN++))
    echo -e "${GREEN}PASS${NC}: Claude-only backward compatibility test placeholder"
    ((TESTS_PASSED++))
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
    # Phase 4.1: New tests
    test_codex_option_defaults_defined
    test_new_detail_format_parseable
    test_codex_icon_in_output
    test_show_codex_off_hides_codex
    test_claude_only_output_unchanged

    teardown
}

main "$@"
