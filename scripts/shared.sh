#!/usr/bin/env bash
# shared.sh - 共通ユーティリティ関数
# tmuxオプションの読み書きとプラットフォーム共通処理を提供

# tmuxオプションの値を取得
# $1: オプション名
# $2: デフォルト値（オプション）
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value="$(tmux show-option -gqv "$option" 2>/dev/null)"
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# tmuxオプションを設定
# $1: オプション名
# $2: 値
set_tmux_option() {
    tmux set-option -gq "$1" "$2"
}

# クロスプラットフォーム対応のファイル更新時刻取得
# $1: ファイルパス
# 戻り値: Unixタイムスタンプ（秒）
get_file_mtime() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        stat -f %m "$file" 2>/dev/null
    else
        # Linux
        stat -c %Y "$file" 2>/dev/null
    fi
}

# 現在のUnixタイムスタンプを取得
get_current_timestamp() {
    date +%s
}

# プロセス名からターミナルアプリ名を判定するヘルパー関数
# $1: プロセス名（フルパス可）
# 戻り値: ターミナル名（iTerm2, WezTerm, Ghostty, Terminal）または空文字
_detect_terminal_from_pname() {
    local pname="$1"
    # basenameを取得（パスが含まれている場合）
    local basename_pname
    basename_pname=$(basename "$pname" 2>/dev/null)

    case "$basename_pname" in
        iTerm2|iTerm.app|iTerm)
            echo "iTerm2"
            ;;
        wezterm|wezterm-gui|WezTerm)
            echo "WezTerm"
            ;;
        ghostty|Ghostty)
            echo "Ghostty"
            ;;
        Terminal|Apple_Terminal)
            echo "Terminal"
            ;;
        *)
            # フルパスでも確認
            case "$pname" in
                *iTerm*) echo "iTerm2" ;;
                *[Ww]ez[Tt]erm*) echo "WezTerm" ;;
                *[Gg]hostty*) echo "Ghostty" ;;
                *Terminal.app*) echo "Terminal" ;;
                *) echo "" ;;
            esac
            ;;
    esac
}

# ターミナルアプリ名を絵文字で取得
# $1: PID（Claude Codeプロセス）
# $2: pane_id（オプション、tmuxペインID）
# 戻り値: 絵文字（🍎=iTerm2, ⚡=WezTerm, 👻=Ghostty, 🪟=Windows Terminal, ❓=不明）
get_terminal_emoji() {
    local pid="$1"
    local pane_id="${2:-}"
    local terminal_name=""

    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: claudeプロセスのTTYからtmuxセッションを特定し、
        # そのセッションにアタッチしているクライアントの親プロセスからターミナルを検出

        # 方法1: pane_idが指定されている場合、そこからセッションを特定
        if [ -n "$pane_id" ] && [ "$pane_id" != "unknown" ]; then
            local session_name
            session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)
            if [ -n "$session_name" ]; then
                # セッションにアタッチしているクライアントを取得
                local client_pid
                client_pid=$(tmux list-clients -t "$session_name" -F '#{client_pid}' 2>/dev/null | head -1)
                if [ -n "$client_pid" ]; then
                    local current_pid="$client_pid"
                    local max_depth=10
                    local depth=0

                    while [ "$depth" -lt "$max_depth" ]; do
                        local pname
                        pname=$(ps -p "$current_pid" -o comm= 2>/dev/null)

                        terminal_name=$(_detect_terminal_from_pname "$pname")
                        if [ -n "$terminal_name" ]; then
                            break
                        fi

                        # 親PIDを取得
                        local ppid
                        ppid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')

                        if [ -z "$ppid" ] || [ "$ppid" = "1" ] || [ "$ppid" = "0" ]; then
                            break
                        fi

                        current_pid="$ppid"
                        ((depth++))
                    done
                fi
            fi
        fi

        # 方法2: pidのTTYからペインを特定し、セッション→クライアントを辿る
        if [ -z "$terminal_name" ]; then
            local tty_info
            tty_info=$(ps -p "$pid" -o tty= 2>/dev/null | tr -d ' ')
            if [ -n "$tty_info" ] && [ "$tty_info" != "??" ]; then
                local tty_path="/dev/$tty_info"
                # tmuxのペイン一覧からTTYでマッチングしてセッションを特定
                local session_name
                session_name=$(tmux list-panes -a -F '#{pane_tty} #{session_name}' 2>/dev/null | grep "^$tty_path " | head -1 | awk '{print $2}')
                if [ -n "$session_name" ]; then
                    local client_pid
                    client_pid=$(tmux list-clients -t "$session_name" -F '#{client_pid}' 2>/dev/null | head -1)
                    if [ -n "$client_pid" ]; then
                        local current_pid="$client_pid"
                        local max_depth=10
                        local depth=0

                        while [ "$depth" -lt "$max_depth" ]; do
                            local pname
                            pname=$(ps -p "$current_pid" -o comm= 2>/dev/null)

                            terminal_name=$(_detect_terminal_from_pname "$pname")
                            if [ -n "$terminal_name" ]; then
                                break
                            fi

                            # 親PIDを取得
                            local ppid
                            ppid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')

                            if [ -z "$ppid" ] || [ "$ppid" = "1" ] || [ "$ppid" = "0" ]; then
                                break
                            fi

                            current_pid="$ppid"
                            ((depth++))
                        done
                    fi
                fi
            fi
        fi

        # 方法3: 元のPIDから直接親プロセスツリーを辿る（tmux環境外の場合のフォールバック）
        if [ -z "$terminal_name" ]; then
            local current_pid="$pid"
            local max_depth=20
            local depth=0

            while [ "$depth" -lt "$max_depth" ]; do
                local pname
                pname=$(ps -p "$current_pid" -o comm= 2>/dev/null)

                terminal_name=$(_detect_terminal_from_pname "$pname")
                if [ -n "$terminal_name" ]; then
                    break
                fi

                # 親PIDを取得
                local ppid
                ppid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')

                if [ -z "$ppid" ] || [ "$ppid" = "1" ] || [ "$ppid" = "0" ]; then
                    break
                fi

                current_pid="$ppid"
                ((depth++))
            done
        fi
    else
        # Linux/WSL: 環境変数やプロセス名から判定
        # TERM_PROGRAMが設定されていれば使用
        if [ -n "$TERM_PROGRAM" ]; then
            case "$TERM_PROGRAM" in
                iTerm.app) terminal_name="iTerm2" ;;
                WezTerm) terminal_name="WezTerm" ;;
                ghostty) terminal_name="Ghostty" ;;
            esac
        fi

        # WSL判定
        if [ -z "$terminal_name" ]; then
            if grep -qi microsoft /proc/version 2>/dev/null; then
                # WSL環境 - Windows Terminal の可能性が高い
                if [ -n "$WT_SESSION" ]; then
                    terminal_name="WindowsTerminal"
                fi
            fi
        fi
    fi

    # 絵文字に変換（tmuxオプションから取得、設定がなければデフォルト値を使用）
    case "$terminal_name" in
        iTerm2|Terminal)
            get_tmux_option "@claudecode_terminal_iterm" "🍎"
            ;;
        WezTerm)
            get_tmux_option "@claudecode_terminal_wezterm" "⚡"
            ;;
        Ghostty)
            get_tmux_option "@claudecode_terminal_ghostty" "👻"
            ;;
        WindowsTerminal)
            get_tmux_option "@claudecode_terminal_windows" "🪟"
            ;;
        *)
            get_tmux_option "@claudecode_terminal_unknown" "❓"
            ;;
    esac
}

# tmuxペインのウィンドウインデックス番号を取得
# $1: pane_id（例: %0, %1）
# 戻り値: "#1", "#2" 形式の文字列（ウィンドウ番号）
# 注: 各ウィンドウに1ペインの場合、pane_indexは常に0になるため
#     より意味のあるwindow_indexを返す
get_pane_index() {
    local pane_id="$1"

    if [ -z "$pane_id" ] || [ "$pane_id" = "unknown" ]; then
        echo ""
        return
    fi

    # tmuxからウィンドウインデックスを取得
    local window_index
    window_index=$(tmux display-message -p -t "$pane_id" '#{window_index}' 2>/dev/null)

    if [ -n "$window_index" ]; then
        echo "#${window_index}"
    else
        echo ""
    fi
}
