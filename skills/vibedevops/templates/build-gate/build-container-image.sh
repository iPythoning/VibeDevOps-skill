#!/usr/bin/env bash

set -euo pipefail

DOCKER_BIN="${VIBEDEVOPS_DOCKER_BIN:-docker}"
PLATFORM="linux/amd64"
NETWORK_MODE=""
CONTEXT="."
TAG=""
TIMEOUT_SECONDS=150
KILL_GRACE_SECONDS="${VIBEDEVOPS_BUILD_KILL_GRACE_SECONDS:-5}"
BUILD_ROUTES=""
OUTPUT_TAR=""
ACTIVE_OUTPUT_TMP=""
ALLOW_DIRTY=0
ACTIVE_BUILD_PID=""
ACTIVE_WATCHDOG_PID=""
ACTIVE_TIMEOUT_DIR=""
ACTIVE_TIMEOUT_MARKER=""
DEFAULT_DIGEST="sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag) TAG="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --network) NETWORK_MODE="$2"; shift 2 ;;
        --context) CONTEXT="$2"; shift 2 ;;
        --timeout-seconds) TIMEOUT_SECONDS="$2"; shift 2 ;;
        --output-tar) OUTPUT_TAR="$2"; shift 2 ;;
        --allow-dirty) ALLOW_DIRTY=1; shift ;;
        --route)
            route="$2|$3"
            if [ -z "$BUILD_ROUTES" ]; then BUILD_ROUTES="$route"; else BUILD_ROUTES="$BUILD_ROUTES
$route"; fi
            shift 3
            ;;
        -h|--help)
            echo "Usage: $0 --tag IMAGE [--platform linux/amd64] [--network host|default|none] [--context .] [--timeout-seconds 150] [--output-tar FILE] [--route BASE_IMAGE APK_REPOSITORY ...] [--allow-dirty]"
            exit 0
            ;;
        *) echo "❌ 未知参数: $1" >&2; exit 1 ;;
    esac
done

[ -n "$TAG" ] || { echo "❌ 必须提供 --tag" >&2; exit 1; }
[ -d "$CONTEXT" ] || { echo "❌ 构建上下文不存在: $CONTEXT" >&2; exit 1; }
case "$TIMEOUT_SECONDS" in ''|*[!0-9]*) echo "❌ timeout-seconds 必须是正整数" >&2; exit 1 ;; esac
[ "$TIMEOUT_SECONDS" -gt 0 ] || { echo "❌ timeout-seconds 必须大于 0" >&2; exit 1; }
case "$KILL_GRACE_SECONDS" in ''|*[!0-9]*) echo "❌ kill grace 必须是正整数" >&2; exit 1 ;; esac
[ "$KILL_GRACE_SECONDS" -gt 0 ] || { echo "❌ kill grace 必须大于 0" >&2; exit 1; }
case "$NETWORK_MODE" in ''|host|default|none) ;; *) echo "❌ network 必须是 host、default 或 none" >&2; exit 1 ;; esac
command -v "$DOCKER_BIN" >/dev/null 2>&1 || { echo "❌ 找不到 Docker CLI: $DOCKER_BIN" >&2; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "❌ 找不到 Perl，无法为构建创建独立进程组" >&2; exit 1; }
command -v ps >/dev/null 2>&1 || { echo "❌ 找不到 ps，无法清理构建进程组成员" >&2; exit 1; }
command -v mktemp >/dev/null 2>&1 || { echo "❌ 找不到 mktemp，无法安全协调构建超时" >&2; exit 1; }
"$DOCKER_BIN" buildx version >/dev/null

if git -C "$CONTEXT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ "$ALLOW_DIRTY" = "0" ] && [ -n "$(git -C "$CONTEXT" status --porcelain --untracked-files=normal)" ]; then
        echo "❌ 构建上下文不是干净 Git checkout；提交改动或显式使用 --allow-dirty" >&2
        exit 1
    fi
else
    [ "$ALLOW_DIRTY" = "1" ] || { echo "❌ 生产构建上下文必须是 Git checkout" >&2; exit 1; }
fi

if [ -z "$BUILD_ROUTES" ]; then
    BUILD_ROUTES="m.daocloud.io/docker.io/library/alpine:3.22@$DEFAULT_DIGEST|https://mirrors.aliyun.com/alpine
public.ecr.aws/docker/library/alpine:3.22@$DEFAULT_DIGEST|https://dl-cdn.alpinelinux.org/alpine"
fi

EXPECTED_DIGEST=""
while IFS='|' read -r base_image apk_repository; do
    [ -n "$base_image" ] || continue
    printf '%s\n' "$apk_repository" | grep -Eq '^https://[^[:space:]|]+/alpine$' || {
        echo "❌ APK repository 必须是以 /alpine 结尾的 HTTPS URL: $apk_repository" >&2
        exit 1
    }
    digest="${base_image##*@}"
    printf '%s\n' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || {
        echo "❌ 基础镜像必须固定 @sha256: $base_image" >&2
        exit 1
    }
    if [ -z "$EXPECTED_DIGEST" ]; then
        EXPECTED_DIGEST="$digest"
    elif [ "$digest" != "$EXPECTED_DIGEST" ]; then
        echo "❌ fallback 基础镜像 digest 不一致: $EXPECTED_DIGEST != $digest" >&2
        exit 1
    fi
done <<< "$BUILD_ROUTES"

VERSION_VALUE="dev"
[ ! -f "$CONTEXT/VERSION" ] || VERSION_VALUE="$(tr -d '[:space:]' < "$CONTEXT/VERSION")"
VCS_REF="${GITHUB_SHA:-unknown}"
if [ "$VCS_REF" = "unknown" ] && git -C "$CONTEXT" rev-parse --verify HEAD >/dev/null 2>&1; then
    VCS_REF="$(git -C "$CONTEXT" rev-parse HEAD)"
fi

signal_build_group() {
    local group_pid="$1" signal_name="$2" member_pid
    kill -"$signal_name" "-$group_pid" 2>/dev/null || true
    for member_pid in $(ps -axo pid=,pgid= | awk -v group="$group_pid" '$2 == group { print $1 }'); do
        kill -"$signal_name" "$member_pid" 2>/dev/null || true
    done
}

cleanup_active_build() {
    [ -z "$ACTIVE_WATCHDOG_PID" ] || kill "$ACTIVE_WATCHDOG_PID" 2>/dev/null || true
    if [ -n "$ACTIVE_BUILD_PID" ]; then
        signal_build_group "$ACTIVE_BUILD_PID" TERM
        sleep "$KILL_GRACE_SECONDS"
        signal_build_group "$ACTIVE_BUILD_PID" KILL
    fi
    [ -z "$ACTIVE_OUTPUT_TMP" ] || rm -f "$ACTIVE_OUTPUT_TMP"
    [ -z "$ACTIVE_TIMEOUT_MARKER" ] || rm -f "$ACTIVE_TIMEOUT_MARKER"
    [ -z "$ACTIVE_TIMEOUT_DIR" ] || rmdir "$ACTIVE_TIMEOUT_DIR" 2>/dev/null || true
}
trap cleanup_active_build EXIT
trap 'exit 130' INT TERM

run_build() {
    local base_image="$1" apk_repository="$2" build_pid watchdog_pid exit_code timeout_dir timeout_marker
    if [ -n "$NETWORK_MODE" ]; then
        set -- --network "$NETWORK_MODE"
    else
        set --
    fi
    perl -MPOSIX -e '
        my $sid = POSIX::setsid();
        die "setsid failed: $!" if $sid == -1;
        exec @ARGV or die "exec failed: $!";
    ' "$DOCKER_BIN" buildx build \
        --platform "$PLATFORM" \
        "$@" \
        --load \
        --build-arg "BASE_IMAGE=$base_image" \
        --build-arg "APK_REPOSITORY=$apk_repository" \
        --build-arg "VERSION=$VERSION_VALUE" \
        --build-arg "VCS_REF=$VCS_REF" \
        --tag "$TAG" \
        "$CONTEXT" &
    build_pid=$!
    ACTIVE_BUILD_PID="$build_pid"
    timeout_dir="$(mktemp -d "${TMPDIR:-/tmp}/vibedevops-build-timeout.XXXXXX")"
    timeout_marker="$timeout_dir/fired"
    ACTIVE_TIMEOUT_DIR="$timeout_dir"
    ACTIVE_TIMEOUT_MARKER="$timeout_marker"
    (
        sleep "$TIMEOUT_SECONDS"
        if kill -0 "$build_pid" 2>/dev/null; then
            : > "$timeout_marker"
            echo "⚠️  构建路径超时 ${TIMEOUT_SECONDS}s: base=$base_image apk=$apk_repository" >&2
            signal_build_group "$build_pid" TERM
            sleep "$KILL_GRACE_SECONDS"
            signal_build_group "$build_pid" KILL
        fi
    ) &
    watchdog_pid=$!
    ACTIVE_WATCHDOG_PID="$watchdog_pid"

    set +e
    wait "$build_pid"
    exit_code=$?
    set -e
    if [ ! -f "$timeout_marker" ]; then
        kill "$watchdog_pid" 2>/dev/null || true
    fi
    wait "$watchdog_pid" 2>/dev/null || true
    rm -f "$timeout_marker"
    rmdir "$timeout_dir" 2>/dev/null || true
    ACTIVE_BUILD_PID=""
    ACTIVE_WATCHDOG_PID=""
    ACTIVE_TIMEOUT_DIR=""
    ACTIVE_TIMEOUT_MARKER=""
    return "$exit_code"
}

while IFS='|' read -r base_image apk_repository; do
    [ -n "$base_image" ] || continue
    echo "➡️  尝试构建路径: base=$base_image apk=$apk_repository"
    if run_build "$base_image" "$apk_repository"; then
        "$DOCKER_BIN" image inspect "$TAG" >/dev/null
        if [ -n "$OUTPUT_TAR" ]; then
            [ ! -d "$OUTPUT_TAR" ] || { echo "❌ output-tar 不能是目录: $OUTPUT_TAR" >&2; exit 1; }
            [ ! -L "$OUTPUT_TAR" ] || { echo "❌ output-tar 不能是软链: $OUTPUT_TAR" >&2; exit 1; }
            output_tmp="$OUTPUT_TAR.tmp.$$"
            rm -f "$output_tmp"
            ACTIVE_OUTPUT_TMP="$output_tmp"
            "$DOCKER_BIN" image save --output "$output_tmp" "$TAG"
            mv "$output_tmp" "$OUTPUT_TAR"
            ACTIVE_OUTPUT_TMP=""
        fi
        echo "✅ 镜像构建完成: $TAG base=$base_image apk=$apk_repository platform=$PLATFORM"
        exit 0
    fi
    echo "⚠️  构建路径失败，切换下一镜像源: $base_image" >&2
done <<< "$BUILD_ROUTES"

echo "❌ 所有基础镜像路径均构建失败" >&2
exit 1
