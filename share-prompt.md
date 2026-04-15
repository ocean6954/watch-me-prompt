---
name: share-prompt
description: セッション内のプロンプトをDynamoDBに保存してチームでナレッジ共有
allowed-tools: Bash(bash:*), AskUserQuestion
---

## Your task

ユーザーが `/share-prompt` を実行したとき、現在のセッションから未送信のユーザープロンプトを抽出し、API 経由で DynamoDB に保存します。

**重要**: このスキルは確認なしで即実行してください。各ステップの途中でユーザーに確認を求めず、最後の結果表示まで一気に進めてください。`pick` 引数の場合のみ AskUserQuestion で番号を聞きます。

## 引数パターン

| 引数 | 動作 |
|---|---|
| なし | 未送信の全プロンプトを即送信（デフォルト） |
| `1`, `3` 等の数値 | 直近N件を即送信 |
| `pick` | 一覧表示 → ユーザーに番号を選択してもらう |

## 実行手順

### Step 1: 環境変数の確認

```bash
bash ~/.claude/scripts/extract-prompts.sh check-env
```

exit code が 0 以外の場合、エラーメッセージに従い `install.sh` の再実行を案内して終了する。

### Step 2: 送信

引数に応じてコマンドを選択して実行する。

**デフォルト（引数なし）:**

```bash
bash ~/.claude/scripts/extract-prompts.sh send all
```

**数値指定の場合（例: 直近3件）:**

```bash
bash ~/.claude/scripts/extract-prompts.sh send 3
```

**pick の場合:**

まず一覧を表示する:

```bash
bash ~/.claude/scripts/extract-prompts.sh list
```

一覧を表示した後、AskUserQuestion で選択を聞く:

質問: `共有するプロンプト番号を指定してください（例: 1,3 / 1-3 / all）`

ユーザーが `all` と答えた場合:

```bash
bash ~/.claude/scripts/extract-prompts.sh send all
```

それ以外の回答の場合、ユーザーの入力をそのまま第3引数に渡す:

```bash
bash ~/.claude/scripts/extract-prompts.sh send pick "1,3"
```

### Step 3: 結果確認

send コマンドは成功時に以下を出力する。その内容をそのままユーザーに表示する:

```
共有完了
- 保存件数: {N}件
- プロジェクト: {プロジェクト名}
- ユーザー: {ユーザー名}
```

エラーの場合は stderr の内容を表示する。

## エラーハンドリング

- 環境変数未設定: Step 1 で検知し、設定方法を案内して終了
- API がエラーを返した場合: send コマンドがエラーメッセージを出力する
- セッションファイルが見つからない場合: send コマンドがエラーメッセージを出力する
- 未送信のプロンプトがない場合: 「未送信のプロンプトはありません。」と表示して終了

## 注意事項

- 必ず日本語で出力する
- プロンプト本文はそのまま保存する（要約しない）
- AWS 認証はチームメンバーには不要（API Gateway 経由）
- 送信済み履歴は `~/.claude/.shared-prompt-history` に保存される
