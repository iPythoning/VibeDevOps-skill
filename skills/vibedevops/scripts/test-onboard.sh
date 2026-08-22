#!/bin/bash
# onboard-reconcile 守卫测试：不覆盖已有变量 / 平台侧判定 / skip 清单 / 单仓模式。
set -e

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/skills/vibedevops/templates/build-gate/onboard-reconcile.sh"
FIXTURE="$(mktemp -d)"
trap 'code=$?; [ "$code" -eq 0 ] || echo "onboard fixture failed near line $LINENO" >&2; rm -rf "$FIXTURE"' EXIT

TOOLS="$FIXTURE/tools"
RUNNERS="$FIXTURE/runners"
CALLS="$FIXTURE/calls.log"
mkdir -p "$TOOLS" "$RUNNERS/template-runner" "$FIXTURE/units"
: > "$CALLS"

# 模板 runner 目录（rsync 的源）+ 假 config.sh
cat > "$RUNNERS/template-runner/config.sh" <<'EOF'
#!/bin/sh
echo "config $*" >> "$ONBOARD_TEST_CALLS"
exit 0
EOF
cat > "$RUNNERS/template-runner/run.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$RUNNERS/template-runner/config.sh" "$RUNNERS/template-runner/run.sh"

# ── mock curl：fixture API。仓况：
#   repo-a  有 workflows / 无 runner / 无变量        → 应注册 + 全量补变量
#   repo-b  有 workflows / 已有 runner / 只缺 1 变量 → 不注册、只补缺的
#   repo-c  无 workflows                             → 不动
#   repo-skip 有 workflows 但在 skip 清单            → 不动
cat > "$TOOLS/curl" <<'EOF'
#!/bin/bash
URL=""; POST=0; CODE_ONLY=0
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
  a="${ARGS[$i]}"
  case "$a" in
    http*) URL="$a" ;;
    -X) [ "${ARGS[$((i+1))]}" = "POST" ] && POST=1 ;;
    -w) CODE_ONLY=1 ;;
  esac
done
[ "$POST" = "1" ] && echo "POST $URL" >> "$ONBOARD_TEST_CALLS"
case "$URL" in
  *"&page=1") echo '[{"name":"repo-a","archived":false,"fork":false},{"name":"repo-b","archived":false,"fork":false},{"name":"repo-c","archived":false,"fork":false},{"name":"repo-skip","archived":false,"fork":false},{"name":"repo-archived","archived":true,"fork":false}]' ;;
  */user/repos?*) echo '[]' ;;
  */repos/*/repo-c/contents/.github/workflows) [ "$CODE_ONLY" = "1" ] && printf 404 ;;
  */contents/.github/workflows) [ "$CODE_ONLY" = "1" ] && printf 200 ;;
  */repo-a/actions/runners/registration-token) echo '{"token":"fixture-reg-token"}' ;;
  */repo-a/actions/runners) echo '{"runners":[]}' ;;
  */repo-b/actions/runners) echo '{"runners":[{"name":"test-gha-repo-b","status":"online"}]}' ;;
  */repo-a/actions/variables?*) echo '{"variables":[]}' ;;
  */repo-b/actions/variables?*) echo '{"variables":[{"name":"CI_RUNNER"},{"name":"CD_RUNNER"},{"name":"VIBEDEVOPS_CONTROL_RUNNER"},{"name":"CD_BUILDX_DRIVER"},{"name":"CD_BUILD_CACHE"},{"name":"CD_BUILD_CACHE_FROM"}]}' ;;
  */actions/variables) [ "$CODE_ONLY" = "1" ] && printf 201 ;;
  *) [ "$CODE_ONLY" = "1" ] && printf 200 || echo '{}' ;;
esac
exit 0
EOF
# mock 掉需要 root/系统的工具
for t in systemctl chown runuser; do
  cat > "$TOOLS/$t" <<EOF
#!/bin/bash
echo "$t \$*" >> "\$ONBOARD_TEST_CALLS"
[ "$t" = runuser ] || exit 0
# runuser -u user -- env ... ./config.sh ... → 在当前目录直接跑 config.sh
shift 3; exec env "\$@"
EOF
  chmod 755 "$TOOLS/$t"
done
chmod 755 "$TOOLS/curl"

echo "repo-skip" > "$FIXTURE/skip.txt"
echo "fixture-pat" > "$FIXTURE/token"

run_reconcile() {
  PATH="$TOOLS:$PATH" ONBOARD_TEST_CALLS="$CALLS" \
  ONBOARD_OWNER=testowner \
  ONBOARD_TOKEN_FILE="$FIXTURE/token" \
  ONBOARD_RUNNERS_DIR="$RUNNERS" \
  ONBOARD_RUNNER_USER="$(id -un)" \
  ONBOARD_RUNNER_PREFIX="test-gha-" \
  ONBOARD_SKIP_FILE="$FIXTURE/skip.txt" \
  ONBOARD_LOG="$FIXTURE/reconcile.log" \
  ONBOARD_UNIT_DIR="$FIXTURE/units" \
  "$@" bash "$SCRIPT"
}

# ── 轮 1：全量对账 ──
run_reconcile env

# repo-a 注册了（config 恰好 1 次，且 url 指向 repo-a）
[ "$(grep -c '^config ' "$CALLS")" = "1" ] || { echo "FAIL: config.sh calls != 1"; cat "$CALLS"; exit 1; }
grep -q 'config .*repo-a' "$CALLS" || { echo "FAIL: registered wrong repo"; exit 1; }
# repo-a 补了全部 7 个变量；repo-b 只补缺的 1 个（CD_BUILD_NETWORK）——不覆盖已有
A_VARS=$(grep -c 'POST .*/repo-a/actions/variables$' "$CALLS" || true)
B_VARS=$(grep -c 'POST .*/repo-b/actions/variables$' "$CALLS" || true)
[ "$A_VARS" = "7" ] || { echo "FAIL: repo-a vars=$A_VARS (want 7)"; exit 1; }
[ "$B_VARS" = "1" ] || { echo "FAIL: repo-b vars=$B_VARS (want 1, never overwrite)"; exit 1; }
# repo-c（无 workflows）与 repo-skip（清单）完全不动
grep -qE 'POST .*/(repo-c|repo-skip)/' "$CALLS" && { echo "FAIL: touched repo-c/repo-skip"; exit 1; }
# 注册后拉起了单元
grep -q 'systemctl start github-actions-repo-a' "$CALLS" || { echo "FAIL: unit not started"; exit 1; }

# ── 轮 2：单仓模式只动目标仓 ──
: > "$CALLS"
rm -rf "$RUNNERS/repo-a"
run_reconcile env ONBOARD_ONLY_REPO=repo-b
grep -q 'config ' "$CALLS" && { echo "FAIL: only-mode registered something"; exit 1; }
grep -qE 'POST .*/repo-a/' "$CALLS" && { echo "FAIL: only-mode touched repo-a"; exit 1; }
[ "$(grep -c 'POST .*/repo-b/actions/variables$' "$CALLS")" = "1" ] || { echo "FAIL: only-mode repo-b vars"; exit 1; }

echo "onboard reconcile guardrails: OK"
