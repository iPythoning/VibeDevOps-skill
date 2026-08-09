# 密钥管理规范（SECRETS）

> Vibe coding 第一大生产事故：AI 把密钥硬编码进代码 / `.env` 被 commit。
> 防线按**依赖成本从零到高**排列：能用服务端白嫖的不装工具，能用单二进制的不接 SaaS。
> 一个宣称「不靠自觉」的体系，不能把第一道防线建立在"用户记得装某个工具"上。

## 一、铁律（写进 AGENTS.md 反模式）

- ❌ 密钥出现在代码、commit、对话截图里的任何一处，都按泄露处理
- ❌ 真 `.env` 永不入库；入库的只有 `.env.example`（变量名 + 假值）
- ❌ 不在 agent 对话里粘贴真实生产密钥——让 agent 读环境变量，不读值

## 二、第 0 层（零安装，先开这个）：GitHub 服务端拦截

仓库/组织设置 → **Secret scanning + Push protection** 打开。免费、服务端强制、
装不上/被忘/换机器都不影响——这是唯一一道不依赖本地环境的防线，所以排第一。
Dependabot alerts 顺手打开（依赖漏洞）。

局限：只认 GitHub 收录的密钥模式，push 时才拦（本地 commit 已产生）。所以要有第 1 层。

## 三、第 1 层（单二进制，离线可用）：gitleaks pre-commit

```bash
brew install gitleaks          # 无账号、无网络依赖、国内直接装
cp templates/security/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

hook 优先级：gitleaks → 兜底正则（AWS/OpenAI/GitHub/Slack/私钥模式）→ 都没有则放行并提示。
commit 时就拦，比 push 拦截早一步，密钥根本进不了历史。

## 四、第 2 层（solo/小团队默认）：sops + age，密钥加密进 git

「不集中」不一定要上 SaaS——solo 开发者的部署密钥用 sops+age 加密后**直接进 git**：
零服务依赖、离线可用、弱网友好、密钥和代码同生命周期（回滚代码 = 回滚密钥）。

```bash
brew install sops age

# 一次性：生成密钥对（私钥保管好，这是唯一不进 git 的东西）
age-keygen -o ~/.config/sops/age/keys.txt     # 输出里的 public key 填进 .sops.yaml

# 项目根放 .sops.yaml（模板见同目录 sops.yaml），然后：
sops -e .env > .env.enc && rm .env            # 加密入库，明文不留
git add .sops.yaml .env.enc

# 部署/本地使用时解密（CI 里私钥存为唯一一个 repo secret：SOPS_AGE_KEY）
sops -d .env.enc > .env
# 或不落盘直接注入：
sops exec-env .env.enc 'npm run dev'
```

repo secrets 从「几十个零散密钥」收敛为**一个** age 私钥；轮换某个密钥 = 改 `.env.enc` 重新
commit，有 diff、有历史、可回滚。

## 五、CI/CD：最少明文原则

- **默认**：`.env.enc` 进 git + CI 里 `SOPS_AGE_KEY` 一个 secret 解密（见上）
- 部署密钥放 GitHub Environments 或 repo secrets，以最小权限提供给 `push main` 的 CD；正常发布不配置 Required reviewers。发布授权已在 PR 合并完成，手动审批只会制造“已合并但未上线”的隐性队列。
- 团队化之后再考虑集中托管（见第八节），不要一开始就上

## 六、提交前拦截：pre-commit hook

```bash
cp templates/security/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

优先级：gitleaks → Infisical `infisical scan`（如已装）→ 内置兜底正则。

## 七、泄露应急（真的漏了怎么办）

1. **先轮换，后清理**——密钥一旦进过 git 历史，就当它已公开：立刻去服务商后台吊销/换新
2. 清历史：`git filter-repo --invert-paths --path .env`（或 BFG），强推远端
3. 查使用记录：服务商后台看该密钥最近调用日志，确认是否被滥用
4. 落一份 ADR：怎么漏的、为什么没被拦住、补了哪道防线

## 八、什么时候才升级到 Infisical（团队化附录）

[Infisical](https://github.com/Infisical/cli) 的本体是**集中托管 + 运行时注入**
（`infisical run --env=dev -- npm run dev`），它需要一个后端（云 SaaS 或自托管服务器）。
满足以下任一条再上，否则 YAGNI：

- 有多个团队成员需要**按权限**分发密钥（张三只能拿 dev，李四能拿 prod）
- 多环境密钥要**集中轮换**、轮换后所有人自动生效
- 给客户交付时要按租户隔离密钥作用域

CI 机器身份用法（Universal Auth，repo secrets 只存 CLIENT_ID/SECRET 两个凭据）见
`../ci/deploy.yml` 注释。solo 阶段 sops+age 覆盖同样需求且零服务依赖——**同时跑两套
密钥体系比没有体系更糟，二选一**。
