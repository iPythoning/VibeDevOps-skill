#!/usr/bin/env bash
# runner-failover.sh — CI 额度/账单故障自动切换 watcher（无人值守闭环，通用模板）
#
# 解决的问题：CI 服务（GitHub Actions 等）额度耗尽/账单异常时，job 会【静默失败】
# ——失败但 0 步、无 runner，看着像代码红实则是账单红。本脚本自动识别这类签名，
# 把纳管仓整体切到自建 runner；等 CI 恢复再自动切回。
#
# 部署：在一台常驻机上定时跑（cron / systemd timer / launchd，如每 10 分钟）。
#
# 模型 B（hosted 主，self-hosted 只做额度耗尽 failover）：
#   探针判额度：只看探针仓一个 hosted job（0 步/无 runner=额度拒绝），绝不拿业务仓当判据。
#   额度耗尽 → 过车道同步门(parity) → 逐仓设 bundle 切 self-hosted，写 LANE_MODE=selfhosted。
#   额度重置 → 只 del 本脚本 managed_list 里的仓，切回 hosted，写 LANE_MODE=hosted。
#   同步保证：切 self-hosted 前跑 LANE_PARITY_CMD（同一 job 两车道结果必须一致）；空=降级放行。
#
# 安全阀：
#   - 只回收"本脚本设置的"变量（state.managed=true）；人工设的路由永不动。
#   - runner 不在线的仓不切（否则 job 永远 queued 是更危险的静默失败）。
#
# 占位符：
#   OWNER        GitHub owner/org。留空则自动从 `gh repo view` 推断
#   PROBE_REPO   探针仓 OWNER/REPO：一个只含"钉死托管 runner 的 workflow"的专用仓
#   PROBE_WORKFLOW  探针 workflow 文件名
#   RUNNER_LABEL 切到自建时写入 CI_RUNNER/CD_RUNNER 的标签数组
#   STATE_DIR    状态/日志目录（默认 ~/.runner-failover）
set -u
PATH="${RUNNER_FAILOVER_EXTRA_PATH:+$RUNNER_FAILOVER_EXTRA_PATH:}/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"   # 覆盖常见 gh/jq 安装位

OWNER="${OWNER:-$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)}"
PROBE_REPO="${PROBE_REPO:-${OWNER}/hosted-probe}"
PROBE_WORKFLOW="${PROBE_WORKFLOW:-hosted-probe.yml}"
RUNNER_LABEL="${RUNNER_LABEL:-[\"self-hosted\",\"builder\"]}"
STATE_DIR="${STATE_DIR:-$HOME/.runner-failover}"

STATE="${STATE_DIR}/state.json"
LOG="${STATE_DIR}/failover.log"
LOCKDIR="${TMPDIR:-/tmp}/runner-failover.lock"
PROBE_INTERVAL="${PROBE_INTERVAL:-3600}"        # 故障态多久探一次恢复
DETECT_WINDOW_MIN="${DETECT_WINDOW_MIN:-45}"    # 只看最近这么多分钟内的失败
DISCOVER_INTERVAL="${DISCOVER_INTERVAL:-21600}" # 6h 刷新一次纳管仓清单
mkdir -p "${STATE_DIR}"

[ -n "${OWNER}" ] || { echo "❌ 无法确定 OWNER"; exit 2; }

log() { echo "[$(date '+%F %T')] $*" >> "${LOG}"; }
# 通知：mac 用 osascript 弹通知（可选，Linux 无）；改成你的通知渠道（IM webhook / mail）更好
notify() {
  log "NOTIFY: $*"
  command -v osascript >/dev/null 2>&1 \
    && osascript -e "display notification \"$*\" with title \"runner-failover\"" 2>/dev/null || true
}
state_get() { [ -f "${STATE}" ] && jq -r ".$1 // empty" "${STATE}" 2>/dev/null || true; }
state_set() {
  tmp=$(mktemp)
  { [ -f "${STATE}" ] && cat "${STATE}" || echo '{}'; } | jq ".$1 = $2" > "${tmp}" && mv "${tmp}" "${STATE}"
}

# ── 切换用的变量包 ──
# 默认最小包（只切 runner 标签）。若某仓在自建车道还需镜像站/缓存等变量，
# 按仓在此扩展：给该仓返回一组变量名，并在 var_value 里给出对应取值。
bundle_keys() {
  # 示例扩展点（按仓配置）：
  #   case "$1" in
  #     my-python-svc) echo "CI_RUNNER CD_RUNNER CI_REGISTRY_MIRROR CI_PIP_INDEX_URL" ;;
  #     *)             echo "CI_RUNNER CD_RUNNER" ;;
  #   esac
  echo "CI_RUNNER CD_RUNNER"
}
var_value() {
  case "$1" in
    CI_RUNNER|CD_RUNNER)  printf '%s' "${RUNNER_LABEL}" ;;
    # 若在 bundle_keys 里加了镜像站/缓存变量，在此补对应取值：
    # CI_REGISTRY_MIRROR) printf '%s' 'docker.m.daocloud.io/' ;;
    # CI_PIP_INDEX_URL)   printf '%s' 'https://mirrors.aliyun.com/pypi/simple/' ;;
  esac
}

# ── 纳管范围 = 自动发现：owner 名下 30 天内有推送 + 已注册 self-hosted runner 的私有仓 ──
# 新仓注册 runner 后自动进保护圈，无需改本脚本。
discover_repos() {
  now=$(date +%s); last=$(state_get repos_refreshed_epoch); last=${last:-0}
  cached=$(state_get repos)
  if [ -n "${cached}" ] && [ $((now - last)) -lt "${DISCOVER_INTERVAL}" ]; then
    printf '%s' "${cached}"; return
  fi
  found=""
  for name in $(gh repo list "${OWNER}" --limit 100 --json name,visibility,pushedAt \
      --jq '.[] | select(.visibility=="PRIVATE" and (.pushedAt > (now-2592000|todate))) | .name' 2>/dev/null); do
    [ "${OWNER}/${name}" = "${PROBE_REPO}" ] && continue
    n=$(gh api "repos/${OWNER}/${name}/actions/runners" --jq '.runners | length' 2>/dev/null || echo 0)
    [ "${n:-0}" -gt 0 ] && found="${found} ${name}"
  done
  found="${found# }"
  if [ -n "${found}" ]; then
    state_set repos "\"${found}\""
    state_set repos_refreshed_epoch "${now}"
    log "纳管仓清单已刷新: ${found}"
    printf '%s' "${found}"
  else
    printf '%s' "${cached}"                      # 发现失败沿用旧清单，不缩圈
  fi
}

repo_in_failover() { gh variable list -R "${OWNER}/$1" 2>/dev/null | awk '{print $1}' | grep -qx CI_RUNNER; }
runner_online() {
  gh api "repos/${OWNER}/$1/actions/runners" \
    --jq '[.runners[] | select(.status=="online")] | length' 2>/dev/null | grep -qv '^0$'
}
# 账单/额度拒绝签名：最近窗口内存在 conclusion=failure 的 run，其中有 0 步且无 runner 的 failed job
billing_sig() {
  cutoff=$(date -u -v-"${DETECT_WINDOW_MIN}"M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
           || date -u -d "-${DETECT_WINDOW_MIN} min" '+%Y-%m-%dT%H:%M:%SZ')  # BSD/GNU date 两种写法
  for rid in $(gh api "repos/${OWNER}/$1/actions/runs?per_page=6" \
      --jq ".workflow_runs[] | select(.conclusion==\"failure\" and .created_at > \"${cutoff}\") | .id" 2>/dev/null); do
    n=$(gh api "repos/${OWNER}/$1/actions/runs/${rid}/jobs" \
      --jq '[.jobs[] | select(.conclusion=="failure" and (.steps|length)==0 and .runner_name==null)] | length' 2>/dev/null || echo 0)
    [ "${n:-0}" -gt 0 ] && return 0
  done
  return 1
}
set_bundle() { for k in $(bundle_keys "$1"); do var_value "$k" | gh variable set "$k" -R "${OWNER}/$1" || log "WARN set $1/$k 失败"; done; }
del_bundle() { for k in $(bundle_keys "$1"); do gh variable delete "$k" -R "${OWNER}/$1" 2>/dev/null || true; done; }

# ── 并发锁 ──
if ! mkdir "${LOCKDIR}" 2>/dev/null; then
  # 超过 30 分钟的锁视为残留
  [ -n "$(find "${LOCKDIR}" -maxdepth 0 -mmin +30 2>/dev/null)" ] \
    && rmdir "${LOCKDIR}" 2>/dev/null && mkdir "${LOCKDIR}" 2>/dev/null || exit 0
fi
trap 'rmdir "${LOCKDIR}" 2>/dev/null' EXIT

command -v gh >/dev/null || { log "gh 不在 PATH，跳过"; exit 0; }
command -v jq >/dev/null || { log "jq 不在 PATH，跳过"; exit 0; }
gh auth status >/dev/null 2>&1 || { log "gh 未登录，跳过"; exit 0; }

REPOS=$(discover_repos)
[ -n "${REPOS}" ] || { log "纳管清单为空且无缓存，跳过本轮"; exit 0; }
# ── 车道同步门（同一 job 两车道结果必须一致）——切 self-hosted 前核验目标车道能跑 ──
# LANE_PARITY_CMD：核验命令（如 'ssh builder /usr/local/sbin/check-lane-parity'）；空=不设门（降级放行）。
LANE_PARITY_CMD="${LANE_PARITY_CMD:-}"
PARITY_MSG=""
parity_ok() {
  [ -n "${LANE_PARITY_CMD}" ] || return 0
  PARITY_MSG=$(eval "${LANE_PARITY_CMD}" 2>&1); local rc=$?
  [ "$rc" = 255 ] && { PARITY_MSG="parity 命令不可达（网络？）"; return 2; }
  return "$rc"
}

# ── 基建级失败自愈（两态都跑）──
# self-hosted 断连会把 job 打成 Abandoned：conclusion=failure 但没有任何 failed step，
# 且 runner 已被分配过——这是基建签名不是代码红，自动重跑（每 run 最多补 2 次）。
infra_heal() {
  cutoff=$(date -u -v-90M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '-90 min' '+%Y-%m-%dT%H:%M:%SZ')
  for repo in ${REPOS}; do
    for rid in $(gh api "repos/${OWNER}/${repo}/actions/runs?per_page=6" \
        --jq ".workflow_runs[] | select(.conclusion==\"failure\" and .created_at > \"${cutoff}\") | .id" 2>/dev/null); do
      tries=$(state_get "heal_${rid}"); tries=${tries:-0}
      [ "${tries}" -ge 2 ] && continue
      sig=$(gh api "repos/${OWNER}/${repo}/actions/runs/${rid}/jobs" --jq \
        '[.jobs[] | select(.conclusion=="failure")] as $f
         | if ($f|length)>0 and ([$f[] | select((.runner_name // "") != "") | select(([.steps[] | select(.conclusion=="failure")]|length)==0)]|length) == ($f|length)
           then "infra" else "code" end' 2>/dev/null)
      if [ "${sig}" = "infra" ]; then
        gh run rerun "${rid}" -R "${OWNER}/${repo}" --failed 2>/dev/null \
          && state_set "heal_${rid}" $((tries+1)) \
          && log "自愈重跑 ${repo} run=${rid}（第 $((tries+1)) 次，断连型失败）"
      fi
    done
  done
}
infra_heal

# ===== 车道状态机（模型 B：hosted 主，额度耗尽才走 self-hosted，重置切回）=====
# MODE=上次切到的车道；managed_list=本脚本自己设过 bundle 的仓。安全阀（老回切炸弹病根修复）：
# ① 只在【模式真正切换】时动作，不是每次探针成功都动；② 切回只删 managed_list 里的仓，绝不碰
# 人工/reconcile 设的；③ 删除失败不吞、告警；④ 切 self-hosted 前过 parity 门。
MODE=$(state_get lane_mode); MODE=${MODE:-hosted}
now=$(date +%s); last=$(state_get last_probe_epoch); last=${last:-0}

# 探针判额度：只看探针仓一个 hosted job（0 步/无 runner=额度拒绝），绝不拿业务仓当判据
prid=$(gh run list -R "${PROBE_REPO}" --workflow "${PROBE_WORKFLOW}" --limit 1 --json databaseId,status,conclusion --jq '.[0]|"\(.databaseId) \(.status)/\(.conclusion)"' 2>/dev/null || true)
probe=$(printf '%s' "${prid}" | cut -d' ' -f2); pid=$(printf '%s' "${prid}" | cut -d' ' -f1)
quota=unknown
if [ "${probe}" = "completed/success" ]; then
  quota=available
elif [ "${probe}" = "completed/failure" ] && [ -n "${pid}" ]; then
  pj=$(gh api "repos/${PROBE_REPO}/actions/runs/${pid}/jobs" --jq '[.jobs[]|select((.steps|length)==0 and ((.runner_name // "")==""))]|length' 2>/dev/null || echo 0)
  [ "${pj:-0}" -gt 0 ] && quota=exhausted
fi

# 到点补发探针（额度坏时被拒零成本），保证下一轮有新鲜判据
if [ $((now - last)) -ge "${PROBE_INTERVAL}" ]; then
  gh workflow run "${PROBE_WORKFLOW}" -R "${PROBE_REPO}" 2>/dev/null && state_set last_probe_epoch "${now}" && log "探针已 dispatch（上次: ${probe:-无}, quota=${quota}）"
fi

[ "${quota}" = unknown ] && { log "额度状态未知（probe=${probe:-无}），本轮不切换"; exit 0; }
desired=hosted; [ "${quota}" = exhausted ] && desired=selfhosted

if [ "${desired}" = "${MODE}" ]; then
  # 无切换：self-hosted 态顺带跑 parity，提前发现漂移（网络失败不误报）
  if [ "${desired}" = selfhosted ]; then
    parity_ok; pr=$?
    [ "${pr}" = 1 ] && notify "⚠️ self-hosted 车道漂移：${PARITY_MSG}（同一 job 可能假红，尽快修构建机）"
  fi
  exit 0
fi

if [ "${desired}" = selfhosted ]; then
  # 额度耗尽 → 切 self-hosted。切换前过 parity 门（同步保证）。
  parity_ok; pr=$?
  [ "${pr}" = 1 ] && notify "⛔ 需切 self-hosted 但车道不同步：${PARITY_MSG}。仍切（hosted 在拒），缺工具的 job 会红——立即修构建机。"
  managed_now=""
  for repo in ${REPOS}; do
    if runner_online "${repo}"; then
      set_bundle "${repo}" && managed_now="${managed_now} ${repo}"
    else
      notify "${repo} 无在线 self-hosted runner，未切（job 会排队，需人工）"
    fi
  done
  state_set lane_mode '"selfhosted"'
  state_set managed_list "\"${managed_now# }\""
  state_set last_probe_epoch 0
  gh variable set LANE_MODE --body selfhosted -R "${PROBE_REPO}" 2>/dev/null || log "WARN 写 LANE_MODE 失败"
  notify "hosted 额度耗尽 → 已切 self-hosted:${managed_now}"
else
  # 额度重置 → 切回 hosted。安全阀：只删 managed_list 里本脚本设过的仓，删除失败不吞。
  prev=$(state_get managed_list)
  [ -n "${prev}" ] || { log "切回 hosted：managed_list 为空，不删任何变量"; state_set lane_mode '"hosted"'; gh variable set LANE_MODE --body hosted -R "${PROBE_REPO}" 2>/dev/null; exit 0; }
  err=$(mktemp); restored=""; failed=""
  for repo in ${prev}; do
    ok=1
    for k in $(bundle_keys "${repo}"); do
      gh variable delete "$k" -R "${OWNER}/${repo}" 2>"${err}" || { ok=0; log "WARN del ${repo}/$k 失败: $(cat "${err}")"; }
    done
    [ "${ok}" = 1 ] && restored="${restored} ${repo}" || failed="${failed} ${repo}"
  done
  rm -f "${err}"
  state_set lane_mode '"hosted"'
  state_set managed_list '""'
  gh variable set LANE_MODE --body hosted -R "${PROBE_REPO}" 2>/dev/null || log "WARN 写 LANE_MODE 失败"
  notify "hosted 额度已重置 → 已切回 hosted:${restored}${failed:+（删失败需人工:${failed}）}"
fi
