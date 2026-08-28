#!/usr/bin/env bash
# ADR 0009 §2：跳过不是通过。禁止 `npm run X --if-present`——脚本缺失时它静默成功，
# 与「拒绝」在界面上都是绿的。改为显式判定：有脚本真跑真红，没有就 ::notice 明说跳过。
set -u
hits=$(grep -rnE 'npm run [A-Za-z0-9:_-]+ --if-present' skills/vibedevops/templates --include='*.yml' 2>/dev/null || true)
if [ -n "$hits" ]; then
  echo "❌ ADR 0009 §2: --if-present 静默跳过反模式:"
  echo "$hits" | sed 's/^/    /'
  exit 1
fi
exit 0
