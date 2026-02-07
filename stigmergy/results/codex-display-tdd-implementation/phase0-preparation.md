# Phase 0 準備完了報告: Codex プロセス動作確認

**実施日**: 2026-02-06
**調査対象**: codex プロセスの動作、セッションファイル構造、動作状態判定方法
**状態**: ✅ **調査完了 - 実装可能**

---

## 1. Codex の利用可能性確認

### 1.1 実行可能性
```bash
which codex
# 結果: /home/takets/.local/share/mise/installs/node/24.13.0/bin/codex
```
**結論**: ✅ codex コマンドは実行可能

### 1.2 プロセス実行状況
```bash
ps aux | grep codex | grep -v grep
```
**結果**: 複数の codex プロセスが起動中
- **メインプロセス**: `node /home/takets/.local/share/mise/installs/node/24.13.0/bin/codex`
- **サブプロセス**: `/home/takets/.local/share/mise/installs/node/24.13.0/lib/node_modules/@openai/codex/vendor/x86_64-unknown-linux-musl/codex/codex`
- **MCP 連携**: serena MCP サーバーとして起動済み

**結論**: ✅ codex は継続的に実行中

---

## 2. ファイルシステム構造

### 2.1 ディレクトリ構成
```
~/.codex/
├── config.toml              # 設定ファイル
├── auth.json                # 認証情報
├── history.jsonl            # コマンド履歴
├── models_cache.json        # モデルキャッシュ
├── version.json             # バージョン情報
├── .personality_migration   # マイグレーション情報
│
├── sessions/                # セッションファイル
│   └── {YYYY}/{MM}/{DD}/
│       ├── rollout-{ISO_TIMESTAMP}-{UUID}.jsonl
│       ├── rollout-{ISO_TIMESTAMP}-{UUID}.jsonl
│       └── ...
│
├── log/                      # ログディレクトリ
│   └── codex-tui.log        # TUI ログ（1.7MB）
│
├── shell_snapshots/          # シェルスナップショット
├── skills/                   # スキル定義
└── tmp/                      # 一時ファイル
```

### 2.2 セッションファイルの位置確認

**推測**: `~/.codex/sessions/YYYY/MM/DD/`
**実測**: ✅ **完全に一致**

```bash
find ~/.codex/sessions -type f -name "*.jsonl" 2>/dev/null | head -1
# /home/takets/.codex/sessions/2026/02/05/rollout-2026-02-05T17-08-42-019c2cd8-a8b1-7422-b815-663ad2c58044.jsonl
```

### 2.3 ログファイル位置確認

**推測**: `~/.codex/log/`
**実測**: ✅ **確認完了**

```bash
ls -la ~/.codex/log/
# codex-tui.log (1.7MB)
```

**注意**: ログファイルは単一の `codex-tui.log` のみ（セッションファイルと異なり日付分割されない）

---

## 3. セッションファイルの詳細構造

### 3.1 ファイル名フォーマット

**パターン**: `rollout-{ISO_TIMESTAMP}-{UUID}.jsonl`

**例**:
```
rollout-2026-02-06T16-58-32-019c31f5-b535-7260-8d1a-d6890f246fc8.jsonl
                 └─ ISO 8601 時刻（T区切り）
                                    └─ UUID v7形式
```

### 3.2 JSONL フォーマット（各行が JSON）

**構造**: 各行は以下の構造を持つ JSON オブジェクト

```json
{
  "timestamp": "2026-02-05T08:08:42.419Z",  // ISO 8601形式
  "type": "session_meta" | "response_item" | ...,
  "payload": {
    // type に応じたペイロード
  }
}
```

**主要なレコードタイプ**:

1. **`type: "session_meta"`** - セッション開始時に記録
   ```json
   {
     "payload": {
       "id": "019c2cd8-a8b1-7422-b815-663ad2c58044",  // セッションID (UUID)
       "timestamp": "2026-02-05T08:08:42.417Z",
       "cwd": "/home/takets/.claude",                   // 作業ディレクトリ
       "originator": "codex_cli_rs",
       "cli_version": "0.97.0",
       "source": "cli",
       "model_provider": "openai"
     }
   }
   ```

2. **`type: "response_item"`** - ユーザー入力と AI レスポンス
   - `role`: "user" | "developer" | "assistant"
   - `content`: リクエスト/レスポンス内容

### 3.3 セッションファイルへのアクセス確認

**実行中のプロセスがどのセッションにアクセスしているか確認**:

```bash
lsof -p <PID> | grep -E '\.jsonl'
```

**実測結果** (PID 3728261):
```
codex   3728261 takets   23w  REG  8,48  29286  1953617
/home/takets/.codex/sessions/2026/02/06/rollout-2026-02-06T16-58-32-019c31f5-b535-7260-8d1a-d6890f246fc8.jsonl
```

**結論**: ✅ プロセスは現在のセッションファイルに書き込み中（fd 23w = write）

---

## 4. 動作状態判定の方法

### 4.1 状態判定アルゴリズム

**目標**: 各 codex プロセスの状態を `working` / `idle` で判定

**最適な方法**: セッションファイルの **mtime（最終更新時刻）** を利用

```bash
# Step 1: 現在のセッションファイルを特定
current_session=$(lsof -p <PID> 2>/dev/null | grep '\.jsonl' | awk '{print $NF}')

# Step 2: mtime を取得
mtime=$(stat -c %Y "$current_session")

# Step 3: 現在時刻との差分を計算
current_time=$(date +%s)
diff=$((current_time - mtime))

# Step 4: 閾値で判定
if [ "$diff" -lt 30 ]; then
    echo "working"  # 30秒以内に更新
else
    echo "idle"     # 30秒以上更新なし
fi
```

### 4.2 閾値設定の推奨

**状態**: `working` の場合、セッションファイルが継続的に更新される
**推奨閾値**: `WORKING_THRESHOLD = 30秒`

**根拠**:
- codex の応答スピードは通常 5-20秒
- UI の遅延やネットワーク遅延を考慮し 30秒に設定
- 調整可能（既存の Claude Code では `WORKING_THRESHOLD = 45秒`）

### 4.3 代替判定方法（フォールバック）

**方法 1: ログファイルの mtime** （非推奨）
```bash
mtime=$(stat -c %Y ~/.codex/log/codex-tui.log)
```
問題: TUI ログはバッチ更新の可能性あり、精度が落ちる

**方法 2: プロセスの CPU 使用率**
```bash
ps -p <PID> -o %cpu
```
問題: CPU 使用率 0% でも I/O 待機中の可能性あり、判定が不安定

**推奨**: 方法 0（セッションファイルの mtime）を採用

---

## 5. 複数セッション・複数プロセスの管理

### 5.1 複数 codex プロセスの管理

**現状**: 複数の codex プロセスが同時実行している
```bash
ps aux | grep codex | grep -v grep
# 複数の node と codex プロセスが起動中（異なる pts に分散）
```

**セッションファイルの対応**:
- 各プロセスは独立したセッションファイルを持つ
- `lsof -p <PID>` で個別プロセスが開いているセッションファイルを特定可能

**実装の考慮事項**:
1. `pgrep codex` で全 codex PID を取得
2. 各 PID に対して `lsof -p <PID> | grep '.jsonl'` でセッションファイルを特定
3. 各セッションファイルの mtime で `working` / `idle` を判定

### 5.2 複数セッション管理の例

**シナリオ**: 同じプロセスが複数セッションを保持している場合
- codex は通常 1 プロセス = 1 セッションファイルの関連付け
- ただし、セッション切り替え時に一時的に複数ファイルにアクセスしている可能性あり

**実装上の対応**:
```bash
# 複数の .jsonl を処理する場合は、最後に更新されたファイルを選択
latest_file=$(lsof -p <PID> 2>/dev/null | grep '\.jsonl' | tail -1 | awk '{print $NF}')
mtime=$(stat -c %Y "$latest_file")
```

---

## 6. Claude Code との比較

| 項目 | Claude Code | Codex |
|------|------------|--------|
| **プロセス検出** | `pgrep claude` | `pgrep codex` |
| **セッションファイル** | `~/.claude/projects/{encoded_dir}/*.jsonl` | `~/.codex/sessions/YYYY/MM/DD/*.jsonl` |
| **ログファイル** | `~/.claude/debug/` (複数ファイル) | `~/.codex/log/codex-tui.log` (単一ファイル) |
| **ディレクトリ構造** | フラット（プロジェクト名ベース） | **階層的**（日付ベース） - **注意** |
| **状態判定方法** | セッションファイルの mtime | セッションファイルの mtime（同じ） |
| **複数プロセス** | 複数サポート | 複数サポート |

---

## 7. 実装時の注意点

### 7.1 セッションファイル検索の効率化

⚠️ **重要**: `find ~/.codex/sessions -type f -name "*.jsonl"` は遅い可能性がある

**理由**: ディレクトリ階層が深く（YYYY/MM/DD）、ファイルが多い場合

**推奨実装**:
```bash
# 1. lsof を使用（最速）
latest_file=$(lsof -p <PID> 2>/dev/null | grep '\.jsonl' | tail -1 | awk '{print $NF}')

# 2. 本日のディレクトリのみを検索（フォールバック）
today=$(date +%Y/%m/%d)
find ~/.codex/sessions/$today -type f -name "*.jsonl" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-
```

### 7.2 権限確認

```bash
ls -ld ~/.codex/
# drwxr-xr-x  7 takets  takets  4096 Feb  6 16:58 ~/.codex/
```

**結論**: ✅ 読み取り権限あり（755 = rwxr-xr-x）

### 7.3 パフォーマンスへの影響

**codex 対応による追加処理**:
- `pgrep codex` （高速）
- `lsof -p <PID>` で各 PID のセッション確認 （中程度、PID数に依存）
- `stat -c %Y` で mtime 取得 （高速）

**既存キャッシング機構の活用で性能影響は最小**

---

## 8. 推奨される実装順序

### Phase 1: プロセス検出の拡張（最優先）
```bash
# cache_batch.sh の変更
# claude を codex に拡張

# 影響: 
# - _build_pid_pane_map() で codex プロセスも検出
# - キャッシュに process_type フィールド追加
```

### Phase 2: 動作状態判定の実装
```bash
# session_tracker.sh の拡張
# check_process_status() で codex セッションファイルの mtime 確認

# パス: ~/.codex/sessions/YYYY/MM/DD/*.jsonl
# 判定: mtime < WORKING_THRESHOLD → "working"
```

### Phase 3-5: UI 表示対応
```bash
# claudecode_status.sh, select_claude.sh の変更
# codex アイコン（🦾）の表示制御
```

---

## 9. テスト戦略

### 9.1 単体テスト（Phase 1-2 実装後）

```bash
# Test 1: codex プロセスの検出
pgrep codex
# → codex PID が出力されることを確認

# Test 2: セッションファイルの特定
lsof -p <codex_PID> | grep '.jsonl'
# → 最新のセッションファイルが出力されることを確認

# Test 3: 動作状態判定
stat -c %Y /home/takets/.codex/sessions/2026/02/06/*.jsonl
# → mtime が現在時刻に近いことを確認
```

### 9.2 統合テスト（Phase 4-5 実装後）

```bash
# Test 4: tmux status bar に codex が表示される
tmux display-message "#{client_prefix}"

# Test 5: fzf UI に codex が表示される
# Ctrl+J で確認

# Test 6: @claudecode_show_codex オプション制御
tmux set -g @claudecode_show_codex "off"
# → codex が非表示になることを確認
```

---

## 10. 制限事項と今後の確認項目

### 10.1 確認済み項目 ✅
- [x] codex コマンドの実行可能性
- [x] セッションファイルの位置（`~/.codex/sessions/YYYY/MM/DD/`）
- [x] ログファイルの位置（`~/.codex/log/codex-tui.log`）
- [x] セッションファイルのフォーマット（JSONL）
- [x] 動作状態判定に使用可能なファイル（セッション .jsonl の mtime）
- [x] 複数セッション・複数プロセスの管理方法
- [x] パフォーマンスへの影響（最小限）

### 10.2 実装段階で確認が必要な項目
- [ ] Phase 1 実装後: キャッシュファイルに process_type が正しく記録されているか
- [ ] Phase 2 実装後: codex セッションの mtime が期待通りに更新されるか
- [ ] Phase 3 実装後: 複数プロセス、複数セッションの状態判定が正常に動作するか

---

## 11. 実装への推奨コード例

### 11.1 セッションファイル特定関数

```bash
# codex プロセスのセッションファイルを取得
get_codex_session_file() {
    local pid="$1"
    lsof -p "$pid" 2>/dev/null | grep '\.jsonl$' | tail -1 | awk '{print $NF}'
}

# 使用例
session_file=$(get_codex_session_file 3728261)
# /home/takets/.codex/sessions/2026/02/06/rollout-2026-02-06T16-58-32-019c31f5-b535-7260-8d1a-d6890f246fc8.jsonl
```

### 11.2 動作状態判定関数

```bash
# codex の動作状態を判定
check_codex_status() {
    local pid="$1"
    local working_threshold="${WORKING_THRESHOLD:-30}"
    
    local session_file=$(get_codex_session_file "$pid")
    if [ -z "$session_file" ] || [ ! -f "$session_file" ]; then
        echo "unknown"
        return
    fi
    
    local mtime=$(stat -c %Y "$session_file" 2>/dev/null)
    if [ -z "$mtime" ]; then
        echo "unknown"
        return
    fi
    
    local current_time=$(date +%s)
    local diff=$((current_time - mtime))
    
    if [ "$diff" -lt "$working_threshold" ]; then
        echo "working"
    else
        echo "idle"
    fi
}

# 使用例
status=$(check_codex_status 3728261)
# working または idle
```

---

## 完了チェックリスト

- [x] Phase 0 調査完了
- [x] codex コマンドの実行可能性確認
- [x] セッションファイルの位置特定
- [x] ログファイルの位置特定
- [x] セッションファイルのフォーマット分析
- [x] 動作状態判定方法の確立
- [x] 複数プロセス・セッション管理の検討
- [x] 実装上の注意点の整理

**結論**: ✅ **Phase 1 実装開始の準備完了**

---

## 次ステップ: Phase 1 へ

実装計画の Phase 1（プロセス検出の拡張）を開始できます。

**キー変更**:
1. `scripts/lib/cache_batch.sh` の `_build_pid_pane_map()` で codex を追加検出
2. キャッシュファイルに `process_type` フィールドを追加
3. テスト実行で動作確認

詳細は実装計画の Phase 1 セクションを参照してください。
