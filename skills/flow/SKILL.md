---
name: flow
description: 全链路开发工作流编排器。触发词 /flow、走流程、全链路工作流、feature 开发流程、组装工作流、一条龙。把 ponytail + gstack + PRP + TDD + code-review 串成 思考→计划→实现→自检→出活→部署→复盘,带安全关卡(计划/出 PR 需人工确认;部署走 CD 自动化)。底座融合精选,通用于所有项目。
---

# /flow — 全链路开发工作流

把手头零散的命令收口成一条主力链。只写任务真正需要的最少代码,但绝不砍校验/错误处理/安全/可访问性。**ponytail 按需轻量启用**:默认不挂载——实测默认全程压舱(full/ultra)会持续压制输出质量;确实需要抑制过度工程时显式 `/ponytail lite`。

## 阶段表

| # | 阶段 | 目标 | 主命令 | 备选/补充 | 产出 | 关卡 |
|---|---|---|---|---|---|---|
| 0 | 压舱(可选) | 抑制过度工程 | 默认不启用 | 需要时显式 `/ponytail lite` | — | — |
| 1 | 思考 | 把需求/方案逼清楚 | `/office-hours` | `/grill-me`(拷问计划) · `/council`(多方案抉择) | 需求/决策记录 | — |
| 2 | 计划 | 出可执行计划 | 小改 `/plan` · 新特性 `/prp-prd`→`/prp-plan` | `/autoplan`(自动跑评审,需先有 plan) | plan 文件 | ✋ 计划须你确认才动代码 |
| 3 | 实现 | 最小可用代码+测试 | `/tdd`(RED→GREEN→REFACTOR) | `/prp-implement`(plan 驱动+每步验证) | 代码+测试 commit | — |
| 4 | 自检 | 机械门+过度工程+正确性 | `/verify` → `/ponytail-review` → `/code-review` | `/quality-gate`(快速 lint/type/test) | 报告+删除清单 | ✋ 红的必须先修 |
| 5 | 出活 | commit → PR | `/prp-commit` → `/ship` | 手工 git(只 `git add -u`/逐文件) | PR | ✋✋ 出 PR 前 `git diff --stat` 自查 |
| 6 | 部署 | 上线+盯线上 | 合并 main → 推广不可变制品 → canary | 项目专用 deploy.sh(如 PA) | 生产+监控 | 自动;功能门失败自动回滚 |
| 7 | 复盘 | 沉淀+还债 | `/retro` + `/ponytail-debt` | `/benchmark`(性能回归) | 复盘+债账 | — |

> ponytail 命令在本机带不带命名空间前缀均可(`/ponytail-review` 或 `/ponytail:ponytail-review`,hook 两者都认)。

## 两条线(按改动体量选)

- **快速线**(bugfix/小改): `2 /plan` → `3 /tdd` → `4 /verify`+`/ponytail-review` → `5 /prp-commit`+`/ship` → 合并 main 后 `6 CD` 自动执行
- **完整线**(新特性): `1 /office-hours` → `2 /prp-prd`→`/prp-plan`(或 `/autoplan`) → `3 /tdd` 或 `/prp-implement` → `4 /code-review`+`/ponytail-review`+`/verify` → `5 /ship` → 合并 main 后 `6 CD` 自动执行 → `7 /retro`

## 安全关卡(铁律,对齐全局 CLAUDE.md 修A不坏B)

- **计划关**: plan 未经用户确认不动代码(`/plan` 自带此 gate)。
- **出 PR 关**: 禁 `git add -A`;只 `git add -u` 或逐文件;commit 前 `git diff --stat` 确认无意外的 Dockerfile/nginx/compose 变更。
- **部署关(2026-08-09 起不再是人工关卡)**: 合并进 main 即自动部署,门在 PR 阶段(CI 绿才合并 + 禁止直推 main)。CD 构建一次并推广同一份 SHA/digest 制品,串行 canary,功能层 smoke/真实指标失败自动回滚并复验。**保留的硬要求不变**:跨服务一次只改一个、改完验证再下一个;部署验证不只看 health check / 状态字段绿。
  为什么删掉这道关卡:人工关卡在 solo + agent 的节奏下不是「守门」,是「没人知道该点」——2026-08-09 clawops 七个已合并 PR 在关卡后积压一整天,客户一格都没拿到。**合并 ≠ 上线**本身才是事故源。
- 工具重叠时的取舍: 计划别同时用 `/plan`+`/prp-plan`(后者已含前者);review 三件套各管一摊—`/code-review`(正确性+安全) · `/ponytail-review`(过度工程删除项) · `/verify`(build/type/lint/test 机械门)。

## 调用 /flow 时的编排行为

- **无参数**: 探测当前阶段(有无 plan 文件 / 未提交 diff / 开着的 PR),显示上表并高亮"你在这",给出下一步该敲的命令。
- **`/flow <阶段名或编号>`**: 从该阶段开始引导。
- **`/flow 快速` / `/flow 完整`**: 按对应线逐阶段推进。
- 执行原则: **无副作用阶段**(思考/计划/自检/复盘)我可代跑;**出 PR** 仍停下等你确认(那是 diff 自查关);**部署由 CD 自动完成**,不再等人点头。每过一关向用户汇报产出与下一步。
