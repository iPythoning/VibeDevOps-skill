# 交接状态 · HANDOFF（VibeDevOps-skill）

> 任何 agent 开始工作前**必读**，结束工作前**必更新**。
> 本文件是当前任务状态的唯一权威来源；历史决策看 docs/adr/，历史变更看 git log。

## 当前目标

把“OpenChamber 日常主入口 + Claude 原生 App”的任务路由、有限 fallback 与单写入者交接协议固化到 VibeDevOps 技能、仓库模板和本机全局规则。

## 当前接棒状态

- 状态：待接棒
- 当前写入者：无
- App / 模型：无
- 分支：main
- HEAD：本次交接提交见 `git log -1 --oneline`
- 工作树：应为干净；接棒时以 `git status --short` 为准
- 下一棒：按具体项目任务选择，不默认启用全部模型

## 模型路由状态

- 任务类型：architecture / workflow
- 首选模型：Codex（本次规则实现）
- 当前模型：Codex
- 已失败 / 冷却路由：OpenChamber `opencode-omniroute/sk/gpt-5.6-sol`（无有效 SSE）；`opencode-go/gpt-5.6-luna`（地区限制）；`opencode-go/kimi-k3`（最小请求 90 秒无响应，本次冷却）
- 已验证路由：`opencode-go/kimi-k2.7-code`、`opencode-go/deepseek-v4-pro`、`opencode-omniroute/auto/best-coding`
- 下一 fallback：当前任务无需换模
- 最近错误证据：2026-08-09 本机 `opencode run` smoke test

## 验收标准

- `vibedevops` 能由“多模型/跨 App/路由/接棒”等请求触发。
- OpenChamber 能从 `~/.config/opencode/skills` 读取统一源中的技能。
- 技能明确默认角色、单写入者、结构化接棒载荷和缓存纪律。
- 技能按任务类型定义 OpenChamber 内部 fallback，并限制重试次数与最多三跳。
- 额度/限流/上游故障与 400、权限、地区、代码错误被明确区分。
- 新部署的 AGENTS/HANDOFF 模板包含写入所有权与 Git 状态字段。
- 本机 `~/AGENTS.md` 对所有 coding agent 强制执行同一协议。
- 技能结构、Shell 语法、diff 检查和仓库健康检查通过。

## 已完成

- 2026-08-06：部署跨 agent 交接架构（AGENTS.md / HANDOFF / ADR / 厂商指针）
- 2026-08-09：新增多 App / 多模型路由参考、单写入者规则、结构化接棒模板，并同步本机全局规则。
- 2026-08-09：安装脚本新增 OpenCode/OpenChamber 技能目录，避免图形端漏装。
- 2026-08-09：改为 OpenChamber 日常主入口、Claude 原生 App；加入任务型 fallback、失败冷却、三跳上限与缓存边界。
- 2026-08-09：注册 5 个 OpenChamber Agent；Kimi K2.7 Code、DeepSeek V4 Pro 与 OmniRoute Auto smoke test 通过，Codex/GPT 与 Kimi K3 的失败证据已记录。

## 进行中

（无）

## 已知坑 / 注意事项

- Git hook 可以强制“代码变更必须更新 HANDOFF”，但无法证明某个外部 App 实际使用了指定模型；模型路由依赖所有 App 共同遵守 `~/AGENTS.md`。
- OmniRoute `auto/best-coding` 实测可用且落到 LongCat，但插件 `/api/combos` 仍报 403；只作为最后保障，不作为固定四模型链。
- OpenChamber 的 Codex/GPT 路由本次 smoke test 不可用；修复凭证/地区前继续使用 Codex 原生 App。
- OpenCode Agent 一次只能绑定一个模型；硬额度错误发生在模型响应前时，需在 OpenChamber 一键选择下一 Agent。只有 OmniRoute Combo 能在单请求内自动降级。
- 既有仓库不会被模板自动覆盖；需要在目标仓库显式运行 `/vibedevops 交接` 或现有部署脚本升级。

## 下一步

在一个真实项目中执行 `/vibedevops 路由`，验证 Kimi K2.7 Code / DeepSeek Pro 能仅凭 Git + HANDOFF 接续；Kimi K3 路由恢复后再做 smoke test。

## 如何验证

- `bash -n install.sh skills/vibedevops/scripts/deploy-handoff.sh skills/vibedevops/scripts/health-check.sh`
- `python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/vibedevops`
- `git diff --check`
- `./skills/vibedevops/scripts/health-check.sh --json .`

## 最近交接记录

| 日期 | 操作者 | 摘要 |
|---|---|---|
| 2026-08-09 | Codex | 改为 OpenChamber 优先并加入按任务类型的有限 fallback |
| 2026-08-09 | Codex | 固化四模型跨 App 路由与单写入者接棒协议 |
| 2026-08-06 | 部署脚本 | 初始化交接架构 |
