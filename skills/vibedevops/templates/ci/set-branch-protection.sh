#!/bin/bash
# set-branch-protection —— 给默认分支装上机械门（ADR 0011 自动合并的前提）。
#
# 为什么需要：实测过本组织的主力仓，`branches/main/protection` 全部 404、
# rulesets 全空——**CI 红也能点 Merge、谁都能直推 main 触发生产部署**。
# 在这种仓上谈「让 agent 自动合并」，是在没有门的房子上装智能门锁。
#
# 配置取向（单人/小团队）：
#   - 要求 CI 通过        ← 唯一真正的门
#   - **不要求 review**   ← 单人仓要求 review 等于把自己锁死
#   - 管理员可绕过        ← 紧急逃生门；enforce_admins=false
#   - 禁 force push / 禁删分支
#
# 安全阀（最重要）：**拒绝设一个该仓从没在 PR 上跑过的 check 名**。
# 设错名字的后果是 PR 永远 BLOCKED——等一个永不出现的检查，而界面上
# 只显示「Expected — Waiting for status to be reported」，很难看出是配置错。
#
# 用法：
#   set-branch-protection.sh --repo owner/name --checks "ci,secrets" [--branch main]
#                            [--dry-run] [--force-unverified-checks]
#   set-branch-protection.sh --repo owner/name --remove      # 回滚
set -euo pipefail

REPO=""; CHECKS=""; BRANCH="main"; DRY=0; REMOVE=0; FORCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO=$2; shift 2 ;;
    --checks) CHECKS=$2; shift 2 ;;
    --branch) BRANCH=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --remove) REMOVE=1; shift ;;
    --force-unverified-checks) FORCE=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "必须给 --repo owner/name" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "需要 gh CLI" >&2; exit 2; }

if [ "$REMOVE" = "1" ]; then
  gh api -X DELETE "repos/$REPO/branches/$BRANCH/protection" >/dev/null 2>&1 \
    && echo "✅ 已移除 $REPO@$BRANCH 的分支保护" \
    || { echo "❌ 移除失败（本来就没有？）" >&2; exit 1; }
  exit 0
fi
[ -n "$CHECKS" ] || { echo "必须给 --checks（逗号分隔）；先跑 --dry-run 看建议" >&2; exit 2; }

# ── 安全阀：这些 check 真的会在 PR 上出现吗？ ──
# 判据来自最近合并的 PR 的实际 check 记录，不是猜的
echo "核验 check 名（防止 PR 永远等一个不存在的检查）…"
# 两个坑（都实测踩过）：
#   1. `gh pr checks` 在该 PR 有失败 check 时**返回非零** → set -e 会直接杀掉脚本，
#      表现为「核验中…」之后无声退出。必须 || true。
#   2. 输出是 **tab 分隔**，而 check 名可以含空格（如 matrix 渲染出的
#      `pytest (sqlite)`）——用 awk '{print $1}' 会把它截成 `pytest`，
#      于是核验永远失败。必须按 tab 取第一列。
#   3. `|| true` 会把**网络失败**一起吞掉 → SEEN 为空 → 安全阀退化成「一律拒绝」，
#      而且报的是「从没出现过」（实为「没查到」）。实测撞过一次 TLS handshake
#      timeout，正确的 check 名被拒。fail-closed 方向没错，误导的诊断信息才是问题：
#      它会把人训练成习惯性加 --force，等于废掉安全阀。必须把两种成因分开报。
SEEN=""; OK_PRS=0; TOTAL_PRS=0
for pr in $(gh pr list -R "$REPO" --state merged -L 5 --json number --jq '.[].number' 2>/dev/null); do
  TOTAL_PRS=$((TOTAL_PRS + 1))
  OUT=$(gh pr checks "$pr" -R "$REPO" 2>/dev/null || true)
  [ -n "$OUT" ] && OK_PRS=$((OK_PRS + 1))
  SEEN="$SEEN$(printf '%s\n' "$OUT" | cut -f1)
"
done
if [ "$TOTAL_PRS" -gt 0 ] && [ "$OK_PRS" -eq 0 ]; then
  echo "⛔ 无法核验 check 名：${TOTAL_PRS} 个 PR 一个都没取到 check 记录。" >&2
  echo "   这通常是网络或权限问题，**不代表** check 名是错的——先重试，别急着 --force。" >&2
  exit 4
fi
MISSING=""
IFS=',' read -ra ARR <<< "$CHECKS"
for c in "${ARR[@]}"; do
  c=$(echo "$c" | xargs)
  echo "$SEEN" | grep -qxF "$c" || MISSING="$MISSING $c"
done
if [ -n "$MISSING" ]; then
  echo "⛔ 这些 check 名在最近 5 个已合并 PR 里从没出现过：$MISSING" >&2
  echo "   设成必需会让后续 PR 永远 BLOCKED（界面只显示 Waiting for status，很难看出是配置错）。" >&2
  echo "   先确认名字拼写与该仓 workflow 的 job 名一致；确实要设请加 --force-unverified-checks。" >&2
  [ "$FORCE" = "1" ] || exit 3
  echo "   （--force-unverified-checks 已指定，继续）" >&2
fi

CTX=$(printf '%s' "$CHECKS" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | python3 -c 'import json,sys;print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
BODY=$(python3 -c "
import json,sys
print(json.dumps({
  'required_status_checks': {'strict': False, 'contexts': json.loads(sys.argv[1])},
  'enforce_admins': False,          # 紧急逃生门
  'required_pull_request_reviews': None,   # 单人仓不要求 review
  'restrictions': None,
  'allow_force_pushes': False,
  'allow_deletions': False,
  'required_linear_history': False,
  'required_conversation_resolution': False,
}))" "$CTX")

if [ "$DRY" = "1" ]; then
  echo "── dry-run：将对 $REPO@$BRANCH 设置 ──"
  echo "$BODY" | python3 -m json.tool
  echo "（最近 PR 上实际出现过的 check：）"
  echo "$SEEN" | sort -u | grep -v '^$' | sed 's/^/    /'
  exit 0
fi

echo "$BODY" | gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input - > /tmp/bp-out.json 2>&1 || {
  echo "❌ 设置失败：" >&2; head -3 /tmp/bp-out.json >&2; exit 1
}

# ── 读回自证：设了不等于生效 ──
VERIFY=$(gh api "repos/$REPO/branches/$BRANCH/protection" --jq '.required_status_checks.contexts | join(",")' 2>/dev/null || true)
if [ -z "$VERIFY" ]; then
  echo "❌ 读回验证失败——设置可能没生效" >&2; exit 1
fi
echo "✅ $REPO@$BRANCH 已保护 · 必需检查: $VERIFY"
echo "   不要求 review（单人仓）· 管理员可绕过（逃生门）· 禁 force push/删分支"
echo "   回滚: $0 --repo $REPO --remove"
