# 容器镜像生命周期

这层模板同时处理两种堆积：部署机/开发机的 Docker 镜像与 build cache，以及 GHCR 中持续构建产生的多架构 manifest、子 manifest 和 SHA tag。默认清理命令全部是 dry-run；只有明确的 `--apply` 或安装本机定时守卫才会删除。

## 本机与部署机

```bash
./cleanup-docker-images.sh
./cleanup-docker-images.sh --apply --retention-hours 168 --keep-per-repository 5 --prune-build-cache
```

安全不变量：

- 禁止 `docker image rm --force`；Docker 会再次拒绝竞态中被容器占用的镜像。`docker builder prune --force` 只关闭交互确认，仍只处理超过保留期的未使用 cache。
- 所有运行中或已停止容器引用的镜像都保护；每个 repository 的最新 5 个镜像也保护。
- `--protected-file` 可额外写入 current/last-known-good digest，每行一个。
- 不自动删除 volume 和停止容器。脚本会报告停止容器数量，避免把有状态数据当缓存清掉。

本机每日守卫：

```bash
./install-local-guard.sh
```

macOS 使用 launchd，Linux 使用 systemd user timer；Docker 未运行时安全退出，下次调度再检查。
高频构建机可收紧为 `./install-local-guard.sh --retention-hours 24 --keep-per-repository 2`；所有容器引用仍然优先保护。
已用 `gh auth refresh -s delete:packages,read:packages` 明确授权的个人开发机可加 `--with-ghcr`，每天 04:00 自动治理该账号的全部 GHCR packages。仓库根安装器分别用 `--with-image-lifecycle` 安装 Docker 守卫、`--with-ghcr-retention` 在明确扩大 token 权限后再增加 GHCR 守卫。

## GHCR

```bash
./cleanup-ghcr-versions.sh --owner OWNER --package PACKAGE
./cleanup-ghcr-versions.sh --owner OWNER --package PACKAGE --apply
```

默认每个 package 永久保留最新 30 个版本，保护 `latest/stable/production/prod/rollback/last-known-good/lkg` tag，并跳过 6 小时内仍可能被索引或签名的版本。清理器先从 GHCR Distribution API 拉取每个 digest 的 OCI manifest/index，沿 `manifests[]` 正向边递归保护 tagged/untagged 子 manifest，也沿 `subject.digest` 反向边保护 provenance/SBOM referrer；只有完整引用图证明不在保护闭包中的过期版本才会删除。任一 manifest 无法读取或图不完整时，该 package 本轮候选数强制为 0。`--protected-file` 可额外保护部署控制器记录的 digest。大量多架构构建应在 CI 中每天调度，避免每次 build 产生的 manifest、架构镜像与 attestation 无限累积。

生产流水线必须在构建前实现 `deploy.sh cleanup-images --retry-pending` 与 `image-capacity-check`；上一次清理欠账未销账或磁盘超过阈值时停止新构建。生产双门禁通过后，先把旧 LKG 标成 `rollback`、新制品标成 `production`，再原子完成部署，确保每日 retention 永远看得见当前和唯一回滚制品。

生产清理失败是容量告警，不应回滚已经通过功能和指标门的健康版本；但下一次部署前必须检查磁盘/Registry 配额并重试清理。
