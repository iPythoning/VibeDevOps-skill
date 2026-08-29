# ADR 0013：车道模型 B——hosted 主、self-hosted 只做额度耗尽 failover，两车道必须同步

## 背景

ADR 0006/0007 把 runner 路由做成变量驱动 + 无人值守 failover。落地时出现两个真问题：

1. **回切被做成了炸弹**（2026-08-28 拆除）：旧 failover 在"探针成功即恢复"时对**全部**纳管仓
   无差别 `del_bundle`，单次触发、无 dry-run、`2>/dev/null` 吞删除失败、连人工设的变量都删。
   它从未成功执行过一次，首次真实触发就会作用于 42 个生产仓。
2. **车道语义被理解反了**：一度以为"hosted 永久退役、self-hosted 是主车道"，于是仓被**钉死**
   在 self-hosted。实际是——**私有仓每月有免费 hosted 额度**，额度耗尽才该走 self-hosted，
   新月重置又该切回 hosted。钉死 self-hosted 会白白不吃免费额度，且 xserver 挂 = job 无限排队
   （比全停更糟，是静默挂：钉了 `[self-hosted,xserver]` 的 job 不会自动回落 hosted）。
3. **两车道不同步会假红**：同一个 job 落在 hosted 有 ruby、落在 self-hosted 没 ruby → 打分器
   `hosted 绿 / self-hosted 红`。lane 切换若不保证工具/源一致，failover 本身制造事故。

## 决策

**一、车道模型 B：hosted 是主，self-hosted 只做额度耗尽 failover。**
- 探针只看一个 hosted 探针仓的 job（`steps==0 且 runner_name 空` = 额度拒绝），**绝不拿业务仓判额度**。
- 额度耗尽 → 切 self-hosted；额度重置 → 切回 hosted。默认态是 hosted（`CI_RUNNER` 不设）。

**二、切换必须安全（治老炸弹的病根）。**
- **只在模式真正切换时动作**，不是每次探针成功都动。
- 切回 hosted **只删本脚本 `managed_list` 里自己设过的仓**，绝不碰人工/reconcile 设的变量。
- 删除失败**不吞、告警**；runner 不在线的仓不切（排队是更危险的静默失败）。
- 该逻辑必须有守卫测试 + 反向变异（切回改用全量清单即 FAIL）。

**三、两车道必须同步——同一 job 两车道结果一致。**
- **工具齐备契约**：`lane-parity-manifest.txt` 列 self-hosted 必须具备、hosted 自带且 workflow 会用的命令。
- **切换前 parity 门**：切 self-hosted 前跑 `check-lane-parity.sh`，缺工具即告警（`LANE_PARITY_CMD`）。
- **源走变量不写死**：镜像/pip/npm 前缀随 bundle 变量路由（self-hosted 用大陆镜像、hosted 用官方源，**出同一产物**）。
- **按需冒烟比对**：需要强证明时，同一 workflow 两车道各跑一次比结果。

**四、双 owner 协同。** runner-failover 是车道**唯一 owner**，把当前车道写进 `LANE_MODE` 变量；
onboard-reconcile 读 `LANE_MODE`，`hosted` 态**不补 `CI_RUNNER`**——否则会把 failover 刚切回 hosted 的仓又钉回去。

## 结果

- 免费 hosted 额度被正常吃满，self-hosted 只在耗尽期承载；xserver 挂在额度可用期可回落 hosted。
- 老回切炸弹的病根（无界批量删 + 吞错 + 不可测）被 `managed_list` 安全阀 + 守卫测试根治。
- 车道漂移（缺工具）在**切换前**或日常巡检被抓，不再表现为业务仓假红。
- 代价：探针仓 + `LANE_MODE` 变量 + parity 检查是新的运维面；两 owner 靠 `LANE_MODE` 协同，
  该变量丢失会退化为"reconcile 按默认 selfhosted 补变量"（安全侧，不会误切 hosted）。
