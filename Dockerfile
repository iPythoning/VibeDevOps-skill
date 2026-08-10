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

RUN printf '%s\n' \
        "$APK_REPOSITORY/v3.22/main" \
        "$APK_REPOSITORY/v3.22/community" \
        > /etc/apk/repositories \
    && apk add --no-cache \
        bash=5.2.37-r0 \
        busybox-extras=1.37.0-r20 \
        brotli-libs=1.1.0-r2 \
        c-ares=1.34.8-r0 \
        ca-certificates=20260611-r0 \
        curl=8.14.1-r3 \
        git=2.49.1-r0 \
        git-init-template=2.49.1-r0 \
        gmp=6.3.0-r3 \
        jq=1.8.1-r0 \
        libcurl=8.14.1-r3 \
        libexpat=2.8.2-r0 \
        libffi=3.4.8-r0 \
        libgcc=14.2.0-r6 \
        libidn2=2.3.7-r0 \
        libncursesw=6.5_p20250503-r0 \
        libpsl=0.21.5-r3 \
        libucontext=1.3.2-r0 \
        libunistring=1.3-r0 \
        ncurses-terminfo-base=6.5_p20250503-r0 \
        nghttp2-libs=1.69.0-r0 \
        oniguruma=6.9.10-r0 \
        pcre2=10.46-r0 \
        readline=8.2.13-r1 \
        ruby=3.4.4-r0 \
        ruby-libs=3.4.4-r0 \
        ruby-yaml=0.4.0-r1 \
        yaml=0.2.5-r2 \
        zstd-libs=1.5.7-r0 \
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
