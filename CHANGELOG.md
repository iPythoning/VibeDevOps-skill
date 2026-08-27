# Changelog

## v1.7.7 — 2026-08-27

- **对账心跳**：`onboard-reconcile` 是整条接入自治链的**根**——它死了，新仓就悄悄回到「必撞额度死」的状态，**而没有任何东西会告诉人**。上一版部署时亲手证明过：用通用模板覆盖硬编码版漏带 env，`ONBOARD_OWNER` 未设导致每轮开头就退出，**静默死了 20 分钟**才被偶然发现（当时只看了 `bash -n` 通过就说「已部署」）。现每轮成功写 UTC 时间到仓库变量 `ONBOARD_LAST_SUCCESS`，daily workflow 检查年龄超时即红。
- 两个刻意的设计：**心跳写平台变量而非本机文件**（本机文件要人登上去才看得见）；**检查 workflow 跑托管 runner 不走变量路由**——它监控的正是自建车道，跑在自建 runner 上会在自建车道整个挂掉时一起沉默，**监控与被监控对象不能共享失败模式**。
- 验证做了三层：部署后实跑一次（日志出现 heartbeat 行）、平台侧第二通道核验变量真的写进去了（日志说写了不等于写进去了）、反向自证把心跳改成 4 小时前确认判据正确转红。


## v1.7.6 — 2026-08-27

**用一个真实的新仓做端到端验证，发现「新项目不会被卡死」当时还不成立。**

探针实验：建仓 → 推代码 → 什么都不做。结果 CI 立刻 **0 步失败、无 runner**——教科书式的额度死。对账循环随后自动接入（runner online + 7 个路由变量、零 FAIL），重跑 CI **success（5 步）**，构建机日志实证 `Running job: test → Succeeded`。链路是通的，但过程中挖出两个真缺口：

- **注册前只 exclude 没真删旧配置**。`rsync --exclude` 只是「不从源复制」，**不会删掉目标里已有的同名文件**（`--delete` 默认也不删 excluded 项，那要 `--delete-excluded`）。重注册一个曾注册过的仓时旧 `.runner` 还在 → `config.sh` 报 already configured 失败 → 紧接着 `rm -rf` 删掉整个目录 → **单元指向不存在的路径无限 `activating`**，该仓从此没有 runner，一触发 CI 就撞额度死。**实测两个仓正卡在这个状态**（`token-meter-oss`、`client-site-autoglobal`，平台侧 0 online runner）。ADR 0010 写了「注册前清理」，代码里却只 exclude 没真删——**文档写了、代码没做**。
- **`activating` 是巡检盲区**：systemd 里它既不是 `active` 也不是 `failed`，按这两个状态巡检会漏掉。失败分支现在同时清理单元。
- 另修 `TEMPLATE` 用 `ls | head -1` 可能选中**目标仓自己**（按字母序 `repo-a` < `template-runner`），rsync 自己到自己。现改为跳过自身、且要求候选目录有可执行的 `run.sh` + `config.sh`。
- 守卫补一轮「重注册带旧配置的仓」：断言注册前旧配置被真删、且能重新注册成功。


## v1.7.5 — 2026-08-27

补齐 7/7 基线。补跑单个 case 的过程又挖出框架两个缺陷，都已修并被守卫锁死。

- **新增 `only` 参数**：补跑单个 case 不必全量重跑（一轮完整评测 20+ agent、200 万 token；补一个 case 只用 4 个）。summary 里显式标 `partial`，避免把部分结果当全量写进基线。
- **⚠️ 补跑要开新 run，别用 resume**：resume 按 `(prompt, opts)` 命中缓存，而 fixture 是**外部文件**——改了 fixture 但 load 的 prompt 没变时，它会命中缓存返回**旧 fixture 的内容且无任何提示**。这本身就是一种观测陷阱，已写进 README。
- **negative case 改二元判定，不打分**。rubric 衡量的是「这条轨迹展现了多少该 skill 的流程」，而 negative 的正确行为恰恰是**不展现**——用同一把尺子量，行为完全正确的负例也会得低分。实测：一个改错别字的负例，四维里三维是 0（不需要做那些），加权 0.4 判 fail，两个评分模型还因此分歧 1.1——**框架自己的分歧检测正确地指出了这里有问题**。现负例 `final: null`，只判「有没有套用不该用的流程」。
- **判据改结构化字段 `abusedProcess`**：原实现用正则在 why 里找「滥触发」三个字——而「**未**滥触发」「不算滥触发」同样含这三个字，**必然假阳性**（实测两个行为正确的负例全被判成滥触发）。改后 neg-1 正确 pass、neg-2 正确 fail。**这是「判据写错」在本次开发里的第 N 次，而且就发生在我修判据问题的代码里。**
- **加反引号配对守卫**：往 prompt 模板字符串里写 markdown code span 会提前终止它——这个坑本次撞了三次。语法检查能抓到但报错指向截断处很难读，现单独给一条明确失败信息。

### 完整基线

| case | 结果 |
|---|---|
| pos-1 判断站点是否挂了 | 1.75 |
| pos-2 判断「0 行=没人用」 | 2.0 |
| pos-3 证明门禁真会拦 | 2.0 |
| pos-4 CI 绿能否上线 | 2.0 |
| edge-1 「查不到=不存在」 | 2.0 |
| neg-1 改错别字 | ✅ pass（未套流程） |
| neg-2 列目录 | ❌ fail（仍滥触发，下轮靶子） |

neg-2 **不为让它通过而继续改描述**——那是过拟合。等积累更多同类 case 再一起调。


## v1.7.4 — 2026-08-27

补跑首轮挂掉的两个 case，拿到第一份**用正确 rubric 评出**的完整基线。

- **两个补跑的 case 都是满分 2.0**：`pos-2-empty-table`（把「预发手动触发一次再查表」定为反向自证第一步，枚举 writer 断链/查错库/时间窗/租户过滤/feature flag/软删除等成因并逐类分配排除步骤，点名网关日志与上游 token 消耗作为独立第二通道，且明确禁止在排除完成前做任何不可逆动作）、`edge-1-grep-not-found`（做正对照证明 grep 在本仓能工作 + 负对照证明未命中即真未命中，再遍历 git 全历史 ref，并标注未 fetch 的远程分支等未覆盖范围）。
- **修好了 rubric 传递链**。首轮 rubric 静默退回默认的真因查清了：那次批量改动的脚本第三处 `assert` 抛异常退出，**`write()` 从未执行**——前两处改动（schema 加 rubric 字段、load prompt 要求返回它）全丢了，而当时因为「没报错」以为成功。**这本身就是 `evidence-discipline` 要防的形态：把「assert 没报错」当成「改动已生效」，中间少了「确认文件真的写了」这一步。** 本轮 `rubricSource: fixture` 已确认生效。
- **`infraFailures` 修复经受了实测**：本轮又有 1 个 exec agent API 中断，框架正确地把它排除在评分外（`executed: 6, infraFailures: 1`），没有污染 skill 分数。

### 「触发」不是二元的——三态判断（本轮最重要的发现）

一个「列目录」的 negative case 出现分数退化（1.4 → 0）。查下去发现：agent **加载了 skill、读了它的「什么时候不适用」段、正确判断不适用、没套三步法**——这是理想行为，却因为 `loadedSkill=true` 撞上「加载即滥触发」的旧判据被判 0。

**是 fixture 的判据错了，不是 skill 或 agent 错了。** 触发有三态：没加载 / 加载并套用 / **加载后正确排除**。第三种最容易被误判——读 skill 的描述来判断适不适用，本身就是正常工作流程。

已修：negative case 的判据改为落在「有没有套用流程」这个**可观测的动作**上（fixture 用 `must_not` 写明具体行为），评分规则同步改为三态判断。


## v1.7.3 — 2026-08-27

### 第一次真实评测跑完了，产出三个发现

在 `evidence-discipline` 上跑首轮（7 case × 执行 + 双模型交叉评分，22 个 agent、200 万 token）：

| case | 分数 | 说明 |
|---|---|---|
| pos-1 判断站点是否挂了 | **2.0** | 识别本机代理 + 8 个 TUN + fake-IP，再用第三方节点从四国复核，还排除了 CDN 缓存假活 |
| pos-3 证明门禁真会拦 | **2.0** | 造必然违规输入实测转红 + 合规输入转绿，双向验证 |
| pos-4 CI 绿能否上线 | **2.0** | 推翻「四项全绿」前提（两项是 skipping），实测复现缺陷 |
| neg-1 改错别字 | 1.8 | 正确**没有**触发 |
| neg-2 列目录文件 | 1.4 | ⚠️ **滥触发**——纯 `ls` 任务却全程套三步法 |
| pos-2 / edge-1 | 0 | ❌ 执行 agent API 中断，**不是 skill 失败** |

**三个发现**：

1. **skill 有效**（有真实轨迹的四个 case，三个满分一个 1.8）——但这不是重点，重点是下面两条。
2. **抓到一个真实滥触发**：negative case 的价值就在这里，没有它发现不了。已据此收窄 skill 描述并加「什么时候不适用」段，**复测该 case 已正确不触发，且 agent 给的理由直接引用了新加的边界原文**。
3. **框架把基础设施故障算成了 skill 失败**：2 个 exec agent 因 API 中断返回空轨迹，被评分判成 0 分 fail——skill 看起来是 4/7 而实际是 4/5。已修：空轨迹判为 `infraFailures` 不计入评分。
4. **rubric 静默退回默认**：fixture 里写了 4 个维度，实际按默认维度评的，而**没有任何提示**。已修：rubric 来源显式 log，退回默认时明确说「若 fixture 里确实写了，这是缺陷」。


- **rubric 改为跟 fixture 走**。原先写死在 `run-skill-eval.js` 里（「定位/复现/证据/结论」四维，是给前端 bug 复现设计的）——**首次拿它测另一条 skill 时立刻暴露：这个框架只能测一条 skill**。现 rubric 写在 fixture 的 `rubric:` 段（维度/权重/分级/通过线全可配），没写则退回默认。打分 schema 的 dimensions 同步放开为动态 key。
- **第一个真实用例进 `examples/`**：`evidence-discipline` 这条 skill 的 SKILL.md + 完整 fixture（7 case：4 正 2 反 1 边界，4 个 rubric 维度）。它同时是「失败模式写成可执行 skill」的第一个产物——**靶子是实测选的**：本机 59 条失败沉淀里，「观测不可靠却下确定结论」占 13 条，是第二名（4 条）的三倍多，且多条明确记着「第二次」。
- 该 skill 覆盖的形态（每条都有事故背书）：管道吞退出码、错误走 stdout、jq `//` 把 false 当空、`--if-present` 静默成功、调试协议订阅时机、健康检查窗口太短、看似执行实为 no-op、本机代理污染观测。


## v1.7.2 — 2026-08-27

- **`check-feature-map.sh` 去掉 pyyaml 硬依赖**。首次把门禁接进真实 CI 就挂了：self-hosted 构建机上只有 python3、**没有 pip**（`pip: command not found`，退出码 127）。**门禁不该因为环境缺个第三方库就红**——现改为有 pyyaml 用它、没有则用针对本 schema 的内置解析器（不是通用 YAML 解析器，只认模板里出现的形态）。
- 降级路径由守卫测试覆盖（`FEATURE_MAP_PARSER=builtin` 钩子）：既验证它与 pyyaml 同判为通过，也验证它能抓到组件不匹配——**否则「解析出空数据于是没有错误」会是一种假绿**。降级路径不被测，就只会在出问题时第一次跑，这是 ADR 0009 同款。


## v1.7.1 — 2026-08-27

- **修 `automerge-tiers.sh` 前置门的判据：jq 的 `//` 对 false 与 null 一视同仁**。原判据写成 `.required_status_checks.strict // empty`，而正常保护里 `strict` 常为 `false`——`false // empty` 返回 empty，于是**配置正确的仓被判成「无分支保护」而拒绝判档**。改取 `.url`（保护存在时必为非空字符串）。守卫测试补反向 case：有保护（含 strict=false 形态）必须正常放行。
- **修 `check-feature-map.sh` 两个实战暴露的缺陷**（在给 PulseAgent 建首份地图时踩到）：① 正则不跳 JSX 注释，把已下线、被注释掉的路由当成真路由，strict 模式误报「未入图」；② 顶层包装组件（`<Route element={<ProtectedRoute><Onboarding/></ProtectedRoute>}>`）只抓最外层，而包装组件常是内联函数、没有对应文件，导致那条路由**无论怎么填都过不了校验**。现改为先剥注释、再穿透已知包装组件取内层功能组件。守卫测试锁死两者。
- **首份真实地图落地**：PulseAgent `docs/feature-map.yaml`，21 个功能全部带 known_traps，校验器 exit=0。建图过程本身就是价值证明——**抓出 7 处猜测错误**：5 个页面的 `i18n_prefix` 猜错（`credits`/`funnel` 等页面根本没有 i18n key，中英文硬编码）、外联的 API 前缀实际是 `/api/crm` 而非 `/api/outreach`、邀请码页面在 `/app/invitations` 但接口在 `/api/enterprise/invitation-codes`；另顺带发现 `CODEMAP.md` 把 `/app/credits` 写成了 `/app/credit`。
- 这是「判据写错导致门静默失效」在本次发布里的**第三次同型复现**，三次形态各不相同、都很隐蔽：① 管道 `| tail` 吞掉退出码，让报错的门禁返回 0；② `gh api` 404 把错误 JSON 打到 stdout，让「输出为空即无保护」永远为假；③ jq `//` 把 false 当空。**共同点：门禁本身在运行、也打印了正确信息，只有那一行判据是错的。** 这正是 ADR 0009 要求「门禁必须自证有效」的原因——三次都是被反向变异测试抓出来的，没有一次是靠读代码发现的。


## v1.7.0 — 2026-08-27

- **ADR 0011：验证闭环必须自治——人是 verifier 就是并行度上限**。前十个 ADR 解决的是同一件事：**怎么把代码安全送上生产**（变量路由 0006、无人值守 failover 0007、链路实测 0008、门禁自证 0009、接入对账 0010）。它们共享一个从未写下来的前提：**验证由人做**。把最近的真实故障按「谁完成了验证」重新归类，四件里有三件是「门禁绿着，而真相在别处」——CD 首跑红是人读 384 秒构建日志找到 `network:` 参数缺失；容器引擎卡死是人翻日志发现进程在等 GUI 对话框；可选依赖导致生产 502 是人回读源码发现类型注解在导入期求值。**再加一道门禁的收益在递减（已知错误正被逐个吃掉），而给 agent 一次验证能力的收益在递增——它对每个后续任务复用，而且可以并行。**
- **能力层 `templates/verification/verify-web.sh`**：agent 自己打开页面、采 console/失败请求/性能与内存指标/截图，产出机器可判的证据 JSON，越界即非零退出（同时是门禁）。能力来自浏览器调试协议通道——实测 `cdp('Performance.getMetrics')` 可取 `JSHeapUsedSize`/`Nodes`/`Documents`，配 navigation timing 得首屏耗时。**`curl` 200 只证明服务器回了字节，证明不了页面能用。**
- **该工具自身踩过绿色谎言并已修**：早期版本 `--url http://x` 打开一个无关错误页，因无 console 错误、无失败请求而报「✅ 验证通过」——缺的是「页面到底加载没加载」判据。现补 DOM 规模 + 主文档状态双判据，守卫测试锁死。诚实标注：主文档状态常因事件时序取不到（实测多为 0），真正兜底的是 DOM 规模判据。
- **地图层 `feature-map.template.yaml` + `check-feature-map.sh`**：功能名→路由→组件→进入条件→验证方式→已知坑，让「一张截图」「某某页面坏了」能被机械翻译成可复现的操作序列。**过期的地图比没有地图更危险**（让 agent 自信地走错），故校验器进 PR 门禁。**尤其校验路由↔组件对应**：只验路由存在不够——路由表里同时有 `/messages` 与 `/inbox` 时，地图写错一个照样通过而 agent 会被带到另一个页面（写模板时本人当场踩中，校验器抓出）。
- **技能测试层 `templates/skill-testing/`**（README + 可跑的 `run-skill-eval.js` workflow 脚本）：多 sub-agent 独立执行任务样本 → rubric 打分 → **两个模型交叉评分且分歧取低**（分歧说明 rubric 或任务描述不清，该改 fixture 而非 skill；累计 3 个即重写 rubric 维度）→ 与基线比对防退化（**基线只在人工确认后更新，自动更新基线等于没有基线**）。分三类属性测：触发准确性/执行正确性/结果质量——**只测结果质量是常见错误**，最常见的失败是根本没触发，而那时结果看着还正常。
- **自动合并分级 `templates/ci/automerge-tiers.sh`**：按**可逆性**分档。T1 纯文档/测试/文案 → CI 绿即合；T2 有运行时影响 → CI 绿 + 门禁自证有效 + 实际操作产品的证据 + 部署侧自动回滚；**T3 不可逆或影响面超出可验证范围（迁移/密钥/生产编排/流水线自身/真钱/认证授权）→ 永远人工，不接受任何证据豁免**。混合改动按最危险的文件定档，**不被大量安全文件稀释**。实测：本仓与 clawops 最近两个 PR 都被正确判为 T3（都改了流水线自身）。
- **诊断层 `templates/verification/capture-trace.sh`**：CPU trace 与 heap snapshot 按需采集，实测产出 681KB / 2,743 条 trace 事件与 32MB / 406,422 节点的堆快照，可直接拖进 DevTools 的 Performance / Memory 面板。**不进常态门禁**（单次快照数十 MB）。实现踩了两个真坑并记进注释：`Tracing` 绑在当前 target 上——先 `openOrReuseTab` 会换 target 导致 `Tracing.end` 报 "Tracing is not started"，正解是先开页再 start 再 reload；heredoc 是 ES module 上下文，`require('fs')` 与顶层 await 冲突，须用 `await import('node:fs')`。
- **修一个会漏掉首屏错误的真 bug**：`verify-web.sh` 早期版本在导航**之后**才 `Network.enable`，而 CDP 只推送订阅之后的事件——首屏的 console 错误与失败请求全部漏掉。修正时序（先 enable、再导航、已开页面则 reload）后，同一个生产站点的 console 错误从 **0 变成 4**。这正是「构建绿、单测过、`curl` 有 HTML，却漏掉运行时 ReferenceError」那类事故的复发点。
- **自动合并的前置门**：实测三个主力仓 `branches/main/protection` 全部 404、`rulesets` 全空——**零机械门**，CI 红也能点 Merge、谁都能直推 main 触发生产部署。**在这种仓上讨论自动合并等于在没有门的房子上装智能门锁**，故判定器内置前置检查（无保护即拒判档，退出码 30）。该检查自身也踩过同型坑：`gh api` 在 404 时把错误 JSON 打到 **stdout**，判据若写成「输出为空即无保护」就永远为假、门静默失效——改判实质字段并由守卫测试锁死。
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
