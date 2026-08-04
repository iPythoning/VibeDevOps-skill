#!/usr/bin/env bash
# reverify.sh — 补验欠账：构建机恢复后，自动重跑本机兜底(LOCAL)通过的门禁
#
# 为什么：build-gate.sh 在构建机不可达时降级 LOCAL 兜底，证据强度最弱。
# LOCAL 通过 ≠ 结案，只是欠账。销账主路径已内嵌在 build-gate.sh 启动时（机会式：
# 构建越勤销得越快，机器睡眠也不影响）；本脚本供手动跑或额外挂 cron 加速销账。
# 构建机可达时，把队列里每个仓库用 --force-builder 复跑一次门禁，通过即销账；
# 失败保留在队列，下次再试。
#
# 队列格式（${PENDING_QUEUE}，TSV 每行一条）：
#   timestamp <TAB> repo_path <TAB> project <TAB> sha <TAB> gate_command
#
# 可选加速（crontab -e；不装也不影响正确性）：
#   */15 * * * * /path/to/reverify.sh >> ~/.build-gate-reverify.log 2>&1
#
# 用法：reverify.sh        # 幂等，可随时手动跑

set -uo pipefail

BUILDER_SSH="${BUILDER_SSH:-}"
PENDING_QUEUE="${PENDING_QUEUE:-$HOME/.build-gate-pending.tsv}"
GATE="$(dirname "$0")/build-gate.sh"

[ -n "$BUILDER_SSH" ] || { echo "❌ 未配置 BUILDER_SSH，无法补验"; exit 1; }
[ -f "$PENDING_QUEUE" ] || exit 0
# 构建机不可达 → 原样退出，等下一个 cron 周期；不降级、不报错
ssh -o BatchMode=yes -o ConnectTimeout=8 "$BUILDER_SSH" true 2>/dev/null || exit 0

TMP="$(mktemp)"
while IFS=$'\t' read -r TS REPO PROJECT SHA CMD; do
  [ -n "$REPO" ] || continue
  if [ ! -d "$REPO/.git" ]; then
    echo "✗ 丢弃 ${PROJECT}：仓库 $REPO 已不存在"
    continue
  fi
  HEAD="$(git -C "$REPO" rev-parse HEAD)"
  # HEAD 已前进（旧 sha 是祖先）→ 验当前 HEAD 即覆盖欠账；旧 sha 不在当前历史 → 记录作废
  if [ "$HEAD" != "$SHA" ] && ! git -C "$REPO" merge-base --is-ancestor "$SHA" "$HEAD" 2>/dev/null; then
    echo "✗ 丢弃 ${PROJECT}：欠账 sha ${SHA:0:8} 不在当前历史（可能 reset/rebase 过）"
    continue
  fi
  echo "▶ 补验 $PROJECT @ ${HEAD:0:8}（欠账于 ${TS}，当时 sha ${SHA:0:8}）"
  if "$GATE" "$REPO" --cmd "$CMD" --force-builder; then
    echo "  ✅ 复验通过，销账"
  else
    echo "  ❌ 复验失败，保留在队列 —— 该 commit 仍未获得强证据，禁止发布"
    printf '%s\t%s\t%s\t%s\t%s\n' "$TS" "$REPO" "$PROJECT" "$SHA" "$CMD" >> "$TMP"
  fi
done < "$PENDING_QUEUE"

mv "$TMP" "$PENDING_QUEUE"
[ -s "$PENDING_QUEUE" ] || rm -f "$PENDING_QUEUE"
