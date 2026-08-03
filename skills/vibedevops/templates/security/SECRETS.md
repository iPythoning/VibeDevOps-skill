# 密钥管理规范（SECRETS）

> Vibe coding 第一大生产事故：AI 把密钥硬编码进代码 / `.env` 被 commit。
> 本规范三层防线：**进不去**（pre-commit 拦截）→ **不集中**（Infisical 托管）→ **漏了能救**（应急流程）。

## 一、铁律（写进 AGENTS.md 反模式）

- ❌ 密钥出现在代码、commit、对话截图里的任何一处，都按泄露处理
- ❌ 真 `.env` 永不入库；入库的只有 `.env.example`（变量名 + 假值）
- ❌ 不在 agent 对话里粘贴真实生产密钥——让 agent 读环境变量，不读值

## 二、本地开发：Infisical 注入，密钥不落盘

```bash
# 安装（macOS）
brew install infisical/get-cli/infisical
# 其他平台见 https://github.com/Infisical/cli

# 一次性登录 + 初始化（在项目根目录，生成 infisical.json，可入库）
infisical login
infisical init

# 日常：启动命令前套一层，密钥运行时注入，本地不留 .env
infisical run --env=dev -- npm run dev
infisical run --env=dev -- python main.py
```

收益：新人不用拷 `.env`，`infisical run` 直接拿到自己权限内的密钥；密钥轮换后所有人下次启动自动生效。

## 三、CI/CD：机器身份，不落明文

GitHub Actions 里用 Infisical 机器身份（Universal Auth）拉密钥，不往 repo secrets 里堆几十个零散密钥：

```yaml
# 见 ../ci/deploy.yml 的完整示例，核心两步：
# 1) npm install -g @infisical/cli
# 2) INFISICAL_UNIVERSAL_AUTH_CLIENT_ID / CLIENT_SECRET 存 repo secrets（仅此两个）
#    infisical run --env=prod -- ./deploy.sh
```

## 四、提交前拦截：pre-commit hook

```bash
cp templates/security/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

优先级：Infisical `infisical scan` → gitleaks → 内置兜底正则（AWS/OpenAI/GitHub/Slack/私钥模式）。

## 五、泄露应急（真的漏了怎么办）

1. **先轮换，后清理**——密钥一旦进过 git 历史，就当它已公开：立刻去服务商后台吊销/换新
2. 清历史：`git filter-repo --invert-paths --path .env`（或 BFG），强推远端
3. 查使用记录：服务商后台看该密钥最近调用日志，确认是否被滥用
4. 落一份 ADR：怎么漏的、为什么没被拦住、补了哪道防线

## 六、兜底加固（免费，5 分钟）

- GitHub 仓库设置 → Secret scanning + Push protection 打开
- Dependabot alerts 打开（依赖漏洞）
