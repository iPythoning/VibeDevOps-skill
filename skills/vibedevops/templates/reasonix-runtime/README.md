# Reasonix 常驻运行时

这套模板把原生 [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix) 配成仅监听本机的常驻服务，并自动补齐 Reasonix 的 OpenCode Go Provider。它不把 OpenChamber 的 `Reasonix-Go` 冒充成原生 Reasonix 进程。

## 前置条件

```bash
npm i -g reasonix
```

Reasonix v1.21.x 已内置 OpenCode Go 预设，安装器还需要 Node.js 来解析 `reasonix doctor --json` 的结构化结果。模板采用官方字段：`https://opencode.ai/zen/go/v1`、`OPENCODE_GO_API_KEY`、128K Provider 上下文，以及 DeepSeek/Kimi 的逐模型推理协议。

## 安装

交互安装会安全读取 API Key，不在终端回显：

```bash
./install.sh
```

自动化时从 stdin 输入，避免把密钥放进进程参数和 shell history：

```bash
printf '%s\n' "$OPENCODE_GO_API_KEY" | ./install.sh --api-key-stdin
```

也可以从仓库根目录一起安装：

```bash
./install.sh --with-reasonix-runtime
```

根安装器的这个显式选项也授权 Linux 启用 user lingering。直接运行运行时安装器时，Linux 首次安装需显式加 `--enable-linger`；否则脚本会在启动服务前停止并给出提示。

安装器会：

1. 备份并幂等更新 `~/.reasonix/config.toml`；已有 `opencode-go` Provider 不覆盖，并在改默认模型前通过 `reasonix doctor --json` 验证它确实声明了目标模型。
2. 把真实密钥写入 `~/.reasonix/.env`，当前文件及含旧密钥的备份均强制为 `0600`；配置文件只保存变量名。
3. 新配置将全局 `default_model` 指向 `opencode-go/deepseek-v4-flash`；已有配置保留原默认模型，常驻 wrapper 仍显式使用 Flash。官方 compaction 阈值设为允许的最高值 85%。
4. macOS 安装登录会话内自动拉起的 `launchd` KeepAlive；Linux 安装 `systemd --user` 的 `Restart=always` 服务，并检查 user lingering 以保证注销和重启后常驻。
5. 只监听 `127.0.0.1:8787`，启动后验证 `/healthz`。

高 compaction 阈值会保留更长的稳定前缀，但缓存命中率仍由实际请求前缀和上游计算，无法用环境变量锁定 90%。

## 验证

```bash
./health-check.sh
curl -fsS http://127.0.0.1:8787/healthz
```

OpenChamber 继续使用 `Reasonix-Go` 处理低成本循环；需要真正调用原生 Reasonix HTTP 服务的客户端应连接 `http://127.0.0.1:8787`。两者共享模型纪律，不共享进程或会话状态。

## 安全边界

- 无认证模式只允许 loopback，脚本会拒绝 `0.0.0.0` 和局域网地址。
- 安装器拒绝替换受管配置、凭据、wrapper 或服务文件的软链，避免重定向写入和密钥权限绕过。
- 不读取或复制 OpenCode 的 `auth.json`。OpenCode Go Key 必须由用户明确输入到 Reasonix 自己的凭据文件。
- 不把 `REASONIX_CACHE_OPTIMIZE`、`REASONIX_CONTEXT_BUDGET` 当作正式接口；Reasonix 的正式配置是 `config.toml` 和 `reasonix config compact-ratio`。
- 需要远程访问时不要改这个模板的监听地址；应另外配置 token/password、TLS 反向代理和访问控制。
