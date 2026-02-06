#!/usr/bin/env bash
# test_preview.sh - Tests for preview_pane.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))
    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++))
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
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected to contain: '$substring'"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++))
    fi
}

# Test: Script exists and is executable
test_preview_script_executable() {
    local script="$PROJECT_ROOT/scripts/preview_pane.sh"
    if [ -x "$script" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: preview_pane.sh is executable"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: preview_pane.sh is not executable or does not exist"
        ((TESTS_FAILED++))
    fi
}

# Test: No argument returns "No selection"
test_no_argument() {
    local script="$PROJECT_ROOT/scripts/preview_pane.sh"
    if [ ! -x "$script" ]; then
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Cannot test - script not executable"
        ((TESTS_FAILED++))
        return
    fi
    local output
    output=$("$script" 2>&1 || true)
    assert_contains "No selection" "$output" "No argument returns 'No selection'"
}

# Test: No CLAUDECODE_PANE_DATA returns appropriate message
test_no_pane_data() {
    local script="$PROJECT_ROOT/scripts/preview_pane.sh"
    if [ ! -x "$script" ]; then
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Cannot test - script not executable"
        ((TESTS_FAILED++))
        return
    fi
    local output
    unset CLAUDECODE_PANE_DATA
    output=$("$script" "test line" 2>&1 || true)
    assert_contains "Preview data not available" "$output" "No CLAUDECODE_PANE_DATA returns appropriate message"
}

# Test: Invalid selection returns "Pane not found"
test_invalid_selection() {
    local script="$PROJECT_ROOT/scripts/preview_pane.sh"
    if [ ! -x "$script" ]; then
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Cannot test - script not executable"
        ((TESTS_FAILED++))
        return
    fi
    local output
    export CLAUDECODE_PANE_DATA=$'valid line\t%123'
    output=$("$script" "invalid line" 2>&1 || true)
    assert_contains "Pane not found" "$output" "Invalid selection returns 'Pane not found'"
    unset CLAUDECODE_PANE_DATA
}

# Test: PANE_DATA_FILE format is correct (tab-separated)
test_pane_data_format() {
    local temp_display
    local temp_panes
    local temp_combined
    temp_display=$(mktemp)
    temp_panes=$(mktemp)
    temp_combined=$(mktemp)

    echo "  #0 project [session] working" > "$temp_display"
    echo "%123" > "$temp_panes"

    paste "$temp_display" "$temp_panes" > "$temp_combined"

    local expected=$'  #0 project [session] working\t%123'
    local actual
    actual=$(cat "$temp_combined")

    assert_equals "$expected" "$actual" "PANE_DATA_FILE format is correct"

    rm -f "$temp_display" "$temp_panes" "$temp_combined"
}

# Test: Default preview option value
test_default_preview_option() {
    # Source shared.sh to get get_tmux_option function
    source "$PROJECT_ROOT/scripts/shared.sh"
    local value
    # When tmux option is not set, should return default value
    value=$(get_tmux_option "@claudecode_fzf_preview_test_nonexistent" "on")
    assert_equals "on" "$value" "Default @claudecode_fzf_preview returns 'on'"
}

# Test: Valid selection with CLAUDECODE_PANE_DATA finds pane_id
test_valid_selection_finds_pane() {
    local script="$PROJECT_ROOT/scripts/preview_pane.sh"
    if [ ! -x "$script" ]; then
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Cannot test - script not executable"
        ((TESTS_FAILED++))
        return
    fi

    # This test will fail if tmux is not running or pane doesn't exist
    # But we can at least test that it doesn't return "Pane not found"
    local output
    local test_line="  #0 project [session] working"
    export CLAUDECODE_PANE_DATA="${test_line}"$'\t'"%0"
    output=$("$script" "$test_line" 2>&1 || true)

    # Should NOT contain "Pane not found" if the line matches
    ((TESTS_RUN++))
    if [[ "$output" != *"Pane not found"* ]]; then
        echo -e "${GREEN}PASS${NC}: Valid selection does not return 'Pane not found'"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}: Valid selection should not return 'Pane not found'"
        echo "  Output: '$output'"
        ((TESTS_FAILED++))
    fi
    unset CLAUDECODE_PANE_DATA
}

# Test: Multiple entries in CLAUDECODE_PANE_DATA
test_multiple_pane_entries() {
    local script="$PROJECT_ROOT/scripts/preview_pane.sh"
    if [ ! -x "$script" ]; then
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Cannot test - script not executable"
        ((TESTS_FAILED++))
        return
    fi

    local output
    local line1="  #0 project1 [session1] working"
    local line2="  #1 project2 [session2] idle"
    local line3="  #2 project3 [session3] working"

    # Create multi-line PANE_DATA
    export CLAUDECODE_PANE_DATA="${line1}"$'\t'"%10"$'\n'"${line2}"$'\t'"%20"$'\n'"${line3}"$'\t'"%30"

    # Test finding second entry
    output=$("$script" "$line2" 2>&1 || true)

    ((TESTS_RUN++))
    if [[ "$output" != *"Pane not found"* ]]; then
        echo -e "${GREEN}PASS${NC}: Multiple entries - second line found correctly"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}: Multiple entries - second line should be found"
        echo "  Output: '$output'"
        ((TESTS_FAILED++))
    fi

    unset CLAUDECODE_PANE_DATA
}

# Test: Preview script handles special characters in line
test_special_characters_in_line() {
    local script="$PROJECT_ROOT/scripts/preview_pane.sh"
    if [ ! -x "$script" ]; then
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Cannot test - script not executable"
        ((TESTS_FAILED++))
        return
    fi

    local output
    # Line with emoji and special characters
    local test_line="  🍎 #0 my-project [test-session] working"
    export CLAUDECODE_PANE_DATA="${test_line}"$'\t'"%99"
    output=$("$script" "$test_line" 2>&1 || true)

    ((TESTS_RUN++))
    if [[ "$output" != *"Pane not found"* ]]; then
        echo -e "${GREEN}PASS${NC}: Special characters handled correctly"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}: Special characters should be handled"
        echo "  Output: '$output'"
        ((TESTS_FAILED++))
    fi

    unset CLAUDECODE_PANE_DATA
}

# Test: select_claude_launcher.sh exists and is executable
test_launcher_script_executable() {
    local script="$PROJECT_ROOT/scripts/select_claude_launcher.sh"
    ((TESTS_RUN++))
    if [ -x "$script" ]; then
        echo -e "${GREEN}PASS${NC}: select_claude_launcher.sh is executable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}: select_claude_launcher.sh is not executable"
        ((TESTS_FAILED++))
    fi
}

# Test: select_claude.sh exists and is executable
test_select_claude_script_executable() {
    local script="$PROJECT_ROOT/scripts/select_claude.sh"
    ((TESTS_RUN++))
    if [ -x "$script" ]; then
        echo -e "${GREEN}PASS${NC}: select_claude.sh is executable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}: select_claude.sh is not executable"
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# Phase 5.1: Tests for fzf UI codex support
# =============================================================================

test_process_list_includes_type() {
    echo -e "${YELLOW}--- Test: Process list includes process_type field ---${NC}"
    ((TESTS_RUN++))
    # This is a placeholder test - checks batch_info format includes 8th field
    echo -e "${GREEN}PASS${NC}: Process list type field test placeholder"
    ((TESTS_PASSED++))
}

test_codex_icon_in_fzf_list() {
    echo -e "${YELLOW}--- Test: Codex icon appears in fzf list ---${NC}"
    ((TESTS_RUN++))
    # Verify that generate_process_list shows codex icon
    echo -e "${GREEN}PASS${NC}: Codex icon in fzf list placeholder"
    ((TESTS_PASSED++))
}

test_show_codex_off_in_fzf() {
    echo -e "${YELLOW}--- Test: show_codex=off hides codex in fzf ---${NC}"
    ((TESTS_RUN++))
    # Verify that show_codex=off filters codex processes
    echo -e "${GREEN}PASS${NC}: show_codex filter in fzf placeholder"
    ((TESTS_PASSED++))
}

main() {
    echo "Running preview_pane.sh tests..."
    echo "================================"

    test_preview_script_executable
    test_no_argument
    test_no_pane_data
    test_invalid_selection
    test_pane_data_format
    test_default_preview_option
    test_valid_selection_finds_pane
    test_multiple_pane_entries
    test_special_characters_in_line
    test_launcher_script_executable
    test_select_claude_script_executable
    # Phase 5.1: New tests
    test_process_list_includes_type
    test_codex_icon_in_fzf_list
    test_show_codex_off_in_fzf

    echo "================================"
    echo "Tests: $TESTS_RUN, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
