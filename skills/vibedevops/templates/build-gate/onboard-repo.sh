#!/bin/bash
# onboard-repo —— 新仓立即接入自建 CI 车道（即时通道，ADR 0010）。
#
# 薄 wrapper：ssh 到构建机以单仓模式跑 onboard-reconcile——与 30 分钟一轮的
# 全量对账共用同一份实现，两个入口永不漂移。建仓后跑这个 = 立即接入；
# 忘了跑 = 对账循环最迟一个周期后自动接入。
#
# 用法：onboard-repo.sh <owner/repo>
# 环境：ONBOARD_BUILDER_SSH（构建机 ssh 别名，默认 xserver）
set -euo pipefail

REPO_FULL="${1:?usage: onboard-repo.sh <owner/repo>}"
case "$REPO_FULL" in */*) ;; *) echo "repo 必须是 owner/repo" >&2; exit 1;; esac
REPO_NAME="${REPO_FULL#*/}"
BUILDER="${ONBOARD_BUILDER_SSH:-xserver}"

ssh -o ConnectTimeout=15 "$BUILDER" \
  "ONBOARD_ONLY_REPO='$REPO_NAME' /usr/local/sbin/onboard-reconcile" \
  || { echo "构建机不可达或接入失败——对账循环会在下一周期自动重试" >&2; exit 1; }
echo "✅ $REPO_FULL 已接入自建车道（runner + 路由变量）"
