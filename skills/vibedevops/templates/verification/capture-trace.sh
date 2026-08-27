#!/bin/bash
# capture-trace —— 抓 CPU trace / heap snapshot，让「慢」和「泄漏」有据可查（ADR 0011 能力层）。
#
# 为什么单独一个脚本：verify-web.sh 是常态门禁（每次改动都跑，要快）；trace 与
# heap 是**诊断**工具（页面级 700KB / 堆 45MB 起步），按需触发。
#
# 实测跑通（本机 ego-browser + Chromium）：
#   - Tracing.start → IO.read 流式拼接 → 3,140 条 traceEvents / 747KB，
#     产物可直接拖进浏览器 DevTools 的 Performance 面板
#   - HeapProfiler.takeHeapSnapshot → addHeapSnapshotChunk 拼接 → 645,822 节点 /
#     2,182,346 边 / 45MB .heapsnapshot
#
# 用法：capture-trace.sh --url URL [--out DIR] [--mode trace|heap|both] [--cpu-throttle N]
set -euo pipefail

URL=""; OUT="${TRACE_OUT:-./verification-evidence}"; MODE="both"; THROTTLE=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) URL=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --mode) MODE=$2; shift 2 ;;
    --cpu-throttle) THROTTLE=$2; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$URL" ] || { echo "必须给 --url" >&2; exit 2; }
case "$MODE" in trace|heap|both) ;; *) echo "--mode 只能是 trace|heap|both" >&2; exit 2 ;; esac
command -v ego-browser >/dev/null 2>&1 || { echo "缺 ego-browser（见 ADR 0011 能力层）" >&2; exit 3; }
mkdir -p "$OUT"
LABEL=$(printf '%s' "$URL" | sed 's|https\?://||; s|[^A-Za-z0-9]|-|g' | cut -c1-50)

ego-browser nodejs <<EGOEOF
const task = await useOrCreateTaskSpace('capture-trace ${LABEL}');
const MODE = '${MODE}';
const out = [];

if (MODE === 'trace' || MODE === 'both') {
  // CPU 节流让性能问题在快机器上也暴露出来（1=不节流）
  // 顺序要紧：Tracing 绑在当前 target 上，先 openOrReuseTab 会换 target 导致
  // Tracing.end 报 "Tracing is not started"（实测踩中）。所以：先把页开好，
  // 再 start，再用 reload 触发一次完整导航，让首屏落进 trace。
  await openOrReuseTab('${URL}', { wait: true, timeout: 30 });
  await waitForLoad().catch(() => {});
  if (${THROTTLE} > 1) await cdp('Emulation.setCPUThrottlingRate', { rate: ${THROTTLE} }).catch(() => {});
  await cdp('Tracing.start', {
    transferMode: 'ReturnAsStream',
    traceConfig: { includedCategories: ['devtools.timeline', 'blink.user_timing', 'loading', 'v8.execute'] },
  });
  await cdp('Page.reload', { ignoreCache: true }).catch(() => {});
  await waitForLoad().catch(() => {});
  await wait(2);                       // 单位是秒
  await cdp('Tracing.end');
  await wait(1);
  const evs = await drainEvents().catch(() => []);
  const done = (evs || []).find(e => (e.method || '').includes('tracingComplete'));
  const handle = done && done.params && done.params.stream;
  if (handle) {
    let data = '', eof = false;
    while (!eof) {
      const chunk = await cdp('IO.read', { handle, size: 1048576 });
      data += (chunk.data || ''); eof = !!chunk.eof;
    }
    await cdp('IO.close', { handle }).catch(() => {});
    const fs = await import('node:fs');
    fs.writeFileSync('${OUT}/${LABEL}.trace.json', data);
    let n = 0; try { n = (JSON.parse(data).traceEvents || []).length; } catch {}
    out.push('trace: ${OUT}/${LABEL}.trace.json (' + Math.round(data.length/1024) + 'KB, ' + n + ' events)');
  } else {
    out.push('trace: FAILED — 没收到 tracingComplete 流句柄');
  }
}

if (MODE === 'heap' || MODE === 'both') {
  await openOrReuseTab('${URL}', { wait: true, timeout: 30 });
  await waitForLoad().catch(() => {});
  const light = await cdp('Runtime.getHeapUsage').catch(() => ({}));
  await cdp('HeapProfiler.enable').catch(() => {});
  await cdp('HeapProfiler.takeHeapSnapshot', { reportProgress: false });
  await wait(2);
  const evs = await drainEvents().catch(() => []);
  const chunks = (evs || [])
    .filter(e => (e.method || '').includes('addHeapSnapshotChunk'))
    .map(e => (e.params && e.params.chunk) || '');
  if (chunks.length) {
    const fs = await import('node:fs');
    const data = chunks.join('');
    fs.writeFileSync('${OUT}/${LABEL}.heapsnapshot', data);
    let nodes = 0; try { nodes = (JSON.parse(data).snapshot || {}).node_count || 0; } catch {}
    out.push('heap: ${OUT}/${LABEL}.heapsnapshot (' + Math.round(data.length/1048576) + 'MB, ' + nodes + ' nodes)');
  } else {
    out.push('heap: FAILED — 没收到快照分片');
  }
  out.push('heapUsed: ' + Math.round((light.usedSize || 0) / 1048576 * 10) / 10 + 'MB');
}

cliLog(out.join('\n'));
EGOEOF

cat <<'TIPEOF'

产物用法：
  .trace.json      → 拖进浏览器 DevTools 的 Performance 面板（Load profile）
  .heapsnapshot    → 拖进 Memory 面板；两次快照对比才能定位泄漏
边界（实测）：
  - 单次 heap 快照可达数十 MB，多次对比容易吃满内存——按需抓，别进常态门禁
  - 浏览器扩展会在 trace/coverage 里留下 chrome-extension:// 噪音，分析时先过滤
  - 本机若有代理/TUN，会混入 ERR_TUNNEL_CONNECTION_FAILED 之类的**环境错误**，
    不要当成站点问题——判断前先在无代理环境复测一次
TIPEOF
