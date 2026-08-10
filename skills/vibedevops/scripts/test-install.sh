#!/usr/bin/env bash

set -euo pipefail
trap 'echo "installer fixture failed at line $LINENO" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FIXTURE_HOME="$(mktemp -d)"
EMPTY_HOME="$(mktemp -d)"
BAD_HOME="$(mktemp -d)"
LINK_HOME="$(mktemp -d)"
DANGLING_HOME="$(mktemp -d)"
MENTION_HOME="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_HOME" "$EMPTY_HOME" "$BAD_HOME" "$LINK_HOME" "$DANGLING_HOME" "$MENTION_HOME"' EXIT

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
grep -q 'VIBEDEVOPS:MANAGED-DEVOPS:START' "$FIXTURE_HOME/AGENTS.md"
grep -q 'Xserver 构建优先、Mac fallback' "$FIXTURE_HOME/AGENTS.md"
[ "$(grep -c 'VIBEDEVOPS:MANAGED-DEVOPS:START' "$FIXTURE_HOME/AGENTS.md")" = 1 ]
[ "$(grep -c 'VIBEDEVOPS:MANAGED-DEVOPS:END' "$FIXTURE_HOME/AGENTS.md")" = 1 ]
GLOBAL_BACKUPS="$(find "$FIXTURE_HOME" -maxdepth 1 -type f -name 'AGENTS.md.*.bak' | wc -l | tr -d ' ')"
[ "$GLOBAL_BACKUPS" = 1 ]
if [ "$(uname -s)" = "Darwin" ]; then
    GLOBAL_MODE="$(stat -f '%Lp' "$FIXTURE_HOME/AGENTS.md")"
else
    GLOBAL_MODE="$(stat -c '%a' "$FIXTURE_HOME/AGENTS.md")"
fi
[ "$GLOBAL_MODE" = 600 ]
grep -q '# Claude-specific notes' "$FIXTURE_HOME/.claude/CLAUDE.md"
[ "$(grep -cxF '@../AGENTS.md' "$FIXTURE_HOME/.claude/CLAUDE.md")" = 1 ]
[ -L "$FIXTURE_HOME/.claude/CLAUDE.md" ]
if [ "$(uname -s)" = "Darwin" ]; then
    CLAUDE_MODE="$(stat -f '%Lp' "$FIXTURE_HOME/shared/claude.md")"
else
    CLAUDE_MODE="$(stat -c '%a' "$FIXTURE_HOME/shared/claude.md")"
fi
[ "$CLAUDE_MODE" = 600 ]
CLAUDE_BACKUP="$(find "$FIXTURE_HOME/shared" -maxdepth 1 -type f -name 'claude.md.*.bak' -print -quit)"
[ -n "$CLAUDE_BACKUP" ] && [ "$(cat "$CLAUDE_BACKUP")" = '# Claude-specific notes' ]
[ ! -L "$FIXTURE_HOME/.gemini/GEMINI.md" ]
DANGLING_BACKUP="$(find "$FIXTURE_HOME/.gemini" -maxdepth 1 -type l -name 'GEMINI.md.*.bak' -print -quit)"
[ -n "$DANGLING_BACKUP" ] && [ "$(readlink "$DANGLING_BACKUP")" = 'missing-gemini.md' ]
BACKUP="$(find "$FIXTURE_HOME/.codex/skills" -maxdepth 1 -type d -name 'vibedevops.*.bak' -print -quit)"
[ -n "$BACKUP" ] && grep -qxF 'preserve me' "$BACKUP/local.txt"
[ "$(find "$FIXTURE_HOME/.codex/skills" -maxdepth 1 -type d -name 'vibedevops.*.bak' | wc -l | tr -d ' ')" = 1 ]

HOME="$EMPTY_HOME" \
VIBEDEVOPS_REPO_DIR="$REPO_DIR" \
VIBEDEVOPS_SKIP_REPO_UPDATE=1 \
    "$REPO_DIR/install.sh" >/dev/null
HOME="$EMPTY_HOME" \
VIBEDEVOPS_REPO_DIR="$REPO_DIR" \
VIBEDEVOPS_SKIP_REPO_UPDATE=1 \
    "$REPO_DIR/install.sh" >/dev/null
[ -f "$EMPTY_HOME/AGENTS.md" ]
grep -q 'VIBEDEVOPS:MANAGED-DEVOPS:START' "$EMPTY_HOME/AGENTS.md"
grep -q 'Git 仓库是构建与交接的唯一事实源' "$EMPTY_HOME/AGENTS.md"
[ "$(find "$EMPTY_HOME" -maxdepth 1 -type f -name 'AGENTS.md.*.bak' | wc -l | tr -d ' ')" = 0 ]

printf '%s\n' \
    '# preserve malformed rules' \
    '<!-- VIBEDEVOPS:MANAGED-DEVOPS:START -->' \
    'must survive' > "$BAD_HOME/AGENTS.md"
cp "$BAD_HOME/AGENTS.md" "$BAD_HOME/AGENTS.before"
if HOME="$BAD_HOME" \
    VIBEDEVOPS_REPO_DIR="$REPO_DIR" \
    VIBEDEVOPS_SKIP_REPO_UPDATE=1 \
    "$REPO_DIR/install.sh" >/dev/null 2>&1; then
    echo "malformed managed markers must be rejected" >&2
    exit 1
fi
cmp -s "$BAD_HOME/AGENTS.before" "$BAD_HOME/AGENTS.md"

mkdir -p "$LINK_HOME/dotfiles"
printf '# linked global rules\n' > "$LINK_HOME/dotfiles/AGENTS.shared.md"
ln -s dotfiles/AGENTS.shared.md "$LINK_HOME/AGENTS.md"
HOME="$LINK_HOME" \
VIBEDEVOPS_REPO_DIR="$REPO_DIR" \
VIBEDEVOPS_SKIP_REPO_UPDATE=1 \
    "$REPO_DIR/install.sh" >/dev/null
[ -L "$LINK_HOME/AGENTS.md" ]
grep -q 'VIBEDEVOPS:MANAGED-DEVOPS:START' "$LINK_HOME/dotfiles/AGENTS.shared.md"
[ "$(find "$LINK_HOME/dotfiles" -maxdepth 1 -type f -name 'AGENTS.shared.md.*.bak' | wc -l | tr -d ' ')" = 1 ]

ln -s missing/AGENTS.md "$DANGLING_HOME/AGENTS.md"
if HOME="$DANGLING_HOME" \
    VIBEDEVOPS_REPO_DIR="$REPO_DIR" \
    VIBEDEVOPS_SKIP_REPO_UPDATE=1 \
    "$REPO_DIR/install.sh" >/dev/null 2>&1; then
    echo "dangling global rules symlink must be rejected" >&2
    exit 1
fi
[ -L "$DANGLING_HOME/AGENTS.md" ]

printf '%s\n' \
    '# marker mentions are ordinary user rules' \
    'explain <!-- VIBEDEVOPS:MANAGED-DEVOPS:START --> without managing' \
    'KEEP_BETWEEN_MENTIONS' \
    'explain <!-- VIBEDEVOPS:MANAGED-DEVOPS:END --> without managing' \
    > "$MENTION_HOME/AGENTS.md"
HOME="$MENTION_HOME" \
VIBEDEVOPS_REPO_DIR="$REPO_DIR" \
VIBEDEVOPS_SKIP_REPO_UPDATE=1 \
    "$REPO_DIR/install.sh" >/dev/null
grep -q 'KEEP_BETWEEN_MENTIONS' "$MENTION_HOME/AGENTS.md"
grep -q '^explain <!-- VIBEDEVOPS:MANAGED-DEVOPS:START --> without managing$' "$MENTION_HOME/AGENTS.md"

echo "installer global-rules fixtures passed"
