# Changelog

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
