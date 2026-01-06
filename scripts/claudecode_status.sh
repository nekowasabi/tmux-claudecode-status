#!/usr/bin/env bash
# claudecode_status.sh - Claude Code status information for tmux
# Outputs formatted status for display in tmux statusline

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"
source "$CURRENT_DIR/session_tracker.sh"

# Default configuration
DEFAULT_ICON=""                    # Nerd Font: robot
DEFAULT_WORKING_DOT="🤖"
DEFAULT_IDLE_DOT="🔔"
DEFAULT_SEPARATOR=" "              # セッション間のセパレータ
DEFAULT_WORKING_COLOR=""           # 作業中の色（空の場合は色なし）
DEFAULT_IDLE_COLOR=""              # アイドル中の色（空の場合は色なし）
DEFAULT_LEFT_SEP=""                # 左側の囲み文字
DEFAULT_RIGHT_SEP=""               # 右側の囲み文字

# Terminal emoji priority for sorting
# Priority: 🍎(iTerm)=1, ⚡(WezTerm)=2, 👻(Ghostty)=3, 🪟(Windows Terminal)=4, ❓(other)=5
get_terminal_priority() {
    local emoji="$1"
    case "$emoji" in
        🍎) echo 1 ;;
        ⚡) echo 2 ;;
        👻) echo 3 ;;
        🪟) echo 4 ;;
        *)  echo 5 ;;
    esac
}

# Cache configuration
CACHE_DIR="/tmp"
CACHE_FILE="$CACHE_DIR/claudecode_status_cache_$$"
CACHE_TTL=2

# Clean up cache on exit
cleanup_cache() {
    rm -f "$CACHE_FILE"
}
trap cleanup_cache EXIT

main() {
    # Check cache
    if [ -f "$CACHE_FILE" ]; then
        local cache_age
        cache_age=$(( $(get_current_timestamp) - $(get_file_mtime "$CACHE_FILE") ))
        if [ "$cache_age" -lt "$CACHE_TTL" ]; then
            cat "$CACHE_FILE"
            return
        fi
    fi

    # Get session details (新形式: terminal_emoji:pane_index:project_name:status|...)
    local details
    details=$(get_session_details)

    # No sessions
    if [ -z "$details" ]; then
        echo "" > "$CACHE_FILE"
        cat "$CACHE_FILE"
        return
    fi

    # Load user configuration
    local working_dot idle_dot working_color idle_color separator
    local show_terminal show_pane
    local left_sep right_sep
    working_dot=$(get_tmux_option "@claudecode_working_dot" "$DEFAULT_WORKING_DOT")
    idle_dot=$(get_tmux_option "@claudecode_idle_dot" "$DEFAULT_IDLE_DOT")
    working_color=$(get_tmux_option "@claudecode_working_color" "$DEFAULT_WORKING_COLOR")
    idle_color=$(get_tmux_option "@claudecode_idle_color" "$DEFAULT_IDLE_COLOR")
    separator=$(get_tmux_option "@claudecode_separator" "$DEFAULT_SEPARATOR")
    left_sep=$(get_tmux_option "@claudecode_left_sep" "$DEFAULT_LEFT_SEP")
    right_sep=$(get_tmux_option "@claudecode_right_sep" "$DEFAULT_RIGHT_SEP")
    # 新オプション: ターミナル絵文字とペイン番号の表示制御
    show_terminal=$(get_tmux_option "@claudecode_show_terminal" "on")
    show_pane=$(get_tmux_option "@claudecode_show_pane" "on")

    # Generate output: "🍎#0 project-name... ●" 形式
    local output=""
    local first=1

    # Parse details (terminal_emoji:pane_index:project_name:status|...)
    IFS='|' read -ra entries <<< "$details"

    # Sort entries: first by terminal emoji priority, then by pane index
    # Build sortable list with priority prefix
    local sort_input=""
    for entry in "${entries[@]}"; do
        local temp="${entry}"
        local terminal_emoji="${temp%%:*}"
        temp="${temp#*:}"
        local pane_index="${temp%%:*}"

        # Get priority from helper function
        local priority
        priority=$(get_terminal_priority "$terminal_emoji")

        # Extract numeric part from pane_index (e.g., "#3" -> "3")
        local pane_num="${pane_index#\#}"
        # Default to 999 if empty or not a number
        if ! [[ "$pane_num" =~ ^[0-9]+$ ]]; then
            pane_num=999
        fi

        # Append to sort input: priority:pane_num:original_entry (with newline)
        sort_input+="$(printf '%d:%03d:%s' "$priority" "$pane_num" "$entry")"$'\n'
    done

    # Sort and extract original entries
    local sorted_entries=()
    while IFS= read -r line; do
        [ -n "$line" ] && sorted_entries+=("$line")
    done < <(echo -n "$sort_input" | sort -t: -k1,1n -k2,2n | cut -d: -f3-)

    # Use sorted entries
    for entry in "${sorted_entries[@]}"; do
        local terminal_emoji pane_index project_name status dot color prefix

        # Parse entry (terminal_emoji:pane_index:project_name:status)
        # 4つのフィールドに分割
        local temp="${entry}"
        terminal_emoji="${temp%%:*}"
        temp="${temp#*:}"
        pane_index="${temp%%:*}"
        temp="${temp#*:}"
        project_name="${temp%%:*}"
        status="${temp##*:}"

        # 状態に応じてドットと色を選択
        if [ "$status" = "working" ]; then
            dot="$working_dot"
            color="$working_color"
        else
            dot="$idle_dot"
            color="$idle_color"
        fi

        # プレフィックスを構築（ターミナル絵文字 + ペイン番号）
        prefix=""
        if [ "$show_terminal" = "on" ] && [ -n "$terminal_emoji" ]; then
            prefix+="$terminal_emoji"
        fi
        if [ "$show_pane" = "on" ] && [ -n "$pane_index" ]; then
            prefix+="$pane_index"
        fi
        # プレフィックスがあれば末尾にスペースを追加
        if [ -n "$prefix" ]; then
            prefix+=" "
        fi

        # セパレータを追加（最初以外）
        if [ "$first" = "1" ]; then
            first=0
            output+="  "  # Left margin
        else
            output+="$separator"
        fi

        # 色に応じた形式を調整
        local formatted_dot
        if [ -n "$color" ]; then
            formatted_dot="#[fg=$color]${dot}#[default]"
        else
            formatted_dot="${dot}"
        fi

        # プレフィックス + プロジェクト名 + ドットを追加（左右の囲み文字付き）
        output+="${left_sep}${prefix}${project_name} ${formatted_dot}${right_sep}"
        output+="$separator"
    done

    output+="  "  # Right margin

    echo "$output" > "$CACHE_FILE"
    cat "$CACHE_FILE"
}

main "$@"
