#!/usr/bin/env bash
# templates ↔ 运行体 漂移报告（ADR 0012 的跨仓部分）。
# 运行体在别的仓/机器（agents-toolchain=~/.agents、xserver-bootstrap=xserver），单仓 CI 够不着，
# 故本工具不进 CI，需要本地有对应克隆。它只「让漂移可见」——不强制同一（运行体有机器专属硬编码），
# 由人判断漂移是「有意的硬编码差异」还是「漏传播的逻辑改动」。上次三处手动同步的痛点即此。
# 用法：AGENTS_TOOLKIT_DIR=~/.agents XSERVER_BOOTSTRAP_DIR=/path/to/xserver-bootstrap \
#         ./skills/vibedevops/scripts/check-runtime-drift.sh
set -u
cd "$(dirname "$0")/../../.." || exit 2
MAN=docs/adr/runtime-drift-manifest.tsv
[ -f "$MAN" ] || { echo "缺 $MAN"; exit 2; }
shown=0; skipped=0
while IFS=$'\t' read -r tmpl envvar rel note; do
  case "$tmpl" in ''|\#*) continue;; esac
  base="${!envvar:-}"
  if [ -z "$base" ] || [ ! -e "$base/$rel" ]; then
    echo "○ 跳过 $rel（$envvar 未设或路径不存在）—— $note"
    skipped=$((skipped + 1)); continue
  fi
  shown=$((shown + 1))
  d=$(diff -u "$tmpl" "$base/$rel" 2>/dev/null || true)
  if [ -z "$d" ]; then
    echo "✓ $rel 与模板完全一致"
  else
    add=$(printf '%s\n' "$d" | grep -c '^+[^+]'); del=$(printf '%s\n' "$d" | grep -c '^-[^-]')
    echo "≠ $rel 漂移 +$add/-$del 行（$note）"
    echo "    模板:   $tmpl"
    echo "    运行体: $base/$rel"
    echo "    → 人工判断：机器专属硬编码差异，还是漏传播的逻辑改动？"
  fi
done < "$MAN"
echo "── 比对 $shown 对，跳过 $skipped 对（缺本地克隆）──"
exit 0
