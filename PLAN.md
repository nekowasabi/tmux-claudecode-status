---
mission_id: tmux-claudecode-status-001
title: "tmux-statusline-claudecode-status プラグイン実装"
status: planning
progress: 0
phase: planning
tdd_mode: true
blockers: 0
created_at: "2025-12-29"
updated_at: "2025-12-29"
---

# tmux-statusline-claudecode-status 実装計画

## Commander's Intent

### Purpose
tmuxの上部ステータスバー（status-top）にClaude Codeの実行状態を表示し、複数セッションを個別に追跡してidle/working状態を可視化する。

### End State
- tmuxステータスバーに `●●○` 形式で各Claude Codeセッションの状態を表示
- working（作業中）とidle（待機中）が色で区別可能
- 複数セッション実行時にどれが完了しているか一目で判別可能

### Key Tasks
1. Claude Codeプロセスの検出とセッション追跡
2. 各セッションのworking/idle状態判定
3. tmux status-top への統合
4. カスタマイズ可能な設定オプション

### Constraints
- TPM（tmux Plugin Manager）対応必須
- パフォーマンス: 50ms以内で実行完了
- クロスプラットフォーム: Linux/macOS対応

### Restraints
- Nerd Font依存（デフォルトアイコン）
- tmux 2.9以上（status-format対応）

---

## Context

### 概要
このプラグインは、tmuxのステータスバーにClaude Codeの実行状態をリアルタイム表示する。特に複数のClaude Codeセッションを並行実行する際、各セッションの状態（working/idle）を個別に追跡し、どのセッションが作業中でどれが完了待ちかを即座に把握できるようにする。

### 必須のルール
1. **TDD厳守**: テスト → 実装 → リファクタリングの順序
2. **軽量実装**: 毎秒実行されるため、処理は最小限に
3. **キャッシュ活用**: 頻繁な呼び出しに対応

### 開発のゴール
- ユーザーが `set -g @plugin 'takets/tmux-claudecode-status'` を追加するだけで動作
- 複数セッションの状態が `●●○` 形式で即座に確認可能

---

## References

### @ref: 参照ファイル
| パス | 用途 |
|------|------|
| `~/.tmux/plugins/tpm/tpm` | TPMのプラグイン読み込みパターン参照 |
| `~/.tmux/plugins/tpm/scripts/source_plugins.sh` | プラグインソース方法 |
| `~/.claude/debug/` | セッション状態検出のデータソース |
| `~/.claude/history.jsonl` | セッション履歴（補助的検出） |

### @target: 実装ファイル
| パス | 説明 |
|------|------|
| `/home/takets/repos/tmux-statusline-claudecode-status/claudecode_status.tmux` | TPMエントリーポイント |
| `/home/takets/repos/tmux-statusline-claudecode-status/scripts/shared.sh` | 共通ユーティリティ |
| `/home/takets/repos/tmux-statusline-claudecode-status/scripts/claudecode_status.sh` | メインステータス出力 |
| `/home/takets/repos/tmux-statusline-claudecode-status/scripts/session_tracker.sh` | セッション追跡ロジック |
| `/home/takets/repos/tmux-statusline-claudecode-status/README.md` | ドキュメント |

### @test: テストファイル
| パス | 説明 |
|------|------|
| `/home/takets/repos/tmux-statusline-claudecode-status/tests/test_detection.sh` | プロセス検出テスト |
| `/home/takets/repos/tmux-statusline-claudecode-status/tests/test_status.sh` | ステータス判定テスト |
| `/home/takets/repos/tmux-statusline-claudecode-status/tests/test_output.sh` | 出力フォーマットテスト |

---

## Progress Map

| Process | Status | Progress | Phase | Notes |
|---------|--------|----------|-------|-------|
| 1. 基本構造作成 | completed | 100% | - | ディレクトリ・ファイル構造 |
| 2. 共通ユーティリティ | completed | 100% | - | shared.sh |
| 3. プロセス検出 | completed | 100% | - | pgrepベースの検出 |
| 4. セッション追跡 | completed | 100% | - | 個別セッション状態判定 |
| 5. メイン出力 | completed | 100% | - | フォーマット済み出力 |
| 6. TPM統合 | completed | 100% | - | エントリーポイント |
| 10. 検出テスト | completed | 100% | - | test_detection.sh |
| 11. ステータステスト | completed | 100% | - | test_status.sh |
| 200. README作成 | completed | 100% | - | ドキュメント |

---

## Processes

### Process 1: 基本構造作成

#### 目標
プロジェクトのディレクトリ構造とファイルスケルトンを作成

#### Red Phase
```bash
# テスト: ディレクトリ構造確認
test -d scripts && test -d tests && echo "PASS" || echo "FAIL"
```

#### Green Phase
```bash
mkdir -p scripts tests
touch claudecode_status.tmux
touch scripts/{shared.sh,claudecode_status.sh,session_tracker.sh}
touch tests/{test_detection.sh,test_status.sh,test_output.sh}
chmod +x claudecode_status.tmux scripts/*.sh tests/*.sh
```

#### Refactor Phase
- shebang追加
- 基本コメント追加

---

### Process 2: 共通ユーティリティ (shared.sh)

#### 目標
tmuxオプションの読み書きと共通関数を提供

#### Red Phase
```bash
# テスト: 関数の存在確認
source scripts/shared.sh
type get_tmux_option &>/dev/null && echo "PASS" || echo "FAIL"
```

#### Green Phase
```bash
#!/usr/bin/env bash
# shared.sh - 共通ユーティリティ

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value="$(tmux show-option -gqv "$option")"
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

set_tmux_option() {
    tmux set-option -gq "$1" "$2"
}

# クロスプラットフォームstat
get_file_mtime() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f %m "$file" 2>/dev/null
    else
        stat -c %Y "$file" 2>/dev/null
    fi
}
```

---

### Process 3: プロセス検出

#### 目標
実行中のClaude Codeプロセスを検出しPID一覧を取得

#### Red Phase
```bash
# テスト: プロセス検出関数
source scripts/session_tracker.sh
result=$(get_claude_pids)
# Claude実行中なら数値のPID、なければ空
```

#### Green Phase
```bash
get_claude_pids() {
    # 方法1: pgrep（最も確実）
    local pids
    pids=$(pgrep -d ' ' "^claude$" 2>/dev/null)

    if [ -z "$pids" ]; then
        # 方法2: ps経由
        pids=$(ps aux | grep -E "node.*claude" | grep -v grep | awk '{print $2}' | tr '\n' ' ')
    fi

    echo "$pids"
}
```

---

### Process 4: セッション追跡 (session_tracker.sh)

#### 目標
各Claude Codeセッションのworking/idle状態を判定

#### 検出ロジック
1. `pgrep` でclaudeプロセスのPID取得
2. 各PIDに対応するdebugファイルを特定
3. debugファイルの更新時刻で状態判定（5秒以内 = working）

#### Red Phase
```bash
# テスト: セッション状態取得
source scripts/session_tracker.sh
result=$(get_session_states)
# 期待: "working:N,idle:M" 形式
```

#### Green Phase
```bash
#!/usr/bin/env bash
# session_tracker.sh - セッション追跡

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"

WORKING_THRESHOLD=5  # 秒

get_session_states() {
    local pids working_count=0 idle_count=0
    pids=$(get_claude_pids)

    if [ -z "$pids" ]; then
        echo "working:0,idle:0"
        return
    fi

    local current_time
    current_time=$(date +%s)

    # debugディレクトリの最新ファイルで判定
    local debug_dir="$HOME/.claude/debug"

    for pid in $pids; do
        local is_working=false

        # /proc/{pid}/fdからdebugファイルを特定（Linux）
        if [ -d "/proc/$pid/fd" ]; then
            local debug_file
            debug_file=$(ls -l "/proc/$pid/fd" 2>/dev/null | grep "$debug_dir" | head -1 | awk '{print $NF}')

            if [ -n "$debug_file" ] && [ -f "$debug_file" ]; then
                local mtime
                mtime=$(get_file_mtime "$debug_file")
                if [ -n "$mtime" ]; then
                    local diff=$((current_time - mtime))
                    if [ "$diff" -lt "$WORKING_THRESHOLD" ]; then
                        is_working=true
                    fi
                fi
            fi
        fi

        # フォールバック: CPU使用率で判定
        if ! $is_working; then
            local cpu
            cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
            if [ -n "$cpu" ] && [ "$(echo "$cpu > 5" | bc 2>/dev/null)" = "1" ]; then
                is_working=true
            fi
        fi

        if $is_working; then
            ((working_count++))
        else
            ((idle_count++))
        fi
    done

    echo "working:$working_count,idle:$idle_count"
}

get_claude_pids() {
    pgrep -d ' ' "^claude$" 2>/dev/null || \
    ps aux | grep -E "node.*claude" | grep -v grep | awk '{print $2}' | tr '\n' ' '
}
```

---

### Process 5: メイン出力 (claudecode_status.sh)

#### 目標
セッション状態をフォーマットしてtmuxステータスバー用に出力

#### 表示形式
```
  ●●○   (アイコン + working×2 + idle×1)
```

#### Red Phase
```bash
# テスト: 出力フォーマット
./scripts/claudecode_status.sh
# 期待: Nerd Fontアイコン + 状態ドット
```

#### Green Phase
```bash
#!/usr/bin/env bash
# claudecode_status.sh - メインステータス出力

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"
source "$CURRENT_DIR/session_tracker.sh"

# デフォルト設定
DEFAULT_ICON=""                    # Nerd Font: robot
DEFAULT_WORKING_DOT="●"
DEFAULT_IDLE_DOT="○"
DEFAULT_WORKING_COLOR="#f97316"    # orange
DEFAULT_IDLE_COLOR="#22c55e"       # green
DEFAULT_ICON_COLOR="#a855f7"       # purple

# キャッシュ設定
CACHE_FILE="/tmp/claudecode_status_cache_$$"
CACHE_TTL=2

main() {
    # キャッシュチェック
    if [ -f "$CACHE_FILE" ]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(get_file_mtime "$CACHE_FILE") ))
        if [ "$cache_age" -lt "$CACHE_TTL" ]; then
            cat "$CACHE_FILE"
            return
        fi
    fi

    # セッション状態取得
    local states
    states=$(get_session_states)

    local working idle
    working=$(echo "$states" | grep -oP 'working:\K[0-9]+')
    idle=$(echo "$states" | grep -oP 'idle:\K[0-9]+')

    # セッションなし
    if [ "$working" = "0" ] && [ "$idle" = "0" ]; then
        echo "" > "$CACHE_FILE"
        cat "$CACHE_FILE"
        return
    fi

    # ユーザー設定読み込み
    local icon working_dot idle_dot working_color idle_color icon_color
    icon=$(get_tmux_option "@claudecode_icon" "$DEFAULT_ICON")
    working_dot=$(get_tmux_option "@claudecode_working_dot" "$DEFAULT_WORKING_DOT")
    idle_dot=$(get_tmux_option "@claudecode_idle_dot" "$DEFAULT_IDLE_DOT")
    working_color=$(get_tmux_option "@claudecode_working_color" "$DEFAULT_WORKING_COLOR")
    idle_color=$(get_tmux_option "@claudecode_idle_color" "$DEFAULT_IDLE_COLOR")
    icon_color=$(get_tmux_option "@claudecode_icon_color" "$DEFAULT_ICON_COLOR")

    # 出力生成
    local output=""
    output+="#[fg=$icon_color]$icon #[default]"

    # workingドット
    for ((i=0; i<working; i++)); do
        output+="#[fg=$working_color]$working_dot#[default]"
    done

    # idleドット
    for ((i=0; i<idle; i++)); do
        output+="#[fg=$idle_color]$idle_dot#[default]"
    done

    echo "$output" > "$CACHE_FILE"
    cat "$CACHE_FILE"
}

main
```

---

### Process 6: TPM統合 (claudecode_status.tmux)

#### 目標
TPMが読み込むエントリーポイントを作成し、`#{claudecode_status}` フォーマット文字列を有効化

#### Red Phase
```bash
# テスト: tmux.confでの読み込み
tmux source-file ~/.tmux.conf
tmux show-option -gqv status-format[1] | grep claudecode
```

#### Green Phase
```bash
#!/usr/bin/env bash
# claudecode_status.tmux - TPMエントリーポイント

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/scripts/shared.sh"

# フォーマット文字列の補間
claudecode_status="#($CURRENT_DIR/scripts/claudecode_status.sh)"
claudecode_status_interpolation="\#{claudecode_status}"

do_interpolation() {
    local string="$1"
    echo "${string/$claudecode_status_interpolation/$claudecode_status}"
}

update_tmux_option() {
    local option="$1"
    local option_value
    option_value="$(get_tmux_option "$option")"
    local new_value
    new_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_value"
}

main() {
    update_tmux_option "status-right"
    update_tmux_option "status-left"
    update_tmux_option "status-format[0]"
    update_tmux_option "status-format[1]"
}

main
```

---

### Process 200: README作成

#### 内容
```markdown
# tmux-claudecode-status

tmuxステータスバーにClaude Codeの実行状態を表示するプラグイン

## 特徴
- 複数セッションの個別追跡
- working/idle状態の色分け表示
- カスタマイズ可能なアイコン・色

## インストール
1. TPMを使用:
   ```bash
   set -g @plugin 'takets/tmux-claudecode-status'
   ```
2. ステータスバーに追加:
   ```bash
   set -g status 2
   set -g status-format[1] '#{claudecode_status}'
   ```

## 設定オプション
| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| @claudecode_icon |  | メインアイコン |
| @claudecode_working_dot | ● | working状態のドット |
| @claudecode_idle_dot | ○ | idle状態のドット |
| @claudecode_working_color | #f97316 | working色（オレンジ） |
| @claudecode_idle_color | #22c55e | idle色（グリーン） |
```

---

## Management

### Blockers
（現時点でなし）

### Lessons
- Claude Codeプロセスは `claude` という名前で実行される
- セッション状態は `~/.claude/debug/*.txt` の更新時刻で判定可能
- tmuxのstatus-formatは配列形式（status-format[0], status-format[1]）

### Feedback Log
| 日時 | ソース | 内容 |
|------|--------|------|
| 2025-12-29 | 調査 | プロセス検出方法確定（pgrep） |
| 2025-12-29 | 調査 | 状態判定方法確定（debugファイル更新時刻） |
| 2025-12-29 | ユーザー | 複数セッション個別追跡が必須要件 |

### Completion Checklist
- [ ] 全テストがパス
- [ ] README完成
- [ ] 実機での動作確認
- [ ] TPMでのインストール確認
