#!/bin/bash
# install-flow-skill.sh — 一键安装 /flow skill 到本机所有 Agent

set -e

REPO_URL="https://github.com/iPythoning/flow-skill.git"
REPO_DIR="$HOME/Documents/GitHub/flow-skill"
SKILL_SRC="$REPO_DIR/skills/flow"

echo "🚀 安装 /flow skill 到本机所有 Agent..."

# 1. 克隆或更新仓库
if [ -d "$REPO_DIR/.git" ]; then
    echo "📦 更新现有仓库..."
    cd "$REPO_DIR" && git pull
else
    echo "📦 克隆仓库..."
    mkdir -p "$HOME/Documents/GitHub"
    git clone "$REPO_URL" "$REPO_DIR"
fi

# 2. 安装到各 Agent
install_to_agent() {
    local agent_dir=$1
    local agent_name=$2
    local target="$agent_dir/flow"

    if [ -d "$agent_dir" ]; then
        echo "🔗 安装到 $agent_name..."
        rm -rf "$target"
        ln -s "$SKILL_SRC" "$target"
        echo "   ✅ $agent_name -> $target"
    else
        echo "   ⚠️  $agent_name 目录不存在，跳过"
    fi
}

install_to_agent "$HOME/.claude/skills" "Claude Code"
install_to_agent "$HOME/.agents/skills" "Agents"
install_to_agent "$HOME/.cc-switch/skills" "CC-Switch"

# 3. 尝试安装到 Kimi Work（如果目录存在）
KIMI_SKILLS="$HOME/Library/Application Support/kimi-desktop/daimon-share/daimon/skills"
if [ -d "$KIMI_SKILLS" ]; then
    echo "🔗 安装到 Kimi Work..."
    rm -rf "$KIMI_SKILLS/flow"
    ln -s "$SKILL_SRC" "$KIMI_SKILLS/flow"
    echo "   ✅ Kimi Work -> $KIMI_SKILLS/flow"
fi

echo ""
echo "✅ 安装完成！/flow skill 已同步到所有 Agent。"
echo "📍 统一源: $SKILL_SRC"
echo "🔄 更新方式: cd $REPO_DIR && git pull"
echo ""
echo "触发词: /flow、走流程、全链路工作流、feature 开发流程、组装工作流、一条龙"
