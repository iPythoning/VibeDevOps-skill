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
echo "  feature-map 校验器: OK（一致通过 / 三类漂移各自转红）"

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
tier_of() { PATH="$TOOLS:$PATH" "$CI_T/automerge-tiers.sh" --pr 1 --repo o/r >/dev/null 2>&1; echo $?; }

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

# ── 4. skill 评测脚本语法（workflow 约定：顶层 return 合法，包一层验）──
node -e "
const fs=require('fs');
const src=fs.readFileSync('$ROOT/skills/vibedevops/templates/skill-testing/run-skill-eval.js','utf8');
new (Object.getPrototypeOf(async function(){}).constructor)('args','agent','parallel','phase','log', src.replace(/^export const meta/m,'const meta'));
" || { echo "FAIL: run-skill-eval.js 语法错误"; exit 1; }
echo "  skill 评测脚本语法: OK"

echo "verification autonomy guardrails: OK"
