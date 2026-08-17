# CI/CD 最佳实践

## 默认发布契约

1. **短分支、小批量**：变更通过短生命周期分支进入 PR，降低合并和回滚半径。
2. **PR 是验证与授权边界**：自动执行 secret scan、lint、typecheck、test、build；全绿并完成审核才合并。
3. **合并即发布授权**：`push main` 自动进入 CD，不再添加人工审批。需要发布时间窗口时延迟合并。
4. **构建一次、逐级推广**：制品以 Git SHA 与 digest 标识，生成 provenance/SBOM；测试、canary、生产使用同一份不可变制品。
5. **渐进发布**：优先 canary/blue-green；用错误率、延迟、饱和度和业务成功率决定自动推进或回滚。
6. **验证到功能层**：部署后发真实请求验证关键路径，不只检查进程或 `/health`。
7. **失败自动止损**：smoke/canary 失败自动推广上一绿制品，回滚后再次验证；工作流仍保持失败并告警。
8. **可追溯**：记录 commit、制品 digest、workflow URL、部署目标、指标判定和回滚结果。
9. **制品有生命周期**：成功发布后清理部署机未引用的旧镜像与 build cache；Registry 设每日 retention。current/last-known-good、生产/回滚 tag 与至少 30 个最新 package versions 永久/窗口内保护。
10. **容灾有顺序与截止时间**：Xserver 构建优先、Mac fallback；GitHub hosted push 优先、Xserver fallback；独立 hosted watchdog 与部署控制器共同强制从 workflow 创建到原子完成部署不得超过 30 分钟，超时取消并回滚。

## 安全与可靠性

- 工作流默认 `permissions: contents: read`，仅按 job 增加权限；云端身份优先 OIDC 短期 token。
- 第三方 Action 锁定完整 commit SHA，由 Renovate/Dependabot 更新，避免浮动标签供应链风险。
- 生产部署串行；PR 检查对同一 PR 取消旧运行，既防竞争也节省额度。
- secrets 只在部署 job 注入并限制到目标 environment；不写日志、不落制品。
- 数据库采用 expand-contract；不可逆迁移与应用发布解耦。危险功能用 feature flag 控制暴露，而不是卡住已合并部署。
- 自动回滚失败时立即告警并进入 RUNBOOK；禁止静默吞错或继续部署下一版本。
- 在 canary 前由独立部署控制器建立带充足 TTL 的可续租回滚租约，在推广开始前续租；只有生产功能门和指标门全绿后，才由控制器原子完成“更新 last-known-good + 解除租约”。这样即使 Actions 整条 run 被取消、runner 失联或 GitHub 不再调度 rollback job，控制器仍会自动恢复 last-known-good。显式 rollback job 用于快速恢复，租约是最终保险。
- 发布过程中禁止把“取消 workflow”当作回滚操作；取消只停止 GitHub 调度，不保证已执行的生产副作用被撤销。
- 镜像清理禁止 `docker image rm --force` 和自动删除 volume；所有容器引用都保护。`docker builder prune --force` 仅关闭交互确认，必须限定过期且未使用 cache。清理失败单独告警并在下一次构建前重试；容量或清理债务超限时禁止制造新镜像，但不因容量维护失败回滚已经验证为健康的生产版本。
- hosted CI 额度或容量不足时切换到受监控的 self-hosted runner/外部 CD 控制器；正常发布路径仍由 `push main` 自动触发，不能退化为人工命令。切换机制见 ADR 0006：`runs-on` 由仓库变量路由（`CI_RUNNER`/`CD_RUNNER`），故障日先跑 `templates/ci/runner-canary.yml` 实证调度与连通，再一条 `gh variable set` 完成切换；恢复即删变量回 hosted。额度/账单故障只影响 hosted 计算，不影响 self-hosted 调度与 Packages/API/git（2026-08-17 实证）。

## 持续交付与持续部署

DORA 将持续交付定义为软件始终处于可按需安全发布状态；持续部署则进一步自动把通过门禁的变更发布到生产。本方案明确选择持续部署：人工决策在 PR 审核/合并，合并后的机械步骤全部自动化。

## 模板脚本契约

- `scripts/verify.sh`：对合并后的 main 运行完整确定性门禁。
- `scripts/auth-deploy.sh`：用 GitHub OIDC 换短期身份；不得输出 token。
- `deploy.sh`：实现 `last-known-good`、`verify-artifact`、`arm-rollback <lkg> --ttl <duration>`、`renew-rollback --ttl <duration>`、`canary`、`promote`、`complete-deployment <artifact> --deadline-epoch <unix-seconds>`、`rollback`、`cleanup-images --keep <current> --keep <lkg> --retention-hours <n>`、`cleanup-images --retry-pending --retention-hours <n>`、`image-capacity-check --max-disk-percent <n> --max-cleanup-debt <n>`；回滚租约必须由 Actions runner 之外的部署控制器持有，`complete-deployment` 只在 deadline 前且生产功能门与指标门全绿、Registry 的 `production`/`rollback` tag 已更新后原子更新 last-known-good 并解除租约。
- `scripts/cleanup-ghcr-versions.sh` + `image-retention.yml`：每日清理过期 GHCR versions，最小权限仅为 `contents: read` 与 `packages: write`。
- `scripts/smoke-test.sh <canary|production>`：验证真实关键业务路径。
- `scripts/metrics-gate.sh <canary|production>`：按错误率、延迟、饱和度和业务成功率返回明确退出码。
- `scripts/notify-deploy-failure.sh`：通知流水线、canary、推广或回滚失败，并附 workflow URL。

## 建议观测指标

- DORA：部署频率、变更前置时间、部署失败恢复时间、变更失败率、可靠性。
- 发布门槛：5xx/错误率、P95/P99 延迟、资源饱和度、核心业务成功率。
- 流水线：排队时间、执行时间、失败阶段、自动回滚次数与回滚成功率。

## 官方依据

- [DORA：Continuous delivery](https://dora.dev/capabilities/continuous-delivery/)
- [DORA：Trunk-based development](https://dora.dev/capabilities/trunk-based-development/)
- [GitHub Actions：OpenID Connect](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [GitHub Actions：Concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
- [GitHub Actions：Environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
- [GitHub Actions：Self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners)
- [SLSA v1.2：Provenance](https://slsa.dev/spec/v1.2/provenance)
