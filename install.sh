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
  API_URL=$(grep -m1 'export SHARE_PROMPT_API_URL=' ~/.zshrc | sed 's/^export SHARE_PROMPT_API_URL="\{0,1\}\(.*\)"\{0,1\}$/\1/')
  if [[ ! "$API_URL" =~ ^https://[a-zA-Z0-9._/%?=\&:+-]+$ ]]; then
    echo "警告: .zshrc の SHARE_PROMPT_API_URL が不正な形式です。"
    printf '現在の値: %s\n' "$API_URL" | cat -v
    echo ".zshrc を確認し、正しい https:// URL に修正してください。"
    API_URL=""
  else
    echo "SHARE_PROMPT_API_URL は既に設定されています: ${API_URL}"
  fi
else
  read -p "API エンドポイント URL を入力してください: " API_URL </dev/tty
  if [ -z "$API_URL" ]; then
    echo "URL が入力されませんでした。後から .zshrc に以下を追加してください:"
    echo "  export SHARE_PROMPT_API_URL=\"https://<api-id>.execute-api.ap-northeast-1.amazonaws.com/prod/prompts\""
  elif [[ "$API_URL" =~ [[:cntrl:]] ]]; then
    echo "エラー: URL に制御文字が含まれています。正しい URL を入力してください。"
  elif [[ ! "$API_URL" =~ ^https://[a-zA-Z0-9._/%?=\&:+-]+$ ]]; then
    echo "エラー: 有効な https:// URL を入力してください。"
    printf '入力された値: %s\n' "$API_URL" | cat -v
    echo "後から .zshrc に正しい URL を追加してください。"
  else
    ESCAPED_URL=$(printf '%s' "$API_URL" | sed 's/["`$\\!]/\\&/g')
    echo "export SHARE_PROMPT_API_URL=\"${ESCAPED_URL}\"" >> ~/.zshrc
    echo ".zshrc に追加しました。"
  fi
fi

# 4. ユーザー名の設定
echo ""
if grep -q "SHARE_PROMPT_USER" ~/.zshrc 2>/dev/null; then
  PROMPT_USER=$(grep -m1 'export SHARE_PROMPT_USER=' ~/.zshrc | sed 's/^export SHARE_PROMPT_USER="\{0,1\}\(.*\)"\{0,1\}$/\1/')
  echo "SHARE_PROMPT_USER は既に設定されています: ${PROMPT_USER}"
else
  read -p "表示名を入力してください（例: tanaka）: " PROMPT_USER </dev/tty
  if [ -z "$PROMPT_USER" ]; then
    echo "エラー: 表示名は必須です。後から .zshrc に以下を追加してください:"
    echo "  export SHARE_PROMPT_USER=\"your-name\""
  elif [ ${#PROMPT_USER} -gt 64 ] || [[ "$PROMPT_USER" =~ [\`\$\\!\;\|\'\"\&\<\>\(\)\{\}] ]] || [[ "$PROMPT_USER" =~ [[:cntrl:]] ]]; then
    echo "エラー: 表示名に使用できない文字が含まれているか、長すぎます（64文字以内、制御文字・シェルメタ文字は不可）。"
  else
    ESCAPED_USER=$(printf '%s' "$PROMPT_USER" | sed 's/["`$\\!]/\\&/g')
    echo "export SHARE_PROMPT_USER=\"${ESCAPED_USER}\"" >> ~/.zshrc
    echo ".zshrc に追加しました。"
  fi
fi

# 5. ダッシュボードの配置（API URL を埋め込み）
if [ -n "${API_URL:-}" ]; then
  echo "ダッシュボードを配置中..."
  DASH_TMP="$(mktemp)"
  if curl -sf -o "$DASH_TMP" "${REPO_RAW}/dashboard.html" && [ -s "$DASH_TMP" ]; then
    sed "s|__API_URL__|$(printf '%s' "$API_URL" | sed 's/[\\&/|]/\\&/g')|g" "$DASH_TMP" > ~/.claude/dashboard.html
    echo "完了: ~/.claude/dashboard.html"
  else
    echo "警告: ダッシュボードのダウンロードに失敗しました。"
  fi
  rm -f "$DASH_TMP"
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
