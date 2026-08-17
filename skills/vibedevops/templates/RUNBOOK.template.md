# RUNBOOK — 上线、回滚与事故应急（__PROJECT_NAME__）

> 出问题时没人有时间现想流程。本文件是"半夜被叫醒也能照着做"的预案。
> 任何 agent 执行部署/回滚前必读；流程变更时同步更新本文件。

正常发布只走 `push main` 自动 CD，不以本 RUNBOOK 代替流水线。手工命令仅用于自动回滚失败后的事故恢复，并必须记录操作者、目标 commit/制品和验证结果。不要用“取消 workflow”代替回滚：canary 前必须由独立部署控制器持有带 TTL 的回滚租约，流水线失联时自动恢复 last-known-good。

## 一、上线即留退路

每次部署前自问并写下答案：**"这步怎么 revert？"**

- 代码变更：优先让 CD 重新推广上一份已验证的不可变制品；随后用 `git revert <commit>` 恢复 main，避免生产与主干长期分叉
- 配置变更：改前值记在 HANDOFF.md，改后验证不过立即还原
- 跨服务：一次只改一个服务，改完验证再下一个

## 二、数据库变更纪律（vibe coding 重灾区）

0. **任何破坏性操作前先落带 manifest 的备份**（时间戳、原命令、路径映射三要素，见
   `references/dangerous-commands.md`）；回滚步骤引用 manifest 路径，不写没有坐标的"从备份恢复"。
1. **迁移前先备份**，一行命令的事：
   - PostgreSQL：`pg_dump -Fc $DATABASE_URL > backup-$(date +%F-%H%M).dump`
   - MySQL：`mysqldump $DB_NAME | gzip > backup-$(date +%F-%H%M).sql.gz`
   - SQLite：`cp data.db data.db.bak-$(date +%F-%H%M)`
2. **expand-contract 模式**：删字段/改字段拆成两次部署——
   - 第一次：加新字段，代码同时读写新旧（expand），部署
   - 第二次：确认无依赖后删旧字段（contract），部署
   - ❌ 禁止"改字段 + 改代码"一把梭，中途回滚代码会读不到旧结构
3. ❌ AI 生成的 migration 必须逐行人工过目：`DROP`、`ALTER`、`UPDATE ... SET` 全表操作是重点

## 三、事故三板斧

| 步骤 | 目标 | 动作 |
|---|---|---|
| 1. 止损 | 先不疼 | 回滚到上一绿版本 / 关功能开关 / 降级。先恢复服务，不找原因 |
| 2. 定位 | 找到根因 | 看错误追踪（Sentry）→ 看日志 → `git log --oneline -10` 最近变更 |
| 3. 复盘 | 不再犯 | blameless 5-why（见下），产出 ADR 落 `docs/adr/` |

## 四、复盘模板（复制到 docs/adr/，编号递增）

```
- 事故时间 / 影响范围 / 持续时长：
- 时间线：发现 → 止损 → 恢复 各是什么时刻、谁做了什么
- 根因（连续问 5 个为什么，写到答不动为止）：
  1. 为什么挂了？因为 …
  2. 为什么会那样？因为 …
  3. …
- 为什么现有防线没拦住？（测试/CI/监控/评审 哪层漏了）
- 整改项（每项有 owner 和期限，能写成测试的写成测试）：
```

## 五、监控现状（上线即监控清单的落地情况）

- [ ] `/health` 端点返回依赖真实状态（DB/缓存 ping 过才算 up，不硬编码 200）
- [ ] 错误追踪（Sentry 或同类）已接入，DSN 走 Infisical 注入
- [ ] 可用性监控（UptimeRobot 免费档即可）盯 `/health`
- [ ] 告警能到人（邮件/Telegram/微信任一）
