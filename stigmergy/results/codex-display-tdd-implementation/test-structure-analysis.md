# 既存テスト構造分析 - Codex対応TDD実装

## 1. 既存テストファイル概要

### 1.1 test_detection.sh - 機能検出テスト
**ファイルパス**: `/home/takets/repos/tmux-claudecode-status/tests/test_detection.sh`

**構造**:
- テスト対象: スクリプトファイルの存在確認、関数の存在確認
- テストケース: 9個
  - `test_shared_sh_exists`: shared.sh の実行可能性確認
  - `test_session_tracker_exists`: session_tracker.sh の実行可能性確認
  - `test_shared_functions_exist`: 共通関数の存在確認（get_tmux_option, set_tmux_option, get_file_mtime, get_current_timestamp）
  - `test_session_tracker_functions_exist`: セッション追跡関数の存在確認（get_claude_pids, check_process_status, get_session_states）
  - `test_get_claude_pids_returns_format`: PID返却形式検証（空またはスペース区切り数値）
  - `test_get_session_states_format`: セッション状態形式検証（working:N,idle:M）
  - `test_get_file_mtime`: ファイル変更時刻の取得検証
  - `test_get_current_timestamp`: 現在タイムスタンプの取得検証
  - `test_check_process_status_returns_valid_state`: プロセスステータス返却値検証

**使用技術**:
- **アサーション方法**:
  - `assert_equals()`: 期待値と実際の値の比較
  - `assert_not_empty()`: 値が空でないかの確認
  - `assert_function_exists()`: bash関数の存在確認（`type`コマンド使用）
  - `assert_file_executable()`: ファイルの実行可能性確認（`test -x`）
- **テスト統計**: TESTS_RUN, TESTS_PASSED, TESTS_FAILED を自動計数
- **カラー出力**: GREEN(PASS), RED(FAIL), YELLOW(見出し)
- **セットアップ/クリーンアップ**: setup()とteardown()関数でサマリー表示

---

### 1.2 test_status.sh - ステータス取得テスト
**ファイルパス**: `/home/takets/repos/tmux-claudecode-status/tests/test_status.sh`

**構造**:
- テスト対象: プロセス状態検出とセッション状態の集約
- テストケース: 9個
  - `test_get_session_states_format`: セッション状態フォーマット検証（working:N,idle:M）
  - `test_get_session_states_with_no_processes`: 空プロセスリスト時の挙動（期待値: working:0,idle:0）
  - `test_check_process_status_returns_valid_state`: プロセスステータス検証（working|idle）
  - `test_check_process_status_nonexistent_pid`: 存在しないPID時の挙動（期待値: idle）
  - `test_working_threshold_env_var`: CLAUDECODE_WORKING_THRESHOLD環境変数の処理確認
  - `test_session_states_numbers_are_valid`: セッション状態の数値が非負であることの確認
  - `test_multiple_check_process_status_calls`: 同一PIDへの複数呼び出しの一貫性
  - `test_session_tracker_handles_empty_pids`: 空PIDリストの安全な処理
  - `test_session_states_are_numeric`: セッション状態値の数値確認

**使用技術**:
- **アサーション方法**:
  - `assert_equals()`: 期待値とマッチング
  - `assert_matches()`: 正規表現パターンマッチング
- **モック機能**: `get_claude_pids()` をモック関数で置き換え
- **環境変数テスト**: CLAUDECODE_WORKING_THRESHOLD の読み込み確認
- **数値パース**: awkでセッション状態から数値を抽出

---

### 1.3 test_golden_master.sh - ゴールデンマスター回帰テスト
**ファイルパス**: `/home/takets/repos/tmux-claudecode-status/tests/test_golden_master.sh`

**構造**:
- テスト対象: 既存の実装動作をキャプチャし、リファクタリング後も動作が変わらないことを確認
- テストケース: 20個以上
  - **プラットフォーム関数テスト** (6個): get_os, get_current_timestamp, get_file_mtime
  - **tmuxオプション関数テスト** (3個): get_tmux_option, get_tmux_option_cached, キャッシュ処理
  - **優先度関数テスト** (12個): ターミナル優先度、ステータス優先度
  - **絵文字関数テスト** (1個): get_terminal_emoji
  - **キャッシュ関数テスト** (1個): キャッシュ未作成時の処理

**使用技術**:
- **アサーション方法**: assert_equals(), assert_matches(), assert_numeric()
- **カスタムアサーション**: assert_numeric() で数値フォーマット検証
- **環境管理**: 一時ファイル作成/削除（mktemp, rm -f）
- **数値範囲チェック**: タイムスタンプの合理性検証（2020-2100年）
- **絵文字テスト**: Unicode絵文字の直接テスト

---

### 1.4 test_output.sh - 出力フォーマットテスト
**ファイルパス**: `/home/takets/repos/tmux-claudecode-status/tests/test_output.sh`

**構造**:
- テスト対象: claudecode_status.sh のスクリプト実行と出力フォーマット
- テストケース: 9個
  - claudecode_status.sh の実行可能性確認
  - 出力フォーマット（tmux カラーコード）確認
  - ステータスドット（● ○）確認
  - プラグイン構造確認（ファイル存在、関数定義、dependencies）

**使用技術**:
- **grep検索**: 静的なファイル内容確認（grep -q）
- **スクリプト実行**: 実際のスクリプト実行による動的テスト
- **アサーション方法**: assert_equals(), assert_matches(), assert_contains()
- **出力検証**: tmux形式コード、絵文字の存在確認
- **エラーハンドリング**: stderr/stdout を統合キャプチャ

---

### 1.5 test_preview.sh - プレビューペイン機能テスト
**ファイルパス**: `/home/takets/repos/tmux-claudecode-status/tests/test_preview.sh`

**構造**:
- テスト対象: preview_pane.sh, select_claude_launcher.sh, select_claude.sh
- テストケース: 11個
  - スクリプト実行可能性テスト
  - 環境変数処理テスト（CLAUDECODE_PANE_DATA）
  - マルチラインデータ処理
  - 特殊文字・絵文字の処理

**使用技術**:
- **アサーション方法**: assert_equals(), assert_contains()
- **環境変数管理**: export/unset CLAUDECODE_PANE_DATA
- **マルチラインデータ処理**: newline(\n) で複数行をつなぐ
- **テンポラリファイル**: mktemp を使用した一時ファイル作成
- **paste コマンド**: タブ区切りデータの結合

---

## 2. テスト実行方法

### 2.1 個別テストの実行
```bash
bash tests/test_detection.sh
bash tests/test_status.sh
bash tests/test_golden_master.sh
bash tests/test_output.sh
bash tests/test_preview.sh
```

### 2.2 全テストの実行
```bash
for test_file in tests/test_*.sh; do
    echo "Running $test_file..."
    bash "$test_file" || exit 1
done
```

### 2.3 テスト依存関係
- すべてのテストが PROJECT_ROOT を基準に相対パスで参照
- shared.sh と session_tracker.sh の sourcing が必須
- テスト実行時に /tmp に一時ファイルを作成（権限必須）

---

## 3. モックとフィクスチャの実装パターン

### 3.1 関数モック
```bash
# 元の関数をバックアップして置き換え
original_get_claude_pids=$(declare -f get_claude_pids)

# モック実装
get_claude_pids() {
    echo ""
}

# テスト実行
result=$(get_session_states)

# 復元
eval "$original_get_claude_pids"
```

### 3.2 テンポラリファイル
```bash
# テスト用一時ファイル作成
tmp_file="/tmp/test_mtime_$$"
touch "$tmp_file"

# テスト処理
mtime=$(get_file_mtime "$tmp_file")

# クリーンアップ
rm -f "$tmp_file"
```

### 3.3 環境変数フィクスチャ
```bash
# テスト前: 環境変数を保存
original_threshold="$WORKING_THRESHOLD"

# テスト: 新しい値を設定
CLAUDECODE_WORKING_THRESHOLD=10

# テスト後: 復元
WORKING_THRESHOLD="$original_threshold"
```

### 3.4 データフォーマットの例
```bash
# セッション状態形式
working:0,idle:0
working:2,idle:1

# PANE_DATA形式（タブ区切り）
  #0 project [session] working	%123
  #1 other-project [test] idle	%456
```

---

## 4. Codex対応に必要な新規テスト設計

### 4.1 テスト対象となるCodex機能

**背景**: 現在のシステムは Claude Code のプロセス検出と状態追跡に特化。Codex対応では、複数プロセスタイプの識別と表示が必要。

#### 4.1.1 プロセス検出と識別（新規）

**テストケース**:
1. `test_get_process_type_returns_claude_or_codex()`
   - 期待: get_process_type() が "claude" または "codex" を返す
   
2. `test_get_codex_pids_returns_valid_format()`
   - 期待: get_codex_pids() がスペース区切りPIDを返すか空を返す
   
3. `test_get_mixed_process_pids_claude_and_codex()`
   - 期待: claude と codex プロセスを同時に検出
   - 実装例:
   ```bash
   get_claude_pids() { echo "1234 5678"; }
   get_codex_pids() { echo "9012"; }
   result=$(get_all_process_pids)
   assert_contains "1234" "$result"
   assert_contains "9012" "$result"
   ```

#### 4.1.2 プロセスタイプごとの状態判定（新規）

**テストケース**:
4. `test_check_process_status_with_type()`
   - 期待: check_process_status_typed(pid, type) が型に応じた状態を返す
   
5. `test_get_session_states_typed()`
   - 期待形式: `claude:working:2,claude:idle:1,codex:working:1,codex:idle:0`
   - パース例:
   ```bash
   assert_matches "^claude:working:[0-9]+,claude:idle:[0-9]+,codex:working:[0-9]+,codex:idle:[0-9]+$" "$result"
   ```

6. `test_get_session_states_typed_with_only_claude()` / `test_get_session_states_typed_with_only_codex()`
   - 期待: 片方のプロセスタイプが存在しないときもエラーなく処理

#### 4.1.3 プロセスタイプ別の表示（新規）

**テストケース**:
7. `test_get_process_icon_claude()` / `test_get_process_icon_codex()`
   - 期待: 型別アイコン（@claudecode_codex_icon 新規オプション）
   
8. `test_claudecode_status_shows_typed_dots()`
   - 期待: 出力に claude と codex それぞれのドットが含まれる
   
9. `test_claudecode_status_typed_colors()`
   - 期待: type-specific color が tmux format codes に含まれる

#### 4.1.4 フォーマット・キャッシング（新規）

**テストケース**:
10. `test_typed_session_states_cache_hits()`
    - 期待: 同一TTY/タイムスタンプではキャッシュを再利用
    
11. `test_claudecode_status_typed_cache_validity()`
    - 期待: キャッシュが有効期間内（TTL）はキャッシュ値を返す

---

## 5. テストファーストの実装順序

### Phase 1: 基本的な型識別（Week 1）

**実装順序**:
1. `test_get_process_type_returns_claude_or_codex`
   - 依存: session_tracker.sh に get_process_type(pid) を追加
   - テストファイル: tests/test_detection.sh
   
2. `test_get_codex_pids_returns_valid_format`
   - 依存: session_tracker.sh に get_codex_pids() を追加
   - テストファイル: tests/test_detection.sh
   
3. `test_get_mixed_process_pids_claude_and_codex`
   - 依存: get_all_process_pids() を追加
   - テストファイル: tests/test_detection.sh

### Phase 2: 状態判定の型別化（Week 2）

**実装順序**:
4. `test_check_process_status_with_type` → check_process_status_typed(pid, type)
   - 依存: session_tracker.sh の check_process_status() を拡張
   - テストファイル: tests/test_status.sh
   
5. `test_get_session_states_typed` → get_session_states_typed()
   - 依存: 型別集約関数を追加
   - テストファイル: tests/test_status.sh
   
6. `test_get_session_states_typed_with_only_claude` / codex
   - テストファイル: tests/test_status.sh

### Phase 3: 出力・表示の型別化（Week 3）

**実装順序**:
7. `test_get_process_icon_claude` / `test_get_process_icon_codex`
   - 依存: claudecode_status.sh に get_process_icon(type) を追加
   - テストファイル: tests/test_output.sh
   - 設定項目: @claudecode_codex_icon（新規）
   
8. `test_claudecode_status_shows_typed_dots`
   - 依存: 出力フォーマット関数の拡張
   - テストファイル: tests/test_output.sh
   
9. `test_claudecode_status_typed_colors`
   - 依存: @claudecode_codex_working_color, @claudecode_codex_idle_color（新規）
   - テストファイル: tests/test_output.sh

### Phase 4: パフォーマンス・安定性（Week 4）

**実装順序**:
10. `test_typed_session_states_cache_hits`
    - 依存: キャッシュロジックの型別対応
    - テストファイル: tests/test_golden_master.sh
    
11. `test_claudecode_status_typed_cache_validity`
    - テストファイル: tests/test_golden_master.sh

---

## 6. テスト実装で参考にすべき既存パターン

### 6.1 関数存在確認パターン
```bash
test_typed_functions_exist() {
    echo -e "${YELLOW}--- Test: Typed functions exist ---${NC}"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    
    assert_function_exists "get_process_type" "get_process_type function exists"
    assert_function_exists "get_codex_pids" "get_codex_pids function exists"
    assert_function_exists "get_session_states_typed" "get_session_states_typed function exists"
}
```

### 6.2 正規表現パターンマッチング
```bash
test_get_session_states_typed_format() {
    echo -e "${YELLOW}--- Test: Typed session states format ---${NC}"
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    
    local result
    result=$(get_session_states_typed)
    
    # パターン: claude:working:N,claude:idle:M,codex:working:P,codex:idle:Q
    assert_matches "^claude:working:[0-9]+,claude:idle:[0-9]+,codex:working:[0-9]+,codex:idle:[0-9]+$" "$result" \
        "Format matches typed pattern"
}
```

### 6.3 モック置き換えパターン
```bash
test_mixed_pids_with_mock() {
    echo -e "${YELLOW}--- Test: Mixed Claude and Codex PIDs ---${NC}"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    
    original_get_claude=$(declare -f get_claude_pids)
    original_get_codex=$(declare -f get_codex_pids)
    
    get_claude_pids() { echo "1234 5678"; }
    get_codex_pids() { echo "9012"; }
    
    local result
    result=$(get_all_process_pids)
    
    assert_contains "1234" "$result"
    assert_contains "9012" "$result"
    
    eval "$original_get_claude"
    eval "$original_get_codex"
}
```

---

## 7. テスト実装時の注意点

### 7.1 複雑性管理
- **関数単位テスト**: 各機能は5～10個のテストケースに限定
- **統合テスト**: 実際のプロセスが存在しない環境ではモックを使用必須
- **段階的検証**: 低レベルテスト（型識別）→ 高レベルテスト（出力）の順

### 7.2 環境依存性
- **PID/プロセス**: ps コマンド実行可能な環境が必須
- **tmux**: プレビュー関連テスト以外では不要（ただしオプション取得時は必須）
- **一時ファイル**: /tmp への書き込み権限が必須

### 7.3 テスト実行時間
- **目標**: 各テストファイル < 5秒
- **最適化**: 不要なプロセス生成を避け、モックを活用
- **キャッシング**: 同一プロセス情報への複数アクセスはキャッシュで最適化

### 7.4 CI/CD 統合
```bash
#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# 全テスト実行
for test in tests/test_*.sh; do
    echo "===== Running $test ====="
    bash "$test" || exit 1
done

echo "===== All tests passed ====="
```

---

## 8. 開発工程でのテスト実行タイミング

### 開発サイクル
1. **テスト作成** (Red phase)
   - 新機能用テストを `tests/test_*.sh` に追加
   - テスト実行: `bash tests/test_*.sh` → FAIL を確認

2. **実装** (Green phase)
   - `scripts/*.sh` に関数/ロジックを実装
   - テスト実行: `bash tests/test_*.sh` → PASS を確認

3. **リファクタリング** (Refactor phase)
   - ゴールデンマスターテストで回帰確認
   - テスト実行: `bash tests/test_golden_master.sh` → PASS を確認

4. **統合テスト** (Integration phase)
   - 複数機能の組み合わせテスト
   - 実際のプロセス環境で動作確認

---

## 9. まとめ：Codex対応テスト実装への推奨事項

### 推奨度 ★★★★★ - 必須実装
- フェーズ1のテスト群: プロセス型識別は基盤機能
- 既存テストパターンの再利用: assert_* 関数、モック機能、環境変数管理

### 推奨度 ★★★★☆ - 高優先度
- 状態判定の型別化テスト: ビジネスロジック検証
- ゴールデンマスター拡張: 回帰テスト充実

### 推奨度 ★★★☆☆ - 中優先度
- 出力テスト: UI検証

### リスク・注意点
- **プロセス環境への依存**: get_process_type() の実装は OS / ps コマンドの仕様に依存
- **パフォーマンス**: get_codex_pids() + get_claude_pids() の並行実行で遅延が増加する可能性
- **キャッシング戦略**: 型別状態の更新頻度がモニタリング必須

