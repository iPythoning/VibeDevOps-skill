#!/bin/bash

set -e

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
INSTALLER="$ROOT/skills/vibedevops/templates/build-gate/install-github-runner.sh"
FIXTURE="$(mktemp -d)"
trap 'code=$?; [ "$code" -eq 0 ] || echo "build runner fixture failed near line $LINENO" >&2; rm -rf "$FIXTURE"' EXIT

TEST_HOME="$FIXTURE/home"
TOOLS="$FIXTURE/tools"
INSTALL_DIR="$TEST_HOME/.local/share/vibedevops-runners/ipythoning-fixture-xserver"
mkdir -p "$INSTALL_DIR" "$TOOLS"

cat > "$INSTALL_DIR/run.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$INSTALL_DIR/config.sh" <<'EOF'
#!/bin/sh
set -e
[ "$ACTIONS_RUNNER_INPUT_TOKEN" = "fixture-token" ]
printf '%s\n' "$@" > "$VIBEDEVOPS_RUNNER_ARGS_LOG"
url=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = "--url" ]; then url=$2; shift 2; else shift; fi
done
[ -n "$url" ]
printf '{"gitHubUrl":"%s"}\n' "$url" > .runner
EOF
chmod 700 "$INSTALL_DIR/run.sh" "$INSTALL_DIR/config.sh"

cat > "$TOOLS/docker" <<'EOF'
#!/bin/sh
[ "$1" = "info" ]
EOF
cat > "$TOOLS/loginctl" <<'EOF'
#!/bin/sh
echo yes
EOF
cat > "$TOOLS/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$VIBEDEVOPS_SYSTEMCTL_LOG"
EOF
chmod 700 "$TOOLS/docker" "$TOOLS/loginctl" "$TOOLS/systemctl"

: > "$FIXTURE/runner-args"
: > "$FIXTURE/systemctl-log"
printf 'fixture-token\n' | env \
    HOME="$TEST_HOME" USER=fixture PATH="$TOOLS:/usr/bin:/bin" \
    VIBEDEVOPS_RUNNER_OS=Linux VIBEDEVOPS_RUNNER_ARCH=x86_64 \
    VIBEDEVOPS_RUNNER_ARGS_LOG="$FIXTURE/runner-args" \
    VIBEDEVOPS_SYSTEMCTL_LOG="$FIXTURE/systemctl-log" \
    "$INSTALLER" --repo iPythoning/fixture --role xserver --name fixture-runner --token-stdin >/dev/null

UNIT="$TEST_HOME/.config/systemd/user/vibedevops-runner-ipythoning-fixture-xserver.service"
WRAPPER="$TEST_HOME/.local/bin/vibedevops-runner-ipythoning-fixture-xserver"
[ -f "$UNIT" ] && [ -x "$WRAPPER" ]
! grep -q -- '--token\|fixture-token' "$FIXTURE/runner-args" "$UNIT" "$WRAPPER"
grep -q 'exec env -i' "$WRAPPER"
grep -q '^ExecStart="' "$UNIT"
! grep -q '^KillMode=' "$UNIT"
grep -q 'enable vibedevops-runner-ipythoning-fixture-xserver.service' "$FIXTURE/systemctl-log"
grep -q 'restart vibedevops-runner-ipythoning-fixture-xserver.service' "$FIXTURE/systemctl-log"

if [ "$(uname -s)" = "Darwin" ]; then
    [ "$(stat -f '%Lp' "$INSTALL_DIR")" = "700" ]
else
    [ "$(stat -c '%a' "$INSTALL_DIR")" = "700" ]
fi

env HOME="$TEST_HOME" USER=fixture PATH="$TOOLS:/usr/bin:/bin" \
    VIBEDEVOPS_RUNNER_OS=Linux VIBEDEVOPS_RUNNER_ARCH=x86_64 \
    VIBEDEVOPS_RUNNER_ARGS_LOG="$FIXTURE/runner-args" \
    VIBEDEVOPS_SYSTEMCTL_LOG="$FIXTURE/systemctl-log" \
    "$INSTALLER" --repo iPythoning/fixture --role xserver --name fixture-runner >/dev/null

printf '{"gitHubUrl":"https://github.com/iPythoning/fixture-old"}\n' > "$INSTALL_DIR/.runner"
if env HOME="$TEST_HOME" USER=fixture PATH="$TOOLS:/usr/bin:/bin" \
    VIBEDEVOPS_RUNNER_OS=Linux VIBEDEVOPS_RUNNER_ARCH=x86_64 \
    "$INSTALLER" --repo iPythoning/fixture --role xserver --name fixture-runner >/dev/null 2>&1; then
    echo "installer accepted an existing runner bound to another repository" >&2
    exit 1
fi

echo "build runner fixtures passed"
