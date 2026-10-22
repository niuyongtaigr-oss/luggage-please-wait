#!/usr/bin/env bash
# ==========================================================================
# 行李箱请等等 · 端到端自测
# push 之前跑一次。全绿再推。
#   bash tools/selftest.sh
# 依赖：google-chrome（或 chromium）、python3。不需要网络。
# ==========================================================================
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="${CHROME:-$(command -v google-chrome || command -v chromium || command -v chromium-browser)}"

if [ -z "$CHROME" ]; then echo "✗ 找不到 Chrome，可用 CHROME=/path/to/chrome bash tools/selftest.sh"; exit 1; fi
if [ ! -f "$ROOT/index.html" ] || [ ! -f "$ROOT/data.js" ]; then echo "✗ index.html 或 data.js 不在 $ROOT"; exit 1; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/index.html" "$TMP/t.html"
cp "$ROOT/data.js"    "$TMP/data.js"

# 把一段走位脚本注入到副本里（不动源文件）
python3 - "$TMP/t.html" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
probe = """
<script>
window.__E__ = []; window.addEventListener('error', e => window.__E__.push(e.message));
const log = [], sleep = ms => new Promise(r => setTimeout(r, ms));
const cur = () => { const x = document.querySelector('.screen.on'); return x ? x.id : 'none'; };
(async () => {
  await sleep(150);

  // 1. Ctrl+K 预填 + 必填校验
  document.dispatchEvent(new KeyboardEvent('keydown', { key:'k', ctrlKey:true, bubbles:true }));
  if (!document.querySelector('#fAvoid').value) log.push('FAIL: Ctrl+K 没填上');
  document.querySelector('#btnSubmit').click();
  await sleep(2400);
  if (cur() !== 's-review') log.push('FAIL: 提交后没进审批页 (' + cur() + ')');

  // 2. 演示固定第 3 条
  if (document.querySelector('#revLeaving').textContent !== '这个城市') log.push('FAIL: 没锁死第 3 条');
  if (document.querySelector('#revIdx').textContent !== '12') log.push('FAIL: 第 12 份不对');

  // 3. 身份改副标
  document.querySelector('.id[data-id="你的钱包"]').click();
  if (!document.querySelector('.vote--think [data-sub]').textContent.includes('押一付三')) log.push('FAIL: 身份没改变按钮文案');

  // 4. 投票 -> 追加格出现
  document.querySelector('.vote[data-vote="think"]').click();
  await sleep(120);
  if (document.querySelector('#extraZone').hidden) log.push('FAIL: 再想想没出追加格');

  // 5. 护栏命中但不禁用
  const t = document.querySelector('#fReason');
  t.value = '活该，你就是怂'; t.dispatchEvent(new Event('input', { bubbles:true }));
  await sleep(120);
  if (document.querySelector('#guard').hidden) log.push('FAIL: 护栏没弹');
  if (document.querySelector('#btnVote').disabled) log.push('FAIL: 护栏把发送禁了');

  // 6. 改掉坏词，护栏收起
  t.value = '押一付三你算了三遍，其实你算的不是钱。';
  t.dispatchEvent(new Event('input', { bubbles:true }));
  await sleep(80);
  if (!document.querySelector('#guard').hidden) log.push('FAIL: 护栏没收起');

  // 7. 盖章 -> 判决书 + 计数
  document.querySelector('#btnVote').click();
  await sleep(3000);
  if (cur() !== 's-verdict') log.push('FAIL: 没进判决书 (' + cur() + ')');
  if (document.querySelector('#cSeen').textContent !== '41') log.push('FAIL: 41 不对');
  if (document.querySelector('#cThink').textContent !== '27') log.push('FAIL: 27 不对');
  if (!document.querySelector('#passFoot').textContent.includes('上一轮')) log.push('FAIL: 页脚没写上一轮');

  // 8. 换一条 + 翻面
  document.querySelector('#btnToSwap').click();
  await sleep(200);
  if (cur() !== 's-swap') log.push('FAIL: 没进换一条');
  if (document.querySelector('#cardName').textContent !== '杨浦滨江线') log.push('FAIL: 第一张不是杨浦');
  document.querySelector('#cardFront').click();
  if (!document.querySelector('#flip').classList.contains('flipped')) log.push('FAIL: 翻面没生效');

  // 9. 再抽一条
  document.querySelector('#btnNextCard').click();
  if (document.querySelector('#cardName').textContent !== '愚园线') log.push('FAIL: 再抽一条没换卡');

  if (window.__E__.length) log.push('FAIL: JS 报错 ' + window.__E__.join('|'));

  const d = document.createElement('div'); d.id = '__T__';
  d.textContent = log.length ? log.join(' ;; ') : 'ALLGREEN';
  document.body.appendChild(d);
})();
</script>
"""
open(p, "w", encoding="utf-8").write(s.replace("</body>", probe + "</body>"))
PY

echo "跑走位脚本…"
OUT="$("$CHROME" --headless=new --disable-gpu --window-size=1440,900 \
      --virtual-time-budget=25000 --dump-dom "file://$TMP/t.html?r=$RANDOM" 2>/dev/null)"

RESULT="$(printf '%s' "$OUT" | python3 -c "
import sys,re,html
d=sys.stdin.read()
m=re.search(r'id=\"__T__\">([^<]*)<', d)
print(html.unescape(m.group(1)) if m else 'NO OUTPUT — 页面没跑起来')
")"

if [ "$RESULT" = "ALLGREEN" ]; then
  echo "✓ 全部通过（9 组断言：预填 / 提交 / 锁池 / 身份 / 追加格 / 护栏 / 判决 / 换一条 / 翻面）"
  exit 0
else
  echo "✗ 有问题："
  printf '%s\n' "$RESULT" | tr ';' '\n' | sed '/^$/d'
  exit 1
fi
