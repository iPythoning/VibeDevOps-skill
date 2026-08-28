#!/usr/bin/env bash
# ADR 0012：机械对账本身必须挂在 CI 上，不能被静默摘除——否则「有对账」和「没对账」无法区分
# （这是 ADR 0009「门禁必须自证」用在对账机制自己身上）。
set -u
grep -q 'check-adr-compliance.sh' .github/workflows/ci.yml \
  || { echo "❌ ADR 0012: check-adr-compliance.sh 未挂进 .github/workflows/ci.yml——对账没跑=没对账"; exit 1; }
exit 0
