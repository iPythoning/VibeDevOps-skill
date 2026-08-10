#!/bin/bash

set -e
umask 077

APPLY=0
RETENTION_HOURS=168
KEEP_PER_REPOSITORY=5
PROTECTED_FILE=""
PRUNE_BUILD_CACHE=0
DOCKER_BIN="${VIBEDEVOPS_DOCKER_BIN:-docker}"

fail() {
    echo "❌ $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: cleanup-docker-images.sh [options]

默认只预览；删除必须显式传 --apply。脚本永不强制删除 image，所有容器引用的镜像永久保护；builder prune 的 --force 只关闭交互确认，仍只处理未使用 cache。

Options:
  --retention-hours N       只处理至少 N 小时前的镜像（默认 168）
  --keep-per-repository N   每个 repository 无条件保留最新 N 个镜像（默认 5）
  --protected-file PATH     每行一个额外保护的 image ref/digest
  --prune-build-cache       同时清理过期且未使用的 build cache
  --apply                   执行删除
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --retention-hours) RETENTION_HOURS=$2; shift 2 ;;
        --keep-per-repository) KEEP_PER_REPOSITORY=$2; shift 2 ;;
        --protected-file) PROTECTED_FILE=$2; shift 2 ;;
        --prune-build-cache) PRUNE_BUILD_CACHE=1; shift ;;
        --apply) APPLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "未知参数: $1" ;;
    esac
done

case "$RETENTION_HOURS" in ''|*[!0-9]*) fail "retention-hours 必须是整数" ;; esac
case "$KEEP_PER_REPOSITORY" in ''|*[!0-9]*) fail "keep-per-repository 必须是整数" ;; esac
[ "$RETENTION_HOURS" -ge 24 ] || fail "retention-hours 至少为 24"
[ "$KEEP_PER_REPOSITORY" -ge 2 ] || fail "keep-per-repository 至少为 2，必须保留回滚余量"
[ -z "$PROTECTED_FILE" ] || [ -f "$PROTECTED_FILE" ] || fail "protected file 不存在: $PROTECTED_FILE"
command -v "$DOCKER_BIN" >/dev/null 2>&1 || fail "未找到 docker CLI"
if command -v node >/dev/null 2>&1; then
    JSON_RUNTIME=node
elif command -v python3 >/dev/null 2>&1; then
    JSON_RUNTIME=python3
else
    fail "需要 Node.js 或 Python 3 解析 docker inspect"
fi

if ! "$DOCKER_BIN" info >/dev/null 2>&1; then
    echo "ℹ️  Docker daemon 未运行，本次无需清理"
    exit 0
fi

WORK_DIR="$(mktemp -d)"
cleanup_work() {
    rm -rf "$WORK_DIR"
}
trap cleanup_work EXIT HUP INT TERM

image_ids="$($DOCKER_BIN image ls --no-trunc --quiet | sort -u)"
if [ -z "$image_ids" ]; then
    echo "✅ 本机没有 Docker 镜像"
    exit 0
fi

# shellcheck disable=SC2086
$DOCKER_BIN image inspect $image_ids > "$WORK_DIR/images.json"
container_ids="$($DOCKER_BIN ps --all --quiet)"
if [ -n "$container_ids" ]; then
    # shellcheck disable=SC2086
    $DOCKER_BIN inspect --format '{{.Image}}' $container_ids | sort -u > "$WORK_DIR/container-image-ids"
else
    : > "$WORK_DIR/container-image-ids"
fi

: > "$WORK_DIR/extra-protected-ids"
if [ -n "$PROTECTED_FILE" ]; then
    while IFS= read -r image_ref; do
        [ -n "$image_ref" ] || continue
        "$DOCKER_BIN" image inspect --format '{{.Id}}' "$image_ref" >> "$WORK_DIR/extra-protected-ids" 2>/dev/null || fail "受保护镜像不存在: $image_ref"
    done < "$PROTECTED_FILE"
    sort -u "$WORK_DIR/extra-protected-ids" -o "$WORK_DIR/extra-protected-ids"
fi

if [ "$JSON_RUNTIME" = "node" ]; then
    node -e '
const fs = require("fs");
const images = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const keep = Number(process.argv[2]);
const cutoff = Date.now() - Number(process.argv[3]) * 3600_000;
const protectedIds = new Set([
  ...fs.readFileSync(process.argv[4], "utf8").split(/\r?\n/),
  ...fs.readFileSync(process.argv[5], "utf8").split(/\r?\n/),
].filter(Boolean));
const repositoryImages = new Map();
for (const image of images) {
  for (const tag of image.RepoTags || []) {
    const repository = tag.replace(/:[^/:]+$/, "");
    if (!repositoryImages.has(repository)) repositoryImages.set(repository, new Map());
    repositoryImages.get(repository).set(image.Id, image);
  }
}
for (const imagesById of repositoryImages.values()) {
  const group = [...imagesById.values()];
  group.sort((a, b) => Date.parse(b.Created) - Date.parse(a.Created));
  for (const image of group.slice(0, keep)) protectedIds.add(image.Id);
}
for (const image of images) {
  if (protectedIds.has(image.Id) || Date.parse(image.Created) > cutoff) continue;
  process.stdout.write([image.Id, (image.RepoTags || []).join(",") || "-", image.Created].join("\t") + "\n");
}
' "$WORK_DIR/images.json" "$KEEP_PER_REPOSITORY" "$RETENTION_HOURS" "$WORK_DIR/container-image-ids" "$WORK_DIR/extra-protected-ids" > "$WORK_DIR/candidates"
else
    python3 -c '
import datetime, json, pathlib, sys, time

images = json.loads(pathlib.Path(sys.argv[1]).read_text())
keep = int(sys.argv[2])
cutoff = time.time() - int(sys.argv[3]) * 3600
protected = set(filter(None, pathlib.Path(sys.argv[4]).read_text().splitlines()))
protected.update(filter(None, pathlib.Path(sys.argv[5]).read_text().splitlines()))

def created(image):
    return datetime.datetime.fromisoformat(image["Created"].replace("Z", "+00:00")).timestamp()

repositories = {}
for image in images:
    for tag in image.get("RepoTags") or []:
        repository = tag.rsplit(":", 1)[0]
        repositories.setdefault(repository, {})[image["Id"]] = image
for images_by_id in repositories.values():
    group = list(images_by_id.values())
    group.sort(key=created, reverse=True)
    protected.update(image["Id"] for image in group[:keep])
for image in images:
    if image["Id"] in protected or created(image) > cutoff:
        continue
    tags = ",".join(image.get("RepoTags") or []) or "-"
    print("\t".join((image["Id"], tags, image["Created"])))
' "$WORK_DIR/images.json" "$KEEP_PER_REPOSITORY" "$RETENTION_HOURS" "$WORK_DIR/container-image-ids" "$WORK_DIR/extra-protected-ids" > "$WORK_DIR/candidates"
fi

candidate_count="$(wc -l < "$WORK_DIR/candidates" | tr -d ' ')"
deleted_count=0
skipped_count=0
while IFS="$(printf '\t')" read -r image_id repo_tags created_at; do
    [ -n "$image_id" ] || continue
    if [ "$APPLY" = "1" ]; then
        if [ "$repo_tags" != "-" ]; then
            old_ifs=$IFS
            IFS=','
            # shellcheck disable=SC2086
            if $DOCKER_BIN image rm $repo_tags; then
                removed=1
            else
                removed=0
            fi
            IFS=$old_ifs
        else
            if $DOCKER_BIN image rm "$image_id"; then removed=1; else removed=0; fi
        fi
        if [ "$removed" = "1" ]; then
            deleted_count=$((deleted_count + 1))
            echo "  deleted id=$image_id created=$created_at tags=$repo_tags"
        else
            skipped_count=$((skipped_count + 1))
            echo "  skipped-in-use-or-dependent id=$image_id tags=$repo_tags" >&2
        fi
    else
        echo "  would-delete id=$image_id created=$created_at tags=$repo_tags"
    fi
done < "$WORK_DIR/candidates"

if [ "$PRUNE_BUILD_CACHE" = "1" ]; then
    if [ "$APPLY" = "1" ]; then
        "$DOCKER_BIN" builder prune --force --filter "until=${RETENTION_HOURS}h"
    else
        echo "  would-prune unused build cache older than ${RETENTION_HOURS}h"
    fi
fi

stopped_count="$($DOCKER_BIN ps --all --filter status=exited --quiet | wc -l | tr -d ' ')"
if [ "$APPLY" = "1" ]; then
    echo "✅ Docker 镜像清理完成：deleted=$deleted_count skipped=$skipped_count protected-by-containers=$(wc -l < "$WORK_DIR/container-image-ids" | tr -d ' ') stopped-containers=$stopped_count"
    "$DOCKER_BIN" system df
else
    echo "ℹ️  Docker dry-run：candidates=$candidate_count stopped-containers=$stopped_count；确认后加 --apply"
fi
