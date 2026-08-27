#!/bin/bash
# automerge-tiers —— 判定一个 PR 属于哪一档合并权限（ADR 0011 第四层）。
#
# 自动合并不是「CI 绿了就合」——CI 绿而产品是坏的，这条流水线上已经发生过
# 多次（ADR 0009）。这里的判据是**改动的可逆性**与**证据的充分性**两条轴：
#
#   T1 auto      纯可逆、无运行时影响 → CI 绿即可自动合并
#   T2 evidence  有运行时影响但可验证 → CI 绿 + 实际操作过产品的证据
#   T3 human     不可逆或影响面超出可验证范围 → 永远人工，不接受任何证据豁免
#
# T3 是**硬边界**：自动化的是「确认功能是否成立」，不是「替人承担不可逆后果」。
#
# 用法：automerge-tiers.sh --pr 123 --repo owner/name [--json]
# 退出码：0=T1  10=T2  20=T3  30=仓库无分支保护（前提不成立）  2=用法错误
set -euo pipefail

PR=""; REPO=""; JSON=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr) PR=$2; shift 2 ;;
    --repo) REPO=$2; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$PR" ] && [ -n "$REPO" ] || { echo "用法: --pr N --repo owner/name" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "需要 gh CLI" >&2; exit 2; }

# ── 前置门：没有分支保护，自动合并就是空中楼阁 ──
# 实测过的真实状态：三个仓 GET /branches/main/protection 全 404、rulesets 全空——
# 也就是 CI 红也能点 Merge、谁都能直推 main 触发生产部署。**在这种仓上讨论
# 「让 agent 自动合并」是在没有门的房子上装智能门锁。** 先有机械门，再谈自动化。
if [ "${AUTOMERGE_SKIP_PROTECTION_CHECK:-0}" != "1" ]; then
  # 判据不能写成「输出为空即无保护」——gh api 在 404 时把错误 JSON 打到 **stdout**
  # （实测 149 字节的 {"message":"Branch not protected",...}），那样判据永远为假、
  # 这道门静默失效。要判实质字段：拿得到 required_status_checks 才算有保护。
  # 取 .url 而不是某个布尔字段：jq 的 `//` 对 **false 与 null 一视同仁**都走
  # alternative——判据写成 `.required_status_checks.strict // empty` 时，
  # strict=false 的正常保护会被判成「无保护」（本人实测踩中，同型第三次）。
  # .url 在保护存在时必为非空字符串，不存在时整个响应没有该字段。
  PROT=$(gh api "repos/$REPO/branches/main/protection" --jq '.url // empty' 2>/dev/null || true)
  RULES=$(gh api "repos/$REPO/rulesets" --jq 'length' 2>/dev/null || echo 0)
  case "$RULES" in ''|*[!0-9]*) RULES=0 ;; esac
  if [ -z "$PROT" ] && [ "$RULES" = "0" ]; then
    echo "⛔ $REPO 的 main 没有任何分支保护（protection 404 且 rulesets 空）。" >&2
    echo "   自动合并的前提是「CI 红不能合、不能直推 main」由平台强制，而不是靠自觉。" >&2
    echo "   先设保护规则；确认要在无保护仓上评估分档，设 AUTOMERGE_SKIP_PROTECTION_CHECK=1。" >&2
    exit 30
  fi
fi

FILES=$(gh pr view "$PR" -R "$REPO" --json files --jq '.files[].path' 2>/dev/null || true)
[ -n "$FILES" ] || { echo "取不到 PR 文件清单" >&2; exit 2; }

# ── T3：不可逆 / 超出可验证范围。命中任一即人工，不可豁免 ──
# 语义分组写清楚，方便各仓按需增补——**只增不减**。
T3_PATTERNS='
(^|/)(migrations?|alembic)/            # 数据库迁移：改错了要人来判断怎么回滚数据
(^|/)\.env|secrets?/|\.sops\.|age\.key # 密钥与凭据
docker-compose.*\.ya?ml$               # 生产编排
(^|/)nginx/|\.conf$                    # 反代与站点配置
(^|/)deploy/                           # 部署脚本
(^|/)\.github/workflows/               # 流水线自身：改坏了会让后续所有判据失效
(payment|billing|stripe|wechat.?pay|alipay) # 真钱路径
(auth|permission|rbac|tenant.?isolat)  # 认证/授权/租户隔离
'
T3_HIT=""
while IFS= read -r pat; do
  pat=$(echo "$pat" | sed 's/#.*//' | tr -d '[:space:]')
  [ -n "$pat" ] || continue
  HIT=$(echo "$FILES" | grep -iE "$pat" || true)
  [ -n "$HIT" ] && T3_HIT="$T3_HIT$(echo "$HIT" | head -3)\n"
done <<< "$T3_PATTERNS"

if [ -n "$T3_HIT" ]; then
  if [ "$JSON" = "1" ]; then
    printf '{"tier":"T3","reason":"不可逆或影响面超出可验证范围","files":%s}\n' \
      "$(echo -e "$T3_HIT" | grep -v '^$' | head -5 | python3 -c 'import json,sys;print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))' 2>/dev/null || echo '[]')"
  else
    echo "T3 · 人工合并（不可逆/超出可验证范围）"; echo -e "$T3_HIT" | grep -v '^$' | head -5 | sed 's/^/  /'
  fi
  exit 20
fi

# ── T1：纯可逆、无运行时影响 ──
# 判据是「全部文件都属于这些类别」，任何一个文件超出即降级到 T2。
NON_T1=$(echo "$FILES" | grep -vE '\.(md|txt)$|^docs/|(^|/)(tests?|__tests__|spec)/|\.(test|spec)\.[jt]sx?$|(^|/)i18n/.*\.json$|(^|/)locales?/' || true)
if [ -z "$NON_T1" ]; then
  if [ "$JSON" = "1" ]; then echo '{"tier":"T1","reason":"纯文档/测试/文案，无运行时影响"}'
  else echo "T1 · CI 绿即可自动合并（纯文档/测试/文案）"; fi
  exit 0
fi

# ── T2：有运行时影响但可验证 ──
if [ "$JSON" = "1" ]; then
  printf '{"tier":"T2","reason":"有运行时影响，需产品级证据","runtimeFiles":%s}\n' \
    "$(echo "$NON_T1" | head -5 | python3 -c 'import json,sys;print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))' 2>/dev/null || echo '[]')"
else
  cat <<'T2EOF'
T2 · 需要产品级证据才可自动合并。必须同时满足：
  1. CI 全绿
  2. 门禁自证有效——本次 CI 里存在一条会失败的变异证明，或门禁自带金丝雀
     （ADR 0009：从未被证明会红的检查等于没有检查）
  3. 实际操作过产品的证据：verify-web.sh 通过（含 console/网络/性能判据），
     或对应平台的等价实测（模拟器复现/API 端到端）
  4. 部署侧有自动回滚（健康检查失败即回退上一版本）
缺任何一条 → 降级人工。
T2EOF
  echo "  运行时文件："; echo "$NON_T1" | head -5 | sed 's/^/    /'
fi
exit 10
