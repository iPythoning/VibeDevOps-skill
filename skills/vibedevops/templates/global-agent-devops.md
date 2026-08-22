<!-- VIBEDEVOPS:MANAGED-DEVOPS:START -->
## VibeDevOps 受管 DevOps 规则

> 本节由 VibeDevOps 安装器从 GitHub 仓库幂等同步。所有 coding agent 共同遵守，不依赖某台机器的私有配置。

- Git 仓库是构建与交接的唯一事实源。Dockerfile、`.dockerignore`、基础镜像源顺序、digest、构建入口、CI/CD workflow、部署脚本、健康检查和回滚逻辑全部版本化。
- PR 自动执行 secret scan、lint、typecheck、test 与 build，全绿才允许合并。合并 `main` 即生产部署授权，随后自动构建一次不可变制品、推送、按 digest 部署、功能 smoke/canary，失败自动回滚并复验。
- 容器链路固定为 Xserver 构建优先、Mac fallback；GHCR 推送固定为 GitHub hosted 优先、Xserver fallback；云端只拉 digest。成功路径必须在 workflow 创建后 1800 秒内完成，超时取消并回滚。
- CI/CD 必过 job 的 `runs-on` 不写死 hosted 标签，由仓库变量路由（默认 hosted，故障期 `gh variable set` 切 self-hosted，恢复即删）。托管额度/账单故障只影响 hosted 计算，不影响 self-hosted 调度与 Packages/API/git；故障日先跑 runner-canary 实证当日连通与调度，禁止引用历史网络结论。长驻控制面 job 与构建 job 不得挤同一个单并发 runner。
- 路由自治优先于人工（ADR 0007）：账单/额度拒绝签名（job 0 步+无 runner）自动切自建 runner、hosted 探针恢复自动切回；断连型 job（failure 但 0 failed-step 且已分配 runner）自愈重跑；注册 runner 即纳管。网络路由是探测结果非配置，环境无关、只在变化时动作、不打断在跑 job。无人值守安全阀：只回收自己设的变量、runner 不在线不切。构建机出境代理的端口访问控制必须 iptables 网络层强制且幂等（应用层 allow-lan 不可靠，规则累积会成全开放隐患）。
- **新增仓库一律走这条线**：CI/CD 从 VibeDevOps 模板起步（pr-check/deploy 已内置变量路由），建仓后跑 `onboard-repo.sh <owner/repo>` 立即接入统一构建机（注册 runner + 设齐路由变量，注册即自动进入账单故障 failover 纳管）。**忘了跑也没事**：构建机上的 `onboard-reconcile.timer`（ADR 0010）每 30 分钟对账全部仓——有 `.github/workflows` 但缺 runner / 缺路由变量的仓自动接入；只做加法绝不覆盖已有变量值；不想被接入的仓写进 skip 清单。不走模板的仓库必须写明原因。每台构建机上一个 runner 只许一个监管者（系统级 service 单元），叠加监管会抢会话。
- Xserver 与 Mac 必须 checkout 同一 clean commit，使用仓库内同一个构建脚本。禁止服务器私有 Dockerfile、手工复制漂移或依赖本机 cache 才能成功；cache 只能提速。
- 大陆节点优先 `m.daocloud.io/docker.io/...@sha256:...`，单路径有界超时后切上游；所有 fallback 必须固定同一 digest。Xserver 的 Docker build 和临时容器显式使用 `--network host`，不得重启平台托管的 Docker daemon。
- 每次健康部署后只清理未引用旧镜像和过期 build cache。current、last-known-good、production/rollback tag 及其 provenance/SBOM 引用闭包必须保护；禁止 force 删除镜像，禁止自动删除 volume。
- 所有长期凭据使用最小权限；CI 优先短期身份。密钥不得进入 Git、argv、日志、镜像层或服务文件。
<!-- VIBEDEVOPS:MANAGED-DEVOPS:END -->
