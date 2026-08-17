#!/usr/bin/env bash
# net-adaptive.sh — 构建机网络自适应路由层（通用模板）
#
# 解决的问题：受限/间歇封锁的网络下，构建机到 CI 服务（GitHub 等）的出境时通时断。
# 写死"永远直连"或"永远走代理"都会周期性翻车。本脚本把路由变成【探测结果】：
#   探测 direct/proxy 到目标 → 决策 DIRECT|PROXY|DOWN → 应用到 runner 用户的 git + runner 服务。
# 环境无关：今天直连断就走代理，明天直连通就自动直连、代理闲置，零人工。
#
# 部署：在构建机上以 root 跑，systemd timer 每几分钟一次 + 关键操作前按需触发。
# 只在路由【变化】时动作（改配置 + 重启空闲 runner），不每次折腾。
#
# 前提：本机已有一个本地出境代理监听在 ${PROXY_URL}（见 references/egress-proxy.md，
#       本脚本与具体代理工具无关，只探测端口是否能出境）。
#
# 占位符：
#   PROXY_URL     本地代理地址，如 http://127.0.0.1:PORT（PORT 用你的代理实际端口）
#   PROXY_UNIT    代理进程的 systemd 服务名（用于"代理活着才探代理"；留空则跳过该判断）
#   PROBE_URL     出境探测目标，通常就是你的 CI 服务，如 https://github.com
#   RUNNER_USER   跑 CI runner 的专用用户（非 root）
#   RUNNER_UNIT_GLOB  runner 服务的 systemd 单元通配，官方 actions runner 默认 'actions.runner.*'
#                     或安装脚本自定义的前缀，如 'github-actions-*'
#   NO_PROXY_EXTRA    额外直连（不走代理）的主机/网段，逗号分隔（镜像站、内网等）
set -u
PROXY_URL="${PROXY_URL:-http://127.0.0.1:PORT}"   # 改成你的代理实际监听端口
PROXY_UNIT="${PROXY_UNIT:-}"
PROBE_URL="${PROBE_URL:-https://github.com}"
RUNNER_USER="${RUNNER_USER:-runner}"
RUNNER_UNIT_GLOB="${RUNNER_UNIT_GLOB:-actions.runner.*}"
NO_PROXY_EXTRA="${NO_PROXY_EXTRA:-}"

STATE="${STATE_FILE:-/run/net-route}"          # 当前路由：DIRECT / PROXY / DOWN
LOG="${LOG_FILE:-/var/log/net-adaptive.log}"
log(){ echo "[$(date '+%F %T')] $*" >> "${LOG}"; }

probe(){ curl -s -o /dev/null -w '%{http_code}' --max-time 7 ${2:+-x "$2"} "$1" 2>/dev/null; }

# ── 探测决策 ──
d=$(probe "${PROBE_URL}")
if [ "${d}" = 200 ]; then
  route=DIRECT
elif { [ -z "${PROXY_UNIT}" ] || systemctl is-active "${PROXY_UNIT}" >/dev/null 2>&1; } \
     && [ "$(probe "${PROBE_URL}" "${PROXY_URL}")" = 200 ]; then
  route=PROXY
else
  route=DOWN
fi

prev=$(cat "${STATE}" 2>/dev/null || echo "")
echo "${route}" > "${STATE}"
[ "${route}" = "${prev}" ] && exit 0            # 路由没变，不动作

log "路由变化: ${prev:-初始} → ${route} (direct=${d})"

# ── 应用到 runner 用户的 git（每次 git 调用读最新，无需重启）──
# 为什么单独配 git：有些 CI 步骤（如全历史 secret 扫描）自己 git fetch，不继承 runner 的 env 代理。
if [ "${route}" = PROXY ]; then
  su - "${RUNNER_USER}" -s /bin/bash -c \
    "git config --global http.${PROBE_URL%/}/.proxy ${PROXY_URL}; git config --global http.${PROBE_URL%/}/.version HTTP/1.1" 2>/dev/null
else
  su - "${RUNNER_USER}" -s /bin/bash -c \
    "git config --global --unset http.${PROBE_URL%/}/.proxy 2>/dev/null; git config --global --unset http.${PROBE_URL%/}/.version 2>/dev/null" 2>/dev/null
fi

# ── 应用到 runner 出境 env（systemd drop-in），仅在空闲时重启，避免打断在跑的 job ──
# 本地网段/镜像站永远直连，不经代理（回环+RFC1918+CGNAT+你的镜像站/内网）。
NOPROXY="localhost,127.0.0.1,::1,10.0.0.0/8,100.64.0.0/10,172.16.0.0/12,192.168.0.0/16${NO_PROXY_EXTRA:+,${NO_PROXY_EXTRA}}"
list_units(){ systemctl list-unit-files --no-pager "${RUNNER_UNIT_GLOB}" 2>/dev/null | awk '/\.service/{print $1}'; }

for unit in $(list_units); do
  dropin="/etc/systemd/system/${unit}.d"; mkdir -p "${dropin}"
  if [ "${route}" = PROXY ]; then
    cat > "${dropin}/proxy.conf" <<CONF
[Service]
Environment="HTTPS_PROXY=${PROXY_URL}" "HTTP_PROXY=${PROXY_URL}" "NO_PROXY=${NOPROXY}"
Environment="https_proxy=${PROXY_URL}" "http_proxy=${PROXY_URL}" "no_proxy=${NOPROXY}"
CONF
  else
    rm -f "${dropin}/proxy.conf"                 # DIRECT/DOWN：不走代理
  fi
done
systemctl daemon-reload

# 只重启空闲 runner（进程里有 Runner.Worker 子进程 = 正在跑 job，不打断，下轮再切）
for unit in $(list_units); do
  name="${unit%.service}"
  if pgrep -f "${name}.*Runner.Worker" >/dev/null 2>&1; then
    log "  ${unit} 忙，跳过重启（下轮再切）"; continue
  fi
  systemctl restart "${unit}" 2>/dev/null
done
log "已应用路由 ${route} 到 ${RUNNER_USER}-git + runner"
