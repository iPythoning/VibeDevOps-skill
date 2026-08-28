# 交接状态 · HANDOFF（VibeDevOps-skill）

> 任何 agent 开始工作前**必读**，结束工作前**必更新**。
> 本文件是当前任务状态的唯一权威来源；历史决策看 docs/adr/，历史变更看 git log。

## 2026-08-28 · 能力尽调（8-agent 证伪）+ 拆掉一颗活雷

**触发**：老板问"这套工具链真的治理好了还是一直打补丁 / 能否迁移 / 能否商业化"。跑了 8-agent
证伪导向尽调（5 路取证 + 3 路证伪，1.29M tokens）。完整报告（七维成熟度 / 返工趋势 / 逐层可迁移性 /
五路径商业化排序，全部结论附可机械复验证据）见 Artifact：
https://claude.ai/code/artifact/19fd01b3-1d3f-400d-bebf-9c447d10c82d
**一句话结论**：成熟度 **1.9/5「成型工具链」**——在从打补丁往真治理过渡，但没到；缺的是
**ADR ↔ templates ↔ 运行体的机械对账**。它作为个人杠杆/求职作品集是成功的，作为产品会输得难看。

### ✅ 已处理 · P0：拆掉 runner-failover 的恢复回切炸弹（完成）
- **炸弹**：`agents-toolchain/scripts/runner-failover.sh` 在 `state.managed=true` 时，一旦 hosted
  探针返回 `completed/success`，就对全部纳管仓逐个 `del_bundle` 清空 `CI_RUNNER/CD_RUNNER` 等路由
  变量。实测 state 确为 managed=true / **42 仓** / 三哨兵（PulseAgent·paibaowork-emdash·pulseagent-io-site）
  均有 CI_RUNNER → `in_failover` 恒真，launchd 每 10min 都走到该分支；探针 205 次运行 0 成功，只差某次
  GitHub 免费额度月度重置偶然成功即触发，且该路径**从未成功执行过一次**（首次运行即在 42 生产仓上，
  无 dry-run/测试/二次确认）。
- **修复**（agents-toolchain `af7dd3c`，已 push main）：移除回切动作 + 每小时探针 dispatch（纯烧
  API），保留 `infra_heal` 断连自愈；`runner-failover-state.json` 的 `managed` 置 false 作数据层
  防线（防模板回灌/脚本回退重新上膛）。实测：手动跑一次 exit 0、无删除、无探针、42 仓变量完好。
- **⚠️ 未处理 twin（P0 follow-up）**：本仓模板 `templates/ci/runner-failover.sh` 仍含同一炸弹。
  谁 `install.sh` / 同步该模板到自建机并置 managed=true 就重新上膛。**同步前必须先剔除同一分支。**

### ✅ 已完成 · P1：三处"自打脸"全修 + 合并 + main 绿（2026-08-28）
PR #24（`f97db5b`）+ PR #25（`a6f64e4`）已合并，main CI 全绿。
1. **ADR 0009 金丝雀已落地**：`ci.yml` 的 secrets job 与模板 `pr-check.yml` 的 secrets-scan job 各加
   门禁自证——下载同版本 gitleaks（pinned sha256 + arch 自适应）扫一个随机假 `ghp_` token，扫不出即
   `exit 1`。**CI 实证金丝雀步骤 success**（本地先证：`ghp_` 5/5 确定性检出；随机 AWS 键实测漏检已弃用）。
2. **四处 `runs-on` 变量路由**：`ci.yml` 四处 → `${{ vars.CI_RUNNER && fromJSON(...) || 'ubuntu-latest' }}`
   （完整性扫描又补了第 4 处 `image-retention.yml`）。`onboard-heartbeat.yml`/`hosted-canary.yml` 的硬编码是
   刻意例外，未动。
3. **去 `--if-present`**：模板 `pr-check.yml` 改为显式 `npm pkg get` 判定 + `::notice` 明示跳过。

**⚠️ 修复过程中挖出并已处理的两个连带问题：**
- **CI 打分器静默假红（PR #25 已修）**：`health-check.sh` 的 `inspect_ci_workflows` 消费方
  `2>/dev/null || CI_FACTS=""` + 精确匹配，把 ruby 任何抖动静默变成假 0/15（正是 ADR 0009 §5 反面）。
  改哨兵前缀提取 + 重试 + `unsafe_load_file`，加守卫测试（反向变异：旧码 CI=0、新码 15）。
- **本 public 仓被 onboard-reconcile 误路由到无 ruby 的 xserver → CI 假红**：已 unset CI_RUNNER +
  把 `VibeDevOps-skill` 写入 xserver `onboard-skip.txt`（`/etc` + `/lzcsys` 持久副本），回落 hosted。

**🔭 系统性问题：**
- ✅ **已修**：`onboard-reconcile` 枚举加 `.private==true`（覆盖 private+internal，排除 public）——public 仓
  有免费 hosted，不再上 xserver 车道。三处同步：模板（本仓 PR #26 `6c0312d`）+ 运行体 `/usr/local/sbin/onboard-reconcile`
  + 持久源 `iPythoning/xserver-bootstrap` `6de5e03`。守卫测试加 `repo-public` 夹具（反向变异实证）。
  线上实证：枚举从 55 仓（含 24 public）收敛到 31 private，VibeDevOps-skill 已排除。
- ✅ **已修**：xserver 装 ruby——`apt-packages-ours.txt` 加 `ruby`（开机 bootstrap 自动补装，跨重启持久），
  运行时已装 ruby 3.1.2 (Psych 4.0.3)。功能实证：xserver 上跑 `inspect_ci_workflows` 的 ruby（含 PR #25 的
  `unsafe_load_file`）输出 `CI_FACTS 1 0 0`，打分器不再假 0/15。持久源 `xserver-bootstrap` `37475f4`。
- ✅ **已修**：onboard-skip 跨重启持久——`bootstrap.sh` step2 加 `install onboard-skip.txt → /etc/onboard-skip.txt`，
  git-tracked `onboard-skip.txt` 为源，开机播种到服务读的 `/etc`（易失）。同 commit `37475f4`。
  **新增 skip 项写进 xserver-bootstrap 仓的 `onboard-skip.txt` 并提交**（不要只改 /etc，重启即失）。

### ✅ 根因 · P1 已治理：ADR↔templates↔运行体 机械对账（ADR 0012，PR #27 `e45c915`）
原缺口：**没有任何机制在对账"ADR 决策 ↔ templates 实现 ↔ 运行体"**，12 条 ADR 全靠人记得实现，已 3 条落空。
已落地机制（CI 必过 + 自守卫）：
- `docs/adr/checks/*.sh` 可执行不变量校验，锁死刚修的三处防回归（0006 无写死 runs-on / 0009-§1 金丝雀 /
  0009-§2 无 --if-present / 0012 对账自己挂 CI）。
- `check-adr-compliance.sh` 跑全部 checks + **强制覆盖**：每条 ADR 要么有 `checks/NNNN-*.sh` 要么在
  `EXEMPT.tsv`——**新 ADR 两者都缺即 CI FAIL**，逼「决策与校验同生」。
- `test-adr-compliance.sh` 反向变异守卫，5 处变异全被抓（判据写错的解药）。
- `check-runtime-drift.sh` + `runtime-drift-manifest.tsv`：templates↔运行体跨仓漂移报告（不进 CI，需本地克隆）。
  **新增 skip/ADR 或改运行体脚本后，跑一次它看漂移**。实测 runner-failover 模板 vs ~/.agents 漂移 +111/-123 行。
- **后续可扩**：0009 §3/§4 等难 grep 的条款仍靠 review；跨仓 PAT 就绪后 runtime-drift 可升级为定时 CI 对账；
  `ci.yml` 的 `bash -n` 仍是手工清单（审计旧账，可换 `find`）。

### 📦 P2：模板 ≠ 真身（可迁移性/可售性的根）
`templates/` 与实际在跑的 `~/.agents/scripts/` 已漂移 117–299 行（runner-failover 237 / cd-lane 164 /
net-adaptive 141 / onboard-repo 89），且本机版有 19 处硬编码基础设施（`100.82.86.40`、`/lzcsys/data`、
ssh 别名）从没进模板。跑通 22 仓的没开源，开源的 forks=0 从没在第二台机跑通。**迁移分层**：约定层 +
`health-check.sh` 今天可用（<1h，8/8 守卫测试跨机通过）；完整自建 CD 是周级、需两台专用机器。

### 💰 商业化（老板决策项，非工程任务）
护城河≈0（代码 2-3 周可复刻）；12 条 ADR 仅 0009/0011 跨环境普适（17%），其余是中国车道/个人账号/
拒付 CI 费三重约束的产物；创始动机（拒付 CI 费）与卖点自相矛盾；26 天 2 star / 0 fork。
**建议：不做产品，把方法论翻英文公开 → 声誉 / staff offer / 咨询**（路径排序见 Artifact）。
**明确不做 SaaS**（6-9 月全职、资产复用<15%、solo 胜率 5-10%）。

## 当前目标

v1.7.0 验证自治（ADR 0011）已完成，PR #14 待合并。

**四层交付物**（全部实测驱动，不是纸面模板）：
- `templates/verification/verify-web.sh` — 常态门禁：打开页面采 console/失败请求/
  性能内存/截图，越界非零退出。**修过一个会漏首屏错误的真 bug**（导航后才 enable，
  CDP 只推订阅之后的事件）——修正后同一生产站点 console 错误从 0 变 4。
- `templates/verification/capture-trace.sh` — 诊断：CPU trace（681KB/2743 事件）与
  heap snapshot（32MB/406422 节点），可直接进 DevTools。不进常态门禁。
- `templates/verification/feature-map.template.yaml` + `check-feature-map.sh` — 地图层，
  含**路由↔组件对应**校验（写模板时本人把 /messages 与 /inbox 搞混，被校验器当场抓出）。
- `templates/skill-testing/` — README + 可跑的 `run-skill-eval.js`（多 sub-agent +
  rubric + 双模型交叉评分分歧取低 + 回归基线）。
- `templates/ci/automerge-tiers.sh` — 按可逆性分三档，内置**分支保护前置门**
  （实测三仓 main 全无保护，无保护即拒判档）。

**已知坑（都写进了脚本注释）**：
- ego-browser heredoc 是 ES module 上下文——`require` 与顶层 await 冲突，用 `await import`
- `Tracing` 绑当前 target，先 `openOrReuseTab` 会换 target 致 `Tracing is not started`
- `gh api` 404 时把错误 JSON 打到 **stdout**，「输出为空即无保护」的判据永远为假
- ego-browser 的 `wait()` 单位是秒；`click` 必须传 `'@N'` 不能传数字
- 本机代理/TUN 会在证据里混入 `ERR_TUNNEL_CONNECTION_FAILED`，别当站点问题

**诚实的边界**：iOS 模拟器三重实测确认不可用（本机只有 Command Line Tools，无完整
Xcode），移动端原生复现这条链在本环境是断的；heap 两次快照 diff / retainer path
分析没有现成工具，要自己写解析。

**下一步**：合并 #14 → 自动 Release v1.7.0 → 在自有仓落地第一份 `docs/feature-map.yaml`
（建议从 PulseAgent 起，它的路由/i18n 结构最全）。

## 上一版目标（v1.6.0，已发布）

发布 v1.7.0：验证自治（ADR 0011）——把「人是唯一 verifier」这个并行度瓶颈拆掉。四层：能力层（verify-web.sh，浏览器调试协议采证，实测可取堆/节点/首屏）、地图层（feature-map + 校验器，含路由↔组件对应校验）、技能层（失败模式写成可执行 skill）、技能测试层（多 sub-agent + rubric + 双模型交叉评分分歧取低 + 回归基线）。自动合并按可逆性分三档，T3 不可逆改动永远人工。守卫测试 test-verification.sh 全绿。

## 上一版目标（v1.6.0，已发布）

发布 v1.6.0：仓库接入自治（ADR 0010）——把「新仓必撞额度死」从『记得跑接入命令』升级为构建机对账循环状态收敛。新模板 onboard-reconcile.sh（30min 对账，全程本机、不依赖入站通道）+ onboard-repo.sh（同一实现的单仓模式即时通道）+ service/timer + 守卫测试（含变异自证）。五条硬纪律全部有当日实战事故背书（.runner_migrated 残留 / 双通道互毒 / 裸奔空窗 / 只做加法 / 平台侧判定）。

## 上一版目标（v1.3.0，已发布）

发布 v1.3.0：把 runner 变量路由（v1.2.0）从手动升级为无人值守自治——账单/额度故障自动切换恢复、断连 job 自愈重跑、注册即纳管；新增网络自适应路由层（探测决策、环境无关）、三车道一键切换、基础镜像预烤零跨境、构建机出境代理方法论。ADR 0007。

## 当前接棒状态

- 状态：v1.2.0 内容完成于 `feat/actions-quota-immune-cicd` 分支，验证基线全绿（6 fixtures + 体检 + yaml/bash -n）；待 PR 合并 main 触发自动 Release
- 当前写入者：Claude Code
- App / 模型：Claude Code / Fable 5
- 分支：feat/actions-quota-immune-cicd
- 工作树：应为干净；接棒时以 `git status --short` 为准
- 下一棒：合并本 PR 后，跑 `./install.sh` 让受管块新条款同步进 ~/AGENTS.md；再按需把变量路由推广到其余产品仓（trade-crm / wechat-scrm / portal 等）
- 附注（2026-08-17 当日晚些修正）：xserver 的 runner **一直有系统级 `github-actions-<name>.service` 单元守护**（先前"nohup 无守护"是用 `*runner*` 通配漏搜的误判）。现状：13 单元全部 enable + `SupplementaryGroups=docker` drop-in（PA runner 缺 docker 组的根因即由此根治）。铁律：**一个 runner 只许一个监管者**——叠加 svc.sh / user 单元会双听抢会话导致全场 offline（当日实测事故）；单元为 KillMode=process，重启须用 agents-toolchain 的 `xserver-runner-systemd.sh` restart_clean 防孤儿双听。无人值守闭环（账单故障自动切换/恢复 watcher + hosted-canary 探针仓）见 agents-toolchain 仓 `scripts/runner-failover.sh`

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
- 仓库自身在 PR 与 main push 上自动运行密钥扫描、Shell 语法、体检评分 fixtures 和安装器 fixtures。
- 生产体检识别 `scripts/test-*.sh` 形式的轻量 Shell 测试，不再把脚本型仓库误判为无测试。
- 原生 Reasonix 模板在 macOS/Linux 上幂等生成服务，强制 loopback，安全存储 Provider Key，并通过隔离 fixture 与真实 Reasonix `doctor` 解析验证。
- 镜像生命周期 fixture 证明容器引用、最新版本、生产/回滚 tag 与 current/LKG 不会被删；本机定时守卫和 GHCR retention 均默认保守且可审计。
- 生产镜像链路固定为 Xserver 构建优先、Mac fallback，GitHub hosted push GHCR 优先、Xserver fallback；只向 online/idle 专用 runner 派单，并在 workflow 创建后 1800 秒内完成云端推广，否则回滚。
- Dockerfile、`.dockerignore`、基础镜像源顺序、digest 与构建入口全部进入 Git；大陆节点先走 DaoCloud，150 秒失败切 Public ECR，两条路径解析到同一 digest。
- 本机不存在 `~/AGENTS.md` 时，安装器也能从 GitHub 仓库创建权威规则源；已有规则只替换受管 DevOps 区块并保留 0600 备份，所有 Agent 入口收敛到同一文件。
- main CI 全绿后自动发布 `VERSION` 对应 GitHub Release；仅当本次新建 Release 后验证失败才自动删除该 Release/tag。

## 已完成

- 2026-08-06：部署跨 agent 交接架构（AGENTS.md / HANDOFF / ADR / 厂商指针）
- 2026-08-09：新增多 App / 多模型路由参考、单写入者规则、结构化接棒模板，并同步本机全局规则。
- 2026-08-09：安装脚本新增 OpenCode/OpenChamber 技能目录，避免图形端漏装。
- 2026-08-09：改为 OpenChamber 日常主入口、Claude 原生 App；加入任务型 fallback、失败冷却、三跳上限与缓存边界。
- 2026-08-09：注册 5 个 OpenChamber Agent；Kimi K2.7 Code、DeepSeek V4 Pro 与 OmniRoute Auto smoke test 通过，Codex/GPT 与 Kimi K3 的失败证据已记录。
- 2026-08-10：按 CI/CD 最佳实践统一“合并 main 即授权”，补齐不可变制品、provenance/SBOM、OIDC、渐进验证、自动回滚复验、可续租 TTL 回滚租约、原子完成发布与逐门禁证据。
- 2026-08-10：安装器新增全局规则收敛，将 Claude/Codex/OpenCode/Cursor/Gemini/Qwen/Windsurf 指向 `~/AGENTS.md`，并用隔离 fixture 防止覆盖厂商专属配置。
- 2026-08-10：已在本机执行新安装器；OpenCode/OpenChamber 全局入口直链 `~/AGENTS.md`，Claude import 唯一，9/9 skills surface 校验通过，原 Claude 配置已生成可恢复备份。
- 2026-08-10：新增仓库自身 CI 与 `.env`/备份忽略规则，发布 VibeDevOps 前不再依赖本机自觉验证。
- 2026-08-10：GitHub CI 首轮暴露 GNU/BSD `stat` 差异；fixture 已按操作系统分支修复，并把 checkout 统一升级到官方 v5 固定 SHA。
- 2026-08-10：主干 CI 通过后发现 Gitleaks v2 的 Node 20 弃用警告；工作流与模板已升级到官方 v3.0.0 固定 SHA（Node 24）。
- 2026-08-10：新增原生 Reasonix v1.21.5 常驻模板；本机 launchd、OpenCode Go Provider、85% compaction 与 loopback `/healthz` 已实装验证，安装器二次运行不产生漂移备份。
- 2026-08-10：新增 Docker/GHCR 三层镜像生命周期；本机 launchd、xserver 与 pulse systemd timer 已安装，Docker 删除保护所有容器引用且不使用 force/不删 volume。
- 2026-08-10：xserver 安全删除 22 个旧镜像，镜像占用从 26.02GB 降至 17.29GB；个人 GHCR 从 1107 个 versions 降至 472。本轮基于完整 OCI 图再删 71 个；21 个 package 均不超过 30，`wa-sdr-core` 为最新 30 + 1 个受保护版本。
- 2026-08-10：生产 build 模板支持 `VIBEDEVOPS_BUILD_RUNNER` 路由到局域网 `lan-builder` self-hosted runner，BuildKit state 复用并限时清理；生产服务器只拉 digest。
- 2026-08-10：生产模板升级为确定性双 fallback：Xserver→Mac 构建、GitHub hosted→Xserver 推送；同一份临时 image tar 在路径间交接，推送后生成 provenance/SBOM，云端只接收 digest。
- 2026-08-10：容量欠账成为下次构建前置门禁；生产/rollback tag 在解除回滚租约前更新，回滚会恢复 production tag；GHCR 通过 Registry manifest 构造受保护 OCI 引用闭包，图不完整时整个 package 保守不删。
- 2026-08-10：新增独立 hosted deadline watchdog，消除 self-hosted runner 状态检查与入队竞态导致的无限排队；状态查询失败退避重试，1800 秒后持续重试 force-cancel/cancel，部署控制器仍独立拒绝过期 complete。
- 2026-08-10：runner registration token 改用官方 `ACTIONS_RUNNER_INPUT_TOKEN` 临时环境，不进入 argv；Linux 移除 `KillMode=process`，stop/restart 使用 systemd control-group 清理完整 listener 进程树，并新增隔离行为 fixture。
- 2026-08-10：OCI 保护闭包增加 `subject.digest` 反向 referrer，production/rollback 对应的 provenance 与 SBOM 不会因 retention 丢失；runner `.runner` 仓库 URL 改为 jq 精确比较并覆盖前缀碰撞负例。
- 2026-08-10：当前 `iPythoning/VibeDevOps-skill` 已注册并常驻 `xserver-vibedevops`（Linux/X64/xserver）与 `mac-vibedevops`（macOS/ARM64/mac-builder），两者 GitHub 状态均为 online/idle；Xserver 使用非 root `gha` 用户与 lingering，Mac launchd 会拉起 Docker Desktop。
- 2026-08-10：runner listener 统一以 `env -i` 最小环境启动，验证未继承 API key/secret 类变量；清除了 Xserver 首次 root 误装留下的 666 MiB 未注册 runner 目录。
- 2026-08-10：PR #3 首轮 CI 发现 Linux hosted fixture 缺少 macOS `plutil`；安装器改为显式校验/可注入该工具，fixture 用 Python `plistlib` 做跨平台真实 plist 解析，本地回归已通过。
- 2026-08-10：PR #3 复跑全绿并 squash 合并，main CI `31356872316` 通过；GitHub Release `v1.1.0` 已发布。
- 2026-08-10：新增仓库级非 root Dockerfile、统一构建入口与 CI 容器 smoke；Mac 使用 DaoCloud 冷构建 `linux/amd64` 成功，镜像约 18.2 MB，含 `/healthz`，总耗时 101 秒。
- 2026-08-10：官方资料与实测确认 DaoCloud 完整前缀、DaoCloud Docker 前缀替换和 Public ECR 的 Alpine 3.22 OCI index digest 均为 `sha256:14358309…95dce`；公共 GitHub 模板不采用账号专属阿里云 mirror URL。
- 2026-08-10：Alpine 官方 CDN 在本机冷构建 300 秒超时，切到 Alpine 官方镜像列表收录的阿里云公共包源后，29 个固定版本包安装耗时 8.1 秒；镜像 health=healthy、UID=10001、`/healthz=ok`、amd64、18,241,191 bytes。
- 2026-08-10：`install.sh` 已在本机实装受管 DevOps 区块，Claude/Codex/OpenCode/OpenChamber/Cursor/Gemini/Qwen/Windsurf 与 9 个 skills surface 全部指向 Git checkout；二次执行无新备份。
- 2026-08-10：仓库 CI 新增 main 自动 GitHub Release 与失败回滚，v1.1.1 release/tag 当前均未预占，release notes 可从 CHANGELOG 确定生成。
- 2026-08-10：main workflow concurrency 改为按 commit SHA 唯一，连续版本不会因 GitHub“同组只保留一个 pending run”的语义跳过中间 CI/Release；PR 仍会取消同分支旧运行。
- 2026-08-10：专项代码复审关闭全部 HIGH/MEDIUM 后 APPROVE；超时 fixture 证明父 CLI 先退出、子进程忽略 TERM 时仍会在宽限后清完整独立进程组。
- 2026-08-10：Xserver 以非 root `gha` 从 GitHub clone 并 detached checkout `a3a4761a102b2ca1e1a34d57f3b6aefbcde5013c`，host 网络冷构建耗时 65 秒；health=healthy、UID=10001、`/healthz=ok`、amd64，tar=45,070,848 bytes。
- 2026-08-10：Mac 从同一 clean commit `a3a4761a102b2ca1e1a34d57f3b6aefbcde5013c` 构建耗时 11 秒；health=healthy、UID=10001、`/healthz=ok`、amd64，tar=18,261,504 bytes。两端测试 tar/容器/镜像已删除，Xserver checkout 与 Dockerfile 保留，223 个 volume 未触碰。
- 2026-08-10：PR #5 squash 合并到 main `65c1834a81186ee75f6f97717a8a8d070dc05b3d`；main CI `31364675469` 全绿，自动发布 GitHub Release `v1.1.1`，轻量标签与 Release target 均精确指向该提交。
- 2026-08-10：发布收尾再次清除本机 1 个遗留测试容器与 `dev`、`default-dev`、`pgid-dev`、`mac` 四个测试镜像；均可从 Git 重建，Docker volume 与业务镜像未触碰。

## 进行中

- 无。v1.1.1 发布链已经闭环。

## 已知坑 / 注意事项

- Git hook 可以强制“代码变更必须更新 HANDOFF”，但无法证明某个外部 App 实际使用了指定模型；模型路由依赖所有 App 共同遵守 `~/AGENTS.md`。
- OmniRoute `auto/best-coding` 实测可用且落到 LongCat，但插件 `/api/combos` 仍报 403；只作为最后保障，不作为固定四模型链。
- OpenChamber 的 Codex/GPT 路由本次 smoke test 不可用；修复凭证/地区前继续使用 Codex 原生 App。
- OpenCode Agent 一次只能绑定一个模型；硬额度错误发生在模型响应前时，需在 OpenChamber 一键选择下一 Agent。只有 OmniRoute Combo 能在单请求内自动降级。
- 既有仓库不会被模板自动覆盖；需要在目标仓库显式运行 `/vibedevops 交接` 或现有部署脚本升级。
- `wa-sdr-core` 当前 31 个 GHCR versions 是最新 30 + 1 个生产/回滚保护版本，不应为追求数字强删。账户级每日 04:00 retention 已升级为带 GET/DELETE 重试的 OCI 引用闭包版本；任一 package 图不完整会候选归零。
- pulse 当前 40 个容器全部运行，镜像清理 dry-run 候选为 0；Docker 显示的“可回收”共享层不能用 force 清除。xserver/pulse 的 volume 不属于镜像缓存，自动守卫明确不删除。
- GitHub 个人账号的 self-hosted runner 是 repository scoped；当前两台 runner 只注册到 `iPythoning/VibeDevOps-skill`，应用到任何生产仓库时必须用该仓库的一次性 registration token 再注册一个实例。
- runner 在线/忙碌预检需要目标仓库 secret `VIBEDEVOPS_RUNNER_READ_TOKEN`（fine-grained，仅 `Administration: read`）。GitHub 不允许流水线自动铸造这种长期凭据；当前未把本机拥有 `repo/workflow/user` 等广泛 scope 的 classic token复制到仓库，避免为“全自动”扩大泄露半径。

## 下一步

由用户指定首个生产仓库，在该仓库注册两台 runner、创建最小权限 `VIBEDEVOPS_RUNNER_READ_TOKEN`，再补齐该应用自己的 OIDC、部署控制器和功能门。模板发布不等于擅自部署未指定的业务应用。

## 如何验证

2026-08-10 当前验证已通过：build runner、container fallback/超时强杀、image lifecycle、CI/CD health、全局安装器新旧 HOME fixtures，Mac 真实 DaoCloud/阿里云镜像构建与非 root smoke，Actionlint v1.7.7、skill quick validate、Gitleaks 和 `git diff --check`。PR #5 与 main CI `31364675469` 全绿，GitHub Release `v1.1.1`/tag/target SHA 一致。Reasonix 本机验证按用户要求不重复执行；仓库 CI 继续固定 v1.21.5 + SHA256 验证。

- `bash -n install.sh skills/vibedevops/scripts/deploy-handoff.sh skills/vibedevops/scripts/health-check.sh skills/vibedevops/scripts/test-health-check.sh skills/vibedevops/scripts/test-install.sh`
- `./skills/vibedevops/scripts/test-health-check.sh`
- `./skills/vibedevops/scripts/test-build-runner.sh`
- `./skills/vibedevops/scripts/test-container-build.sh`
- `./skills/vibedevops/scripts/test-install.sh`
- `./skills/vibedevops/scripts/test-reasonix-runtime.sh`
- `./skills/vibedevops/scripts/test-image-lifecycle.sh`
- `bash -n skills/vibedevops/templates/build-gate/install-github-runner.sh`
- `./skills/vibedevops/templates/build-gate/build-container-image.sh --tag vibedevops-skill:local`
- `actionlint skills/vibedevops/templates/ci/pr-check.yml skills/vibedevops/templates/ci/deploy.yml`
- `actionlint skills/vibedevops/templates/ci/image-retention.yml .github/workflows/ci.yml`
- `GOTOOLCHAIN=local go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/ci.yml skills/vibedevops/templates/ci/deploy.yml`
- `python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/vibedevops`
- `git diff --check`
- `./skills/vibedevops/scripts/health-check.sh --json .`
- `gh api repos/iPythoning/VibeDevOps-skill/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'`

## 最近交接记录

| 日期 | 操作者 | 摘要 |
|---|---|---|
| 2026-08-10 | Codex | 按最佳实践修正合并授权边界并补齐自动 CI/CD 安全链 |
| 2026-08-09 | Codex | 改为 OpenChamber 优先并加入按任务类型的有限 fallback |
| 2026-08-09 | Codex | 固化四模型跨 App 路由与单写入者接棒协议 |
| 2026-08-06 | 部署脚本 | 初始化交接架构 |
