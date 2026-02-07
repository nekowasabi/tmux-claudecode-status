# TDD詳細実装計画: Codex プロセス表示機能

## メタ情報

| 項目 | 値 |
|------|-----|
| 元計画 | `~/.claude/plans/structured-popping-tiger.md` |
| 作成日 | 2026-02-06 |
| 推定フェーズ数 | 6 (Phase 0-5) |
| リスクレベル | medium |
| テストフレームワーク | カスタム bash テスト (assert_equals, assert_matches, assert_contains) |

## 成功条件

1. 全既存テスト (5ファイル, 約50テスト) がパスし続けること
2. 新規テストが全てパスすること
3. Claude のみ起動時に既存の表示が変わらないこと (後方互換性)
4. codex プロセスが検出・表示されること
5. tmux オプションで codex 表示を制御できること

---

## Phase 0: 事前調査

### 目的
codex プロセスの実際の動作を確認し、実装の前提条件を確定する。

### 0.1 実行手順

```bash
# Step 1: codex プロセス情報の収集
codex  # 別ペインで起動

# Step 2: プロセス名の確認
ps -eo pid,comm | grep codex
# 確認: comm フィールドが正確に "codex" か

# Step 3: プロセスツリーの確認
pstree -p <codex_pid>
# 確認: 親プロセスの構造が claude と類似しているか

# Step 4: ファイルディスクリプタの確認
ls -la /proc/<codex_pid>/fd 2>/dev/null
lsof -p <codex_pid> 2>/dev/null | grep -E '\.(log|jsonl|json)'

# Step 5: セッション/ログディレクトリの特定
find ~/.codex -type f 2>/dev/null | head -30
find ~/.config/codex -type f 2>/dev/null | head -30

# Step 6: 作業ディレクトリの確認
readlink /proc/<codex_pid>/cwd 2>/dev/null

# Step 7: 動作状態の変化確認
# codex で何かタスクを実行し、ファイルの mtime 変化を観察
```

### 0.2 確認項目チェックリスト

| # | 確認項目 | 想定値 | 実際の値 | 影響範囲 |
|---|---------|--------|---------|---------|
| 1 | プロセス名 (comm) | `codex` | [要確認] | `_build_pid_pane_map`, `get_all_claude_info_batch` |
| 2 | セッションファイルの場所 | `~/.codex/sessions/` | [要確認] | `get_project_session_dir_cached` |
| 3 | ログ/JSONL ファイルの場所 | 不明 | [要確認] | `check_process_status` (方法3) |
| 4 | 動作状態判定ファイル | 不明 | [要確認] | `check_process_status` |
| 5 | mtime 変化の閾値 | 5秒 (claude と同一) | [要確認] | `WORKING_THRESHOLD` |
| 6 | 複数セッションの管理方法 | ディレクトリベース | [要確認] | `get_project_session_dir_cached` |
| 7 | CWD の取得可否 | `/proc/PID/cwd` | [要確認] | `get_project_name_for_pid` |

### 0.3 記録方法

調査結果を `docs/codex-investigation.md` に記録する。

```markdown
# Codex 動作調査結果

## プロセス情報
- プロセス名 (comm): [実際の値]
- プロセスツリー: [構造の説明]

## ファイルパス
- セッションファイル: [実際のパス]
- ログファイル: [実際のパス]
- 設定ディレクトリ: [実際のパス]

## 動作状態の判定方法
- working 判定: [ファイルと mtime 閾値]
- idle 判定: [条件]

## Claude との差異
- [差異があれば記録]
```

### 0.4 Phase 0 完了判定

- [ ] プロセス名が確定し、awk のマッチ条件が決定できた
- [ ] 動作状態判定に使用するファイルパスが特定できた
- [ ] 調査結果が `docs/codex-investigation.md` に記録された
- [ ] Phase 1 以降の実装を調整する必要があるか判断できた

### 0.5 Phase 0 のリスクと対策

| リスク | 対策 |
|--------|------|
| codex がインストールされていない | モック環境でテスト可能な設計にする |
| セッションファイルが存在しない | TTY mtime ベースの判定で代替 |
| プロセス名が "codex" でない | Phase 0 で正確な名前を特定してから進む |

---

## Phase 1: プロセス検出の拡張 (TDD)

### 対象ファイル
- `scripts/lib/cache_batch.sh`: `_build_pid_pane_map()`, `get_all_claude_info_batch()`
- `scripts/session_tracker.sh`: `get_claude_pids()` + 新関数 `get_ai_pids()`

### 1.1 テストケース作成 (Red)

**新規テストファイル**: `tests/test_codex_detection.sh`

```bash
#!/usr/bin/env bash
# tests/test_codex_detection.sh - Codex detection tests

# --- テストケース一覧 ---

# T1.1: get_ai_pids 関数が存在する
test_get_ai_pids_function_exists() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    assert_function_exists "get_ai_pids" "get_ai_pids function exists"
}

# T1.2: get_ai_pids がフィルターなしで両方を返す
test_get_ai_pids_returns_both_types() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local result
    result=$(get_ai_pids)
    # 結果が空か、数値のスペース区切りであることを確認
    if [ -z "$result" ] || [[ "$result" =~ ^[0-9\ ]+$ ]]; then
        PASS
    else
        FAIL "Invalid format: $result"
    fi
}

# T1.3: get_ai_pids "claude" フィルターが動作する
test_get_ai_pids_claude_filter() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local result
    result=$(get_ai_pids "claude")
    # claude フィルターの結果が空か数値のみ
    if [ -z "$result" ] || [[ "$result" =~ ^[0-9\ ]+$ ]]; then
        PASS
    else
        FAIL
    fi
}

# T1.4: get_ai_pids "codex" フィルターが動作する
test_get_ai_pids_codex_filter() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local result
    result=$(get_ai_pids "codex")
    if [ -z "$result" ] || [[ "$result" =~ ^[0-9\ ]+$ ]]; then
        PASS
    else
        FAIL
    fi
}

# T1.5: get_process_type 関数が存在する
test_get_process_type_function_exists() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    assert_function_exists "get_process_type" "get_process_type function exists"
}

# T1.6: get_process_type_cached 関数が存在する
test_get_process_type_cached_function_exists() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    assert_function_exists "get_process_type_cached" "get_process_type_cached function exists"
}

# T1.7: get_claude_pids は後方互換性を保つ（既存テストとの整合性）
test_get_claude_pids_backward_compatible() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local result
    result=$(get_claude_pids)
    # 既存のフォーマットを維持: 空か数値のスペース区切り
    if [ -z "$result" ] || [[ "$result" =~ ^[0-9\ ]+$ ]]; then
        PASS
    else
        FAIL
    fi
}

# T1.8: batch 出力に process_type フィールドが含まれる
test_batch_output_includes_process_type() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    init_batch_cache
    local result
    result=$(get_all_claude_info_batch)
    # 結果が空でなければ、8フィールド目にprocess_typeがある
    if [ -n "$result" ]; then
        local field_count
        field_count=$(echo "$result" | head -1 | awk -F'|' '{print NF}')
        assert_equals "8" "$field_count" "batch output has 8 fields (including process_type)"
    else
        PASS "No processes running (acceptable)"
    fi
    cleanup_batch_cache
}
```

### 1.2 実装 (Green)

#### Task 1.2.1: `get_ai_pids()` と補助関数を追加
**ファイル**: `scripts/session_tracker.sh` (41行目以降に挿入)

```bash
# AI プロセス（claude + codex）の PID 一覧を取得
# $1: フィルター（オプション: "claude", "codex", 空=両方）
get_ai_pids() {
    local filter="${1:-}"
    local pids=""
    if [ -z "$filter" ]; then
        pids=$(ps -eo pid,comm 2>/dev/null | awk '$2 == "claude" || $2 == "codex" {print $1}' | tr '\n' ' ')
    else
        pids=$(ps -eo pid,comm 2>/dev/null | awk -v f="$filter" '$2 == f {print $1}' | tr '\n' ' ')
    fi
    echo "$pids"
}

get_process_type() {
    local pid="$1"
    ps -p "$pid" -o comm= 2>/dev/null | tr -d ' '
}

get_process_type_cached() {
    local pid="$1"
    if [ -n "$BATCH_PROCESS_TREE_FILE" ] && [ -f "$BATCH_PROCESS_TREE_FILE" ]; then
        awk -v pid="$pid" '{gsub(/^[ \t]+/,""); split($0,f,/[ \t]+/); if(f[1]==pid) print f[3]}' "$BATCH_PROCESS_TREE_FILE"
    else
        get_process_type "$pid"
    fi
}
```

#### Task 1.2.2: `get_claude_pids()` を `get_ai_pids` のラッパーに変更
**ファイル**: `scripts/session_tracker.sh` (既存関数を修正)

- 既存の `get_claude_pids()` 本体を `get_ai_pids "claude"` に委譲
- 関数シグネチャは維持（後方互換性）

#### Task 1.2.3: `_build_pid_pane_map()` で codex も検出
**ファイル**: `scripts/lib/cache_batch.sh` (109-137行目)

変更箇所:
- `if (comm == "claude") claude[pid] = 1` → `if (comm == "claude" || comm == "codex") ai_proc[pid] = comm`
- `for (pid in claude)` → `for (pid in ai_proc)`

#### Task 1.2.4: `get_all_claude_info_batch()` で process_type を出力
**ファイル**: `scripts/lib/cache_batch.sh` (153-184行目)

変更箇所:
- `if(f[3]=="claude") claude_pids[f[1]]=1` → `if(f[3]=="claude" || f[3]=="codex") proc_pids[f[1]]=f[3]`
- 出力行に8番目のフィールドとして `proc_pids[pid]` を追加

### 1.3 リファクタリング

- `get_claude_pids()` の内部実装を `get_ai_pids("claude")` に統一
- 変数名 `claude_pids` → `proc_pids` (awk 内ローカル変数)

### 1.4 検証方法

```bash
# 新規テスト実行
./tests/test_codex_detection.sh

# 既存テスト回帰確認
./tests/test_detection.sh
./tests/test_status.sh
./tests/test_golden_master.sh
```

### 1.5 依存関係

- Phase 0 の調査結果（プロセス名の確定）
- 後続の Phase 2-5 はすべてこの Phase に依存

---

## Phase 2: プロセス識別と動作状態判定の拡張 (TDD)

### 対象ファイル
- `scripts/session_tracker.sh`: `get_project_session_dir_cached()`, `check_process_status()`

### 2.1 テストケース作成 (Red)

**新規テストファイル**: `tests/test_codex_status.sh`

```bash
#!/usr/bin/env bash
# tests/test_codex_status.sh - Codex status detection tests

# T2.1: get_project_session_dir_cached が proc_type 引数を受け取る
test_get_project_session_dir_cached_accepts_proc_type() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    # 存在しないPIDでも引数2個で呼べることを確認（エラーなし）
    local result
    result=$(get_project_session_dir_cached "999999" "claude" 2>&1)
    # エラーが出なければ OK
    PASS
}

# T2.2: get_project_session_dir_cached が claude の場合 ~/.claude/projects を探す
test_session_dir_claude_uses_claude_projects() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    # 現在のシェルPIDで claude タイプを指定
    local result
    result=$(get_project_session_dir_cached $$ "claude")
    # 結果が空か ~/.claude/projects 配下であること
    if [ -z "$result" ] || [[ "$result" == *"/.claude/projects/"* ]]; then
        PASS
    else
        FAIL "Unexpected path: $result"
    fi
}

# T2.3: get_project_session_dir_cached が codex の場合 claude 以外のパスを探す
test_session_dir_codex_uses_codex_path() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local result
    result=$(get_project_session_dir_cached $$ "codex")
    # 結果が空か codex 関連パスであること
    if [ -z "$result" ] || [[ "$result" != *"/.claude/projects/"* ]]; then
        PASS
    else
        FAIL "codex should not use .claude/projects: $result"
    fi
}

# T2.4: check_process_status が codex PID でも working/idle を返す
test_check_process_status_with_codex_type() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local status
    status=$(check_process_status $$ "")
    if [ "$status" = "working" ] || [ "$status" = "idle" ]; then
        PASS
    else
        FAIL "Invalid status: $status"
    fi
}

# T2.5: check_process_status の後方互換性（引数1個で動作）
test_check_process_status_backward_compatible() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    # 既存の呼び出し形式: check_process_status PID
    local status
    status=$(check_process_status $$)
    if [ "$status" = "working" ] || [ "$status" = "idle" ]; then
        PASS
    else
        FAIL
    fi
}
```

### 2.2 実装 (Green)

#### Task 2.2.1: `get_project_session_dir_cached()` にプロセスタイプ分岐を追加
**ファイル**: `scripts/session_tracker.sh` (445-484行目)

- 引数 `$2` に `proc_type` を追加（オプショナル）
- `proc_type` が未指定の場合は `get_process_type_cached` で自動判定
- `case "$proc_type"` で claude/codex のディレクトリパスを分岐
  - `claude`: 既存ロジック (`~/.claude/projects/$encoded_dir`)
  - `codex`: Phase 0 の調査結果に基づくパス

#### Task 2.2.2: `check_process_status()` にプロセスタイプ対応を追加
**ファイル**: `scripts/session_tracker.sh` (489-565行目)

- 方法3 のセッションファイル判定で `proc_type` を `get_project_session_dir_cached` に伝播
- codex 用のファイル検索パターンを追加 (Phase 0 の調査に基づく)

### 2.3 リファクタリング

- `get_project_session_dir` (非キャッシュ版) も同様にプロセスタイプ対応
- 共通のディレクトリ判定ロジックをヘルパー関数に抽出検討

### 2.4 検証方法

```bash
./tests/test_codex_status.sh
./tests/test_status.sh          # 既存回帰
./tests/test_detection.sh       # 既存回帰
```

### 2.5 依存関係

- Phase 0 (codex セッションファイルのパス確定)
- Phase 1 (`get_process_type_cached` が利用可能)

---

## Phase 3: 表示ロジックの変更 (TDD)

### 対象ファイル
- `scripts/claudecode_status.sh`: `main()` 関数
- `scripts/session_tracker.sh`: `get_session_details()`

### 3.1 テストケース作成 (Red)

**新規テストファイル**: `tests/test_codex_display.sh`

```bash
#!/usr/bin/env bash
# tests/test_codex_display.sh - Codex display integration tests

# T3.1: get_session_details の戻り値形式にプロセスタイプが含まれる
test_session_details_includes_process_type() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local details
    details=$(get_session_details)
    if [ -z "$details" ]; then
        PASS "No sessions (acceptable)"
        return
    fi
    # 新形式: process_type:terminal_emoji:pane_index:project_name:status
    # フィールド数が5であること
    local first_entry="${details%%|*}"
    local field_count
    field_count=$(echo "$first_entry" | awk -F: '{print NF}')
    assert_equals "5" "$field_count" "session details has 5 fields"
}

# T3.2: tmux オプション @claudecode_show_codex のデフォルトが "on"
test_show_codex_default_on() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    local result
    result=$(get_tmux_option "@claudecode_show_codex" "on")
    assert_equals "on" "$result" "show_codex defaults to on"
}

# T3.3: tmux オプション @claudecode_codex_icon のデフォルトが "🦾"
test_codex_icon_default() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    local result
    result=$(get_tmux_option "@claudecode_codex_icon" "🦾")
    assert_equals "🦾" "$result" "codex_icon defaults to 🦾"
}

# T3.4: tmux オプション @claudecode_claude_icon のデフォルトが空
test_claude_icon_default_empty() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    local result
    result=$(get_tmux_option "@claudecode_claude_icon" "")
    assert_equals "" "$result" "claude_icon defaults to empty"
}

# T3.5: claudecode_status.sh がエラーなしで実行できる（回帰テスト強化）
test_claudecode_status_no_error() {
    local output
    output=$("$PROJECT_ROOT/scripts/claudecode_status.sh" 2>&1)
    local exit_code=$?
    assert_equals "0" "$exit_code" "claudecode_status.sh exits with 0"
}

# T3.6: get_session_details で codex プロセスの process_type が "codex"
test_session_details_codex_type_value() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    # モック: get_claude_pids を codex も含むように
    # 実際の codex が無い場合はスキップ
    local codex_pids
    codex_pids=$(ps -eo pid,comm 2>/dev/null | awk '$2 == "codex" {print $1}')
    if [ -z "$codex_pids" ]; then
        SKIP "No codex processes running"
        return
    fi
    local details
    details=$(get_session_details)
    assert_contains "codex:" "$details" "session details contains codex type"
}
```

### 3.2 実装 (Green)

#### Task 3.2.1: `get_session_details()` に process_type フィールドを追加
**ファイル**: `scripts/session_tracker.sh` (596-679行目)

変更箇所:
- PID ループ内で `get_process_type_cached "$pid"` を呼び出し
- `show_codex` チェック: codex で show_codex=off ならスキップ
- 出力形式: `terminal_emoji:pane_index:project_name:status` → `process_type:terminal_emoji:pane_index:project_name:status`

#### Task 3.2.2: `get_session_details()` で全 AI プロセスを走査
**ファイル**: `scripts/session_tracker.sh`

- `pids=$(get_claude_pids)` → `pids=$(get_ai_pids)`
- codex プロセスも含めて走査

#### Task 3.2.3: `claudecode_status.sh` の `main()` に新オプションと表示ロジックを追加
**ファイル**: `scripts/claudecode_status.sh` (32-186行目)

変更箇所:
- 新オプション読み込み: `show_codex`, `codex_icon`, `claude_icon`
- パース処理: 5フィールド対応 (`process_type:terminal_emoji:pane_index:project_name:status`)
- プロセスタイプ別アイコンの追加

### 3.3 リファクタリング

- パース処理の共通化（5フィールドパーサーをヘルパー関数化検討）
- プレフィックス構築ロジックの整理

### 3.4 検証方法

```bash
./tests/test_codex_display.sh
./tests/test_output.sh          # 既存回帰
./tests/test_golden_master.sh   # 既存回帰
```

### 3.5 依存関係

- Phase 1 (`get_ai_pids`, `get_process_type_cached`)
- Phase 2 (`check_process_status` の codex 対応)

---

## Phase 4: fzf UI の対応 (TDD)

### 対象ファイル
- `scripts/select_claude.sh`: `generate_process_list()`

### 4.1 テストケース作成 (Red)

**新規テストファイル**: `tests/test_codex_fzf.sh`

```bash
#!/usr/bin/env bash
# tests/test_codex_fzf.sh - Codex fzf UI tests

# T4.1: generate_process_list が process_type 付きの batch_info をパースできる
test_generate_process_list_parses_8_fields() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    source "$PROJECT_ROOT/scripts/select_claude.sh"
    init_batch_cache
    local result
    result=$(generate_process_list)
    # 結果が空か、パイプ区切りのデータ
    if [ -z "$result" ]; then
        PASS "No processes (acceptable)"
    else
        # 各行が6フィールド以上であること
        local field_count
        field_count=$(echo "$result" | head -1 | awk -F'|' '{print NF}')
        if [ "$field_count" -ge 6 ]; then
            PASS
        else
            FAIL "Expected >= 6 fields, got $field_count"
        fi
    fi
    cleanup_batch_cache
}

# T4.2: select_claude.sh がエラーなしで --list モードを実行できる
test_select_claude_list_mode_no_error() {
    local output
    output=$("$PROJECT_ROOT/scripts/select_claude.sh" --list 2>&1)
    local exit_code=$?
    # exit code 0 or 1 (no processes) are both acceptable
    if [ "$exit_code" -le 1 ]; then
        PASS
    else
        FAIL "exit code: $exit_code"
    fi
}

# T4.3: generate_process_list の出力に codex アイコンが含まれる (codex 起動時)
test_generate_process_list_codex_icon() {
    local codex_pids
    codex_pids=$(ps -eo pid,comm 2>/dev/null | awk '$2 == "codex" {print $1}')
    if [ -z "$codex_pids" ]; then
        SKIP "No codex processes running"
        return
    fi
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    source "$PROJECT_ROOT/scripts/select_claude.sh"
    init_batch_cache
    local result
    result=$(generate_process_list)
    assert_contains "🦾" "$result" "codex icon present in process list"
    cleanup_batch_cache
}

# T4.4: generate_process_list の出力にプロセスタイプフィールドがある
test_generate_process_list_has_proc_type_field() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    source "$PROJECT_ROOT/scripts/select_claude.sh"
    init_batch_cache
    local result
    result=$(generate_process_list)
    if [ -z "$result" ]; then
        PASS "No processes (acceptable)"
    else
        # 6番目のフィールドが claude または codex
        local proc_type
        proc_type=$(echo "$result" | head -1 | awk -F'|' '{print $6}')
        if [ "$proc_type" = "claude" ] || [ "$proc_type" = "codex" ]; then
            PASS
        else
            FAIL "Expected claude|codex, got: $proc_type"
        fi
    fi
    cleanup_batch_cache
}
```

### 4.2 実装 (Green)

#### Task 4.2.1: `generate_process_list()` の awk 処理を拡張
**ファイル**: `scripts/select_claude.sh` (45-204行目)

変更箇所:
- batch_info パース: 8番目のフィールド `process_type` を読み取り
- `show_codex` / `codex_icon` / `claude_icon` オプションを取得
- codex プロセスの場合 `codex_icon` プレフィックスを表示行に追加
- 出力の6番目フィールドに `process_type` を追加

#### Task 4.2.2: `sort_process_list()` でプロセスタイプを考慮
- ソートキーにプロセスタイプ優先度を追加（オプション）

### 4.3 リファクタリング

- awk 内のターミナル判定ロジックとプロセスタイプ判定を整理
- `show_codex` == "off" の早期フィルタリング

### 4.4 検証方法

```bash
./tests/test_codex_fzf.sh
./tests/test_preview.sh          # 既存回帰
```

### 4.5 依存関係

- Phase 1 (`get_all_claude_info_batch` の8フィールド出力)
- Phase 3 と並列実行可能（fzf UI は独自の batch_info パスを使用）

---

## Phase 5: 統合テストと文書化 (TDD)

### 対象ファイル
- `tests/test_codex_integration.sh` (新規)
- `README.md`, `README_ja.md`

### 5.1 テストケース作成 (Red)

**新規テストファイル**: `tests/test_codex_integration.sh`

```bash
#!/usr/bin/env bash
# tests/test_codex_integration.sh - End-to-end integration tests

# T5.1: Claude のみの場合、既存の表示形式が変わらない
test_claude_only_backward_compatible() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    # get_ai_pids を claude のみに制限
    get_ai_pids() { ps -eo pid,comm 2>/dev/null | awk '$2 == "claude" {print $1}' | tr '\n' ' '; }
    local details
    details=$(get_session_details)
    if [ -z "$details" ]; then
        PASS "No claude processes (acceptable)"
        return
    fi
    # 4フィールド形式（process_type 含む5フィールドの新形式）
    # 全エントリの process_type が claude
    local all_claude=true
    IFS='|' read -ra entries <<< "$details"
    for entry in "${entries[@]}"; do
        local proc_type="${entry%%:*}"
        if [ "$proc_type" != "claude" ]; then
            all_claude=false
            break
        fi
    done
    if $all_claude; then
        PASS
    else
        FAIL "Non-claude entries found in claude-only mode"
    fi
}

# T5.2: 全テストスイートの一括実行
test_all_existing_tests_pass() {
    local failed=0
    for test_file in "$PROJECT_ROOT"/tests/test_detection.sh \
                     "$PROJECT_ROOT"/tests/test_status.sh \
                     "$PROJECT_ROOT"/tests/test_golden_master.sh \
                     "$PROJECT_ROOT"/tests/test_output.sh \
                     "$PROJECT_ROOT"/tests/test_preview.sh; do
        if [ -x "$test_file" ]; then
            if ! bash "$test_file" > /dev/null 2>&1; then
                echo "FAIL: $test_file"
                failed=1
            fi
        fi
    done
    if [ "$failed" -eq 0 ]; then
        PASS "All existing test suites pass"
    else
        FAIL "Some existing test suites failed"
    fi
}

# T5.3: claudecode_status.sh のパフォーマンス（200ms以内）
test_status_performance() {
    local start end elapsed
    start=$(date +%s%N)
    "$PROJECT_ROOT/scripts/claudecode_status.sh" > /dev/null 2>&1
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))  # ms
    if [ "$elapsed" -lt 200 ]; then
        PASS "Performance: ${elapsed}ms (< 200ms)"
    else
        FAIL "Performance: ${elapsed}ms (>= 200ms threshold)"
    fi
}

# T5.4: README に codex 関連オプションが記載されている
test_readme_documents_codex() {
    if grep -q "codex" "$PROJECT_ROOT/README.md"; then
        PASS
    else
        FAIL "README.md does not mention codex"
    fi
}

# T5.5: README_ja に codex 関連オプションが記載されている
test_readme_ja_documents_codex() {
    if grep -q "codex" "$PROJECT_ROOT/README_ja.md"; then
        PASS
    else
        FAIL "README_ja.md does not mention codex"
    fi
}
```

### 5.2 実装 (Green)

#### Task 5.2.1: README.md に codex セクションを追加
- 新 tmux オプション3つの説明
- 使用例
- codex + claude 同時表示のスクリーンショット説明

#### Task 5.2.2: README_ja.md に同様の変更

### 5.3 検証方法

```bash
# 全テスト一括実行
for f in tests/test_*.sh; do echo "=== $f ==="; bash "$f"; echo; done
```

### 5.4 依存関係

- Phase 1-4 すべて完了後

---

## タスク分解と依存関係 (DAG)

### 依存関係グラフ

```
Phase 0: 事前調査
    │
    ├──→ Phase 1: プロセス検出拡張
    │       │
    │       ├──→ Phase 2: 動作状態判定拡張
    │       │       │
    │       │       └──→ Phase 3: 表示ロジック変更
    │       │               │
    │       │               └──→ Phase 5: 統合テスト・文書化
    │       │
    │       └──→ Phase 4: fzf UI 対応 (Phase 3 と並列可能)
    │               │
    │               └──→ Phase 5: 統合テスト・文書化
    │
    (Phase 0 完了後)
```

### 並列実行可能なタスク

```
Group 1 (Sequential):
  Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 5

Group 2 (Parallel with Phase 3):
  Phase 4 (Phase 1 完了後に開始可能)

並列化ポイント:
  Phase 1 完了後:
    ├── [Agent A] Phase 2 → Phase 3
    └── [Agent B] Phase 4
  両方完了後:
    └── Phase 5
```

### サブタスク詳細一覧

| ID | タスク | フェーズ | 依存 | 推定規模 | ファイル |
|----|--------|---------|------|---------|---------|
| 0.1 | codex プロセス調査 | 0 | なし | small | (手動) |
| 0.2 | 調査結果記録 | 0 | 0.1 | trivial | docs/codex-investigation.md |
| 1.1 | テスト: test_codex_detection.sh 作成 | 1 | 0 | small | tests/test_codex_detection.sh |
| 1.2 | get_ai_pids() 実装 | 1 | 1.1 | small | scripts/session_tracker.sh |
| 1.3 | get_process_type() 実装 | 1 | 1.1 | trivial | scripts/session_tracker.sh |
| 1.4 | _build_pid_pane_map() 修正 | 1 | 1.1 | small | scripts/lib/cache_batch.sh |
| 1.5 | get_all_claude_info_batch() 修正 | 1 | 1.1 | small | scripts/lib/cache_batch.sh |
| 1.6 | get_claude_pids() ラッパー化 | 1 | 1.2 | trivial | scripts/session_tracker.sh |
| 1.7 | Phase 1 テスト実行・確認 | 1 | 1.2-1.6 | trivial | - |
| 2.1 | テスト: test_codex_status.sh 作成 | 2 | 1.7 | small | tests/test_codex_status.sh |
| 2.2 | get_project_session_dir_cached() 修正 | 2 | 2.1 | moderate | scripts/session_tracker.sh |
| 2.3 | check_process_status() 修正 | 2 | 2.1 | moderate | scripts/session_tracker.sh |
| 2.4 | Phase 2 テスト実行・確認 | 2 | 2.2-2.3 | trivial | - |
| 3.1 | テスト: test_codex_display.sh 作成 | 3 | 2.4 | small | tests/test_codex_display.sh |
| 3.2 | get_session_details() 修正 | 3 | 3.1 | moderate | scripts/session_tracker.sh |
| 3.3 | claudecode_status.sh main() 修正 | 3 | 3.1 | moderate | scripts/claudecode_status.sh |
| 3.4 | Phase 3 テスト実行・確認 | 3 | 3.2-3.3 | trivial | - |
| 4.1 | テスト: test_codex_fzf.sh 作成 | 4 | 1.7 | small | tests/test_codex_fzf.sh |
| 4.2 | generate_process_list() 修正 | 4 | 4.1 | moderate | scripts/select_claude.sh |
| 4.3 | Phase 4 テスト実行・確認 | 4 | 4.2 | trivial | - |
| 5.1 | テスト: test_codex_integration.sh 作成 | 5 | 3.4, 4.3 | small | tests/test_codex_integration.sh |
| 5.2 | README.md 更新 | 5 | 5.1 | small | README.md |
| 5.3 | README_ja.md 更新 | 5 | 5.1 | small | README_ja.md |
| 5.4 | 全テスト一括実行・最終確認 | 5 | 5.1-5.3 | trivial | - |

---

## 品質保証計画

### 既存テストの継続的実行

各 Phase の Green (実装) 完了後に必ず以下を実行:

```bash
# 既存テスト全件 (Phase 0 でベースラインを記録)
./tests/test_detection.sh      # 9 tests
./tests/test_status.sh         # 9 tests
./tests/test_golden_master.sh  # 約20 tests
./tests/test_output.sh         # 9 tests
./tests/test_preview.sh        # 11 tests
```

### 新規テストの実行

| Phase | テストファイル | テスト数 (予定) |
|-------|--------------|----------------|
| 1 | `tests/test_codex_detection.sh` | 8 |
| 2 | `tests/test_codex_status.sh` | 5 |
| 3 | `tests/test_codex_display.sh` | 6 |
| 4 | `tests/test_codex_fzf.sh` | 4 |
| 5 | `tests/test_codex_integration.sh` | 5 |
| **合計** | | **28** |

### パフォーマンステスト

```bash
# claudecode_status.sh の実行時間 (目標: < 200ms)
time ./scripts/claudecode_status.sh

# select_claude.sh --list の実行時間 (目標: < 300ms)
time ./scripts/select_claude.sh --list
```

### 統合テストシナリオ

| # | シナリオ | 期待結果 |
|---|---------|---------|
| S1 | Claude のみ起動 | 既存と同一の表示 |
| S2 | Codex のみ起動 | 🦾 アイコン付きで表示 |
| S3 | 両方起動 | 両方が表示、ソート正常 |
| S4 | `@claudecode_show_codex off` | Codex 非表示 |
| S5 | カスタムアイコン設定 | 設定アイコンで表示 |
| S6 | fzf UI で codex 選択 | 正しいペインにフォーカス移動 |

---

## リスクマトリクス

| リスク | 確率 | 影響度 | 軽減策 |
|--------|------|--------|--------|
| codex セッションファイルが存在しない | medium | high | TTY mtime ベースの判定にフォールバック |
| プロセス名が "codex" でない | low | high | Phase 0 で正確に特定 |
| 既存テストの破損 | medium | critical | 各 Phase で全回帰テスト実行 |
| パフォーマンス劣化 (2倍のプロセス走査) | medium | medium | awk 一括処理、キャッシュ活用 |
| awk フィールド数変更による下流影響 | medium | high | 後方互換フィールド順序を維持、末尾にのみ追加 |
| Bash 3.2 互換性の破損 | low | medium | macOS + Linux 両方でテスト |

---

## TDD サイクルまとめ

各 Phase の実行フロー:

```
┌─────────────────────────────────────────────┐
│  1. Red: テストファイル作成                    │
│     → テスト実行 → 全て FAIL を確認           │
│                                               │
│  2. Green: 最小限の実装                       │
│     → テスト実行 → 新規テスト PASS を確認     │
│     → 既存テスト実行 → 回帰なし確認           │
│                                               │
│  3. Refactor: コード品質改善                  │
│     → テスト実行 → 全て PASS 維持を確認       │
│                                               │
│  4. Commit: Phase 完了コミット                │
│     → コミットメッセージに Phase 番号記載     │
└─────────────────────────────────────────────┘
```

### コミット計画

| Phase | コミットメッセージ |
|-------|-------------------|
| 0 | `docs: codex プロセス動作調査結果を記録` |
| 1 | `feat: codex プロセスの検出機能を追加 (Phase 1)` |
| 2 | `feat: codex プロセスの動作状態判定を追加 (Phase 2)` |
| 3 | `feat: codex プロセスの表示ロジックを追加 (Phase 3)` |
| 4 | `feat: fzf UI で codex プロセスを表示 (Phase 4)` |
| 5 | `docs: codex 表示機能のドキュメントを更新 (Phase 5)` |

---

## 変更ファイル一覧 (全体)

| ファイル | 変更種別 | Phase |
|----------|---------|-------|
| `docs/codex-investigation.md` | 新規 | 0 |
| `tests/test_codex_detection.sh` | 新規 | 1 |
| `scripts/session_tracker.sh` | 修正 | 1, 2, 3 |
| `scripts/lib/cache_batch.sh` | 修正 | 1 |
| `tests/test_codex_status.sh` | 新規 | 2 |
| `tests/test_codex_display.sh` | 新規 | 3 |
| `scripts/claudecode_status.sh` | 修正 | 3 |
| `tests/test_codex_fzf.sh` | 新規 | 4 |
| `scripts/select_claude.sh` | 修正 | 4 |
| `tests/test_codex_integration.sh` | 新規 | 5 |
| `README.md` | 修正 | 5 |
| `README_ja.md` | 修正 | 5 |
