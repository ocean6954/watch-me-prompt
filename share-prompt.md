---
name: share-prompt
description: セッション内のプロンプトをDynamoDBに保存してチームでナレッジ共有
allowed-tools: Bash(bash:*), Bash(curl:*), Bash(basename:*), AskUserQuestion
---

## Your task

ユーザーが `/share-prompt` を実行したとき、現在のセッションから未送信のユーザープロンプトを抽出し、API 経由で DynamoDB に保存します。

## 引数パターン

| 引数 | 動作 |
|---|---|
| なし | 未送信の全プロンプトを即送信（デフォルト） |
| `1`, `3` 等の数値 | 直近N件を即送信 |
| `pick` | 一覧表示 → ユーザーに番号を選択してもらう |

## 実行手順

### Step 1: API エンドポイントの確認

環境変数 `SHARE_PROMPT_API_URL` が設定されているか確認する。

```bash
echo "${SHARE_PROMPT_API_URL:-}"
```

未設定の場合、以下を案内して終了する:
- `export SHARE_PROMPT_API_URL="https://<api-id>.execute-api.ap-northeast-1.amazonaws.com/prod/prompts"` を `.zshrc` 等に追加
- URL がわからない場合は管理者に `bash ~/.claude/scripts/setup-shared-prompts.sh` の実行を依頼

### Step 2: プロンプト抽出

ヘルパースクリプトを使ってプロンプトを抽出します。

```bash
# デフォルト（引数なし）: 未送信の全件を抽出
bash ~/.claude/scripts/extract-prompts.sh all

# 数値指定の場合（例: 直近3件）
bash ~/.claude/scripts/extract-prompts.sh 3

# pick の場合: まず一覧表示
bash ~/.claude/scripts/extract-prompts.sh list
```

`all` モードは送信済みプロンプトを自動除外します。「未送信のプロンプトはありません。」と表示された場合は、その旨をユーザーに伝えて終了します。

### Step 3: 選択（pick 引数の場合のみ）

`pick` 引数の場合、Step 2 の一覧をユーザーに表示し、AskUserQuestion で選択を聞きます。

表示形式:
```
セッション内のプロンプト一覧:

  1. claude codeのプロンプト抽出方法を...
  2. フックは良くないなと思ってる...
  3. プロンプトは、引数があれば...
```

質問: `共有するプロンプト番号を指定してください（例: 1,3 / 1-3 / all）`

ユーザーの回答を受けて、pick モードで抽出します:
```bash
bash ~/.claude/scripts/extract-prompts.sh pick "1,3"
```

### Step 4: API に送信

抽出した JSON 配列をリクエストボディに組み立てて、curl で送信します。

```bash
PROJECT=$(basename "$(pwd)")

# extract-prompts.sh の出力（JSON配列）を PROMPTS_JSON に格納済みとする
curl -s -X POST "$SHARE_PROMPT_API_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"prompts\": ${PROMPTS_JSON},
    \"project\": \"${PROJECT}\",
    \"user\": \"${USER}\"
  }"
```

**重要**:
- `extract-prompts.sh` の数値/all/pick モードの出力はそのまま JSON 配列なので、`prompts` フィールドにそのまま埋め込める
- `$USER` は macOS の環境変数から自動取得される

### Step 5: 送信済みを記録

API の送信が成功したら、送信したプロンプトを履歴に記録します。

```bash
bash ~/.claude/scripts/extract-prompts.sh mark-sent "${PROMPTS_JSON}"
```

これにより、次回 `/share-prompt` を実行した際に同じプロンプトが再送信されなくなります。

### Step 6: 結果表示

API のレスポンスを確認し、以下の形式で結果を表示します:

```
共有完了
- 保存件数: {N}件
- プロジェクト: {プロジェクト名}
- ユーザー: {$USER}
```

## エラーハンドリング

- `SHARE_PROMPT_API_URL` 未設定: Step 1 で検知し、設定方法を案内して終了
- API がエラーを返した場合: レスポンスのエラーメッセージを表示
- セッションファイルが見つからない場合: エラーメッセージを表示して終了
- 未送信のプロンプトがない場合: 「未送信のプロンプトはありません。」と表示して終了

## 注意事項

- 必ず日本語で出力する
- プロンプト本文はそのまま保存する（要約しない）
- AWS 認証はチームメンバーには不要（API Gateway 経由）
- 送信済み履歴は `~/.claude/.shared-prompt-history` に保存される
