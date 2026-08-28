#!/usr/bin/env bash
# ADR 0006 §1：必过 workflow 不写死 runner，runs-on 走仓库变量
#   runs-on: ${{ vars.CI_RUNNER && fromJSON(vars.CI_RUNNER) || 'ubuntu-latest' }}
# 例外（刻意钉死目标 runner，各有理由，见各文件头注释）：
#   onboard-heartbeat（监控不得与被监控共享失败模式）、hosted-canary（它就是 hosted 探针）、
#   runner-canary（探针必须固定目标才能实测该 runner）。
set -u
ALLOW='onboard-heartbeat\.yml|hosted-canary\.yml|runner-canary\.yml'
bad=0
FILES=$( { find skills/vibedevops/templates -name '*.yml' 2>/dev/null; ls .github/workflows/*.yml 2>/dev/null; } | sort -u )
while IFS= read -r f; do
  [ -n "$f" ] || continue
  echo "$f" | grep -qE "$ALLOW" && continue
  # 写死 = runs-on 行不引用 vars. 且带具体 runner 值
  hits=$(grep -nE 'runs-on:' "$f" | grep -v 'vars\.' | grep -E 'ubuntu-latest|windows-latest|macos-|\[[[:space:]]*self-hosted' || true)
  if [ -n "$hits" ]; then
    echo "❌ ADR 0006: $f 有写死的 runs-on（应走 \${{ vars.CI_RUNNER && fromJSON(vars.CI_RUNNER) || 'ubuntu-latest' }}）:"
    echo "$hits" | sed 's/^/    /'
    bad=1
  fi
done <<EOF
$FILES
EOF
exit $bad
