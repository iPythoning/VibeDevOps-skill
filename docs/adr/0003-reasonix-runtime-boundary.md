# ADR 0003：原生 Reasonix 运行时与 OpenChamber Agent 分层

- 状态：已接受
- 日期：2026-08-10
- 决策者：用户 / Codex

## 背景

OpenChamber 的 `Reasonix-Go` 只是绑定 `opencode-go/deepseek-v4-flash` 的 Agent 配置，不会调用原生 Reasonix 进程。原生 Reasonix 虽已能长期运行，但常驻服务、Provider 配置与健康检查此前只存在于单机，无法通过 VibeDevOps 复用。

## 决策

新增独立 `reasonix-runtime` 模板：macOS 使用 `launchd` KeepAlive，Linux 使用 `systemd --user` Restart；服务仅监听 loopback。Provider 采用 Reasonix 官方 OpenCode Go 预设字段，真实 Key 只进入 Reasonix home 的 `0600` `.env`，配置只保存 `api_key_env`。安装器备份并保留已有 Provider，不读取 OpenCode 的凭据存储，也不宣称环境变量能锁定缓存命中率。

## 后果

新机器可复现本机的原生 Reasonix 常驻能力，并能机械验证配置、服务和 `/healthz`。OpenChamber 与原生 Reasonix 共享路由纪律，但保持独立进程和会话。远程暴露、TLS 与 token/password 认证不属于本模板，必须单独设计。
