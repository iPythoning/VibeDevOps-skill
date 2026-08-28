#!/usr/bin/env bash
# runner-failover.sh — CI 额度/账单故障自动切换 watcher（无人值守闭环，通用模板）
#
# 解决的问题：CI 服务（GitHub Actions 等）额度耗尽/账单异常时，job 会【静默失败】
# ——失败但 0 步、无 runner，看着像代码红实则是账单红。本脚本自动识别这类签名，
# 把纳管仓整体切到自建 runner；等 CI 恢复再自动切回。
#
# 部署：在一台常驻机上定时跑（cron / systemd timer / launchd，如每 10 分钟）。
#
# 两态闭环：
#   正常态：在哨兵仓检测"账单拒绝签名" → 确认各仓 self-hosted runner 在线 →
#           自动设变量包切自建 runner，通知。
#   故障态：（恢复回切分支已作为 P0 安全修复移除——单次探针成功即跨全部纳管仓无界批量删除路由，
#           且不可安全测试；托管有意退役时它只会是事故触发。仅保留 infra_heal 断连自愈。）
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
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"   # 覆盖常见 gh/jq 安装位

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
# 哨兵 = 清单里最近推送的前三个仓（只在这几个上跑账单探测，省 API）
SENTINELS=$(printf '%s' "${REPOS}" | tr ' ' '\n' | head -3 | tr '\n' ' ')

in_failover=false
for r in ${SENTINELS}; do repo_in_failover "$r" && in_failover=true && break; done

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

if [ "${in_failover}" = true ]; then
  # ── 恢复回切分支已移除（P0 安全修复，2026-08-28）──
  # 原逻辑：探针检测到托管 CI 恢复 → 对全部纳管仓 del_bundle，一次性删光路由变量切回托管。
  # 这是个哑雷：① 单次探针成功即跨【全部】纳管仓批量删除；② del_bundle 用 `2>/dev/null || true`
  # 吞掉删除失败；③ 该路径几乎不可能被安全测试——首次真实触发即作用于全部生产仓，无 dry-run。
  # 当托管车道被有意永久退役时（自建 runner 成为常态主车道），它只可能作为事故触发、绝不可能作为
  # 恢复触发。故移除回切动作与每小时探针 dispatch（账单坏时探针恒被拒，纯烧 API）；上方 PROBE_*
  # 配置随之失效，保留仅为向后兼容。infra_heal（断连自愈）继续生效。
  # 若确需"托管恢复后自动切回"，请以【有界、可测、逐仓二次确认】的方式显式重写，切勿恢复此处的
  # 无界批量删除。
  :
else
  # ── 正常态：检测账单/额度故障 ──
  for r in ${SENTINELS}; do
    if billing_sig "$r"; then
      log "检测到账单/额度拒绝签名（哨兵仓 $r），开始整体切换"
      switched=""
      for repo in ${REPOS}; do
        repo_in_failover "${repo}" && continue
        if runner_online "${repo}"; then
          set_bundle "${repo}" && switched="${switched} ${repo}"
        else
          notify "${repo} 无在线 self-hosted runner，未切换（需人工处理）"
        fi
      done
      if [ -n "${switched}" ]; then
        state_set managed true
        state_set last_probe_epoch 0
        notify "托管 runner 被账单/额度拒绝，已自动切换到自建 runner:${switched}"
      fi
      break
    fi
  done
fi
