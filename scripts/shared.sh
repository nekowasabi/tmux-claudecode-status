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
