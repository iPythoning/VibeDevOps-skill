# VibeDevOps — vibe coding，但不放弃理解

> 触发词：`/vibedevops`、`看懂 AI 改动`、`项目地图`、`变更摘要`、`复述测试`、`交接架构`、`HANDOFF`、`生产就绪体检`
>
> 🇬🇧 [English Version](README.en.md) · 前身：`flow-skill`（`/flow` 工作流编排器，仍在本仓库 `skills/flow/`）

**vibe coding 的速度可以全拿，理解不能全丢。** VibeDevOps 把"理解"和"生产保障"从感觉变成流程和文件：

- **变更解释契约** —— 每次改动前后，AI 被迫输出可读的方案与摘要
- **三阶段理解进阶** —— 从"被动看懂"到"主动掌控"的可执行路线
- **跨 agent 交接架构** —— `AGENTS.md` + `HANDOFF.md` + ADR + 厂商指针，让理解固化进仓库，任何 agent 秒接续
- **生产级保障包** —— 密钥基线（Infisical）/ CI 三件套 / 回滚预案 / 监控清单，模板化机械防线，不靠自觉
- **`/vibedevops 体检`** —— 生产就绪 0–100 评分，一键看清你的 vibe 项目敢不敢上线

搭配本仓库的 `/flow`（工作流主干：思考→计划→实现→自检→出活→部署→复盘）使用：**flow 管"活怎么干完"，vibedevops 管"你和下一个 agent 还懂不懂这个项目"。**

---

## 一、变更解释契约（零成本，马上可用）

每次让 AI 动手，在需求后面追加这段固定指令：

> 改动前，先告诉我你打算改哪些文件、每个文件改什么、为什么，等我确认再动手。
> 改动完成后，请输出：① 变更文件清单 ② 每个文件改动的一句话说明 ③ 如果涉及多个文件，说明它们之间的调用关系 ④ 如果引入了新的目录或文件，说明它在项目结构中的位置。

配套动作：改动后跑 `git diff`，让 AI 逐段解释。diff 是性价比最高的学习材料——真实、具体、就是你自己的代码。

---

## 二、三阶段理解进阶路线

| 阶段 | 时间 | 核心 | 关键动作 |
|---|---|---|---|
| 一、让 AI 被迫"解释" | 第 1–2 周 | 不改变自己，先改变下的指令 | 上面的变更解释契约 + 逐段读 `git diff` |
| 二、建立项目地图 | 第 2–4 周 | 黑盒文件夹 → 脑子里的地图 | `tree -L 3` 概括每层职责 · 从入口沿调用链走主流程 · 画依赖框图，每次改动后更新（活文档） |
| 三、小步验证 | 第 4 周起 | 用工程习惯固化理解 | 小步提交（每个 commit 说清为什么存在）· **复述测试**（不看解释自己讲，AI 纠正）· **预测练习**（先猜会动哪几个文件，猜错即盲区） |

---

## 三、跨 agent 交接架构

对话里的理解会随上下文压缩蒸发；落盘的不会。这套架构让任何厂商的 agent（Claude / Codex / Cursor / Gemini / Windsurf / Kimi）进任何仓库都能秒接续：

| 文件 | 作用 |
|---|---|
| `AGENTS.md` | **唯一权威协作守则**：接续三步、收尾三件套、验证命令、Git 纪律、反模式。所有厂商文件只是指针，冲突时以它为准 |
| `docs/HANDOFF.md` | 交接状态板：当前目标 / 已完成 / 进行中（含文件位置）/ 已知坑 / 下一步 / 验证方式 |
| `docs/adr/` | 架构决策记录，治"忘了为什么这么改"。对话里想通但没落的决策，等于没发生过 |
| 厂商指针 | `CLAUDE.md` / `GEMINI.md` / `.cursorrules` / `.windsurfrules` / `.github/copilot-instructions.md` 全部指向同一份 AGENTS.md |

**一键部署（幂等、非破坏性）：**

```bash
# 1. 编辑脚本里的 REPOS 数组，填入你的仓库路径
# 2. 先 dry-run 看清单
./skills/vibedevops/scripts/deploy-handoff.sh --dry-run
# 3. 确认后落笔（只新增不覆盖；已有文件备份 .bak 后追加指针；每仓库单独提交可 revert）
./skills/vibedevops/scripts/deploy-handoff.sh
```

部署纪律与踩坑记录（macOS bash 3.2 `set -u` 空数组坑、`.gitignore` 忽略 `docs/` 需 `git add -f`、`index.lock` 残留等）见 [skills/vibedevops/SKILL.md](skills/vibedevops/SKILL.md)。

---

## 四、生产级保障包（上线前后的机械防线）

Vibe Coder 的典型事故不是看不懂代码，而是密钥泄露、没有 CI、上线靠祈祷、出事不会回滚。所有保障都是**模板 + 脚本 + AGENTS.md 规则**三件套——不靠自觉维持。

### 密钥与安全基线（含 [Infisical CLI](https://github.com/Infisical/cli)）

三层防线，规范全文见 [templates/security/SECRETS.md](skills/vibedevops/templates/security/SECRETS.md)：

- **进不去**：pre-commit 拦截（`infisical scan` → gitleaks → 兜底正则）；真 `.env` 永不入库
- **不集中**：本地 `infisical run --env=dev -- <启动命令>` 运行时注入、不落盘；CI 用机器身份（Universal Auth），repo secrets 只存两个凭据
- **漏了能救**：先轮换后清理（`git filter-repo`）→ 查调用日志 → 落 ADR

### CI 三件套（[templates/ci/](skills/vibedevops/templates/ci/)）

`pr-check.yml`（密钥扫描 + lint/type/test，含 Node/Python/Go 替换段）· `deploy.yml`（GitHub Environments 人工 approve + Infisical 注入 + 功能层 smoke test）· 回滚标准动作见 RUNBOOK

### 回滚与事故应急（[RUNBOOK.template.md](skills/vibedevops/templates/RUNBOOK.template.md)）

上线即留退路（先写"这步怎么 revert"）· 数据库迁移先备份 + expand-contract 两次部署 + AI 生成的破坏性 SQL 逐行人工过目 · 事故三板斧（止损→定位→blameless 5-why 复盘落 ADR）

### 监控与环境（[production-checklist.md](skills/vibedevops/templates/production-checklist.md)）

监控四件套（真实 `/health`、Sentry、可用性监控、告警到人）· 环境可复现验收标准"新机器 clone 到跑通 ≤ 5 分钟" · [renovate.json](skills/vibedevops/templates/renovate.json) 依赖周更（major 单独人工过目）

### `/vibedevops 体检` —— 生产就绪评分

对任意仓库按 7 个维度（测试 15 / CI 15 / 密钥 20 / 监控 15 / 回滚 10 / 环境 10 / 交接 15）打 0–100 分并输出缺口清单。评分规则见 [SKILL.md](skills/vibedevops/SKILL.md) 第六节。

---

## 五、/flow —— 工作流主干（原 flow-skill）

把手头零散的命令收口成一条主力链。**ponytail 全程压舱**（默认 full，动老代码/重构用 ultra），只写任务真正需要的最少代码，但绝不砍校验/错误处理/安全/可访问性。

| # | 阶段 | 目标 | 主命令 | 备选/补充 | 产出 | 关卡 |
|---|---|---|---|---|---|---|
| 0 | 压舱 | 抑制过度工程 | `/ponytail full` | 重构 `/ponytail ultra` · 探索脚本 `/ponytail lite` | — | — |
| 1 | 思考 | 把需求/方案逼清楚 | `/office-hours` | `/grill-me`（拷问计划） · `/council`（多方案抉择） | 需求/决策记录 | — |
| 2 | 计划 | 出可执行计划 | 小改 `/plan` · 新特性 `/prp-prd`→`/prp-plan` | `/autoplan`（自动跑评审，需先有 plan） | plan 文件 | ✋ 计划须你确认才动代码 |
| 3 | 实现 | 最小可用代码+测试 | `/tdd`（RED→GREEN→REFACTOR） | `/prp-implement`（plan 驱动+每步验证） | 代码+测试 commit | — |
| 4 | 自检 | 机械门+过度工程+正确性 | `/verify` → `/ponytail-review` → `/code-review` | `/quality-gate`（快速 lint/type/test） | 报告+删除清单 | ✋ 红的必须先修 |
| 5 | 出活 | commit → PR | `/prp-commit` → `/ship` | 手工 git（只 `git add -u`/逐文件） | PR | ✋✋ 出 PR 前 `git diff --stat` 自查 |
| 6 | 部署 | 上线+盯线上 | `/land-and-deploy` → `/canary` | 项目专用 deploy.sh | 生产+监控 | ✋✋✋ 部署生产必须你点头 |
| 7 | 复盘 | 沉淀+还债 | `/retro` + `/ponytail-debt` | `/benchmark`（性能回归） | 复盘+债账 | — |

**两条线（按改动体量选）：**

- **快速线**（bugfix/小改）: `0 ponytail` → `2 /plan` → `3 /tdd` → `4 /verify`+`/ponytail-review` → `5 /prp-commit`+`/ship` → `6 /land-and-deploy`+`/canary`
- **完整线**（新特性）: `0` → `1 /office-hours` → `2 /prp-prd`→`/prp-plan`（或 `/autoplan`） → `3 /tdd` 或 `/prp-implement` → `4 /code-review`+`/ponytail-review`+`/verify` → `5 /ship` → `6 /land-and-deploy`+`/canary` → `7 /retro`

**安全关卡（铁律）：** 计划未经确认不动代码 · 禁 `git add -A`，出 PR 前 `git diff --stat` 自查 · 部署生产必须明确点头，验证穿透到功能层（发真实请求看回复）。

**开源生态映射：** `/flow` 每个环节都对应成熟开源工具——计划 [adr-tools](https://github.com/npryce/adr-tools) · 实现 [Jest](https://github.com/jestjs/jest)/[pytest](https://github.com/pytest-dev/pytest) · 自检 [ESLint](https://github.com/eslint/eslint)/[SonarQube](https://github.com/SonarSource/sonarqube) · 出活 [semantic-release](https://github.com/semantic-release/semantic-release)/[changesets](https://github.com/changesets/changesets) · 部署 [Argo CD](https://github.com/argoproj/argo-cd)/[Flux](https://github.com/fluxcd/flux2) · 金丝雀 [Flagger](https://github.com/fluxcd/flagger)/[Argo Rollouts](https://github.com/argoproj/argo-rollouts) · 压测 [k6](https://github.com/grafana/k6)。`/flow` 的价值不是取代它们，而是串成一条**有安全关卡、有上下文记忆、有复盘沉淀**的完整工作流。

完整细节见 [skills/flow/SKILL.md](skills/flow/SKILL.md)。

---

## 安装

### 1. 克隆仓库

```bash
git clone https://github.com/iPythoning/VibeDevOps-skill.git
```

### 2. 安装到各 Agent

**Claude Code:**
```bash
mkdir -p ~/.claude/skills
cp -r VibeDevOps-skill/skills/vibedevops ~/.claude/skills/
cp -r VibeDevOps-skill/skills/flow ~/.claude/skills/
```

**Kimi Work / Daimon:**
```bash
# 使用 symlink 保持同步
ln -s ~/VibeDevOps-skill/skills/vibedevops \
  ~/Library/Application\ Support/kimi-desktop/daimon-share/daimon/skills/vibedevops
ln -s ~/VibeDevOps-skill/skills/flow \
  ~/Library/Application\ Support/kimi-desktop/daimon-share/daimon/skills/flow
```

**通用方式（推荐）:** 统一源 + 各 agent 目录 symlink，或直接跑一键脚本：

```bash
cd VibeDevOps-skill && ./install.sh
```

---

## 仓库结构

```
├── skills/
│   ├── vibedevops/          # 理解层 + 治理层 + 生产保障（本仓库主力）
│   │   ├── SKILL.md
│   │   ├── templates/       # AGENTS.md / HANDOFF.md / ADR / RUNBOOK / 厂商指针
│   │   │   ├── security/    # 密钥基线：SECRETS.md（含 Infisical）、pre-commit、env.example
│   │   │   ├── ci/          # pr-check.yml / deploy.yml（GitHub Actions 骨架）
│   │   │   ├── production-checklist.md  # 监控四件套 + 环境可复现
│   │   │   └── renovate.json            # 依赖更新基线
│   │   └── scripts/
│   │       └── deploy-handoff.sh   # 跨仓库批量部署（幂等，--dry-run）
│   └── flow/                # 工作流主干（原 flow-skill）
│       └── SKILL.md
├── install.sh
└── README.md / README.en.md
```

---

## 支持

如果这个项目帮到了你，欢迎支持：

<a href="https://www.buymeacoffee.com/ipythoning" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="160">
</a>

---

## 出品

<p align="center">
  <a href="https://pulseagent.io" target="_blank">
    <img src="https://img.shields.io/badge/Made%20with%20%E2%9D%A4%20by-PulseAgent-orange?style=for-the-badge" alt="PulseAgent">
  </a>
</p>

**[PulseAgent](https://pulseagent.io)** — AI Agent 驱动的产品交付平台

---

## 许可证

MIT © [iPythoning](https://github.com/iPythoning)
