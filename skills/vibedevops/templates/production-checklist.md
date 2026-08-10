# 上线即监控 + 环境可复现 清单

> 部署关的"验证穿透到功能层"在这里落地。上线前逐项打勾，打不齐的先记录在 HANDOFF.md 已知坑。

## 零、CI/CD 主链

- [ ] 短生命周期分支 + PR；required checks 全绿才合并，禁止绕过 main 直接推送。
- [ ] PR 合并 main 自动触发 CD；`workflow_dispatch` 只用于重试/回滚，不是正常发布入口。
- [ ] 制品只构建一次，以 commit SHA/digest 标识，并在环境之间推广同一份不可变制品；记录 provenance/SBOM。
- [ ] Actions 使用最小 `permissions`，第三方 Action 锁定完整 commit SHA；部署身份优先 OIDC 短期凭证。
- [ ] 生产部署串行；先 canary/blue-green，再按真实指标自动推进或回滚。
- [ ] 功能层 smoke test、错误率/延迟/饱和度门槛和自动回滚已机械化；回滚后再次验证。
- [ ] canary 前由独立部署控制器建立带充足 TTL 的可续租回滚租约，推广前续租，生产全绿后原子更新 last-known-good 并解除；整条 CI run 被取消或 runner 失联也能安全恢复。
- [ ] 数据库使用 expand-contract，危险功能用 feature flag；应用回滚不依赖逆向执行破坏性迁移。
- [ ] 每次发布记录 commit、制品 digest、每个功能/指标门禁 outcome、部署结果和回滚证据。
- [ ] 成功部署后自动清理部署机未引用旧镜像/build cache，显式保护 current 与 last-known-good，禁止 `docker image rm --force`、不删 volume；下一次构建前重试清理欠账并执行容量门禁。
- [ ] GHCR/Registry 每日 retention 已启用：生产/回滚 tag 受保护，至少保留最新 30 个 versions，新构建至少有 6 小时安全窗。
- [ ] hosted CI 额度和 runner 在线状态有监控；额度不足时自动路由 self-hosted runner/外部 CD，不退回人工发布。
- [ ] Xserver 构建失败会自动切 Mac，GitHub hosted push 失败会自动切 Xserver；只选择 online/idle 专用 runner，独立 hosted watchdog 在 1800 秒取消超时 workflow，`complete-deployment` 也机械拒绝过期发布。

## 一、监控四件套（最低成本，半天能搞完）

- [ ] **`/health` 端点返回依赖真实状态**：ping 一次 DB / 缓存 / 关键下游，任何一个挂了返回 503。
      ❌ 反模式：硬编码 `return 200`——负载均衡看到绿，用户看到白屏。
- [ ] **错误追踪**：Sentry（或同类）接入，DSN 走 Infisical 注入，不入库。
- [ ] **可用性监控**：UptimeRobot 免费档盯 `/health`，5 分钟间隔。
- [ ] **告警到人**：邮件 / Telegram / 微信任一，半夜能叫醒。

## 二、环境可复现（新人 5 分钟跑起来）

- [ ] 版本锁定文件存在：`.nvmrc` / `.python-version` / `mise.toml` / `go.mod`（按语言选一）
- [ ] 依赖安装一条命令：`npm ci` / `pip install -r requirements.txt` / `go mod download`
- [ ] 密钥一条命令：`infisical run --env=dev -- <启动命令>`（见 `security/SECRETS.md`）
- [ ] README 验收标准：**新机器从 clone 到跑通 ≤ 5 分钟**，超过就改 README 直到达标
- [ ] （可选进阶）`devcontainer.json`——VS Code / GitHub Codespaces 一键环境

## 三、依赖更新

- [ ] `renovate.json`（见 templates 同目录）或 Dependabot 已启用
- [ ] 规则：非 major 分组周更；major 单独 PR 人工过目 breaking changes
