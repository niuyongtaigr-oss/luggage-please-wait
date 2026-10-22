#!/usr/bin/env bash
# ==========================================================================
# wait-deploy.sh · 等线上真的更新了再回话
#
# 为什么需要它：
#   curl 拿到 HTTP 200 只说明「站点活着」，不代表「新代码上线了」。
#   GitHub Pages 在新构建完成前，一直服务上一次的旧版本——
#   这段时间访问是 200，但内容是旧的。用状态码判断部署 = 误报。
#
# 用法：
#   bash tools/wait-deploy.sh "mechLine"          # 等某个标记出现在线上
#   bash tools/wait-deploy.sh "mechLine" 30       # 最多等 30 次 × 5 秒
#
# 原理：轮询线上 HTML，直到出现你给的那个字符串。
# ==========================================================================
set -u

MARKER="${1:-}"
TRIES="${2:-24}"
URL="${URL:-https://niuyongtaigr-oss.github.io/luggage-please-wait/}"

if [ -z "$MARKER" ]; then
  echo "用法: bash tools/wait-deploy.sh <线上应出现的字符串> [轮询次数]"
  echo "例:   bash tools/wait-deploy.sh mechLine"
  exit 2
fi

echo "等待线上出现「$MARKER」…"

for i in $(seq 1 "$TRIES"); do
  CODE=$(curl -s -o /tmp/_dep.html -w "%{http_code}" "$URL")
  HIT=$(grep -c -- "$MARKER" /tmp/_dep.html 2>/dev/null || true)
  HIT=${HIT:-0}

  if [ "$HIT" -gt 0 ]; then
    echo "✓ 第 $((i*5)) 秒：已上线（HTTP $CODE，标记命中 $HIT 处）"
    exit 0
  fi
  echo "  $((i*5))s  HTTP $CODE  标记未出现（页面还是旧的）"
  sleep 5
done

echo "✗ 超时：${TRIES} 次轮询后仍未看到「$MARKER」"
echo "  可能原因："
echo "    1. 忘了 git push"
echo "    2. Pages 构建失败 —— 看 https://github.com/niuyongtaigr-oss/luggage-please-wait/deployments"
echo "    3. 标记字符串写错了"
exit 1
