#!/bin/bash
# verify-web —— 让 agent 自己确认「这个页面到底成不成立」（ADR 0011 能力层）。
#
# 为什么存在：`curl` 拿到 200 只证明服务器回了字节，证明不了页面能用——
# JS 报错、资源 404、首屏 5 秒、内存泄漏，全都是 200。而这些恰恰是
# 「门禁全绿但产品是坏的」那一类事故的栖息地（ADR 0009 / 0011）。
#
# 本脚本把「实际打开页面并采证」标准化成一条命令，产出机器可判的证据 JSON：
#   - console 错误与警告（页面自己喊疼）
#   - 失败请求（4xx/5xx/被阻断）
#   - 性能与内存指标（CDP Performance.getMetrics + navigation timing）
#   - 截图（人要看时才看，机器先判）
# 任一硬性判据越界即非零退出——于是它可以直接当门禁用。
#
# 依赖：ego-browser（提供 CDP 通道；`cdp('Performance.getMetrics')` 实测可用）。
# 用法：
#   verify-web.sh --url https://example.com [--out DIR] [--budget-load-ms 3000]
#                 [--budget-heap-mb 80] [--allow-console-errors] [--baseline FILE]
set -euo pipefail

URL=""; OUT="${VERIFY_OUT:-./verification-evidence}"; BUDGET_LOAD="${VERIFY_BUDGET_LOAD_MS:-0}"
BUDGET_HEAP="${VERIFY_BUDGET_HEAP_MB:-0}"; ALLOW_CONSOLE=0; BASELINE=""; LABEL=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) URL=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --budget-load-ms) BUDGET_LOAD=$2; shift 2 ;;
    --budget-heap-mb) BUDGET_HEAP=$2; shift 2 ;;
    --allow-console-errors) ALLOW_CONSOLE=1; shift ;;
    --baseline) BASELINE=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$URL" ] || { echo "必须给 --url" >&2; exit 2; }
case "$URL" in http://*|https://*) ;; *) echo "URL 必须带协议" >&2; exit 2 ;; esac
command -v ego-browser >/dev/null 2>&1 || { echo "缺 ego-browser（验证能力层的前提，见 ADR 0011）" >&2; exit 3; }

mkdir -p "$OUT"
LABEL="${LABEL:-$(printf '%s' "$URL" | sed 's|https\?://||; s|[^A-Za-z0-9]|-|g' | cut -c1-60)}"
EVIDENCE="$OUT/$LABEL.json"
SHOT="$OUT/$LABEL.png"

# ego-browser 的 heredoc 体是 Node 脚本；所有结果必须经 cliLog 出来。
# 单次 IIFE 取完页面侧数据（SKILL 明确：不要拆成多次 js() 调用）。
ego-browser nodejs <<EGOEOF > "$OUT/$LABEL.raw" 2>&1 || true
const task = await useOrCreateTaskSpace('verify-web ${LABEL}');
const consoleErrors = [];
const failedRequests = [];
let mainStatus = 0;
await cdp('Runtime.enable').catch(() => {});
await cdp('Network.enable').catch(() => {});
await openOrReuseTab('${URL}', { wait: true, timeout: 30 });
await waitForLoad().catch(() => {});
// drainEvents 收页面异步事件（导航/网络），是失败请求与运行时报错的来源
const events = await drainEvents().catch(() => []);
for (const e of (events || [])) {
  const m = e && (e.method || e.type) || '';
  const p = e && (e.params || e.payload) || {};
  if (m.includes('exceptionThrown')) consoleErrors.push(JSON.stringify(p).slice(0, 300));
  if (m.includes('consoleAPICalled') && p.type === 'error') consoleErrors.push(JSON.stringify(p.args || p).slice(0, 300));
  if (m.includes('loadingFailed')) failedRequests.push((p.errorText || 'failed') + ' ' + (p.type || ''));
  if (m.includes('responseReceived') && p.response) {
    if (p.type === 'Document' && !mainStatus) mainStatus = p.response.status;
    if (p.response.status >= 400) {
      failedRequests.push(p.response.status + ' ' + (p.response.url || '').slice(0, 160));
    }
  }
}
await cdp('Performance.enable').catch(() => {});
const perf = await cdp('Performance.getMetrics').catch(() => ({ metrics: [] }));
const metrics = {};
for (const m of (perf.metrics || [])) metrics[m.name] = m.value;
const page = await js(String.raw\`(() => {
  const n = performance.getEntriesByType('navigation')[0] || {};
  const errs = (window.__verifyErrors || []);
  return {
    title: document.title || '',
    dclMs: Math.round(n.domContentLoadedEventEnd || 0),
    loadMs: Math.round(n.loadEventEnd || 0),
    transferKB: Math.round((n.transferSize || 0) / 1024),
    domNodes: document.getElementsByTagName('*').length,
    pageErrors: errs.slice(0, 10),
  };
})()\`);
await captureScreenshot({ path: '${SHOT}' }).catch(() => {});
cliLog('__EVIDENCE__' + JSON.stringify({
  url: '${URL}', taskSpace: task.id, title: page.title,
  loadMs: page.loadMs, dclMs: page.dclMs, transferKB: page.transferKB,
  domNodes: page.domNodes,
  heapUsedMB: Math.round((metrics.JSHeapUsedSize || 0) / 1048576 * 10) / 10,
  heapTotalMB: Math.round((metrics.JSHeapTotalSize || 0) / 1048576 * 10) / 10,
  documents: metrics.Documents || 0,
  mainStatus,
  consoleErrors, failedRequests,
}));
EGOEOF

grep -o '__EVIDENCE__.*' "$OUT/$LABEL.raw" 2>/dev/null | sed 's/^__EVIDENCE__//' | head -1 > "$EVIDENCE" || true
if [ ! -s "$EVIDENCE" ]; then
  echo "❌ 采证失败——ego-browser 没有返回证据。原始输出：$OUT/$LABEL.raw" >&2
  tail -5 "$OUT/$LABEL.raw" >&2 2>/dev/null || true
  exit 4
fi

# ── 判据：机器先判，人只在需要时看截图 ──
FAIL=0
read_num() { python3 -c "import json,sys;d=json.load(open('$EVIDENCE'));print(d.get('$1',0) or 0)" 2>/dev/null || echo 0; }
count_arr() { python3 -c "import json;d=json.load(open('$EVIDENCE'));print(len(d.get('$1') or []))" 2>/dev/null || echo 0; }

LOAD=$(read_num loadMs); HEAP=$(read_num heapUsedMB)
CERR=$(count_arr consoleErrors); FREQ=$(count_arr failedRequests)

echo "── 验证证据 $URL ──"
python3 -c "
import json;d=json.load(open('$EVIDENCE'))
print(f\"  标题: {d.get('title','')[:60]}\")
print(f\"  首屏: DCL {d.get('dclMs')}ms / load {d.get('loadMs')}ms / 传输 {d.get('transferKB')}KB\")
print(f\"  内存: heap {d.get('heapUsedMB')}MB (总 {d.get('heapTotalMB')}MB) / DOM {d.get('domNodes')} 节点\")
for e in (d.get('consoleErrors') or [])[:3]: print(f\"  ⚠ console: {e[:120]}\")
for r in (d.get('failedRequests') or [])[:3]: print(f\"  ⚠ 请求失败: {r[:120]}\")
" 2>/dev/null || cat "$EVIDENCE"

# 「页面真的加载了吗」——不加这道，打开错误页/空白页也会报通过（实测踩过：
# --url http://x 解析到无关主机，无 console 错误、无失败请求，于是判"✅ 通过"）。
# 局限：mainStatus 依赖 drainEvents 抓到主文档的 responseReceived，实测常为 0
# （Network.enable 晚于导航时事件已流走）。所以真正兜底的是 domNodes 判据。
MAIN=$(read_num mainStatus); NODES=$(read_num domNodes)
if [ "${MAIN%.*}" != "0" ] && [ "${MAIN%.*}" -ge 400 ] 2>/dev/null; then
  echo "❌ 主文档 HTTP ${MAIN}——页面根本没加载成功" >&2; FAIL=1
fi
if [ "${NODES%.*}" -lt 40 ] 2>/dev/null; then
  echo "❌ DOM 只有 ${NODES} 个节点——多半是错误页/空白页，不是目标页面" >&2; FAIL=1
fi

if [ "$ALLOW_CONSOLE" = "0" ] && [ "$CERR" -gt 0 ]; then
  echo "❌ 页面有 $CERR 条 console 错误（--allow-console-errors 可豁免）" >&2; FAIL=1
fi
if [ "$FREQ" -gt 0 ]; then echo "❌ 有 $FREQ 个请求失败（4xx/5xx/被阻断）" >&2; FAIL=1; fi
if [ "$BUDGET_LOAD" != "0" ] && [ "${LOAD%.*}" -gt "$BUDGET_LOAD" ] 2>/dev/null; then
  echo "❌ 首屏 ${LOAD}ms 超预算 ${BUDGET_LOAD}ms" >&2; FAIL=1
fi
if [ "$BUDGET_HEAP" != "0" ] && [ "${HEAP%.*}" -gt "$BUDGET_HEAP" ] 2>/dev/null; then
  echo "❌ 堆 ${HEAP}MB 超预算 ${BUDGET_HEAP}MB" >&2; FAIL=1
fi
# 基线对比：回归检测（性能退化 >30% 视为退化）
if [ -n "$BASELINE" ] && [ -f "$BASELINE" ]; then
  python3 - "$BASELINE" "$EVIDENCE" << 'PYEOF' || FAIL=1
import json, sys
b = json.load(open(sys.argv[1])); c = json.load(open(sys.argv[2]))
bad = False
for k, unit in (('loadMs','ms'), ('heapUsedMB','MB'), ('domNodes','')):
    ov, nv = (b.get(k) or 0), (c.get(k) or 0)
    if ov and nv > ov * 1.3:
        print(f"❌ 回归: {k} {ov}{unit} → {nv}{unit} (+{round((nv/ov-1)*100)}%)"); bad = True
sys.exit(1 if bad else 0)
PYEOF
fi

[ "$FAIL" = "0" ] && echo "✅ 验证通过 · 证据 $EVIDENCE · 截图 $SHOT" || echo "证据留档: $EVIDENCE / $SHOT" >&2
exit "$FAIL"
