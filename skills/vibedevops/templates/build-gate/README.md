# build-gate 模板 —— 弱网 / 资源受限环境的构建门禁

适用场景（中国开发者全中的组合）：CI 免费额度会耗尽且**静默失败**、本机性能跑不动全量验证、
自建构建机（NAS / 软路由 / 家庭服务器）连通不稳、代理工具抢路由、拉境外镜像慢。

核心思想一句话：**"在哪验证"是一个显式的、自动降级的、留证据的路由决策；本机兜底通过不算结案，算欠账。**

## 组成

| 文件 | 作用 |
|---|---|
| `build-gate.sh` | 三级路由门禁：CLOUD（CI）→ BUILDER（专用构建机）→ LOCAL（本机兜底），结果统一写 `<repo>/docs/BUILD-EVIDENCE.md` |
| `reverify.sh` | 补验欠账：cron 定期跑，构建机恢复后把 LOCAL 通过的记录用 `--force-builder` 复验销账 |

## 部署

```bash
cp build-gate.sh reverify.sh ~/bin/   # 或任何固定位置，两个脚本放同一目录
chmod +x ~/bin/build-gate.sh ~/bin/reverify.sh

# 配置构建机（ssh alias 或 user@host；没有构建机就留空，则只有 CLOUD/LOCAL 两级）
export BUILDER_SSH=builder            # 写进 shell rc
export BUILDER_IMAGE=my-builder:node22  # 可选；留空则直接在构建机上跑，不用 docker

# 补验 cron（crontab -e）
*/15 * * * * ~/bin/reverify.sh >> ~/.build-gate-reverify.log 2>&1
```

## 日常使用

```bash
build-gate.sh /path/to/repo --cmd "npm ci && npm test && npm run build"
# 门禁不过 = 禁止发布；LOCAL 通过的 commit 在补验销账前同样禁止发布
```

## 配套纪律（写进仓库 AGENTS.md 才生效）

1. **机器角色锁死**：开发机只做内循环（受影响测试 + 类型检查）；构建机做全量验证；生产机只拉已验证制品、绝不构建。每台机器的资源消耗才有上限。
2. **证据即真相**：任何人 / 任何 agent 都能从 `docs/BUILD-EVIDENCE.md` 查到"这个 commit 被谁、在哪、用什么命令验证过"。LOCAL 记录必须带"弱证据"标注。
3. **镜像走私有 registry**：构建机不依赖公共镜像加速——在网络通畅的机器上 build/push builder 镜像到私有 registry（如 GHCR），构建机只 pull。预烤清单文档化，版本升级一次烤齐。
4. **依赖源预置 + 缓存卷**：npm/pip/go 镜像源烤进 builder 镜像，包缓存挂卷，避免每次构建重新下载。
5. **代理规避**：内网/隧道目标一律用 IP + ssh alias（必要时 `BindInterface` 绑物理网卡），脚本里禁止裸域名；不依赖修改代理工具的配置。

## 设计要点（为什么长这样）

- **额度是显式变量**：CI 额度查不到时按不足处理，保守降级——"以为 CI 在跑其实没跑"是最危险的静默失败。
- **降级不降标准**：三条路跑的是同一条门禁命令、写同一份证据，区别只在证据强度标注。
- **欠账必须可还清**：`reverify.sh` 幂等，仓库消失 / sha 被 rebase 掉的记录自动作废；HEAD 前进的仓库验当前 HEAD 即覆盖旧欠账。
- **bash 3.2 兼容**（macOS 自带）：不用数组、`set -u` 下无空数组展开问题；**`$VAR` 后紧跟全角字符（；，：（）等）会被吞进变量名导致 unbound variable，一律写 `${VAR}`**——本模板就此踩过坑。
