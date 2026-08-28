<!--
  求职作品集。下面的联系方式是占位符——给雇主前请填上 姓名 / 邮箱 / LinkedIn。
  English version: PORTFOLIO.md
-->

# 让 CI/CD 对 coding agent 安全 —— 一份作品集

*Platform / DevEx / agent-infrastructure.* GitHub: **[@iPythoning](https://github.com/iPythoning)** · 联系方式: `<你的邮箱>` · `<你的 LinkedIn>`

当一个团队 40–70% 的 PR 由 coding agent 写出，有一个问题至今没有好答案：**agent 到底可以自己合并什么？以及，你凭什么相信批准它的那些检查是真的？** 下面全部是我的回答，而且它只有一个形状——*门禁必须能证明自己会红，决策必须被机械强制、而不是靠人记得。* 每一条主张都链到本仓里正在跑的代码和绿色 CI。

我想展示的信号，不是"我会写 CI 流水线"，而是两件面试问不出来、LLM 也生成不出来的东西：**在证据层面推理，以及知道自己的判据什么时候会骗我。**

---

## 一、门禁必须先证明自己会失败，才有资格放行

> 一道从未失败过的门禁，和一道不存在的门禁，在证据上无法区分。 —— [ADR 0009](adr/0009-gates-must-prove-themselves.md)

一道"红了好几周、已知问题"的密钥扫描，可能从没扫过一次——它会因为**自己**的原因失败，而且长得跟"扫到了泄露"一模一样。所以现在扫描器的第一步，是在临时目录里现造一个**随机生成**的假凭据去扫**它**；扫不出来就让这一步红，并明说本次"扫描通过"不可信。随机是刻意的：写死的样本会进仓库、被真实扫描扫到。

- **代码**：[`.github/workflows/ci.yml`](../.github/workflows/ci.yml)（`secrets` job）的金丝雀步骤，以及出厂模板 [`pr-check.yml`](../skills/vibedevops/templates/ci/pr-check.yml)。
- **实证**：`main` 上 `Gate self-proof — gitleaks canary` 步骤**绿**——它下载同版本 gitleaks、植入随机 `ghp_` token、确认扫描器能抓到。（这道金丝雀我最初用的 AWS 键形态，本地实测**静默漏检**，发布前换成了确定检出的形态——一道你没跑过的金丝雀，本身就是假门禁。）

## 二、合并权限按可逆性分档，不按绿勾

> 自动化的是「确认功能是否成立」，不是「替人承担不可逆后果」。 —— [ADR 0011](adr/0011-verification-autonomy.md)

自动合并工具按"检查绿了"放行，依赖机器人按"patch 还是 minor"放行。两者都没问那个真正重要的问题：**这个改动错了，能不能自动退回来？** 改动按 可逆性 × 证据充分度 分三档；凡是碰 migrations、`.env`、secrets 的一律 T3——永不交给 agent，无豁免。

- **代码**：[`automerge-tiers.sh`](../skills/vibedevops/templates/ci/automerge-tiers.sh)。它对一个 `main` 没有任何分支保护的仓**拒绝判档**——"在没有门的房子上装智能门锁"。

## 三、一个知道自己会被骗的判官

这是我最希望评审读的一段。上面那个前置检查要回答"这个分支有没有保护"——而**把这个判断本身写对**，我试了三次，每一次都记在代码它该在的地方：

```bash
# 判据不能写成「输出为空即无保护」——gh api 在 404 时把错误 JSON 打到 *stdout*
# （实测 149 字节的 {"message":"Branch not protected",...}），那样判据永远为假、
# 这道门静默失效。要判实质字段：拿得到 required_status_checks 才算有保护。
# 取 .url 而不是某个布尔字段：jq 的 `//` 对 *false 与 null 一视同仁* 都走 alternative——
# 判据写成 `.required_status_checks.strict // empty` 时，strict=false 的正常保护
# 会被判成「无保护」（本人实测踩中，同型第三次）。
PROT=$(gh api "repos/$REPO/branches/main/protection" --jq '.url // empty' ...)
```

两种让**判官自己出错**的方式——扫描器把错误写进你当作结果读的那条通道，以及一个分不清 `false` 与"不存在"的 JSON 操作符——两个都是因为我以前被烧过、现在把判据写成能扛住它，才被抓住。"我的判据会骗我"这个反射，是这里最难伪造的东西，而且它远不止用在这一处。

## 把这一切串起来的一步：规则不是机制

我把"门禁必须自证"写成了正式决策——然后几周没实现它。我在自己的 CI 里写死了 hosted runner，而我亲手写的文档正告诉别人别这么做；我在那份反对 `--if-present` 的模板里，留着 `--if-present` 的静默跳过。我是靠对自己的仓跑了一轮 **8-agent 证伪审计**、拿到实证，才发现的。

于是我把强制往上提了一层（[ADR 0012](adr/0012-adr-decisions-must-be-mechanically-reconciled.md)、[`check-adr-compliance.sh`](../skills/vibedevops/scripts/check-adr-compliance.sh)）：一个在 CI 里跑遍所有已声明不变量的对账器，**只要有任何一条决策既没有可执行校验、也没有显式豁免，就让构建红**——你没法"加了规则忘了强制"，因为忘记本身现在就是一次红色构建。对账器由变异测试守卫，让判官自己不会悄悄烂掉。叙事版本是那篇文章 [*Green Lies*](../articles/04-green-lies-fake-gates.en.md)。

---

## 这份材料证明了什么

| 信号 | 在哪看 |
|---|---|
| 门禁自证（反假绿） | [ci.yml](../.github/workflows/ci.yml) 的金丝雀 · [ADR 0009](adr/0009-gates-must-prove-themselves.md) |
| 面向 agent 的合并策略（按可逆性分档） | [automerge-tiers.sh](../skills/vibedevops/templates/ci/automerge-tiers.sh) · [ADR 0011](adr/0011-verification-autonomy.md) |
| 在证据层调试自己的判据 | 上面那段判官陷阱注释 |
| 决策靠机器强制、不靠记忆 | [ADR 0012](adr/0012-adr-decisions-must-be-mechanically-reconciled.md) + [checks/](adr/checks/) |
| 愿意对自己的成果做证伪审计 | *Green Lies* 复盘 |

**匹配岗位**：platform / 开发者体验 / agent-infrastructure 团队——为 AI agent 操作的工具做 CI/CD、合并自动化、证据化验证、policy-as-code。

*这只是一套自建 DevOps 工具链的一个切片，那套东西在跑约 22 个生产仓。上面任何一个决策我都乐意细讲，包括那些让我搭进去一周的。*
