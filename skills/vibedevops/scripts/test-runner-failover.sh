#!/usr/bin/env bash
# runner-failover 守卫测试（模型 B）：mock gh，验证车道切换 + 安全阀。
# 覆盖：① 额度耗尽+MODE=hosted → 切 self-hosted（逐仓 set_bundle、写 LANE_MODE）；
#      ② 额度重置+MODE=selfhosted → 切回 hosted，只删 managed_list 里的仓；
#      ③ 安全阀：不在 managed_list 的仓（人工/reconcile 设的）绝不被删；
#      ④ 额度未知 / 同态 → 不切换。反向变异：切回若用全量 REPOS 而非 managed_list，③ 必 FAIL。
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
RF="${RF_SCRIPT:-$ROOT/skills/vibedevops/templates/ci/runner-failover.sh}"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
BIN="$FIX/bin"; mkdir -p "$BIN"
CALLS="$FIX/calls.log"; : > "$CALLS"

cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "gh $*" >> "$MOCK_CALLS"
case "$*" in
  "auth status") exit 0 ;;
  "run list -R "*) echo "$MOCK_PROBE_LINE" ;;
  "api "*"/runs/"*"/jobs"*) echo "${MOCK_PROBE_PJ:-0}" ;;
  "api "*"?per_page=6"*) echo "" ;;
  "api "*"/actions/runners"*) echo "1" ;;
  "workflow run "*) exit 0 ;;
  "variable "*) exit 0 ;;
  "repo list "*) echo "" ;;
  *) echo "" ;;
esac
exit 0
EOF
chmod +x "$BIN/gh"

run_rf() {  # $1=probe状态 $2=lane_mode $3=managed_list
  local probe="$1" mode="$2" managed="$3"
  : > "$CALLS"
  cat > "$FIX/state.json" <<JSON
{"repos":"repo-a repo-b repo-c","repos_refreshed_epoch":$(date +%s),"lane_mode":"$mode","managed_list":"$managed","last_probe_epoch":$(date +%s)}
JSON
  local pl pj
  if [ "$probe" = exhausted ]; then pl="99 completed/failure"; pj=1
  elif [ "$probe" = available ]; then pl="99 completed/success"; pj=0
  else pl="99 completed/failure"; pj=0; fi
  RUNNER_FAILOVER_EXTRA_PATH="$BIN" MOCK_CALLS="$CALLS" MOCK_PROBE_LINE="$pl" MOCK_PROBE_PJ="$pj" \
  OWNER=testowner PROBE_REPO=testowner/hosted-canary PROBE_WORKFLOW=hosted-probe.yml \
  STATE_DIR="$FIX" STATE="$FIX/state.json" LOCKDIR="$FIX/lock.$RANDOM" LANE_PARITY_CMD="" \
  bash "$RF" >/dev/null 2>&1 || true
}

echo "== ①额度耗尽+hosted → 切 self-hosted =="
run_rf exhausted hosted ""
grep -q 'variable set CI_RUNNER -R testowner/repo-a' "$CALLS" || { echo "FAIL①: 没给 repo-a 设 CI_RUNNER"; cat "$CALLS"; exit 1; }
grep -q 'variable set CI_RUNNER -R testowner/repo-c' "$CALLS" || { echo "FAIL①: 没给 repo-c 设 CI_RUNNER"; exit 1; }
grep -q 'variable set LANE_MODE --body selfhosted' "$CALLS" || { echo "FAIL①: 没写 LANE_MODE=selfhosted"; exit 1; }
[ "$(jq -r .lane_mode "$FIX/state.json")" = selfhosted ] || { echo "FAIL①: state.lane_mode 未置 selfhosted"; exit 1; }
[ "$(jq -r .managed_list "$FIX/state.json")" = "repo-a repo-b repo-c" ] || { echo "FAIL①: managed_list 未记录"; exit 1; }
echo "  OK"

echo "== ②③额度重置+selfhosted，managed=a b → 只删 a b，绝不删 c(安全阀) =="
run_rf available selfhosted "repo-a repo-b"
grep -q 'variable delete CI_RUNNER -R testowner/repo-a' "$CALLS" || { echo "FAIL②: 没删 repo-a"; exit 1; }
grep -q 'variable delete CI_RUNNER -R testowner/repo-b' "$CALLS" || { echo "FAIL②: 没删 repo-b"; exit 1; }
grep -q 'variable delete CI_RUNNER -R testowner/repo-c' "$CALLS" && { echo "FAIL③(安全阀): 删了不在 managed_list 的 repo-c！"; exit 1; }
grep -q 'variable set LANE_MODE --body hosted' "$CALLS" || { echo "FAIL②: 没写 LANE_MODE=hosted"; exit 1; }
[ "$(jq -r .lane_mode "$FIX/state.json")" = hosted ] || { echo "FAIL②: state.lane_mode 未置 hosted"; exit 1; }
echo "  OK"

echo "== ④额度未知 → 不切换 =="
run_rf unknown selfhosted "repo-a"
grep -qE 'variable (set|delete)' "$CALLS" && { echo "FAIL④: 额度未知却动了变量"; exit 1; }
echo "  OK"

echo "== ⑤同态（额度耗尽已在 selfhosted）→ 不切换 =="
run_rf exhausted selfhosted "repo-a repo-b repo-c"
grep -qE 'variable (set|delete) CI_RUNNER' "$CALLS" && { echo "FAIL⑤: 同态却切换了"; exit 1; }
echo "  OK"

echo "runner-failover guardrails: OK"
