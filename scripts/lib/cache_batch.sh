#!/usr/bin/env bash
# cache_batch.sh - Process-lifetime batch cache (18 functions)
# Source guard: prevent double-sourcing
if [ -n "${__LIB_CACHE_BATCH_LOADED:-}" ]; then return 0; fi
__LIB_CACHE_BATCH_LOADED=1

# Dependencies
source "${BASH_SOURCE[0]%/*}/platform.sh"
source "${BASH_SOURCE[0]%/*}/terminal.sh"

# ==============================================================================
# FAST_MODE Configuration
# ==============================================================================
# FAST_MODE: select_claude.sh --list用の軽量モード
# 1の場合、check_pane_activity()をスキップしてセッションファイル更新時刻のみで判定
FAST_MODE="${FAST_MODE:-0}"

# ==============================================================================
# バッチ処理用キャッシュ変数（一時ファイルパス）
# ==============================================================================
BATCH_DIR=""
BATCH_PROCESS_TREE_FILE=""
BATCH_PANE_INFO_FILE=""
BATCH_TERMINAL_CACHE_FILE=""
BATCH_TMUX_OPTIONS_FILE=""
BATCH_CLIENTS_CACHE_FILE=""
BATCH_TTY_STAT_FILE=""
BATCH_PID_PANE_MAP_FILE=""
BATCH_LSOF_OUTPUT_FILE=""
BATCH_INITIALIZED=0

# ==============================================================================
# バッチ処理初期化・クリーンアップ
# ==============================================================================

# バッチ処理の初期化（全キャッシュを一度に作成）
# select_claude.sh の先頭で呼び出し
# 高速化: 全外部コマンドを1フェーズで並列実行（Phase分離を廃止）
init_batch_cache() {
    if [ "$BATCH_INITIALIZED" = "1" ]; then
        return 0
    fi

    # 一時ディレクトリを1回で作成
    BATCH_DIR="/tmp/claudecode_batch_$$"
    mkdir -p "$BATCH_DIR"
    BATCH_PROCESS_TREE_FILE="$BATCH_DIR/ps"
    BATCH_PANE_INFO_FILE="$BATCH_DIR/panes"
    BATCH_TERMINAL_CACHE_FILE="$BATCH_DIR/term"
    BATCH_PID_PANE_MAP_FILE="$BATCH_DIR/pidmap"
    BATCH_TMUX_OPTIONS_FILE="$BATCH_DIR/opts"
    BATCH_CLIENTS_CACHE_FILE="$BATCH_DIR/clients"
    BATCH_TTY_STAT_FILE="$BATCH_DIR/ttystat"
    BATCH_LSOF_OUTPUT_FILE="$BATCH_DIR/lsof"

    # ========================================
    # 全外部コマンドを並列実行（Phase統合で待機時間削減）
    # ========================================

    # プロセスツリー取得（args フィールドを追加してCodex検出に対応）
    ps -eo pid,ppid,comm,args 2>/dev/null > "$BATCH_PROCESS_TREE_FILE" &
    local ps_pid=$!

    # tmuxペイン情報（pane_current_pathも取得）
    tmux list-panes -a -F "#{pane_id}"$'\t'"#{pane_pid}"$'\t'"#{session_name}"$'\t'"#{window_index}"$'\t'"#{pane_index}"$'\t'"#{pane_tty}"$'\t'"#{pane_current_path}" 2>/dev/null > "$BATCH_PANE_INFO_FILE" &
    local panes_pid=$!

    # tmuxオプション
    tmux show-options -g 2>/dev/null | grep "^@claudecode" > "$BATCH_TMUX_OPTIONS_FILE" &
    local opts_pid=$!

    # tmuxクライアント情報
    tmux list-clients -F "#{client_session}"$'\t'"#{client_tty}"$'\t'"#{client_pid}" 2>/dev/null > "$BATCH_CLIENTS_CACHE_FILE" &
    local clients_pid=$!

    # 基本コマンドを待機
    wait $ps_pid $panes_pid $opts_pid $clients_pid

    # ========================================
    # 後処理（awk統合処理）を並列実行
    # ========================================

    # PID -> pane_id マッピング + ターミナル検出 + TTY stat を並列実行
    _build_pid_pane_map &
    local pidmap_pid=$!

    # ターミナル検出
    _prebuild_terminal_cache &
    local termcache_pid=$!

    # TTY mtime一括取得
    if [[ "$(get_os)" == "Darwin" ]]; then
        awk -F'\t' 'NF>=6 && $6!="" {print $6}' "$BATCH_PANE_INFO_FILE" 2>/dev/null | \
            sort -u | xargs stat -f "%N %m" 2>/dev/null > "$BATCH_TTY_STAT_FILE" &
    else
        awk -F'\t' 'NF>=6 && $6!="" {print $6}' "$BATCH_PANE_INFO_FILE" 2>/dev/null | \
            sort -u | xargs stat -c "%n %Y" 2>/dev/null > "$BATCH_TTY_STAT_FILE" &
    fi
    local ttystat_pid=$!

    # 後処理を待機
    wait $pidmap_pid $termcache_pid $ttystat_pid 2>/dev/null

    trap cleanup_batch_cache EXIT
    BATCH_INITIALIZED=1
}

# PID -> pane_id マッピングを構築（内部関数）
# claudeプロセスのみを対象に祖先を辿り、pane_pidにマッチするものをマッピング
_build_pid_pane_map() {
    # claude と codex プロセスを対象
    awk -F'\t' '
    FNR == NR {
        pane_pids[$2] = $1  # pane_pid -> pane_id
        next
    }
    {
        gsub(/^[ \t]+/, "")
        n = split($0, f, /[ \t]+/)
        pid = f[1]; parent = f[2]; comm = f[3]

        # 4番目以降のフィールドを args として結合
        args = ""
        for (i = 4; i <= n; i++) {
            args = args (i > 4 ? " " : "") f[i]
        }

        if (pid != "" && pid != "PID") {
            ppid[pid] = parent
            # claude プロセスを検出
            if (comm == "claude") {
                ai_proc[pid] = "claude"
            }
            # Codex プロセスを検出（commに依存せず、args から /bin/codex を検索）
            # Note: ps -eo comm は 'MainThread' を返すため、args で判定
            else if (args ~ /\/bin\/codex([[:space:]]|$)/) {
                ai_proc[pid] = "codex"
            }
        }
    }
    END {
        # AI プロセスの祖先を辿る
        for (pid in ai_proc) {
            current = pid
            for (d = 0; d < 20; d++) {
                if (current in pane_pids) {
                    print pid "\t" pane_pids[current] "\t" ai_proc[pid]
                    break
                }
                if (current == "" || current == "1" || current == "0") break
                current = ppid[current]
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
        # grepの方がawkより高速
        grep "^${pid}	" "$BATCH_PID_PANE_MAP_FILE" 2>/dev/null | cut -f2
    fi
}

# 複数PIDの全情報を一括取得（FAST_MODE用の超高速版）
# 戻り値: "pid|pane_id|session_name|window_index|tty_path|terminal|cwd" 形式の行リスト
# 注意: Detached セッション（クライアント未接続）のプロセスは除外される
get_all_claude_info_batch() {
    [ "$BATCH_INITIALIZED" != "1" ] && return

    # awkで一括処理: 全キャッシュファイルを結合
    # ファイル順序:
    #   1: BATCH_PID_PANE_MAP_FILE (pid -> pane_id)
    #   2: BATCH_PANE_INFO_FILE (pane_id -> session, window, tty, cwd)
    #   3: BATCH_TERMINAL_CACHE_FILE (session -> terminal)
    #   4: BATCH_CLIENTS_CACHE_FILE (attached sessions)
    #   5: BATCH_PROCESS_TREE_FILE (process tree with claude detection)
    awk -v f1="$BATCH_PID_PANE_MAP_FILE" \
        -v f2="$BATCH_PANE_INFO_FILE" \
        -v f3="$BATCH_TERMINAL_CACHE_FILE" \
        -v f4="$BATCH_CLIENTS_CACHE_FILE" \
        -v f5="$BATCH_PROCESS_TREE_FILE" '
    BEGIN { FS="\t" }
    FILENAME == f1 { pid_pane[$1]=$2; pid_type[$1]=$3; next }
    FILENAME == f2 { pane_session[$1]=$3; pane_window[$1]=$4; pane_tty[$1]=$6; pane_cwd[$1]=$7; next }
    FILENAME == f3 { session_term[$1]=$2; next }
    FILENAME == f4 { attached_sessions[$1]=1; next }
    # f5 (BATCH_PROCESS_TREE_FILE) は使用しない（pid_type で既に判定済み）
    END {
        # pid_type を使用（BATCH_PID_PANE_MAP_FILE から取得済み）
        for(pid in pid_type) {
            p=pid_pane[pid]; if(p=="") continue
            s=pane_session[p]
            # Detached セッションも含める（すべてのセッションを表示）
            # if (!(s in attached_sessions)) continue
            c=pane_cwd[p]; if(c=="") c="unknown"
            print pid"|"p"|"s"|"pane_window[p]"|"pane_tty[p]"|"session_term[s]"|"c"|"pid_type[pid]
        }
    }' "$BATCH_PID_PANE_MAP_FILE" "$BATCH_PANE_INFO_FILE" "$BATCH_TERMINAL_CACHE_FILE" "$BATCH_CLIENTS_CACHE_FILE" "$BATCH_PROCESS_TREE_FILE" 2>/dev/null
}

# バッチキャッシュのクリーンアップ
cleanup_batch_cache() {
    # ディレクトリごと削除（高速化）
    [ -n "$BATCH_DIR" ] && [ -d "$BATCH_DIR" ] && rm -rf "$BATCH_DIR"
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
# バッチ版クライアント情報取得
# ==============================================================================

# キャッシュからセッションのclient_pidを取得
# $1: session_name
# 戻り値: client_pid（最初のクライアントのPID）
get_client_pid_for_session_cached() {
    local session="$1"
    if [ -n "$BATCH_CLIENTS_CACHE_FILE" ] && [ -f "$BATCH_CLIENTS_CACHE_FILE" ]; then
        # フォーマット: "session_name\tclient_tty\tclient_pid"
        awk -F'\t' -v s="$session" '$1 == s { print $3; exit }' "$BATCH_CLIENTS_CACHE_FILE"
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
        # -a: AND条件（-d cwd かつ -p pid_list）- これがないと全プロセスを返してしまう
        # -d cwd: FD field を cwd に限定
        # 出力形式: "COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME"
        lsof -a -d cwd -p "$pid_list" 2>/dev/null > "$BATCH_LSOF_OUTPUT_FILE"
    fi
}

# キャッシュからPIDのcwdを取得
# $1: PID
# 戻り値: cwd パス
get_cwd_from_lsof_cache() {
    local pid="$1"
    if [ -n "$BATCH_LSOF_OUTPUT_FILE" ] && [ -f "$BATCH_LSOF_OUTPUT_FILE" ] && [ -s "$BATCH_LSOF_OUTPUT_FILE" ]; then
        # lsof 通常出力形式（-F pn なし）:
        # COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        # claude  1234 user  cwd   DIR    1,4      640   12 /path/to/dir
        # PIDが一致する行からNAME（最後のフィールド）を抽出
        awk -v pid="$pid" '
            $2 == pid && $4 == "cwd" { print $NF; exit }
        ' "$BATCH_LSOF_OUTPUT_FILE"
    fi
}

# ==============================================================================
# バッチ版ペインインデックス取得
# ==============================================================================

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
