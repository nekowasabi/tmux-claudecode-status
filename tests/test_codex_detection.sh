#!/usr/bin/env bash
# tests/test_codex_detection.sh - Codex process detection tests
# Tests for detecting both 'claude' and 'codex' processes

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

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    ((TESTS_RUN++))

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected to contain: '$needle'"
        echo "  Actual: '$haystack'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_field_count() {
    local line="$1"
    local expected_count="$2"
    local message="${3:-}"
    ((TESTS_RUN++))

    local actual_count
    actual_count=$(echo "$line" | awk -F'|' '{print NF}')

    if [ "$actual_count" = "$expected_count" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected field count: $expected_count"
        echo "  Actual field count: $actual_count"
        echo "  Line: $line"
        ((TESTS_FAILED++))
        return 1
    fi
}

# モックデータセットアップ
setup_mock_cache() {
    BATCH_DIR=$(mktemp -d)
    BATCH_PROCESS_TREE_FILE="$BATCH_DIR/ps"
    BATCH_PANE_INFO_FILE="$BATCH_DIR/panes"
    BATCH_TERMINAL_CACHE_FILE="$BATCH_DIR/term"
    BATCH_CLIENTS_CACHE_FILE="$BATCH_DIR/clients"
    BATCH_PID_PANE_MAP_FILE="$BATCH_DIR/pidmap"
    BATCH_TMUX_OPTIONS_FILE="$BATCH_DIR/opts"
    BATCH_TTY_STAT_FILE="$BATCH_DIR/ttystat"
    BATCH_LSOF_OUTPUT_FILE="$BATCH_DIR/lsof"
}

teardown_mock_cache() {
    if [ -n "${BATCH_DIR:-}" ] && [ -d "$BATCH_DIR" ]; then
        rm -rf "$BATCH_DIR"
    fi
}

# テストのセットアップ
setup() {
    echo -e "${YELLOW}=== Test Codex Detection Suite ===${NC}"
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

test_build_pid_pane_map_detects_codex() {
    echo -e "${YELLOW}--- Test: _build_pid_pane_map detects codex processes ---${NC}"

    # cache_batch.sh をソース
    source "$PROJECT_ROOT/scripts/lib/cache_batch.sh"

    # モックキャッシュセットアップ
    setup_mock_cache

    # モックデータ作成（codex プロセスのみ）
    cat > "$BATCH_PANE_INFO_FILE" << 'EOF'
%1	5678	test-session	0	0	/dev/pts/1	/home/user/project
EOF

    cat > "$BATCH_PROCESS_TREE_FILE" << 'EOF'
  PID  PPID COMMAND
 5678  1000 node    /home/user/.local/share/mise/installs/node/24/bin/codex --full-auto
EOF

    # 関数実行
    _build_pid_pane_map

    # 結果確認: codex PID がマップされているべき
    local result
    result=$(cat "$BATCH_PID_PANE_MAP_FILE" 2>/dev/null || echo "")

    assert_contains "$result" "5678" "_build_pid_pane_map should detect codex process (PID 5678)"

    teardown_mock_cache
}

test_build_pid_pane_map_detects_both() {
    echo -e "${YELLOW}--- Test: _build_pid_pane_map detects both claude and codex ---${NC}"

    source "$PROJECT_ROOT/scripts/lib/cache_batch.sh"
    setup_mock_cache

    # モックデータ作成（claude + codex）
    cat > "$BATCH_PANE_INFO_FILE" << 'EOF'
%1	1234	session1	0	0	/dev/pts/1	/home/user/project1
%2	5678	session2	0	0	/dev/pts/2	/home/user/project2
EOF

    cat > "$BATCH_PROCESS_TREE_FILE" << 'EOF'
  PID  PPID COMMAND
 1234  1000 claude
 5678  1001 node    /usr/local/bin/codex --full-auto
EOF

    _build_pid_pane_map

    local result
    result=$(cat "$BATCH_PID_PANE_MAP_FILE" 2>/dev/null || echo "")

    assert_contains "$result" "1234" "Should detect claude process (PID 1234)"
    assert_contains "$result" "5678" "Should detect codex process (PID 5678)"

    teardown_mock_cache
}

test_batch_info_includes_process_type() {
    echo -e "${YELLOW}--- Test: get_all_claude_info_batch output includes process_type field ---${NC}"

    source "$PROJECT_ROOT/scripts/lib/cache_batch.sh"
    setup_mock_cache

    # モックデータ作成
    cat > "$BATCH_PANE_INFO_FILE" << 'EOF'
%1	1234	session1	0	0	/dev/pts/1	/home/user/project1
%2	5678	session2	1	0	/dev/pts/2	/home/user/project2
EOF

    cat > "$BATCH_PROCESS_TREE_FILE" << 'EOF'
  PID  PPID COMMAND
 1234  1000 claude
 5678  1001 node    /usr/local/bin/codex --full-auto
EOF

    cat > "$BATCH_TERMINAL_CACHE_FILE" << 'EOF'
session1	kitty
session2	wezterm
EOF

    cat > "$BATCH_CLIENTS_CACHE_FILE" << 'EOF'
session1	/dev/ttys001	9999
session2	/dev/ttys002	9998
EOF

    cat > "$BATCH_PID_PANE_MAP_FILE" << 'EOF'
1234	%1	claude
5678	%2	codex
EOF

    BATCH_INITIALIZED=1

    # 関数実行
    local result
    result=$(get_all_claude_info_batch)

    # 出力が空でないことを確認
    assert_not_empty "$result" "get_all_claude_info_batch should return non-empty result"

    # 各行のフィールド数を確認（8フィールド: 既存7 + process_type）
    local line1 line2
    line1=$(echo "$result" | head -n1)
    line2=$(echo "$result" | tail -n1)

    if [ -n "$line1" ]; then
        assert_field_count "$line1" "8" "Output should have 8 fields (including process_type)"
    fi

    if [ -n "$line2" ] && [ "$line1" != "$line2" ]; then
        # process_type フィールドが 'claude' または 'codex' を含むことを確認
        local process_type
        process_type=$(echo "$line1" | awk -F'|' '{print $8}')
        if [ "$process_type" = "claude" ] || [ "$process_type" = "codex" ]; then
            ((TESTS_RUN++))
            echo -e "${GREEN}PASS${NC}: process_type field contains valid value: $process_type"
            ((TESTS_PASSED++))
        else
            ((TESTS_RUN++))
            echo -e "${RED}FAIL${NC}: process_type field has invalid value: $process_type"
            ((TESTS_FAILED++))
        fi
    fi

    teardown_mock_cache
}

test_batch_info_backward_compatible() {
    echo -e "${YELLOW}--- Test: get_all_claude_info_batch maintains backward compatibility (7 existing fields) ---${NC}"

    source "$PROJECT_ROOT/scripts/lib/cache_batch.sh"
    setup_mock_cache

    # モックデータ作成（claude のみ）
    cat > "$BATCH_PANE_INFO_FILE" << 'EOF'
%1	1234	session1	0	0	/dev/pts/1	/home/user/project
EOF

    cat > "$BATCH_PROCESS_TREE_FILE" << 'EOF'
  PID  PPID COMMAND
 1234  1000 claude
EOF

    cat > "$BATCH_TERMINAL_CACHE_FILE" << 'EOF'
session1	kitty
EOF

    cat > "$BATCH_CLIENTS_CACHE_FILE" << 'EOF'
session1	/dev/ttys001	9999
EOF

    cat > "$BATCH_PID_PANE_MAP_FILE" << 'EOF'
1234	%1	claude
EOF

    BATCH_INITIALIZED=1

    local result
    result=$(get_all_claude_info_batch)

    # 最初の7フィールドが従来どおりであることを確認
    # フォーマット: pid|pane_id|session|window|tty|terminal|cwd|process_type
    local line
    line=$(echo "$result" | head -n1)

    local pid pane_id session window tty terminal cwd
    pid=$(echo "$line" | awk -F'|' '{print $1}')
    pane_id=$(echo "$line" | awk -F'|' '{print $2}')
    session=$(echo "$line" | awk -F'|' '{print $3}')
    window=$(echo "$line" | awk -F'|' '{print $4}')
    tty=$(echo "$line" | awk -F'|' '{print $5}')
    terminal=$(echo "$line" | awk -F'|' '{print $6}')
    cwd=$(echo "$line" | awk -F'|' '{print $7}')

    assert_equals "1234" "$pid" "Field 1 (pid) is correct"
    assert_equals "%1" "$pane_id" "Field 2 (pane_id) is correct"
    assert_equals "session1" "$session" "Field 3 (session) is correct"
    assert_equals "0" "$window" "Field 4 (window) is correct"
    assert_equals "/dev/pts/1" "$tty" "Field 5 (tty) is correct"
    assert_equals "kitty" "$terminal" "Field 6 (terminal) is correct"
    assert_equals "/home/user/project" "$cwd" "Field 7 (cwd) is correct"

    teardown_mock_cache
}

test_no_codex_unchanged_behavior() {
    echo -e "${YELLOW}--- Test: Behavior unchanged when no codex processes exist ---${NC}"

    source "$PROJECT_ROOT/scripts/lib/cache_batch.sh"
    setup_mock_cache

    # モックデータ作成（claude のみ）
    cat > "$BATCH_PANE_INFO_FILE" << 'EOF'
%1	1234	session1	0	0	/dev/pts/1	/home/user/project
EOF

    cat > "$BATCH_PROCESS_TREE_FILE" << 'EOF'
  PID  PPID COMMAND
 1234  1000 claude
 9999  1001 bash
EOF

    cat > "$BATCH_TERMINAL_CACHE_FILE" << 'EOF'
session1	kitty
EOF

    cat > "$BATCH_CLIENTS_CACHE_FILE" << 'EOF'
session1	/dev/ttys001	9999
EOF

    _build_pid_pane_map

    local result
    result=$(cat "$BATCH_PID_PANE_MAP_FILE" 2>/dev/null || echo "")

    # claude プロセスは検出される
    assert_contains "$result" "1234" "Should detect claude process"

    # bash プロセスは検出されない（codex でも claude でもないため）
    if [[ "$result" == *"9999"* ]]; then
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: Should not detect non-claude/codex processes"
        echo "  Result: $result"
        ((TESTS_FAILED++))
    else
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: Does not detect non-claude/codex processes"
        ((TESTS_PASSED++))
    fi

    teardown_mock_cache
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    test_build_pid_pane_map_detects_codex
    test_build_pid_pane_map_detects_both
    test_batch_info_includes_process_type
    test_batch_info_backward_compatible
    test_no_codex_unchanged_behavior

    teardown
}

main "$@"
