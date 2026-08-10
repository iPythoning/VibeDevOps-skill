#!/bin/bash

set -e
umask 077

ADDR="127.0.0.1:8787"
LABEL="ai.reasonix.serve"
OFFLINE=0
OS_NAME="${VIBEDEVOPS_REASONIX_OS:-$(uname -s)}"
REASONIX_HOME="${REASONIX_HOME:-$HOME/.reasonix}"
REASONIX_BIN="${VIBEDEVOPS_REASONIX_BIN:-}"

fail() {
    echo "❌ $*" >&2
    exit 1
}

mode_of() {
    if [ "$(uname -s)" = "Darwin" ]; then
        stat -f '%Lp' "$1"
    else
        stat -c '%a' "$1"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --addr) ADDR=$2; shift 2 ;;
        --label) LABEL=$2; shift 2 ;;
        --offline) OFFLINE=1; shift ;;
        --reasonix-home) REASONIX_HOME=$2; shift 2 ;;
        *) fail "未知参数: $1" ;;
    esac
done

case "$ADDR" in 127.0.0.1:*|'[::1]':*) ;; *) fail "无认证服务地址不是字面量 loopback: $ADDR" ;; esac
PORT="${ADDR##*:}"
case "$PORT" in ''|*[!0-9]*) fail "端口必须是 1-65535 的整数: $PORT" ;; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || fail "端口必须介于 1 和 65535"

CONFIG_FILE="$REASONIX_HOME/config.toml"
CREDENTIALS_FILE="$REASONIX_HOME/.env"

[ -f "$CONFIG_FILE" ] || fail "缺少 Reasonix 配置: $CONFIG_FILE"
if [ -z "$REASONIX_BIN" ]; then
    REASONIX_BIN="$(command -v reasonix 2>/dev/null || true)"
fi
[ -n "$REASONIX_BIN" ] && [ -x "$REASONIX_BIN" ] || fail "未找到可执行的 reasonix"
command -v node >/dev/null 2>&1 || fail "解析 Reasonix doctor 结果需要 Node.js"
DOCTOR_JSON="$(mktemp "$REASONIX_HOME/.health-doctor.XXXXXX.json")"
cleanup_doctor() {
    rm -f "$DOCTOR_JSON"
}
trap cleanup_doctor EXIT HUP INT TERM
REASONIX_HOME="$REASONIX_HOME" "$REASONIX_BIN" doctor --json > "$DOCTOR_JSON" || fail "Reasonix doctor 失败"
API_KEY_ENV="$(node -e '
const report = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const matches = (report.providers || []).filter((provider) => provider.name === "opencode-go");
if (matches.length !== 1 || typeof matches[0].api_key_env !== "string") process.exit(1);
process.stdout.write(matches[0].api_key_env);
' "$DOCTOR_JSON")" || fail "config.toml 必须且只能配置一个 opencode-go Provider"
case "$API_KEY_ENV" in
    [0-9]*|*[!A-Za-z0-9_]*) fail "Provider api_key_env 非法: $API_KEY_ENV" ;;
esac
[ -f "$CREDENTIALS_FILE" ] || fail "缺少 Reasonix Provider 凭据文件: $CREDENTIALS_FILE"
[ ! -L "$CREDENTIALS_FILE" ] || fail "拒绝使用凭据软链: $CREDENTIALS_FILE"
[ "$(mode_of "$CREDENTIALS_FILE")" = "600" ] || fail "$CREDENTIALS_FILE 权限过宽，应为 0600"
grep -Eq "^[[:space:]]*(export[[:space:]]+)?${API_KEY_ENV}=" "$CREDENTIALS_FILE" || fail "$CREDENTIALS_FILE 缺少 $API_KEY_ENV"

VERSION="$("$REASONIX_BIN" --version 2>/dev/null || true)"

if [ "$OFFLINE" = "0" ]; then
    case "$OS_NAME" in
        Darwin)
            launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || fail "launchd 服务未运行: $LABEL"
            ;;
        Linux)
            command -v loginctl >/dev/null 2>&1 || fail "Linux 常驻检查需要 loginctl"
            [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" = "yes" ] || fail "user lingering 未启用，注销后服务不会常驻"
            systemctl --user is-active --quiet reasonix-serve.service || fail "systemd user 服务未运行: reasonix-serve.service"
            ;;
        *) fail "不支持的系统: $OS_NAME" ;;
    esac

    HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://$ADDR/healthz" 2>/dev/null || true)"
    [ "$HTTP_CODE" = "200" ] || fail "Reasonix /healthz 返回 $HTTP_CODE"
else
    HTTP_CODE="offline"
fi

echo "✅ Reasonix runtime healthy"
echo "   version: ${VERSION:-unknown}"
echo "   provider: opencode-go ($API_KEY_ENV)"
echo "   endpoint: http://$ADDR/healthz ($HTTP_CODE)"
