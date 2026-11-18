#!/bin/bash
# 一鍵上傳到 GitHub：bash scripts/push.sh "這次改了什麼"
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d .git ] || { echo "還沒設定 GitHub，請先執行：bash scripts/setup_github.sh"; exit 1; }

git add -A
if git diff --cached --quiet; then
  echo "沒有變更需要上傳。"; exit 0
fi
echo "這次會上傳的檔案："
git diff --cached --stat
MSG="${1:-update $(date '+%Y-%m-%d %H:%M')}"
git commit -q -m "$MSG"
git push -q
echo "✓ 已上傳：$MSG"
