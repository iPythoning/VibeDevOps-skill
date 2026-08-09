---
name: vibedevops
description: Vibe coding 但不放弃理解，生产级 DevOps 保障。用于 /vibedevops、看懂 AI 改动、项目地图、变更摘要、复述测试、跨 App/多模型路由、Claude/Codex/Reasonix/Kimi 切换、交接架构、HANDOFF、AGENTS.md、密钥泄露、CI、回滚、监控和生产就绪体检。提供变更解释契约、单写入者多模型工作流、AGENTS.md/HANDOFF/ADR 跨 agent 交接架构，以及模板化机械门禁。通用于所有项目与所有厂商 agent。
---

# VibeDevOps — vibe coding，但不放弃理解

核心理念：**vibe coding 的速度可以全拿，理解不能全丢。** 理解不是看懂每一行代码，而是始终能回答四个问题——改了什么、为什么改、动了哪里、怎么验证。这套 skill 把"理解"从感觉变成流程和文件。

## 一、变更解释契约（每次改动都生效，零成本）

每次让 AI 动手，在需求后面追加这段固定指令：

> 改动前，先告诉我你打算改哪些文件、每个文件改什么、为什么，等我确认再动手。
> 改动完成后，请输出：① 变更文件清单 ② 每个文件改动的一句话说明 ③ 如果涉及多个文件，说明它们之间的调用关系 ④ 如果引入了新的目录或文件，说明它在项目结构中的位置。

配套动作：**改动后跑 `git diff`，让 AI 逐段解释。** diff 是性价比最高的学习材料——真实、具体、就是你自己的代码。

## 二、三阶段理解进阶路线

### 阶段一：让 AI 被迫"解释"（第 1–2 周）

不改变自己，先改变下的指令——即上面的变更解释契约。目标是每次改动都留下可读的解释痕迹。

### 阶段二：建立项目地图（第 2–4 周）

把"黑盒文件夹"变成脑子里的地图：

1. **跑结构**：`tree -L 3`，让 AI 用一句话概括每层目录的职责。
2. **找入口**：每个项目都有入口（`main.py` / `index.ts` / `App.vue`…），从入口顺着 import / 调用链走一遍主流程。
3. **画一张图**：核心文件 + 依赖关系画成框图（手绘也行），贴在旁边。**每次改动后更新它——这就是活文档。**

### 阶段三：小步验证（第 4 周起）

用工程习惯把理解固化下来：

- **小步提交**：一个功能拆成多个 commit，每个 commit 都能说清"这一步为什么存在"。
- **复述测试**：改完后不看 AI 的解释，自己向 AI 复述"改了什么、为什么这么改"，让 AI 纠正。**能讲出来才算懂。**
- **预测练习**：提需求前先猜"这大概会动哪几个文件"，再和实际改动对比。猜错的地方就是知识盲区。

## 三、交接架构：把理解固化进仓库

对话里的理解会随上下文压缩蒸发；落盘的不会。这套架构让**任何厂商的 agent（Claude / Codex / Cursor / Gemini / Windsurf / Kimi）进任何仓库都能秒接续**：

| 文件 | 作用 |
|---|---|
| `AGENTS.md` | **唯一权威协作守则**：接续三步（开始前）、收尾三件套（结束前）、验证命令、Git 纪律、反模式。所有厂商文件只是指针，冲突时以它为准 |
| `docs/HANDOFF.md` | 交接状态板：当前目标 / 已完成 / 进行中（含文件位置）/ 已知坑 / 下一步 / 验证方式。任何 agent 上手先读它 |
| `docs/adr/` | 架构决策记录（ADR），治"忘了为什么这么改"。对话里想通但没落的决策，等于没发生过 |
| 厂商指针 | `CLAUDE.md` / `GEMINI.md` / `.cursorrules` / `.windsurfrules` / `.github/copilot-instructions.md` —— 无论谁进来，都被指向同一份 AGENTS.md |

模板见 `templates/`，一键部署脚本见 `scripts/deploy-handoff.sh`（幂等、支持 `--dry-run`）。

**接续三步（agent 开始工作前必做）：**
1. 按固定顺序读：`README* → AGENTS.md → docs/HANDOFF.md → docs/adr/ → git log -10 --oneline`
2. 先跑一次验证命令确认基线是绿的；**基线红 → 先修基线，绝不在红基线上叠改动**
3. 用自己的话复述当前任务与验收标准，确认与 HANDOFF 一致后再动手

**收尾三件套（结束工作前必做）：**
1. 跑完整验证命令，确认全绿
2. 更新 `docs/HANDOFF.md`
3. 提交 git，不留未提交的半成品

### 多 App / 多模型切换

把 App 视为无状态入口，把 Git、`AGENTS.md` 和 `docs/HANDOFF.md` 视为状态机。详细角色路由与接棒格式见 `references/model-routing.md`。

必须遵守：

1. 一个分支/工作树同一时刻只有一个写入者；其他模型只读审查。
2. 换 App 前先验证、更新 HANDOFF、提交；下一棒从该 commit 接续。
3. HANDOFF 记录当前写入者、App/模型、分支与 HEAD、验收标准、验证证据、fallback 状态和下一棒唯一动作。
4. 不复制整段聊天历史；只传仓库事实、决策、证据和必要视觉素材。
5. 需要并行写入时使用不同 worktree 和不同分支，合并前由一个主工程负责人收口。

**部署纪律（跨仓库批量部署时）：**
- 只新增、不覆盖；已存在的厂商文件备份（`.bak`）后追加指针块
- 每个仓库单独提交（消息含"交接架构"），可随时 `git revert` 回滚
- 工具厂商自管的内部仓库（`.codex/`、`.claude/` 等）**跳过**，动了会搞坏工具
- 没有 git 的目录这套架构立不住，先 `git init` 再部署

**踩过的坑（部署脚本作者注意）：**
- macOS 自带 bash 3.2 下 `set -u` 对空数组展开误报 unbound variable——不要用 `set -u`，用 `${arr[@]+"${arr[@]}"}` 防御式展开
- `.gitignore` 忽略整个 `docs/` 时交接文件会被漏掉——提交用 `git add -f`，文件一旦被跟踪即恢复正常跟踪
- 部署前检查 `.git/index.lock` 残留（确认无进程后清除）
- bash 3.2 下 `$VAR` 后紧跟全角字符（；，：（）等）会被吞进变量名，`set -u` 时报 unbound variable——shell 里变量后接中文一律 `${VAR}`

## 四、生产级保障包（上线前后的机械防线）

Vibe Coder 的典型事故不是看不懂代码，而是密钥泄露、没有 CI、上线靠祈祷、出事不会回滚。所有保障都做成**模板 + 脚本 + AGENTS.md 规则**三件套——不靠自觉维持，自觉是最不可靠的关卡。

### 4.1 密钥与安全基线（第一事故源）

防线按**依赖成本从零到高**排列（规范全文见 `templates/security/SECRETS.md`）——机械防线不能建立在"用户记得装某个工具"上：

- **第 0 层（零安装）**：GitHub Secret scanning + Push protection 打开——服务端强制，装不上/被忘/换机器都不影响，所以排第一
- **第 1 层（单二进制）**：`templates/security/pre-commit` 提交前拦截（gitleaks → Infisical（如已装）→ 兜底正则）；`.env.example` 入库、真 `.env` 永不入库
- **第 2 层（solo/小团队默认）**：sops + age 把部署密钥**加密进 git**（模板 `templates/security/sops.yaml`）——零服务依赖、离线可用、密钥与代码同生命周期；repo secrets 收敛为一个 age 私钥
- **漏了能救**：先轮换后清理（`git filter-repo`）→ 查调用日志 → 落 ADR
- **团队化之后**才升级 [Infisical](https://github.com/Infisical/cli)（集中托管 + 按权限分发 + 运行时注入，需要云或自托管后端）；升级条件与 CI 机器身份用法见 SECRETS.md 第八节。**同时跑两套密钥体系比没有体系更糟，二选一**

### 4.2 CI 三件套（`templates/ci/`）

- `pr-check.yml`：密钥扫描 + lint/type/test，PR 必过（含 Node/Python/Go 三语言注释替换段）
- `deploy.yml`：PR 合并进 main 后重验合并结果、构建一次带 provenance/SBOM 的不可变制品，以 OIDC 短期身份自动部署；功能层 smoke/canary 失败自动回滚并复验
- 回滚标准动作：见 RUNBOOK

**授权边界：PR 合并就是生产部署授权。** 审核、CI 和发布时间决策都在合并前完成；合并后不得再次等待人工 approve。`workflow_dispatch` 只用于重试、回滚和事故恢复，不能成为正常发布的唯一入口。需要等待发布时间窗口时延迟合并 PR。

完整流水线、不可变制品、渐进发布、OIDC、供应链锁定和观测指标见 `references/ci-cd-best-practices.md`。

### 4.3 回滚与事故应急（`templates/RUNBOOK.template.md`）

- **上线即留退路**：每次部署前写下"这步怎么 revert"；`git revert` 优先于修复 patch
- **数据库变更纪律**：迁移前一行命令备份；expand-contract 拆两次部署；AI 生成的 `DROP`/全表 `ALTER`/`UPDATE` 必须逐行人工过目
- **事故三板斧**：止损（回滚/降级）→ 定位（Sentry → 日志 → 最近 `git log`）→ 复盘（blameless 5-why，产出 ADR）

### 4.4 监控与环境（`templates/production-checklist.md`）

- 监控四件套：`/health` 返回依赖真实状态（禁硬编码 200）、Sentry、可用性监控、告警到人
- 环境可复现：版本锁定文件 + 安装一条命令 + `infisical run` 拿密钥；验收标准"新机器 clone 到跑通 ≤ 5 分钟"
- 依赖更新：`templates/renovate.json`——非 major 分组周更，major 单独 PR 人工过目

### 4.5 弱网 / 资源受限环境：降级路由与补验欠账（`templates/build-gate/`）

中国开发者的典型组合：本机性能有限、CI 免费额度会耗尽且**静默失败**、自建构建机连通不稳、代理工具抢路由、拉境外镜像慢。对策不是"找一台更强的机器"，而是把"在哪验证"变成显式机制：

- **机器角色锁死**：开发机只做内循环（受影响测试 + 类型检查）；专用构建机做全量验证；生产机只拉已验证制品、绝不构建。角色写死，每台机器的资源消耗才有上限。
- **三级路由门禁**：CLOUD（CI）→ BUILDER（专用构建机）→ LOCAL（本机兜底），自动降级，三条路跑同一条命令、写同一份 `docs/BUILD-EVIDENCE.md`，区别只在证据强度标注。**CI 额度查不到时按不足处理——"以为 CI 在跑其实没跑"是最危险的静默失败。**
- **构建时限铁律**：任何门禁 `GATE_TIMEOUT`（默认 600s）机械强制，超时强杀、证据记耗时。超时 = 修构建（缓存/依赖/拆分），不许调大上限。
- **补验欠账（去 cron 化）**：LOCAL 兜底通过 ≠ 结案，只是欠账。记录进队列，销账内嵌在 build-gate 启动路径——之后任何一次构建自动补验（构建越勤销得越快，不依赖 cron 也不怕机器睡眠）；**欠账未销的 commit 禁止发布**。
- **镜像走私有 registry + 依赖源运行时注入**：构建机不依赖公共镜像加速器——builder 镜像在网络通畅的机器 build/push（如 GHCR），构建机只 pull（公共 Docker Hub 在部分网络下完全不可达）；npm/pip 源用环境变量运行时注入 + 命名缓存卷（脚本内置），通用官方镜像即插即用，免重烤。
- **构建机 docker 一律 `--network host`**：NAS/品牌小主机的 docker 常由厂商托管，docker0 默认桥不存在是常态——显式 host 网络让桥状态与构建无关，也绝不重启这类机器的 docker daemon。
- **代理规避 + 双路径 ssh**：构建机配 overlay 网络（Tailscale 类）为主、局域网 IP 兜底的双 alias（CGNAT `100.64/10` 段必须走虚拟网卡，绝不绑物理网卡；局域网路径反之）；脚本里禁止裸域名和 `root@IP`；靠绕，不靠改代理工具配置。

模板与部署说明：`templates/build-gate/`（bash 3.2 兼容，macOS 自带 bash 可直接跑）。

## 五、与 /flow 的关系

`/flow`（见 `../flow/SKILL.md`）是**工作流主干**：思考→计划→实现→自检→出活→部署→复盘，带安全关卡。VibeDevOps 是**理解层与治理层**：flow 管"活怎么干完"，vibedevops 管"你和下一个 agent 还懂不懂这个项目、敢不敢让它上线"。两者共用同一套安全关卡：计划须确认、出 PR 前 `git diff --stat`、PR CI 全绿才合并；合并 main 后由 CD 自动部署、验证和失败回滚。

## 六、调用 /vibedevops 时的编排行为

- **无参数**：探测当前仓库交接健康度（有无 AGENTS.md / HANDOFF.md / ADR / 验证命令是否已填），给出缺口清单和下一步。
- **`/vibedevops 地图`**：执行阶段二——扫目录结构、找入口、沿调用链走主流程，输出带注释的项目地图。
- **`/vibedevops 交接`**：在当前仓库部署交接架构（先 `--dry-run` 给清单，确认后落笔）。
- **`/vibedevops 路由`**：读取 `references/model-routing.md`，按任务风险、视觉依赖、上下文规模和成本选择主模型与专项审查者；不默认让四个模型全部参与。
- **`/vibedevops fallback`**：读取 `references/model-routing.md`，先区分额度/限流/上游故障与请求/代码错误；只对前者按任务类型执行有限 fallback，并把失败模型、证据、下一跳和冷却状态写入 HANDOFF。
- **`/vibedevops 接棒`**：核对工作树、当前写入者、分支/HEAD、验收标准和验证证据；接棒条件不满足时停止写入并报告缺口。
- **`/vibedevops 复述`**：基于最近的 git diff / commit，向用户提问"这次改了什么、为什么"，纠正其复述。
- **`/vibedevops 体检`**：生产就绪评分（0–100），按下表逐项探测、输出得分与缺口清单。评分不止是报告，`scripts/health-check.sh --min <分数>` 低于阈值退出码 1，可直接挂 pre-push / CI 当门禁——分数不够拦下，不靠自觉：

| 维度 | 分值 | 判定规则 |
|---|---|---|
| 测试 | 15 | 有测试目录/配置且验证命令非"待补充" |
| CI | 15 | PR 检查（8）+ push main 自动部署（4）+ 功能 smoke/canary 与失败自动回滚（3） |
| 密钥 | 20 | `.env` 在 gitignore（5）+ 无密钥入库痕迹（10，`git log -p` 抽样 / 跑 gitleaks）+ 有注入或加密方案（5，sops+age / Infisical 任一） |
| 监控 | 15 | `/health` 真实依赖检查 + 错误追踪接入（按实现度给分） |
| 回滚预案 | 10 | RUNBOOK 存在且含回滚/备份步骤 |
| 环境可复现 | 10 | 版本锁定文件 + README 有 5 分钟跑通说明 |
| 交接文件 | 15 | AGENTS.md / HANDOFF.md / ADR 齐备且非模板未填状态 |

- 执行原则：扫描与解释无副作用可直接做；**写入交接文件、git init、批量部署前必须给用户确认清单**。
