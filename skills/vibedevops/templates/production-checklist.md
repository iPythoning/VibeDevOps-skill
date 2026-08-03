# 上线即监控 + 环境可复现 清单

> 部署关的"验证穿透到功能层"在这里落地。上线前逐项打勾，打不齐的先记录在 HANDOFF.md 已知坑。

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
