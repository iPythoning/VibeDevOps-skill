#!/usr/bin/env bash
# ADR ↔ templates 机械对账（ADR 0012）。
# 根因治理：12 条 ADR 全靠人记得去实现，已多次「决策写了、templates 没做」。此脚本把
# 「每条 ADR 决策 → 可执行校验」变成机械强制：
#   1) 跑 docs/adr/checks/*.sh 里每条不变量校验（当前锁定 0006/0009/0012）；
#   2) 强制覆盖：每条 ADR（0001+）要么有 checks/NNNN-*.sh，要么在 EXEMPT.tsv 显式豁免。
# 新 ADR 若既不加 check 也不豁免 → 本对账 FAIL，无法静默漏实现。
set -u
cd "$(dirname "$0")/../../.." || { echo "无法定位仓库根"; exit 2; }
CHECKS=docs/adr/checks
EXEMPT="$CHECKS/EXEMPT.tsv"
fail=0

echo "── 1. ADR 不变量校验 ──"
ran=0
for c in "$CHECKS"/[0-9]*.sh; do
  [ -f "$c" ] || continue
  ran=$((ran + 1))
  if bash "$c"; then echo "  ✓ $(basename "$c")"; else echo "  ✗ $(basename "$c") 未通过"; fail=1; fi
done
[ "$ran" -gt 0 ] || { echo "  ⚠️ 没有任何 checks/*.sh——对账形同虚设"; fail=1; }

echo "── 2. ADR 覆盖强制（每条 ADR 必须有 check 或显式豁免）──"
for adr in docs/adr/0[0-9][0-9][0-9]-*.md; do
  [ -f "$adr" ] || continue
  n=$(basename "$adr" | cut -c1-4)
  [ "$n" = 0000 ] && continue
  ls "$CHECKS/$n"-*.sh >/dev/null 2>&1 && continue
  if awk -F'\t' -v n="$n" '$1==n{f=1} END{exit !f}' "$EXEMPT" 2>/dev/null; then continue; fi
  echo "  ✗ ADR $n（$(basename "$adr")）既无 $CHECKS/$n-*.sh 也不在 EXEMPT.tsv"
  echo "      → 加一条可执行校验，或在 EXEMPT.tsv 写明为何无静态不变量。"
  fail=1
done

if [ "$fail" = 0 ]; then echo "ADR 机械对账：全部通过 ✓"; else echo "ADR 机械对账：有未满足项 ✗"; fi
exit $fail
