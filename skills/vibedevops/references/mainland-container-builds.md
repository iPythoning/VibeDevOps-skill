# 中国大陆容器构建：镜像源与可复现性

## 官方依据

- [DaoCloud 镜像加速站](https://docs.daocloud.io/community/mirror/) 推荐给原镜像增加 `m.daocloud.io/` 前缀，并收录 `docker.io/library/alpine`。
- [DaoCloud public-image-mirror](https://github.com/DaoCloud/public-image-mirror) 说明镜像 hash 与源保持一致、推荐优先使用 `@sha256`，并公开服务状态与限流信息。
- [Docker registry mirror 文档](https://docs.docker.com/docker-hub/image-library/mirror/) 说明 daemon 可通过 `registry-mirrors` 使用 pull-through cache。
- [阿里云 ACR 镜像加速文档](https://help.aliyun.com/zh/acr/user-guide/accelerate-the-pulls-of-docker-official-images) 使用账号专属 `*.mirror.aliyuncs.com` 地址，因此不能作为可直接复制到公共 GitHub 模板的默认值。
- [Alpine 官方镜像列表](https://mirrors.alpinelinux.org/) 收录 Alibaba Cloud 的公共 `https://mirrors.aliyun.com/alpine/`，可作为 Alpine 包仓库的大陆首选；包版本与签名校验保持不变。

## VibeDevOps 默认策略

```text
大陆 Xserver / Mac:
  m.daocloud.io/docker.io/<image>@sha256:<digest>
  + mirrors.aliyun.com/alpine
    ↓ 150 秒失败
  public.ecr.aws/docker/library/<image>@sha256:<same-digest>
  + dl-cdn.alpinelinux.org/alpine

GitHub hosted:
  public.ecr.aws/docker/library/<image>@sha256:<same-digest>
```

daemon mirror 可以作为额外加速，但仓库必须在没有任何本机配置和 cache 的干净环境中成功构建。任何替代镜像源上线前，都要分别解析 manifest/index 并确认 digest 相同；只比较 tag 不足以证明内容一致。

统一入口：

```bash
./skills/vibedevops/templates/build-gate/build-container-image.sh --tag app:"$(git rev-parse HEAD)"
```
