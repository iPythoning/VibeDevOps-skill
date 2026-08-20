# xserver 重启恢复架构（reboot-idempotent build lane）

> 2026-08-20 事故收口：xserver（懒猫微服，不可变 overlay 系统）晨间重启，易失层
> （/etc /opt /usr/local、apt 包、用户账户、/var/lib/docker 镜像层）全部丢失，
> 15 个 self-hosted runner + mihomo 出境代理 + 守护单元整层消失，私有仓 CI/CD
> 自建车道死亡半天（叠加 GitHub hosted 账单故障 = 双车道全灭）。
> 本文档固化恢复架构；操作细节以 **`iPythoning/xserver-bootstrap` 仓的 README 为准**。

## 核心事实（构建机约束）

| 事实 | 后果 |
|---|---|
| `/` 是不可变 overlay，upper 每次开机重建 | `/etc` `/opt` `/usr/local`、apt 包、`gha` 用户重启即失 |
| `box-init` 每次开机 `rm -rf /var/lib/docker/*` 并自己重启 docker（L114-116） | 镜像层全丢；daemon.json 的 mirror/代理**开机路径无法生效**（hook 点都在 docker 重启之后） |
| 持久路径只有 `/lzcsys/data/**`、`/root`、`/etc/ssh` | 一切要长活的东西（runner 本体、恢复仓、secrets、buildx/mihomo 二进制）都放 `/lzcsys/data` |
| 判别易失看 **btrfs birth**（`stat -c %w`），不看 mtime | overlayfs copy_up 保留下层时间戳，mtime 会骗人 |

## 恢复架构（三层，全部在持久盘）

1. **状态仓** `/lzcsys/data/xserver-bootstrap`（= GitHub `iPythoning/xserver-bootstrap`）：
   `bootstrap.sh`（幂等恢复十步：apt→脚本→mihomo→daemon.json→gha(uid 钉死 19999)→
   runner 单元→enable→保温+compose→buildx→Tailscale）+ `snapshot.sh`（实况抓回仓库）+
   units/dropins/etc 快照 + manifest（enabled 实况）。
2. **secrets 盘** `/lzcsys/data/xserver-secrets/`（不进 git）：mihomo 二进制、
   provider-nodes.yaml（Mac launchd 每 2h 代拉订阅时**同步刷新此持久副本**）、docker-buildx 二进制。
3. **开机自动执行**（2026-08-20 新增，杜绝人工）：懒猫 box-init 官方钩子目录
   `/lzcsys/var/custom/hooks/data-disk-ready/`（持久分区，数据盘挂载后逐个执行）。
   钩子 `50-gha-bootstrap` 现场写入并 enable `xserver-bootstrap.service`（oneshot，
   After=network-online docker，跑 bootstrap.sh），`--no-block start` 兜底。

## Runner 纳管规则（对齐「注册 runner 即纳管」）

`scripts/xserver-runner-systemd.sh` **动态发现**：`/lzcsys/data/gha-build/runners/` 下凡
`.runner` + `.credentials` 同在的目录自动生成 `github-actions-<name>.service`
（User=gha + SupplementaryGroups=docker + Restart=always），无硬编码清单。
新仓注册 runner 三步：解包 `runner-base.tgz` → `config.sh`（token 走
`gh api -X POST repos/<org>/<repo>/actions/runners/registration-token`，经 127.0.0.1:7890）→
重跑该脚本。注册凭据在持久盘，**重启后无需重新注册**。
一个 runner 只许一个监管者（系统级单元）；proxy env drop-in 由 net-adaptive 动态维护。

## 出境代理端口控制（网络层强制，幂等）

7890 只对 127.0.0.0/8 开放：`mihomo.service.d/firewall.conf` 的 ExecStartPost iptables
（ACCEPT 127/8 + DROP 其余），随 mihomo 每次启动自动重应用；drop-in 进快照仓，
bootstrap 装回后首启即生效。**不依赖 mihomo allow-lan（应用层不可靠）。**

## 验收（重启后应全自动达成）

```bash
systemctl status xserver-bootstrap        # active (exited) + SUCCESS
systemctl list-units 'github-actions-*' --state=running   # = 注册 runner 数（当前 16）
curl -s -o /dev/null -w '%{http_code}' -x http://127.0.0.1:7890 https://api.github.com/zen  # 200
iptables -L INPUT -n | grep 7890          # ACCEPT 127/8 + DROP
```

改过 xserver 系统配置后：`bash /lzcsys/data/xserver-bootstrap/snapshot.sh` + commit push，
否则改动重启即失且快照仓不知情。
