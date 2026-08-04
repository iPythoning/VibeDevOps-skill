---
name: vibedevops
description: Vibe coding 但不放弃理解，生产级 DevOps 保障。触发词 /vibedevops、看懂 AI 改动、项目地图、变更摘要、复述测试、交接架构、HANDOFF、AGENTS.md、密钥泄露、Infisical、CI 模板、回滚预案、事故复盘、上线监控、生产就绪体检。把"被动看懂 AI 写的代码"升级为"主动掌控项目"：变更解释契约 + 三阶段理解进阶 + AGENTS.md/HANDOFF/ADR 跨 agent 交接架构 + 密钥/CI/回滚/监控机械防线（模板化，不靠自觉）+ /vibedevops 体检生产就绪评分。通用于所有项目与所有厂商 agent。
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

三层防线，规范全文见 `templates/security/SECRETS.md`：

- **进不去**：`templates/security/pre-commit` 提交前拦截（Infisical `infisical scan` → gitleaks → 兜底正则）；`.env.example` 入库、真 `.env` 永不入库
- **不集中**：[Infisical CLI](https://github.com/Infisical/cli) 托管密钥，本地 `infisical run --env=dev -- <启动命令>` 运行时注入、不落盘；CI 用机器身份（Universal Auth），repo secrets 只存两个凭据
- **漏了能救**：先轮换后清理（`git filter-repo`）→ 查调用日志 → 落 ADR
- 兜底：GitHub Secret scanning + Push protection + Dependabot 打开

### 4.2 CI 三件套（`templates/ci/`）

- `pr-check.yml`：密钥扫描 + lint/type/test，PR 必过（含 Node/Python/Go 三语言注释替换段）
- `deploy.yml`：main 合并后部署，挂 GitHub Environments 人工 approve；Infisical 注入密钥；部署后 smoke test **穿透到功能层**
- 回滚标准动作：见 RUNBOOK

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
- **补验欠账**：LOCAL 兜底通过 ≠ 结案，只是欠账。记录进队列，构建机恢复后由 cron（`reverify.sh`）自动复验销账；**欠账未销的 commit 禁止发布**。
- **镜像走私有 registry**：构建机不依赖公共镜像加速器——在网络通畅的机器上 build/push builder 镜像（如 GHCR），构建机只 pull；依赖源烤进镜像 + 缓存卷。
- **代理规避纪律**：内网/隧道目标一律 IP + ssh alias（必要时 `BindInterface` 绑物理网卡），脚本里禁止裸域名；靠绕，不靠改代理工具配置。

模板与部署说明：`templates/build-gate/`（bash 3.2 兼容，macOS 自带 bash 可直接跑）。

## 五、与 /flow 的关系

`/flow`（见 `../flow/SKILL.md`）是**工作流主干**：思考→计划→实现→自检→出活→部署→复盘，带安全关卡。VibeDevOps 是**理解层与治理层**：flow 管"活怎么干完"，vibedevops 管"你和下一个 agent 还懂不懂这个项目、敢不敢让它上线"。两者共用同一套安全关卡（计划须确认 / 出 PR 前 `git diff --stat` / 部署必须点头）。

## 六、调用 /vibedevops 时的编排行为

- **无参数**：探测当前仓库交接健康度（有无 AGENTS.md / HANDOFF.md / ADR / 验证命令是否已填），给出缺口清单和下一步。
- **`/vibedevops 地图`**：执行阶段二——扫目录结构、找入口、沿调用链走主流程，输出带注释的项目地图。
- **`/vibedevops 交接`**：在当前仓库部署交接架构（先 `--dry-run` 给清单，确认后落笔）。
- **`/vibedevops 复述`**：基于最近的 git diff / commit，向用户提问"这次改了什么、为什么"，纠正其复述。
- **`/vibedevops 体检`**：生产就绪评分（0–100），按下表逐项探测、输出得分与缺口清单：

| 维度 | 分值 | 判定规则 |
|---|---|---|
| 测试 | 15 | 有测试目录/配置且验证命令非"待补充" |
| CI | 15 | `.github/workflows/` 存在 PR 检查 + 部署流（各半） |
| 密钥 | 20 | `.env` 在 gitignore（5）+ 无密钥入库痕迹（10，`git log -p` 抽样 / 跑 infisical scan）+ 有注入方案（5） |
| 监控 | 15 | `/health` 真实依赖检查 + 错误追踪接入（按实现度给分） |
| 回滚预案 | 10 | RUNBOOK 存在且含回滚/备份步骤 |
| 环境可复现 | 10 | 版本锁定文件 + README 有 5 分钟跑通说明 |
| 交接文件 | 15 | AGENTS.md / HANDOFF.md / ADR 齐备且非模板未填状态 |

- 执行原则：扫描与解释无副作用可直接做；**写入交接文件、git init、批量部署前必须给用户确认清单**。
