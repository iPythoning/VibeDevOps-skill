<!-- VIBEDEVOPS:MANAGED-DEVOPS:START -->
## VibeDevOps 受管 DevOps 规则

> 本节由 VibeDevOps 安装器从 GitHub 仓库幂等同步。所有 coding agent 共同遵守，不依赖某台机器的私有配置。

- Git 仓库是构建与交接的唯一事实源。Dockerfile、`.dockerignore`、基础镜像源顺序、digest、构建入口、CI/CD workflow、部署脚本、健康检查和回滚逻辑全部版本化。
- PR 自动执行 secret scan、lint、typecheck、test 与 build，全绿才允许合并。合并 `main` 即生产部署授权，随后自动构建一次不可变制品、推送、按 digest 部署、功能 smoke/canary，失败自动回滚并复验。
- 容器链路固定为 Xserver 构建优先、Mac fallback；GHCR 推送固定为 GitHub hosted 优先、Xserver fallback；云端只拉 digest。成功路径必须在 workflow 创建后 1800 秒内完成，超时取消并回滚。
- Xserver 与 Mac 必须 checkout 同一 clean commit，使用仓库内同一个构建脚本。禁止服务器私有 Dockerfile、手工复制漂移或依赖本机 cache 才能成功；cache 只能提速。
- 大陆节点优先 `m.daocloud.io/docker.io/...@sha256:...`，单路径有界超时后切上游；所有 fallback 必须固定同一 digest。Xserver 的 Docker build 和临时容器显式使用 `--network host`，不得重启平台托管的 Docker daemon。
- 每次健康部署后只清理未引用旧镜像和过期 build cache。current、last-known-good、production/rollback tag 及其 provenance/SBOM 引用闭包必须保护；禁止 force 删除镜像，禁止自动删除 volume。
- 所有长期凭据使用最小权限；CI 优先短期身份。密钥不得进入 Git、argv、日志、镜像层或服务文件。
<!-- VIBEDEVOPS:MANAGED-DEVOPS:END -->
