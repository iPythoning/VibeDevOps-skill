#!/bin/bash

set -e
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/cleanup-docker-images.sh"
GHCR_SOURCE="$SCRIPT_DIR/cleanup-ghcr-versions.sh"
OS_NAME="${VIBEDEVOPS_IMAGE_GUARD_OS:-$(uname -s)}"
TARGET_DIR="$HOME/.local/lib/vibedevops"
TARGET="$TARGET_DIR/cleanup-docker-images.sh"
LOG_DIR="$HOME/.local/state/vibedevops"
RETENTION_HOURS=168
KEEP_PER_REPOSITORY=5
WITH_GHCR=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --retention-hours) RETENTION_HOURS=$2; shift 2 ;;
        --keep-per-repository) KEEP_PER_REPOSITORY=$2; shift 2 ;;
        --with-ghcr) WITH_GHCR=1; shift ;;
        *) echo "❌ 未知参数: $1" >&2; exit 1 ;;
    esac
done
case "$RETENTION_HOURS" in ''|*[!0-9]*) echo "❌ retention-hours 必须是整数" >&2; exit 1 ;; esac
case "$KEEP_PER_REPOSITORY" in ''|*[!0-9]*) echo "❌ keep-per-repository 必须是整数" >&2; exit 1 ;; esac
[ "$RETENTION_HOURS" -ge 24 ] || { echo "❌ retention-hours 至少为 24" >&2; exit 1; }
[ "$KEEP_PER_REPOSITORY" -ge 2 ] || { echo "❌ keep-per-repository 至少为 2" >&2; exit 1; }
case "$OS_NAME" in Darwin|Linux) ;; *) echo "❌ 只支持 macOS/Linux: $OS_NAME" >&2; exit 1 ;; esac

case "$HOME" in ''|/) echo "❌ HOME 不能是空值或 /" >&2; exit 1 ;; esac
[ -x "$SOURCE" ] || { echo "❌ 缺少 cleanup 脚本: $SOURCE" >&2; exit 1; }
if [ "$WITH_GHCR" = "1" ]; then
    [ -x "$GHCR_SOURCE" ] || { echo "❌ 缺少 GHCR cleanup 脚本: $GHCR_SOURCE" >&2; exit 1; }
    command -v gh >/dev/null 2>&1 || { echo "❌ GHCR 守卫需要 gh CLI" >&2; exit 1; }
    gh auth status 2>&1 | grep -q "delete:packages" || { echo "❌ gh token 缺少 delete:packages scope" >&2; exit 1; }
fi
mkdir -p "$TARGET_DIR" "$LOG_DIR"
[ ! -L "$TARGET" ] || { echo "❌ 拒绝替换软链: $TARGET" >&2; exit 1; }
cp "$SOURCE" "$TARGET.new.$$"
chmod 700 "$TARGET.new.$$"
mv "$TARGET.new.$$" "$TARGET"

xml_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

if [ "$OS_NAME" = "Darwin" ]; then
    LABEL="dev.vibedevops.image-cleanup"
    SERVICE="$HOME/Library/LaunchAgents/$LABEL.plist"
    mkdir -p "$(dirname "$SERVICE")"
    [ ! -L "$SERVICE" ] || { echo "❌ 拒绝替换软链: $SERVICE" >&2; exit 1; }
    cat > "$SERVICE.new.$$" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml_escape "$TARGET")</string><string>--apply</string><string>--retention-hours</string><string>$RETENTION_HOURS</string>
    <string>--keep-per-repository</string><string>$KEEP_PER_REPOSITORY</string><string>--prune-build-cache</string>
  </array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$(xml_escape "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")</string></dict>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$(xml_escape "$LOG_DIR/image-cleanup.log")</string>
  <key>StandardErrorPath</key><string>$(xml_escape "$LOG_DIR/image-cleanup.error.log")</string>
</dict>
</plist>
EOF
    plutil -lint "$SERVICE.new.$$" >/dev/null
    mv "$SERVICE.new.$$" "$SERVICE"
    chmod 600 "$SERVICE"
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$SERVICE"
    launchctl enable "gui/$(id -u)/$LABEL"
else
    UNIT_DIR="$HOME/.config/systemd/user"
    SERVICE="$UNIT_DIR/vibedevops-image-cleanup.service"
    TIMER="$UNIT_DIR/vibedevops-image-cleanup.timer"
    mkdir -p "$UNIT_DIR"
    [ ! -L "$SERVICE" ] && [ ! -L "$TIMER" ] || { echo "❌ 拒绝替换 systemd 软链" >&2; exit 1; }
    escaped_target="$(printf '%s' "$TARGET" | sed 's/\\/\\\\/g; s/"/\\"/g; s/%/%%/g')"
    cat > "$SERVICE.new.$$" <<EOF
[Unit]
Description=VibeDevOps safe Docker image cleanup

[Service]
Type=oneshot
ExecStart="$escaped_target" --apply --retention-hours $RETENTION_HOURS --keep-per-repository $KEEP_PER_REPOSITORY --prune-build-cache
NoNewPrivileges=true
PrivateTmp=true
EOF
    cat > "$TIMER.new.$$" <<'EOF'
[Unit]
Description=Daily VibeDevOps Docker image cleanup

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF
    mv "$SERVICE.new.$$" "$SERVICE"
    mv "$TIMER.new.$$" "$TIMER"
    chmod 600 "$SERVICE" "$TIMER"
    systemctl --user daemon-reload
    systemctl --user enable --now vibedevops-image-cleanup.timer
fi

if [ "$WITH_GHCR" = "1" ]; then
    GHCR_TARGET="$TARGET_DIR/cleanup-ghcr-versions.sh"
    [ ! -L "$GHCR_TARGET" ] || { echo "❌ 拒绝替换软链: $GHCR_TARGET" >&2; exit 1; }
    cp "$GHCR_SOURCE" "$GHCR_TARGET.new.$$"
    chmod 700 "$GHCR_TARGET.new.$$"
    mv "$GHCR_TARGET.new.$$" "$GHCR_TARGET"
    if [ "$OS_NAME" = "Darwin" ]; then
        GHCR_LABEL="dev.vibedevops.ghcr-cleanup"
        GHCR_SERVICE="$HOME/Library/LaunchAgents/$GHCR_LABEL.plist"
        [ ! -L "$GHCR_SERVICE" ] || { echo "❌ 拒绝替换软链: $GHCR_SERVICE" >&2; exit 1; }
        cat > "$GHCR_SERVICE.new.$$" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$GHCR_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml_escape "$GHCR_TARGET")</string><string>--all-packages</string><string>--keep-count</string><string>30</string>
    <string>--min-age-hours</string><string>6</string><string>--apply</string>
  </array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$(xml_escape "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")</string></dict>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$(xml_escape "$LOG_DIR/ghcr-cleanup.log")</string>
  <key>StandardErrorPath</key><string>$(xml_escape "$LOG_DIR/ghcr-cleanup.error.log")</string>
</dict>
</plist>
EOF
        plutil -lint "$GHCR_SERVICE.new.$$" >/dev/null
        mv "$GHCR_SERVICE.new.$$" "$GHCR_SERVICE"
        chmod 600 "$GHCR_SERVICE"
        launchctl bootout "gui/$(id -u)/$GHCR_LABEL" >/dev/null 2>&1 || true
        launchctl bootstrap "gui/$(id -u)" "$GHCR_SERVICE"
        launchctl enable "gui/$(id -u)/$GHCR_LABEL"
    else
        GHCR_SERVICE="$UNIT_DIR/vibedevops-ghcr-cleanup.service"
        GHCR_TIMER="$UNIT_DIR/vibedevops-ghcr-cleanup.timer"
        [ ! -L "$GHCR_SERVICE" ] && [ ! -L "$GHCR_TIMER" ] || { echo "❌ 拒绝替换 GHCR systemd 软链" >&2; exit 1; }
        escaped_ghcr="$(printf '%s' "$GHCR_TARGET" | sed 's/\\/\\\\/g; s/"/\\"/g; s/%/%%/g')"
        cat > "$GHCR_SERVICE.new.$$" <<EOF
[Unit]
Description=VibeDevOps GHCR retention

[Service]
Type=oneshot
ExecStart="$escaped_ghcr" --all-packages --keep-count 30 --min-age-hours 6 --apply
Environment="PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
NoNewPrivileges=true
PrivateTmp=true
EOF
        cat > "$GHCR_TIMER.new.$$" <<'EOF'
[Unit]
Description=Daily VibeDevOps GHCR retention

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF
        mv "$GHCR_SERVICE.new.$$" "$GHCR_SERVICE"
        mv "$GHCR_TIMER.new.$$" "$GHCR_TIMER"
        chmod 600 "$GHCR_SERVICE" "$GHCR_TIMER"
        systemctl --user daemon-reload
        systemctl --user enable --now vibedevops-ghcr-cleanup.timer
    fi
    echo "✅ GHCR 每日 retention 已安装：最新 30 个 versions + 生产/回滚 tag + 6 小时安全窗"
fi

echo "✅ 本机镜像防护已安装：保留每仓库最新 $KEEP_PER_REPOSITORY 份，清理 ${RETENTION_HOURS} 小时前且未被任何容器引用的镜像和 build cache"
