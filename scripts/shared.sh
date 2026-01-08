#!/usr/bin/env bash
# shared.sh - 共通ユーティリティ関数
# tmuxオプションの読み書きとプラットフォーム共通処理を提供
# バッチ処理用キャッシュ機能を含む（Bash 3.2互換）

# ==============================================================================
# バッチ処理用キャッシュ変数（一時ファイルパス）
# ==============================================================================
BATCH_PROCESS_TREE_FILE=""
BATCH_PANE_INFO_FILE=""
BATCH_LSOF_OUTPUT_FILE=""
BATCH_TERMINAL_CACHE_FILE=""
BATCH_INITIALIZED=0

# ==============================================================================
# バッチ処理初期化・クリーンアップ
# ==============================================================================

# PID -> pane_id マッピング用キャッシュファイル
BATCH_PID_PANE_MAP_FILE=""

# バッチ処理の初期化（全キャッシュを一度に作成）
# select_claude.sh の先頭で呼び出し
init_batch_cache() {
    if [ "$BATCH_INITIALIZED" = "1" ]; then
        return 0
    fi

    # 一時ファイルを作成
    BATCH_PROCESS_TREE_FILE=$(mktemp)
    BATCH_PANE_INFO_FILE=$(mktemp)
    BATCH_LSOF_OUTPUT_FILE=$(mktemp)
    BATCH_TERMINAL_CACHE_FILE=$(mktemp)
    BATCH_PID_PANE_MAP_FILE=$(mktemp)

    # プロセスツリーを取得（1回の ps 呼び出し）
    ps -eo pid,ppid,comm 2>/dev/null > "$BATCH_PROCESS_TREE_FILE"

    # tmuxペイン情報を取得（1回の tmux 呼び出し）
    # タブ区切りで出力（$'\t' を使用してリテラルタブを挿入）
    # window_name も追加取得
    tmux list-panes -a -F "#{pane_id}"$'\t'"#{pane_pid}"$'\t'"#{session_name}"$'\t'"#{window_index}"$'\t'"#{pane_index}"$'\t'"#{pane_tty}"$'\t'"#{window_name}" 2>/dev/null > "$BATCH_PANE_INFO_FILE"

    # PID -> pane_id マッピングを構築（一度のawk処理で全プロセスツリーを解析）
    _build_pid_pane_map

    # クリーンアップ用trapを設定
    trap cleanup_batch_cache EXIT

    BATCH_INITIALIZED=1
}

# PID -> pane_id マッピングを構築（内部関数）
# 全プロセスの祖先を辿り、pane_pidにマッチするものをマッピング
_build_pid_pane_map() {
    # awkで効率的にマッピングを構築
    # FNR==NR で最初のファイル（ペイン情報）を処理
    awk -F'\t' '
    # 最初のファイル（ペイン情報）を読み込み
    FNR == NR {
        pane_pids[$2] = $1  # pane_pid -> pane_id
        next
    }
    # 2番目のファイル（プロセスツリー）を読み込み
    {
        # 空白で区切られたps出力を処理
        gsub(/^[ \t]+/, "")
        split($0, fields, /[ \t]+/)
        pid = fields[1]
        parent = fields[2]
        if (pid != "PID" && pid != "") {
            ppid[pid] = parent
        }
    }
    END {
        # 各プロセスについて祖先を辿り、pane_pidにマッチしたらマッピング
        for (pid in ppid) {
            current = pid
            depth = 0
            while (depth < 20 && current != "" && current != "1" && current != "0") {
                if (current in pane_pids) {
                    print pid "\t" pane_pids[current]
                    break
                }
                current = ppid[current]
                depth++
            }
        }
    }
    ' "$BATCH_PANE_INFO_FILE" "$BATCH_PROCESS_TREE_FILE" > "$BATCH_PID_PANE_MAP_FILE"
}

# PIDからpane_idを直接取得（O(1)検索）
# $1: PID
# 戻り値: pane_id または空文字列
get_pane_id_for_pid_direct() {
    local pid="$1"
    if [ -n "$BATCH_PID_PANE_MAP_FILE" ] && [ -f "$BATCH_PID_PANE_MAP_FILE" ]; then
        awk -F'\t' -v pid="$pid" '$1 == pid { print $2; exit }' "$BATCH_PID_PANE_MAP_FILE"
    fi
}

# バッチキャッシュのクリーンアップ
cleanup_batch_cache() {
    [ -n "$BATCH_PROCESS_TREE_FILE" ] && rm -f "$BATCH_PROCESS_TREE_FILE"
    [ -n "$BATCH_PANE_INFO_FILE" ] && rm -f "$BATCH_PANE_INFO_FILE"
    [ -n "$BATCH_LSOF_OUTPUT_FILE" ] && rm -f "$BATCH_LSOF_OUTPUT_FILE"
    [ -n "$BATCH_TERMINAL_CACHE_FILE" ] && rm -f "$BATCH_TERMINAL_CACHE_FILE"
    [ -n "$BATCH_PID_PANE_MAP_FILE" ] && rm -f "$BATCH_PID_PANE_MAP_FILE"
    BATCH_INITIALIZED=0
}

# ==============================================================================
# バッチ版プロセス情報取得関数
# ==============================================================================

# キャッシュからPPIDを取得
# $1: PID
# 戻り値: PPID
get_ppid_cached() {
    local pid="$1"
    if [ -n "$BATCH_PROCESS_TREE_FILE" ] && [ -f "$BATCH_PROCESS_TREE_FILE" ]; then
        awk -v pid="$pid" '$1 == pid { print $2 }' "$BATCH_PROCESS_TREE_FILE"
    else
        ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' '
    fi
}

# キャッシュからプロセス名を取得
# $1: PID
# 戻り値: プロセス名（comm）
get_comm_cached() {
    local pid="$1"
    if [ -n "$BATCH_PROCESS_TREE_FILE" ] && [ -f "$BATCH_PROCESS_TREE_FILE" ]; then
        awk -v pid="$pid" '$1 == pid { print $3 }' "$BATCH_PROCESS_TREE_FILE"
    else
        ps -p "$pid" -o comm= 2>/dev/null
    fi
}

# ==============================================================================
# バッチ版tmuxペイン情報取得関数
# ==============================================================================

# キャッシュからペイン情報を取得（pane_id指定）
# $1: pane_id
# 戻り値: "pane_pid	session_name	window_index	pane_index	pane_tty"（タブ区切り）
get_pane_info_cached() {
    local pane_id="$1"
    if [ -n "$BATCH_PANE_INFO_FILE" ] && [ -f "$BATCH_PANE_INFO_FILE" ]; then
        awk -F'\t' -v pid="$pane_id" '$1 == pid { print $2"\t"$3"\t"$4"\t"$5"\t"$6 }' "$BATCH_PANE_INFO_FILE"
    fi
}

# キャッシュからセッション名を取得
# $1: pane_id
# 戻り値: session_name
get_session_name_cached() {
    local pane_id="$1"
    if [ -n "$BATCH_PANE_INFO_FILE" ] && [ -f "$BATCH_PANE_INFO_FILE" ]; then
        awk -F'\t' -v pid="$pane_id" '$1 == pid { print $3 }' "$BATCH_PANE_INFO_FILE"
    else
        tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null
    fi
}

# キャッシュからウィンドウインデックスを取得
# $1: pane_id
# 戻り値: window_index
get_window_index_cached() {
    local pane_id="$1"
    if [ -n "$BATCH_PANE_INFO_FILE" ] && [ -f "$BATCH_PANE_INFO_FILE" ]; then
        awk -F'\t' -v pid="$pane_id" '$1 == pid { print $4 }' "$BATCH_PANE_INFO_FILE"
    else
        tmux display-message -p -t "$pane_id" '#{window_index}' 2>/dev/null
    fi
}

# キャッシュからウィンドウ名を取得
# $1: pane_id
# 戻り値: window_name
get_window_name_cached() {
    local pane_id="$1"
    if [ -n "$BATCH_PANE_INFO_FILE" ] && [ -f "$BATCH_PANE_INFO_FILE" ]; then
        awk -F'\t' -v pid="$pane_id" '$1 == pid { print $7 }' "$BATCH_PANE_INFO_FILE"
    else
        tmux display-message -p -t "$pane_id" '#{window_name}' 2>/dev/null
    fi
}

# キャッシュから全ペインリストを取得
# 戻り値: "pane_pid pane_id" 行のリスト
get_all_panes_cached() {
    if [ -n "$BATCH_PANE_INFO_FILE" ] && [ -f "$BATCH_PANE_INFO_FILE" ]; then
        awk -F'\t' '{ print $2" "$1 }' "$BATCH_PANE_INFO_FILE"
    else
        tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null
    fi
}

# ==============================================================================
# バッチ版ターミナル検出キャッシュ
# ==============================================================================

# セッション単位でターミナルをキャッシュ
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

# ==============================================================================
# バッチ版lsof出力取得
# ==============================================================================

# 複数PIDのlsof結果をバッチ取得
# $1: カンマ区切りのPIDリスト（例: "123,456,789"）
init_lsof_cache() {
    local pid_list="$1"
    if [ -n "$BATCH_LSOF_OUTPUT_FILE" ] && [ -n "$pid_list" ]; then
        # lsof でFD "cwd" (current working directory) のみを取得
        # -d cwd: FD field を cwd に限定
        # -F pcn: PID, command, name を出力
        lsof -d cwd -p "$pid_list" -F pn 2>/dev/null > "$BATCH_LSOF_OUTPUT_FILE"
    fi
}

# キャッシュからPIDのcwdを取得
# $1: PID
# 戻り値: cwd パス
get_cwd_from_lsof_cache() {
    local pid="$1"
    if [ -n "$BATCH_LSOF_OUTPUT_FILE" ] && [ -f "$BATCH_LSOF_OUTPUT_FILE" ] && [ -s "$BATCH_LSOF_OUTPUT_FILE" ]; then
        # lsof -F pn 出力形式:
        # pPID
        # nPATH
        # pPID
        # nPATH
        awk -v pid="$pid" '
            /^p/ { current_pid = substr($0, 2) }
            /^n/ && current_pid == pid { print substr($0, 2); exit }
        ' "$BATCH_LSOF_OUTPUT_FILE"
    fi
}

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

# Status priority for sorting (working processes displayed first)
get_status_priority() {
    local status="$1"
    case "$status" in
        working) echo 0 ;;  # Working first
        idle) echo 1 ;;
        *) echo 2 ;;
    esac
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

# バッチ版: tmuxペインのウィンドウインデックス番号を取得（キャッシュ使用）
# $1: pane_id（例: %0, %1）
# 戻り値: "#1", "#2" 形式の文字列（ウィンドウ番号）
get_pane_index_cached() {
    local pane_id="$1"

    if [ -z "$pane_id" ] || [ "$pane_id" = "unknown" ]; then
        echo ""
        return
    fi

    # キャッシュからウィンドウインデックスを取得
    local window_index
    window_index=$(get_window_index_cached "$pane_id")

    if [ -n "$window_index" ]; then
        echo "#${window_index}"
    else
        echo ""
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

    if [[ "$(uname)" == "Darwin" ]]; then
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
                    local client_pid
                    client_pid=$(tmux list-clients -t "$session_name" -F '#{client_pid}' 2>/dev/null | head -1)
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
