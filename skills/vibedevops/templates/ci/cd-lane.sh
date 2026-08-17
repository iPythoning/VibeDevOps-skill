#!/usr/bin/env bash
# cd-lane.sh — 一键切换某仓的 CI/CD 构建车道（互斥变量组的人话界面，通用模板）
#
# 解决的问题：多台异构构建机 + 时好时坏的跨境网络下，"在哪构建/用什么源"是一组
# 互相关联的仓库变量。手动一个个 gh variable set 极易"少设一个卡一步"。本脚本把
# 每条车道的整组变量一次设齐/一次清干净，杜绝半配置状态。
#
# 车道（按需增删；这里给三条常见形态）：
#   hosted  : 删除全部路由变量 → 回落到 CI 服务托管 runner（额度/账单健康时的默认）
#   builder : 专用原生构建机快车道。用 docker daemon 直建（层缓存永续、零跨境拉取），
#             配合 warm-images.sh 预热基础镜像，FROM 全部本地命中
#   fallback: 天气/额度无关的兜底构建机（可能是异架构 QEMU，较慢）。用 docker-container
#             驱动 + 镜像站，适合 builder 也不可用时
#
# 用法：
#   cd-lane.sh <hosted|builder|fallback> <repo> [repo...]   （repo 不带 owner）
#   cd-lane.sh status <repo>
#
# 占位符（改下面 CONFIG 段，或用环境变量覆盖）：
#   OWNER              GitHub owner/org。留空则从 `gh repo view` 或当前目录推断
#   BUILDER_LABEL      builder 车道 runner 标签数组，如 ["self-hosted","builder"]
#   FALLBACK_LABEL     fallback 车道 runner 标签数组，如 ["self-hosted","fallback-runner"]
#   REGISTRY_MIRROR    容器镜像站（示例默认 docker.m.daocloud.io/，中国区通用；海外留空）
#   PIP_INDEX_URL      pip 源（示例 https://mirrors.aliyun.com/pypi/simple/）
#   NPM_REGISTRY       npm 源（示例 https://registry.npmmirror.com）
#   GOPROXY            go 代理（示例 https://goproxy.cn,direct）
#   FALLBACK_CACHE_FROM  fallback 冷构建的 registry cache 源（按仓改指本仓 :latest，或留空）
set -u

# ── CONFIG ────────────────────────────────────────────────
OWNER="${OWNER:-}"
BUILDER_LABEL="${BUILDER_LABEL:-[\"self-hosted\",\"builder\"]}"
FALLBACK_LABEL="${FALLBACK_LABEL:-[\"self-hosted\",\"fallback-runner\"]}"
REGISTRY_MIRROR="${REGISTRY_MIRROR:-docker.m.daocloud.io/}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://mirrors.aliyun.com/pypi/simple/}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
FALLBACK_CACHE_FROM="${FALLBACK_CACHE_FROM:-}"
# ──────────────────────────────────────────────────────────

# owner 未显式给出时自动推断（避免把内部 owner 硬编码进模板）
if [ -z "${OWNER}" ]; then
  OWNER="$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)"
fi
[ -n "${OWNER}" ] || { echo "❌ 无法确定 OWNER，请用环境变量或 CONFIG 段指定"; exit 2; }

LANE="${1:?用法: cd-lane.sh <hosted|builder|fallback|status> <repo>...}"; shift

# 路由变量全集（一处声明，status/hosted 复用；按你的 CD workflow 实际读取的变量名对齐）
ALL_VARS="CI_RUNNER CD_RUNNER CI_REGISTRY_MIRROR CI_PIP_INDEX_URL CI_NPM_REGISTRY CI_GOPROXY CD_BUILDX_DRIVER CD_BUILDX_DRIVER_OPTS CD_BUILDKITD_CONFIG CD_BUILD_ARGS CD_BUILD_CACHE_FROM CD_BUILD_CACHE_TO"

setv() { printf '%s' "$3" | gh variable set "$2" -R "${OWNER}/$1" || echo "WARN: set $1/$2 失败"; }
delv() { gh variable delete "$2" -R "${OWNER}/$1" 2>/dev/null || true; }

# 中国区/受限网络车道共用的语言级源（builder 与 fallback 都需要）
lane_ci_mirrors() {
  [ -n "${REGISTRY_MIRROR}" ] && setv "$1" CI_REGISTRY_MIRROR "${REGISTRY_MIRROR}"
  [ -n "${PIP_INDEX_URL}" ]   && setv "$1" CI_PIP_INDEX_URL "${PIP_INDEX_URL}"
  [ -n "${NPM_REGISTRY}" ]    && setv "$1" CI_NPM_REGISTRY "${NPM_REGISTRY}"
  [ -n "${GOPROXY}" ]         && setv "$1" CI_GOPROXY "${GOPROXY}"
}
# 构建期（Dockerfile ARG）注入的源。ARG 名因项目而异——这里给最常见的一组，
# 按仓在 Dockerfile 里对齐 ARG 名后增删。BASE_IMAGE 故意不设：builder 车道满仓
# 本地命中（见 warm-images.sh），fallback 车道如需可在此追加指向镜像站的 base。
lane_build_args() {
  {
    [ -n "${PIP_INDEX_URL}" ] && printf 'PIP_INDEX_URL=%s\nPIP_TRUSTED_HOST=%s\n' \
      "${PIP_INDEX_URL}" "$(printf '%s' "${PIP_INDEX_URL}" | sed -E 's#https?://([^/]+)/.*#\1#')"
    [ -n "${NPM_REGISTRY}" ] && printf 'NPM_REGISTRY=%s\n' "${NPM_REGISTRY}"
  } | gh variable set CD_BUILD_ARGS -R "${OWNER}/$1"
}

for repo in "$@"; do
  echo "== ${repo} → ${LANE}"
  case "${LANE}" in
    status)
      gh variable list -R "${OWNER}/${repo}" | grep -E "$(echo ${ALL_VARS} | tr ' ' '|')" \
        || echo "  （无路由变量 = hosted）"
      ;;
    hosted)
      for v in ${ALL_VARS}; do delv "${repo}" "$v"; done
      echo "  已回 CI 托管 runner（全部路由变量已删）"
      ;;
    builder)
      setv "${repo}" CI_RUNNER "${BUILDER_LABEL}"; setv "${repo}" CD_RUNNER "${BUILDER_LABEL}"
      lane_ci_mirrors "${repo}"; lane_build_args "${repo}"
      setv "${repo}" CD_BUILDX_DRIVER 'docker'       # daemon 直建：层缓存永续 + 零跨境
      setv "${repo}" CD_BUILD_CACHE_TO 'type=inline' # docker driver 合法的 cache-to
      delv "${repo}" CD_BUILD_CACHE_FROM             # daemon 层缓存天然命中，无需 import
      delv "${repo}" CD_BUILDKITD_CONFIG             # docker driver 不吃 buildkitd 配置
      delv "${repo}" CD_BUILDX_DRIVER_OPTS           # daemon 直建无需 host 网络 opt
      ;;
    fallback)
      # CI 的容器 job 只能跑 linux，若 fallback 机非 linux，CI 仍指向 builder
      setv "${repo}" CI_RUNNER "${BUILDER_LABEL}"
      setv "${repo}" CD_RUNNER "${FALLBACK_LABEL}"
      lane_ci_mirrors "${repo}"; lane_build_args "${repo}"
      delv "${repo}" CD_BUILDX_DRIVER                # 默认 docker-container 驱动
      delv "${repo}" CD_BUILDX_DRIVER_OPTS
      if [ -n "${REGISTRY_MIRROR}" ]; then
        printf '[registry."docker.io"]\n  mirrors = ["%s"]\n' "${REGISTRY_MIRROR%/}" \
          | gh variable set CD_BUILDKITD_CONFIG -R "${OWNER}/${repo}"
      fi
      [ -n "${FALLBACK_CACHE_FROM}" ] && setv "${repo}" CD_BUILD_CACHE_FROM "${FALLBACK_CACHE_FROM}"
      setv "${repo}" CD_BUILD_CACHE_TO 'type=inline'
      ;;
    *) echo "未知车道 ${LANE}"; exit 2 ;;
  esac

  # per-repo 附加项按仓配置示例（Dockerfile ARG 名因项目而异，默认关闭）：
  #   多阶段/前后端分离仓常有独立的 CD_BACKEND_BUILD_ARGS / CD_FRONTEND_BUILD_ARGS。
  #   若某仓需要，仿照上面 lane_build_args 增设，切回 hosted 时记得一并 delv 清掉。
done
echo "完成。fallback 车道若配了 CD_BUILD_CACHE_FROM，注意按仓改指本仓 :latest（或留空走冷构建）。"
