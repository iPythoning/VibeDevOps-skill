#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD_SCRIPT="$ROOT/skills/vibedevops/templates/build-gate/build-container-image.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

assert_process_gone() {
    local pid="$1" label="$2"
    for attempt in $(seq 1 50); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.1
    done
    echo "$label" >&2
    exit 1
}

mkdir -p "$FIXTURE/context"
printf '%s\n' 1.1.1 > "$FIXTURE/context/VERSION"
git -C "$FIXTURE/context" init -q
git -C "$FIXTURE/context" add VERSION
git -C "$FIXTURE/context" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm init
cat > "$FIXTURE/docker" <<'EOF'
#!/bin/sh
if [ "$1:$2" = "buildx:version" ]; then
    exit 0
fi
if [ "$1:$2" = "buildx:build" ]; then
    printf '%s\n' "$*" >> "$VIBEDEVOPS_BUILD_LOG"
    case "$*" in
        *orphan.example*)
            (trap '' TERM; sleep 30) &
            [ -z "${VIBEDEVOPS_CHILD_PID_FILE:-}" ] || printf '%s\n' "$!" > "$VIBEDEVOPS_CHILD_PID_FILE"
            wait "$!"
            exit 1
            ;;
        *ignoreterm.example*)
            trap '' TERM
            sleep 30 &
            [ -z "${VIBEDEVOPS_CHILD_PID_FILE:-}" ] || printf '%s\n' "$!" > "$VIBEDEVOPS_CHILD_PID_FILE"
            wait "$!"
            exit 1
            ;;
        *m.daocloud.io*) exit 1 ;;
        *public.ecr.aws*) exit 0 ;;
    esac
fi
if [ "$1:$2" = "image:inspect" ]; then
    exit 0
fi
if [ "$1:$2" = "image:save" ]; then
    shift 2
    [ "$1" = "--output" ] || exit 1
    : > "$2"
    exit 0
fi
exit 1
EOF
chmod +x "$FIXTURE/docker"
: > "$FIXTURE/build.log"

VIBEDEVOPS_DOCKER_BIN="$FIXTURE/docker" VIBEDEVOPS_BUILD_LOG="$FIXTURE/build.log" \
    "$BUILD_SCRIPT" --tag fixture:test --context "$FIXTURE/context" --timeout-seconds 5 \
    --output-tar "$FIXTURE/image.tar" >/dev/null 2>&1

[ "$(wc -l < "$FIXTURE/build.log" | tr -d ' ')" = 2 ]
sed -n '1p' "$FIXTURE/build.log" | grep -q 'm.daocloud.io.*@sha256:'
sed -n '2p' "$FIXTURE/build.log" | grep -q 'public.ecr.aws.*@sha256:'
grep -q -- '--platform linux/amd64' "$FIXTURE/build.log"
grep -q -- '--build-arg VERSION=1.1.1' "$FIXTURE/build.log"
sed -n '1p' "$FIXTURE/build.log" | grep -q -- '--build-arg APK_REPOSITORY=https://mirrors.aliyun.com/alpine'
sed -n '2p' "$FIXTURE/build.log" | grep -q -- '--build-arg APK_REPOSITORY=https://dl-cdn.alpinelinux.org/alpine'
[ -f "$FIXTURE/image.tar" ]

: > "$FIXTURE/build.log"
VIBEDEVOPS_DOCKER_BIN="$FIXTURE/docker" VIBEDEVOPS_BUILD_LOG="$FIXTURE/build.log" \
    "$BUILD_SCRIPT" --tag fixture:network --context "$FIXTURE/context" --timeout-seconds 5 \
    --network host --route \
    "public.ecr.aws/docker/library/alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce" \
    "https://dl-cdn.alpinelinux.org/alpine" \
    >/dev/null 2>&1
grep -q -- '--network host' "$FIXTURE/build.log"

printf '%s\n' dirty > "$FIXTURE/context/dirty"
if VIBEDEVOPS_DOCKER_BIN="$FIXTURE/docker" VIBEDEVOPS_BUILD_LOG="$FIXTURE/build.log" \
    "$BUILD_SCRIPT" --tag fixture:dirty --context "$FIXTURE/context" --timeout-seconds 5 >/dev/null 2>&1; then
    echo "dirty Git context must be rejected" >&2
    exit 1
fi
rm "$FIXTURE/context/dirty"

digest_a="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
digest_b="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
if VIBEDEVOPS_DOCKER_BIN="$FIXTURE/docker" VIBEDEVOPS_BUILD_LOG="$FIXTURE/build.log" \
    "$BUILD_SCRIPT" --tag fixture:digest --context "$FIXTURE/context" \
    --route "m.daocloud.io/docker.io/library/alpine@$digest_a" "https://mirrors.aliyun.com/alpine" \
    --route "public.ecr.aws/docker/library/alpine@$digest_b" "https://dl-cdn.alpinelinux.org/alpine" \
    >/dev/null 2>&1; then
    echo "different fallback digests must be rejected" >&2
    exit 1
fi

timeout_start="$(date +%s)"
if VIBEDEVOPS_BUILD_KILL_GRACE_SECONDS=1 \
    VIBEDEVOPS_DOCKER_BIN="$FIXTURE/docker" \
    VIBEDEVOPS_BUILD_LOG="$FIXTURE/build.log" \
    VIBEDEVOPS_CHILD_PID_FILE="$FIXTURE/child.pid" \
    "$BUILD_SCRIPT" --tag fixture:timeout --context "$FIXTURE/context" \
    --timeout-seconds 1 \
    --route "ignoreterm.example/alpine@$digest_a" "https://mirrors.aliyun.com/alpine" \
    >/dev/null 2>&1; then
    echo "timed-out build must fail" >&2
    exit 1
fi
timeout_elapsed="$(( $(date +%s) - timeout_start ))"
[ "$timeout_elapsed" -le 6 ] || {
    echo "timed-out build was not force-killed: ${timeout_elapsed}s" >&2
    exit 1
}
[ -s "$FIXTURE/child.pid" ]
assert_process_gone "$(cat "$FIXTURE/child.pid")" "timed-out build left an orphan child"

rm -f "$FIXTURE/child.pid"
timeout_start="$(date +%s)"
if VIBEDEVOPS_BUILD_KILL_GRACE_SECONDS=1 \
    VIBEDEVOPS_DOCKER_BIN="$FIXTURE/docker" \
    VIBEDEVOPS_BUILD_LOG="$FIXTURE/build.log" \
    VIBEDEVOPS_CHILD_PID_FILE="$FIXTURE/child.pid" \
    "$BUILD_SCRIPT" --tag fixture:orphan --context "$FIXTURE/context" \
    --timeout-seconds 1 \
    --route "orphan.example/alpine@$digest_a" "https://mirrors.aliyun.com/alpine" \
    >/dev/null 2>&1; then
    echo "orphaning timed-out build must fail" >&2
    exit 1
fi
timeout_elapsed="$(( $(date +%s) - timeout_start ))"
[ "$timeout_elapsed" -le 6 ] || {
    echo "orphaning build was not force-killed: ${timeout_elapsed}s" >&2
    exit 1
}
[ -s "$FIXTURE/child.pid" ]
assert_process_gone "$(cat "$FIXTURE/child.pid")" "timed-out build left a child after its CLI exited"

echo "container build fallback fixtures passed"
