# 交接状态 · HANDOFF（VibeDevOps-skill）

> 任何 agent 开始工作前**必读**，结束工作前**必更新**。
> 本文件是当前任务状态的唯一权威来源；历史决策看 docs/adr/，历史变更看 git log。

## 当前目标

发布 VibeDevOps v1.1.1：把 Dockerfile、镜像源 fallback、digest 与构建入口完全仓库化；Xserver 与 Mac 从同一 commit 构建，不依赖任何机器私有文件或 cache。

## 当前接棒状态

- 状态：专项复审 APPROVE，Mac/Xserver 同 commit 构建与 smoke 完成，待 PR/main CI 与自动 Release
- 当前写入者：Codex
- App / 模型：Codex / GPT-5
- 分支：feat/container-image
- HEAD：本次提交见 `git log -1 --oneline`
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

## 进行中

- PR/main CI 与 v1.1.1 自动 Release；合并后再次核对 tag/release commit 与 main CI。

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

创建并合并 v1.1.1 PR，等待 main CI 自动发布 Release。随后由用户指定首个生产仓库，在该仓库注册两台 runner、创建最小权限 `VIBEDEVOPS_RUNNER_READ_TOKEN`，再补齐该应用自己的 OIDC、部署控制器和功能门。

## 如何验证

2026-08-10 当前验证已通过：build runner、container fallback/超时强杀、image lifecycle、CI/CD health、全局安装器新旧 HOME fixtures，Mac 真实 DaoCloud/阿里云镜像构建与非 root smoke，Actionlint v1.7.7、skill quick validate、Gitleaks 和 `git diff --check`。Reasonix 本机验证按用户要求不重复执行；仓库 CI 继续固定 v1.21.5 + SHA256 验证。

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
