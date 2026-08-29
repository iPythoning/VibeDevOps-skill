#!/usr/bin/env bash
# ADR 0013 机械校验：车道模型 B + 两车道同步的关键不变量必须在模板里落地。
set -u
F=skills/vibedevops/templates/ci/runner-failover.sh
R=skills/vibedevops/templates/build-gate/onboard-reconcile.sh
bad=0

[ -f skills/vibedevops/templates/build-gate/lane-parity-manifest.txt ] \
  || { echo "❌ ADR 0013 §三: 缺 lane-parity-manifest.txt（工具齐备契约）"; bad=1; }
[ -f skills/vibedevops/templates/build-gate/check-lane-parity.sh ] \
  || { echo "❌ ADR 0013 §三: 缺 check-lane-parity.sh（切换前 parity 门）"; bad=1; }

grep -q 'state_get managed_list' "$F" \
  || { echo "❌ ADR 0013 §二: failover 无 managed_list 安全阀（切回可能误删非本脚本设的变量）"; bad=1; }
grep -q 'for repo in ${prev}' "$F" \
  || { echo "❌ ADR 0013 §二: 切回未按 managed_list(prev) 逐仓，安全阀失效"; bad=1; }
grep -q 'parity_ok' "$F" \
  || { echo "❌ ADR 0013 §三: failover 无切换前 parity 门"; bad=1; }
grep -q 'variable set LANE_MODE' "$F" \
  || { echo "❌ ADR 0013 §四: failover 未写 LANE_MODE（reconcile 协同失效）"; bad=1; }
grep -q 'LANE_MODE' "$R" \
  || { echo "❌ ADR 0013 §四: reconcile 未读 LANE_MODE（hosted 态会跟 failover 抢车道）"; bad=1; }

exit $bad
