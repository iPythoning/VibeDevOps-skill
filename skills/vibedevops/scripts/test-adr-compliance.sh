#!/usr/bin/env bash
# 守卫 check-adr-compliance.sh：反向变异证明每条校验真的会红（bd5f0c9 的解药——
# 「判据写错」不能在为治理判据而写的对账里复发）。
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# 复制整棵树（含 .git 无所谓，checker 只读文件）
( cd "$ROOT" && tar cf - --exclude=.git --exclude=node_modules . ) | ( cd "$WORK" && tar xf - )
CHK="$WORK/skills/vibedevops/scripts/check-adr-compliance.sh"

run() { ( cd "$WORK" && bash "$CHK" >/dev/null 2>&1 ); }
restore() { cp "$ROOT/$1" "$WORK/$1"; }

# 0) 干净树必须通过
run || { echo "FAIL: 干净树对账未通过（先修 templates 再谈守卫）"; ( cd "$WORK" && bash "$CHK" ); exit 1; }
echo "  基线：干净树对账通过 ✓"

expect_fail() { # $1=描述
  if run; then echo "FAIL: 变异未被抓到 —— $1"; exit 1; fi
  echo "  反向变异被抓：$1 ✓"
}

# 变异 1：模板 workflow 注入写死 runs-on（违反 0006）
cat >> "$WORK/skills/vibedevops/templates/ci/pr-check.yml" <<'YAML'
  _mut_hardcoded:
    runs-on: ubuntu-latest
    steps:
      - run: 'true'
YAML
expect_fail "0006 写死 runs-on"
restore skills/vibedevops/templates/ci/pr-check.yml

# 变异 2：抹掉 pr-check.yml 的金丝雀（违反 0009 §1）
sed -i.bak '/canary/d;/金丝雀/d;/self-proof/d' "$WORK/skills/vibedevops/templates/ci/pr-check.yml"
expect_fail "0009 §1 缺金丝雀"
restore skills/vibedevops/templates/ci/pr-check.yml

# 变异 3：塞入 --if-present（违反 0009 §2）
printf '      - run: npm run lint --if-present\n' >> "$WORK/skills/vibedevops/templates/ci/pr-check.yml"
expect_fail "0009 §2 --if-present 静默跳过"
restore skills/vibedevops/templates/ci/pr-check.yml

# 变异 4：新增一条既无 check 也未豁免的 ADR（违反覆盖强制）
printf '# ADR 0099：测试用假 ADR\n' > "$WORK/docs/adr/0099-fake-uncovered.md"
expect_fail "覆盖强制：新 ADR 无 check 无豁免"
rm -f "$WORK/docs/adr/0099-fake-uncovered.md"

# 变异 5：把对账从 ci.yml 摘掉（违反 0012）
sed -i.bak 's#check-adr-compliance.sh#DISABLED-adr-check#g' "$WORK/.github/workflows/ci.yml"
expect_fail "0012 对账未挂进 CI"
restore .github/workflows/ci.yml

echo "adr-compliance guardrails: OK"
