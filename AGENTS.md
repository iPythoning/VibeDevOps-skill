# AGENTS.md — VibeDevOps-skill

> 本文件是本仓库的**唯一权威协作守则**，对所有厂商的 coding agent（Claude Code / Codex / Cursor / Gemini / Windsurf / Kimi 等）一视同仁。
> CLAUDE.md、GEMINI.md、.cursorrules 等厂商文件只是指向本文件的指针；冲突时以本文件为准。

## 开始工作前：接续三步（必做）

1. 按固定顺序阅读：`README* → AGENTS.md → docs/HANDOFF.md → docs/adr/ → git log -10 --oneline`
2. 先跑一次验证命令，确认基线是绿的。**基线红 → 先修基线，绝不在红基线上叠改动。**
3. 用自己的话复述当前任务与验收标准，确认与 HANDOFF 一致后再动手。

## 结束工作前：收尾三件套（必做）

1. 跑完整验证命令，确认全绿。
2. 更新 `docs/HANDOFF.md`：当前目标 / 已完成 / 进行中（含文件与位置）/ 已知坑 / 下一步 / 验证方式。
3. 提交 git：**不留未提交的半成品**；commit message 用 Conventional Commits 并写清"为什么"。

## 验证命令（共同基线）

- 测试 / 检查：`bash -n install.sh skills/vibedevops/scripts/deploy-handoff.sh skills/vibedevops/scripts/health-check.sh skills/vibedevops/scripts/test-build-runner.sh skills/vibedevops/scripts/test-health-check.sh skills/vibedevops/scripts/test-image-lifecycle.sh skills/vibedevops/scripts/test-install.sh skills/vibedevops/scripts/test-reasonix-runtime.sh skills/vibedevops/templates/build-gate/install-github-runner.sh skills/vibedevops/templates/image-lifecycle/cleanup-docker-images.sh skills/vibedevops/templates/image-lifecycle/cleanup-ghcr-versions.sh skills/vibedevops/templates/image-lifecycle/install-local-guard.sh skills/vibedevops/templates/reasonix-runtime/install.sh skills/vibedevops/templates/reasonix-runtime/health-check.sh && ./skills/vibedevops/scripts/test-build-runner.sh && ./skills/vibedevops/scripts/test-health-check.sh && ./skills/vibedevops/scripts/test-image-lifecycle.sh && ./skills/vibedevops/scripts/test-install.sh && ./skills/vibedevops/scripts/test-reasonix-runtime.sh && ./skills/vibedevops/scripts/health-check.sh --json . >/dev/null`

如命令变更，必须同步更新本节——这是所有 agent 的共同基线。

## 决策记录（ADR）

- 任何"为什么这么改"的架构 / 方案决策，写入 `docs/adr/`，格式见 `docs/adr/0000-template.md`。
- 对话里想通但没落盘的决策，等于没发生过。

## Git 纪律

- 小步提交，一个 commit 只做一件事；一个任务一个分支。
- PR / 合并描述里贴验收标准；验收标准尽量写成可执行测试。

## CI/CD 纪律

- PR 阶段自动执行 test / typecheck / lint / build，全绿才允许合并。
- PR 合并进 `main` 即完成生产部署授权；`push main` 必须自动部署、功能冒烟并在失败时自动回滚。
- 禁止把 `workflow_dispatch` 或合并后的人工 approve 设为正常发布必经门；手动触发仅用于重试、回滚和事故恢复。
- 需要等待发布时间窗口时延迟合并，不得先合并再卡住部署。
- hosted CI 额度不足时切换受监控的 self-hosted runner/外部 CD 控制器，不得退回手工部署。
- 每次成功部署后清理部署机旧镜像/build cache，current 与 last-known-good digest 必须保护；禁止 `docker image rm --force`、禁止自动删 volume。`docker builder prune --force` 只允许用于关闭交互确认，且必须带过期过滤器并只清未使用 cache。
- GHCR 必须有每日 retention：保护生产/回滚 tag，至少保留最新 30 个 package versions，并给新构建至少 6 小时安全窗；清理失败告警但不回滚健康版本。

## 反模式（禁止）

- ❌ 把关键上下文写进 `.claude/`、`.cursor/` 等厂商私有目录
- ❌ 依赖对话摘要 / 上下文压缩传递状态
- ❌ 在测试红的状态下继续叠新功能
- ❌ 一次性做超出"半天能讲完"粒度的任务再交接


## 工程原则

- 不保留向后兼容：删除过时路径，而不是加兼容层、回退或迁移代码。
- 选择能完全满足当前需求的最简实现；避免投机性的抽象、配置与间接层。
- 分层演进：从端到端能跑通的最小版本开始，在"已经能用"的基础上叠加新能力；绝不用半成品复杂度替换能用的产品。
- 保持组件模块化，关注点清晰分离。
- 优先采用成熟且维护良好的库（能降低整体复杂度或提升可靠性时）；无明确理由不重复实现常见功能。
- 先用项目里已有的依赖，再考虑自己实现或新增包；在查文档和类型定义之前，不要假设某个库缺少某能力。
- 架构决策面向长期；不接受"只能应付现在、注定以后替换"的临时方案。

冲突裁决：架构边界按长期设计，边界之内的实现按当前最简。

安全红线：绝不提交密钥、证书、证件与客户隐私数据；发现仓库中已存在此类文件时，先报告，不静默处理。
