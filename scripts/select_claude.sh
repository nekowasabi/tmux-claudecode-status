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

# 共有キャッシュを確認（claudecode_status.shが生成したもの）
# 新鮮なキャッシュがあればバッチ初期化をスキップして高速化
# 最適化版: 1回のファイル読み込みで全フィールドを取得
SHARED_CACHE_DATA=""
SHARED_CACHE_OPTIONS=""
SHARED_CACHE_TTY_STAT=""
if read_shared_cache_all; then
    SHARED_CACHE_DATA="$_SHARED_CACHE_PROCESSES"
    SHARED_CACHE_OPTIONS="$_SHARED_CACHE_OPTIONS"
    SHARED_CACHE_TTY_STAT="$_SHARED_CACHE_TTY_STAT"
fi

# 共有キャッシュがない場合のみバッチ処理キャッシュを初期化
if [ -z "$SHARED_CACHE_DATA" ]; then
    init_batch_cache
fi

# 高速判定モードを有効化（TTY mtimeベースの軽量判定）
FAST_MODE=1

# working判定の閾値（秒）- TTY mtimeがこの秒数以内ならworking
WORKING_THRESHOLD="${CLAUDECODE_WORKING_THRESHOLD:-5}"

# Note: WSL check removed for macOS optimization

# Generate and sort list of Claude Code processes for fzf
# Output format: pane_id|terminal_emoji|pane_index|project_name|status|display_line
# 超高速版: generate + sort を1つのawk呼び出しに統合
# 共有キャッシュがあればそれを使用し、なければバッチ情報を取得
generate_process_list() {
    # 共有キャッシュがあればそれを使用（init_batch_cacheをスキップ可能）
    local batch_info
    if [ -n "$SHARED_CACHE_DATA" ]; then
        batch_info="$SHARED_CACHE_DATA"
    else
        batch_info=$(get_all_claude_info_batch)
    fi

    [ -z "$batch_info" ] && return

    # ステータスアイコンとターミナル絵文字を取得（Phase 5: codex/claude アイコン追加）
    # 優先順位: 1.共有キャッシュ 2.バッチキャッシュファイル 3.tmux直接取得
    local working_dot idle_dot terminal_iterm terminal_wezterm terminal_ghostty terminal_windows terminal_vscode terminal_alacritty terminal_unknown
    local show_codex codex_icon claude_icon
    if [ -n "$SHARED_CACHE_OPTIONS" ]; then
        # 共有キャッシュからオプションを取得（最速）
        IFS=$'\t' read -r working_dot idle_dot terminal_iterm terminal_wezterm terminal_ghostty terminal_windows terminal_vscode terminal_alacritty terminal_unknown <<< "$SHARED_CACHE_OPTIONS"
        # Phase 5: codex options (fallback to tmux)
        show_codex=$(get_tmux_option "@claudecode_show_codex" "on")
        codex_icon=$(get_tmux_option "@claudecode_codex_icon" "🦾")
        claude_icon=$(get_tmux_option "@claudecode_claude_icon" "")
    elif [ -n "$BATCH_TMUX_OPTIONS_FILE" ] && [ -f "$BATCH_TMUX_OPTIONS_FILE" ]; then
        eval "$(awk '
        /@claudecode_working_dot/ {gsub(/@claudecode_working_dot /,""); print "working_dot='\''"$0"'\''"}
        /@claudecode_idle_dot/ {gsub(/@claudecode_idle_dot /,""); print "idle_dot='\''"$0"'\''"}
        /@claudecode_terminal_iterm/ {gsub(/@claudecode_terminal_iterm /,""); print "terminal_iterm='\''"$0"'\''"}
        /@claudecode_terminal_wezterm/ {gsub(/@claudecode_terminal_wezterm /,""); print "terminal_wezterm='\''"$0"'\''"}
        /@claudecode_terminal_ghostty/ {gsub(/@claudecode_terminal_ghostty /,""); print "terminal_ghostty='\''"$0"'\''"}
        /@claudecode_terminal_windows/ {gsub(/@claudecode_terminal_windows /,""); print "terminal_windows='\''"$0"'\''"}
        /@claudecode_terminal_vscode/ {gsub(/@claudecode_terminal_vscode /,""); print "terminal_vscode='\''"$0"'\''"}
        /@claudecode_terminal_alacritty/ {gsub(/@claudecode_terminal_alacritty /,""); print "terminal_alacritty='\''"$0"'\''"}
        /@claudecode_terminal_unknown/ {gsub(/@claudecode_terminal_unknown /,""); print "terminal_unknown='\''"$0"'\''"}
        /@claudecode_show_codex/ {gsub(/@claudecode_show_codex /,""); print "show_codex='\''"$0"'\''"}
        /@claudecode_codex_icon/ {gsub(/@claudecode_codex_icon /,""); print "codex_icon='\''"$0"'\''"}
        /@claudecode_claude_icon/ {gsub(/@claudecode_claude_icon /,""); print "claude_icon='\''"$0"'\''"}
        ' "$BATCH_TMUX_OPTIONS_FILE")"
    else
        # フォールバック: tmuxから直接取得
        working_dot=$(get_tmux_option "@claudecode_working_dot" "🤖")
        idle_dot=$(get_tmux_option "@claudecode_idle_dot" "🔔")
        terminal_iterm=$(get_tmux_option "@claudecode_terminal_iterm" "🍎")
        terminal_wezterm=$(get_tmux_option "@claudecode_terminal_wezterm" "⚡")
        terminal_ghostty=$(get_tmux_option "@claudecode_terminal_ghostty" "👻")
        terminal_windows=$(get_tmux_option "@claudecode_terminal_windows" "🪟")
        terminal_vscode=$(get_tmux_option "@claudecode_terminal_vscode" "📝")
        terminal_alacritty=$(get_tmux_option "@claudecode_terminal_alacritty" "🔲")
        terminal_unknown=$(get_tmux_option "@claudecode_terminal_unknown" "❓")
        # Phase 5: codex options
        show_codex=$(get_tmux_option "@claudecode_show_codex" "on")
        codex_icon=$(get_tmux_option "@claudecode_codex_icon" "🦾")
        claude_icon=$(get_tmux_option "@claudecode_claude_icon" "")
    fi
    : "${working_dot:=🤖}" "${idle_dot:=🔔}"
    : "${terminal_iterm:=🍎}" "${terminal_wezterm:=⚡}" "${terminal_ghostty:=👻}" "${terminal_windows:=🪟}" "${terminal_vscode:=📝}" "${terminal_alacritty:=🔲}" "${terminal_unknown:=❓}"
    : "${show_codex:=on}" "${codex_icon:=🦾}" "${claude_icon:=}"

    # 現在時刻とthreshold（EPOCHSECONDS使用で高速化）
    local current_time="${EPOCHSECONDS:-$(date +%s)}"
    local threshold="${WORKING_THRESHOLD:-5}"

    # TTY mtime を取得（優先順位: 1.共有キャッシュ 2.バッチキャッシュ 3.リアルタイム）
    local tty_stat_data=""
    if [ -n "$SHARED_CACHE_TTY_STAT" ]; then
        # 共有キャッシュから取得（セミコロン区切りを改行に変換）
        tty_stat_data=$(echo "$SHARED_CACHE_TTY_STAT" | tr ';' '\n')
    elif [ -n "$BATCH_TTY_STAT_FILE" ] && [ -f "$BATCH_TTY_STAT_FILE" ]; then
        tty_stat_data=$(cat "$BATCH_TTY_STAT_FILE")
    else
        # フォールバック: batch_infoからTTYパスを抽出してstatを実行
        local tty_paths
        tty_paths=$(echo "$batch_info" | awk -F'|' '{print $5}' | sort -u | grep -v '^$')
        if [ -n "$tty_paths" ]; then
            if [[ "$(get_os)" == "Darwin" ]]; then
                tty_stat_data=$(echo "$tty_paths" | xargs stat -f "%N %m" 2>/dev/null)
            else
                tty_stat_data=$(echo "$tty_paths" | xargs stat -c "%n %Y" 2>/dev/null)
            fi
        fi
    fi

    # TTY mtime + batch_info を1つのawkで処理し、ソート済みで出力
    {
        [ -n "$tty_stat_data" ] && echo "$tty_stat_data"
        echo "---SEPARATOR---"
        echo "$batch_info"
    } | awk -F'|' \
        -v working_icon="$working_dot" \
        -v idle_icon="$idle_dot" \
        -v emoji_iterm="$terminal_iterm" \
        -v emoji_wezterm="$terminal_wezterm" \
        -v emoji_ghostty="$terminal_ghostty" \
        -v emoji_windows="$terminal_windows" \
        -v emoji_vscode="$terminal_vscode" \
        -v emoji_alacritty="$terminal_alacritty" \
        -v emoji_unknown="$terminal_unknown" \
        -v current_time="$current_time" \
        -v threshold="$threshold" \
        -v show_codex="$show_codex" \
        -v codex_icon="$codex_icon" \
        -v claude_icon="$claude_icon" \
    '
    BEGIN { in_data = 0; count = 0 }
    /^---SEPARATOR---$/ { in_data = 1; next }
    !in_data {
        split($0, parts, " ")
        tty_mtime[parts[1]] = parts[2]
        next
    }
    {
        pane_id = $2
        if (pane_id == "" || pane_id in seen) next
        seen[pane_id] = 1

        session_name = $3; window_index = $4; tty_path = $5
        terminal_name = $6; cwd = $7; proc_type = $8

        # Phase 5: Filter codex if show_codex is off
        if (proc_type == "codex" && show_codex != "on") next

        # Terminal emoji + priority
        if (terminal_name == "iTerm2" || terminal_name == "Terminal") {
            emoji = emoji_iterm; tpri = 1
        } else if (terminal_name == "WezTerm") {
            emoji = emoji_wezterm; tpri = 2
        } else if (terminal_name == "Ghostty") {
            emoji = emoji_ghostty; tpri = 3
        } else if (terminal_name == "WindowsTerminal") {
            emoji = emoji_windows; tpri = 4
        } else if (terminal_name == "VSCode") {
            emoji = emoji_vscode; tpri = 5
        } else if (terminal_name == "Alacritty") {
            emoji = emoji_alacritty; tpri = 6
        } else {
            emoji = emoji_unknown; tpri = 99
        }

        # Project name
        n = split(cwd, p, "/")
        proj = p[n]
        if (proj == "" || proj == "/") proj = "claude"
        if (length(proj) > 18) proj = substr(proj, 1, 15) "..."
        if (proj in pcnt) { pcnt[proj]++; proj = proj "#" pcnt[proj] }
        else pcnt[proj] = 1

        # Status (TTY mtime based)
        status = "idle"; spri = 1
        if (tty_path in tty_mtime && (current_time - tty_mtime[tty_path]) < threshold) {
            status = "working"; spri = 0
        }
        icon = (status == "working") ? working_icon : idle_icon

        # Phase 5: Process type icon
        type_icon = ""
        if (proc_type == "codex" && codex_icon != "") {
            type_icon = codex_icon " "
        } else if (proc_type == "claude" && claude_icon != "") {
            type_icon = claude_icon " "
        }

        # Display line
        pidx = "#" window_index
        line = icon type_icon emoji " " pidx " " proj
        if (session_name != "") line = line " [" session_name "]"

        # Store for sorting (add proc_type to data)
        data[count] = pane_id "|" emoji "|" pidx "|" proj "|" status "|" proc_type "|" line
        sort_key[count] = sprintf("%d:%d:%03d", spri, tpri, window_index + 0)
        count++
    }
    END {
        # Simple insertion sort (typically <10 items)
        for (i = 1; i < count; i++) {
            key = sort_key[i]; val = data[i]
            j = i - 1
            while (j >= 0 && sort_key[j] > key) {
                sort_key[j+1] = sort_key[j]
                data[j+1] = data[j]
                j--
            }
            sort_key[j+1] = key
            data[j+1] = val
        }
        for (i = 0; i < count; i++) print data[i]
    }
    '
}

# sort_process_list is now integrated into generate_process_list
sort_process_list() { cat; }

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
    # --no-clear prevents screen flicker on startup
    fzf_opts=$(get_tmux_option_cached "@claudecode_fzf_opts" "--height=100% --reverse --no-clear --prompt=Select\ Claude:\ ")

    # Get preview setting
    local preview_enabled
    preview_enabled=$(get_tmux_option_cached "@claudecode_fzf_preview" "on")

    # Build preview option if enabled
    local preview_opt=""
    if [ "$preview_enabled" = "on" ]; then
        local preview_script="$CURRENT_DIR/preview_pane.sh"
        if [ -x "$preview_script" ]; then
            # Build CLAUDECODE_PANE_DATA for preview
            local pane_data=""
            for i in "${!display_lines[@]}"; do
                if [ -n "$pane_data" ]; then
                    pane_data+=$'\n'
                fi
                pane_data+="${display_lines[$i]}"$'\t'"${pane_ids[$i]}"
            done
            export CLAUDECODE_PANE_DATA="$pane_data"
            local preview_position
            preview_position=$(get_tmux_option "@claudecode_fzf_preview_position" "down")
            local preview_size
            preview_size=$(get_tmux_option "@claudecode_fzf_preview_size" "50%")
            preview_opt="--preview='$preview_script {}' --preview-window=${preview_position}:${preview_size}:wrap"
        fi
    fi

    # Run fzf
    local selected
    # Use eval to properly handle escaped spaces in fzf options
    selected=$(echo "$fzf_input" | eval "fzf $fzf_opts $preview_opt")

    # Cleanup
    unset CLAUDECODE_PANE_DATA

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
