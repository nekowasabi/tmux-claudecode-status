#!/usr/bin/env bash
# session_tracker.sh - Claude Codeセッション追跡
# 各セッションのworking/idle状態を判定

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"

# working判定の閾値（秒）
# この秒数以内にファイルが更新されていればworking
# tmux-monitorを参考に30秒に設定（Claude Codeは応答生成中でも
# .jsonlファイルの更新が不定期のため、短い閾値では誤判定する）
WORKING_THRESHOLD="${CLAUDECODE_WORKING_THRESHOLD:-30}"

# CPU使用率の閾値（%）- この値以上ならworking
# Claude Codeはバックグラウンドでも一定のCPU使用率があるため、高めに設定
CPU_THRESHOLD="${CLAUDECODE_CPU_THRESHOLD:-20}"

# ペインコンテンツハッシュのキャッシュディレクトリ
CACHE_DIR="/tmp/claudecode_status_cache"

# Claude Codeプロセスの PID 一覧を取得
# 戻り値: スペース区切りのPID一覧
get_claude_pids() {
    # 後方互換性のため get_ai_pids を使用
    get_ai_pids "claude"
}

# Phase 2: AI プロセス（claude + codex）の PID 一覧を取得
# $1: フィルタ（オプション: "claude" or "codex"）
# 戻り値: スペース区切りの PID 一覧
get_ai_pids() {
    local filter="${1:-}"
    local pids=""

    if [ "$BATCH_INITIALIZED" = "1" ] && [ -f "$BATCH_PROCESS_TREE_FILE" ]; then
        # バッチキャッシュから取得
        if [ -n "$filter" ]; then
            pids=$(awk -v f="$filter" '$3 == f {print $1}' "$BATCH_PROCESS_TREE_FILE" | tr '\n' ' ')
        else
            pids=$(awk '$3 == "claude" || $3 == "codex" {print $1}' "$BATCH_PROCESS_TREE_FILE" | tr '\n' ' ')
        fi
    else
        # 通常モード: ps コマンドで取得
        if [ -n "$filter" ]; then
            pids=$(ps -eo pid,comm 2>/dev/null | awk -v f="$filter" '$2 == f {print $1}' | tr '\n' ' ')
        else
            pids=$(ps -eo pid,comm 2>/dev/null | awk '$2 == "claude" || $2 == "codex" {print $1}' | tr '\n' ' ')
        fi
    fi

    echo "$pids"
}

# PIDからプロセスタイプを取得
# $1: PID
# 戻り値: "claude" または "codex"
get_process_type() {
    local pid="$1"
    local comm args
    read -r comm args < <(ps -p "$pid" -o comm=,args= 2>/dev/null)

    # Claude Code プロセス（claude と claude-raw の両方）
    if [ "$comm" = "claude" ] || [ "$comm" = "claude-raw" ]; then
        echo "claude"
    # Codex 検出: commに依存せず args から /bin/codex を検索
    # Note: ps -o comm= は 'MainThread' を返すため
    elif [[ "$args" =~ /bin/codex([[:space:]]|$) ]]; then
        echo "codex"
    fi
}

# キャッシュ版
get_process_type_cached() {
    local pid="$1"
    if [ "$BATCH_INITIALIZED" = "1" ] && [ -f "$BATCH_PROCESS_TREE_FILE" ]; then
        awk -v pid="$pid" '$1 == pid { print $3 }' "$BATCH_PROCESS_TREE_FILE"
    else
        get_process_type "$pid"
    fi
}

# PIDからtmuxペイン情報を取得
# $1: PID
# 戻り値: "pane_id:pane_name" または空文字列（見つからない場合）
get_pane_info_for_pid() {
    local target_pid="$1"

    # tmuxが起動していない場合は空を返す
    if ! tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null >/dev/null; then
        echo ""
        return
    fi

    # 各tmuxペインを走査してPIDを確認
    while IFS=' ' read -r pane_pid pane_id; do
        # ペインのプロセスツリーをチェック
        # 対象PIDがペインのPIDの子孫かを確認
        if is_descendant_of "$target_pid" "$pane_pid"; then
            # ペイン名を取得（window名を使用）
            local pane_name
            pane_name=$(tmux display-message -p -t "$pane_id" '#{window_name}' 2>/dev/null)
            if [ -n "$pane_name" ]; then
                # pane_id:pane_name 形式で返す
                echo "${pane_id}:${pane_name}"
                return
            fi
        fi
    done < <(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null)

    # 見つからない場合は空
    echo ""
}

# バッチ版: PIDからtmuxペイン情報を取得（キャッシュ使用）
# $1: PID
# 戻り値: "pane_id:pane_name" または空文字列（見つからない場合）
get_pane_info_for_pid_cached() {
    local target_pid="$1"

    # キャッシュが初期化されていない場合は元の関数を使用
    if [ "$BATCH_INITIALIZED" != "1" ]; then
        get_pane_info_for_pid "$target_pid"
        return
    fi

    # 直接マッピングからpane_idを取得（O(1)相当）
    local pane_id
    pane_id=$(get_pane_id_for_pid_direct "$target_pid")

    if [ -n "$pane_id" ]; then
        # ペイン名をキャッシュから取得
        local pane_name
        pane_name=$(get_window_name_cached "$pane_id")
        if [ -n "$pane_name" ]; then
            echo "${pane_id}:${pane_name}"
            return
        fi
    fi

    echo ""
}

# 後方互換性のためのラッパー
get_pane_name_for_pid() {
    local info
    info=$(get_pane_info_for_pid "$1")
    if [ -n "$info" ]; then
        echo "${info#*:}"
    else
        echo ""
    fi
}

# PIDからプロジェクト名（作業ディレクトリ名）を取得
# $1: PID
# $2: 最大文字数（デフォルト: 18）
# 戻り値: プロジェクト名（長い場合は省略）
get_project_name_for_pid() {
    local pid="$1"
    local max_length="${2:-18}"
    local project_name=""
    local cwd=""

    # OS判定でcwd取得方法を分岐
    if [[ "$(get_os)" == "Darwin" ]]; then
        # macOS: lsofでcwdを取得
        cwd=$(lsof -p "$pid" 2>/dev/null | awk '$4 == "cwd" {print $9}')
    else
        # Linux: /proc/PID/cwdから取得
        local cwd_link="/proc/$pid/cwd"
        if [ -L "$cwd_link" ]; then
            cwd=$(readlink "$cwd_link" 2>/dev/null)
        fi
        # フォールバック: pwdxコマンド
        if [ -z "$cwd" ]; then
            cwd=$(pwdx "$pid" 2>/dev/null | cut -d: -f2 | tr -d ' ')
        fi
    fi

    # cwdからプロジェクト名を抽出（basenameの代わりにパラメータ展開）
    if [ -n "$cwd" ] && [ "$cwd" != "/" ]; then
        project_name="${cwd##*/}"
    fi

    # 取得できない場合はデフォルト名
    if [ -z "$project_name" ] || [ "$project_name" = "/" ]; then
        project_name="claude"
    fi

    # 長すぎる場合は省略
    if [ "${#project_name}" -gt "$max_length" ]; then
        project_name="${project_name:0:$((max_length - 3))}..."
    fi

    echo "$project_name"
}

# バッチ版: PIDからプロジェクト名（作業ディレクトリ名）を取得（キャッシュ使用）
# $1: PID
# $2: 最大文字数（デフォルト: 18）
# 戻り値: プロジェクト名（長い場合は省略）
get_project_name_for_pid_cached() {
    local pid="$1"
    local max_length="${2:-18}"
    local project_name=""
    local cwd=""

    # キャッシュが初期化されていない場合は元の関数を使用
    if [ "$BATCH_INITIALIZED" != "1" ]; then
        get_project_name_for_pid "$pid" "$max_length"
        return
    fi

    # OS判定でcwd取得方法を分岐
    if [[ "$(get_os)" == "Darwin" ]]; then
        # macOS: キャッシュからcwdを取得
        cwd=$(get_cwd_from_lsof_cache "$pid")
        # キャッシュにない場合はフォールバック
        if [ -z "$cwd" ]; then
            cwd=$(lsof -d cwd -p "$pid" -F n 2>/dev/null | awk '/^n/ {print substr($0, 2); exit}')
        fi
    else
        # Linux: /proc/PID/cwdから取得
        local cwd_link="/proc/$pid/cwd"
        if [ -L "$cwd_link" ]; then
            cwd=$(readlink "$cwd_link" 2>/dev/null)
        fi
        # フォールバック: pwdxコマンド
        if [ -z "$cwd" ]; then
            cwd=$(pwdx "$pid" 2>/dev/null | cut -d: -f2 | tr -d ' ')
        fi
    fi

    # cwdからプロジェクト名を抽出（basenameの代わりにパラメータ展開）
    if [ -n "$cwd" ] && [ "$cwd" != "/" ]; then
        project_name="${cwd##*/}"
    fi

    # 取得できない場合はデフォルト名
    if [ -z "$project_name" ] || [ "$project_name" = "/" ]; then
        project_name="claude"
    fi

    # 長すぎる場合は省略
    if [ "${#project_name}" -gt "$max_length" ]; then
        project_name="${project_name:0:$((max_length - 3))}..."
    fi

    echo "$project_name"
}

# プロセスが別のプロセスの子孫かを確認
# $1: チェック対象PID
# $2: 祖先候補PID
# 戻り値: 0 (子孫), 1 (非子孫)
is_descendant_of() {
    local check_pid="$1"
    local ancestor_pid="$2"
    local current_pid="$check_pid"

    # 同一の場合はtrue
    if [ "$current_pid" = "$ancestor_pid" ]; then
        return 0
    fi

    # 親プロセスを辿る（最大20階層）
    local max_depth=20
    local depth=0
    while [ "$depth" -lt "$max_depth" ]; do
        local ppid
        ppid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')

        # 親が取得できない or PID 1 に到達
        if [ -z "$ppid" ] || [ "$ppid" = "1" ] || [ "$ppid" = "0" ]; then
            return 1
        fi

        # 祖先候補と一致
        if [ "$ppid" = "$ancestor_pid" ]; then
            return 0
        fi

        current_pid="$ppid"
        ((depth++))
    done

    return 1
}

# バッチ版: プロセスが別のプロセスの子孫かを確認（キャッシュ使用）
# $1: チェック対象PID
# $2: 祖先候補PID
# 戻り値: 0 (子孫), 1 (非子孫)
is_descendant_of_cached() {
    local check_pid="$1"
    local ancestor_pid="$2"
    local current_pid="$check_pid"

    # 同一の場合はtrue
    if [ "$current_pid" = "$ancestor_pid" ]; then
        return 0
    fi

    # 親プロセスを辿る（最大20階層）- キャッシュ版ppid取得を使用
    local max_depth=20
    local depth=0
    while [ "$depth" -lt "$max_depth" ]; do
        local ppid
        ppid=$(get_ppid_cached "$current_pid")

        # 親が取得できない or PID 1 に到達
        if [ -z "$ppid" ] || [ "$ppid" = "1" ] || [ "$ppid" = "0" ]; then
            return 1
        fi

        # 祖先候補と一致
        if [ "$ppid" = "$ancestor_pid" ]; then
            return 0
        fi

        current_pid="$ppid"
        ((depth++))
    done

    return 1
}

# キャッシュディレクトリを確保
ensure_cache_dir() {
    [ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
}

# ペインコンテンツのハッシュを保存
save_content_hash() {
    local pane_id="$1"
    local content_hash="$2"
    ensure_cache_dir
    echo "$content_hash" > "$CACHE_DIR/${pane_id//\//_}.hash"
}

# 前回のハッシュを取得
get_previous_hash() {
    local pane_id="$1"
    local hash_file="$CACHE_DIR/${pane_id//\//_}.hash"
    [ -f "$hash_file" ] && cat "$hash_file"
}

# 最後にペインコンテンツが変化した時刻を保存
save_last_change_time() {
    local pane_id="$1"
    local timestamp="$2"
    ensure_cache_dir
    echo "$timestamp" > "$CACHE_DIR/${pane_id//\//_}.lastchange"
}

# 最後にペインコンテンツが変化した時刻を取得
get_last_change_time() {
    local pane_id="$1"
    local time_file="$CACHE_DIR/${pane_id//\//_}.lastchange"
    [ -f "$time_file" ] && cat "$time_file"
}

# ペインコンテンツの変化を検出
check_pane_activity() {
    local pane_id="$1"
    local current_time
    current_time=$(date +%s)

    # 現在のペインコンテンツをキャプチャ（最後の20行）
    local current_content
    current_content=$(tmux capture-pane -t "$pane_id" -p -S -20 2>/dev/null)

    # ハッシュ化
    local current_hash
    current_hash=$(echo "$current_content" | md5sum | cut -d' ' -f1)

    # 前回のハッシュと比較
    local previous_hash
    previous_hash=$(get_previous_hash "$pane_id")

    # 現在のハッシュを保存
    save_content_hash "$pane_id" "$current_hash"

    # 比較結果を判定
    if [ -z "$previous_hash" ]; then
        # 初回は変化ありとみなす
        save_last_change_time "$pane_id" "$current_time"
        echo "unknown"
    elif [ "$current_hash" != "$previous_hash" ]; then
        # 変化あり - 時刻を更新
        save_last_change_time "$pane_id" "$current_time"
        echo "working"
    else
        # 変化なし - 最後の変化から30秒以内ならworking
        local last_change
        last_change=$(get_last_change_time "$pane_id")
        if [ -n "$last_change" ]; then
            local diff=$((current_time - last_change))
            if [ "$diff" -lt "$WORKING_THRESHOLD" ]; then
                echo "working"
            else
                echo "idle"
            fi
        else
            echo "idle"
        fi
    fi
}

# 高速版: TTY mtimeベースのペインアクティビティ検出
# FAST_MODE用: tmux capture-pane + md5sum を使わず、TTYのmtimeのみで判定
check_pane_activity_fast() {
    local pane_id="$1"
    local current_time
    current_time=$(get_current_timestamp)

    # ペインのTTYパスを取得（キャッシュ優先）
    local tty_path
    if [ -n "$BATCH_PANE_INFO_FILE" ] && [ -f "$BATCH_PANE_INFO_FILE" ]; then
        tty_path=$(awk -F'\t' -v pid="$pane_id" '$1 == pid { print $6 }' "$BATCH_PANE_INFO_FILE")
    else
        tty_path=$(tmux display-message -p -t "$pane_id" '#{pane_tty}' 2>/dev/null)
    fi

    if [ -z "$tty_path" ] || [ ! -e "$tty_path" ]; then
        echo "idle"
        return
    fi

    # TTYのmtimeを取得
    local current_mtime
    current_mtime=$(get_file_mtime "$tty_path")

    if [ -z "$current_mtime" ]; then
        echo "idle"
        return
    fi

    # mtimeが閾値内かチェック
    local diff=$((current_time - current_mtime))
    if [ "$diff" -lt "$WORKING_THRESHOLD" ]; then
        echo "working"
    else
        echo "idle"
    fi
}

# PIDからプロジェクトディレクトリパスを取得
# $1: PID
# 戻り値: ~/.claude/projects/ 内のディレクトリパス（見つからない場合は空）
get_project_session_dir() {
    local pid="$1"
    local cwd=""

    # OS判定でcwd取得方法を分岐
    if [[ "$(get_os)" == "Darwin" ]]; then
        # macOS: lsofでcwdを取得
        cwd=$(lsof -p "$pid" 2>/dev/null | awk '$4 == "cwd" {print $9}')
    else
        # Linux: /proc/PID/cwdから取得
        local cwd_link="/proc/$pid/cwd"
        if [ -L "$cwd_link" ]; then
            cwd=$(readlink "$cwd_link" 2>/dev/null)
        fi
    fi

    if [ -n "$cwd" ]; then
        # cwdをClaude Codeのプロジェクトディレクトリ名形式に変換
        # 例: /home/takets/repos/foo -> -home-takets-repos-foo
        local encoded_dir
        encoded_dir=$(echo "$cwd" | sed 's|^/||; s|/|-|g; s|^|-|')
        local project_dir="$HOME/.claude/projects/$encoded_dir"
        if [ -d "$project_dir" ]; then
            echo "$project_dir"
            return
        fi
    fi

    echo ""
}

# バッチ版: PIDからプロジェクトディレクトリパスを取得（lsofキャッシュ使用）
# $1: PID
# 戻り値: ~/.claude/projects/ 内のディレクトリパス（見つからない場合は空）
get_project_session_dir_cached() {
    local pid="$1"
    local proc_type="${2:-}"
    local cwd=""

    # キャッシュが初期化されていない場合は元の関数を使用
    if [ "$BATCH_INITIALIZED" != "1" ]; then
        get_project_session_dir "$pid"
        return
    fi

    # プロセスタイプが指定されていない場合は検出
    if [ -z "$proc_type" ]; then
        proc_type=$(get_process_type_cached "$pid")
    fi

    # OS判定でcwd取得方法を分岐
    if [[ "$(get_os)" == "Darwin" ]]; then
        # macOS: キャッシュからcwdを取得
        cwd=$(get_cwd_from_lsof_cache "$pid")
        # キャッシュにない場合はフォールバック
        if [ -z "$cwd" ]; then
            cwd=$(lsof -d cwd -p "$pid" 2>/dev/null | awk '$4 == "cwd" {print $NF}')
        fi
    else
        # Linux: /proc/PID/cwdから取得
        local cwd_link="/proc/$pid/cwd"
        if [ -L "$cwd_link" ]; then
            cwd=$(readlink "$cwd_link" 2>/dev/null)
        fi
    fi

    if [ -n "$cwd" ]; then
        case "$proc_type" in
            claude)
                # Claude Code: プロジェクトディレクトリ形式
                # 例: /home/takets/repos/foo -> -home-takets-repos-foo
                local encoded_dir
                encoded_dir=$(echo "$cwd" | sed 's|^/||; s|/|-|g; s|^|-|')
                local project_dir="$HOME/.claude/projects/$encoded_dir"
                if [ -d "$project_dir" ]; then
                    echo "$project_dir"
                    return
                fi
                ;;
            codex)
                # Codex: セッションディレクトリ（~/.codex/sessions/）
                local sessions_dir="$HOME/.codex/sessions"
                if [ -d "$sessions_dir" ]; then
                    echo "$sessions_dir"
                    return
                fi
                ;;
        esac
    fi

    echo ""
}

# 単一プロセスのworking状態を判定
# $1: PID, $2: pane_id（ペインコンテンツ変化検出用、オプション）
# 戻り値: "working" または "idle"
check_process_status() {
    local pid="$1"
    local pane_id="${2:-}"  # オプショナル: デフォルト値を空文字に

    # FAST_MODE: TTY mtimeのみで高速判定（select_claude.sh --list用）
    if [ "$FAST_MODE" = "1" ] && [ -n "$pane_id" ]; then
        check_pane_activity_fast "$pane_id"
        return
    fi

    local current_time
    current_time=$(get_current_timestamp)

    # 方法1: ペインコンテンツの変化で判定（pane_idが提供されている場合）
    if [ -n "$pane_id" ]; then
        local activity
        activity=$(check_pane_activity "$pane_id")
        if [ "$activity" != "unknown" ]; then
            echo "$activity"
            return
        fi
    fi

    # 方法2: CPU使用率で判定（閾値以上ならworking）
    local cpu
    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' | cut -d. -f1)
    if [ -n "$cpu" ] && [ "$cpu" -gt "$CPU_THRESHOLD" ] 2>/dev/null; then
        echo "working"
        return
    fi

    # 方法3: プロジェクトのセッションファイル（.jsonl）の更新時刻で判定
    # プロセスタイプを検出
    local proc_type
    proc_type=$(get_process_type_cached "$pid")

    # バッチ版を使用してlsofキャッシュを共有
    local project_dir
    project_dir=$(get_project_session_dir_cached "$pid" "$proc_type")

    if [ -n "$project_dir" ] && [ -d "$project_dir" ]; then
        local latest_file=""

        case "$proc_type" in
            claude)
                # Claude Code: プロジェクトディレクトリ直下の.jsonl
                latest_file=$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -1)
                ;;
            codex)
                # Codex: 日付ベースディレクトリから最新の.jsonlを検索
                latest_file=$(find "$project_dir" -type f -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
                ;;
            *)
                # Unknown process type: use claude behavior as fallback
                latest_file=$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -1)
                ;;
        esac

        if [ -n "$latest_file" ] && [ -f "$latest_file" ]; then
            local mtime
            mtime=$(get_file_mtime "$latest_file")
            if [ -n "$mtime" ]; then
                local diff=$((current_time - mtime))
                # 閾値内ならworking
                if [ "$diff" -lt "$WORKING_THRESHOLD" ]; then
                    echo "working"
                    return
                fi
            fi
        fi
    fi

    # 方法4: debug ファイルで判定（旧方式、フォールバック、claude のみ）
    if [ "$proc_type" = "claude" ]; then
        local debug_dir="$HOME/.claude/debug"
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
    fi

    # 全ての判定でworkingでない場合はidle
    echo "idle"
}

# 全セッションの状態を取得（旧形式・後方互換用）
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

# 全セッションの詳細情報を取得（新形式）
# 戻り値: "terminal_emoji:pane_index:project_name:status|..." 形式
# statusは "working" または "idle"
# 同じプロジェクト名でも異なるセッションの場合は番号付きで表示
# 注意: Detached セッション（クライアント未接続）のプロセスは除外される
get_session_details() {
    # Phase 4: AI プロセス（claude + codex）を取得
    local pids
    pids=$(get_ai_pids)

    if [ -z "$pids" ]; then
        echo ""
        return
    fi

    # Attached セッション一覧を取得（Detached 除外用）
    local attached_sessions
    attached_sessions=$(tmux list-clients -F '#{client_session}' 2>/dev/null | sort -u)

    # show_codex オプション
    local show_codex="${SHOW_CODEX:-on}"

    local details=""
    local seen_pane_ids=""
    local seen_project_names=""  # "name:count|name:count|..." 形式

    for pid in $pids; do
        local pane_info pane_id pane_index project_name status terminal_emoji proc_type

        # プロセスタイプを取得
        proc_type=$(get_process_type_cached "$pid")

        # show_codex が off で codex プロセスの場合はスキップ
        if [ "$proc_type" = "codex" ] && [ "$show_codex" != "on" ]; then
            continue
        fi

        # ペイン情報を取得（重複チェック用）
        pane_info=$(get_pane_info_for_pid "$pid")
        if [ -z "$pane_info" ]; then
            pane_id="unknown_$$_$pid"
            pane_index=""
        else
            pane_id="${pane_info%%:*}"
            # ペインインデックスを取得
            pane_index=$(get_pane_index "$pane_id")
        fi

        # Detached セッションのプロセスをスキップ
        if [ -n "$pane_id" ] && [ "$pane_id" != "unknown_$$_$pid" ]; then
            local session_name
            session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)
            if [ -n "$session_name" ]; then
                # セッションが attached_sessions に含まれているかチェック
                if ! echo "$attached_sessions" | grep -qx "$session_name"; then
                    # Detached セッションのプロセスはスキップ
                    continue
                fi
            fi
        fi

        # 同じペインIDの重複を避ける
        if [[ "$seen_pane_ids" == *"|$pane_id|"* ]]; then
            continue
        fi
        seen_pane_ids+="|$pane_id|"

        # ターミナル絵文字を取得（pane_idを渡してセッション特定に使用）
        terminal_emoji=$(get_terminal_emoji "$pid" "$pane_id")

        # プロジェクト名を取得（作業ディレクトリ名）
        project_name=$(get_project_name_for_pid "$pid")

        # プロジェクト名の出現回数をカウント（Bash 3.x互換方式）
        local current_count=0
        if [[ "$seen_project_names" == *"|$project_name:"* ]]; then
            # 既存のカウントを抽出
            local pattern="${project_name}:"
            local after="${seen_project_names#*|${pattern}}"
            current_count="${after%%|*}"
            ((current_count++))
            # カウントを更新
            seen_project_names="${seen_project_names/|${pattern}${after%%|*}|/|${pattern}${current_count}|}"
            # 同じ名前が既に存在する場合、番号を付ける
            project_name="${project_name}#${current_count}"
        else
            seen_project_names+="|${project_name}:1|"
        fi

        # 状態を取得（ペインIDを渡す）
        status=$(check_process_status "$pid" "$pane_id")

        # 詳細を追加（新形式: process_type:terminal_emoji:pane_index:project_name:status）
        if [ -n "$details" ]; then
            details+="|"
        fi
        details+="${proc_type}:${terminal_emoji}:${pane_index}:${project_name}:${status}"
    done

    echo "$details"
}

# 直接実行時のテスト用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Claude PIDs: $(get_claude_pids)"
    echo "Session states: $(get_session_states)"
fi
