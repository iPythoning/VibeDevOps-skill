#!/bin/bash

set -e
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROVIDER_TEMPLATE="$SCRIPT_DIR/provider-opencode-go.toml"
MODEL="opencode-go/deepseek-v4-flash"
PROFILE="balanced"
ADDR="127.0.0.1:8787"
LABEL="ai.reasonix.serve"
COMPACT_RATIO="85"
READ_KEY_STDIN=0
NO_START=0
DRY_RUN=0
ENABLE_LINGER=0
OS_NAME="${VIBEDEVOPS_REASONIX_OS:-$(uname -s)}"
REASONIX_HOME="${REASONIX_HOME:-$HOME/.reasonix}"
REASONIX_BIN="${VIBEDEVOPS_REASONIX_BIN:-}"

fail() {
    echo "❌ $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --api-key-stdin       从 stdin 读取 OpenCode Go API Key，不把密钥放进 argv
  --reasonix-home PATH  覆盖 Reasonix home（默认 ~/.reasonix）
  --binary PATH         指定 reasonix 二进制
  --model MODEL         常驻服务默认模型
  --profile PROFILE     economy | balanced | delivery
  --addr HOST:PORT      仅允许 loopback 地址
  --compact-ratio N     自动 compaction 阈值，65-85（默认 85）
  --no-start            生成配置和服务文件，但不加载服务
  --enable-linger       Linux 上授权启用 user lingering，确保注销后仍常驻
  --dry-run             只显示计划，不写文件
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --api-key-stdin) READ_KEY_STDIN=1; shift ;;
        --reasonix-home) REASONIX_HOME=$2; shift 2 ;;
        --binary) REASONIX_BIN=$2; shift 2 ;;
        --model) MODEL=$2; shift 2 ;;
        --profile) PROFILE=$2; shift 2 ;;
        --addr) ADDR=$2; shift 2 ;;
        --compact-ratio) COMPACT_RATIO=$2; shift 2 ;;
        --no-start) NO_START=1; shift ;;
        --enable-linger) ENABLE_LINGER=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "未知参数: $1" ;;
    esac
done

case "$HOME" in ""|/) fail "HOME 不能是空值或 /" ;; esac
case "$REASONIX_HOME" in ""|/) fail "Reasonix home 不能是空值或 /" ;; esac
case "$ADDR" in 127.0.0.1:*|'[::1]':*) ;; *) fail "无认证模板只允许字面量 loopback 地址: $ADDR" ;; esac
PORT="${ADDR##*:}"
case "$PORT" in ''|*[!0-9]*) fail "端口必须是 1-65535 的整数: $PORT" ;; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || fail "端口必须介于 1 和 65535"
case "$PROFILE" in economy|balanced|delivery) ;; *) fail "无效 profile: $PROFILE" ;; esac
case "$COMPACT_RATIO" in ''|*[!0-9]*) fail "compact ratio 必须是 65-85 的整数" ;; esac
[ "$COMPACT_RATIO" -ge 65 ] && [ "$COMPACT_RATIO" -le 85 ] || fail "compact ratio 必须介于 65 和 85"
[ -f "$PROVIDER_TEMPLATE" ] || fail "缺少 Provider 模板: $PROVIDER_TEMPLATE"
case "$MODEL" in opencode-go/*) MODEL_ID="${MODEL#opencode-go/}" ;; *) fail "此模板只管理 opencode-go 模型: $MODEL" ;; esac
case "$MODEL_ID" in ''|*[!A-Za-z0-9._:-]*) fail "模型 ID 含非法字符: $MODEL_ID" ;; esac
grep -Fq "\"$MODEL_ID\"" "$PROVIDER_TEMPLATE" || fail "Provider 模板未声明模型: $MODEL_ID"
command -v node >/dev/null 2>&1 || fail "解析 Reasonix doctor 结果需要 Node.js"

if [ -z "$REASONIX_BIN" ]; then
    REASONIX_BIN="$(command -v reasonix 2>/dev/null || true)"
fi
[ -n "$REASONIX_BIN" ] && [ -x "$REASONIX_BIN" ] || fail "未找到可执行的 reasonix；先运行 npm i -g reasonix"
case "$REASONIX_BIN" in /*) ;; *) REASONIX_BIN="$(cd "$(dirname "$REASONIX_BIN")" && pwd)/$(basename "$REASONIX_BIN")" ;; esac

CONFIG_FILE="$REASONIX_HOME/config.toml"
CREDENTIALS_FILE="$REASONIX_HOME/.env"
LOG_DIR="$REASONIX_HOME/log"
WRAPPER="$HOME/.local/bin/reasonix-vibedevops-serve"
SERVICE_PATH="$(dirname "$REASONIX_BIN"):$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

case "$OS_NAME" in
    Darwin) SERVICE_FILE="$HOME/Library/LaunchAgents/$LABEL.plist" ;;
    Linux) SERVICE_FILE="$HOME/.config/systemd/user/reasonix-serve.service" ;;
    *) fail "只支持 macOS 和 Linux: $OS_NAME" ;;
esac

if [ "$DRY_RUN" = "1" ]; then
    echo "Reasonix runtime plan"
    echo "  binary: $REASONIX_BIN"
    echo "  config: $CONFIG_FILE"
    echo "  service: $SERVICE_FILE"
    echo "  endpoint: http://$ADDR"
    echo "  model: $MODEL"
    exit 0
fi

mkdir -p "$REASONIX_HOME" "$LOG_DIR" "$(dirname "$WRAPPER")" "$(dirname "$SERVICE_FILE")"

for managed_path in "$CONFIG_FILE" "$CREDENTIALS_FILE" "$WRAPPER" "$SERVICE_FILE"; do
    [ ! -L "$managed_path" ] || fail "拒绝替换受管文件软链: $managed_path"
    [ ! -e "$managed_path" ] || [ -f "$managed_path" ] || fail "受管路径不是普通文件: $managed_path"
done
[ ! -f "$CREDENTIALS_FILE" ] || chmod 600 "$CREDENTIALS_FILE"

staged_config=""
staged_credentials=""
staged_wrapper=""
staged_service=""
VALIDATE_HOME=""
cleanup_staging() {
    [ -z "$staged_config" ] || rm -f "$staged_config"
    [ -z "$staged_credentials" ] || rm -f "$staged_credentials"
    [ -z "$staged_wrapper" ] || rm -f "$staged_wrapper"
    [ -z "$staged_service" ] || rm -f "$staged_service"
    [ -z "$VALIDATE_HOME" ] || rm -rf "$VALIDATE_HOME"
}
trap cleanup_staging EXIT HUP INT TERM

backup_file() {
    local target=$1
    local mode=$2
    local stamp="$(date +%Y%m%d%H%M%S)"
    local backup="$target.$stamp.$$.bak"
    local index=0
    while [ -e "$backup" ]; do
        index=$((index + 1))
        backup="$target.$stamp.$$.$index.bak"
    done
    cp "$target" "$backup"
    chmod "$mode" "$backup"
    echo "   backup: $backup"
}

install_generated() {
    local staged=$1
    local target=$2
    local mode=$3
    if [ -f "$target" ] && cmp -s "$staged" "$target"; then
        rm -f "$staged"
        chmod "$mode" "$target"
        return
    fi
    [ -e "$target" ] && backup_file "$target" "$mode"
    mv "$staged" "$target"
    chmod "$mode" "$target"
}

if [ ! -f "$CONFIG_FILE" ]; then
    staged_config="$CONFIG_FILE.new.$$"
    {
        echo 'config_version = 5'
        printf 'default_model = "%s"\n\n' "$MODEL"
        echo '[agent]'
        echo 'soft_compact_ratio = 0.5'
        echo 'tool_result_snip_ratio = 0.6'
        printf 'compact_ratio = 0.%s\n' "$COMPACT_RATIO"
        echo 'compact_force_ratio = 0.9'
        echo 'cold_resume_prune = true'
        echo
        sed -n '1,$p' "$PROVIDER_TEMPLATE"
    } > "$staged_config"
    API_KEY_ENV="OPENCODE_GO_API_KEY"
else
    DOCTOR_JSON="$(mktemp "$REASONIX_HOME/.doctor.XXXXXX.json")"
    if ! REASONIX_HOME="$REASONIX_HOME" "$REASONIX_BIN" doctor --json > "$DOCTOR_JSON"; then
        rm -f "$DOCTOR_JSON"
        fail "现有 config.toml 未通过 Reasonix doctor，未做任何修改"
    fi
    set +e
    API_KEY_ENV="$(node -e '
const fs = require("fs");
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const matches = (report.providers || []).filter((provider) => provider.name === "opencode-go");
if (matches.length === 0) process.exit(3);
if (matches.length > 1) process.exit(6);
const provider = matches[0];
if (typeof provider.api_key_env !== "string" || !provider.api_key_env) process.exit(5);
if (!Array.isArray(provider.models) || !provider.models.includes(process.argv[2])) process.exit(4);
process.stdout.write(provider.api_key_env);
' "$DOCTOR_JSON" "$MODEL_ID" 2>/dev/null)"
    PROVIDER_STATUS=$?
    set -e
    rm -f "$DOCTOR_JSON"
    case "$PROVIDER_STATUS" in
        0) APPEND_PROVIDER=0 ;;
        3) API_KEY_ENV="OPENCODE_GO_API_KEY"; APPEND_PROVIDER=1 ;;
        4) fail "现有 opencode-go Provider 未声明模型 $MODEL_ID；未修改默认模型" ;;
        5) fail "现有 opencode-go Provider 缺少 api_key_env；请先修复配置" ;;
        6) fail "检测到重复的 opencode-go Provider；请先去重" ;;
        *) fail "无法解析 Reasonix doctor 输出；未做任何修改" ;;
    esac
    staged_config="$CONFIG_FILE.new.$$"
    cp "$CONFIG_FILE" "$staged_config"
    if [ "$APPEND_PROVIDER" = "1" ]; then
        printf '\n' >> "$staged_config"
        sed -n '1,$p' "$PROVIDER_TEMPLATE" >> "$staged_config"
    fi
fi

case "$API_KEY_ENV" in
    ''|[0-9]*|*[!A-Za-z0-9_]*) fail "Provider api_key_env 非法: $API_KEY_ENV" ;;
esac

credential_present() {
    [ -f "$CREDENTIALS_FILE" ] && grep -Eq "^[[:space:]]*(export[[:space:]]+)?${API_KEY_ENV}=" "$CREDENTIALS_FILE"
}

stage_credential() {
    local secret=$1
    : > "$staged_credentials"
    if [ -f "$CREDENTIALS_FILE" ]; then
        awk -v key="$API_KEY_ENV" '
            {
                probe = $0
                sub(/^[[:space:]]*/, "", probe)
                sub(/^export[[:space:]]+/, "", probe)
                if (substr(probe, 1, length(key) + 1) == key "=") next
                print
            }
        ' "$CREDENTIALS_FILE" > "$staged_credentials"
    fi
    printf '%s=%s\n' "$API_KEY_ENV" "$secret" >> "$staged_credentials"
    chmod 600 "$staged_credentials"
}

staged_credentials="$CREDENTIALS_FILE.new.$$"
if [ "$READ_KEY_STDIN" = "1" ]; then
    IFS= read -r API_KEY || fail "stdin 中没有 API Key"
    [ -n "$API_KEY" ] || fail "API Key 不能为空"
    stage_credential "$API_KEY"
    unset API_KEY
elif ! credential_present; then
    if [ -t 0 ]; then
        printf 'OpenCode Go API Key（不会回显）: ' >&2
        IFS= read -r -s API_KEY
        printf '\n' >&2
        [ -n "$API_KEY" ] || fail "API Key 不能为空"
        stage_credential "$API_KEY"
        unset API_KEY
    else
        fail "缺少 $API_KEY_ENV；交互运行或使用 --api-key-stdin"
    fi
else
    cp "$CREDENTIALS_FILE" "$staged_credentials"
    chmod 600 "$staged_credentials"
fi

VALIDATE_HOME="$(mktemp -d "$REASONIX_HOME/.vibedevops-validate.XXXXXX")"
cp "$staged_config" "$VALIDATE_HOME/config.toml"
cp "$staged_credentials" "$VALIDATE_HOME/.env"
chmod 600 "$VALIDATE_HOME/config.toml" "$VALIDATE_HOME/.env"
if ! REASONIX_HOME="$VALIDATE_HOME" "$REASONIX_BIN" config compact-ratio "$COMPACT_RATIO" >/dev/null; then
    fail "staged config 未通过 compact-ratio；正式配置未修改"
fi
if ! REASONIX_HOME="$VALIDATE_HOME" "$REASONIX_BIN" doctor --json > "$VALIDATE_HOME/doctor.json"; then
    fail "staged config 未通过 Reasonix doctor；正式配置未修改"
fi
node -e '
const fs = require("fs");
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const matches = (report.providers || []).filter((provider) => provider.name === "opencode-go");
if (matches.length !== 1) process.exit(1);
const provider = matches[0];
if (provider.api_key_env !== process.argv[3]) process.exit(1);
if (!Array.isArray(provider.models) || !provider.models.includes(process.argv[2])) process.exit(1);
' "$VALIDATE_HOME/doctor.json" "$MODEL_ID" "$API_KEY_ENV" || fail "staged Provider 语义校验失败；正式配置未修改"
cp "$VALIDATE_HOME/config.toml" "$staged_config"
case "$CONFIG_FILE" in "$HOME"/*) DISPLAY_CONFIG="~/${CONFIG_FILE#"$HOME"/}" ;; *) DISPLAY_CONFIG="$CONFIG_FILE" ;; esac
RESOLUTION_LINE="# Resolution order: flag > ./reasonix.toml > $DISPLAY_CONFIG > built-in defaults."
if [ -n "$RESOLUTION_LINE" ] && grep -q '^# Resolution order:' "$staged_config"; then
    normalized_config="$CONFIG_FILE.normalized.$$"
    awk -v resolution="$RESOLUTION_LINE" '
        /^# Resolution order:/ { print resolution; next }
        { print }
    ' "$staged_config" > "$normalized_config"
    mv "$normalized_config" "$staged_config"
fi
rm -rf "$VALIDATE_HOME"
VALIDATE_HOME=""

install_generated "$staged_credentials" "$CREDENTIALS_FILE" 600
install_generated "$staged_config" "$CONFIG_FILE" 600

shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

staged_wrapper="$WRAPPER.new.$$"
{
    echo '#!/bin/sh'
    echo 'exec /usr/bin/env -i \'
    printf '  HOME=%s \\\n' "$(shell_quote "$HOME")"
    printf '  PATH=%s \\\n' "$(shell_quote "$SERVICE_PATH")"
    printf '  REASONIX_HOME=%s \\\n' "$(shell_quote "$REASONIX_HOME")"
    printf '  %s serve \\\n' "$(shell_quote "$REASONIX_BIN")"
    printf '    --addr %s \\\n' "$(shell_quote "$ADDR")"
    echo "    --auth none \\"
    printf '    --model %s \\\n' "$(shell_quote "$MODEL")"
    printf '    --profile %s\n' "$(shell_quote "$PROFILE")"
} > "$staged_wrapper"
install_generated "$staged_wrapper" "$WRAPPER" 700

xml_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

if [ "$OS_NAME" = "Darwin" ]; then
    staged_service="$SERVICE_FILE.new.$$"
    cat > "$staged_service" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$(xml_escape "$LABEL")</string>
  <key>Program</key><string>$(xml_escape "$WRAPPER")</string>
  <key>WorkingDirectory</key><string>$(xml_escape "$HOME")</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$(xml_escape "$LOG_DIR/reasonix-serve.log")</string>
  <key>StandardErrorPath</key><string>$(xml_escape "$LOG_DIR/reasonix-serve.error.log")</string>
</dict>
</plist>
EOF
else
    staged_service="$SERVICE_FILE.new.$$"
    escaped_wrapper="$(printf '%s' "$WRAPPER" | sed 's/\\/\\\\/g; s/"/\\"/g; s/%/%%/g')"
    cat > "$staged_service" <<EOF
[Unit]
Description=Reasonix local agent server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart="$escaped_wrapper"
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=default.target
EOF
fi
install_generated "$staged_service" "$SERVICE_FILE" 600

if [ "$NO_START" = "0" ]; then
    if [ "$OS_NAME" = "Darwin" ]; then
        launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
        launchctl bootstrap "gui/$(id -u)" "$SERVICE_FILE"
        launchctl enable "gui/$(id -u)/$LABEL"
        launchctl kickstart -k "gui/$(id -u)/$LABEL"
    else
        command -v loginctl >/dev/null 2>&1 || fail "Linux 常驻需要 loginctl"
        CURRENT_USER="$(id -un)"
        LINGER="$(loginctl show-user "$CURRENT_USER" -p Linger --value 2>/dev/null || true)"
        if [ "$LINGER" != "yes" ]; then
            [ "$ENABLE_LINGER" = "1" ] || fail "user lingering 未启用；确认后加 --enable-linger 重试"
            loginctl enable-linger "$CURRENT_USER" || fail "无法启用 user lingering；请运行 loginctl enable-linger $CURRENT_USER"
            LINGER="$(loginctl show-user "$CURRENT_USER" -p Linger --value 2>/dev/null || true)"
            [ "$LINGER" = "yes" ] || fail "user lingering 启用后未生效"
        fi
        systemctl --user daemon-reload
        systemctl --user enable --now reasonix-serve.service
        systemctl --user restart reasonix-serve.service
    fi

    attempts=0
    until curl -fsS --max-time 3 "http://$ADDR/healthz" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 10 ] || fail "Reasonix 启动后未通过 /healthz；查看 $LOG_DIR"
        sleep 1
    done
    VIBEDEVOPS_REASONIX_BIN="$REASONIX_BIN" "$SCRIPT_DIR/health-check.sh" --addr "$ADDR" --label "$LABEL" --reasonix-home "$REASONIX_HOME"
fi

echo "✅ Reasonix runtime 已配置"
echo "   provider: opencode-go ($API_KEY_ENV)"
echo "   model: $MODEL"
echo "   service: $SERVICE_FILE"
echo "   endpoint: http://$ADDR"
