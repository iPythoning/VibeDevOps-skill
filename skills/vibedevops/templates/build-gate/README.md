# build-gate 模板 —— 弱网 / 资源受限环境的构建门禁

适用场景（中国开发者全中的组合）：CI 免费额度会耗尽且**静默失败**、本机性能跑不动全量验证、
自建构建机（NAS / 软路由 / 家庭服务器）连通不稳、代理工具抢路由、拉境外镜像慢。

核心思想一句话：**"在哪验证"是一个显式的、自动降级的、留证据的路由决策；本机兜底通过不算结案，算欠账。**

## 组成

| 文件 | 作用 |
|---|---|
| `build-gate.sh` | 三级路由门禁：CLOUD（CI）→ BUILDER（专用构建机）→ LOCAL（本机兜底），结果统一写 `<repo>/docs/BUILD-EVIDENCE.md`；启动时自动补验历史欠账 |
| `reverify.sh` | 补验欠账（销账主路径已内嵌进 build-gate 启动时，本脚本供手动跑 / 可选 cron 加速） |
| `build-container-image.sh` | Xserver/Mac 共用的 `linux/amd64` 构建入口：DaoCloud + 阿里云 Alpine 包镜像优先，单路径 150 秒超时后切 Public ECR + Alpine 官方 CDN，并固定同一基础镜像 digest |

## 部署

```bash
cp build-gate.sh reverify.sh ~/bin/   # 或任何固定位置，两个脚本放同一目录
chmod +x ~/bin/build-gate.sh ~/bin/reverify.sh

# 目标容器仓库：把统一构建入口纳入该仓库版本控制
mkdir -p /path/to/repo/scripts
cp build-container-image.sh /path/to/repo/scripts/build-container-image.sh
chmod +x /path/to/repo/scripts/build-container-image.sh

# 配置构建机（ssh alias 或 user@host；没有构建机就留空，则只有 CLOUD/LOCAL 两级）
export BUILDER_SSH=builder              # 写进 shell rc
export BUILDER_IMAGE=my-builder:node22  # 可选；留空则直接在构建机上跑，不用 docker

# 国内网络加速（可选，运行时注入，不用重烤镜像）
export NPM_REGISTRY=https://registry.npmmirror.com
export PIP_INDEX=https://mirrors.aliyun.com/pypi/simple
```

不需要装 cron：销账内嵌在每次构建的启动路径里，构建越勤销得越快、机器睡眠也不影响。
想加速销账再额外挂 `reverify.sh` 的 cron（见其头注释）。

## 日常使用

```bash
build-gate.sh /path/to/repo --cmd "npm ci && npm test && npm run build"
# 门禁不过 = 禁止发布；LOCAL 通过的 commit 在补验销账前同样禁止发布
```

## 配套纪律（写进仓库 AGENTS.md 才生效）

1. **机器角色锁死**：开发机只做内循环（受影响测试 + 类型检查）；构建机做全量验证；生产机只拉已验证制品、绝不构建。每台机器的资源消耗才有上限。
2. **证据即真相**：任何人 / 任何 agent 都能从 `docs/BUILD-EVIDENCE.md` 查到"这个 commit 被谁、在哪、用什么命令验证过、跑了多久"。LOCAL 记录必须带"弱证据"标注。
3. **构建时限是铁律不是愿望**：`GATE_TIMEOUT`（默认 600s）机械强制——超时强杀、证据留痕。超时的正确响应永远是修构建（缓存 / 依赖 / 拆分），不是调大上限；上限一松，构建时间只会单调变长。
4. **镜像源有界 fallback**：Dockerfile 的基础镜像必须显式 registry + 版本 + digest，禁止裸 `FROM node:22`。大陆节点先走 DaoCloud 的 `m.daocloud.io/docker.io/...` 前缀；Alpine 包走其官方 mirror 列表收录的阿里云公共镜像。单路径超时后同时切上游基础镜像与官方包源，两条基础镜像路径必须解析到同一 digest。项目专有 builder 镜像优先预烤到 GHCR，公共镜像站只解决冷启动，不能成为唯一副本。
5. **依赖源运行时注入 + 缓存卷**：`NPM_REGISTRY` / `PIP_INDEX` 环境变量运行时注入（脚本已内置），通用官方镜像（`python:3.12-slim` 等）即插即用，不必为换源重烤镜像；包缓存挂命名卷（脚本已内置 `build-gate-npm` / `build-gate-pip`），实测热缓存能把门禁耗时打到冷缓存的一半以下。
6. **构建机 docker 一律 `--network host`**（脚本已内置）：NAS / 家庭服务器 / 品牌小主机的 docker 常由厂商系统托管（自定义网络栈），默认 docker0 桥不存在是常态不是故障——显式 host 网络让桥的状态与构建彻底无关。也绝不重启这类机器的 docker daemon（上面跑着厂商全家桶）。

## Xserver → Mac → GHCR → 云端（30 分钟硬上限）

`templates/ci/deploy.yml` 固定为以下容灾链，不靠人工改 runner：

1. GitHub hosted 控制 job 查询 self-hosted runner 状态，只选择 `online && !busy` 的机器；Xserver 优先，构建失败才用 Mac。
2. 两台机器都构建 `linux/amd64`，同一 Git SHA 只选择首个成功产物；未压缩传输的临时 artifact 仅保留 1 天。
3. GitHub hosted runner 优先把该产物 push GHCR 并生成 provenance/SBOM；失败才由 Xserver 下载同一产物并 push。
4. 云端只接收 `image@sha256:digest`，经过 canary、功能门和指标门后才推广；旧 LKG 与新 production 都有 Registry tag 保护。
5. workflow 创建时间即开始计时；独立 GitHub hosted watchdog 不依赖 self-hosted jobs，会在 1800 秒通过 Actions API 强制取消仍未完成的 workflow。状态查询瞬时失败会保留 watchdog 并重试；deadline 后取消请求持续重试到成功或 watchdog 35 分钟硬超时。`complete-deployment` 同时校验 deadline，超时不更新 LKG/不解除租约；显式 rollback 与独立 30 分钟租约共同兜底恢复。

目标仓库需要两个专用、持久在线并启用自动更新的 repository runners：

```text
Xserver labels: self-hosted,linux,x64,xserver
Mac labels:     self-hosted,macOS,mac-builder
```

如需自定义 labels，设置 Actions variables（JSON 数组）：

```text
VIBEDEVOPS_XSERVER_RUNNER=["self-hosted","linux","x64","xserver"]
VIBEDEVOPS_MAC_RUNNER=["self-hosted","macOS","mac-builder"]
```

再设置 repository secret `VIBEDEVOPS_RUNNER_READ_TOKEN`：使用 fine-grained token，仅授予目标仓库 `Administration: read`，只供控制 job 读取 runner 的 online/busy 状态。构建和 GHCR push 仍使用每个 job 的短期 `GITHUB_TOKEN`；生产身份只在 hosted deployment job 用 OIDC 获取，不进入 Xserver 或 Mac。

在两台机器注册常驻 runner（registration token 只经 stdin 传递）：

```bash
ssh xserver-lan 'mkdir -p ~/.local/bin'
scp install-github-runner.sh xserver-lan:~/.local/bin/install-github-runner.sh
gh api --method POST repos/OWNER/REPO/actions/runners/registration-token --jq .token \
  | ssh xserver-lan '~/.local/bin/install-github-runner.sh --repo OWNER/REPO --role xserver --token-stdin'

gh api --method POST repos/OWNER/REPO/actions/runners/registration-token --jq .token \
  | ./install-github-runner.sh --repo OWNER/REPO --role mac --token-stdin
```

Xserver 的 SSH 用户必须是 docker 组中的专用非 root 用户；安装器会拒绝 root。不要把 token 拼进 SSH 命令或日志；stdin 读入后仅通过 runner 官方 `ACTIONS_RUNNER_INPUT_TOKEN` 临时环境传入，绝不进入进程 argv 或服务文件。安装器固定校验官方 runner v2.336.0 的 SHA256，Linux 使用 systemd user 常驻并要求 lingering，systemd 默认 control-group stop 会清理完整 listener 进程树；Mac 使用 launchd 常驻且在接单前自动启动 Docker Desktop。两端 listener 都通过 `env -i` 最小环境启动，避免把登录会话中的 API key、代理凭据或其他本机变量带进 runner。

30 分钟不是说明文字：runner route 1 分钟、容量门禁 2 分钟（并行）、Xserver/Mac 每次构建 6 分钟、每个 push 尝试 3 分钟、两个选择 job 各 1 分钟、prepare 1 分钟、canary/promote 各 3 分钟；即使两级 build 和两级 push 都走 fallback，成功路径的阶段预算仍不超过 28 分钟，并由部署控制器再次核验绝对 deadline。image tar 超过 2 GiB 会直接失败。两台机器必须是该生产链的专用 runner，不能同时承接不可信 PR 或其他长任务；Dockerfile 需要热缓存且输出 artifact 应保持精简，否则 job 会按预算失败，而不是悄悄放宽上限。

两台构建机不得各自维护 Dockerfile，也不得依赖某台机器私有 cache 才能成功。Dockerfile、`.dockerignore`、镜像源顺序、digest 和构建入口必须进入业务仓库；本机只保存可删除 cache。示例：

```bash
./skills/vibedevops/templates/build-gate/build-container-image.sh --tag app:"$(git rev-parse HEAD)"
```
7. **代理规避 + 双路径 ssh**：构建机 ssh 配两条路——overlay 网络（Tailscale 类，CGNAT `100.64/10` 段必须走 utun 虚拟网卡，**绝不能绑物理网卡**）为主，局域网 IP + `BindInterface` 绑物理网卡为兜底；两条路径的 host key 交叉比对一致后再收录。脚本里禁止裸域名和 `root@IP`，路由策略统一收敛在 `~/.ssh/config`；不依赖修改代理工具的配置。

## 下游 fork 约定（消灭双副本漂移）

把模板拷去做本机特化（改构建机坐标、接私有证据目录等）没问题，但**记下你 fork 时的上游 commit**，
并定期检查上游是否更新（示例：`git -C <本仓> log <你的基线>..HEAD -- skills/vibedevops/templates/build-gate`）。
推荐把这条检查挂在你自己 build-gate 的启动路径里（机会式，无 cron 依赖）——通用改进流回下游，
本机特化不上传。方向约定：**通用改进先改这里（上游），再回灌你的特化版**，反着来迟早分叉成两套互不认识的东西。

## 设计要点（为什么长这样）

- **额度是显式变量**：CI 额度查不到时按不足处理，保守降级——"以为 CI 在跑其实没跑"是最危险的静默失败。
- **降级不降标准**：三条路跑的是同一条门禁命令、写同一份证据，区别只在证据强度标注。
- **欠账必须可还清**：`reverify.sh` 幂等，仓库消失 / sha 被 rebase 掉的记录自动作废；HEAD 前进的仓库验当前 HEAD 即覆盖旧欠账。
- **bash 3.2 兼容**（macOS 自带）：不用数组、`set -u` 下无空数组展开问题；**`$VAR` 后紧跟全角字符（；，：（）等）会被吞进变量名导致 unbound variable，一律写 `${VAR}`**——本模板就此踩过坑。
