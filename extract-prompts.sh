#!/bin/bash
set -euo pipefail

# extract-prompts.sh - セッションJSONLからユーザープロンプトを抽出・送信
#
# 使い方:
#   extract-prompts.sh [mode] [selection]
#     - 引数なし or "list"  → 番号付き一覧表示
#     - <N>                 → 直近N件をJSON配列で出力
#     - all                 → 全件をJSON配列で出力
#     - pick 1,3,5          → 指定番号をJSON配列で出力
#     - check-env           → 環境変数の確認
#     - send <submode> [selection]  → 抽出 + API送信 + 履歴記録を一括実行
#       send all            → 未送信の全件を送信
#       send <N>            → 直近N件を送信
#       send pick "1,3"     → 指定番号を送信
#
# セッションファイルは現在のディレクトリから自動解決される

MODE="${1:-list}"

# ─── check-env モード ───────────────────────────────────
if [ "$MODE" = "check-env" ]; then
  errors=0
  if [ -z "${SHARE_PROMPT_API_URL:-}" ]; then
    echo "SHARE_PROMPT_API_URL が未設定です。" >&2
    echo '  export SHARE_PROMPT_API_URL="https://<api-id>.execute-api.ap-northeast-1.amazonaws.com/prod/prompts"' >&2
    errors=1
  else
    echo "API_URL=SET"
  fi
  if [ -z "${SHARE_PROMPT_USER:-}" ]; then
    echo "SHARE_PROMPT_USER が未設定です。" >&2
    echo '  export SHARE_PROMPT_USER="your-name"' >&2
    errors=1
  else
    echo "USER=SET"
  fi
  if [ "$errors" -eq 1 ]; then
    echo "" >&2
    echo "install.sh を再実行して設定してください。" >&2
    exit 1
  fi
  exit 0
fi

# ─── send モード ────────────────────────────────────────
if [ "$MODE" = "send" ]; then
  # 環境変数チェック
  if [ -z "${SHARE_PROMPT_API_URL:-}" ] || [ -z "${SHARE_PROMPT_USER:-}" ]; then
    echo "環境変数が未設定です。check-env で確認してください。" >&2
    exit 1
  fi

  # URL バリデーション
  if [[ ! "${SHARE_PROMPT_API_URL}" =~ ^https:// ]]; then
    echo "SHARE_PROMPT_API_URL が https:// で始まっていません。" >&2
    exit 1
  fi

  SEND_MODE="${2:-all}"
  SEND_SELECTION="${3:-}"
  shift  # "send" を消す

  # プロジェクト名を取得
  PROJECT="$(basename "$(pwd)")"

  # Python で抽出 → ペイロード構築 → curl 送信 → 履歴記録を一括実行
  exec python3 - "$@" <<'PYTHON'
import sys
import json
import hashlib
import os
import subprocess
import re
from urllib.parse import urlparse

# ─── 引数 ───
send_mode = sys.argv[1] if len(sys.argv) > 1 else "all"
send_selection = sys.argv[2] if len(sys.argv) > 2 else ""

# ─── 環境変数（bash 側で検証済み） ───
api_url = os.environ["SHARE_PROMPT_API_URL"]
user = os.environ["SHARE_PROMPT_USER"]

# ─── URL バリデーション（Python 側でも検証） ───
parsed_url = urlparse(api_url)
if parsed_url.scheme != "https" or not parsed_url.hostname:
    print("SHARE_PROMPT_API_URL が不正です（https:// で始まる有効な URL が必要です）。", file=sys.stderr)
    sys.exit(1)
blocked_hosts = {"169.254.169.254", "localhost", "127.0.0.1", "0.0.0.0", "[::1]"}
if parsed_url.hostname in blocked_hosts:
    print("SHARE_PROMPT_API_URL にローカル/メタデータアドレスは使用できません。", file=sys.stderr)
    sys.exit(1)

# ─── ユーザー名バリデーション ───
if len(user) > 64 or len(user) == 0 or re.search(r'[\x00-\x1f\x7f"\'`$\\;|&<>(){}]', user):
    print("SHARE_PROMPT_USER に不正な文字が含まれているか、長すぎます（制御文字・シェルメタ文字は使用不可、64文字以内）。", file=sys.stderr)
    sys.exit(1)

# ─── 定数 ───
MIN_LENGTH = 5
BATCH_SIZE = 50  # サーバー側の maxPrompts と揃える
HISTORY_FILE = os.path.expanduser("~/.claude/.shared-prompt-history")
SKIP_PREFIXES = [
    "<command-message>",
    "<command-name>",
    "## Your task",
    "[Request interrupted",
]

# ─── セッションファイル解決 ───
def resolve_session_file():
    cwd = os.getcwd()
    project_dir_name = cwd.replace("/", "-")
    project_path = os.path.expanduser(f"~/.claude/projects/{project_dir_name}")
    if not os.path.isdir(project_path):
        print(f"プロジェクトディレクトリが見つかりません: {project_path}", file=sys.stderr)
        sys.exit(1)
    jsonl_files = []
    for f in os.listdir(project_path):
        if f.endswith(".jsonl") and f != "sessions-index.json":
            full = os.path.join(project_path, f)
            if os.path.isfile(full):
                jsonl_files.append(full)
    if not jsonl_files:
        print(f"セッションファイルが見つかりません: {project_path}", file=sys.stderr)
        sys.exit(1)
    jsonl_files.sort(key=os.path.getmtime, reverse=True)
    return jsonl_files[0]

# ─── ヘルパー関数 ───
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
    if not os.path.exists(HISTORY_FILE):
        return set()
    with open(HISTORY_FILE) as f:
        return set(line.strip() for line in f if line.strip())

def save_history(hashes):
    with open(HISTORY_FILE, "a") as f:
        for h in hashes:
            f.write(h + "\n")

# ─── プロンプト抽出 ───
session_file = resolve_session_file()
prompts = []
with open(session_file) as f:
    for line in f:
        obj = json.loads(line.strip())
        if obj.get("type") == "user" and obj.get("userType") == "external":
            text = extract_text(obj["message"].get("content", ""))
            if len(text) >= MIN_LENGTH and not should_skip(text):
                prompts.append({
                    "text": text,
                    "timestamp": obj.get("timestamp", "")
                })

if not prompts:
    print("プロンプトが見つかりませんでした。", file=sys.stderr)
    sys.exit(1)

# ─── 送信対象の選定 ───
if send_mode == "all":
    history = load_history()
    selected = [p for p in prompts if prompt_hash(p["text"]) not in history]
    if not selected:
        print("未送信のプロンプトはありません。")
        sys.exit(0)
elif send_mode.isdigit():
    n = int(send_mode)
    selected = prompts[-n:]
elif send_mode == "pick":
    indices = set()
    max_idx = len(prompts)
    for part in send_selection.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            if "-" in part:
                start, end = part.split("-", 1)
                start, end = int(start), int(end)
                if end - start > 1000:
                    print(f"範囲が大きすぎます: {part}", file=sys.stderr)
                    sys.exit(1)
                for i in range(start, end + 1):
                    indices.add(i)
            else:
                indices.add(int(part))
        except ValueError:
            print(f"無効な指定: {part}", file=sys.stderr)
            sys.exit(1)
    selected = [prompts[i - 1] for i in sorted(indices) if 1 <= i <= max_idx]
else:
    print(f"不明な送信モード: {send_mode}", file=sys.stderr)
    sys.exit(1)

if not selected:
    print("送信対象のプロンプトがありません。")
    sys.exit(0)

# ─── バッチ分割して送信 ───
project = os.path.basename(os.getcwd())
total = len(selected)
batches = [selected[i:i + BATCH_SIZE] for i in range(0, total, BATCH_SIZE)]
batch_count = len(batches)
sent = 0

for batch_idx, batch in enumerate(batches, 1):
    payload = json.dumps({
        "prompts": batch,
        "project": project,
        "user": user
    }, ensure_ascii=False)

    if batch_count > 1:
        print(f"バッチ {batch_idx}/{batch_count} を送信中... ({len(batch)}件)", file=sys.stderr)

    result = subprocess.run(
        ["curl", "-s", "-w", "\n%{http_code}", "-X", "POST", api_url,
         "--max-time", "30",
         "-H", "Content-Type: application/json", "-d", "@-"],
        input=payload,
        capture_output=True, text=True
    )

    output_lines = result.stdout.strip().rsplit("\n", 1)
    body = output_lines[0] if len(output_lines) > 1 else ""
    status_code = output_lines[-1] if output_lines else ""

    if result.returncode != 0:
        print(f"curl エラー (バッチ {batch_idx}/{batch_count}, exit code {result.returncode})", file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        print(f"- 送信済み: {sent}件 / 全体: {total}件", file=sys.stderr)
        sys.exit(1)

    if not status_code.isdigit() or int(status_code) >= 400:
        print(f"API エラー (バッチ {batch_idx}/{batch_count}, HTTP {status_code}): {body}", file=sys.stderr)
        print(f"- 送信済み: {sent}件 / 全体: {total}件", file=sys.stderr)
        sys.exit(1)

    # バッチ成功 → 即時履歴記録（途中失敗時も進捗を残す）
    save_history([prompt_hash(p["text"]) for p in batch])
    sent += len(batch)

# ─── 結果表示 ───
print(f"共有完了")
print(f"- 保存件数: {sent}件")
if batch_count > 1:
    print(f"- バッチ数: {batch_count}")
print(f"- プロジェクト: {project}")
print(f"- ユーザー: {user}")

PYTHON
  # exec により、Python 終了後にここには到達しない
fi

# ─── 既存モード（list / all / pick / mark-sent / 数値） ──────

resolve_session_file() {
  local project_dir_name
  project_dir_name="$(pwd | sed 's/[/_]/-/g')"
  local project_path="$HOME/.claude/projects/${project_dir_name}"

  if [ ! -d "$project_path" ]; then
    echo "プロジェクトディレクトリが見つかりません: $project_path" >&2
    return 1
  fi

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
SELECTION="${2:-}"

MIN_LENGTH=5
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
    for i, p in enumerate(prompts, 1):
        preview = p["text"].split("\n")[0][:70]
        if len(p["text"].split("\n")[0]) > 70:
            preview += "..."
        print(f"  {i}. {preview}")

elif mode == "all":
    history = load_history()
    unsent = [p for p in prompts if prompt_hash(p["text"]) not in history]
    if not unsent:
        print("未送信のプロンプトはありません。", file=sys.stderr)
        sys.exit(0)
    json.dump(unsent, sys.stdout, ensure_ascii=False, indent=2)

elif mode.isdigit():
    n = int(mode)
    json.dump(prompts[-n:], sys.stdout, ensure_ascii=False, indent=2)

elif mode == "pick":
    indices = set()
    max_idx = len(prompts)
    for part in selection.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            if "-" in part:
                start, end = part.split("-", 1)
                start, end = int(start), int(end)
                if end - start > 1000:
                    print(f"範囲が大きすぎます: {part}", file=sys.stderr)
                    sys.exit(1)
                for i in range(start, end + 1):
                    indices.add(i)
            else:
                indices.add(int(part))
        except ValueError:
            print(f"無効な指定: {part}", file=sys.stderr)
            sys.exit(1)
    selected = [prompts[i - 1] for i in sorted(indices) if 1 <= i <= max_idx]
    json.dump(selected, sys.stdout, ensure_ascii=False, indent=2)

elif mode == "mark-sent":
    raw = sys.stdin.read() if selection == "-" else selection
    sent_prompts = json.loads(raw)
    hashes = [prompt_hash(p["text"]) for p in sent_prompts]
    save_history(hashes)
    print(f"{len(hashes)}件を送信済みに記録しました。", file=sys.stderr)

else:
    print(f"不明なモード: {mode}", file=sys.stderr)
    sys.exit(1)
PYTHON
