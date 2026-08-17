# 危险命令分级与破坏性操作前备份

Agent（或人）在生产机上执行 shell 时的三级防线。可作为 PreToolUse hook、
运维脚本 preflight、或 RUNBOOK 检查项的判定素材。

## 三级分级

| 级别 | 处置 | 判定 |
|---|---|---|
| **Blocked** | 永远拒绝，给出替代 | 不可逆且无业务正当性 |
| **Dangerous** | 先自动备份，再要求显式确认 | 可逆性取决于事前备份 |
| **Warning** | 提示影响面，确认后执行 | 影响大但常规 |

### Blocked（拒绝 + 替代建议）

| 模式（regex 素材） | 替代 |
|---|---|
| `rm\s+(-[a-z]*[rf][a-z]*\s+)*(/\|/\*)(\s\|$)` （根目录递归删除） | 删除具体路径，绝不对 `/` 递归 |
| `dd\s+.*of=/dev/(sd\|nvme\|disk)` | 落文件再校验，不直写块设备 |
| `mkfs\.` 任意变体对已挂载设备 | 先 `umount` + 双人确认设备名 |
| `:\(\)\s*{\s*:\|:&\s*};:` （fork bomb） | 无 |
| `chmod\s+(-R\s+)?777\s+/(\s\|$)` | 对具体路径给最小权限 |
| `docker\s+(image\s+)?rm\s+.*--force` / 自动删 volume | 走镜像生命周期模板的保护式清理 |
| `git\s+push\s+.*--force(\s\|$)`（对共享分支） | `--force-with-lease` + 分支保护 |

### Dangerous（备份后确认）

`rm -r` 任意非根路径 · `DROP TABLE`/`TRUNCATE`/全表 `UPDATE` · `docker system prune`
（**必须限定 dangling/until 过滤，禁 `-af` 裸跑**——与镜像保留纪律冲突的修复建议一律改写）·
覆盖式重定向写配置文件 · `crontab -r` · `systemctl disable` 生产服务

### Warning（提示影响面）

服务重启 · nginx reload · 防火墙规则变更 · 包管理器全量升级

## 受保护路径清单（Dangerous 升 Blocked）

`/etc` `/boot` `/usr` `/var/lib/docker` `/var/lib/postgresql` 数据库数据目录 ·
生产 `.env` · 证书目录 · 任何 `*_pgdata` / 数据卷挂载点

## 破坏性操作前：manifest 驱动的备份

裸 `cp -r` 备份在恢复时会丢上下文（备份自哪、为什么、对应哪条命令）。备份必须带 manifest：

```
backup-<UTC 时间戳>/
├── manifest.json   # {"when": ..., "command": <原始命令>, "paths": {"<原路径>": "<备份内路径>"}, "operator": ...}
└── files/...
```

- 恢复 = 读 manifest 逐路径放回，可精确、可审计；
- 备份目录设保留窗口（如 7 天）自动清理，避免变成第二个磁盘炸弹；
- RUNBOOK 的回滚步骤必须引用 manifest 路径，不写"从备份恢复"这种没有坐标的话。

## 体检/诊断输出契约

任何健康检查、诊断脚本的每条 issue 必须同时给出四件套：
**阈值 + 当前值 + severity + 一条可直接复制执行的修复命令**。
只报"磁盘紧张"不给 `df` 数值和清理命令的检查项，等于没写。
修复命令必须符合本文件分级（禁止把 `docker system prune -af` 当修复建议）。
