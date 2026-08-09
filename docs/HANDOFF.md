# 交接状态 · HANDOFF（VibeDevOps-skill）

> 任何 agent 开始工作前**必读**，结束工作前**必更新**。
> 本文件是当前任务状态的唯一权威来源；历史决策看 docs/adr/，历史变更看 git log。

## 当前目标

把 Claude / Codex / Reasonix+DeepSeek Flash / Kimi 的跨 App 路由与单写入者交接协议固化到 VibeDevOps 技能、仓库模板和本机全局规则。

## 当前接棒状态

- 状态：待接棒
- 当前写入者：无
- App / 模型：无
- 分支：main
- HEAD：本次交接提交见 `git log -1 --oneline`
- 工作树：应为干净；接棒时以 `git status --short` 为准
- 下一棒：按具体项目任务选择，不默认启用全部模型

## 验收标准

- `vibedevops` 能由“多模型/跨 App/路由/接棒”等请求触发。
- 技能明确默认角色、单写入者、结构化接棒载荷和缓存纪律。
- 新部署的 AGENTS/HANDOFF 模板包含写入所有权与 Git 状态字段。
- 本机 `~/AGENTS.md` 对所有 coding agent 强制执行同一协议。
- 技能结构、Shell 语法、diff 检查和仓库健康检查通过。

## 已完成

- 2026-08-06：部署跨 agent 交接架构（AGENTS.md / HANDOFF / ADR / 厂商指针）
- 2026-08-09：新增多 App / 多模型路由参考、单写入者规则、结构化接棒模板，并同步本机全局规则。

## 进行中

（无）

## 已知坑 / 注意事项

- Git hook 可以强制“代码变更必须更新 HANDOFF”，但无法证明某个外部 App 实际使用了指定模型；模型路由依赖所有 App 共同遵守 `~/AGENTS.md`。
- 既有仓库不会被模板自动覆盖；需要在目标仓库显式运行 `/vibedevops 交接` 或现有部署脚本升级。

## 下一步

在一个真实项目中执行 `/vibedevops 路由`，验证下一棒能仅凭 Git + HANDOFF 接续。

## 如何验证

- `bash -n install.sh skills/vibedevops/scripts/deploy-handoff.sh skills/vibedevops/scripts/health-check.sh`
- `python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/vibedevops`
- `git diff --check`
- `./skills/vibedevops/scripts/health-check.sh --json .`

## 最近交接记录

| 日期 | 操作者 | 摘要 |
|---|---|---|
| 2026-08-09 | Codex | 固化四模型跨 App 路由与单写入者接棒协议 |
| 2026-08-06 | 部署脚本 | 初始化交接架构 |
