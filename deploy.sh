#!/usr/bin/env bash
# 一鍵部署筆記站 / one-command deploy for the notes site
# 用法 / usage:  ./deploy.sh ["commit 訊息"]
set -euo pipefail
cd "$(dirname "$0")"

msg="${1:-update notes}"

# 沒有任何變更就直接結束
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "沒有變更，不需部署 / Nothing to deploy."
  exit 0
fi

echo "本次變更 / changes:"
git status --short | sed 's/^/  /'

git add -A
git commit -q -m "$msg"

TOKEN="$(gh auth token 2>/dev/null || true)"
if [ -z "$TOKEN" ]; then
  echo "✗ gh 未登入。先執行: gh auth login" >&2
  exit 1
fi

echo "推送中 / pushing…"
git push "https://x-access-token:${TOKEN}@github.com/dandycheng110/dandycheng110.github.io.git" main 2>&1 \
  | sed -E "s#${TOKEN}#***#g; s/^/  /"

echo "✓ 完成。約 1 分鐘後生效："
echo "   https://dandycheng110.github.io/notes/"
