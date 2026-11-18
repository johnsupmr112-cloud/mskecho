#!/bin/bash
# 一次性：把 MSKEcho 專案放上 GitHub（私人 repo）
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_NAME="${1:-mskecho}"

command -v git >/dev/null || { echo "請先安裝 Xcode Command Line Tools：xcode-select --install"; exit 1; }
command -v gh  >/dev/null || { echo "安裝 GitHub CLI…"; brew install gh; }

if ! gh auth status >/dev/null 2>&1; then
  echo "登入 GitHub（選 GitHub.com → HTTPS → Login with a web browser）"
  gh auth login
fi
gh auth setup-git

if [ ! -d .git ]; then
  git init -b main
fi
git add -A
git commit -m "MSKEcho: phase 1 + learning sync" || echo "（沒有新變更需要 commit）"

if git remote get-url origin >/dev/null 2>&1; then
  git push -u origin main
else
  gh repo create "$REPO_NAME" --private --source=. --remote=origin --push
fi
echo "✓ 完成：$(gh repo view --json url -q .url)"
