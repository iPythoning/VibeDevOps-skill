#!/usr/bin/env bash
# build-gate.sh — 构建门禁三级路由（通用模板）
#
# 解决的问题：CI 额度耗尽会静默失败、本机资源不足跑不动全量验证、专用构建机可能连不上。
# 本模板把"在哪验证"变成一个显式的、自动降级的、留证据的路由决策：
#
#   1. CLOUD    CI 服务（默认 GitHub Actions）—— 额度充足时的默认路径
#   2. BUILDER  专用构建机（ssh）—— 额度不足 / CI 不可用时；干净环境 + amd64
#   3. LOCAL    本机 —— 构建机也不可达时兜底；证据最弱，通过后记入补验队列
#
# 三条路把结果写进同一份证据：<repo>/docs/BUILD-EVIDENCE.md（最新在最上，人机共读）。
# LOCAL 通过的记录写入 ${PENDING_QUEUE}；销账内嵌在本脚本启动路径——之后任何一次构建，
# 只要构建机可达就先补验欠账（不依赖 cron；也可手动/定时跑 reverify.sh）。
# LOCAL 通过 ≠ 结案，只是欠账。
#
# 任何门禁默认 10 分钟硬上限（GATE_TIMEOUT）：超时强杀并留证。超时是构建的病，
# 药方是缓存/依赖/拆分，不是调大上限。
#
# 用法：
#   build-gate.sh <repo> --cmd "<gate command>" [--force-cloud|--force-builder|--force-local]
#
# 配置（环境变量，或直接改下面 CONFIG 段）：
#   BUILDER_SSH     构建机 ssh alias/地址。为空 = 没有构建机，CLOUD 之后直接降级 LOCAL
#   BUILDER_IMAGE   构建机上的 docker 镜像。为空 = 不用 docker，直接在构建机上跑
#   GH_RESERVE_MIN  CI 额度保留线（分钟），默认 200；设 0 = 不查额度永远优先 CLOUD
#   PENDING_QUEUE   补验队列文件，默认 ~/.build-gate-pending.tsv

set -uo pipefail

# ── CONFIG ────────────────────────────────────────────────
BUILDER_SSH="${BUILDER_SSH:-}"
BUILDER_IMAGE="${BUILDER_IMAGE:-}"
RESERVE="${GH_RESERVE_MIN:-200}"
PENDING_QUEUE="${PENDING_QUEUE:-$HOME/.build-gate-pending.tsv}"
INCLUDED_MIN="${GH_INCLUDED_MIN:-2000}"   # CI 每月免费分钟数
EVIDENCE_REL="docs/BUILD-EVIDENCE.md"     # 证据文件（相对仓库根）
GATE_TIMEOUT="${GATE_TIMEOUT:-600}"       # 门禁硬上限（秒）。超时 = 构建有病：修缓存/依赖/拆分，不许调大上限
NPM_REGISTRY="${NPM_REGISTRY:-}"          # 运行时注入 npm 源，如 https://registry.npmmirror.com（留空不注入）
PIP_INDEX="${PIP_INDEX:-}"                # 运行时注入 pip 源，如 https://mirrors.aliyun.com/pypi/simple（留空不注入）
# ──────────────────────────────────────────────────────────

REPO=""; CMD=""; FORCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cmd)           CMD="$2"; shift 2;;
    --force-cloud)   FORCE="cloud"; shift;;
    --force-builder) FORCE="builder"; shift;;
    --force-local)   FORCE="local"; shift;;
    *)               REPO="$1"; shift;;
  esac
done

[ -n "$REPO" ] && [ -d "$REPO/.git" ] || { echo "用法: $0 <repo> --cmd \"<gate command>\" [--force-cloud|--force-builder|--force-local]"; exit 1; }
[ -n "$CMD" ] || { echo "❌ 必须用 --cmd 指定门禁命令（如 \"npm ci && npm test && npm run build\"）"; exit 2; }

# 机会式销账：有欠账就先试着还（内嵌于每次构建，不依赖 cron —— 构建越勤销得越快）。
# REVERIFY_GUARD 防递归：reverify.sh 调回本脚本时跳过此步。
if [ -f "$PENDING_QUEUE" ] && [ "${REVERIFY_GUARD:-}" != "1" ] && [ -n "$BUILDER_SSH" ]; then
  REVERIFY_GUARD=1 "$(dirname "$0")/reverify.sh" || true
fi

REPO="$(cd "$REPO" && pwd)"
PROJECT="$(basename "$REPO")"
SHA="$(git -C "$REPO" rev-parse HEAD)"
SHORT="${SHA:0:8}"
BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"

# ── CI 额度查询（GitHub Actions；查不到按额度不足处理，保守降级）──
quota_remaining() {
  [ "$RESERVE" = "0" ] && { echo 999999; return; }
  command -v gh >/dev/null || { echo -1; return; }
  local user; user="$(gh api user -q .login 2>/dev/null)" || { echo -1; return; }
  gh api "/users/$user/settings/billing/usage" 2>/dev/null | python3 -c "
import json,sys,datetime
try: items=json.load(sys.stdin).get('usageItems',[])
except Exception: print(-1); sys.exit()
cm=datetime.datetime.now().strftime('%Y-%m')
print(int(sum(i['quantity'] for i in items if i.get('product')=='actions' and i['date'][:7]==cm)))
" 2>/dev/null | awk -v inc="$INCLUDED_MIN" '{if($1<0)print -1;else print inc-$1}'
}

REMAIN="$(quota_remaining)"
if [ "$REMAIN" -lt 0 ] 2>/dev/null; then
  QUOTA_NOTE="CI 额度未知（查询失败）—— 保守按不足处理"
else
  QUOTA_NOTE="CI 额度剩余约 ${REMAIN} min（保留线 ${RESERVE}）"
fi

# ── 路由决策 ──────────────────────────────────────────────
if [ -n "$FORCE" ]; then
  ROUTE="$FORCE"; REASON="人工指定 --force-$FORCE"
elif [ "$REMAIN" -lt "$RESERVE" ] 2>/dev/null; then
  ROUTE="builder"; REASON="CI 额度不足或未知"
else
  ROUTE="cloud"; REASON="CI 额度充足"
fi
# 无构建机 → builder 路由直接落 local
if [ "$ROUTE" = "builder" ] && [ -z "$BUILDER_SSH" ]; then
  ROUTE="local"; REASON="${REASON}；未配置 BUILDER_SSH，降级本机"
fi
# 构建机不可达 → local
if [ "$ROUTE" = "builder" ]; then
  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$BUILDER_SSH" true 2>/dev/null; then
    ROUTE="local"; REASON="${REASON}；构建机 ($BUILDER_SSH) 不可达，降级本机"
  fi
fi

ROUTE_UP="$(printf %s "$ROUTE" | tr '[:lower:]' '[:upper:]')"
echo "════════════════════════════════════════════"
echo " 构建门禁 · $PROJECT @ $SHORT ($BRANCH)"
echo " $QUOTA_NOTE"
echo " 路由：$ROUTE_UP —— $REASON"
echo " 命令：$CMD"
echo "════════════════════════════════════════════"

START="$(date -u +%FT%TZ)"
START_S="$(date +%s)"
EXIT=0; DETAIL=""
CMD_B64="$(printf %s "$CMD" | base64)"

case "$ROUTE" in
  cloud)
    ORIGIN="$(git -C "$REPO" remote get-url origin 2>/dev/null)"
    [ -n "$ORIGIN" ] || { echo "❌ 无远程仓库，无法走 CI。用 --force-builder 或 --force-local。"; exit 2; }
    GH_REPO="$(printf %s "$ORIGIN" | sed -E 's#.*github.com[:/]##;s#\.git$##')"
    git -C "$REPO" push -q origin "$BRANCH"
    echo "▶ 已 push，等待 CI…"; sleep 6
    RUN="$(gh run list -R "$GH_REPO" --branch "$BRANCH" --limit 1 --json databaseId,url -q '.[0]' 2>/dev/null)"
    if [ -z "$RUN" ] || [ "$RUN" = "null" ]; then
      echo "⚠️ 未发现 CI run（仓库可能没配 workflow）→ 降级重试"
      exec "$0" "$REPO" --cmd "$CMD" --force-builder
    fi
    RID="$(printf %s "$RUN" | python3 -c 'import json,sys;print(json.load(sys.stdin)["databaseId"])')"
    RURL="$(printf %s "$RUN" | python3 -c 'import json,sys;print(json.load(sys.stdin)["url"])')"
    gh run watch "$RID" -R "$GH_REPO" --exit-status
    EXIT=$?
    DETAIL="CI run: $RURL"
    ;;

  builder)
    # HEAD 打成 bundle 传到构建机 → canonical repo fetch → 独立工作目录 checkout → 跑门禁
    BUNDLE="$(mktemp /tmp/gate-bundle.XXXXXX)"
    git -C "$REPO" bundle create "$BUNDLE" "$SHA"
    BSHA_LOCAL="$(shasum -a 256 "$BUNDLE" | awk '{print $1}')"
    WS="\$HOME/build-workspaces/$PROJECT"
    scp -q "$BUNDLE" "$BUILDER_SSH:/tmp/gate-$SHORT.bundle"
    rm -f "$BUNDLE"
    ssh "$BUILDER_SSH" "
      set -e
      mkdir -p $WS
      [ -d $WS/canonical ] || git clone -q /tmp/gate-$SHORT.bundle $WS/canonical
      git -C $WS/canonical fetch -q /tmp/gate-$SHORT.bundle $SHA
      rm -rf $WS/run-$SHORT
      git -C $WS/canonical worktree add -f $WS/run-$SHORT $SHA >/dev/null
      T=''; command -v timeout >/dev/null && T='timeout -k 30 ${GATE_TIMEOUT}'
      if [ -n '$BUILDER_IMAGE' ]; then
        # --network host：NAS/家庭服务器的 docker 常由厂商平台托管，默认 bridge 可能不存在——
        # 显式 host 网络让默认桥的状态与构建彻底无关。缓存挂命名卷，镜像源运行时注入（免预烤）。
        \$T docker run --rm --network host \
          -v build-gate-npm:/root/.npm -v build-gate-pip:/root/.cache/pip \
          ${NPM_REGISTRY:+-e npm_config_registry=$NPM_REGISTRY} \
          ${PIP_INDEX:+-e PIP_INDEX_URL=$PIP_INDEX} \
          -v $WS/run-$SHORT:/src -w /src '$BUILDER_IMAGE' \
          bash -lc \"\$(echo $CMD_B64 | base64 -d)\"
      else
        ${NPM_REGISTRY:+export npm_config_registry=$NPM_REGISTRY;} ${PIP_INDEX:+export PIP_INDEX_URL=$PIP_INDEX;} \
        cd $WS/run-$SHORT && \$T bash -lc \"\$(echo $CMD_B64 | base64 -d)\"
      fi
    "
    EXIT=$?
    DETAIL="构建机 ${BUILDER_SSH}（bundle sha256 本地 ${BSHA_LOCAL}；镜像 ${BUILDER_IMAGE:-无}）"
    ;;

  local)
    echo "⚠️ 本机门禁：证据强度最弱（非干净环境、架构可能不符）。仅作兜底。"
    # 可移植超时：优先 coreutils timeout（退出码 124）；macOS 无 coreutils 时用
    # perl alarm（原生自带，alarm 定时器跨 exec 存活，超时 SIGALRM → 退出码 142）
    run_limited() {
      if command -v timeout >/dev/null 2>&1; then timeout -k 30 "$GATE_TIMEOUT" "$@"
      else perl -e 'alarm shift @ARGV; exec @ARGV' "$GATE_TIMEOUT" "$@"
      fi
    }
    ( cd "$REPO" \
      && ${NPM_REGISTRY:+export npm_config_registry="$NPM_REGISTRY";} \
         ${PIP_INDEX:+export PIP_INDEX_URL="$PIP_INDEX";} \
         run_limited bash -c "$CMD" )
    EXIT=$?
    DETAIL="本机执行（$(uname -m) / $(uname -sr)）"
    # 通过 ≠ 结案：记入补验队列，构建机恢复后由 reverify.sh 自动复验销账
    if [ "$EXIT" -eq 0 ] && [ -n "$BUILDER_SSH" ]; then
      if [ -f "$PENDING_QUEUE" ]; then grep -v -F "	$REPO	" "$PENDING_QUEUE" > "$PENDING_QUEUE.tmp" || true; else : > "$PENDING_QUEUE.tmp"; fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$START" "$REPO" "$PROJECT" "$SHA" "$CMD" >> "$PENDING_QUEUE.tmp"
      mv "$PENDING_QUEUE.tmp" "$PENDING_QUEUE"
      DETAIL="${DETAIL}；弱证据，已记入构建机补验队列"
      echo "  ⏳ 已记入补验队列 $PENDING_QUEUE —— 构建机恢复后自动复验此 commit"
    fi
    ;;
esac

END="$(date -u +%FT%TZ)"
DUR=$(( $(date +%s) - START_S ))
if [ "$EXIT" -eq 124 ] || [ "$EXIT" -eq 142 ]; then   # 124=timeout；142=SIGALRM(perl alarm)
  VERDICT="❌ 超时强杀（>${GATE_TIMEOUT}s）"
  echo "❌ 门禁超过 ${GATE_TIMEOUT}s 被强制终止 —— 这是构建的病：修缓存/依赖/拆分，不许调大上限。"
elif [ "$EXIT" -eq 0 ]; then VERDICT="✅ 通过"; else VERDICT="❌ 失败（exit ${EXIT}）"; fi
DIRTY="$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')"

# ── 证据落盘（仓库内，换 agent 不丢）────────────────────────
EV="$REPO/$EVIDENCE_REL"
mkdir -p "$REPO/docs"
if [ ! -f "$EV" ]; then
  {
    printf '# 构建门禁证据（BUILD-EVIDENCE）\n\n'
    printf '> 每次门禁自动追加，最新在最上面。路由：CLOUD=CI；BUILDER=专用构建机；LOCAL=本机兜底（证据最弱）。\n\n---\n'
  } > "$EV"
fi
TMP="$(mktemp)"
{
  head -n 5 "$EV"
  printf '\n## %s · %s · %s\n\n' "$START" "$PROJECT" "$VERDICT"
  printf -- '- commit：`%s`（分支 `%s`）\n' "$SHA" "$BRANCH"
  printf -- '- 路由：**%s** —— %s\n' "$ROUTE_UP" "$REASON"
  printf -- '- 额度：%s\n' "$QUOTA_NOTE"
  printf -- '- 门禁命令：`%s`\n' "$CMD"
  printf -- '- 结果：%s\n' "$VERDICT"
  printf -- '- 明细：%s\n' "$DETAIL"
  printf -- '- 起止：%s → %s（耗时 %ss，上限 %ss）\n' "$START" "$END" "$DUR" "$GATE_TIMEOUT"
  printf -- '- 门禁后工作区未提交文件数：%s%s\n' "$DIRTY" "$([ "$DIRTY" -gt 0 ] && echo '（⚠️ 验证的不是干净树）')"
  tail -n +6 "$EV"
} > "$TMP"
mv "$TMP" "$EV"

echo
echo "$VERDICT  证据已写入 $EV"
[ "$EXIT" -ne 0 ] && echo "⚠️ 门禁未通过 —— 禁止发布。先修基线。"
exit "$EXIT"
