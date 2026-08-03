#!/bin/bash
# deploy-handoff.sh — 跨 agent 交接架构批量部署脚本（幂等、非破坏性）
# 把 AGENTS.md + docs/HANDOFF.md + docs/adr/ + 厂商指针铺到一批 git 仓库。
# 用法: deploy-handoff.sh [--dry-run]
# 注: 不使用 set -u —— macOS 自带 bash 3.2 对空数组展开会误报 unbound variable

KIT="$(cd "$(dirname "$0")" && pwd)"
TPL="$KIT/../templates"
DATE="$(date +%F)"
TS="$(date +%Y%m%d-%H%M)"
REPORT="$KIT/deploy-report-$TS.md"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

# ↓↓↓ 改成你自己的仓库路径；必须先 git init，非 git 仓库会被自动跳过 ↓↓↓
REPOS=(
  # /path/to/project-a
  # /path/to/project-b
)

# 厂商指针文件（不存在则创建；已存在且未引用 AGENTS.md 则备份后追加指针块）
POINTERS=(CLAUDE.md GEMINI.md .cursorrules .windsurfrules .github/copilot-instructions.md)

detect_verify() {
  local r="$1"
  if [ -f "$r/package.json" ]; then
    if grep -q '"test"' "$r/package.json" 2>/dev/null; then echo 'npm test'; else echo '（package.json 无 test 脚本，待补充）'; fi
  elif [ -f "$r/Makefile" ] && grep -qE '^test:' "$r/Makefile"; then echo 'make test'
  elif [ -f "$r/go.mod" ]; then echo 'go test ./...'
  elif [ -f "$r/Cargo.toml" ]; then echo 'cargo test'
  elif [ -f "$r/pytest.ini" ] || [ -d "$r/tests" ]; then echo 'pytest'
  else echo '（待补充：填写本项目的测试 / 构建命令）'; fi
}

render() { # render <template> <dest> <name> <verify>
  local name="$3" verify="$4"
  sed -e "s/__PROJECT_NAME__/$name/g" -e "s/__VERIFY__/$(echo "$verify" | sed 's/[&/\]/\\&/g')/g" -e "s/__DATE__/$DATE/g" "$1" > "$2"
}

if [ ${#REPOS[@]} -eq 0 ]; then
  echo "REPOS 数组为空——先编辑本脚本填入你的仓库路径。" >&2; exit 1
fi

{
echo "# 交接架构部署报告 · $TS"
echo
[ $DRY -eq 1 ] && echo "**模式：DRY-RUN（未写入任何内容）**" && echo
} >> "$REPORT"

for r in "${REPOS[@]}"; do
  name="$(basename "$r")"
  echo "== $r" >> "$REPORT"
  if [ ! -d "$r/.git" ]; then echo "- 跳过：不是 git 仓库" >> "$REPORT"; continue; fi
  verify="$(detect_verify "$r")"
  created=(); appended=(); kept=()

  if [ $DRY -eq 0 ]; then mkdir -p "$r/docs/adr" "$r/.github"; fi

  # 1) AGENTS.md
  if [ -e "$r/AGENTS.md" ]; then kept+=("AGENTS.md(已存在)")
  else
    [ $DRY -eq 0 ] && render "$TPL/AGENTS.template.md" "$r/AGENTS.md" "$name" "$verify"
    created+=("AGENTS.md")
  fi

  # 2) docs/HANDOFF.md
  if [ -e "$r/docs/HANDOFF.md" ]; then kept+=("docs/HANDOFF.md(已存在)")
  else
    [ $DRY -eq 0 ] && render "$TPL/HANDOFF.template.md" "$r/docs/HANDOFF.md" "$name" "$verify"
    created+=("docs/HANDOFF.md")
  fi

  # 3) ADR 模板与说明
  for f in "adr-0000-template.md:docs/adr/0000-template.md" "adr-README.md:docs/adr/README.md"; do
    src="${f%%:*}"; dst="${f##*:}"
    if [ -e "$r/$dst" ]; then kept+=("$dst(已存在)")
    else
      [ $DRY -eq 0 ] && cp "$TPL/$src" "$r/$dst"
      created+=("$dst")
    fi
  done

  # 4) CHANGELOG.md
  if [ -e "$r/CHANGELOG.md" ]; then kept+=("CHANGELOG.md(已存在)")
  else
    if [ $DRY -eq 0 ]; then
      printf '# Changelog\n\n## %s\n\n- 部署跨 agent 交接架构：AGENTS.md、docs/HANDOFF.md、docs/adr/、厂商指针文件。\n' "$DATE" > "$r/CHANGELOG.md"
    fi
    created+=("CHANGELOG.md")
  fi

  # 5) 厂商指针
  for p in "${POINTERS[@]}"; do
    if [ -e "$r/$p" ]; then
      if grep -q 'AGENTS.md' "$r/$p" 2>/dev/null; then
        kept+=("$p(已含指针)")
      else
        if [ $DRY -eq 0 ]; then
          cp "$r/$p" "$r/$p.bak-$TS"
          printf '\n\n---\n> 🤝 跨 agent 交接协议（%s 部署）：本仓库的权威协作守则为 **AGENTS.md**，当前任务状态见 **docs/HANDOFF.md**。本文件与 AGENTS.md 冲突时，以 AGENTS.md 为准。\n' "$DATE" >> "$r/$p"
        fi
        appended+=("$p(备份后追加指针)")
      fi
    else
      [ $DRY -eq 0 ] && cp "$TPL/pointer.txt" "$r/$p"
      created+=("$p")
    fi
  done

  # 6) 提交（仅提交本次新增/修改的文件；-f 覆盖 gitignore，文件一旦被跟踪即恢复正常跟踪）
  commit_status="dry-run，未提交"
  n_created=${#created[@]:-0}; n_appended=${#appended[@]:-0}
  if [ $DRY -eq 0 ] && [ "$n_created" -gt 0 -o "$n_appended" -gt 0 ]; then
    addlist=()
    for c in ${created[@]+"${created[@]}"}; do addlist+=("$c"); done
    for a in ${appended[@]+"${appended[@]}"}; do addlist+=("${a%%(*}"); done
    err=$((cd "$r" && git add -f -- "${addlist[@]}" && \
     git commit -q -m "docs: 引入跨 agent 交接架构（AGENTS.md + HANDOFF + ADR + 厂商指针）") 2>&1)
    if [ $? -eq 0 ]; then commit_status="已提交"
    else (cd "$r" && git reset -q 2>/dev/null); commit_status="提交失败，文件已保留为未暂存状态: $(echo "$err" | tail -2 | tr '\n' ' ')"; fi
  elif [ "$n_created" -eq 0 ] && [ "$n_appended" -eq 0 ]; then
    commit_status="无变更"
  fi

  {
    [ "$n_created" -gt 0 ] && echo "- 新增: ${created[*]}"
    [ "$n_appended" -gt 0 ] && echo "- 追加: ${appended[*]}"
    [ ${#kept[@]:-0} -gt 0 ] && echo "- 保留: ${kept[*]}"
    echo "- 验证命令: \`$verify\`"
    echo "- git: $commit_status"
    echo
  } >> "$REPORT"
done

echo "报告: $REPORT"
cat "$REPORT"
