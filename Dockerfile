ARG BASE_IMAGE=m.daocloud.io/docker.io/library/alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce
FROM ${BASE_IMAGE}

ARG VERSION=dev
ARG VCS_REF=unknown
ARG APK_REPOSITORY=https://mirrors.aliyun.com/alpine

LABEL org.opencontainers.image.title="VibeDevOps" \
      org.opencontainers.image.description="Portable VibeDevOps skill and delivery templates" \
      org.opencontainers.image.source="https://github.com/iPythoning/VibeDevOps-skill" \
      org.opencontainers.image.version="$VERSION" \
      org.opencontainers.image.revision="$VCS_REF" \
      org.opencontainers.image.licenses="MIT"

# 可复现性由 base image 的 digest pin 承担；apk **不钉包版本**——alpine 稳定
# 分支的仓库是滚动的（安全更新 -rN 递增、旧版即刻下架），钉具体版本等于给
# 门禁装定时假红（2026-08-20 起 main CI 因 pin 过期连红，实证）。一个每隔
# 几周必然假红的可复现性门禁，违反 ADR 0009「门禁必须自证有效」。
# 只列顶层工具包：传递依赖（*-libs 等）由解析器自带，显式钉它们是上次碎的根源。
RUN printf '%s\n' \
        "$APK_REPOSITORY/v3.22/main" \
        "$APK_REPOSITORY/v3.22/community" \
        > /etc/apk/repositories \
    && apk add --no-cache \
        bash \
        busybox-extras \
        ca-certificates \
        curl \
        git \
        jq \
        ruby \
        ruby-yaml \
    && addgroup -S -g 10001 vibedevops \
    && adduser -S -D -u 10001 -G vibedevops -h /home/vibedevops vibedevops

WORKDIR /opt/vibedevops
COPY --chown=10001:10001 . .

RUN install -d -o 10001 -g 10001 /srv \
    && printf '%s\n' ok > /srv/healthz \
    && printf '%s\n' "VibeDevOps $VERSION ($VCS_REF)" > /srv/index.html

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=5s --timeout=2s --start-period=2s --retries=6 \
    CMD wget -qO- http://127.0.0.1:8080/healthz | grep -qx ok || exit 1

CMD ["httpd", "-f", "-p", "8080", "-h", "/srv"]
