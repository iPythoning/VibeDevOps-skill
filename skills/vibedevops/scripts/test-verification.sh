#!/bin/bash
# 验证自治层守卫测试（ADR 0011）：feature-map 校验器 / automerge 分级 / verify-web 判据。
# 全部用 PATH 替身，不依赖真实浏览器与 gh 认证，可在干净 CI 容器里跑。
set -e

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
V="$ROOT/skills/vibedevops/templates/verification"
CI_T="$ROOT/skills/vibedevops/templates/ci"
FIX="$(mktemp -d)"
trap 'code=$?; [ "$code" -eq 0 ] || echo "verification fixture failed near line $LINENO" >&2; rm -rf "$FIX"' EXIT

TOOLS="$FIX/tools"; mkdir -p "$TOOLS"

# ── 1. feature-map 校验器 ──
mkdir -p "$FIX/repo/src/pages" "$FIX/repo/src/i18n"
cat > "$FIX/repo/src/App.tsx" <<'EOF'
<Route path="inbox" element={<Inbox />} />
<Route path="settings" element={<Settings />} />
EOF
: > "$FIX/repo/src/pages/Inbox.tsx"
: > "$FIX/repo/src/pages/Settings.tsx"
echo '{"inbox":{"title":"收件箱"},"settings":{"title":"设置"}}' > "$FIX/repo/src/i18n/zh.json"

write_map() { # $1=out $2=route $3=component $4=i18n_prefix
cat > "$1" <<EOF
meta:
  product: fixture
  router_file: src/App.tsx
  i18n_files: [src/i18n/zh.json]
features:
  - name: 收件箱
    route: $2
    components: [$3]
    i18n_prefix: $4
EOF
}

write_map "$FIX/good.yaml" "/app/inbox" "src/pages/Inbox.tsx" "inbox"
(cd "$FIX/repo" && "$V/check-feature-map.sh" --map "$FIX/good.yaml" >/dev/null 2>&1) \
  || { echo "FAIL: 一致的 map 应该通过"; exit 1; }

# 变异 A：路由不存在 → 必须红
write_map "$FIX/bad-route.yaml" "/app/ghost" "src/pages/Inbox.tsx" "inbox"
if (cd "$FIX/repo" && "$V/check-feature-map.sh" --map "$FIX/bad-route.yaml" >/dev/null 2>&1); then
  echo "FAIL: 路由不存在时应该红"; exit 1
fi

# 变异 B：路由对但组件指向别的页面 → 必须红（这是实战踩过的形态）
write_map "$FIX/bad-comp.yaml" "/app/inbox" "src/pages/Settings.tsx" "inbox"
if (cd "$FIX/repo" && "$V/check-feature-map.sh" --map "$FIX/bad-comp.yaml" >/dev/null 2>&1); then
  echo "FAIL: route 指向 <Inbox> 而 map 写 Settings 时应该红"; exit 1
fi

# 变异 C：i18n 前缀不存在 → 必须红
write_map "$FIX/bad-i18n.yaml" "/app/inbox" "src/pages/Inbox.tsx" "nosuchprefix"
if (cd "$FIX/repo" && "$V/check-feature-map.sh" --map "$FIX/bad-i18n.yaml" >/dev/null 2>&1); then
  echo "FAIL: i18n 前缀不存在时应该红"; exit 1
fi
# 实战暴露的两个缺陷（都在 PulseAgent 建首份地图时踩到）：
# ① 注释掉的路由被当成真路由 → strict 模式误报「未入图」
# ② 顶层包装组件（<ProtectedRoute><Onboarding/></ProtectedRoute>）只抓到外层，
#    而包装组件常是内联函数无对应文件，那条路由怎么填都过不了
cat > "$FIX/repo/src/App2.tsx" <<'EOF'
{/* <Route path="retired" element={<Retired />} /> */}
<Route path="/app/onboarding" element={<ProtectedRoute><Inbox /></ProtectedRoute>} />
EOF
cat > "$FIX/wrap.yaml" <<EOF
meta:
  product: fixture
  router_file: src/App2.tsx
  i18n_files: [src/i18n/zh.json]
features:
  - name: 套壳路由
    route: /app/onboarding
    components: [src/pages/Inbox.tsx]
    i18n_prefix: inbox
EOF
(cd "$FIX/repo" && "$V/check-feature-map.sh" --map "$FIX/wrap.yaml" >/dev/null 2>&1)   || { echo "FAIL: 包装组件应被穿透到内层功能组件"; exit 1; }
# 注释里的路由不该出现在 strict 警告中
STRICT_OUT=$(cd "$FIX/repo" && "$V/check-feature-map.sh" --map "$FIX/wrap.yaml" --strict 2>&1 || true)
echo "$STRICT_OUT" | grep -q 'retired' && { echo "FAIL: 注释掉的路由不该被当成真路由"; exit 1; }
# 零依赖降级路径必须与 pyyaml 路径同判：构建机上常只有 python3 没有 pip
# （实测 self-hosted runner `pip: command not found`，这道门禁首跑即挂）。
# 降级路径若不被测，出问题时才第一次跑——ADR 0009 同款。
(cd "$FIX/repo" && FEATURE_MAP_PARSER=builtin "$V/check-feature-map.sh" --map "$FIX/good.yaml" >/dev/null 2>&1) \
  || { echo "FAIL: builtin 解析器应与 pyyaml 同判为通过"; exit 1; }
if (cd "$FIX/repo" && FEATURE_MAP_PARSER=builtin "$V/check-feature-map.sh" --map "$FIX/bad-comp.yaml" >/dev/null 2>&1); then
  echo "FAIL: builtin 解析器必须也能抓到组件不匹配（否则是解析出空数据的假绿）"; exit 1
fi
echo "  feature-map 校验器: OK（一致通过 / 三类漂移转红 / 跳注释 / 穿透包装 / 零依赖降级同判）"

# ── 2. automerge 分级 ──
mk_gh() { # $1=文件清单（换行分隔）
  cat > "$TOOLS/gh" <<EOF
#!/bin/bash
case "\$*" in
  *"--json files"*) printf '%s\n' '$1' ;;
  *) echo '{}' ;;
esac
EOF
  chmod 755 "$TOOLS/gh"
}
tier_of() { PATH="$TOOLS:$PATH" AUTOMERGE_SKIP_PROTECTION_CHECK=1 "$CI_T/automerge-tiers.sh" --pr 1 --repo o/r >/dev/null 2>&1; echo $?; }

# 前置门：gh api 404 时会把错误 JSON 打到 stdout——判据若写成「输出为空即无保护」
# 就永远为假、门静默失效（本人实测踩中）。这里 mock 出真实的 404 形态，必须判 30。
cat > "$TOOLS/gh" <<'GHEOF'
#!/bin/bash
case "$*" in
  # 真实 gh：404 时错误 JSON 走 stdout；带 --jq 时过滤器作用其上、提不到字段即空输出。
  # 两种形态都 mock，才能证明判据用的是实质字段而不是「输出是否为空」。
  *"branches/main/protection"*--jq*|*--jq*"branches/main/protection"*) exit 0 ;;
  *"branches/main/protection"*) echo '{"message":"Branch not protected","status":"404"}'; exit 0 ;;
  *rulesets*) echo 0 ;;
  *"--json files"*) echo 'README.md' ;;
  *) echo '{}' ;;
esac
GHEOF
chmod 755 "$TOOLS/gh"
PROT_CODE=0
PATH="$TOOLS:$PATH" "$CI_T/automerge-tiers.sh" --pr 1 --repo o/r >/dev/null 2>&1 || PROT_CODE=$?
[ "$PROT_CODE" = "30" ] || { echo "FAIL: 无分支保护时应判 30，实际 $PROT_CODE"; exit 1; }
# 反向：strict=false 的**正常保护**必须被认出来（jq `//` 对 false 走 alternative
# 的坑，会把正常保护误判成无保护——同型第三次，锁死）
cat > "$TOOLS/gh" <<'GHEOF'
#!/bin/bash
case "$*" in
  *"branches/main/protection"*--jq*|*--jq*"branches/main/protection"*)
    echo 'https://api.github.com/repos/o/r/branches/main/protection' ;;
  *rulesets*) echo 0 ;;
  *"--json files"*) echo 'README.md' ;;
  *) echo '{}' ;;
esac
GHEOF
chmod 755 "$TOOLS/gh"
PROT_OK=0
PATH="$TOOLS:$PATH" "$CI_T/automerge-tiers.sh" --pr 1 --repo o/r >/dev/null 2>&1 || PROT_OK=$?
[ "$PROT_OK" = "0" ] || { echo "FAIL: 有分支保护时应正常判档（T1=0），实际 $PROT_OK"; exit 1; }
echo "  automerge 前置门: OK（无保护拒判档 / 有保护放行，含 strict=false 形态）"

mk_gh 'README.md
docs/HANDOFF.md
src/__tests__/a.test.ts'
[ "$(tier_of)" = "0" ] || { echo "FAIL: 纯文档+测试应为 T1(0)，实际 $(tier_of)"; exit 1; }

mk_gh 'src/pages/Inbox.tsx
src/services/api.ts'
[ "$(tier_of)" = "10" ] || { echo "FAIL: 运行时代码应为 T2(10)，实际 $(tier_of)"; exit 1; }

for danger in 'backend/migrations/001_x.py' '.github/workflows/deploy.yml' 'docker-compose.prod.yml' 'src/payment/stripe.ts' 'deploy/nginx/site.conf' 'backend/app/auth/rbac.py'; do
  mk_gh "$danger"
  [ "$(tier_of)" = "20" ] || { echo "FAIL: $danger 应为 T3(20)，实际 $(tier_of)"; exit 1; }
done

# 混合：一个危险文件即整体降到 T3（不能被大量安全文件稀释）
mk_gh 'README.md
docs/a.md
backend/migrations/002_y.py'
[ "$(tier_of)" = "20" ] || { echo "FAIL: 混合含迁移应为 T3"; exit 1; }
echo "  automerge 分级: OK（T1/T2/T3 各档 + 混合不被稀释）"

# ── 3. verify-web 用法守卫（不跑浏览器，只验参数与前置检查）──
# 干净 PATH（无 ego-browser）：必须以「缺依赖」非零退出，而不是假装验证过
if env PATH=/usr/bin:/bin "$V/verify-web.sh" --url http://example.com --out "$FIX/ev" >/dev/null 2>&1; then
  echo "FAIL: 缺 ego-browser 时应非零退出"; exit 1
fi
if "$V/verify-web.sh" --url not-a-url 2>/dev/null; then echo "FAIL: 非法 URL 应被拒"; exit 1; fi
if "$V/verify-web.sh" 2>/dev/null; then echo "FAIL: 缺 --url 应被拒"; exit 1; fi
echo "  verify-web 参数守卫: OK"

# capture-trace 同款参数守卫
if env PATH=/usr/bin:/bin "$V/capture-trace.sh" --url https://example.com >/dev/null 2>&1; then
  echo "FAIL: capture-trace 缺 ego-browser 时应非零退出"; exit 1
fi
if "$V/capture-trace.sh" --url https://x.com --mode bogus >/dev/null 2>&1; then
  echo "FAIL: 非法 --mode 应被拒"; exit 1
fi
if "$V/capture-trace.sh" --mode trace >/dev/null 2>&1; then echo "FAIL: 缺 --url 应被拒"; exit 1; fi
echo "  capture-trace 参数守卫: OK"

# ── 4. skill 评测脚本语法（workflow 约定：顶层 return 合法，包一层验）──
node -e "
const fs=require('fs');
const src=fs.readFileSync('$ROOT/skills/vibedevops/templates/skill-testing/run-skill-eval.js','utf8');
new (Object.getPrototypeOf(async function(){}).constructor)('args','agent','parallel','phase','log', src.replace(/^export const meta/m,'const meta'));
" || { echo "FAIL: run-skill-eval.js 语法错误"; exit 1; }
echo "  skill 评测脚本语法: OK"

# 模板字符串里混入反引号会提前终止它——本次开发撞了三次（每次都是往 prompt
# 里写 markdown code span）。语法检查能抓到，但报错信息指向被截断处、很难读，
# 所以这里单独给一条明确的失败信息。
node -e "
const fs=require('fs');
const src=fs.readFileSync('$ROOT/skills/vibedevops/templates/skill-testing/run-skill-eval.js','utf8');
// 统计非转义反引号数：模板字符串成对，奇数即有一个孤儿
const ticks=(src.match(/(?<!\\\\)\`/g)||[]).length;
if (ticks % 2 !== 0) { console.error('反引号不成对（'+ticks+' 个）——模板字符串里混了 code span？'); process.exit(1); }
" || { echo "FAIL: run-skill-eval.js 反引号不成对"; exit 1; }
echo "  模板字符串反引号配对: OK"

# ── 5. set-branch-protection 安全阀 ──
# 上一版发布时这个脚本**一条守卫都没有**（ADR 0009：没被测过的门禁等于没有门禁），
# 于是它的假阳性是靠生产上撞出来的。三条 case 对应三种成因，必须能被区分开。
BP="$CI_T/set-branch-protection.sh"
mkdir -p "$FIX/bp"
mk_gh() {  # $1=checks 输出内容（空串模拟网络失败）
  cat > "$TOOLS/gh" <<EOF
#!/bin/bash
case "\$1 \$2" in
  "pr list") echo '11'; echo '12' ;;
  "pr checks") printf '%b' "$1" ;;
  "api "*) echo '{}' ;;
  *) echo '{}' ;;
esac
exit 0
EOF
  chmod 755 "$TOOLS/gh"
}

# 5a. check 名确实跑过 → 放行（dry-run 到底）
mk_gh 'test\tpass\t3s\thttp://x
image\tpass\t1s\thttp://y'
PATH="$TOOLS:$PATH" bash "$BP" --repo o/r --checks test --dry-run > "$FIX/bp/a.log" 2>&1 \
  || { echo "FAIL: 跑过的 check 名被误拒"; cat "$FIX/bp/a.log"; exit 1; }

# 5b. check 名从没跑过 → exit 3 拒绝（安全阀本体）
set +e
PATH="$TOOLS:$PATH" bash "$BP" --repo o/r --checks nonexistent --dry-run > "$FIX/bp/b.log" 2>&1
B=$?
set -e
[ "$B" = "3" ] || { echo "FAIL: 未跑过的 check 名应 exit 3，实际 $B"; cat "$FIX/bp/b.log"; exit 1; }
grep -q '从没出现过' "$FIX/bp/b.log" || { echo "FAIL: 缺「从没出现过」诊断"; exit 1; }

# 5c. 一个 PR 都取不到 check（网络/权限失败）→ 必须报「无法核验」而不是「从没出现过」。
# 实测撞过：TLS handshake timeout 把正确的 check 名判成不存在。fail-closed 没错，
# 误导的诊断才是问题——它把人训练成习惯性 --force，等于废掉安全阀。
mk_gh ''
set +e
PATH="$TOOLS:$PATH" bash "$BP" --repo o/r --checks test --dry-run > "$FIX/bp/c.log" 2>&1
C=$?
set -e
[ "$C" = "4" ] || { echo "FAIL: 取不到 check 记录应 exit 4（区别于 3），实际 $C"; cat "$FIX/bp/c.log"; exit 1; }
grep -q '无法核验' "$FIX/bp/c.log" || { echo "FAIL: 网络失败被误报成「从没出现过」"; cat "$FIX/bp/c.log"; exit 1; }
grep -q '从没出现过' "$FIX/bp/c.log" && { echo "FAIL: 网络失败不该报「从没出现过」"; exit 1; }
rm -f "$TOOLS/gh"
echo "  分支保护安全阀（放行/拒绝/网络失败三分）: OK"

echo "verification autonomy guardrails: OK"
