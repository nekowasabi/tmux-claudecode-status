#!/usr/bin/env bash
# tests/test_golden_master.sh - Golden master regression tests
# Captures current behavior of shared.sh functions before refactoring

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

assert_numeric() {
    local value="$1"
    local message="${2:-}"
    ((TESTS_RUN++))

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected numeric value, got: '$value'"
        ((TESTS_FAILED++))
        return 1
    fi
}

setup() {
    echo -e "${YELLOW}=== Golden Master Test Suite ===${NC}"
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
# Platform Functions
# =============================================================================

test_get_os_returns_valid_os() {
    echo -e "${YELLOW}--- Test: get_os returns Darwin or Linux ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local os
    os=$(get_os)

    if [ "$os" = "Darwin" ] || [ "$os" = "Linux" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: get_os returns valid OS: $os"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: get_os returned unexpected value: $os"
        ((TESTS_FAILED++))
    fi
}

test_get_os_caching() {
    echo -e "${YELLOW}--- Test: get_os caches result ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local os1 os2
    os1=$(get_os)
    os2=$(get_os)

    assert_equals "$os1" "$os2" "get_os returns same value on subsequent calls"
}

test_get_current_timestamp_numeric() {
    echo -e "${YELLOW}--- Test: get_current_timestamp returns numeric value ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local timestamp
    timestamp=$(get_current_timestamp)

    assert_numeric "$timestamp" "get_current_timestamp returns numeric timestamp"
}

test_get_current_timestamp_reasonable() {
    echo -e "${YELLOW}--- Test: get_current_timestamp returns reasonable value ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local timestamp
    timestamp=$(get_current_timestamp)

    # Timestamp should be greater than 2020-01-01 (1577836800) and less than 2100-01-01 (4102444800)
    if [ "$timestamp" -gt 1577836800 ] && [ "$timestamp" -lt 4102444800 ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: Timestamp is in reasonable range: $timestamp"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Timestamp out of range: $timestamp"
        ((TESTS_FAILED++))
    fi
}

test_get_file_mtime_returns_numeric() {
    echo -e "${YELLOW}--- Test: get_file_mtime returns numeric timestamp ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    # Create temporary test file
    local test_file="/tmp/test_mtime_$$"
    touch "$test_file"

    local mtime
    mtime=$(get_file_mtime "$test_file")

    rm -f "$test_file"

    assert_numeric "$mtime" "get_file_mtime returns numeric timestamp"
}

test_get_file_mtime_nonexistent_file() {
    echo -e "${YELLOW}--- Test: get_file_mtime with nonexistent file ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local mtime
    mtime=$(get_file_mtime "/nonexistent/file/path/$$" 2>/dev/null)

    # Should return empty string for nonexistent file
    assert_equals "" "$mtime" "get_file_mtime returns empty for nonexistent file"
}

# =============================================================================
# tmux Option Functions
# =============================================================================

test_get_tmux_option_with_default() {
    echo -e "${YELLOW}--- Test: get_tmux_option returns default when option not set ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local result
    result=$(get_tmux_option "@nonexistent_option_$$" "default_value")

    assert_equals "default_value" "$result" "get_tmux_option returns default for nonexistent option"
}

test_get_tmux_option_cached_fallback() {
    echo -e "${YELLOW}--- Test: get_tmux_option_cached falls back when cache not initialized ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    # Ensure batch is not initialized
    BATCH_INITIALIZED=0

    local result
    result=$(get_tmux_option_cached "@nonexistent_option_$$" "cached_default")

    assert_equals "cached_default" "$result" "get_tmux_option_cached returns default when cache not initialized"
}

# =============================================================================
# Terminal Priority Functions
# =============================================================================

test_get_terminal_priority_iterm() {
    echo -e "${YELLOW}--- Test: get_terminal_priority returns 1 for iTerm emoji ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local priority
    priority=$(get_terminal_priority "🍎")

    assert_equals "1" "$priority" "iTerm emoji (🍎) has priority 1"
}

test_get_terminal_priority_wezterm() {
    echo -e "${YELLOW}--- Test: get_terminal_priority returns 2 for WezTerm emoji ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local priority
    priority=$(get_terminal_priority "⚡")

    assert_equals "2" "$priority" "WezTerm emoji (⚡) has priority 2"
}

test_get_terminal_priority_ghostty() {
    echo -e "${YELLOW}--- Test: get_terminal_priority returns 3 for Ghostty emoji ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local priority
    priority=$(get_terminal_priority "👻")

    assert_equals "3" "$priority" "Ghostty emoji (👻) has priority 3"
}

test_get_terminal_priority_windows() {
    echo -e "${YELLOW}--- Test: get_terminal_priority returns 4 for Windows Terminal emoji ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local priority
    priority=$(get_terminal_priority "🪟")

    assert_equals "4" "$priority" "Windows Terminal emoji (🪟) has priority 4"
}

test_get_terminal_priority_unknown() {
    echo -e "${YELLOW}--- Test: get_terminal_priority returns 5 for unknown emoji ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local priority
    priority=$(get_terminal_priority "❓")

    assert_equals "5" "$priority" "Unknown emoji (❓) has priority 5"
}

test_get_terminal_priority_other() {
    echo -e "${YELLOW}--- Test: get_terminal_priority returns 5 for arbitrary text ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local priority
    priority=$(get_terminal_priority "random")

    assert_equals "5" "$priority" "Arbitrary text has priority 5"
}

# =============================================================================
# Status Priority Functions
# =============================================================================

test_get_status_priority_working() {
    echo -e "${YELLOW}--- Test: get_status_priority returns 0 for working ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local priority
    priority=$(get_status_priority "working")

    assert_equals "0" "$priority" "Status 'working' has priority 0"
}

test_get_status_priority_idle() {
    echo -e "${YELLOW}--- Test: get_status_priority returns 1 for idle ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local priority
    priority=$(get_status_priority "idle")

    assert_equals "1" "$priority" "Status 'idle' has priority 1"
}

test_get_status_priority_other() {
    echo -e "${YELLOW}--- Test: get_status_priority returns 2 for unknown status ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local priority
    priority=$(get_status_priority "unknown")

    assert_equals "2" "$priority" "Unknown status has priority 2"
}

# =============================================================================
# Terminal Emoji Functions
# =============================================================================

test_get_terminal_emoji_returns_emoji() {
    echo -e "${YELLOW}--- Test: get_terminal_emoji returns emoji character ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    # Test with current shell PID (guaranteed to exist)
    local emoji
    emoji=$(get_terminal_emoji $$ "unknown")

    # Should return one of the known emojis
    if [[ "$emoji" =~ ^(🍎|⚡|👻|🪟|📝|🔲|❓)$ ]]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: get_terminal_emoji returns valid emoji: $emoji"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: get_terminal_emoji returned unexpected value: $emoji"
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# Cache Functions
# =============================================================================

test_shared_cache_age_no_file() {
    echo -e "${YELLOW}--- Test: get_shared_cache_age returns 999999 when no cache ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    # Remove cache file if it exists
    rm -f "$SHARED_CACHE_FILE"

    local age
    age=$(get_shared_cache_age)

    assert_equals "999999" "$age" "get_shared_cache_age returns 999999 when cache doesn't exist"
}

test_get_tmux_option_empty_default() {
    echo -e "${YELLOW}--- Test: get_tmux_option handles empty default value ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local result
    result=$(get_tmux_option "@nonexistent_option_$$" "")

    assert_equals "" "$result" "get_tmux_option returns empty string when default is empty"
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    # Platform functions
    test_get_os_returns_valid_os
    test_get_os_caching
    test_get_current_timestamp_numeric
    test_get_current_timestamp_reasonable
    test_get_file_mtime_returns_numeric
    test_get_file_mtime_nonexistent_file

    # tmux option functions
    test_get_tmux_option_with_default
    test_get_tmux_option_cached_fallback
    test_get_tmux_option_empty_default

    # Terminal priority functions
    test_get_terminal_priority_iterm
    test_get_terminal_priority_wezterm
    test_get_terminal_priority_ghostty
    test_get_terminal_priority_windows
    test_get_terminal_priority_unknown
    test_get_terminal_priority_other

    # Status priority functions
    test_get_status_priority_working
    test_get_status_priority_idle
    test_get_status_priority_other

    # Terminal emoji functions
    test_get_terminal_emoji_returns_emoji

    # Cache functions
    test_shared_cache_age_no_file

    teardown
}

main "$@"
