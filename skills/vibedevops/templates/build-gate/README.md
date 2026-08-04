# build-gate 模板 —— 弱网 / 资源受限环境的构建门禁

适用场景（中国开发者全中的组合）：CI 免费额度会耗尽且**静默失败**、本机性能跑不动全量验证、
自建构建机（NAS / 软路由 / 家庭服务器）连通不稳、代理工具抢路由、拉境外镜像慢。

核心思想一句话：**"在哪验证"是一个显式的、自动降级的、留证据的路由决策；本机兜底通过不算结案，算欠账。**

## 组成

| 文件 | 作用 |
|---|---|
| `build-gate.sh` | 三级路由门禁：CLOUD（CI）→ BUILDER（专用构建机）→ LOCAL（本机兜底），结果统一写 `<repo>/docs/BUILD-EVIDENCE.md`；启动时自动补验历史欠账 |
| `reverify.sh` | 补验欠账（销账主路径已内嵌进 build-gate 启动时，本脚本供手动跑 / 可选 cron 加速） |

## 部署

```bash
cp build-gate.sh reverify.sh ~/bin/   # 或任何固定位置，两个脚本放同一目录
chmod +x ~/bin/build-gate.sh ~/bin/reverify.sh

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
4. **镜像走私有 registry**：构建机不依赖公共镜像加速——在网络通畅的机器上 build/push builder 镜像到私有 registry（如 GHCR），构建机只 pull。公共 Docker Hub 在部分网络下**完全不可达**，`FROM node:22` 这类裸 Hub 引用是定时炸弹。
5. **依赖源运行时注入 + 缓存卷**：`NPM_REGISTRY` / `PIP_INDEX` 环境变量运行时注入（脚本已内置），通用官方镜像（`python:3.12-slim` 等）即插即用，不必为换源重烤镜像；包缓存挂命名卷（脚本已内置 `build-gate-npm` / `build-gate-pip`），实测热缓存能把门禁耗时打到冷缓存的一半以下。
6. **构建机 docker 一律 `--network host`**（脚本已内置）：NAS / 家庭服务器 / 品牌小主机的 docker 常由厂商系统托管（自定义网络栈），默认 docker0 桥不存在是常态不是故障——显式 host 网络让桥的状态与构建彻底无关。也绝不重启这类机器的 docker daemon（上面跑着厂商全家桶）。
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
