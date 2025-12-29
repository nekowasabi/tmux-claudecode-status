#!/usr/bin/env bash
# session_tracker.sh - Claude Codeセッション追跡
# 各セッションのworking/idle状態を判定

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"

# working判定の閾値（秒）
# この秒数以内にdebugファイルが更新されていればworking
WORKING_THRESHOLD="${CLAUDECODE_WORKING_THRESHOLD:-5}"

# Claude Codeプロセスの PID 一覧を取得
# 戻り値: スペース区切りのPID一覧
get_claude_pids() {
    local pids

    # 方法1: pgrep（最も確実・高速）
    pids=$(pgrep -d ' ' "^claude$" 2>/dev/null)

    if [ -z "$pids" ]; then
        # 方法2: ps経由（フォールバック）
        pids=$(ps aux 2>/dev/null | grep -E "[n]ode.*claude" | awk '{print $2}' | tr '\n' ' ')
    fi

    echo "$pids"
}

# 単一プロセスのworking状態を判定
# $1: PID
# 戻り値: "working" または "idle"
check_process_status() {
    local pid="$1"
    local current_time
    current_time=$(get_current_timestamp)
    local debug_dir="$HOME/.claude/debug"

    # Linux: /proc/{pid}/fd から開いているdebugファイルを特定
    if [ -d "/proc/$pid/fd" ]; then
        local debug_file
        debug_file=$(ls -l "/proc/$pid/fd" 2>/dev/null | grep "$debug_dir" | head -1 | awk '{print $NF}')

        if [ -n "$debug_file" ] && [ -f "$debug_file" ]; then
            local mtime
            mtime=$(get_file_mtime "$debug_file")
            if [ -n "$mtime" ]; then
                local diff=$((current_time - mtime))
                if [ "$diff" -lt "$WORKING_THRESHOLD" ]; then
                    echo "working"
                    return
                fi
            fi
        fi
    fi

    # フォールバック: CPU使用率で判定（5%以上ならworking）
    local cpu
    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' | cut -d. -f1)
    if [ -n "$cpu" ] && [ "$cpu" -gt 5 ] 2>/dev/null; then
        echo "working"
        return
    fi

    echo "idle"
}

# 全セッションの状態を取得
# 戻り値: "working:N,idle:M" 形式
get_session_states() {
    local pids working_count=0 idle_count=0
    pids=$(get_claude_pids)

    if [ -z "$pids" ]; then
        echo "working:0,idle:0"
        return
    fi

    for pid in $pids; do
        local status
        status=$(check_process_status "$pid")
        if [ "$status" = "working" ]; then
            ((working_count++))
        else
            ((idle_count++))
        fi
    done

    echo "working:$working_count,idle:$idle_count"
}

# 直接実行時のテスト用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Claude PIDs: $(get_claude_pids)"
    echo "Session states: $(get_session_states)"
fi
