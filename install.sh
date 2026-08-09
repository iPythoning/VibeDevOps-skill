#!/bin/bash
# install.sh — 一键安装 VibeDevOps skills（vibedevops + flow）到本机所有 Agent

set -e

REPO_URL="https://github.com/iPythoning/VibeDevOps-skill.git"
REPO_DIR="${VIBEDEVOPS_REPO_DIR:-$HOME/Documents/GitHub/VibeDevOps-skill}"

echo "🚀 安装 VibeDevOps skills 到本机所有 Agent..."

# 1. 克隆或更新仓库
if [ "${VIBEDEVOPS_SKIP_REPO_UPDATE:-0}" = "1" ]; then
    [ -d "$REPO_DIR/skills" ] || { echo "❌ VIBEDEVOPS_REPO_DIR 无效: $REPO_DIR"; exit 1; }
elif [ -d "$REPO_DIR/.git" ]; then
    echo "📦 更新现有仓库..."
    git -C "$REPO_DIR" pull --ff-only
else
    echo "📦 克隆仓库..."
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
fi

# 2. 将所有 Agent 的全局规则入口收敛到 ~/AGENTS.md
GLOBAL_RULES="$HOME/AGENTS.md"
POINTER_TEXT='> 本机所有 coding agent 的**唯一权威规则源是 `~/AGENTS.md`**，项目地图是 `~/PROJECTS.md`。
> 进入任何仓库前，先读该仓库的 `AGENTS.md` 与 `docs/HANDOFF.md`，跑一次验证命令确认基线绿；
> 收工前更新 `docs/HANDOFF.md` 并提交，不留半成品。冲突时一律以 `~/AGENTS.md` 为准。'

backup_name() {
    printf '%s.%s.%s.bak\n' "$1" "$(date +%Y%m%d%H%M%S)" "$$"
}

ensure_regular_entry() {
    local target=$1
    local agent_name=$2
    local import_line=${3:-}
    local has_pointer=0
    local has_import=0
    mkdir -p "$(dirname "$target")"
    [ -f "$target" ] && grep -q '唯一权威规则源是.*~/AGENTS.md' "$target" && has_pointer=1
    if [ -z "$import_line" ] || { [ -f "$target" ] && grep -qxF "$import_line" "$target"; }; then
        has_import=1
    fi
    if [ "$has_pointer" = "1" ] && [ "$has_import" = "1" ]; then
        echo "   ✅ $agent_name 规则入口已指向 ~/AGENTS.md"
        return
    fi

    local staged="$target.vibedevops.$$"
    if [ -e "$target" ]; then
        cp -p "$target" "$(backup_name "$target")"
        cp -p "$target" "$staged"
        : > "$staged"
    else
        : > "$staged"
    fi
    if [ "$has_pointer" = "0" ]; then
        printf '%s\n\n' "$POINTER_TEXT" >> "$staged"
    fi
    if [ -f "$target" ]; then
        sed -n '1,$p' "$target" >> "$staged"
    fi
    if [ -n "$import_line" ] && [ "$has_import" = "0" ]; then
        printf '\n%s\n' "$import_line" >> "$staged"
    fi
    mv "$staged" "$target"
    echo "   ✅ $agent_name 规则入口 -> ~/AGENTS.md"
}

ensure_rule_entry() {
    local target=$1
    local agent_name=$2
    local import_line=${3:-}
    if [ -L "$target" ]; then
        local linked
        linked="$(readlink "$target")"
        if [ -e "$target" ]; then
            case "$linked" in
                /*) ;;
                *) linked="$(dirname "$target")/$linked" ;;
            esac
            if [ ! -f "$linked" ]; then
                echo "❌ $agent_name 规则软链未指向普通文件: $target" >&2
                exit 1
            fi
            ensure_regular_entry "$linked" "$agent_name（保留现有软链）" "$import_line"
            return
        fi

        # 悬空软链不能直接写入；保留链接本身后建立可用的本地入口。
        mv "$target" "$(backup_name "$target")"
        ensure_regular_entry "$target" "$agent_name（已备份悬空软链）" "$import_line"
    else
        ensure_regular_entry "$target" "$agent_name" "$import_line"
    fi
}

if [ -f "$GLOBAL_RULES" ]; then
    ensure_rule_entry "$HOME/CLAUDE.md" "Claude Code" '@AGENTS.md'
    ensure_rule_entry "$HOME/.claude/CLAUDE.md" "Claude Code config" '@../AGENTS.md'
    ensure_rule_entry "$HOME/GEMINI.md" "Gemini CLI"
    ensure_rule_entry "$HOME/.gemini/GEMINI.md" "Gemini config"
    ensure_rule_entry "$HOME/.codex/AGENTS.md" "Codex"
    ensure_rule_entry "$HOME/.cursorrules" "Cursor"
    ensure_rule_entry "$HOME/.windsurfrules" "Windsurf"
    [ -d "$HOME/.qwen" ] && ensure_rule_entry "$HOME/.qwen/QWEN.md" "Qwen"

    mkdir -p "$HOME/.config/opencode"
    OPENCODE_RULES="$HOME/.config/opencode/AGENTS.md"
    if [ -L "$OPENCODE_RULES" ]; then
        ln -sfn "$GLOBAL_RULES" "$OPENCODE_RULES"
    else
        if [ -e "$OPENCODE_RULES" ]; then
            mv "$OPENCODE_RULES" "$OPENCODE_RULES.$(date +%Y%m%d%H%M%S).bak"
        fi
        ln -s "$GLOBAL_RULES" "$OPENCODE_RULES"
    fi
    echo "   ✅ OpenCode / OpenChamber 全局规则 -> $GLOBAL_RULES"
else
    echo "   ⚠️  $GLOBAL_RULES 不存在，仅安装 skills；请先建立唯一全局规则源"
fi

# 3. 安装到各 Agent
install_to_agent() {
    local agent_dir=$1
    local agent_name=$2
    local skill=$3
    local target="$agent_dir/$skill"

    if [ -d "$agent_dir" ]; then
        echo "🔗 安装 $skill 到 $agent_name..."
        if [ -L "$target" ]; then
            ln -sfn "$REPO_DIR/skills/$skill" "$target"
        else
            if [ -e "$target" ]; then
                mv "$target" "$target.$(date +%Y%m%d%H%M%S).bak"
            fi
            ln -s "$REPO_DIR/skills/$skill" "$target"
        fi
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

# 4. 安装 OpenChamber 专项 Agent（同名普通文件先备份）
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

# 5. 尝试安装到 Kimi Work（如果目录存在）
KIMI_SKILLS="$HOME/Library/Application Support/kimi-desktop/daimon-share/daimon/skills"
if [ -d "$KIMI_SKILLS" ]; then
    for skill in vibedevops flow; do
        echo "🔗 安装 $skill 到 Kimi Work..."
        target="$KIMI_SKILLS/$skill"
        if [ -L "$target" ]; then
            ln -sfn "$REPO_DIR/skills/$skill" "$target"
        else
            if [ -e "$target" ]; then
                mv "$target" "$target.$(date +%Y%m%d%H%M%S).bak"
            fi
            ln -s "$REPO_DIR/skills/$skill" "$target"
        fi
        echo "   ✅ Kimi Work -> $KIMI_SKILLS/$skill"
    done
fi

echo ""
echo "✅ 安装完成！全局规则、vibedevops + flow skills 与 OpenChamber Agent 已同步。"
echo "📍 统一源: $REPO_DIR/skills"
echo "🔄 更新方式: cd $REPO_DIR && git pull"
echo ""
echo "触发词: /vibedevops（看懂 AI 改动、项目地图、交接架构） · /flow（走流程、全链路工作流）"
