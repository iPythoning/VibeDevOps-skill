# Changelog

## v1.4.0 — 2026-08-19

- **ADR 0008：出境链路必须分域分方向实测——「能连」≠「能传」**。一次真实排障推翻了 0005–0007 共同的隐含前提「探测到通就能用」：同一台云主机到境外生产机 **320 Mbps**、到代码托管平台 **0.41 Mbps** —— **限速按目标域施加，不按国界**；商业代理下行 62 Mbps 但上行仅 3.8 Mbps 且中途断连。**握手状态码与 `time_total` 只能判断是否被阻断，不得作为选型论据（与吞吐可差两个数量级）**；registry / 制品仓选型一律用 ≥100MB 真实镜像分方向实测。
- **代理生效范围要逐层验证**：宿主 shell / 容器引擎守护进程 / BuildKit 守护进程 / 构建容器 `RUN`，四层表现可以完全不同（守护进程的代理配置常不在信号重载范围内，而生产机不能随意重启）。**优先用用户态工具完成出网动作**，不依赖守护进程的代理支持。
- **`NO_PROXY` 自伤与生成器铁律**：被阻断的域名进入 `NO_PROXY` 视为故障；**配置由脚本生成的，修复必须落在生成器**——只改产物等于未修复（现场此坑复发两次）。守卫断言本身必须反向验证。
- **自适应脚本的「撤销分支」是炸弹（修正 ADR 0007 的一处实现风险）**：代表性端点恢复直连 ≠ 所有目标恢复。**代理配置的存废判据必须是「代理本身是否可用」，不是「探测目标是否直连可达」**；撤销类分支要求双向变异验证。
- **跨境推送大 blob 必须分块**（整块 PUT 会 `unexpected EOF`；分块 + 重试可扛）；**推送步必须带服务端回读断言**（退出码 0 ≠ 制品在仓里）。
- **镜像体积升格为 CD 可用性指标**：在实测 10.6 Mbps 出境链路上每 100MB ≈ 75 秒发版时间。删依赖前必须查生产实态（有无数据、是否曾成功启用），不能只看代码引用；对 wheel 分发的 `.so` 做 strip 收益为 0（出厂已 strip）。
- **新增成熟度阶梯 L0–L4** 作为自评基准，明确「最低标准」（低于此不应承接生产流量）与「最高标准」。

## v1.3.0 — 2026-08-17

- 无人值守 runner failover 闭环（ADR 0007）：检测托管 CI 账单/额度拒绝签名→自动切自建 runner→hosted 探针恢复→自动切回；断连型 job（failure 但 0 failed-step 且已分配 runner）自愈重跑；纳管范围自动发现（注册 runner 即纳管）。新模板 `templates/ci/runner-failover.sh` + `hosted-canary.yml`。
- 网络自适应路由层（ADR 0007，`templates/build-gate/net-adaptive.sh`）：路由是探测结果非配置，探测 direct/proxy→决策 DIRECT/PROXY/DOWN→应用到 runner git+出境 env；环境无关（今天要代理/明天不要都自动适应）、只在路由变化时动作、忙 runner 跳过重启不打断在跑 job。
- 三车道一键切换 `templates/ci/cd-lane.sh`：hosted/builder/mac 互斥变量组一次原子设齐，杜绝"少设一个卡一步"。
- 基础镜像预烤零跨境 `templates/build-gate/warm-base-images.sh`：镜像站拉基础/CI 镜像 retag 规范名 + docker 直建驱动本地命中，构建期唯一出境只剩推 registry。
- 构建机出境代理方法论 `references/egress-proxy.md`（工具无关）：自建出境代理根治间歇封锁；端口访问控制靠 iptables 网络层且必须幂等（防规则累积成全开放隐患）；容器 CI 经 host-gateway 回连宿主代理。
- SKILL §4.5 扩写：从"手动降级是治标"升级为无人值守闭环 + 网络自适应；受管全局规则同步新条款。

## v1.2.1 — 2026-08-17

- 受管全局规则新增「新增仓库一律走这条线」：CI/CD 从模板起步（内置变量路由）、统一构建机注册 runner 即自动进入账单故障 failover 纳管（自动发现）；单 runner 单监管者铁律（叠加监管抢会话，当日实测事故）。
- HANDOFF 修正 runner 守护误判（github-actions-* 系统单元一直存在）。

## v1.2.0 — 2026-08-17

- CI/CD runner 由仓库变量路由（ADR 0006）：`pr-check.yml` 与 `deploy.yml` 全部必过 job 的 `runs-on` 走 `CI_RUNNER`/`CD_RUNNER`/`VIBEDEVOPS_CONTROL_RUNNER` 变量，默认 hosted 不变；托管额度/账单故障期一条 `gh variable set` 切 self-hosted，恢复即删。账单欠费日实证：hosted job 3 秒被拒、self-hosted 照常调度，GHCR/API/git 均正常。
- 新增 `templates/ci/runner-canary.yml`：故障日分层定位探针（self-hosted 调度 / 构建机 checkout / 分域名连通），路由决策只认当日实证，禁止引用历史网络结论。
- `deploy.yml` 控制面 job 与构建 job 的 runner 池隔离纪律：长驻 watchdog 不得与构建挤同一个单并发 runner（自饿死陷阱）。
- build-gate 降级缺口 ④ 按失效模式拆分：托管额度/账单故障模式已由变量路由关闭；托管方整体不可用模式维持"事前写明无法发布"。
- 新增 `references/dangerous-commands.md`：破坏性命令三级分级（Blocked/Dangerous/Warning）、受保护路径清单、manifest 驱动的操作前备份、体检输出四件套契约（吸收自一个 MIT 协议开源 CLI 的思路，按本仓纪律重写并剥离上游元素）。
- 受管全局规则新增 runner 变量路由与 canary 实证条款；`RUNBOOK` 模板补破坏性操作前 manifest 备份步骤。

## v1.1.1 — 2026-08-10

- 新增仓库级 Dockerfile 与 `.dockerignore`，Mac、Xserver、CI 从同一 Git commit 构建，不再依赖机器私有文件。
- 新增统一容器构建入口：大陆节点优先 DaoCloud 基础镜像与 Alpine 官方列表收录的阿里云公共包镜像，150 秒失败自动切 Public ECR 与 Alpine 官方 CDN，两条基础镜像路径固定同一 digest。
- CI 新增真实镜像 build、非 root 运行与 `/healthz` smoke test，并用 fixture 验证镜像源 fallback 顺序。
- 将“Docker 配置必须进 Git、本机 cache 仅加速不得影响正确性”同步到全局 Agent 规则与 VibeDevOps 模板。
- 新增仓库托管的全局 DevOps 规则区块，安装器会幂等同步到 `~/AGENTS.md`，新机器无需预置本机规则。
- 仓库自身在 main CI 全绿后自动发布 `VERSION` 对应的 GitHub Release，发布验证失败会删除本次新建的 Release/tag。

## v1.1.0 — 2026-08-10

- 新增原生 Reasonix 常驻运行时：macOS `launchd` KeepAlive 与 Linux `systemd --user` Restart。
- 自动补齐 Reasonix 的 OpenCode Go Provider；已有 Provider 先经真实 doctor 校验模型映射，密钥文件及备份强制 `0600`，受管软链明确拒绝。
- 默认使用 `deepseek-v4-flash`、128K Provider 预算与官方最高 85% compaction 阈值，保持稳定前缀但不虚构固定缓存命中率。
- 新增字面量 loopback 强制、Linux user lingering、`/healthz` 健康检查、跨平台隔离 fixtures、固定 SHA256 的 Reasonix v1.21.5 CI 验证和 `./install.sh --with-reasonix-runtime` 可选入口。
- 固化 OpenChamber 优先的多模型路由、有限 fallback、全局 Agent 规则同步，以及合并 main 后自动部署与失败回滚模板。
- 新增本机/部署机 Docker 每日容量守卫、成功部署后的 current/LKG 保护清理，以及 GHCR 多架构版本每日 retention，阻断残留镜像无限增长。
- 生产镜像链路固定为 Xserver 构建优先、Mac fallback，GitHub hosted push GHCR 优先、Xserver fallback；runner 在线/忙碌状态预检和部署控制器 deadline 共同强制端到端小于 30 分钟。
- 独立 hosted watchdog 兜住 self-hosted 排队竞态；GHCR 清理基于 OCI 引用闭包，图不完整时不删；runner token 不进入 argv，systemd stop 覆盖完整 listener cgroup。

## 2026-08-06

- 部署跨 agent 交接架构：AGENTS.md、docs/HANDOFF.md、docs/adr/、厂商指针。
