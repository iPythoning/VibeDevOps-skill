# ADR 0007：路由由探测与信号自动驱动——无人值守 failover 闭环 + 网络自适应

- 状态：Accepted
- 日期：2026-08-17
- 扩展：[ADR 0006](0006-runner-vars-routing-quota-immunity.md)（手动变量路由）

## 背景

ADR 0006 把 `runs-on` 变成仓库变量路由，但切换是**手动**的（`gh variable set/delete`）。实战中暴露两个不足：

1. **切换靠人。** 托管 CI 账单欠费/额度耗尽发生在任意时刻，人不在场时门禁与 CD 全红，而自建 runner 全程在线闲置——瘫的不是算力，是没人去改变量。
2. **网络是二值假设。** 0006 隐含"要么托管可达、要么走固定构建机"，但真实构建机（家宽/跨境节点）的国际出口会**间歇**被 GFW/QoS 干扰：同一天经历直连通→抖动→完全封锁→恢复。把路由写死成"必走代理"或"必直连"，环境一变就断。

## 决策

**路由是探测与信号的结果，不是写死的配置。** 三条自治机制：

### 1. 无人值守 failover（`templates/ci/runner-failover.sh` + `hosted-canary.yml`）

- **检测**：托管 job 的账单/额度拒绝有稳定签名——`conclusion=failure` 且 `steps=0` 且 `runner_name` 为空（job 根本没启动）。watcher 定时扫哨兵仓识别此签名。
- **切换**：识别到故障 → 给纳管仓自动设变量组（切自建 runner + 区域源）。
- **恢复**：故障期定时 `workflow_dispatch` 一个钉死 `ubuntu-latest` 的探针仓（`hosted-canary.yml`，账单坏时被拒=零成本）；探针跑绿 = 托管计算恢复 → 自动删变量组切回。
- **纳管范围 = 自动发现**：owner 名下近期有推送 + 已注册 self-hosted runner 的仓自动进保护圈，新仓注册 runner 即纳管，无需登记。

### 2. 断连型 job 自愈重跑

self-hosted runner 的出境抖动会把跑到一半的 job 打成 `Abandoned`：`conclusion=failure` 但**没有任何 failed step** 且 runner 已被分配——这是基建签名，不是代码红。watcher 识别此签名自动 `rerun --failed`，每 run 上限 2 次（防死循环）。

### 3. 网络自适应（`templates/build-gate/net-adaptive.sh`）

定时（如每 3 分钟）+ 关键操作前：探测直连、代理到 git 托管面 → 决策 `DIRECT | PROXY | DOWN` → 应用到 runner 的 git 配置与出境 env。

- **环境无关**：直连通 → 清空全部代理配置、直连（"明天不需要 VPN" 零人工）；直连断+代理通 → 挂代理（"今天封锁"）；都不通 → 标记降级交由自愈/本地门禁兜底。
- **只在路由变化时动作**，不每次折腾；**忙 runner（有 Runner.Worker）跳过重启**，不打断在跑的 job。

## 安全阀（无人值守的护栏）

1. **只回收自己设的变量**（`managed` 状态标记）——人工设的路由永不被自动撤。
2. **runner 不在线的仓不切**——否则 job 永远 `queued` 是比"红"更危险的静默失败。
3. **发现失败沿用缓存不缩圈**——纳管清单拉取失败时不误删保护对象。
4. **并发锁 + 残锁超时回收**——watcher 不重入。
5. **代理端口网络层收口**：代理工具的 `mixed-port` 常绑 `*`，应用层 `allow-lan` 语义不可靠——端口访问控制必须由 iptables 网络层强制（只放本地 + 容器网段，拒 overlay/LAN），不靠应用层。见 `references/egress-proxy.md`。

## 结果

- 托管额度/账单故障、构建机网络抖动，都从"人肉救火"降为"系统自治"：检测→切换→恢复→自愈全自动，路由随环境实时适应。
- 代价：多一层探测器与状态文件（仓库/机器级状态，需在 HANDOFF 留痕当前路由）；无人值守要求安全阀严格（护栏错误比不自动更危险）。
- 未覆盖：托管方**整体不可用**（git/API/Packages 全断）仍无法按政策发布——那超出路由自治范围，维持"事前写明无法发布"posture（ADR 0006 结论不变）。
