# Changelog

## v1.7.0 — 2026-08-27

- **ADR 0011：验证闭环必须自治——人是 verifier 就是并行度上限**。前十个 ADR 解决的是同一件事：**怎么把代码安全送上生产**（变量路由 0006、无人值守 failover 0007、链路实测 0008、门禁自证 0009、接入对账 0010）。它们共享一个从未写下来的前提：**验证由人做**。把最近的真实故障按「谁完成了验证」重新归类，四件里有三件是「门禁绿着，而真相在别处」——CD 首跑红是人读 384 秒构建日志找到 `network:` 参数缺失；容器引擎卡死是人翻日志发现进程在等 GUI 对话框；可选依赖导致生产 502 是人回读源码发现类型注解在导入期求值。**再加一道门禁的收益在递减（已知错误正被逐个吃掉），而给 agent 一次验证能力的收益在递增——它对每个后续任务复用，而且可以并行。**
- **能力层 `templates/verification/verify-web.sh`**：agent 自己打开页面、采 console/失败请求/性能与内存指标/截图，产出机器可判的证据 JSON，越界即非零退出（同时是门禁）。能力来自浏览器调试协议通道——实测 `cdp('Performance.getMetrics')` 可取 `JSHeapUsedSize`/`Nodes`/`Documents`，配 navigation timing 得首屏耗时。**`curl` 200 只证明服务器回了字节，证明不了页面能用。**
- **该工具自身踩过绿色谎言并已修**：早期版本 `--url http://x` 打开一个无关错误页，因无 console 错误、无失败请求而报「✅ 验证通过」——缺的是「页面到底加载没加载」判据。现补 DOM 规模 + 主文档状态双判据，守卫测试锁死。诚实标注：主文档状态常因事件时序取不到（实测多为 0），真正兜底的是 DOM 规模判据。
- **地图层 `feature-map.template.yaml` + `check-feature-map.sh`**：功能名→路由→组件→进入条件→验证方式→已知坑，让「一张截图」「某某页面坏了」能被机械翻译成可复现的操作序列。**过期的地图比没有地图更危险**（让 agent 自信地走错），故校验器进 PR 门禁。**尤其校验路由↔组件对应**：只验路由存在不够——路由表里同时有 `/messages` 与 `/inbox` 时，地图写错一个照样通过而 agent 会被带到另一个页面（写模板时本人当场踩中，校验器抓出）。
- **技能测试层 `templates/skill-testing/`**（README + 可跑的 `run-skill-eval.js` workflow 脚本）：多 sub-agent 独立执行任务样本 → rubric 打分 → **两个模型交叉评分且分歧取低**（分歧说明 rubric 或任务描述不清，该改 fixture 而非 skill；累计 3 个即重写 rubric 维度）→ 与基线比对防退化（**基线只在人工确认后更新，自动更新基线等于没有基线**）。分三类属性测：触发准确性/执行正确性/结果质量——**只测结果质量是常见错误**，最常见的失败是根本没触发，而那时结果看着还正常。
- **自动合并分级 `templates/ci/automerge-tiers.sh`**：按**可逆性**分档。T1 纯文档/测试/文案 → CI 绿即合；T2 有运行时影响 → CI 绿 + 门禁自证有效 + 实际操作产品的证据 + 部署侧自动回滚；**T3 不可逆或影响面超出可验证范围（迁移/密钥/生产编排/流水线自身/真钱/认证授权）→ 永远人工，不接受任何证据豁免**。混合改动按最危险的文件定档，**不被大量安全文件稀释**。实测：本仓与 clawops 最近两个 PR 都被正确判为 T3（都改了流水线自身）。
- **守卫测试 `scripts/test-verification.sh`**：feature-map 三类漂移各自转红、automerge 三档 + 混合不稀释、verify-web 缺依赖/非法输入被拒、workflow 脚本语法（按其顶层 return 约定包装后校验）。全部 PATH 替身，干净 CI 容器可跑。
- 顺带：v1.6.0 的 `test-onboard.sh` 补进 AGENTS.md 验证基线（当时漏进清单）。


## v1.6.0 — 2026-08-22

- **ADR 0010：仓库接入自治——「记得跑」不是机制，对账收敛才是**。托管 CI 账单死透后，每个新建仓库仍必撞「额度不足」0 步失败：模板路由 fallback 是 hosted（变量没人设）、failover「无 runner 不切」（没注册的仓是盲区）、「建仓后记得跑接入命令」是无主步骤（人和 agent 都会忘，仓库可从任何入口创建，事件钩子拦不全）。对策 = 把接入从事件驱动改成**状态收敛**：构建机 root 对账循环把「OWNER 名下每个有 workflows 的仓都有 runner + 路由变量」收敛成事实。
- **新模板 `templates/build-gate/onboard-reconcile.sh`（+ systemd service/timer）**：30 分钟一轮全量对账；跳过 archived/fork/无 workflows/skip 清单；全程构建机本机完成（**不依赖任何入站通道**——overlay 网络入站挂死一整天的实证当日发生）；token 只进请求头。
- **新模板 `templates/build-gate/onboard-repo.sh`**：即时通道 = 同一份实现的单仓模式（`ONBOARD_ONLY_REPO`）薄 wrapper——两个入口一份逻辑，永不漂移。
- **五条硬纪律（每条都有当日实战事故背书）**：① 只做加法，**绝不覆盖已存在的变量值**（异构车道配置不被夷平）；② 「已注册」以平台侧 API 为准——`config.sh` 断链残留的正主是 `.runner_migrated`（新版 runner 配置文件），只按 `.runner` 判定/清理会陷入 already configured 死循环，清理清单必须 `.runner*` `.credentials*` `.env` `.path` 全集；③ 注册失败整目录删除重来（半配置残留毒化下一轮）；④ 注册单写入者——双通道并发 `--replace` 互相吊销刚拿到的凭据；⑤ 新 runner 单元出厂即带出网配置（代理 drop-in），否则注册到网络自适应层补配之间存在「裸奔空窗」（实测 npm prebuild 直连 140 秒卡死）——修复落在单元生成器不是事后补。
- **守卫测试 `scripts/test-onboard.sh`**：PATH 替身注入（mock curl/systemctl/runuser），断言不覆盖已有变量/skip 清单/无 workflows 跳过/单仓模式圈地；变异自证（拆掉守卫测试转红）。
- **逃生通道模式（诚实记录天花板）**：控制通道挂死时可用某仓已 online 的 runner 跑 job 代办另一仓的注册，但 runner 用户装不了 systemd 单元——它是「把 90% 准备工作做完」的手段，不是完整替代。
- 首轮全量对账实测清账：35 个存量仓自动注册 runner、补齐 367 个变量，一条历史挂起的「只差注册」待办被顺带关闭——对账模式不区分新欠的和旧欠的。
- 受管全局规则升级：「新增仓库一律走这条线」补「忘了跑也没事」条款。
- **基线修复：Dockerfile 去掉 apk 包版本 pin（保留 base image digest pin）**。alpine 稳定分支仓库是滚动的（安全更新 -rN 递增、旧版即刻下架），钉具体版本等于给门禁装定时假红——2026-08-20 起 main CI 因 pin 过期连红（实证）。可复现性由 base digest 承担；只列顶层工具包，传递依赖（*-libs）不再显式钉（上次碎的根源）。一个每隔几周必然假红的门禁违反 ADR 0009「门禁必须自证有效」。


## v1.5.0 — 2026-08-19

- **ADR 0009：门禁必须自证有效，验证路径必须与生产同形**。一条流水线被「修好」一周、每次都有绿色证据，而真实的 `push → 生产` 一次没通过。同日三道独立门禁被证明是假的，形状完全相同：**绿/红信号与它声称代表的事实之间，没有机制保证对应关系**。
- **金丝雀自检**：拦截型门禁每次运行必须先证明自己会失败，再做真正的检查（密钥扫描先扫一个**随机生成**的假凭据；随机是刻意的——写死的样本会进仓库、会被自己扫到）。**回滚路径必须平时走过一次，不能等出事时第一次用。**
- **跳过不是通过**：守卫写成 job 级 `if:` 时，不满足条件的行为是**跳过**，而跳过的工作流**在界面上是绿的**——「拒绝部署」和「部署成功」长得一样。拦截一律显式失败（非零退出 + 错误行）。
- **岔路要删掉而非规范**：构建工作流只保留「被部署工作流调用」一种触发方式。代价（不能只构建不部署）由「构建但不推送」进 PR 门禁补偿。手工部署入口**默认可对任意分支生效**，必须加分支守卫——扫描发现该洞在多个仓库全部开着。
- **可复用工作流不继承 secrets**：除平台自动注入的令牌外，仓库 secrets 不会自动传入，缺失表现为**空字符串而非报错**；叠加 `set -e` 与被重定向的 stderr，表现为**整步零输出、退出码 1**。所有必需 secret 使用前显式断言非空。
- **禁止吞 stderr**：`cmd 2>/dev/null` + `set -e` 会把「为什么失败」连同失败一起吞掉。
- **删依赖必须在真正没有它的产物上验完整启动**：`try/except ImportError` 守卫挡不住**导入期求值的类型注解**（函数签名在类定义时求值，`None.Attr` 直接抛异常 → 启动即崩）。在仍装着该依赖的产物上做的验证等于没做。
- **配置存在 ≠ 消费方读了 ≠ 消费方认**，三处都要对上；修复必须落在**生成方**，只改产物等于未修复。
- **多写入者纪律**：建分支前查远端同名分支与本地工作树占用；他人已在解同一问题时在其分支追加而非另开；推送必须显示错误（静默推送失败与成功在终端上无法区分）。
- 新增文章 `articles/04-green-lies-fake-gates.md`。

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
