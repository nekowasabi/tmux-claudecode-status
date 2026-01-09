#!/usr/bin/env bash
# select_claude.sh - Claude Code process selection UI using fzf
# Shows a list of running Claude Code processes with their status
# and allows user to select one to focus
#
# Usage:
#   select_claude.sh              # Interactive mode with fzf
#   select_claude.sh --list       # List mode (just print, no fzf)
#
# Requirements:
#   - fzf (for interactive selection)
#   - tmux (for pane information and switching)

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"

# バッチ処理キャッシュを初期化（高速化のため）
init_batch_cache

# 高速判定モードを有効化（TTY mtimeベースの軽量判定）
FAST_MODE=1

# working判定の閾値（秒）- TTY mtimeがこの秒数以内ならworking
WORKING_THRESHOLD="${CLAUDECODE_WORKING_THRESHOLD:-5}"

# Check for WSL environment
if grep -qEi "(microsoft|wsl)" /proc/version 2>/dev/null; then
    echo "This feature is not supported on WSL" >&2
    exit 1
fi

# Note: get_terminal_priority and get_status_priority are in shared.sh

# Status emoji for display
STATUS_WORKING="working"
STATUS_IDLE="idle"

# Generate list of Claude Code processes for fzf
# Output format: pane_id|terminal_emoji|pane_index|project_name|status|display_line
# 超高速版: 1回のawk呼び出しで全情報を取得（bashのwhileループを完全排除）
generate_process_list() {
    # 一括取得した情報を処理
    local batch_info
    batch_info=$(get_all_claude_info_batch)

    if [ -z "$batch_info" ]; then
        return
    fi

    # ステータスアイコンとターミナル絵文字を一括取得（6回のawk呼び出しを1回に削減）
    local working_dot idle_dot terminal_iterm terminal_wezterm terminal_ghostty terminal_unknown
    eval "$(get_tmux_options_bulk \
        "@claudecode_working_dot=working" \
        "@claudecode_idle_dot=idle" \
        "@claudecode_terminal_iterm=🍎" \
        "@claudecode_terminal_wezterm=⚡" \
        "@claudecode_terminal_ghostty=👻" \
        "@claudecode_terminal_unknown=❓")"

    # 現在時刻を取得
    local current_time
    current_time=$(get_current_timestamp)

    # WORKING_THRESHOLDのデフォルト値
    local threshold="${WORKING_THRESHOLD:-5}"

    # TTY mtime情報はinit_batch_cacheで事前取得済み（BATCH_TTY_STAT_FILE）
    # awkで一括処理（bashのwhileループを完全排除）
    {
        if [ -n "$BATCH_TTY_STAT_FILE" ] && [ -f "$BATCH_TTY_STAT_FILE" ]; then
            cat "$BATCH_TTY_STAT_FILE"
            echo "---SEPARATOR---"
        fi
        echo "$batch_info"
    } | awk -F'|' \
        -v working_icon="$working_dot" \
        -v idle_icon="$idle_dot" \
        -v emoji_iterm="$terminal_iterm" \
        -v emoji_wezterm="$terminal_wezterm" \
        -v emoji_ghostty="$terminal_ghostty" \
        -v emoji_unknown="$terminal_unknown" \
        -v current_time="$current_time" \
        -v threshold="$threshold" \
    '
    BEGIN {
        in_data = 0
    }
    # セパレーター前はTTY mtime情報
    /^---SEPARATOR---$/ {
        in_data = 1
        next
    }
    !in_data {
        # TTY mtime情報: "/dev/ttysXXX mtime"
        split($0, parts, " ")
        tty_mtime[parts[1]] = parts[2]
        next
    }
    {
        pane_id = $2
        session_name = $3
        window_index = $4
        tty_path = $5
        terminal_name = $6
        cwd = $7

        if (pane_id == "") next

        # Skip duplicates
        if (pane_id in seen_panes) next
        seen_panes[pane_id] = 1

        # Terminal emoji変換
        if (terminal_name == "iTerm2" || terminal_name == "Terminal") {
            terminal_emoji = emoji_iterm
        } else if (terminal_name == "WezTerm") {
            terminal_emoji = emoji_wezterm
        } else if (terminal_name == "Ghostty") {
            terminal_emoji = emoji_ghostty
        } else {
            terminal_emoji = emoji_unknown
        }

        # Pane index
        pane_index = "#" window_index

        # Project name（cwdから抽出）
        n = split(cwd, path_parts, "/")
        project_name = path_parts[n]
        if (project_name == "" || project_name == "/") project_name = "claude"

        # 長すぎる場合は省略
        if (length(project_name) > 18) {
            project_name = substr(project_name, 1, 15) "..."
        }

        # Handle duplicate project names
        if (project_name in project_counts) {
            project_counts[project_name]++
            project_name = project_name "#" project_counts[project_name]
        } else {
            project_counts[project_name] = 1
        }

        # Status判定（TTY mtimeベース）
        status = "idle"
        if (tty_path != "" && tty_path in tty_mtime) {
            diff = current_time - tty_mtime[tty_path]
            if (diff < threshold) status = "working"
        }

        # Status display
        status_display = (status == "working") ? working_icon : idle_icon

        # Format display line
        display_line = terminal_emoji " " pane_index " " project_name
        if (session_name != "") display_line = display_line " [" session_name "]"
        display_line = display_line " " status_display

        # Output: pane_id|terminal_emoji|pane_index|project_name|status|display_line
        print pane_id "|" terminal_emoji "|" pane_index "|" project_name "|" status "|" display_line
    }
    '
}

# Sort process list by status (working first) and terminal priority
# 高速版: awkでソートキーを付与し、sortで一括処理
sort_process_list() {
    awk -F'|' '
    {
        pane_id = $1
        terminal_emoji = $2
        pane_index = $3
        project_name = $4
        status = $5
        display_line = $6

        # Status priority (working=0, idle=1)
        status_priority = (status == "working") ? 0 : 1

        # Terminal priority
        if (index(terminal_emoji, "🍎") > 0) terminal_priority = 1
        else if (index(terminal_emoji, "⚡") > 0) terminal_priority = 2
        else if (index(terminal_emoji, "👻") > 0) terminal_priority = 3
        else if (index(terminal_emoji, "🪟") > 0) terminal_priority = 4
        else terminal_priority = 5

        # Pane number
        pane_num = substr(pane_index, 2)
        if (pane_num !~ /^[0-9]+$/) pane_num = 999

        # Output with sort key
        printf "%d:%d:%03d|%s|%s|%s|%s|%s|%s\n", \
            status_priority, terminal_priority, pane_num, \
            pane_id, terminal_emoji, pane_index, project_name, status, display_line
    }
    ' | sort -t: -k1,1n -k2,2n -k3,3n | cut -d'|' -f2-
}

# Run fzf selection
run_fzf_selection() {
    local process_list
    process_list=$(generate_process_list | sort_process_list)

    if [ -z "$process_list" ]; then
        echo "No Claude Code processes found." >&2
        return 1
    fi

    # Prepare fzf input (display lines only)
    local fzf_input=""
    local -a pane_ids=()
    local -a display_lines=()
    local index=0

    while IFS='|' read -r pane_id terminal_emoji pane_index project_name status display_line; do
        pane_ids+=("$pane_id")
        display_lines+=("$display_line")
        if [ -n "$fzf_input" ]; then
            fzf_input+=$'\n'
        fi
        fzf_input+="$display_line"
        ((index++))
    done <<< "$process_list"

    # Check if fzf is available
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed. Please install fzf first." >&2
        echo "  brew install fzf  # macOS" >&2
        echo "  apt install fzf   # Ubuntu/Debian" >&2
        return 1
    fi

    # Get fzf options from tmux（キャッシュ版を使用）
    local fzf_opts
    # Note: --border removed because tmux popup already provides a border
    fzf_opts=$(get_tmux_option_cached "@claudecode_fzf_opts" "--height=100% --reverse --prompt=Select\\ Claude:\\ ")

    # Run fzf
    local selected
    # Use eval to properly handle escaped spaces in fzf options
    selected=$(echo "$fzf_input" | eval "fzf $fzf_opts")

    if [ -z "$selected" ]; then
        return 1
    fi

    # Find matching pane_id
    for i in "${!display_lines[@]}"; do
        if [ "${display_lines[$i]}" = "$selected" ]; then
            echo "${pane_ids[$i]}"
            return 0
        fi
    done

    return 1
}

# List mode (print process list without fzf)
list_mode() {
    local process_list
    process_list=$(generate_process_list | sort_process_list)

    if [ -z "$process_list" ]; then
        echo "No Claude Code processes found."
        return 1
    fi

    echo "Claude Code Processes:"
    echo "========================"

    while IFS='|' read -r pane_id terminal_emoji pane_index project_name status display_line; do
        echo "  $display_line"
        echo "    Pane ID: $pane_id"
        echo ""
    done <<< "$process_list"
}

# Main function
main() {
    local mode="interactive"

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --list|-l)
                mode="list"
                shift
                ;;
            --help|-h)
                echo "Usage: select_claude.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --list, -l    List mode (print without fzf)"
                echo "  --help, -h    Show this help message"
                echo ""
                echo "Interactive mode (default):"
                echo "  Uses fzf to select a Claude Code process and focuses it."
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    case "$mode" in
        list)
            list_mode
            ;;
        interactive)
            local selected_pane
            selected_pane=$(run_fzf_selection)

            if [ -n "$selected_pane" ]; then
                # Focus the selected pane
                "$CURRENT_DIR/focus_session.sh" "$selected_pane"
            fi
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
