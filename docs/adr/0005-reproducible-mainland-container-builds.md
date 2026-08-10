# ADR 0005：大陆容器构建必须仓库化并固定同一 digest

- 状态：Accepted
- 日期：2026-08-10

## 背景

Docker Hub 在大陆构建节点可能超时；仅在 Mac/Xserver 手工配置 daemon mirror 会让构建依赖机器私有状态，GitHub 和新机器无法复现。

## 决策

1. Dockerfile、`.dockerignore`、基础镜像顺序、digest 和构建入口全部进入业务仓库。
2. 大陆 Xserver/Mac 先使用 DaoCloud 推荐的 `m.daocloud.io/docker.io/...` 完整前缀；Alpine 包使用官方 mirror 列表收录的阿里云公共镜像，单路径默认 150 秒超时。
3. 失败后同时切 Public ECR 与 Alpine 官方 `dl-cdn`；两条基础镜像路径必须解析到同一 OCI index digest，包仍由 Alpine 签名与固定版本校验。
4. GitHub hosted CI 直接使用 Public ECR，但仍运行同一仓库构建入口和真实容器 smoke test。
5. 本机 cache 与 daemon mirror 只能优化速度，不得成为正确性条件；生产机仍只按 GHCR digest 拉取。

## 结果

镜像定义不再分叉，冷机器 clone 后即可构建。镜像站不可用会显式失败并切换，不会无限等待；上游内容变化由 digest 校验阻断。
