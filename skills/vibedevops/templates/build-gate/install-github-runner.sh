#!/bin/bash

set -e
umask 077

RUNNER_VERSION="2.336.0"
LINUX_X64_SHA256="04cf0be1aff4c3ec3554466c39124ca250e3effd8873bb7e8d68535aa9505d5d"
MAC_ARM64_SHA256="8e8839c49b7060b6b2154f4931f815df330c27f167d53ef2239ee3dfce28b079"
REPO=""
ROLE=""
RUNNER_NAME=""
TOKEN_STDIN=0

fail() {
    echo "❌ $*" >&2
    exit 1
}

xml_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g'
}

usage() {
    cat <<'EOF'
Usage: install-github-runner.sh --repo OWNER/REPO --role xserver|mac --token-stdin [--name NAME]

Registration token 必须从 stdin 传入，只通过 runner 官方临时环境输入，不写入 argv、服务文件或日志。
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo) REPO=$2; shift 2 ;;
        --role) ROLE=$2; shift 2 ;;
        --name) RUNNER_NAME=$2; shift 2 ;;
        --token-stdin) TOKEN_STDIN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "未知参数: $1" ;;
    esac
done

case "$REPO" in
    */*) ;;
    *) fail "repo 必须是 OWNER/REPO" ;;
esac
printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || fail "repo 含非法字符"
case "$ROLE" in
    xserver|mac) ;;
    *) fail "role 必须是 xserver 或 mac" ;;
esac
[ "$(id -u)" -ne 0 ] || fail "拒绝以 root 运行 GitHub runner；请使用具备 docker 组权限的专用用户"

OS="${VIBEDEVOPS_RUNNER_OS:-$(uname -s)}"
ARCH="${VIBEDEVOPS_RUNNER_ARCH:-$(uname -m)}"
case "$ROLE:$OS:$ARCH" in
    xserver:Linux:x86_64)
        ASSET="actions-runner-linux-x64-$RUNNER_VERSION.tar.gz"
        EXPECTED_SHA256="$LINUX_X64_SHA256"
        LABELS="xserver"
        ;;
    mac:Darwin:arm64)
        ASSET="actions-runner-osx-arm64-$RUNNER_VERSION.tar.gz"
        EXPECTED_SHA256="$MAC_ARM64_SHA256"
        LABELS="mac-builder"
        ;;
    *) fail "$ROLE 不支持当前平台 $OS/$ARCH" ;;
esac

command -v curl >/dev/null 2>&1 || fail "需要 curl"
command -v jq >/dev/null 2>&1 || fail "需要 jq"
[ "$ROLE" != "xserver" ] || docker info >/dev/null 2>&1 || fail "Xserver Docker daemon 未运行"
if [ "$ROLE" = "mac" ]; then
    [ -d /Applications/Docker.app ] || fail "Mac fallback 需要 Docker Desktop"
fi

SLUG="$(printf '%s-%s' "$REPO" "$ROLE" | tr '[:upper:]/_' '[:lower:]---')"
INSTALL_DIR="$HOME/.local/share/vibedevops-runners/$SLUG"
RUNNER_NAME="${RUNNER_NAME:-$(hostname -s)-$ROLE}"
mkdir -p "$INSTALL_DIR" "$HOME/.local/bin" "$HOME/.local/state/vibedevops"
chmod 700 "$INSTALL_DIR" "$HOME/.local/bin" "$HOME/.local/state/vibedevops"

if [ ! -x "$INSTALL_DIR/run.sh" ]; then
    ARCHIVE="$(mktemp)"
    trap 'rm -f "$ARCHIVE"' EXIT HUP INT TERM
    curl --fail --silent --show-error --location \
        --retry 4 --retry-all-errors --connect-timeout 10 \
        "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/$ASSET" -o "$ARCHIVE"
    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL_SHA256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
    else
        ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
    fi
    [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail "runner archive SHA256 不匹配"
    tar -xzf "$ARCHIVE" -C "$INSTALL_DIR"
    rm -f "$ARCHIVE"
    trap - EXIT HUP INT TERM
fi

if [ -f "$INSTALL_DIR/.runner" ]; then
    CONFIGURED_URL="$(jq -er '.gitHubUrl | sub("/+$"; "")' "$INSTALL_DIR/.runner" 2>/dev/null || true)"
    [ "$CONFIGURED_URL" = "https://github.com/$REPO" ] || fail "安装目录已绑定其他仓库"
else
    [ "$TOKEN_STDIN" = "1" ] || fail "首次注册必须传 --token-stdin"
    IFS= read -r REGISTRATION_TOKEN
    [ -n "$REGISTRATION_TOKEN" ] || fail "未收到 registration token"
    (
        cd "$INSTALL_DIR"
        ACTIONS_RUNNER_INPUT_TOKEN="$REGISTRATION_TOKEN" ./config.sh --unattended --replace \
            --url "https://github.com/$REPO" \
            --name "$RUNNER_NAME" \
            --labels "$LABELS" \
            --work _work
    )
    REGISTRATION_TOKEN=""
fi

WRAPPER="$HOME/.local/bin/vibedevops-runner-$SLUG"
[ ! -L "$WRAPPER" ] || fail "拒绝替换软链: $WRAPPER"
WRAPPER_NEW="$WRAPPER.new.$$"
if [ "$ROLE" = "mac" ]; then
    cat > "$WRAPPER_NEW" <<EOF
#!/bin/bash
set -e
open -gja Docker
attempt=0
until /opt/homebrew/bin/docker info >/dev/null 2>&1; do
    attempt=\$((attempt + 1))
    [ "\$attempt" -le 60 ] || { echo "Docker Desktop 未在 120 秒内就绪" >&2; exit 1; }
    sleep 2
done
exec env -i \
    HOME="$HOME" USER="$USER" LOGNAME="$USER" TMPDIR="${TMPDIR:-/tmp}" \
    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$INSTALL_DIR/run.sh"
EOF
else
    cat > "$WRAPPER_NEW" <<EOF
#!/bin/bash
exec env -i \
    HOME="$HOME" USER="$USER" LOGNAME="$USER" TMPDIR="${TMPDIR:-/tmp}" \
    PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$INSTALL_DIR/run.sh"
EOF
fi
chmod 700 "$WRAPPER_NEW"
mv "$WRAPPER_NEW" "$WRAPPER"

if [ "$OS" = "Darwin" ]; then
    LABEL="dev.vibedevops.runner.$SLUG"
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    [ ! -L "$PLIST" ] || fail "拒绝替换软链: $PLIST"
    PLIST_WRAPPER="$(xml_escape "$WRAPPER")"
    PLIST_STDOUT="$(xml_escape "$HOME/.local/state/vibedevops/$SLUG.log")"
    PLIST_STDERR="$(xml_escape "$HOME/.local/state/vibedevops/$SLUG.err.log")"
    cat > "$PLIST.new.$$" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$PLIST_WRAPPER</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>$PLIST_STDOUT</string>
  <key>StandardErrorPath</key><string>$PLIST_STDERR</string>
</dict></plist>
EOF
    plutil -lint "$PLIST.new.$$" >/dev/null
    mv "$PLIST.new.$$" "$PLIST"
    chmod 600 "$PLIST"
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    launchctl enable "gui/$(id -u)/$LABEL"
else
    command -v systemctl >/dev/null 2>&1 || fail "Linux 常驻需要 systemd user"
    if command -v loginctl >/dev/null 2>&1; then
        LINGER="$(loginctl show-user "$USER" -p Linger --value 2>/dev/null || true)"
        [ "$LINGER" = "yes" ] || fail "user lingering 未启用；管理员需执行 loginctl enable-linger $USER"
    fi
    UNIT_DIR="$HOME/.config/systemd/user"
    UNIT="vibedevops-runner-$SLUG.service"
    mkdir -p "$UNIT_DIR"
    [ ! -L "$UNIT_DIR/$UNIT" ] || fail "拒绝替换软链: $UNIT_DIR/$UNIT"
    SYSTEMD_WRAPPER="$(printf '%s' "$WRAPPER" | sed 's/\\/\\\\/g; s/"/\\"/g; s/%/%%/g')"
    cat > "$UNIT_DIR/$UNIT.new.$$" <<EOF
[Unit]
Description=VibeDevOps GitHub Actions runner ($REPO / $ROLE)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart="$SYSTEMD_WRAPPER"
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
    mv "$UNIT_DIR/$UNIT.new.$$" "$UNIT_DIR/$UNIT"
    chmod 600 "$UNIT_DIR/$UNIT"
    systemctl --user daemon-reload
    systemctl --user enable "$UNIT"
    systemctl --user restart "$UNIT"
fi

echo "✅ GitHub runner 已常驻：repo=$REPO role=$ROLE name=$RUNNER_NAME labels=$LABELS"
