#!/usr/bin/env bash
# terminal.sh - Terminal detection, emoji mapping, WSL support
# Source guard: prevent double-sourcing
if [ -n "${__LIB_TERMINAL_LOADED:-}" ]; then return 0; fi
__LIB_TERMINAL_LOADED=1

# Dependencies
source "${BASH_SOURCE[0]%/*}/platform.sh"
source "${BASH_SOURCE[0]%/*}/tmux_options.sh"

# ==============================================================================
# Terminal Detection and Utilities
# ==============================================================================

# Terminal emoji priority for sorting
# Priority: apple(iTerm)=1, lightning(WezTerm)=2, ghost(Ghostty)=3, window(Windows Terminal)=4, question(other)=5
get_terminal_priority() {
    local emoji="$1"
    case "$emoji" in
        *🍎*) echo 1 ;;
        *⚡*) echo 2 ;;
        *👻*) echo 3 ;;
        *🪟*) echo 4 ;;
        *)  echo 5 ;;
    esac
}

# ==============================================================================
# WSL環境用ターミナル検出関数
# ==============================================================================

# tmuxクライアントの環境変数からターミナルを検出（WSL専用）
# $1: client_pid（tmuxクライアントのPID）
# 戻り値: ターミナル名（WindowsTerminal, WezTerm, VSCode, Alacritty, Unknown）
detect_terminal_from_client_env() {
    local client_pid="$1"
    local env_file="/proc/$client_pid/environ"

    if [ ! -r "$env_file" ]; then
        echo "Unknown"
        return
    fi

    local env_content
    env_content=$(cat "$env_file" 2>/dev/null | tr '\0' '\n')

    # Windows Terminal
    if echo "$env_content" | grep -q "^WT_SESSION="; then
        echo "WindowsTerminal"
        return
    fi

    # WezTerm
    if echo "$env_content" | grep -q "^TERM_PROGRAM=WezTerm"; then
        echo "WezTerm"
        return
    fi

    # VS Code
    if echo "$env_content" | grep -q "^VSCODE_IPC_HOOK_CLI="; then
        echo "VSCode"
        return
    fi

    # Alacritty
    if echo "$env_content" | grep -q "^ALACRITTY_"; then
        echo "Alacritty"
        return
    fi

    echo "Unknown"
}

# tmuxセッションに接続しているクライアントからターミナルを検出（WSL専用）
# $1: session_name（tmuxセッション名）
# 戻り値: ターミナル名（WindowsTerminal, WezTerm, VSCode, Alacritty）または空文字
get_terminal_for_session_wsl() {
    local session_name="$1"

    # WSL環境でない場合は何も返さない
    if ! grep -qi microsoft /proc/version 2>/dev/null; then
        return
    fi

    local client_pid
    client_pid=$(tmux list-clients -t "$session_name" -F '#{client_pid}' 2>/dev/null | head -1)

    if [ -z "$client_pid" ]; then
        return
    fi

    local terminal
    terminal=$(detect_terminal_from_client_env "$client_pid")

    if [ "$terminal" != "Unknown" ]; then
        echo "$terminal"
    fi
}

# ==============================================================================
# ターミナル検出ヘルパー関数
# ==============================================================================

# プロセス名からターミナルアプリ名を判定するヘルパー関数
# $1: プロセス名（フルパス可）
# 戻り値: ターミナル名（iTerm2, WezTerm, Ghostty, Terminal）または空文字
_detect_terminal_from_pname() {
    local pname="$1"
    # basenameを取得（パスが含まれている場合）
    local basename_pname="${pname##*/}"

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

    if [[ "$(get_os)" == "Darwin" ]]; then
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

        # WSL判定 - tmuxクライアントの環境変数から検出
        if [ -z "$terminal_name" ]; then
            if grep -qi microsoft /proc/version 2>/dev/null; then
                # WSL環境: pane_idからセッションを特定してターミナルを検出
                if [ -n "$pane_id" ] && [ "$pane_id" != "unknown" ]; then
                    local session_name
                    session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)
                    if [ -n "$session_name" ]; then
                        terminal_name=$(get_terminal_for_session_wsl "$session_name")
                    fi
                fi

                # フォールバック: 現在のプロセスの環境変数をチェック
                if [ -z "$terminal_name" ]; then
                    if [ -n "${WT_SESSION:-}" ]; then
                        terminal_name="WindowsTerminal"
                    elif [ -n "${VSCODE_IPC_HOOK_CLI:-}" ]; then
                        terminal_name="VSCode"
                    elif [ -n "${ALACRITTY_LOG:-}" ] || [ -n "${ALACRITTY_SOCKET:-}" ]; then
                        terminal_name="Alacritty"
                    fi
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
        VSCode)
            get_tmux_option "@claudecode_terminal_vscode" "📝"
            ;;
        Alacritty)
            get_tmux_option "@claudecode_terminal_alacritty" "🔲"
            ;;
        *)
            get_tmux_option "@claudecode_terminal_unknown" "❓"
            ;;
    esac
}

# セッション単位でターミナルをキャッシュ（バッチ処理用）
# $1: session_name
# $2: terminal_name（設定する場合）
# 戻り値: キャッシュされたターミナル名
get_terminal_for_session_cached() {
    local session="$1"
    local set_value="${2:-}"

    if [ -z "$BATCH_TERMINAL_CACHE_FILE" ] || [ ! -f "$BATCH_TERMINAL_CACHE_FILE" ]; then
        echo ""
        return
    fi

    if [ -n "$set_value" ]; then
        # 値を設定
        printf '%s\t%s\n' "$session" "$set_value" >> "$BATCH_TERMINAL_CACHE_FILE"
        echo "$set_value"
    else
        # 値を取得
        awk -F'\t' -v s="$session" '$1 == s { print $2; exit }' "$BATCH_TERMINAL_CACHE_FILE"
    fi
}

# バッチ版: ターミナルアプリ名を絵文字で取得（キャッシュ使用）
# セッション単位でキャッシュし、親プロセス走査を最小化
# $1: PID（Claude Codeプロセス）
# $2: pane_id（オプション、tmuxペインID）
# 戻り値: 絵文字（🍎=iTerm2, ⚡=WezTerm, 👻=Ghostty, 🪟=Windows Terminal, ❓=不明）
get_terminal_emoji_cached() {
    local pid="$1"
    local pane_id="${2:-}"
    local terminal_name=""

    # キャッシュが初期化されていない場合は元の関数を使用
    if [ "$BATCH_INITIALIZED" != "1" ]; then
        get_terminal_emoji "$pid" "$pane_id"
        return
    fi

    if [[ "$(get_os)" == "Darwin" ]]; then
        # macOS: セッション単位でキャッシュを確認

        # 方法1: pane_idが指定されている場合、そこからセッションを特定
        if [ -n "$pane_id" ] && [ "$pane_id" != "unknown" ]; then
            local session_name
            session_name=$(get_session_name_cached "$pane_id")

            if [ -n "$session_name" ]; then
                # キャッシュを確認
                terminal_name=$(get_terminal_for_session_cached "$session_name")

                if [ -z "$terminal_name" ]; then
                    # キャッシュになければ検出してキャッシュ
                    # バッチキャッシュから取得（tmux list-clients 呼び出し不要）
                    local client_pid
                    client_pid=$(get_client_pid_for_session_cached "$session_name")
                    if [ -n "$client_pid" ]; then
                        local current_pid="$client_pid"
                        local max_depth=10
                        local depth=0

                        while [ "$depth" -lt "$max_depth" ]; do
                            local pname
                            pname=$(get_comm_cached "$current_pid")

                            terminal_name=$(_detect_terminal_from_pname "$pname")
                            if [ -n "$terminal_name" ]; then
                                # キャッシュに保存
                                get_terminal_for_session_cached "$session_name" "$terminal_name" >/dev/null
                                break
                            fi

                            # 親PIDを取得（キャッシュ版）
                            local ppid
                            ppid=$(get_ppid_cached "$current_pid")

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

        # キャッシュで見つからなければ元の関数にフォールバック
        if [ -z "$terminal_name" ]; then
            get_terminal_emoji "$pid" "$pane_id"
            return
        fi
    else
        # Linux/WSL: 元の関数を使用
        get_terminal_emoji "$pid" "$pane_id"
        return
    fi

    # 絵文字に変換（キャッシュ版tmuxオプションから取得、設定がなければデフォルト値を使用）
    case "$terminal_name" in
        iTerm2|Terminal)
            get_tmux_option_cached "@claudecode_terminal_iterm" "🍎"
            ;;
        WezTerm)
            get_tmux_option_cached "@claudecode_terminal_wezterm" "⚡"
            ;;
        Ghostty)
            get_tmux_option_cached "@claudecode_terminal_ghostty" "👻"
            ;;
        WindowsTerminal)
            get_tmux_option_cached "@claudecode_terminal_windows" "🪟"
            ;;
        VSCode)
            get_tmux_option_cached "@claudecode_terminal_vscode" "📝"
            ;;
        Alacritty)
            get_tmux_option_cached "@claudecode_terminal_alacritty" "🔲"
            ;;
        *)
            get_tmux_option_cached "@claudecode_terminal_unknown" "❓"
            ;;
    esac
}

# ターミナル検出を事前に実行してキャッシュに格納（内部関数）
# awkで一括処理して高速化
_prebuild_terminal_cache() {
    # クライアントキャッシュとプロセスツリーから一括でターミナルを検出
    if [ -z "$BATCH_CLIENTS_CACHE_FILE" ] || [ ! -f "$BATCH_CLIENTS_CACHE_FILE" ]; then
        return
    fi
    if [ -z "$BATCH_PROCESS_TREE_FILE" ] || [ ! -f "$BATCH_PROCESS_TREE_FILE" ]; then
        return
    fi

    # WSL環境判定
    local is_wsl=0
    if grep -qi microsoft /proc/version 2>/dev/null; then
        is_wsl=1
    fi

    if [ "$is_wsl" = "1" ]; then
        # ===== WSL環境用のロジック =====
        # クライアント情報から環境変数を読み込んでターミナル判定
        while IFS=$'\t' read -r session client_tty client_pid; do
            [ -z "$session" ] || [ -z "$client_pid" ] && continue

            local terminal
            terminal=$(detect_terminal_from_client_env "$client_pid")
            if [ -n "$terminal" ] && [ "$terminal" != "Unknown" ]; then
                printf '%s\t%s\n' "$session" "$terminal"
            fi
        done < "$BATCH_CLIENTS_CACHE_FILE" >> "$BATCH_TERMINAL_CACHE_FILE"
    else
        # ===== macOS/Linux環境用のロジック（既存） =====
        # awkで一括処理: プロセスツリーとクライアント情報を結合してターミナルを検出
        awk -F'\t' '
        # 最初のファイル（プロセスツリー）を読み込み
        FNR == NR {
            gsub(/^[ \t]+/, "")
            split($0, fields, /[ \t]+/)
            pid = fields[1]
            parent = fields[2]
            comm = fields[3]
            if (pid != "PID" && pid != "") {
                ppid[pid] = parent
                pcomm[pid] = comm
            }
            next
        }
        # 2番目のファイル（クライアント情報）を処理
        {
            session = $1
            client_pid = $3
            if (session == "" || client_pid == "") next

            # 親プロセスを辿ってターミナルを検出
            current = client_pid
            for (depth = 0; depth < 10; depth++) {
                if (current == "" || current == "1" || current == "0") break
                comm = pcomm[current]
                # ターミナル名を検出
                if (comm ~ /iTerm|Terminal/) {
                    print session "\tiTerm2"
                    break
                } else if (comm ~ /[Ww]ez[Tt]erm/) {
                    print session "\tWezTerm"
                    break
                } else if (comm ~ /[Gg]hostty/) {
                    print session "\tGhostty"
                    break
                }
                current = ppid[current]
            }
        }
        ' "$BATCH_PROCESS_TREE_FILE" "$BATCH_CLIENTS_CACHE_FILE" >> "$BATCH_TERMINAL_CACHE_FILE"
    fi
}
