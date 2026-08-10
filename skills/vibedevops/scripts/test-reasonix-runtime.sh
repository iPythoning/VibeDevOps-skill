#!/bin/bash

set -e

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
INSTALLER="$ROOT/skills/vibedevops/templates/reasonix-runtime/install.sh"
HEALTH_CHECK="$ROOT/skills/vibedevops/templates/reasonix-runtime/health-check.sh"
FIXTURE_BASE="$(mktemp -d)"
FIXTURE_ROOT="$FIXTURE_BASE/reasonix runtime's"
mkdir -p "$FIXTURE_ROOT"
trap 'code=$?; [ "$code" -eq 0 ] || echo "reasonix runtime fixture failed near line $LINENO" >&2; rm -rf "$FIXTURE_BASE"' EXIT

mode_of() {
    if [ "$(uname -s)" = "Darwin" ]; then
        stat -f '%Lp' "$1"
    else
        stat -c '%a' "$1"
    fi
}

make_fake_reasonix() {
    local target=$1
    mkdir -p "$(dirname "$target")"
    cat > "$target" <<'EOF'
#!/bin/sh
case "$1" in
    --version) echo "reasonix v1.21.5" ;;
    config) [ "${VIBEDEVOPS_FAKE_CONFIG_FAIL:-0}" = "1" ] && exit 1; exit 0 ;;
    doctor)
        config="${REASONIX_HOME:-$HOME/.reasonix}/config.toml"
        count="$(grep -Ec "name[[:space:]]*=[[:space:]]*['\"]opencode-go['\"]" "$config" 2>/dev/null || true)"
        if [ "$count" -gt 1 ]; then
            echo '{"providers":[{"name":"opencode-go","models":["deepseek-v4-flash"],"api_key_env":"OPENCODE_GO_API_KEY"},{"name":"opencode-go","models":["deepseek-v4-flash"],"api_key_env":"OPENCODE_GO_API_KEY"}]}'
        elif [ "$count" -eq 1 ]; then
            if grep -Eq "['\"]deepseek-v4-flash['\"]" "$config"; then model=deepseek-v4-flash; else model=glm-5.2; fi
            printf '{"providers":[{"name":"opencode-go","models":["%s"],"api_key_env":"OPENCODE_GO_API_KEY"}]}\n' "$model"
        else
            echo '{"providers":[]}'
        fi
        ;;
esac
exit 0
EOF
    chmod +x "$target"
}

run_fixture() {
    local os_name=$1
    local fixture_home="$FIXTURE_ROOT/$os_name/home"
    local fake_bin="$FIXTURE_ROOT/$os_name/bin/reasonix"
    mkdir -p "$fixture_home"
    make_fake_reasonix "$fake_bin"

    if [ "$os_name" = "Linux" ]; then
        mkdir -p "$fixture_home/.reasonix"
        cat > "$fixture_home/.reasonix/config.toml" <<'EOF'
config_version = 5
default_model = "custom/local"
language = "zh"

[[providers]]
name = "custom"
kind = "openai"
base_url = "http://127.0.0.1:9999/v1"
models = ["local"]
default = "local"
api_key_env = "CUSTOM_API_KEY"
EOF
        printf 'CUSTOM_API_KEY=preserve-me\n  OPENCODE_GO_API_KEY=old-one\n export OPENCODE_GO_API_KEY=old-two\n' > "$fixture_home/.reasonix/.env"
        chmod 644 "$fixture_home/.reasonix/.env"
    fi

    printf 'fixture-opencode-key\n' | HOME="$fixture_home" VIBEDEVOPS_REASONIX_OS="$os_name" VIBEDEVOPS_REASONIX_BIN="$fake_bin" \
        "$INSTALLER" --api-key-stdin --no-start >/dev/null

    CONFIG="$fixture_home/.reasonix/config.toml"
    CREDENTIALS="$fixture_home/.reasonix/.env"
    WRAPPER="$fixture_home/.local/bin/reasonix-vibedevops-serve"
    if [ "$os_name" = "Linux" ]; then
        grep -qxF 'default_model = "custom/local"' "$CONFIG"
    else
        grep -qxF 'default_model = "opencode-go/deepseek-v4-flash"' "$CONFIG"
    fi
    [ "$(grep -cxF 'name           = "opencode-go"' "$CONFIG")" = 1 ]
    grep -qxF 'base_url       = "https://opencode.ai/zen/go/v1"' "$CONFIG"
    grep -qxF 'api_key_env    = "OPENCODE_GO_API_KEY"' "$CONFIG"
    grep -qxF 'OPENCODE_GO_API_KEY=fixture-opencode-key' "$CREDENTIALS"
    [ "$(grep -Ec '^[[:space:]]*(export[[:space:]]+)?OPENCODE_GO_API_KEY=' "$CREDENTIALS")" = 1 ]
    ! grep -q 'old-one\|old-two' "$CREDENTIALS"
    [ "$(mode_of "$CREDENTIALS")" = 600 ]
    for backup in "$CREDENTIALS".*.bak; do
        [ ! -e "$backup" ] || [ "$(mode_of "$backup")" = 600 ]
    done
    [ "$(mode_of "$WRAPPER")" = 700 ]
    sh -n "$WRAPPER"
    "$WRAPPER" >/dev/null
    ! grep -R 'fixture-opencode-key' "$fixture_home/.reasonix/config.toml" "$WRAPPER" "$fixture_home/Library" "$fixture_home/.config" 2>/dev/null

    if [ "$os_name" = "Darwin" ]; then
        SERVICE="$fixture_home/Library/LaunchAgents/ai.reasonix.serve.plist"
        grep -q '<key>KeepAlive</key><true/>' "$SERVICE"
        grep -q '<key>RunAtLoad</key><true/>' "$SERVICE"
        command -v plutil >/dev/null 2>&1 && plutil -lint "$SERVICE" >/dev/null
    else
        SERVICE="$fixture_home/.config/systemd/user/reasonix-serve.service"
        grep -qxF 'Restart=always' "$SERVICE"
        grep -qxF 'NoNewPrivileges=true' "$SERVICE"
        grep -qxF 'name = "custom"' "$CONFIG"
        grep -qxF 'CUSTOM_API_KEY=preserve-me' "$CREDENTIALS"
    fi

    HOME="$fixture_home" PATH="$(dirname "$fake_bin"):$PATH" VIBEDEVOPS_REASONIX_OS="$os_name" \
        "$HEALTH_CHECK" --offline >/dev/null

    chmod 644 "$CREDENTIALS"
    HOME="$fixture_home" VIBEDEVOPS_REASONIX_OS="$os_name" VIBEDEVOPS_REASONIX_BIN="$fake_bin" \
        "$INSTALLER" --no-start >/dev/null
    [ "$(mode_of "$CREDENTIALS")" = 600 ]
    [ "$(grep -cxF 'name           = "opencode-go"' "$CONFIG")" = 1 ]
}

run_fixture Darwin
run_fixture Linux

reject_home="$FIXTURE_ROOT/reject/home"
reject_bin="$FIXTURE_ROOT/reject/bin/reasonix"
mkdir -p "$reject_home"
make_fake_reasonix "$reject_bin"
if printf 'fixture-opencode-key\n' | HOME="$reject_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$reject_bin" \
    "$INSTALLER" --api-key-stdin --no-start --addr 0.0.0.0:8787 >/dev/null 2>&1; then
    echo "non-loopback Reasonix address was accepted" >&2
    exit 1
fi

if printf 'fixture-opencode-key\n' | HOME="$reject_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$reject_bin" \
    "$INSTALLER" --api-key-stdin --no-start --addr localhost:8787 >/dev/null 2>&1; then
    echo "localhost Reasonix address was accepted" >&2
    exit 1
fi

missing_model_home="$FIXTURE_ROOT/missing-model/home"
missing_model_bin="$FIXTURE_ROOT/missing-model/bin/reasonix"
mkdir -p "$missing_model_home/.reasonix"
make_fake_reasonix "$missing_model_bin"
cat > "$missing_model_home/.reasonix/config.toml" <<'EOF'
config_version = 5
default_model = "opencode-go/glm-5.2"

[[providers]]
name = "opencode-go"
kind = "openai"
base_url = "https://opencode.ai/zen/go/v1"
models = ["glm-5.2"]
default = "glm-5.2"
api_key_env = "OPENCODE_GO_API_KEY"
EOF
printf 'OPENCODE_GO_API_KEY=preserve-me\n' > "$missing_model_home/.reasonix/.env"
if HOME="$missing_model_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$missing_model_bin" \
    "$INSTALLER" --no-start >/dev/null 2>&1; then
    echo "provider missing selected model was accepted" >&2
    exit 1
fi
grep -qxF 'default_model = "opencode-go/glm-5.2"' "$missing_model_home/.reasonix/config.toml"

symlink_home="$FIXTURE_ROOT/symlink/home"
symlink_bin="$FIXTURE_ROOT/symlink/bin/reasonix"
mkdir -p "$symlink_home/.reasonix"
make_fake_reasonix "$symlink_bin"
printf 'OPENCODE_GO_API_KEY=preserve-me\n' > "$symlink_home/credential-target"
ln -s "$symlink_home/credential-target" "$symlink_home/.reasonix/.env"
if printf 'replacement\n' | HOME="$symlink_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$symlink_bin" \
    "$INSTALLER" --api-key-stdin --no-start >/dev/null 2>&1; then
    echo "credential symlink was accepted" >&2
    exit 1
fi
grep -qxF 'OPENCODE_GO_API_KEY=preserve-me' "$symlink_home/credential-target"

config_symlink_home="$FIXTURE_ROOT/config-symlink/home"
config_symlink_bin="$FIXTURE_ROOT/config-symlink/bin/reasonix"
mkdir -p "$config_symlink_home/.reasonix"
make_fake_reasonix "$config_symlink_bin"
printf 'default_model = "custom/local"\n' > "$config_symlink_home/config-target"
ln -s "$config_symlink_home/config-target" "$config_symlink_home/.reasonix/config.toml"
if printf 'replacement\n' | HOME="$config_symlink_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$config_symlink_bin" \
    "$INSTALLER" --api-key-stdin --no-start >/dev/null 2>&1; then
    echo "config symlink was accepted" >&2
    exit 1
fi
grep -qxF 'default_model = "custom/local"' "$config_symlink_home/config-target"

transaction_home="$FIXTURE_ROOT/transaction/home"
transaction_bin="$FIXTURE_ROOT/transaction/bin/reasonix"
mkdir -p "$transaction_home/.reasonix"
make_fake_reasonix "$transaction_bin"
cat > "$transaction_home/.reasonix/config.toml" <<'EOF'
config_version = 5
default_model = "custom/local"
EOF
cp "$transaction_home/.reasonix/config.toml" "$transaction_home/original.toml"
if HOME="$transaction_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$transaction_bin" \
    "$INSTALLER" --no-start </dev/null >/dev/null 2>&1; then
    echo "installer modified config without credentials" >&2
    exit 1
fi
cmp -s "$transaction_home/original.toml" "$transaction_home/.reasonix/config.toml"

printf 'OPENCODE_GO_API_KEY=fixture-opencode-key\n' > "$transaction_home/.reasonix/.env"
if HOME="$transaction_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$transaction_bin" VIBEDEVOPS_FAKE_CONFIG_FAIL=1 \
    "$INSTALLER" --no-start >/dev/null 2>&1; then
    echo "installer accepted failed staged compact-ratio" >&2
    exit 1
fi
cmp -s "$transaction_home/original.toml" "$transaction_home/.reasonix/config.toml"

no_linger_home="$FIXTURE_ROOT/no-linger/home"
no_linger_bin="$FIXTURE_ROOT/no-linger/bin/reasonix"
no_linger_tools="$FIXTURE_ROOT/no-linger/tools"
mkdir -p "$no_linger_home" "$no_linger_tools"
make_fake_reasonix "$no_linger_bin"
cat > "$no_linger_tools/loginctl" <<'EOF'
#!/bin/sh
[ "$1" = "show-user" ] && echo no
exit 0
EOF
chmod +x "$no_linger_tools/loginctl"
if printf 'fixture-opencode-key\n' | HOME="$no_linger_home" PATH="$no_linger_tools:$PATH" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$no_linger_bin" \
    "$INSTALLER" --api-key-stdin >/dev/null 2>&1; then
    echo "Linux runtime started without user lingering authorization" >&2
    exit 1
fi

if [ -n "${VIBEDEVOPS_REASONIX_REAL_BIN:-}" ]; then
    real_home="$FIXTURE_ROOT/real-v1.21.5/home"
    mkdir -p "$real_home"
    printf 'fixture-opencode-key\n' | HOME="$real_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$VIBEDEVOPS_REASONIX_REAL_BIN" \
        "$INSTALLER" --api-key-stdin --no-start >/dev/null
    HOME="$real_home" REASONIX_HOME="$real_home/.reasonix" "$VIBEDEVOPS_REASONIX_REAL_BIN" doctor --json > "$real_home/doctor.json"
    node -e '
const report = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
if (report.version !== "v1.21.5") process.exit(1);
if (report.config.default_model !== "opencode-go/deepseek-v4-flash") process.exit(1);
const providers = report.providers.filter((provider) => provider.name === "opencode-go");
if (providers.length !== 1 || !providers[0].models.includes("deepseek-v4-flash")) process.exit(1);
' "$real_home/doctor.json"

    real_noncanonical_home="$FIXTURE_ROOT/real-noncanonical/home"
    mkdir -p "$real_noncanonical_home/.reasonix"
    cat > "$real_noncanonical_home/.reasonix/config.toml" <<'EOF'
config_version=5
"default_model"='opencode-go/deepseek-v4-flash'

[[providers]]
name='opencode-go'
kind='openai'
base_url='https://opencode.ai/zen/go/v1'
models=['deepseek-v4-flash']
default='deepseek-v4-flash'
api_key_env='OPENCODE_GO_API_KEY'
context_window=128000
EOF
    printf 'OPENCODE_GO_API_KEY=preserve-me\n' > "$real_noncanonical_home/.reasonix/.env"
    HOME="$real_noncanonical_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$VIBEDEVOPS_REASONIX_REAL_BIN" \
        "$INSTALLER" --no-start >/dev/null
    HOME="$real_noncanonical_home" REASONIX_HOME="$real_noncanonical_home/.reasonix" "$VIBEDEVOPS_REASONIX_REAL_BIN" doctor --json > "$real_noncanonical_home/doctor.json"
    node -e '
const report = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const providers = report.providers.filter((provider) => provider.name === "opencode-go");
if (providers.length !== 1 || providers[0].api_key_env !== "OPENCODE_GO_API_KEY") process.exit(1);
' "$real_noncanonical_home/doctor.json"
    HOME="$real_noncanonical_home" VIBEDEVOPS_REASONIX_OS=Linux VIBEDEVOPS_REASONIX_BIN="$VIBEDEVOPS_REASONIX_REAL_BIN" \
        "$HEALTH_CHECK" --offline >/dev/null
fi

echo "reasonix runtime fixtures passed"
