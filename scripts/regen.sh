#!/bin/bash
# 重新產生 Xcode 專案（新增/刪除 Swift 檔之後執行）
# 會先把你在 Xcode 介面設定的 Team 與 Bundle ID 寫回 project.yml，避免被 xcodegen 洗掉
# （Bundle ID 一變，iPhone 會當成另一個 App，學習資料就看不到了）
set -euo pipefail
cd "$(dirname "$0")/.."

PBX="MSKEcho.xcodeproj/project.pbxproj"
if [ -f "$PBX" ]; then
  TEAM=$(grep -m1 -oE 'DEVELOPMENT_TEAM = [A-Z0-9]+;' "$PBX" | sed -E 's/DEVELOPMENT_TEAM = ([A-Z0-9]+);/\1/' || true)
  BUNDLE=$(grep -m1 -oE 'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;' "$PBX" | sed -E 's/PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;/\1/' || true)
  if [ -n "${TEAM:-}" ]; then
    sed -i '' -E "s/^([[:space:]]*DEVELOPMENT_TEAM:).*/\1 \"$TEAM\"/" project.yml
    echo "✓ Team ID：$TEAM"
  fi
  if [ -n "${BUNDLE:-}" ]; then
    sed -i '' -E "s/^([[:space:]]*PRODUCT_BUNDLE_IDENTIFIER:).*/\1 $BUNDLE/" project.yml
    echo "✓ Bundle ID：$BUNDLE"
  fi
fi

if ! command -v xcodegen >/dev/null; then
  echo "找不到 xcodegen，請先執行：brew install xcodegen"; exit 1
fi
xcodegen
echo "完成。若 Xcode 已開著，它會自動重新載入；接著按 ⌘R。"
