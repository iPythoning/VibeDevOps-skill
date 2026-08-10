#!/bin/bash

set -e

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GHCR_CLEANUP="$ROOT/skills/vibedevops/templates/image-lifecycle/cleanup-ghcr-versions.sh"
DOCKER_CLEANUP="$ROOT/skills/vibedevops/templates/image-lifecycle/cleanup-docker-images.sh"
INSTALL_GUARD="$ROOT/skills/vibedevops/templates/image-lifecycle/install-local-guard.sh"
DEPLOY_WORKFLOW="$ROOT/skills/vibedevops/templates/ci/deploy.yml"
FIXTURE="$(mktemp -d)"
trap 'code=$?; [ "$code" -eq 0 ] || echo "image lifecycle fixture failed near line $LINENO" >&2; rm -rf "$FIXTURE"' EXIT

cat > "$FIXTURE/versions.json" <<'EOF'
[
  {"id":8,"name":"sha256:new","created_at":"2099-01-01T00:00:00Z","metadata":{"container":{"tags":["sha-new"]}}},
  {"id":7,"name":"sha256:production","created_at":"2020-01-07T00:00:00Z","metadata":{"container":{"tags":["production"]}}},
  {"id":6,"name":"sha256:child-tagged","created_at":"2020-01-06T00:00:00Z","metadata":{"container":{"tags":["arch-amd64"]}}},
  {"id":5,"name":"sha256:child-untagged","created_at":"2020-01-05T00:00:00Z","metadata":{"container":{"tags":[]}}},
  {"id":4,"name":"sha256:attestation","created_at":"2020-01-04T12:00:00Z","metadata":{"container":{"tags":["sbom"]}}},
  {"id":3,"name":"sha256:rollback","created_at":"2020-01-04T00:00:00Z","metadata":{"container":{"tags":["rollback"]}}},
  {"id":2,"name":"sha256:old-tagged","created_at":"2020-01-03T00:00:00Z","metadata":{"container":{"tags":["sha-old"]}}},
  {"id":1,"name":"sha256:old-untagged","created_at":"2020-01-02T00:00:00Z","metadata":{"container":{"tags":[]}}}
]
EOF

cat > "$FIXTURE/manifests.json" <<'EOF'
[
  {"digest":"sha256:new","manifest":{}},
  {"digest":"sha256:production","manifest":{"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"digest":"sha256:child-tagged"},{"digest":"sha256:child-untagged"}]}},
  {"digest":"sha256:child-tagged","manifest":{}},
  {"digest":"sha256:child-untagged","manifest":{}},
  {"digest":"sha256:attestation","manifest":{"mediaType":"application/vnd.oci.image.manifest.v1+json","subject":{"digest":"sha256:production"}}},
  {"digest":"sha256:rollback","manifest":{}},
  {"digest":"sha256:old-tagged","manifest":{}},
  {"digest":"sha256:old-untagged","manifest":{}}
]
EOF

cat > "$FIXTURE/gh" <<'EOF'
#!/bin/sh
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
    echo tester
    exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "--method" ] && [ "$3" = "DELETE" ]; then
    printf '%s\n' "$4" >> "$VIBEDEVOPS_DELETE_LOG"
    exit 0
fi
exit 1
EOF
chmod +x "$FIXTURE/gh"
: > "$FIXTURE/deletes"
VIBEDEVOPS_GH_BIN="$FIXTURE/gh" VIBEDEVOPS_GHCR_VERSIONS_FILE="$FIXTURE/versions.json" VIBEDEVOPS_GHCR_MANIFESTS_FILE="$FIXTURE/manifests.json" VIBEDEVOPS_DELETE_LOG="$FIXTURE/deletes" \
    "$GHCR_CLEANUP" --owner tester --package app --keep-count 2 --min-age-hours 1 > "$FIXTURE/ghcr-dry-run"
grep -q 'candidates=2' "$FIXTURE/ghcr-dry-run"
grep -q 'id=2' "$FIXTURE/ghcr-dry-run"
grep -q 'id=1' "$FIXTURE/ghcr-dry-run"
! grep -q 'id=3' "$FIXTURE/ghcr-dry-run"
! grep -q 'id=4' "$FIXTURE/ghcr-dry-run"
! grep -q 'id=5' "$FIXTURE/ghcr-dry-run"
! grep -q 'id=6' "$FIXTURE/ghcr-dry-run"

VIBEDEVOPS_GH_BIN="$FIXTURE/gh" VIBEDEVOPS_GHCR_VERSIONS_FILE="$FIXTURE/versions.json" VIBEDEVOPS_GHCR_MANIFESTS_FILE="$FIXTURE/manifests.json" VIBEDEVOPS_DELETE_LOG="$FIXTURE/deletes" \
    "$GHCR_CLEANUP" --owner tester --package app --keep-count 2 --min-age-hours 1 --apply >/dev/null
[ "$(wc -l < "$FIXTURE/deletes" | tr -d ' ')" = 2 ]

cat > "$FIXTURE/incomplete-manifests.json" <<'EOF'
[
  {"digest":"sha256:new","manifest":{}},
  {"digest":"sha256:production","manifest":{}}
]
EOF
VIBEDEVOPS_GH_BIN="$FIXTURE/gh" VIBEDEVOPS_GHCR_VERSIONS_FILE="$FIXTURE/versions.json" VIBEDEVOPS_GHCR_MANIFESTS_FILE="$FIXTURE/incomplete-manifests.json" VIBEDEVOPS_DELETE_LOG="$FIXTURE/deletes" \
    "$GHCR_CLEANUP" --owner tester --package app --keep-count 2 --min-age-hours 1 > "$FIXTURE/ghcr-incomplete"
grep -q 'candidates=0' "$FIXTURE/ghcr-incomplete"

grep -q 'cleanup-images --retry-pending' "$DEPLOY_WORKFLOW"
grep -q 'image-capacity-check --max-disk-percent 85 --max-cleanup-debt 0' "$DEPLOY_WORKFLOW"
grep -q '^  build_xserver:' "$DEPLOY_WORKFLOW"
grep -q '^  build_mac:' "$DEPLOY_WORKFLOW"
grep -q '^  push_github:' "$DEPLOY_WORKFLOW"
grep -q '^  push_xserver:' "$DEPLOY_WORKFLOW"
grep -q 'VIBEDEVOPS_RUNNER_READ_TOKEN' "$DEPLOY_WORKFLOW"
grep -q 'STARTED_AT + 1800' "$DEPLOY_WORKFLOW"
grep -q '^  deadline_watchdog:' "$DEPLOY_WORKFLOW"
grep -q 'force-cancel' "$DEPLOY_WORKFLOW"
grep -q 'complete-deployment.*--deadline-epoch' "$DEPLOY_WORKFLOW"
grep -q 'imagetools create --tag "$IMAGE:rollback" "$LAST_KNOWN_GOOD"' "$DEPLOY_WORKFLOW"
grep -q 'imagetools create --tag "$IMAGE:production" "$CURRENT_ARTIFACT"' "$DEPLOY_WORKFLOW"

cat > "$FIXTURE/images.json" <<'EOF'
[
  {"Id":"sha256:used","Created":"2020-01-01T00:00:00Z","RepoTags":["app:used"]},
  {"Id":"sha256:new","Created":"2099-01-01T00:00:00Z","RepoTags":["app:new","app:production"]},
  {"Id":"sha256:keep","Created":"2020-01-03T00:00:00Z","RepoTags":["app:keep"]},
  {"Id":"sha256:old","Created":"2020-01-02T00:00:00Z","RepoTags":["app:old"]},
  {"Id":"sha256:dangling","Created":"2020-01-01T00:00:00Z","RepoTags":null}
]
EOF
cat > "$FIXTURE/docker" <<'EOF'
#!/bin/sh
case "$1:$2" in
    info:) exit 0 ;;
    image:ls) printf '%s\n' sha256:used sha256:new sha256:keep sha256:old sha256:dangling ;;
    image:inspect) cat "$VIBEDEVOPS_IMAGES_JSON" ;;
    image:rm) shift 2; printf 'rm %s\n' "$*" >> "$VIBEDEVOPS_DOCKER_LOG" ;;
    ps:*)
        case "$*" in *status=exited*) ;; *) echo container-one ;; esac
        ;;
    inspect:--format) echo sha256:used ;;
    builder:prune) printf 'builder-prune\n' >> "$VIBEDEVOPS_DOCKER_LOG" ;;
    system:df) echo 'fixture system df' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$FIXTURE/docker"
: > "$FIXTURE/docker-log"
VIBEDEVOPS_DOCKER_BIN="$FIXTURE/docker" VIBEDEVOPS_IMAGES_JSON="$FIXTURE/images.json" VIBEDEVOPS_DOCKER_LOG="$FIXTURE/docker-log" \
    "$DOCKER_CLEANUP" --apply --retention-hours 24 --keep-per-repository 2 --prune-build-cache >/dev/null
grep -q 'app:old' "$FIXTURE/docker-log"
grep -q 'sha256:dangling' "$FIXTURE/docker-log"
grep -q 'builder-prune' "$FIXTURE/docker-log"
! grep -q 'app:used\|app:new\|app:keep' "$FIXTURE/docker-log"

mkdir -p "$FIXTURE/guard-tools" "$FIXTURE/guard-home"
cat > "$FIXTURE/guard-tools/launchctl" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FIXTURE/guard-tools/launchctl"
HOME="$FIXTURE/guard-home" PATH="$FIXTURE/guard-tools:$PATH" VIBEDEVOPS_IMAGE_GUARD_OS=Darwin \
    "$INSTALL_GUARD" --retention-hours 24 --keep-per-repository 2 >/dev/null
GUARD_PLIST="$FIXTURE/guard-home/Library/LaunchAgents/dev.vibedevops.image-cleanup.plist"
plutil -lint "$GUARD_PLIST" >/dev/null
grep -q '<string>24</string>' "$GUARD_PLIST"
grep -q '<string>2</string>' "$GUARD_PLIST"
grep -q '<key>EnvironmentVariables</key>' "$GUARD_PLIST"

echo "image lifecycle fixtures passed"
