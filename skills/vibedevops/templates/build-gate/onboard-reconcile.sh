#!/bin/bash
# onboard-reconcile —— 仓库接入自治：对账循环（ADR 0010）。
#
# 为什么存在：托管 CI 账单/额度死后，新仓「runner 未注册 + 路由变量未设」必撞
# 0 步失败；failover（ADR 0007）「无 runner 不切」救不了没注册的仓；而「建仓后
# 记得跑接入命令」不是机制——人和 agent 都会忘，仓库还可能从任何入口被创建。
# 本脚本把接入从「事件驱动」改成「状态收敛」：定期对账 OWNER 名下全部仓，
# 凡「有 .github/workflows 但缺构建机 runner / 缺路由变量」的仓自动接入。
#
# 纪律（每条都有实战事故背书，见 ADR 0010）：
# - 只做加法：注册缺失的 runner、补缺失的变量；**绝不覆盖已存在的变量值**
#   ——某仓刻意不同的车道配置（如 mac 车道）不被夷平。
# - 「已注册」以平台侧 API 为准，不信本地目录——config.sh 断链会留下
#   半配置残留（.runner_migrated 等）把本地判定骗成「已配置」。
# - 注册失败整目录删除重来——半配置残留会毒化下一轮。
# - 全程构建机本机完成：注册 runner 本来就是本机操作，不依赖任何入站通道
#   （overlay 网络入站挂死一整天的实证）。
# - 注册是单写入者：绝不与其他注册通道（手动命令/逃生 job）并发跑同一仓。
# - token 只进请求头，不进日志、不进 argv。
#
# 依赖：curl、jq、rsync、systemd（runner 单元）。全部可经 PATH 注入替身测试。
set -u

OWNER="${ONBOARD_OWNER:?set ONBOARD_OWNER (GitHub user/org)}"
TOKEN_FILE="${ONBOARD_TOKEN_FILE:?set ONBOARD_TOKEN_FILE (600, repo-admin scope PAT)}"
RUNNERS_DIR="${ONBOARD_RUNNERS_DIR:?set ONBOARD_RUNNERS_DIR (persistent disk!)}"
RUNNER_USER="${ONBOARD_RUNNER_USER:-gha}"
RUNNER_LABELS="${ONBOARD_RUNNER_LABELS:-xserver,build}"
RUNNER_NAME_PREFIX="${ONBOARD_RUNNER_PREFIX:-xserver-gha-}"
SKIP_FILE="${ONBOARD_SKIP_FILE:-/etc/onboard-skip.txt}"
LOG="${ONBOARD_LOG:-/var/log/onboard-reconcile.log}"
# 可选：外部 runner 单元生成器（如 bootstrap 仓的 systemd 生成器）。
# 未设则用内置最小单元。生成器只该写单元不该 start——start 在本脚本末尾统一做。
UNIT_GENERATOR="${ONBOARD_UNIT_GENERATOR:-}"
# 路由变量集：JSON 对象，key=变量名 value=值。默认 = ADR 0006/0008 定案的
# 自建车道全套。改这里 = 改所有新仓的出厂配置。
VARS_JSON="${ONBOARD_VARS_JSON:-$(cat <<'DEFAULTS'
{
  "CI_RUNNER": "[\"self-hosted\",\"xserver\"]",
  "CD_RUNNER": "[\"self-hosted\",\"xserver\"]",
  "VIBEDEVOPS_CONTROL_RUNNER": "[\"self-hosted\",\"xserver\"]",
  "CD_BUILDX_DRIVER": "docker",
  "CD_BUILD_CACHE": "none",
  "CD_BUILD_CACHE_FROM": "none",
  "CD_BUILD_NETWORK": "host"
}
DEFAULTS
)}"
API="${ONBOARD_API:-https://api.github.com}"
UNIT_DIR="${ONBOARD_UNIT_DIR:-/etc/systemd/system}"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
[ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || stat -f %z "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ] \
  && tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

[ -r "$TOKEN_FILE" ] || { log "SKIP: no token file"; exit 0; }
TOKEN=$(head -1 "$TOKEN_FILE" | tr -d '[:space:]')
[ -n "$TOKEN" ] || { log "SKIP: empty token"; exit 0; }

gh_api() { curl -sS --connect-timeout 10 --max-time 40 \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

# ── 1. 列仓（owner 全部，排除 archived/fork）──
REPOS=""
for page in 1 2 3 4 5; do
  BATCH=$(gh_api "$API/user/repos?affiliation=owner&per_page=100&page=$page" \
    | jq -r '.[] | select(.archived==false and .fork==false) | .name' 2>/dev/null) || break
  [ -n "$BATCH" ] || break
  REPOS="$REPOS $BATCH"
done
REPOS=$(echo "$REPOS" | tr ' ' '\n' | sort -u)
[ -n "$(echo "$REPOS" | tr -d '[:space:]')" ] || { log "WARN: repo list empty (token/network?)"; exit 0; }

write_minimal_unit() { # $1=slug $2=dir —— 内置最小 runner 单元（无外部生成器时）
  cat > "$UNIT_DIR/github-actions-$1.service" <<UNIT
[Unit]
Description=GitHub Actions runner ($1)
After=network-online.target

[Service]
User=$RUNNER_USER
WorkingDirectory=$2
ExecStart=$2/run.sh
Restart=always
RestartSec=15
KillMode=control-group

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable "github-actions-$1.service" >/dev/null 2>&1 || true
}

NEED_START=""
for REPO in $REPOS; do
  # 单仓模式（即时通道走这里：ONBOARD_ONLY_REPO=<name> 立即接入一个仓，
  # 与全量对账共用同一份逻辑——两个入口一份实现，永不漂移）
  if [ -n "${ONBOARD_ONLY_REPO:-}" ] && [ "$REPO" != "$ONBOARD_ONLY_REPO" ]; then
    continue
  fi
  if [ -f "$SKIP_FILE" ] && grep -v '^#' "$SKIP_FILE" | grep -qxE "($OWNER/)?$REPO"; then
    continue
  fi
  # 无 CI 的仓不需要 runner
  WF_CODE=$(gh_api -o /dev/null -w '%{http_code}' "$API/repos/$OWNER/$REPO/contents/.github/workflows")
  [ "$WF_CODE" = "200" ] || continue

  # ── 2. runner 缺则注册（平台侧为准）──
  HAVE=$(gh_api "$API/repos/$OWNER/$REPO/actions/runners" \
    | jq -r --arg p "$RUNNER_NAME_PREFIX" '[.runners[] | select(.name | startswith($p))] | length' 2>/dev/null || echo 0)
  if [ "${HAVE:-0}" = "0" ]; then
    SLUG=$(echo "$REPO" | tr '[:upper:]' '[:lower:]')
    DIR="$RUNNERS_DIR/$SLUG"
    # 模板不能是目标自己——按字母序取第一个时很容易选中它（rsync 自己到自己），
    # 而且要挑一个「配置齐全」的目录当模板：只有 run.sh + config.sh 齐的才算数。
    TEMPLATE=""
    for CAND in "$RUNNERS_DIR"/*/; do
      [ -d "$CAND" ] || continue
      case "$CAND" in *"/$SLUG/") continue ;; esac
      [ -x "$CAND/config.sh" ] && [ -x "$CAND/run.sh" ] || continue
      TEMPLATE="$CAND"; break
    done
    if [ -z "$TEMPLATE" ]; then log "$REPO: FAIL no template runner dir under $RUNNERS_DIR"; continue; fi
    REG=$(gh_api -X POST "$API/repos/$OWNER/$REPO/actions/runners/registration-token" | jq -r .token)
    if [ -z "$REG" ] || [ "$REG" = "null" ]; then log "$REPO: FAIL registration-token"; continue; fi
    mkdir -p "$DIR"
    rsync -a --delete \
      --exclude '.runner*' --exclude '.credentials*' --exclude '.env' --exclude '.path' \
      --exclude '_work' --exclude '_diag' "$TEMPLATE" "$DIR/"
    # rsync 的 --exclude 只是「不从源复制」，**不会删掉目标里已有的同名文件**
    # （--delete 默认也不删 excluded 项，那要 --delete-excluded）。于是重注册一个
    # 曾经注册过的仓时，旧的 .runner 还在，config.sh 直接报 already configured
    # 并失败，紧接着 rm -rf 把整个目录删掉——单元指向不存在的路径无限 activating，
    # 该仓从此没有 runner，一旦触发 CI 就撞额度死。实测两个仓栽在这里。
    # ADR 里写了「注册前清理」，但代码里只 exclude 没真删——文档写了、代码没做。
    rm -f "$DIR"/.runner* "$DIR"/.credentials* "$DIR"/.env "$DIR"/.path 2>/dev/null || true
    chown -R "$RUNNER_USER:$RUNNER_USER" "$DIR"
    if (cd "$DIR" && runuser -u "$RUNNER_USER" -- env \
        HTTPS_PROXY="${HTTPS_PROXY:-}" HTTP_PROXY="${HTTP_PROXY:-}" \
        ACTIONS_RUNNER_INPUT_TOKEN="$REG" \
        ./config.sh --unattended --replace --url "https://github.com/$OWNER/$REPO" \
        --name "$RUNNER_NAME_PREFIX$SLUG" --labels "$RUNNER_LABELS" --work _work >> "$LOG" 2>&1); then
      chown -R "$RUNNER_USER:$RUNNER_USER" "$DIR"
      [ -n "$UNIT_GENERATOR" ] || write_minimal_unit "$SLUG" "$DIR"
      NEED_START="$NEED_START $SLUG"
      log "$REPO: runner registered"
    else
      log "$REPO: FAIL config.sh"
      rm -rf "$DIR"   # 半配置残留会毒化下一轮，整目录重来
      # 单元也要清：只删目录会留下一个指向不存在路径的单元无限 activating，
      # 而 systemd 状态是 activating（既不是 active 也不是 failed），巡检容易漏掉。
      systemctl stop "github-actions-$SLUG.service" 2>/dev/null || true
      systemctl disable "github-actions-$SLUG.service" 2>/dev/null || true
      rm -f "$UNIT_DIR/github-actions-$SLUG.service" 2>/dev/null || true
      systemctl daemon-reload 2>/dev/null || true
      continue
    fi
  fi

  # ── 3. 变量缺则补（绝不覆盖已有值）──
  EXISTING=$(gh_api "$API/repos/$OWNER/$REPO/actions/variables?per_page=100" | jq -r '.variables[].name' 2>/dev/null)
  echo "$VARS_JSON" | jq -r 'keys[]' | while read -r K; do
    echo "$EXISTING" | grep -qx "$K" && continue
    V=$(echo "$VARS_JSON" | jq -r --arg k "$K" '.[$k]')
    CODE=$(gh_api -o /dev/null -w '%{http_code}' -X POST "$API/repos/$OWNER/$REPO/actions/variables" \
      -d "$(jq -nc --arg n "$K" --arg v "$V" '{name:$n,value:$v}')")
    [ "$CODE" = "201" ] && log "$REPO: var $K set" || log "$REPO: var $K FAIL code=$CODE"
  done
done

# ── 4. 统一装单元并拉起（外部生成器只写不拉起；start 幂等）──
if [ -n "$NEED_START" ]; then
  if [ -n "$UNIT_GENERATOR" ]; then
    bash "$UNIT_GENERATOR" >> "$LOG" 2>&1 && log "unit generator OK" || log "unit generator FAIL"
  fi
  for SLUG in $NEED_START; do
    systemctl start "github-actions-$SLUG.service" 2>/dev/null || log "start $SLUG FAIL"
  done
  log "started:$NEED_START"
fi

# ── 5. 心跳：把「本轮成功跑完」写回平台，让「对账自己死了」可被发现 ──
# 这个循环是整条自治链的根：它死了，新仓就悄悄回到「必撞额度死」的状态，
# 而没有任何东西会告诉人。**实测过一次**：用通用模板覆盖硬编码版时漏带 env，
# ONBOARD_OWNER 未设导致每轮开头就退出，静默死了 20 分钟才被偶然发现。
# 心跳写成仓库变量而不是本机文件——本机文件要人登上去才看得见，
# 而平台侧的变量可以被一个 daily workflow 检查（超时即红、即发通知）。
if [ -n "${ONBOARD_HEARTBEAT_REPO:-}" ]; then
  NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  HB_CODE=$(gh_api -o /dev/null -w '%{http_code}' -X PATCH \
    "$API/repos/$OWNER/$ONBOARD_HEARTBEAT_REPO/actions/variables/ONBOARD_LAST_SUCCESS" \
    -d "$(jq -nc --arg v "$NOW_ISO" '{name:"ONBOARD_LAST_SUCCESS",value:$v}')")
  if [ "$HB_CODE" = "404" ]; then   # 变量还不存在，首次创建
    HB_CODE=$(gh_api -o /dev/null -w '%{http_code}' -X POST \
      "$API/repos/$OWNER/$ONBOARD_HEARTBEAT_REPO/actions/variables" \
      -d "$(jq -nc --arg v "$NOW_ISO" '{name:"ONBOARD_LAST_SUCCESS",value:$v}')")
  fi
  case "$HB_CODE" in
    20*|404) log "heartbeat: $NOW_ISO" ;;
    *) log "heartbeat FAIL code=$HB_CODE" ;;
  esac
fi
exit 0
