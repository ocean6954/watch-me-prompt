#!/bin/bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/ocean6954/watch-me-prompt/main"

echo "=== watch-me-prompt インストール ==="
echo ""

# 1. ディレクトリ作成
mkdir -p ~/.claude/commands ~/.claude/scripts

# 2. ファイルをダウンロード
echo "ファイルをダウンロード中..."
curl -sf -o ~/.claude/commands/share-prompt.md "${REPO_RAW}/share-prompt.md"
curl -sf -o ~/.claude/scripts/extract-prompts.sh "${REPO_RAW}/extract-prompts.sh"
chmod +x ~/.claude/scripts/extract-prompts.sh
echo "完了。"

# 3. API URL の設定
echo ""
if grep -q "SHARE_PROMPT_API_URL" ~/.zshrc 2>/dev/null; then
  API_URL=$(grep "SHARE_PROMPT_API_URL" ~/.zshrc | sed 's/.*="\(.*\)"/\1/')
  echo "SHARE_PROMPT_API_URL は既に設定されています: ${API_URL}"
else
  read -p "API エンドポイント URL を入力してください: " API_URL
  if [ -z "$API_URL" ]; then
    echo "URL が入力されませんでした。後から .zshrc に以下を追加してください:"
    echo "  export SHARE_PROMPT_API_URL=\"https://<api-id>.execute-api.ap-northeast-1.amazonaws.com/prod/prompts\""
  else
    echo "export SHARE_PROMPT_API_URL=\"${API_URL}\"" >> ~/.zshrc
    echo ".zshrc に追加しました。"
  fi
fi

# 4. ダッシュボードの配置（API URL を埋め込み）
if [ -n "${API_URL:-}" ]; then
  echo "ダッシュボードを配置中..."
  curl -sf "${REPO_RAW}/dashboard.html" | sed "s|__API_URL__|${API_URL}|g" > ~/.claude/dashboard.html
  echo "完了: ~/.claude/dashboard.html"
fi

echo ""
echo "================================================"
echo "  インストール完了！"
echo ""
echo "  使い方:"
echo "    Claude Code で /share-prompt を実行"
echo "    ダッシュボード: open ~/.claude/dashboard.html"
echo ""
echo "  ターミナルを再起動するか、以下を実行してください:"
echo "    source ~/.zshrc"
echo "================================================"
