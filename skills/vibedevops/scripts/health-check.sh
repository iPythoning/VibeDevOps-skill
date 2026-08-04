#!/usr/bin/env bash
# health-check.sh — VibeDevOps 生产就绪体检（0–100 分 + 缺口清单）
#
# 对任意 git 仓库按 7 个维度打分，对应 SKILL.md 第六节的评分表：
#   测试 15 / CI 15 / 密钥 20 / 监控 15 / 回滚 10 / 环境可复现 10 / 交接文件 15
#
# 用法：
#   ./health-check.sh [repo-dir]        # 默认当前目录
#   ./health-check.sh --json [dir]      # JSON 输出
#   ./health-check.sh --min 60 [dir]    # 门禁模式：低于 60 分退出码 1（可挂 pre-push / CI）
#   curl -fsSL <raw-url> | bash -s -- /path/to/repo
#
# 门禁接法示例（.git/hooks/pre-push 或 CI step）：
#   ./health-check.sh --min 60 . || { echo "生产就绪分不达标，禁止 push"; exit 1; }
#
# bash 3.2 兼容（macOS 自带）：不用数组；$VAR 后接中文一律 ${VAR}；
# 不用「git xxx | head -1」管道（pipefail 下 SIGPIPE 会翻转退出码），一律命令替换后判空。

set -uo pipefail

JSON=0
REPO="."
MIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift;;
    --min)  MIN="$2"; shift 2;;
    *)      REPO="$1"; shift;;
  esac
done

[ -d "$REPO/.git" ] || { echo "❌ ${REPO} 不是 git 仓库"; exit 1; }
REPO="$(cd "$REPO" && pwd)"
cd "$REPO"

SCORE=0
GAPS=""
NOTE=""
TRACKED="$(git ls-files)"   # 跟踪文件清单快照，monorepo 子目录也能查到

gap() { GAPS="${GAPS}$1
"; }
note() { NOTE="${NOTE}$1
"; }
# 任一路径存在即真（避免 `ls a b c` 部分缺失返回非零的坑）
has_any() { for f in "$@"; do [ -e "$f" ] && return 0; done; return 1; }
# 在跟踪文件内容里搜模式，找到即真（命令替换判空，不走管道）
tracked_has() { [ -n "$(git grep -lIl -e "$1" 2>/dev/null)" ]; }
tracked_re()  { [ -n "$(git grep -lIE "$1" 2>/dev/null)" ]; }
# 跟踪文件路径里匹配（查文件名，不查内容）
path_has() { printf '%s\n' "$TRACKED" | grep -qE "$1"; }
# 占位符 ≥3 处才算「模板未填」（个别 待补充 不误伤）
tmpl_bad() { [ "$(grep -coE '待补充|TODO|占位|\[填写' "$1" 2>/dev/null)" -ge 3 ]; }

# ── 1. 测试（15）──────────────────────────────────────────
T=0
if path_has '(^|/)(tests?|__tests__|spec|e2e)/' \
   || path_has '(^|/)(jest\.config\.|vitest\.config\.|pytest\.ini|tox\.ini|\.rspec|go\.mod$)'; then
  T=8
else
  gap "[测试 -8] 没有测试目录或测试配置（tests/、jest.config、pytest.ini…）"
fi
VERIFY_HIT=""
if [ -f AGENTS.md ] && grep -Eq '验证|verify|test' AGENTS.md && ! grep -q '待补充' AGENTS.md; then VERIFY_HIT=1; fi
if path_has '(^|/)package\.json$' && git grep -q '"test"' -- '*/package.json' package.json 2>/dev/null; then VERIFY_HIT=1; fi
if [ -f Makefile ] && grep -q '^test:' Makefile; then VERIFY_HIT=1; fi
if [ -n "$VERIFY_HIT" ]; then T=$((T+7)); else gap "[测试 -7] 找不到明确的验证命令（AGENTS.md 验证命令段 / package.json test / Makefile test）"; fi
SCORE=$((SCORE+T)); note "测试：${T}/15"

# ── 2. CI（15）────────────────────────────────────────────
C=0
if [ -d .github/workflows ]; then
  PR=0; DEPLOY=0
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    grep -q 'pull_request' "$f" && PR=1
    grep -qiE 'deploy|release|cd' "$f" && DEPLOY=1
  done
  [ "$PR" = 1 ]     && C=$((C+8))  || gap "[CI -8] 有 workflows 但没有 PR 触发的检查流（pull_request）"
  [ "$DEPLOY" = 1 ] && C=$((C+7))  || gap "[CI -7] 有 workflows 但没有部署/发布流（deploy/release）"
else
  gap "[CI -15] 没有 .github/workflows/ —— PR 无机械门禁，合并靠自觉"
fi
SCORE=$((SCORE+C)); note "CI：${C}/15"

# ── 3. 密钥（20）──────────────────────────────────────────
S=0
if [ -f .gitignore ] && grep -qE '^\.env($|[^a-z])|\*\.env' .gitignore; then
  S=$((S+5))
else
  gap "[密钥 -5] .gitignore 没有排除 .env"
fi
LEAK=""
printf '%s\n' "$TRACKED" | grep -E '(^|/)\.env($|\.)' | grep -qvE '\.example|\.sample|\.template' && LEAK=1
[ -z "$LEAK" ] && [ -n "$(git log --all --oneline -- '*.env' 2>/dev/null)" ] && LEAK=1
[ -z "$LEAK" ] && tracked_re 'sk-[A-Za-z0-9]{20}|ghp_[A-Za-z0-9]{20}|gho_[A-Za-z0-9]{20}|AKIA[A-Z0-9]{16}|^-----BEGIN [A-Z ]*PRIVATE KEY-----$' && LEAK=1
if [ -z "$LEAK" ]; then S=$((S+10)); else gap "[密钥 -10] 仓库或 git 历史里发现疑似密钥/.env 入库痕迹 —— 先轮换再清史（git filter-repo）"; fi
if path_has '(^|/)(\.?infisical\.json|\.?sops\.ya?ml)$' || tracked_re 'infisical|doppler|sops'; then
  S=$((S+5))
elif path_has '(^|/)\.env\.(example|sample|template)$'; then
  S=$((S+3)); gap "[密钥 -2] 有 .env.example 占位（好），但没有运行时注入方案（infisical/sops/doppler）"
else
  gap "[密钥 -5] 没有密钥注入/托管方案，也没有 .env.example"
fi
SCORE=$((SCORE+S)); note "密钥：${S}/20"

# ── 4. 监控（15）──────────────────────────────────────────
M=0
if tracked_has 'health'; then
  M=$((M+5))
  # /health 是否真的查依赖（db/redis ping），而不是硬编码 200
  if tracked_re 'SELECT 1|\.ping\(|redis.*ping|db\.(raw|execute)|prisma\.\$queryRaw'; then
    M=$((M+5))
  else
    gap "[监控 -5] 有 /health 端点但看不到依赖真实检查（db/redis ping）—— 硬编码 200 等于没有"
  fi
else
  gap "[监控 -10] 没有 /health 端点"
fi
if tracked_re 'sentry|Sentry|rollbar|honeybadger|bugsnag'; then
  M=$((M+5))
else
  gap "[监控 -5] 没有错误追踪接入（Sentry / Rollbar / Honeybadger…）"
fi
SCORE=$((SCORE+M)); note "监控：${M}/15"

# ── 5. 回滚预案（10）──────────────────────────────────────
R=0
RB=""
for f in RUNBOOK.md docs/RUNBOOK.md docs/runbook.md; do [ -f "$f" ] && RB="$f" && break; done
if [ -n "$RB" ]; then
  R=$((R+5))
  if grep -qiE 'rollback|回滚' "$RB" && grep -qiE 'backup|备份' "$RB"; then
    R=$((R+5))
  else
    gap "[回滚 -5] ${RB} 存在但缺回滚或备份步骤"
  fi
else
  gap "[回滚 -10] 没有 RUNBOOK —— 出事时的标准动作不存在"
fi
SCORE=$((SCORE+R)); note "回滚：${R}/10"

# ── 6. 环境可复现（10）────────────────────────────────────
E=0
if path_has '(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|requirements.*\.txt|Pipfile\.lock|poetry\.lock|uv\.lock|go\.sum|Gemfile\.lock|Cargo\.lock|composer\.lock)$'; then
  E=$((E+5))
else
  gap "[环境 -5] 没有依赖版本锁定文件"
fi
RM=""
for f in README.md readme.md README; do [ -f "$f" ] && RM="$f" && break; done
if [ -n "$RM" ] && grep -qiE 'install|安装|npm i|pip install|docker compose|make |快速开始|quickstart|getting started' "$RM"; then
  E=$((E+5))
else
  gap "[环境 -5] README 没有安装/跑通说明 —— 验收标准：新机器 clone 到跑通 ≤ 5 分钟"
fi
SCORE=$((SCORE+E)); note "环境：${E}/10"

# ── 7. 交接文件（15）──────────────────────────────────────
H=0
if [ -f AGENTS.md ] && [ "$(wc -c < AGENTS.md)" -gt 500 ] && ! tmpl_bad AGENTS.md; then
  H=$((H+5))
else
  gap "[交接 -5] AGENTS.md 缺失/过薄/还是模板未填状态"
fi
if [ -f docs/HANDOFF.md ] && ! tmpl_bad docs/HANDOFF.md; then
  H=$((H+5))
else
  gap "[交接 -5] docs/HANDOFF.md 缺失或未填 —— 换 agent 就失忆"
fi
if path_has '^docs/adr/.+\.md$'; then
  H=$((H+5))
else
  gap "[交接 -5] docs/adr/ 没有决策记录 —— 三个月后没人知道当初为什么这么改"
fi
SCORE=$((SCORE+H)); note "交接：${H}/15"

# ── 输出 ──────────────────────────────────────────────────
if [ "$SCORE" -ge 80 ]; then VERDICT="🟢 可以上线，保持纪律";
elif [ "$SCORE" -ge 60 ]; then VERDICT="🟡 能跑但有裸奔环节，先补缺口";
elif [ "$SCORE" -ge 40 ]; then VERDICT="🟠 多处裸奔，出事是时间问题";
else VERDICT="🔴 祈祷驱动部署（Prayer-Driven Deployment）"; fi

# 门禁判定：--min 模式下低于阈值退出码 1（JSON / 文本两条输出路径共用）
gate_exit() {
  if [ -n "$MIN" ] && [ "$SCORE" -lt "$MIN" ]; then
    [ "$JSON" = 1 ] || echo " ⛔ 门禁：${SCORE} < ${MIN}，不达标（补上面的缺口再来）"
    exit 1
  fi
  exit 0
}

if [ "$JSON" = 1 ]; then
  printf '{"repo":"%s","score":%d,"min":%s,"verdict":"%s","breakdown":"%s","gaps":"%s"}\n' \
    "$REPO" "$SCORE" "${MIN:-null}" "$VERDICT" "$(printf %s "$NOTE" | tr '\n' ';')" "$(printf %s "$GAPS" | tr '\n' ';' | sed 's/"/\\"/g')"
  gate_exit
fi

echo "════════════════════════════════════════════"
echo " VibeDevOps 体检 · $(basename "$REPO")"
echo "════════════════════════════════════════════"
printf %s "$NOTE"
echo "--------------------------------------------"
echo " 总分：${SCORE}/100   ${VERDICT}"
echo "--------------------------------------------"
if [ -n "$GAPS" ]; then
  echo " 缺口清单（按维度排列，从上往下补）:"
  printf %s "$GAPS" | sed 's/^/  • /'
else
  echo " 没有缺口 —— 纪律保持住。"
fi
echo "--------------------------------------------"
echo " 分享你的得分：${SCORE}/100 🩺 https://github.com/iPythoning/VibeDevOps-skill"
gate_exit
