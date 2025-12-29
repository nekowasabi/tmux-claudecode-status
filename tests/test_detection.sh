#!/usr/bin/env bash
# tests/test_detection.sh - Detection functionality tests
# Tests for session detection and Claude Code identification

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# テスト結果カウンター
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# テストユーティリティ関数
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

assert_not_empty() {
    local value="$1"
    local message="${2:-}"
    ((TESTS_RUN++))

    if [ -n "$value" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message (value is empty)"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_function_exists() {
    local func_name="$1"
    local message="${2:-Function $func_name exists}"
    ((TESTS_RUN++))

    if type "$func_name" &>/dev/null; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_executable() {
    local file="$1"
    local message="${2:-File $file is executable}"
    ((TESTS_RUN++))

    if [ -x "$file" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        ((TESTS_FAILED++))
        return 1
    fi
}

# テストのセットアップ
setup() {
    echo -e "${YELLOW}=== Test Detection Suite ===${NC}"
    echo ""
}

# テストのクリーンアップ
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

test_shared_sh_exists() {
    echo -e "${YELLOW}--- Test: shared.sh exists and is executable ---${NC}"
    assert_file_executable "$PROJECT_ROOT/scripts/shared.sh" "shared.sh is executable"
}

test_session_tracker_exists() {
    echo -e "${YELLOW}--- Test: session_tracker.sh exists and is executable ---${NC}"
    assert_file_executable "$PROJECT_ROOT/scripts/session_tracker.sh" "session_tracker.sh is executable"
}

test_shared_functions_exist() {
    echo -e "${YELLOW}--- Test: shared.sh functions exist ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    assert_function_exists "get_tmux_option" "get_tmux_option function exists"
    assert_function_exists "set_tmux_option" "set_tmux_option function exists"
    assert_function_exists "get_file_mtime" "get_file_mtime function exists"
    assert_function_exists "get_current_timestamp" "get_current_timestamp function exists"
}

test_session_tracker_functions_exist() {
    echo -e "${YELLOW}--- Test: session_tracker.sh functions exist ---${NC}"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    assert_function_exists "get_claude_pids" "get_claude_pids function exists"
    assert_function_exists "check_process_status" "check_process_status function exists"
    assert_function_exists "get_session_states" "get_session_states function exists"
}

test_get_claude_pids_returns_format() {
    echo -e "${YELLOW}--- Test: get_claude_pids returns space-separated PIDs or empty ---${NC}"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local result
    result=$(get_claude_pids)

    # 結果が空か、数値のスペース区切りであることを確認
    if [ -z "$result" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: get_claude_pids returns empty (no Claude processes)"
        ((TESTS_PASSED++))
    elif [[ "$result" =~ ^[0-9\ ]+$ ]]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: get_claude_pids returns valid PIDs: $result"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: get_claude_pids returned invalid format: $result"
        ((TESTS_FAILED++))
    fi
}

test_get_session_states_format() {
    echo -e "${YELLOW}--- Test: get_session_states returns correct format ---${NC}"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    local result
    result=$(get_session_states)

    # "working:N,idle:M" 形式であることを確認
    if [[ "$result" =~ ^working:[0-9]+,idle:[0-9]+$ ]]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: get_session_states returns valid format: $result"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: get_session_states returned invalid format: $result"
        ((TESTS_FAILED++))
    fi
}

test_get_file_mtime() {
    echo -e "${YELLOW}--- Test: get_file_mtime works correctly ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    # テスト用一時ファイル作成
    local tmp_file="/tmp/test_mtime_$$"
    touch "$tmp_file"

    local mtime
    mtime=$(get_file_mtime "$tmp_file")

    rm -f "$tmp_file"

    # mtimeが数値であることを確認
    if [[ "$mtime" =~ ^[0-9]+$ ]]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: get_file_mtime returns valid timestamp: $mtime"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: get_file_mtime returned invalid timestamp: $mtime"
        ((TESTS_FAILED++))
    fi
}

test_get_current_timestamp() {
    echo -e "${YELLOW}--- Test: get_current_timestamp returns valid timestamp ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"

    local ts
    ts=$(get_current_timestamp)

    # タイムスタンプが数値であることを確認
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: get_current_timestamp returns valid timestamp: $ts"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: get_current_timestamp returned invalid value: $ts"
        ((TESTS_FAILED++))
    fi
}

test_check_process_status_returns_valid_state() {
    echo -e "${YELLOW}--- Test: check_process_status returns 'working' or 'idle' ---${NC}"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"

    # 現在のシェルのPIDでテスト（存在するプロセス）
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

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    test_shared_sh_exists
    test_session_tracker_exists
    test_shared_functions_exist
    test_session_tracker_functions_exist
    test_get_claude_pids_returns_format
    test_get_session_states_format
    test_get_file_mtime
    test_get_current_timestamp
    test_check_process_status_returns_valid_state

    teardown
}

main "$@"
