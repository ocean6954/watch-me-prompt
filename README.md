# watch-me-prompt

Claude Code のセッション内プロンプトをチームでナレッジ共有するツール。

`/share-prompt` コマンドで、自分のプロンプトを選択して DynamoDB に保存できます。

## インストール

```bash
bash <(curl -sf https://raw.githubusercontent.com/ocean6954/watch-me-prompt/main/install.sh)
```

実行時に API エンドポイント URL の入力を求められます。管理者から共有された URL を入力してください。

## 使い方

Claude Code で以下のコマンドを実行:

```
/share-prompt          # 未送信の全プロンプトを共有（デフォルト）
/share-prompt 1        # 直前のプロンプトを共有
/share-prompt 3        # 直近3件を共有
/share-prompt pick     # 一覧から選択して共有
```

> **Note**: スキルは確認なしで即実行される設定になっています。毎回確認が欲しい場合は `share-prompt.md` 内の「確認なしで即実行してください」の記述を削除してください。

## 前提条件

- Claude Code がインストール済みであること
- 社内 WiFi に接続していること
- `python3` が使えること（macOS 標準搭載）

## 管理者向け

AWS リソースのセットアップは別途 `~/.claude/scripts/setup-shared-prompts.sh` で行います。
