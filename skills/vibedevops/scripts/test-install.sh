#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FIXTURE_HOME="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_HOME"' EXIT

mkdir -p \
    "$FIXTURE_HOME/.claude/skills" \
    "$FIXTURE_HOME/.agents/skills" \
    "$FIXTURE_HOME/.config/opencode/skills" \
    "$FIXTURE_HOME/.cc-switch/skills" \
    "$FIXTURE_HOME/.codex/skills" \
    "$FIXTURE_HOME/.cursor/skills" \
    "$FIXTURE_HOME/.gemini/skills" \
    "$FIXTURE_HOME/.qwen/skills" \
    "$FIXTURE_HOME/.windsurf/skills" \
    "$FIXTURE_HOME/Library/Application Support/kimi-desktop/daimon-share/daimon/skills"

printf '# Global rules\n\nPR 合并进 main 就是生产部署授权。\n' > "$FIXTURE_HOME/AGENTS.md"
mkdir -p "$FIXTURE_HOME/shared"
printf '# Claude-specific notes\n' > "$FIXTURE_HOME/shared/claude.md"
chmod 600 "$FIXTURE_HOME/shared/claude.md"
ln -s ../shared/claude.md "$FIXTURE_HOME/.claude/CLAUDE.md"
ln -s missing-gemini.md "$FIXTURE_HOME/.gemini/GEMINI.md"
mkdir -p "$FIXTURE_HOME/.codex/skills/vibedevops"
printf 'preserve me\n' > "$FIXTURE_HOME/.codex/skills/vibedevops/local.txt"

HOME="$FIXTURE_HOME" \
VIBEDEVOPS_REPO_DIR="$REPO_DIR" \
VIBEDEVOPS_SKIP_REPO_UPDATE=1 \
    "$REPO_DIR/install.sh" >/dev/null

# 第二次运行必须幂等，不新增备份或重复 import。
HOME="$FIXTURE_HOME" \
VIBEDEVOPS_REPO_DIR="$REPO_DIR" \
VIBEDEVOPS_SKIP_REPO_UPDATE=1 \
    "$REPO_DIR/install.sh" >/dev/null

for target in \
    "$FIXTURE_HOME/.claude/skills/vibedevops" \
    "$FIXTURE_HOME/.agents/skills/vibedevops" \
    "$FIXTURE_HOME/.config/opencode/skills/vibedevops" \
    "$FIXTURE_HOME/.codex/skills/vibedevops" \
    "$FIXTURE_HOME/.cursor/skills/vibedevops" \
    "$FIXTURE_HOME/.gemini/skills/vibedevops" \
    "$FIXTURE_HOME/.qwen/skills/vibedevops" \
    "$FIXTURE_HOME/.windsurf/skills/vibedevops"; do
    [ -L "$target" ] || { echo "missing skill link: $target"; exit 1; }
done

[ "$(readlink "$FIXTURE_HOME/.config/opencode/AGENTS.md")" = "$FIXTURE_HOME/AGENTS.md" ]
grep -qxF '@AGENTS.md' "$FIXTURE_HOME/CLAUDE.md"
grep -qxF '@../AGENTS.md' "$FIXTURE_HOME/.claude/CLAUDE.md"
grep -q '唯一权威规则源是.*~/AGENTS.md' "$FIXTURE_HOME/.codex/AGENTS.md"
grep -q '唯一权威规则源是.*~/AGENTS.md' "$FIXTURE_HOME/.gemini/GEMINI.md"
grep -q '唯一权威规则源是.*~/AGENTS.md' "$FIXTURE_HOME/.qwen/QWEN.md"
grep -q '# Claude-specific notes' "$FIXTURE_HOME/.claude/CLAUDE.md"
[ "$(grep -cxF '@../AGENTS.md' "$FIXTURE_HOME/.claude/CLAUDE.md")" = 1 ]
[ -L "$FIXTURE_HOME/.claude/CLAUDE.md" ]
CLAUDE_MODE="$(stat -f '%Lp' "$FIXTURE_HOME/shared/claude.md" 2>/dev/null || stat -c '%a' "$FIXTURE_HOME/shared/claude.md")"
[ "$CLAUDE_MODE" = 600 ]
CLAUDE_BACKUP="$(find "$FIXTURE_HOME/shared" -maxdepth 1 -type f -name 'claude.md.*.bak' -print -quit)"
[ -n "$CLAUDE_BACKUP" ] && [ "$(cat "$CLAUDE_BACKUP")" = '# Claude-specific notes' ]
[ ! -L "$FIXTURE_HOME/.gemini/GEMINI.md" ]
DANGLING_BACKUP="$(find "$FIXTURE_HOME/.gemini" -maxdepth 1 -type l -name 'GEMINI.md.*.bak' -print -quit)"
[ -n "$DANGLING_BACKUP" ] && [ "$(readlink "$DANGLING_BACKUP")" = 'missing-gemini.md' ]
BACKUP="$(find "$FIXTURE_HOME/.codex/skills" -maxdepth 1 -type d -name 'vibedevops.*.bak' -print -quit)"
[ -n "$BACKUP" ] && grep -qxF 'preserve me' "$BACKUP/local.txt"
[ "$(find "$FIXTURE_HOME/.codex/skills" -maxdepth 1 -type d -name 'vibedevops.*.bak' | wc -l | tr -d ' ')" = 1 ]

echo "installer global-rules fixtures passed"
