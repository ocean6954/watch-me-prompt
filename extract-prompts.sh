#!/bin/bash
set -euo pipefail

# extract-prompts.sh - セッションJSONLからユーザープロンプトを抽出
#
# 使い方:
#   extract-prompts.sh [mode] [selection]
#     - 引数なし or "list"  → 番号付き一覧表示
#     - <N>                 → 直近N件をJSON配列で出力
#     - all                 → 全件をJSON配列で出力
#     - pick 1,3,5          → 指定番号をJSON配列で出力
#
# セッションファイルは現在のディレクトリから自動解決される

resolve_session_file() {
  local project_dir_name
  project_dir_name="$(pwd | sed 's/\//-/g')"
  local project_path="$HOME/.claude/projects/${project_dir_name}"

  if [ ! -d "$project_path" ]; then
    echo "プロジェクトディレクトリが見つかりません: $project_path" >&2
    return 1
  fi

  # 最新の .jsonl ファイルを取得（sessions-index.json は除外）
  local latest
  latest="$(find "$project_path" -maxdepth 1 -name '*.jsonl' -not -name 'sessions-index.json' -type f -print0 \
    | xargs -0 ls -t 2>/dev/null | head -1)"

  if [ -z "$latest" ]; then
    echo "セッションファイルが見つかりません: $project_path" >&2
    return 1
  fi

  echo "$latest"
}

SESSION_FILE="$(resolve_session_file)" || exit 1
MODE="${1:-list}"
SELECTION="${2:-}"

MIN_LENGTH=5  # これ以下の文字数のプロンプトは除外
HISTORY_FILE="$HOME/.claude/.shared-prompt-history"

python3 - "$SESSION_FILE" "$MODE" "$SELECTION" "$MIN_LENGTH" "$HISTORY_FILE" <<'PYTHON'
import sys
import json
import hashlib
import os

session_file = sys.argv[1]
mode = sys.argv[2]
selection = sys.argv[3]
min_length = int(sys.argv[4])
history_file = sys.argv[5]

SKIP_PREFIXES = [
    "<command-message>",
    "<command-name>",
    "## Your task",
    "[Request interrupted",
]

def extract_text(content):
    if isinstance(content, str):
        return content.strip()
    elif isinstance(content, list):
        texts = []
        for c in content:
            if isinstance(c, dict) and c.get("type") == "text":
                texts.append(c["text"].strip())
        return "\n".join(texts)
    return ""

def should_skip(text):
    for prefix in SKIP_PREFIXES:
        if text.startswith(prefix):
            return True
    return False

def prompt_hash(text):
    return hashlib.sha256(text.encode()).hexdigest()[:16]

def load_history():
    if not os.path.exists(history_file):
        return set()
    with open(history_file) as f:
        return set(line.strip() for line in f if line.strip())

def save_history(hashes):
    with open(history_file, "a") as f:
        for h in hashes:
            f.write(h + "\n")

# セッションファイルからユーザープロンプトを抽出
prompts = []
with open(session_file) as f:
    for line in f:
        obj = json.loads(line.strip())
        if obj.get("type") == "user" and obj.get("userType") == "external":
            text = extract_text(obj["message"].get("content", ""))
            if len(text) >= min_length and not should_skip(text):
                prompts.append({
                    "text": text,
                    "timestamp": obj.get("timestamp", "")
                })

if not prompts:
    print("プロンプトが見つかりませんでした。", file=sys.stderr)
    sys.exit(1)

# モードに応じて出力
if mode == "list":
    # 番号付き一覧（プレビュー表示）
    for i, p in enumerate(prompts, 1):
        preview = p["text"].split("\n")[0][:70]
        if len(p["text"].split("\n")[0]) > 70:
            preview += "..."
        print(f"  {i}. {preview}")

elif mode == "all":
    # 送信済みを除外
    history = load_history()
    unsent = [p for p in prompts if prompt_hash(p["text"]) not in history]
    if not unsent:
        print("未送信のプロンプトはありません。", file=sys.stderr)
        sys.exit(0)
    json.dump(unsent, sys.stdout, ensure_ascii=False, indent=2)

elif mode.isdigit():
    # 直近N件
    n = int(mode)
    json.dump(prompts[-n:], sys.stdout, ensure_ascii=False, indent=2)

elif mode == "pick":
    # カンマ区切り or 範囲指定（例: 1,3,5 / 1-3）
    indices = set()
    for part in selection.split(","):
        part = part.strip()
        if "-" in part:
            start, end = part.split("-", 1)
            for i in range(int(start), int(end) + 1):
                indices.add(i)
        else:
            indices.add(int(part))
    selected = [prompts[i - 1] for i in sorted(indices) if 1 <= i <= len(prompts)]
    json.dump(selected, sys.stdout, ensure_ascii=False, indent=2)

elif mode == "mark-sent":
    # 送信完了後に呼ばれる: selection に JSON 配列が渡される
    sent_prompts = json.loads(selection)
    hashes = [prompt_hash(p["text"]) for p in sent_prompts]
    save_history(hashes)
    print(f"{len(hashes)}件を送信済みに記録しました。", file=sys.stderr)

else:
    print(f"不明なモード: {mode}", file=sys.stderr)
    sys.exit(1)
PYTHON
