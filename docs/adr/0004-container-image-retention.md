# ADR 0004：容器镜像必须有本机、部署机与 Registry 三层生命周期

- 状态：Accepted
- 日期：2026-08-10

## 背景

多架构镜像一次构建通常同时产生 manifest、架构子 manifest、SBOM/attestation 与 SHA tag。只清理 dangling image 无法阻止部署机磁盘和 GHCR versions 持续增长；完全依赖人工清理又会在资源紧张时才暴露。

## 决策

采用三层自动治理：开发机每日清理 7 天前的未引用镜像和 build cache；每次构建前重试部署机清理欠账并执行容量门禁，成功部署后清理服务器旧镜像，显式保护 current 与 last-known-good；生产功能门和指标门通过后先把旧 LKG 标记为 `rollback`、新制品标记为 `production`，再完成部署。GHCR 每日清理 superseded versions，保护生产/回滚 tag、最新 30 个 versions 和 6 小时内的新构建；通过 OCI Distribution API 同时遍历 index 的 `manifests[]` 与 provenance/SBOM 的 `subject.digest`，构造受保护制品和供应链证据的双向递归闭包，图不完整时整个 package 保守不删。

生产制品路径固定为 Xserver 构建优先、Mac 构建 fallback，GitHub hosted push GHCR 优先、Xserver push fallback。控制 job 只把构建派给 online 且 idle 的专用 runner；考虑状态检查与入队存在竞态，另有独立 hosted watchdog 从 workflow 创建时间起计时并在 1800 秒强制取消。同一份临时 image artifact 在推送路径间传递，云端仍只推广一个 digest；`complete-deployment` 也必须在同一绝对 deadline 前完成，否则回滚。

删除脚本默认 dry-run，执行必须显式 `--apply`。Docker image 删除永不使用 `--force`，所有运行中或停止容器引用均保护，不自动删除 volume 或停止容器。`docker builder prune --force` 只关闭交互确认，仍限定过期且未使用 cache。清理失败触发容量告警并形成债务；债务未销账或磁盘超过阈值时阻止下一次构建，但不回滚已经通过功能和指标门的健康版本。

## 结果

镜像增长从事故处理变成持续门禁；回滚版本和在用镜像有机械保护；构建与推送分别具有确定的 fallback 和时限。代价是部署接口增加 `cleanup-images`/容量/deadline 契约，Registry workflow 需要 `packages: write`，runner 路由需要一个仅有 Administration read 的 fine-grained token，且旧镜像删除后只能从 Registry 重拉或由源码重建。
