# 推广物料包（promotion kit）

发布节奏建议：每周一篇长文 + 配套短帖，三周打完第一轮。每篇长文发掘金/知乎/公众号，短帖发即刻/LinuxDo/V2EX/X。

---

## 一、短帖模板（即刻 / LinuxDo / V2EX / X）

### 帖子 1：配合长文 01（Stripe 绿灯）

**即刻/短版：**

> 付费客户 $99 的服务断了 9 天，我的 5 个监控全是绿灯。
> Stripe 把 301 重定向也算"投递成功"，请求根本没到我的应用。
> 固化成一条铁律：绿标/200/状态字段都不是功能验证，验证必须穿透到应用本体的签名校验层。
> 顺手开源了个 30 秒体检脚本，给你的 vibe coding 项目打个分（0–100 + 缺口清单）：
> https://github.com/iPythoning/VibeDevOps-skill

**V2EX/LinuxDo 版标题**：`[分享] 付费客户的服务断了 9 天监控全绿：vibe coding 项目的验证纪律`

### 帖子 2：配合长文 02（CI 静默死亡）

> GitHub Actions 免费额度 2000 分钟/月，我 7 月用了 2597。
> 超额之后 CI 不报错、不提醒，直接静默不跑——"没看到红的就是好的"这个习惯会让未验证的代码一路绿灯上生产。
> 解法：把"在哪验证"变成显式路由——CI → 构建机 → 本机兜底，自动降级 + 证据落盘，本机兜底算欠账，构建机恢复自动复验销账。
> 模板开源（bash 3.2 兼容）：https://github.com/iPythoning/VibeDevOps-skill

### 帖子 3：配合长文 03（多 agent 交接）

> 我用 Claude / Codex / Cursor / Kimi 轮换开发 65 个仓库，最大的敌人是失忆。
> 写进 .claude/ 的上下文，换 Codex 就失明——交接只能靠仓库里的厂商中立文件：AGENTS.md + HANDOFF.md + ADR。
> 再加一个 pre-push 钩子：改了代码没更新 HANDOFF 就不让 push。自觉不可靠，护栏才可靠。
> 模板和部署脚本开源：https://github.com/iPythoning/VibeDevOps-skill

### 帖子 4：体检钩子（随时可发）

> 给你的 vibe coding 项目做个体检？
> 一条命令，7 个维度（测试/CI/密钥/监控/回滚/环境/交接）打 0–100 分 + 缺口清单：
> `curl -fsSL https://raw.githubusercontent.com/iPythoning/VibeDevOps-skill/main/skills/vibedevops/scripts/health-check.sh | bash -s -- /path/to/repo`
> 我自己的主力仓库实测 81/100，缺口是 RUNBOOK 和验证命令。低于 60 分的，出事只是时间问题。

---

## 二、awesome 列表 PR 文案

目标列表（提交前逐个确认收录标准与分区，别海投）：

- https://github.com/hesreallyhim/awesome-claude-code （Skills / Tooling 区）
- https://github.com/steipete/agent-rules （或 AGENTS.md 相关 awesome 列表，提交前先搜 "awesome agents.md" 确认当前活跃的那个）
- https://github.com/e2b-dev/awesome-ai-agents （如接受 tooling/skill 类）

PR 标题：`Add VibeDevOps — handoff protocol & production guardrails for AI coding agents`

PR 正文：

```markdown
**VibeDevOps** — an agent skill that treats "understanding AI-written code" and "production readiness" as process, not vibes.

- Cross-agent handoff protocol: AGENTS.md + HANDOFF.md + ADR + vendor pointer files, with an idempotent deploy script and a pre-push hook that blocks code pushes without HANDOFF updates
- Production guardrail templates: secrets baseline (Infisical), CI trio (PR check / deploy with manual approve / smoke tests that verify at the functional layer), rollback RUNBOOK
- `health-check.sh`: one-command 0–100 production-readiness score for any git repo, with a gap list
- build-gate: three-tier build routing (cloud CI → dedicated builder → local fallback) with evidence logging and automatic re-verification — built for CI quota exhaustion and unreliable networks

Repo: https://github.com/iPythoning/VibeDevOps-skill (MIT, bilingual zh/en)
```

---

## 三、发布渠道清单

| 渠道 | 内容形态 | 备注 |
|---|---|---|
| 掘金 | 长文 01/02/03 | 标签：前端/AI/开源；首发选工作日上午 |
| 知乎 | 长文（找「AI 编程」「Claude Code」相关问题挂回答） | 回答比文章流量大 |
| 即刻 | 短帖 1–4 | AI 探索站圈子 |
| LinuxDo / V2EX | 短帖 + 仓库链接 | 标题用事故，不用项目名 |
| 微信公众号 | 长文 | 如有号 |
| X / Reddit (r/ClaudeAI, r/cursor) | 长文 02/03 的英文摘要 + 链接 | 等英文版 SKILL.md 之后效果更好 |

## 四、口径纪律（所有物料统一）

- 叙事顺序永远是：**事故 → 根因 → 机械防线 → 仓库链接**，不发"我开源了一个项目"
- 数据只用真实发生过的（2597 分钟、9 天、65 仓库、主力仓库体检 81 分），不编造
- 成功指标口径：回链数（多少仓库的 AGENTS.md 加了指针）> star 数
