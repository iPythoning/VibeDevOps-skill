# 付费客户的 $99 挂了 9 天，而我的 5 个监控全是绿的

> 事故日期：2026-04-24。这是我用 AI 全速 vibe coding 以来最贵的一课：**状态字段绿 ≠ 功能可用**。

## 事故经过

我的 SaaS 接 Stripe 收款。某次改动后，我在 Stripe 后台配了 5 个 webhook endpoint，全部显示绿标——Stripe 的投递记录里每一条都是"成功"。

九天。整整九天，所有付费流程实际上是断的。一个 $99/月的付费客户，钱付了，服务没开通，没人知道。

直到客户找上门，我才发现真相：那 5 个 endpoint 的请求**根本没到我的应用**——它们被前面的 portal 站点拦截了，有的直接被 301 重定向走。而 Stripe 的投递成功判定把 3xx 也算成功。于是监控面板上每一盏灯都是绿的，业务每一笔钱都是断的。

## 根因不是 Stripe，是我的验证方式

复盘时我意识到，真正的根因是我把"观测到的状态"当成了"功能验证"：

- 我看到 Stripe 后台绿标 → 以为 webhook 通了
- 我看到 health check 返回 200 → 以为服务正常
- 我看到状态字段 `connected` → 以为集成可用

全是错的。这些信号告诉我的是"**某个中间层认为一切正常**"，而不是"**我的应用本体正确处理了真实请求**"。

## 固化下来的铁律

事故之后，这条规则进了我所有 65 个仓库的 `AGENTS.md`：

> **「绿标 / 200 / 状态字段」都不是功能验证。** 加了 webhook、改了回调、动了路由之后，必须 curl 实测真实 URL，确认返回值来自**目标应用本体的签名校验层**，而不是中间代理或 redirect。

具体做法，以 Stripe webhook 为例：

1. 不看 Stripe 后台的投递状态，直接 `curl -X POST` 打真实 endpoint，带一个刻意错误的签名
2. 正确的响应应该来自**应用的验签层**（比如返回 400 signature invalid）——这证明请求真的到达了应用
3. 如果返回的是 301、是 nginx 的默认页、是前端 SPA 的 HTML——请求根本没到应用，绿灯全是假的

同一原则推广到所有部署后验证：

- health check 返回 200 不算数，`/health` 必须真实 ping 一遍 db/redis 再回答
- 部署完核心功能要跑穿透清单：发真实请求、看真实回复、grep 真实日志

## 这套规则现在长在哪

它和另外十几条同类事故固化的规则一起，住在我开源的 VibeDevOps skill 里：

- 仓库：https://github.com/iPythoning/VibeDevOps-skill
- 一条命令给你的项目做体检（0–100 分 + 缺口清单，"监控"维度专门查假 health check）：

```bash
curl -fsSL https://raw.githubusercontent.com/iPythoning/VibeDevOps-skill/main/skills/vibedevops/scripts/health-check.sh | bash -s -- /path/to/your/repo
```

下次看到满屏绿灯的时候，问自己一句：这个绿，是应用本体说的，还是中间层替它说的？
