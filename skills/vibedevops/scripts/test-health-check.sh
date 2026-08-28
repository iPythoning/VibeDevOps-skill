#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HEALTH_CHECK="$SCRIPT_DIR/health-check.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

ci_score() {
  "$HEALTH_CHECK" --json "$1" | sed -n 's/.*CI：\([0-9][0-9]*\)\/15.*/\1/p'
}

init_repo() {
  local repo="$1"
  mkdir -p "$repo/.github/workflows"
  git -C "$repo" init -q
}

GOOD="$TMP_ROOT/good"
init_repo "$GOOD"
cp "$SCRIPT_DIR/../templates/ci/pr-check.yml" "$GOOD/.github/workflows/pr-check.yml"
cp "$SCRIPT_DIR/../templates/ci/deploy.yml" "$GOOD/.github/workflows/deploy.yml"
git -C "$GOOD" add .github
[ "$(ci_score "$GOOD")" = 15 ] || { echo "expected best-practice workflows to score 15/15"; exit 1; }

COMMENTS_ONLY="$TMP_ROOT/comments-only"
init_repo "$COMMENTS_ONLY"
cat > "$COMMENTS_ONLY/.github/workflows/manual.yml" <<'YAML'
name: Manual
on: workflow_dispatch
# pull_request:
# push:
#   branches: [main]
# run: ./deploy.sh deploy image
# run: ./scripts/smoke-test.sh
# if: failure()
# run: ./deploy.sh rollback old
env:
  FAKE_WORKFLOW: |
    pull_request:
    push:
      branches: [main]
    run: ./deploy.sh deploy image
    run: ./scripts/smoke-test.sh
    if: failure()
    run: ./deploy.sh rollback old
jobs:
  manual:
    runs-on: ubuntu-latest
    steps:
      - run: echo manual
YAML
git -C "$COMMENTS_ONLY" add .github
[ "$(ci_score "$COMMENTS_ONLY")" = 0 ] || { echo "comments-only workflow must score 0/15"; exit 1; }

NO_ROLLBACK="$TMP_ROOT/no-rollback"
init_repo "$NO_ROLLBACK"
cp "$SCRIPT_DIR/../templates/ci/pr-check.yml" "$NO_ROLLBACK/.github/workflows/pr-check.yml"
cat > "$NO_ROLLBACK/.github/workflows/deploy.yml" <<'YAML'
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh deploy image
      - run: ./scripts/smoke-test.sh
YAML
git -C "$NO_ROLLBACK" add .github
[ "$(ci_score "$NO_ROLLBACK")" = 12 ] || { echo "auto deploy without rollback must score 12/15"; exit 1; }

IGNORES_MAIN="$TMP_ROOT/ignores-main"
init_repo "$IGNORES_MAIN"
cp "$SCRIPT_DIR/../templates/ci/pr-check.yml" "$IGNORES_MAIN/.github/workflows/pr-check.yml"
cat > "$IGNORES_MAIN/.github/workflows/deploy.yml" <<'YAML'
name: Deploy except main
on:
  push:
    branches-ignore: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh deploy image
      - run: ./scripts/smoke-test.sh
  rollback:
    needs: deploy
    if: failure()
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh rollback old
YAML
git -C "$IGNORES_MAIN" add .github
[ "$(ci_score "$IGNORES_MAIN")" = 8 ] || { echo "workflow excluding main must score only PR checks (8/15)"; exit 1; }

UNREACHABLE="$TMP_ROOT/unreachable-rollback"
init_repo "$UNREACHABLE"
cp "$SCRIPT_DIR/../templates/ci/pr-check.yml" "$UNREACHABLE/.github/workflows/pr-check.yml"
cat > "$UNREACHABLE/.github/workflows/deploy.yml" <<'YAML'
name: Unreachable rollback
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh deploy image
      - run: ./scripts/smoke-test.sh
  rollback:
    needs: deploy
    if: false
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh rollback old
YAML
git -C "$UNREACHABLE" add .github
[ "$(ci_score "$UNREACHABLE")" = 12 ] || { echo "statically unreachable rollback must not earn safety points"; exit 1; }

STEP_GUARD="$TMP_ROOT/step-only-rollback-guard"
init_repo "$STEP_GUARD"
cp "$SCRIPT_DIR/../templates/ci/pr-check.yml" "$STEP_GUARD/.github/workflows/pr-check.yml"
cat > "$STEP_GUARD/.github/workflows/deploy.yml" <<'YAML'
name: Step-only rollback guard
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh deploy image
      - run: ./scripts/smoke-test.sh
  rollback:
    needs: deploy
    runs-on: ubuntu-latest
    steps:
      - if: failure()
        run: ./deploy.sh rollback old
YAML
git -C "$STEP_GUARD" add .github
[ "$(ci_score "$STEP_GUARD")" = 12 ] || { echo "step-only rollback guard must not earn safety points"; exit 1; }

# ── 哨兵提取健壮性：ruby 往 stdout 打杂散行时，CI 判据不得被污染成假 0/15 ──
# 复现曾致 main CI 假红的失败类（identical files 同环境时好时坏）：消费方必须按哨兵前缀提取。
REAL_RUBY="$(command -v ruby || true)"
if [ -n "$REAL_RUBY" ]; then
  WRAP="$TMP_ROOT/ruby-wrap"; mkdir -p "$WRAP"
  { printf '#!/bin/sh\n'; printf 'echo "warning: stray line on stdout"\n'; printf 'exec %q "$@"\n' "$REAL_RUBY"; } > "$WRAP/ruby"
  chmod +x "$WRAP/ruby"
  polluted="$(PATH="$WRAP:$PATH" ci_score "$GOOD")"
  [ "$polluted" = 15 ] || { echo "ruby 杂散 stdout 污染了 CI 判据（哨兵提取失效），得 ${polluted:-空}/15 期望 15"; exit 1; }
fi

echo "health-check CI/CD fixtures passed"
