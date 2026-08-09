# 交接状态 · HANDOFF（VibeDevOps-skill）

> 任何 agent 开始工作前**必读**，结束工作前**必更新**。
> 本文件是当前任务状态的唯一权威来源；历史决策看 docs/adr/，历史变更看 git log。

## 当前目标

发布 CI/CD 最佳实践版 VibeDevOps，并把本机所有 Agent 的用户级入口收敛到 `~/AGENTS.md`；PR 合并 main 即生产授权，随后自动重验、构建一次不可变制品、渐进部署、功能验证并在失败时自动回滚。

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

- `~/AGENTS.md`、VibeDevOps、Flow、中英文 README 和模板不存在“合并后再次人工批准”的冲突。
- PR workflow 具备最小权限、并发取消、secret scan、lint/type/test/build 与 Action SHA 锁定。
- push main workflow 重验合并结果，只构建一次不可变制品并记录 digest/provenance/SBOM。
- CD 使用短期身份、串行部署、功能 smoke/canary、失败自动回滚、独立 TTL 回滚租约、回滚复验和逐门禁发布证据。
- 生产体检只有检测到 push main 自动部署及 smoke/canary + failure() 回滚才给满 CI 分。
- 体检正反例 fixtures 覆盖正常 CD、注释/env 诱骗、缺少回滚、排除 main、静态不可达回滚与仅 step 级 failure guard。
- 技能结构、Shell/YAML 语法、diff 检查和仓库健康检查通过。
- 安装器在隔离 HOME fixture 中验证所有 Agent 的规则入口、skills 链接与厂商配置保留行为。

## 已完成

- 2026-08-06：部署跨 agent 交接架构（AGENTS.md / HANDOFF / ADR / 厂商指针）
- 2026-08-09：新增多 App / 多模型路由参考、单写入者规则、结构化接棒模板，并同步本机全局规则。
- 2026-08-09：安装脚本新增 OpenCode/OpenChamber 技能目录，避免图形端漏装。
- 2026-08-09：改为 OpenChamber 日常主入口、Claude 原生 App；加入任务型 fallback、失败冷却、三跳上限与缓存边界。
- 2026-08-09：注册 5 个 OpenChamber Agent；Kimi K2.7 Code、DeepSeek V4 Pro 与 OmniRoute Auto smoke test 通过，Codex/GPT 与 Kimi K3 的失败证据已记录。
- 2026-08-10：按 CI/CD 最佳实践统一“合并 main 即授权”，补齐不可变制品、provenance/SBOM、OIDC、渐进验证、自动回滚复验、可续租 TTL 回滚租约、原子完成发布与逐门禁证据。
- 2026-08-10：安装器新增全局规则收敛，将 Claude/Codex/OpenCode/Cursor/Gemini/Qwen/Windsurf 指向 `~/AGENTS.md`，并用隔离 fixture 防止覆盖厂商专属配置。
- 2026-08-10：已在本机执行新安装器；OpenCode/OpenChamber 全局入口直链 `~/AGENTS.md`，Claude import 唯一，9/9 skills surface 校验通过，原 Claude 配置已生成可恢复备份。

## 进行中

（无）

## 已知坑 / 注意事项

- Git hook 可以强制“代码变更必须更新 HANDOFF”，但无法证明某个外部 App 实际使用了指定模型；模型路由依赖所有 App 共同遵守 `~/AGENTS.md`。
- OmniRoute `auto/best-coding` 实测可用且落到 LongCat，但插件 `/api/combos` 仍报 403；只作为最后保障，不作为固定四模型链。
- OpenChamber 的 Codex/GPT 路由本次 smoke test 不可用；修复凭证/地区前继续使用 Codex 原生 App。
- OpenCode Agent 一次只能绑定一个模型；硬额度错误发生在模型响应前时，需在 OpenChamber 一键选择下一 Agent。只有 OmniRoute Combo 能在单请求内自动降级。
- 既有仓库不会被模板自动覆盖；需要在目标仓库显式运行 `/vibedevops 交接` 或现有部署脚本升级。

## 下一步

将更新后的 CI/CD 模板应用到具体生产仓库；按 `references/ci-cd-best-practices.md` 补齐验证、OIDC、last-known-good/arm-rollback/renew-rollback/canary/promote/complete-deployment/rollback、功能门、指标门和告警脚本。回滚租约必须由 Actions runner 之外的部署控制器持有。

## 如何验证

- `bash -n install.sh skills/vibedevops/scripts/deploy-handoff.sh skills/vibedevops/scripts/health-check.sh skills/vibedevops/scripts/test-health-check.sh skills/vibedevops/scripts/test-install.sh`
- `./skills/vibedevops/scripts/test-health-check.sh`
- `./skills/vibedevops/scripts/test-install.sh`
- `actionlint skills/vibedevops/templates/ci/pr-check.yml skills/vibedevops/templates/ci/deploy.yml`
- `python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/vibedevops`
- `git diff --check`
- `./skills/vibedevops/scripts/health-check.sh --json .`

## 最近交接记录

| 日期 | 操作者 | 摘要 |
|---|---|---|
| 2026-08-10 | Codex | 按最佳实践修正合并授权边界并补齐自动 CI/CD 安全链 |
| 2026-08-09 | Codex | 改为 OpenChamber 优先并加入按任务类型的有限 fallback |
| 2026-08-09 | Codex | 固化四模型跨 App 路由与单写入者接棒协议 |
| 2026-08-06 | 部署脚本 | 初始化交接架构 |
