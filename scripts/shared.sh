#!/usr/bin/env bash
# shared.sh - 共通ユーティリティ関数
# tmuxオプションの読み書きとプラットフォーム共通処理を提供
# バッチ処理用キャッシュ機能を含む（Bash 3.2互換）

# ==============================================================================
# 高速化用キャッシュ変数
# ==============================================================================
# OS判定をキャッシュ（unameの呼び出しを1回に削減）
_CACHED_OS="${_CACHED_OS:-}"

# FAST_MODE: select_claude.sh --list用の軽量モード
# 1の場合、check_pane_activity()をスキップしてセッションファイル更新時刻のみで判定
FAST_MODE="${FAST_MODE:-0}"

# ==============================================================================
# 共有キャッシュ（claudecode_status.sh → select_claude.sh）
# ==============================================================================
# select_claude.sh の高速化のため、claudecode_status.sh が収集した
# プロセス情報を共有キャッシュに書き出す
SHARED_CACHE_FILE="/tmp/claudecode_shared_process_cache"
SHARED_CACHE_TTL=5  # キャッシュ有効期間（秒）

# 共有キャッシュにプロセス情報を書き出す
# $1: プロセス情報（get_all_claude_info_batch形式: pid|pane_id|session|window|tty|terminal|cwd）
# フォーマット:
#   1行目: タイムスタンプ
#   2行目: tmuxオプション（TAB区切り: working_dot idle_dot terminal_iterm terminal_wezterm terminal_ghostty terminal_unknown）
#   3行目: TTY stat情報（"tty_path mtime;tty_path2 mtime2;..."形式）
#   4行目以降: プロセス情報
write_shared_cache() {
    local process_info="$1"
    local timestamp
    timestamp=$(get_current_timestamp)

    # tmuxオプションを一括取得（6回の呼び出しを1回に最適化）
    local tmux_opts
    tmux_opts=$(tmux show-options -g 2>/dev/null | awk '
        /@claudecode_working_dot/ { wd=$2 }
        /@claudecode_idle_dot/ { id=$2 }
        /@claudecode_terminal_iterm/ { ti=$2 }
        /@claudecode_terminal_wezterm/ { tw=$2 }
        /@claudecode_terminal_ghostty/ { tg=$2 }
        /@claudecode_terminal_unknown/ { tu=$2 }
        END {
            if (wd=="") wd="working"
            if (id=="") id="idle"
            if (ti=="") ti="🍎"
            if (tw=="") tw="⚡"
            if (tg=="") tg="👻"
            if (tu=="") tu="❓"
            print wd "\t" id "\t" ti "\t" tw "\t" tg "\t" tu
        }
    ')

    # TTY stat情報を収集（プロセス情報からTTYパスを抽出）
    local tty_stat=""
    if [ -n "$process_info" ]; then
        local tty_paths
        tty_paths=$(echo "$process_info" | awk -F'|' '{print $5}' | sort -u | grep -v '^$')
        if [ -n "$tty_paths" ]; then
            # stat結果を"path mtime;path2 mtime2"形式に変換
            tty_stat=$(echo "$tty_paths" | xargs stat -f "%N %m" 2>/dev/null | tr '\n' ';' | sed 's/;$//')
        fi
    fi

    {
        echo "$timestamp"
        echo "$tmux_opts"
        echo "$tty_stat"
        echo "$process_info"
    } > "$SHARED_CACHE_FILE" 2>/dev/null
}

# 共有キャッシュからプロセス情報を読み込む
# 戻り値: プロセス情報（キャッシュが新鮮な場合）または空文字（古い/存在しない場合）
# フォーマット: 1行目=tmuxオプション、2行目以降=プロセス情報
read_shared_cache() {
    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        return
    fi

    local current_time
    current_time=$(get_current_timestamp)

    local cache_time
    cache_time=$(head -1 "$SHARED_CACHE_FILE" 2>/dev/null)

    if [ -z "$cache_time" ]; then
        return
    fi

    local age=$((current_time - cache_time))
    if [ "$age" -gt "$SHARED_CACHE_TTL" ]; then
        # キャッシュが古い
        return
    fi

    # タイムスタンプ行を除いた内容を返す（tmuxオプション + プロセス情報）
    tail -n +2 "$SHARED_CACHE_FILE" 2>/dev/null
}

# 共有キャッシュからtmuxオプション行のみを取得
# 戻り値: "working_dot\tidle_dot\tterminal_iterm\tterminal_wezterm\tterminal_ghostty\tterminal_unknown"
read_shared_cache_options() {
    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        return
    fi

    # 2行目がtmuxオプション
    sed -n '2p' "$SHARED_CACHE_FILE" 2>/dev/null
}

# 共有キャッシュからプロセス情報行のみを取得
# 戻り値: プロセス情報（4行目以降）
read_shared_cache_processes() {
    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        return
    fi

    # 4行目以降がプロセス情報
    tail -n +4 "$SHARED_CACHE_FILE" 2>/dev/null
}

# 共有キャッシュからTTY stat情報を取得
# 戻り値: "tty_path mtime;tty_path2 mtime2;..."形式
read_shared_cache_tty_stat() {
    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        return
    fi

    # 3行目がTTY stat情報
    sed -n '3p' "$SHARED_CACHE_FILE" 2>/dev/null
}

# 共有キャッシュを一括読み込み（最適化版）
# 1回のファイル読み込みで全フィールドを取得（awkで1パス処理）
# 戻り値: 成功時0（グローバル変数に値を設定）、失敗時1
# 設定されるグローバル変数:
#   _SHARED_CACHE_OPTIONS: tmuxオプション
#   _SHARED_CACHE_TTY_STAT: TTY stat情報
#   _SHARED_CACHE_PROCESSES: プロセス情報
read_shared_cache_all() {
    _SHARED_CACHE_OPTIONS=""
    _SHARED_CACHE_TTY_STAT=""
    _SHARED_CACHE_PROCESSES=""

    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        return 1
    fi

    local current_time="${EPOCHSECONDS:-$(date +%s)}"

    # awkで1パス処理: タイムスタンプ検証と全フィールド抽出を同時に実行
    local result
    result=$(awk -v now="$current_time" -v ttl="$SHARED_CACHE_TTL" '
        NR==1 {
            if (now - $0 > ttl) { print "EXPIRED"; exit }
            next
        }
        NR==2 { opts=$0; next }
        NR==3 { tty=$0; next }
        NR>3 { procs = procs (procs=="" ? "" : "\n") $0 }
        END {
            if (opts != "") {
                print "OPTIONS:" opts
                print "TTY:" tty
                print "PROCESSES:" procs
            }
        }
    ' "$SHARED_CACHE_FILE" 2>/dev/null)

    if [ "$result" = "EXPIRED" ] || [ -z "$result" ]; then
        return 1
    fi

    # 結果をパース
    _SHARED_CACHE_OPTIONS="${result#OPTIONS:}"
    _SHARED_CACHE_OPTIONS="${_SHARED_CACHE_OPTIONS%%TTY:*}"
    _SHARED_CACHE_OPTIONS="${_SHARED_CACHE_OPTIONS%$'\n'}"

    local rest="${result#*TTY:}"
    _SHARED_CACHE_TTY_STAT="${rest%%PROCESSES:*}"
    _SHARED_CACHE_TTY_STAT="${_SHARED_CACHE_TTY_STAT%$'\n'}"

    _SHARED_CACHE_PROCESSES="${rest#*PROCESSES:}"

    return 0
}

# 共有キャッシュの年齢を取得（秒）
# 戻り値: キャッシュの経過秒数、存在しない場合は999999
get_shared_cache_age() {
    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        echo 999999
        return
    fi

    local current_time
    current_time=$(get_current_timestamp)

    local cache_time
    cache_time=$(head -1 "$SHARED_CACHE_FILE" 2>/dev/null)

    if [ -z "$cache_time" ]; then
        echo 999999
        return
    fi

    echo $((current_time - cache_time))
}

# ==============================================================================
# バッチ処理用キャッシュ変数（一時ファイルパス）
# ==============================================================================
BATCH_PROCESS_TREE_FILE=""
BATCH_PANE_INFO_FILE=""
BATCH_TERMINAL_CACHE_FILE=""
BATCH_TMUX_OPTIONS_FILE=""
BATCH_CLIENTS_CACHE_FILE=""
BATCH_TTY_STAT_FILE=""
BATCH_INITIALIZED=0

# ==============================================================================
# バッチ処理初期化・クリーンアップ
# ==============================================================================

# PID -> pane_id マッピング用キャッシュファイル
BATCH_PID_PANE_MAP_FILE=""

# バッチ処理の初期化（全キャッシュを一度に作成）
# select_claude.sh の先頭で呼び出し
# 高速化: 全外部コマンドを1フェーズで並列実行（Phase分離を廃止）
init_batch_cache() {
    if [ "$BATCH_INITIALIZED" = "1" ]; then
        return 0
    fi

    # 一時ディレクトリを1回で作成
    local batch_dir="/tmp/claudecode_batch_$$"
    mkdir -p "$batch_dir"
    BATCH_PROCESS_TREE_FILE="$batch_dir/ps"
    BATCH_PANE_INFO_FILE="$batch_dir/panes"
    BATCH_TERMINAL_CACHE_FILE="$batch_dir/term"
    BATCH_PID_PANE_MAP_FILE="$batch_dir/pidmap"
    BATCH_TMUX_OPTIONS_FILE="$batch_dir/opts"
    BATCH_CLIENTS_CACHE_FILE="$batch_dir/clients"
    BATCH_TTY_STAT_FILE="$batch_dir/ttystat"

    # ========================================
    # 全外部コマンドを並列実行（Phase統合で待機時間削減）
    # ========================================

    # プロセスツリー取得
    ps -eo pid,ppid,comm 2>/dev/null > "$BATCH_PROCESS_TREE_FILE" &
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
    awk -F'\t' 'NF>=6 && $6!="" {print $6}' "$BATCH_PANE_INFO_FILE" 2>/dev/null | \
        sort -u | xargs stat -f "%N %m" 2>/dev/null > "$BATCH_TTY_STAT_FILE" &
    local ttystat_pid=$!

    # 後処理を待機
    wait $pidmap_pid $termcache_pid $ttystat_pid 2>/dev/null

    trap cleanup_batch_cache EXIT
    BATCH_INITIALIZED=1
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
}

# PID -> pane_id マッピングを構築（内部関数）
# claudeプロセスのみを対象に祖先を辿り、pane_pidにマッチするものをマッピング
_build_pid_pane_map() {
    # claudeプロセスのみを対象にすることで高速化
    awk -F'\t' '
    FNR == NR {
        pane_pids[$2] = $1  # pane_pid -> pane_id
        next
    }
    {
        gsub(/^[ \t]+/, "")
        split($0, f, /[ \t]+/)
        pid = f[1]; parent = f[2]; comm = f[3]
        if (pid != "" && pid != "PID") {
            ppid[pid] = parent
            if (comm == "claude") claude[pid] = 1
        }
    }
    END {
        # claudeプロセスのみ祖先を辿る
        for (pid in claude) {
            current = pid
            for (d = 0; d < 20; d++) {
                if (current in pane_pids) { print pid "\t" pane_pids[current]; break }
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
    awk '
    BEGIN { FS="\t"; fnum=0 }
    FNR==1 { fnum++ }
    fnum==1 { pid_pane[$1]=$2; next }
    fnum==2 { pane_session[$1]=$3; pane_window[$1]=$4; pane_tty[$1]=$6; pane_cwd[$1]=$7; next }
    fnum==3 { session_term[$1]=$2; next }
    fnum==4 { attached_sessions[$1]=1; next }
    fnum==5 { gsub(/^[ \t]+/,""); split($0,f,/[ \t]+/); if(f[3]=="claude") claude_pids[f[1]]=1 }
    END {
        for(pid in claude_pids) {
            p=pid_pane[pid]; if(p=="") continue
            s=pane_session[p]
            # Detached セッションのプロセスを除外
            if (!(s in attached_sessions)) continue
            c=pane_cwd[p]; if(c=="") c="unknown"
            print pid"|"p"|"s"|"pane_window[p]"|"pane_tty[p]"|"session_term[s]"|"c
        }
    }' "$BATCH_PID_PANE_MAP_FILE" "$BATCH_PANE_INFO_FILE" "$BATCH_TERMINAL_CACHE_FILE" "$BATCH_CLIENTS_CACHE_FILE" "$BATCH_PROCESS_TREE_FILE" 2>/dev/null
}

# バッチキャッシュのクリーンアップ
cleanup_batch_cache() {
    # ディレクトリごと削除（高速化）
    [ -d "/tmp/claudecode_batch_$$" ] && rm -rf "/tmp/claudecode_batch_$$"
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

# バッチ版: tmuxオプションの値を取得（キャッシュ使用）
# $1: オプション名
# $2: デフォルト値（オプション）
get_tmux_option_cached() {
    local option="$1"
    local default_value="$2"

    # キャッシュが初期化されていない場合は元の関数を使用
    if [ "$BATCH_INITIALIZED" != "1" ] || [ -z "$BATCH_TMUX_OPTIONS_FILE" ] || [ ! -f "$BATCH_TMUX_OPTIONS_FILE" ]; then
        get_tmux_option "$option" "$default_value"
        return
    fi

    # キャッシュから取得
    # フォーマット: "@claudecode_option_name value"
    local option_value
    option_value=$(awk -v opt="$option" '$1 == opt { $1=""; print substr($0, 2); exit }' "$BATCH_TMUX_OPTIONS_FILE")

    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# バッチ版: 複数のtmuxオプションを一括取得（高速化）
# 引数: "オプション名=デフォルト値" のペアを複数指定
# 戻り値: "オプション名=値" 形式の行を出力（evalで変数に展開可能）
# 使用例: eval "$(get_tmux_options_bulk "@claudecode_working_dot=working" "@claudecode_idle_dot=idle")"
get_tmux_options_bulk() {
    # キャッシュが利用可能かチェック
    if [ "$BATCH_INITIALIZED" != "1" ] || [ -z "$BATCH_TMUX_OPTIONS_FILE" ] || [ ! -f "$BATCH_TMUX_OPTIONS_FILE" ]; then
        # フォールバック: 個別に取得
        for arg in "$@"; do
            local opt="${arg%%=*}"
            local default="${arg#*=}"
            local val
            val=$(get_tmux_option "$opt" "$default")
            # オプション名から@claudecode_を除去して変数名に
            local varname="${opt#@claudecode_}"
            echo "${varname}='${val}'"
        done
        return
    fi

    # 1回のawk呼び出しで全オプションを取得
    awk -v args="$*" '
    BEGIN {
        n = split(args, pairs, " ")
        for (i = 1; i <= n; i++) {
            split(pairs[i], kv, "=")
            opt = kv[1]
            default_val = kv[2]
            defaults[opt] = default_val
            # 変数名は@claudecode_を除去
            varname = opt
            gsub(/^@claudecode_/, "", varname)
            varnames[opt] = varname
        }
    }
    {
        opt = $1
        if (opt in defaults) {
            $1 = ""
            val = substr($0, 2)
            gsub(/'\''/, "'\''\\'\'''\''", val)  # シングルクォートをエスケープ
            print varnames[opt] "='\''" val "'\''"
            found[opt] = 1
        }
    }
    END {
        for (opt in defaults) {
            if (!(opt in found)) {
                val = defaults[opt]
                gsub(/'\''/, "'\''\\'\'''\''", val)
                print varnames[opt] "='\''" val "'\''"
            }
        }
    }
    ' "$BATCH_TMUX_OPTIONS_FILE"
}

# tmuxオプションを設定
# $1: オプション名
# $2: 値
set_tmux_option() {
    tmux set-option -gq "$1" "$2"
}

# OS判定をキャッシュして返す（unameの呼び出しを最小化）
get_os() {
    if [ -z "$_CACHED_OS" ]; then
        _CACHED_OS=$(uname)
    fi
    echo "$_CACHED_OS"
}

# クロスプラットフォーム対応のファイル更新時刻取得
# $1: ファイルパス
# 戻り値: Unixタイムスタンプ（秒）
get_file_mtime() {
    local file="$1"
    if [[ "$(get_os)" == "Darwin" ]]; then
        # macOS
        stat -f %m "$file" 2>/dev/null
    else
        # Linux
        stat -c %Y "$file" 2>/dev/null
    fi
}

# 現在のUnixタイムスタンプを取得（EPOCHSECONDSがあれば使用）
get_current_timestamp() {
    if [ -n "${EPOCHSECONDS:-}" ]; then
        echo "$EPOCHSECONDS"
    else
        date +%s
    fi
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
                    if [ -n "$WT_SESSION" ]; then
                        terminal_name="WindowsTerminal"
                    elif [ -n "$VSCODE_IPC_HOOK_CLI" ]; then
                        terminal_name="VSCode"
                    elif [ -n "$ALACRITTY_LOG" ] || [ -n "$ALACRITTY_SOCKET" ]; then
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
