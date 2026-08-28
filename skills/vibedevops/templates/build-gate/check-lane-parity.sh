#!/usr/bin/env bash
# 车道同步检查 —— self-hosted runner 是否具备契约要求的工具集。
# 「同一 job 两车道结果一致」的机械保证：切到 self-hosted 前先跑这道；缺工具即非零退出、
# 明说缺哪些、会在哪假红。也可定期跑（额度没耗尽时）提前发现漂移，留时间修 xserver。
# 判据以系统 PATH 为准（apt 装的 git/docker/ruby 等在 /usr/bin，root 与 runner(gha) 同见）。
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${LANE_PARITY_MANIFEST:-$DIR/lane-parity-manifest.txt}"
[ -f "$MANIFEST" ] || { echo "⛔ parity manifest 不存在: $MANIFEST" >&2; exit 2; }

missing=""; total=0
while IFS= read -r raw; do
  cmd="${raw%%#*}"; cmd="$(printf '%s' "$cmd" | tr -d '[:space:]')"
  [ -n "$cmd" ] || continue
  total=$((total + 1))
  command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
done < "$MANIFEST"

if [ -n "$missing" ]; then
  echo "⛔ 车道不同步：self-hosted 缺工具:${missing}" >&2
  echo "   这些 job 切到 self-hosted 会假红（hosted 有、这里没有）。" >&2
  echo "   修法：把缺的工具加进 xserver-bootstrap 的 apt-packages-ours.txt 并 apt-get install。" >&2
  exit 1
fi
echo "✓ 车道同步：${total} 项契约工具齐备（self-hosted 可与 hosted 出一致结果）"
exit 0
