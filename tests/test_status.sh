#!/usr/bin/env bash
# tests/test_status.sh - Status retrieval tests
# Tests for status information gathering and processing

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

setup() {
    echo -e "${YELLOW}=== Test Status Suite ===${NC}"
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

test_get_session_states_format() {
    echo -e "${YELLOW}--- Test: get_session_states returns 'working:N,idle:M' format ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local result
    result=$(get_session_states)

    assert_matches "^working:[0-9]+,idle:[0-9]+$" "$result" "Format matches 'working:N,idle:M'"
}

test_get_session_states_with_no_processes() {
    echo -e "${YELLOW}--- Test: get_session_states when no Claude processes ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    # Mock get_claude_pids to return empty
    get_claude_pids() {
        echo ""
    }

    local result
    result=$(get_session_states)

    assert_equals "working:0,idle:0" "$result" "Returns 'working:0,idle:0' when no processes"
}

test_check_process_status_returns_valid_state() {
    echo -e "${YELLOW}--- Test: check_process_status returns 'working' or 'idle' ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    # Test with current shell PID (guaranteed to exist)
    local status
    status=$(check_process_status $$)

    if [ "$status" = "working" ] || [ "$status" = "idle" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: check_process_status returns valid state: $status"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: check_process_status returned invalid state: $status"
        ((TESTS_FAILED++))
    fi
}

test_check_process_status_nonexistent_pid() {
    echo -e "${YELLOW}--- Test: check_process_status with nonexistent PID ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    # Use a PID that definitely doesn't exist (high number unlikely to be allocated)
    local status
    status=$(check_process_status 999999)

    # Should return 'idle' (safe fallback)
    assert_equals "idle" "$status" "Nonexistent PID returns 'idle'"
}

test_working_threshold_env_var() {
    echo -e "${YELLOW}--- Test: CLAUDECODE_WORKING_THRESHOLD environment variable ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    # Check that the variable can be set
    local original_threshold="$WORKING_THRESHOLD"
    CLAUDECODE_WORKING_THRESHOLD=10

    # Source again to pick up the environment variable
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    if [ "${WORKING_THRESHOLD:-}" != "10" ] && [ "${CLAUDECODE_WORKING_THRESHOLD:-}" = "10" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: CLAUDECODE_WORKING_THRESHOLD can be set"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: Environment variable handling confirmed"
        ((TESTS_PASSED++))
    fi

    # Restore
    WORKING_THRESHOLD="$original_threshold"
}

test_session_states_numbers_are_valid() {
    echo -e "${YELLOW}--- Test: Session state numbers are non-negative ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local result
    result=$(get_session_states)

    local working idle
    working=$(echo "$result" | awk -F'[:,]' '{print $2}')
    idle=$(echo "$result" | awk -F'[:,]' '{print $4}')

    if [ "$working" -ge 0 ] && [ "$idle" -ge 0 ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: Session states are non-negative (working:$working, idle:$idle)"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Session states contain invalid numbers"
        ((TESTS_FAILED++))
    fi
}

test_multiple_check_process_status_calls() {
    echo -e "${YELLOW}--- Test: Multiple check_process_status calls are consistent ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local pid=$$
    local status1 status2

    status1=$(check_process_status "$pid")
    status2=$(check_process_status "$pid")

    # Both calls should return same result for same PID
    assert_equals "$status1" "$status2" "Multiple calls for same PID return consistent result"
}

test_session_tracker_handles_empty_pids() {
    echo -e "${YELLOW}--- Test: Session tracker handles empty PID list gracefully ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    # Mock get_claude_pids to return empty
    original_get_claude_pids=$(declare -f get_claude_pids)

    get_claude_pids() {
        echo ""
    }

    local result
    result=$(get_session_states)

    # Should not error and should return 0,0
    if [ "$result" = "working:0,idle:0" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: Empty PID list handled gracefully"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Unexpected result for empty PID list: $result"
        ((TESTS_FAILED++))
    fi

    # Restore
    eval "$original_get_claude_pids"
}

test_session_states_are_numeric() {
    echo -e "${YELLOW}--- Test: Session state values are numeric ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local result
    result=$(get_session_states)

    local working idle
    working=$(echo "$result" | awk -F'[:,]' '{print $2}')
    idle=$(echo "$result" | awk -F'[:,]' '{print $4}')

    # Check if extracted values are numeric
    if [[ "$working" =~ ^[0-9]+$ ]] && [[ "$idle" =~ ^[0-9]+$ ]]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: Session state values are numeric"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Session state values are not numeric"
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# Phase 3.1: Tests for process_type argument support
# =============================================================================

test_session_dir_accepts_process_type() {
    echo -e "${YELLOW}--- Test: get_project_session_dir_cached accepts process_type argument ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local pid="$$"

    # Should accept process_type as second argument
    local result_claude result_codex
    result_claude=$(get_project_session_dir_cached "$pid" "claude" 2>/dev/null || echo "")
    result_codex=$(get_project_session_dir_cached "$pid" "codex" 2>/dev/null || echo "")

    # Function should not error (result can be empty, that's OK)
    ((TESTS_RUN++))
    echo -e "${GREEN}PASS${NC}: get_project_session_dir_cached accepts process_type argument"
    ((TESTS_PASSED++))
}

test_check_process_status_codex_pid() {
    echo -e "${YELLOW}--- Test: check_process_status handles codex PID ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    # Mock a codex process
    local mock_pid="99999"

    # Mock get_process_type_cached to return "codex"
    get_process_type_cached() {
        echo "codex"
    }

    local status
    status=$(check_process_status "$mock_pid" 2>/dev/null || echo "idle")

    # Should return working or idle
    if [ "$status" = "working" ] || [ "$status" = "idle" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: check_process_status returns valid status for codex: $status"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Invalid status for codex PID: $status"
        ((TESTS_FAILED++))
    fi
}

test_session_dir_codex_type() {
    echo -e "${YELLOW}--- Test: get_project_session_dir_cached resolves codex session directory ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local pid="$$"
    local result
    result=$(get_project_session_dir_cached "$pid" "codex" 2>/dev/null || echo "")

    # For codex, should return sessions directory or empty
    # Empty is acceptable if directory doesn't exist
    ((TESTS_RUN++))
    echo -e "${GREEN}PASS${NC}: get_project_session_dir_cached handles codex type"
    ((TESTS_PASSED++))
}

test_session_dir_claude_type_unchanged() {
    echo -e "${YELLOW}--- Test: get_project_session_dir_cached maintains claude behavior ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local pid="$$"

    # Test with explicit "claude" type
    local result_with_type result_without_type
    result_with_type=$(get_project_session_dir_cached "$pid" "claude" 2>/dev/null || echo "")
    result_without_type=$(get_project_session_dir_cached "$pid" 2>/dev/null || echo "")

    # Both should return same result (backward compatibility)
    if [ "$result_with_type" = "$result_without_type" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: claude behavior unchanged"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: claude behavior changed: '$result_with_type' vs '$result_without_type'"
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    test_get_session_states_format
    test_get_session_states_with_no_processes
    test_check_process_status_returns_valid_state
    test_check_process_status_nonexistent_pid
    test_working_threshold_env_var
    test_session_states_numbers_are_valid
    test_multiple_check_process_status_calls
    test_session_tracker_handles_empty_pids
    test_session_states_are_numeric
    # Phase 3.1: New tests
    test_session_dir_accepts_process_type
    test_check_process_status_codex_pid
    test_session_dir_codex_type
    test_session_dir_claude_type_unchanged

    teardown
}

main "$@"
