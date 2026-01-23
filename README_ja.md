# tmux-claudecode-status

tmuxのステータスバーにClaude Codeの実行状態をリアルタイム表示するプラグイン。複数のClaude Codeセッションを個別に追跡し、各セッションのworking/idle状態を色分けして表示します。

## 特徴

- **複数セッション対応**: 複数のClaude Codeプロセスを同時に追跡
- **状態区別**: working（作業中）とidle（待機中）を色で区別
- **軽量・高速**: キャッシュ機能とTTYベースの変化検出により最適化されたパフォーマンス（< 50ms）
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
| `@claudecode_working_threshold` | `30` | working/idle判定の閾値（秒） |
| `@claudecode_select_key` | `""` (空) | プロセス選択機能を開くキーバインド（例: `C-g`） |
| `@claudecode_fzf_opts` | `"--height=40% --reverse --border --prompt='Select Claude: '"` | プロセス選択機能用のfzfオプション |
| `@claudecode_fzf_preview` | `on` | fzfプレビューの有効/無効 (`on`/`off`) |
| `@claudecode_fzf_preview_lines` | `30` | プレビューに表示する行数 |

### カスタマイズ例

```bash
# 囲み文字を追加
set -g @claudecode_left_sep "["
set -g @claudecode_right_sep "]"
# 結果: [🍎#0 project-name 🤖]

# ターミナル絵文字をカスタマイズ
set -g @claudecode_terminal_iterm "🖥️"
set -g @claudecode_terminal_wezterm "W"

# working/idle判定の閾値を変更（デフォルト: 30秒）
set -g @claudecode_working_threshold "10"

# プロセス選択機能を有効化（requires fzf）
set -g @claudecode_select_key "C-j"  # prefix + Ctrl-j to open selector

# プロセス選択機能用のfzfオプションをカスタマイズ
set -g @claudecode_fzf_opts "--height=50% --reverse --border --prompt='Claude> '"

# 色をカスタマイズ（任意）
set -g @claudecode_working_color "#f97316"
set -g @claudecode_idle_color "#22c55e"
```

### 色設定について

色設定はデフォルトで空（tmuxテーマの色を継承）です。必要に応じて設定してください。

### プロセス選択機能

プロセス選択機能により、fzfを使用して複数のClaude Codeセッションを素早く切り替えることができます。この機能は、複数のClaude Codeインスタンスを異なるプロジェクトで同時に実行している場合に特に便利です。

**必要環境:**
- fzf（macOSでは `brew install fzf`、Ubuntuでは `apt install fzf` でインストール）
- tmux 3.2+ （ポップアップサポート用、古いバージョンではsplit-windowフォールバック使用）

**主な機能:**
- **対話的選択**: fzfを使用してClaude Codeプロセスを検索・選択
- **ステータス表示**: 各プロセスのworking/idle状態を表示
- **ターミナル認識**: 各プロセスが実行されているターミナルアプリケーション（Terminal.app、iTerm2、Ghosttyなど）を表示
- **自動フォーカス**: 選択したプロセスのターミナルを自動で切り替え、対応するtmuxペインにフォーカス
- **優先度ソート**: working状態のプロセスを最初に表示し、その後idle状態のプロセスを表示
- **プロンプト送信 (Ctrl+S)**: ポップアップから選択したClaude Codeセッションにプロンプトを送信

**セットアップ:**
```bash
# キーバインドでプロセス選択機能を有効化
set -g @claudecode_select_key "C-j"
```

**使い方 - キーバインドモード:**
1. `prefix + Ctrl-j`（または設定したキー）を押してセレクタを開く
2. プロジェクト名またはターミナルタイプで絞り込むために文字を入力
3. 矢印キーで移動し、以下のキーで操作:
   - **Enter**: 選択したClaude Codeセッションに切り替え
   - **Ctrl+S**: ポップアップを開いて選択セッションにプロンプトを送信
4. 選択したプロセスのターミナルが有効になり、対応するtmuxペインにフォーカスが移動

**使い方 - コマンドライン:**
```bash
# fzfを使用した対話的選択
~/.tmux/plugins/tmux-claudecode-status/scripts/select_claude.sh

# リストモード - fzfなしですべてのプロセスを出力
~/.tmux/plugins/tmux-claudecode-status/scripts/select_claude.sh --list
```

**出力例:**
```
🍎 #0 my-project [session-1] 🤖
🖥️ #1 web-app [session-2] 🤖
⚡ #2 cli-tool [session-3] 🔔
```

**詳細設定:**
```bash
# キーバインドをカスタマイズ
set -g @claudecode_select_key "C-g"

# fzfの表示をカスタマイズ
set -g @claudecode_fzf_opts "--height=50% --reverse --border --prompt='🤖 Select: '"

# カスタムカラーを使用
set -g @claudecode_working_color "#f97316"
set -g @claudecode_idle_color "#22c55e"
```

**動作原理:**
1. `pgrep`を使用して実行中のClaude Codeプロセスをスキャン
2. TTYパス、作業ディレクトリ、ターミナルアプリケーションを含むプロセスメタデータを取得
3. TTY変更時刻をチェックしてステータス（working/idle）を決定
4. ステータスとターミナル優先度でソート
5. ターミナルを示す絵文字、ペイン番号、プロジェクト名、ステータスを含むフォーマット済みリストを表示
6. 選択時に、ターミナルアプリケーションを有効にし、対応するtmuxペインにフォーカス

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
│   ├── claudecode_status.sh     # メイン出力スクリプト
│   ├── select_claude.sh         # プロセス選択UI（fzf）
│   └── focus_session.sh         # ターミナルフォーカス & ペイン切り替え
├── tests/
│   ├── test_detection.sh        # 検出機能テスト
│   ├── test_status.sh           # ステータス判定テスト
│   └── test_output.sh           # 出力フォーマットテスト
├── README.md                    # 英語版ドキュメント
└── README_ja.md                 # このファイル
```

## ライセンス

MIT License

## 貢献

バグ報告や機能提案はGitHub Issuesにお願いします。

## 参考資料

- [tmux Plugin Manager (TPM)](https://github.com/tmux-plugins/tpm)
- [tmux Manual](https://manpages.debian.org/tmux.1)
- [Claude Code CLI](https://github.com/anthropics/claude-code)
