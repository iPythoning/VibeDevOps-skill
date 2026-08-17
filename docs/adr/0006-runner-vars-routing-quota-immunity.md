# ADR 0006：CI/CD runner 由仓库变量路由，托管额度/账单故障即时免疫

- 状态：Accepted
- 日期：2026-08-17

## 背景

托管 CI 的两种资源故障（额度耗尽：job 排队或静默不跑；账单失败：job 被 3 秒拒绝，报
`recent account payments have failed`）都会让 hosted runner 上的门禁与 CD 全线红掉。
2026-08-17 实战中账单欠费同时瘫痪多仓 CI/CD，而各仓已注册的 self-hosted runner 全程在线闲置——
瘫痪的不是算力，是 `runs-on:` 里写死的 `ubuntu-latest`。

同日 canary 实测（两个私有仓，账单欠费状态下）：

1. **账单/额度只影响 hosted job 的计算，不影响 self-hosted 调度**——self-hosted job 照常派发执行；
   Packages（GHCR 推拉）、API、git push/pull 也全部正常。
2. 大陆构建机→`github.com` 当日 200（1.9s），`actions/checkout` 成功——历史"被 RST 当不了 runner"
   的结论有时效性，**必须以当日 canary 为准，不能引用旧结论**。
3. 此前退回 hosted 的另两个根因各有机械解法：容器 job 的 workspace 属主残留 → 仅 self-hosted
   生效的 chown 收尾步；buildx 的 gha cache 导出 TLS 失败 → cache-from/to 切 `type=inline`。

## 决策

1. **workflow 里不写死 runner。** 所有必过 job 的 `runs-on` 走仓库变量：
   `runs-on: ${{ vars.CI_RUNNER && fromJSON(vars.CI_RUNNER) || 'ubuntu-latest' }}`
   （CD job 用 `CD_RUNNER`）。默认值维持 hosted 优先的房规不变。
2. **切换与恢复是变量操作，不是代码改动。** 故障期
   `gh variable set CI_RUNNER --body '["self-hosted","<builder-label>"]'`，恢复后 `gh variable delete`。
   分钟级生效、无需重跑 PR 流程、无 workflow 历史噪音。
3. **区域特化随变量走。** 容器/服务镜像前缀（`CI_REGISTRY_MIRROR`）、pip/npm 源
   （`CI_PIP_INDEX_URL`/`CI_NPM_REGISTRY`）、buildx cache（`CD_BUILD_CACHE_FROM/TO`）同套变量路由；
   默认值 = 官方源（hosted 适用），降级期 = 镜像站（大陆构建机适用）。
4. **故障日先跑 canary 再下结论。** 用 `templates/ci/runner-canary.yml` 探针分层定位：
   self-hosted 能否调度、构建机到 git 托管面/镜像面各域名的连通实况。禁止引用历史网络结论。
5. **控制面 job 与构建 job 不能挤同一个单并发 runner。** 长驻型控制 job（deadline watchdog 等）
   路由到独立 runner 池（如 mac-builder），否则会把唯一构建 slot 占满形成自饿死。
6. 每台构建机保持双注册：`self-hosted,linux,x64,<builder>` 主力 + `self-hosted,macOS,mac-builder`
   fallback（安装器：`templates/build-gate/install-github-runner.sh`）。

## 结果

- 额度/账单故障从"发布停摆等修账单"降级为"一条变量命令的路由切换"，PR 门禁与 CD 全程可用；
  `templates/build-gate/README.md` 记录的降级缺口 ④ 中"托管资源故障"这一失效模式被关闭。
- 托管方**整体不可用**（git/API/Packages 全断）仍未覆盖——那要求发布控制面完全脱离托管方，
  超出本 ADR 范围；维持"事前写明该模式下无法按政策发布"的posture 不变。
- 代价：workflow 里多一层表达式；变量是仓库级状态，需在 HANDOFF/BUILD-EVIDENCE 里留痕当前路由。
