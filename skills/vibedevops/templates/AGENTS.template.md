# AGENTS.md — __PROJECT_NAME__

> 本文件是本仓库的**唯一权威协作守则**，对所有厂商的 coding agent（Claude Code / Codex / Cursor / Gemini / Windsurf / Kimi 等）一视同仁。
> CLAUDE.md、GEMINI.md、.cursorrules 等厂商文件只是指向本文件的指针；冲突时以本文件为准。

## 开始工作前：接续三步（必做）

1. 按固定顺序阅读：`README* → AGENTS.md → docs/HANDOFF.md → docs/adr/ → git log -10 --oneline`
2. 先跑一次验证命令，确认基线是绿的。**基线红 → 先修基线，绝不在红基线上叠改动。**
3. 用自己的话复述当前任务与验收标准，确认与 HANDOFF 一致后再动手。

## 多 App / 多模型写入纪律（强制）

- 一个分支/工作树同一时刻只有一个写入者；其他模型只读审查。
- 动手前核对 `docs/HANDOFF.md` 的当前写入者、App/模型、分支和 HEAD；不一致先停下修正。
- 换 App 前必须验证、更新 HANDOFF 并提交；下一棒从该 commit 接续。
- 并行写入必须使用不同 worktree、不同分支和不重叠的写入范围。
- 禁止用整段聊天记录交接；只交任务契约、Git 状态、验证证据、风险和下一步。
- 日常从 OpenChamber 路由；Claude 使用原生 App。按任务类型选择模型，不把所有模型串成万能链。
- 只有额度/限流/上游不可用或能力不匹配才允许 fallback；HTTP 400、工具 schema、代码或测试错误不得靠换模掩盖。
- 当前模型最多重试一次、整项任务最多跨三个模型；失败模型与下一跳必须写入 HANDOFF，禁止死循环。

## 结束工作前：收尾三件套（必做）

1. 跑完整验证命令，确认全绿。
2. 更新 `docs/HANDOFF.md`：当前目标 / 已完成 / 进行中（含文件与位置）/ 已知坑 / 下一步 / 验证方式。
3. 提交 git：**不留未提交的半成品**；commit message 用 Conventional Commits 并写清"为什么"。

## CI/CD 纪律（强制）

- PR 阶段自动执行 test / typecheck / lint / build，全绿才允许合并。
- PR 合并进 `main` 即完成生产部署授权；`push main` 必须自动部署、功能冒烟并在失败时自动回滚。
- 禁止把 `workflow_dispatch` 或合并后的人工 approve 设为正常发布必经门；手动触发只用于重试、回滚和事故恢复。
- 需要等待发布时间窗口时延迟合并，不得先合并再卡住部署。
- hosted CI 额度不足时切换受监控的 self-hosted runner/外部 CD 控制器，不得退回手工部署。

## 验证命令（共同基线）

- 测试 / 检查：`__VERIFY__`

如命令变更，必须同步更新本节——这是所有 agent 的共同基线。

## 决策记录（ADR）

- 任何"为什么这么改"的架构 / 方案决策，写入 `docs/adr/`，格式见 `docs/adr/0000-template.md`。
- 对话里想通但没落盘的决策，等于没发生过。

## Git 纪律

- 小步提交，一个 commit 只做一件事；一个任务一个分支。
- PR / 合并描述里贴验收标准；验收标准尽量写成可执行测试。

## 反模式（禁止）

- ❌ 把密钥写进代码、commit、`.env` 入库或对话——密钥只走环境变量 / Infisical 注入（见密钥规范）
- ❌ 在 CI / 测试红的状态下合并或继续叠新功能
- ❌ 直接执行含 `DROP` / 全表 `ALTER` / 全表 `UPDATE` 的迁移——先备份，走 expand-contract
- ❌ 把关键上下文写进 `.claude/`、`.cursor/` 等厂商私有目录
- ❌ 依赖对话摘要 / 上下文压缩传递状态
- ❌ 在测试红的状态下继续叠新功能
- ❌ 一次性做超出"半天能讲完"粒度的任务再交接
- ❌ 两个模型同时修改同一工作树或同一分支
