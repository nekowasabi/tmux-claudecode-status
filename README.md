# tmux-claudecode-status

tmuxのステータスバーにClaude Codeの実行状態をリアルタイム表示するプラグイン。複数のClaude Codeセッションを個別に追跡し、各セッションのworking/idle状態を色分けして表示します。

## 特徴

- **複数セッション対応**: 複数のClaude Codeプロセスを同時に追跡
- **状態区別**: working（作業中）とidle（待機中）を色で区別
- **軽量・高速**: キャッシュ機能により毎秒の実行でも高速（< 50ms）
- **カスタマイズ可能**: アイコン・色・ドット記号をカスタマイズ可能
- **クロスプラットフォーム対応**: Linux/macOS対応

## インストール

### TPMを使用した場合（推奨）

`~/.tmux.conf` に以下を追加：

```bash
set -g @plugin 'takets/tmux-claudecode-status'
```

その後、tmuxで `prefix + I` を実行（TPMプラグインリロード）。

### 手動インストール

1. このリポジトリをクローン：
```bash
git clone https://github.com/takets/tmux-claudecode-status ~/.tmux/plugins/tmux-claudecode-status
```

2. `~/.tmux.conf` に以下を追加：
```bash
run-shell "~/.tmux/plugins/tmux-claudecode-status/claudecode_status.tmux"
```

3. tmuxを再起動。

## 設定

### デフォルト表示

デフォルトではステータスバーに `#{claudecode_status}` フォーマット文字列を設定する必要があります。

#### ステータスバーの表示位置設定

`~/.tmux.conf` に以下のいずれかを追加：

```bash
# status-right に表示
set -g status-right "#{claudecode_status} #[default]%H:%M"

# status-left に表示
set -g status-left "#{claudecode_status} #[default]"

# status-format[1]（上部ステータスバー）に表示
set -g status 2
set -g status-format[1] "#{claudecode_status}"
```

### カスタマイズオプション

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `@claudecode_working_dot` | `🤖` | working状態のドット（ロボット絵文字） |
| `@claudecode_idle_dot` | `🔔` | idle状態のドット（ベル絵文字） |
| `@claudecode_working_color` | `""` (空) | working状態の色（空=tmuxデフォルト） |
| `@claudecode_idle_color` | `""` (空) | idle状態の色（空=tmuxデフォルト） |
| `@claudecode_separator` | `" "` | セッション間のセパレータ |
| `@claudecode_left_sep` | `""` (空) | 左囲み文字 |
| `@claudecode_right_sep` | `""` (空) | 右囲み文字 |
| `@claudecode_show_terminal` | `on` | ターミナル絵文字の表示 |
| `@claudecode_show_pane` | `on` | ペイン番号の表示 |
| `@claudecode_terminal_iterm` | `🍎` | iTerm/Terminalの絵文字 |
| `@claudecode_terminal_wezterm` | `⚡` | WezTermの絵文字 |
| `@claudecode_terminal_ghostty` | `👻` | Ghosttyの絵文字 |
| `@claudecode_terminal_windows` | `🪟` | Windows Terminalの絵文字 |
| `@claudecode_terminal_unknown` | `❓` | 不明なターミナルの絵文字 |

### カスタマイズ例

```bash
# 囲み文字を追加
set -g @claudecode_left_sep "["
set -g @claudecode_right_sep "]"
# 結果: [🍎#0 project-name 🤖]

# ターミナル絵文字をカスタマイズ
set -g @claudecode_terminal_iterm "🖥️"
set -g @claudecode_terminal_wezterm "W"

# 色をカスタマイズ（任意）
set -g @claudecode_working_color "#f97316"
set -g @claudecode_idle_color "#22c55e"
```

### 色設定について

色設定はデフォルトで空（tmuxテーマの色を継承）です。必要に応じて設定してください。

## 動作仕組み

### セッション検出

1. `pgrep` でClaude Codeプロセス（プロセス名: `claude`）を検出
2. Linux環境では `/proc/{pid}/fd` からdebugファイルを特定
3. debugファイルの更新時刻（`~/.claude/debug/*.txt`）で状態判定

### 状態判定

- **working**: debugファイルが直近5秒以内に更新されたプロセス
- **idle**: debugファイルの更新が5秒以上前のプロセス

デフォルトの閾値（5秒）は環境変数で変更可能：

```bash
export CLAUDECODE_WORKING_THRESHOLD=10  # 10秒に変更
```

### キャッシュ機能

パフォーマンス向上のため、ステータス出力は2秒間キャッシュされます。

## 表示例

```
  ●●○      # アイコン + working×2 + idle×1
```

## トラブルシューティング

### ステータスが表示されない

1. Claude Codeが実行されていることを確認：
```bash
pgrep claude
```

2. tmuxの設定でステータスバーが有効か確認：
```bash
tmux show-option -g status
```

3. ステータスフォーマットが正しく設定されているか確認：
```bash
tmux show-option -g status-right
```

### 状態が更新されない

1. キャッシュファイルを削除：
```bash
rm -f /tmp/claudecode_status_cache_*
```

2. debugファイルが存在するか確認：
```bash
ls -la ~/.claude/debug/
```

## テスト実行

プロジェクトのテストを実行：

```bash
# 検出テスト
./tests/test_detection.sh

# 出力テスト
./tests/test_output.sh

# ステータステスト
./tests/test_status.sh
```

すべてのテストが PASS することを確認してください。

## ファイル構成

```
tmux-claudecode-status/
├── claudecode_status.tmux      # TPMエントリーポイント
├── scripts/
│   ├── shared.sh               # 共通ユーティリティ
│   ├── session_tracker.sh       # セッション追跡ロジック
│   └── claudecode_status.sh     # メイン出力スクリプト
├── tests/
│   ├── test_detection.sh        # 検出機能テスト
│   ├── test_status.sh           # ステータス判定テスト
│   └── test_output.sh           # 出力フォーマットテスト
└── README.md                    # このファイル
```

## ライセンス

MIT License

## 貢献

バグ報告や機能提案はGitHub Issuesにお願いします。

## 参考資料

- [tmux Plugin Manager (TPM)](https://github.com/tmux-plugins/tpm)
- [tmux Manual](https://manpages.debian.org/tmux.1)
- [Claude Code CLI](https://github.com/anthropics/claude-code)
