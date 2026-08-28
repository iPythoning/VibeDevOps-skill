#!/usr/bin/env bash
# ADR 0009 §1：拦截型密钥扫描门禁必须每次先自证（金丝雀）——扫不出随机假凭据即失败。
# 每个含 gitleaks / infisical scan / trufflehog 步骤的 workflow，同文件里必须有金丝雀步骤。
set -u
bad=0
SCANNERS=$(grep -rlE 'gitleaks|infisical scan|trufflehog' skills/vibedevops/templates --include='*.yml' 2>/dev/null; ls .github/workflows/*.yml 2>/dev/null | xargs grep -lE 'gitleaks|infisical scan|trufflehog' 2>/dev/null)
for f in $(echo "$SCANNERS" | sort -u); do
  [ -f "$f" ] || continue
  if grep -qiE 'canary|self-proof|金丝雀' "$f"; then
    :
  else
    echo "❌ ADR 0009 §1: $f 有密钥扫描但无金丝雀自证（一道从未失败过的门禁与不存在的门禁无法区分）"
    bad=1
  fi
done
exit $bad
