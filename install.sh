#!/bin/bash
# install.sh — 一键安装 VibeDevOps skills（vibedevops + flow）到本机所有 Agent

set -e

REPO_URL="https://github.com/iPythoning/VibeDevOps-skill.git"
REPO_DIR="$HOME/Documents/GitHub/VibeDevOps-skill"

echo "🚀 安装 VibeDevOps skills 到本机所有 Agent..."

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
    local skill=$3
    local target="$agent_dir/$skill"

    if [ -d "$agent_dir" ]; then
        echo "🔗 安装 $skill 到 $agent_name..."
        rm -rf "$target"
        ln -s "$REPO_DIR/skills/$skill" "$target"
        echo "   ✅ $agent_name -> $target"
    else
        echo "   ⚠️  $agent_name 目录不存在，跳过"
    fi
}

for skill in vibedevops flow; do
    install_to_agent "$HOME/.claude/skills" "Claude Code" "$skill"
    install_to_agent "$HOME/.agents/skills" "Agents" "$skill"
    install_to_agent "$HOME/.config/opencode/skills" "OpenCode / OpenChamber" "$skill"
    install_to_agent "$HOME/.cc-switch/skills" "CC-Switch" "$skill"
    install_to_agent "$HOME/.codex/skills" "Codex" "$skill"
    install_to_agent "$HOME/.cursor/skills" "Cursor" "$skill"
    install_to_agent "$HOME/.gemini/skills" "Gemini" "$skill"
    install_to_agent "$HOME/.qwen/skills" "Qwen" "$skill"
    install_to_agent "$HOME/.windsurf/skills" "Windsurf" "$skill"
done

# 3. 安装 OpenChamber 专项 Agent（同名普通文件先备份）
OPENCHAMBER_AGENTS="$HOME/.config/opencode/agents"
OPENCHAMBER_AGENT_SOURCE="$REPO_DIR/skills/vibedevops/templates/openchamber-agents"
mkdir -p "$OPENCHAMBER_AGENTS"
for profile in Reasonix-Go Kimi-K3 Kimi-Code DeepSeek-Pro Fallback-Auto; do
    target="$OPENCHAMBER_AGENTS/$profile.md"
    if [ -L "$target" ]; then
        ln -sfn "$OPENCHAMBER_AGENT_SOURCE/$profile.md" "$target"
    else
        if [ -e "$target" ]; then
            mv "$target" "$target.$(date +%Y%m%d%H%M%S).bak"
        fi
        ln -s "$OPENCHAMBER_AGENT_SOURCE/$profile.md" "$target"
    fi
    echo "   ✅ OpenChamber Agent -> $profile"
done

# 4. 尝试安装到 Kimi Work（如果目录存在）
KIMI_SKILLS="$HOME/Library/Application Support/kimi-desktop/daimon-share/daimon/skills"
if [ -d "$KIMI_SKILLS" ]; then
    for skill in vibedevops flow; do
        echo "🔗 安装 $skill 到 Kimi Work..."
        rm -rf "$KIMI_SKILLS/$skill"
        ln -s "$REPO_DIR/skills/$skill" "$KIMI_SKILLS/$skill"
        echo "   ✅ Kimi Work -> $KIMI_SKILLS/$skill"
    done
fi

echo ""
echo "✅ 安装完成！vibedevops + flow skills 与 OpenChamber Agent 已同步。"
echo "📍 统一源: $REPO_DIR/skills"
echo "🔄 更新方式: cd $REPO_DIR && git pull"
echo ""
echo "触发词: /vibedevops（看懂 AI 改动、项目地图、交接架构） · /flow（走流程、全链路工作流）"
