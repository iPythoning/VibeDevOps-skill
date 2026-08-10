#!/bin/bash

set -e
umask 077

APPLY=0
ALL_PACKAGES=0
KEEP_COUNT=30
MIN_AGE_HOURS=6
OWNER="${GITHUB_REPOSITORY_OWNER:-}"
PACKAGE="${GITHUB_REPOSITORY#*/}"
PROTECTED_TAG_REGEX='^(latest|stable|production|prod|rollback|last-known-good|lkg)$'
PROTECTED_FILE=""
GH_BIN="${VIBEDEVOPS_GH_BIN:-gh}"
VERSIONS_FILE="${VIBEDEVOPS_GHCR_VERSIONS_FILE:-}"
MANIFESTS_FILE="${VIBEDEVOPS_GHCR_MANIFESTS_FILE:-}"
versions_json=""
manifests_json=""
candidates_tsv=""
auth_config=""
registry_config=""

fail() {
    echo "❌ $*" >&2
    exit 1
}

cleanup_temp() {
    [ -z "$versions_json" ] || rm -f "$versions_json"
    [ -z "$manifests_json" ] || rm -f "$manifests_json"
    [ -z "$candidates_tsv" ] || rm -f "$candidates_tsv"
    [ -z "$auth_config" ] || rm -f "$auth_config"
    [ -z "$registry_config" ] || rm -f "$registry_config"
}
trap cleanup_temp EXIT HUP INT TERM

usage() {
    cat <<'EOF'
Usage: cleanup-ghcr-versions.sh [options]

默认只预览；删除必须显式传 --apply。

Options:
  --owner OWNER           GitHub user/org；默认 GITHUB_REPOSITORY_OWNER 或当前用户
  --package NAME          Container package；默认当前仓库名
  --all-packages          清理当前用户的全部 container packages
  --keep-count N          每个 package 无条件保留最新 N 个版本（默认 30）
  --min-age-hours N       只处理至少 N 小时前的版本（默认 6）
  --protected-tags REGEX  永久保护命中任一 tag 的版本
  --protected-file PATH   每行一个需保护的 digest/version name
  --apply                 执行删除
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --owner) OWNER=$2; shift 2 ;;
        --package) PACKAGE=$2; shift 2 ;;
        --all-packages) ALL_PACKAGES=1; shift ;;
        --keep-count) KEEP_COUNT=$2; shift 2 ;;
        --min-age-hours) MIN_AGE_HOURS=$2; shift 2 ;;
        --protected-tags) PROTECTED_TAG_REGEX=$2; shift 2 ;;
        --protected-file) PROTECTED_FILE=$2; shift 2 ;;
        --apply) APPLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "未知参数: $1" ;;
    esac
done

case "$KEEP_COUNT" in ''|*[!0-9]*) fail "keep-count 必须是整数" ;; esac
case "$MIN_AGE_HOURS" in ''|*[!0-9]*) fail "min-age-hours 必须是整数" ;; esac
[ "$KEEP_COUNT" -ge 2 ] || fail "keep-count 至少为 2，必须保留当前与回滚余量"
[ "$MIN_AGE_HOURS" -ge 1 ] || fail "min-age-hours 至少为 1，避免删除仍在索引的构建"
[ -z "$PROTECTED_FILE" ] || [ -f "$PROTECTED_FILE" ] || fail "protected file 不存在: $PROTECTED_FILE"
command -v node >/dev/null 2>&1 || fail "需要 Node.js"
command -v "$GH_BIN" >/dev/null 2>&1 || fail "需要 gh CLI"
command -v curl >/dev/null 2>&1 || fail "需要 curl"

gh_api_retry() {
    local attempt=1
    while [ "$attempt" -le 4 ]; do
        if "$GH_BIN" api "$@"; then
            return 0
        fi
        [ "$attempt" -lt 4 ] || break
        sleep "$attempt"
        attempt=$((attempt + 1))
    done
    return 1
}

if [ -z "$OWNER" ]; then
    OWNER="$(gh_api_retry user --jq .login)"
fi
[ -n "$OWNER" ] || fail "无法确定 GitHub owner"

resolve_scope() {
    if [ "$ALL_PACKAGES" = "1" ] || [ "$OWNER" = "$(gh_api_retry user --jq .login 2>/dev/null || true)" ]; then
        echo user
    elif $GH_BIN api "orgs/$OWNER" >/dev/null 2>&1; then
        echo "orgs/$OWNER"
    else
        echo "users/$OWNER"
    fi
}

SCOPE="$(resolve_scope)"
if [ "$ALL_PACKAGES" = "1" ]; then
    [ "$SCOPE" = "user" ] || fail "--all-packages 仅允许清理当前认证用户，组织请逐 package 指定"
    PACKAGES="$(gh_api_retry --paginate --slurp '/user/packages?package_type=container&per_page=100' | node -e '
const pages = JSON.parse(require("fs").readFileSync(0, "utf8"));
for (const item of pages.flat()) process.stdout.write(item.name + "\n");
')"
else
    [ -n "$PACKAGE" ] || fail "缺少 --package"
    PACKAGES="$PACKAGE"
fi

delete_version() {
    local url=$1
    local attempt=1
    local output=""
    while [ "$attempt" -le 4 ]; do
        if output="$($GH_BIN api --method DELETE "$url" 2>&1)"; then
            return 0
        fi
        if printf '%s' "$output" | grep -Eq 'Package version not found|HTTP 404|"status"[[:space:]]*:[[:space:]]*"?404'; then
            return 2
        fi
        [ "$attempt" -lt 4 ] || break
        sleep "$attempt"
        attempt=$((attempt + 1))
    done
    printf '%s\n' "$output" >&2
    return 1
}

TOTAL_CANDIDATES=0
TOTAL_DELETED=0
TOTAL_CASCADED=0
while IFS= read -r package_name; do
    [ -n "$package_name" ] || continue
    encoded="$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$package_name")"
    if [ "$SCOPE" = "user" ]; then
        endpoint="/user/packages/container/$encoded/versions"
    else
        endpoint="/$SCOPE/packages/container/$encoded/versions"
    fi

    versions_json="$(mktemp)"
    manifests_json="$(mktemp)"
    candidates_tsv="$(mktemp)"
    if [ -n "$VERSIONS_FILE" ]; then
        cp "$VERSIONS_FILE" "$versions_json"
    else
        gh_api_retry --paginate --slurp "$endpoint?per_page=100" > "$versions_json"
    fi

    graph_complete=1
    if [ -n "$MANIFESTS_FILE" ]; then
        cp "$MANIFESTS_FILE" "$manifests_json"
    else
        auth_login="$(gh_api_retry user --jq .login 2>/dev/null || true)"
        github_token="$($GH_BIN auth token 2>/dev/null || true)"
        if [ -z "$auth_login" ] || [ -z "$github_token" ]; then
            graph_complete=0
        else
            auth_config="$(mktemp)"
            printf 'user = "%s:%s"\n' "$auth_login" "$github_token" > "$auth_config"
            registry_scope_owner="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
            registry_scope_package="$(printf '%s' "$package_name" | tr '[:upper:]' '[:lower:]')"
            token_response="$(curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
                --config "$auth_config" --get \
                --data-urlencode 'service=ghcr.io' \
                --data-urlencode "scope=repository:$registry_scope_owner/$registry_scope_package:pull" \
                'https://ghcr.io/token' 2>/dev/null || true)"
            rm -f "$auth_config"
            auth_config=""
            github_token=""
            registry_token="$(printf '%s' "$token_response" | node -e '
let data = "";
process.stdin.on("data", (chunk) => data += chunk);
process.stdin.on("end", () => {
  try {
    const parsed = JSON.parse(data);
    process.stdout.write(parsed.token || parsed.access_token || "");
  } catch (_) {}
});
')"
            token_response=""
            if [ -z "$registry_token" ]; then
                graph_complete=0
            else
                registry_config="$(mktemp)"
                {
                    printf 'header = "Authorization: Bearer %s"\n' "$registry_token"
                    printf 'header = "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json"\n'
                } > "$registry_config"
                registry_token=""
                registry_path="$(node -e 'process.stdout.write(process.argv[1].split("/").map(encodeURIComponent).join("/"))' "$registry_scope_owner/$registry_scope_package")"
                : > "$manifests_json"
                node -e '
const raw = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const versions = Array.isArray(raw[0]) ? raw.flat() : raw;
for (const digest of new Set(versions.map((version) => version.name))) {
  if (/^sha256:[0-9a-f]{64}$/.test(digest)) process.stdout.write(digest + "\n");
}
' "$versions_json" | while IFS= read -r digest; do
                    manifest_body="$(curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
                        --config "$registry_config" \
                        "https://ghcr.io/v2/$registry_path/manifests/$digest" 2>/dev/null || true)"
                    if [ -z "$manifest_body" ]; then
                        echo incomplete > "$manifests_json.incomplete"
                        break
                    fi
                    printf '%s' "$manifest_body" | node -e '
let body = "";
process.stdin.on("data", (chunk) => body += chunk);
process.stdin.on("end", () => {
  const manifest = JSON.parse(body);
  process.stdout.write(JSON.stringify({digest: process.argv[1], manifest}) + "\n");
});
' "$digest" >> "$manifests_json"
                done
                if [ -f "$manifests_json.incomplete" ]; then
                    graph_complete=0
                    rm -f "$manifests_json.incomplete"
                fi
                rm -f "$registry_config"
                registry_config=""
            fi
        fi
    fi
    node -e '
const fs = require("fs");
const raw = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const versions = Array.isArray(raw[0]) ? raw.flat() : raw;
const keep = Number(process.argv[2]);
const cutoff = Date.now() - Number(process.argv[3]) * 3600_000;
const protectedTags = new RegExp(process.argv[4]);
const protectedNames = new Set(process.argv[5] ? fs.readFileSync(process.argv[5], "utf8").split(/\r?\n/).filter(Boolean) : []);
const manifestText = fs.readFileSync(process.argv[6], "utf8").trim();
let manifestRecords = [];
if (manifestText) {
  try {
    const parsed = JSON.parse(manifestText);
    manifestRecords = Array.isArray(parsed) ? parsed : Object.entries(parsed).map(([digest, manifest]) => ({digest, manifest}));
  } catch (_) {
    manifestRecords = manifestText.split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
  }
}
const manifests = new Map(manifestRecords.map((record) => [record.digest, record.manifest]));
const graphComplete = process.argv[7] === "1" && versions.every((version) => manifests.has(version.name));
versions.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
const referrers = new Map();
for (const [digest, manifest] of manifests) {
  const subject = manifest?.subject?.digest;
  if (!subject) continue;
  if (!referrers.has(subject)) referrers.set(subject, []);
  referrers.get(subject).push(digest);
}
const protectedClosure = new Set();
for (const [index, version] of versions.entries()) {
  const tags = version.metadata?.container?.tags || [];
  if (index < keep || Date.parse(version.created_at) > cutoff || protectedNames.has(version.name) || tags.some((tag) => protectedTags.test(tag))) {
    protectedClosure.add(version.name);
  }
}
const queue = [...protectedClosure];
while (queue.length) {
  const digest = queue.shift();
  const manifest = manifests.get(digest);
  for (const descriptor of manifest?.manifests || []) {
    if (!descriptor.digest || protectedClosure.has(descriptor.digest)) continue;
    protectedClosure.add(descriptor.digest);
    queue.push(descriptor.digest);
  }
  for (const referrer of referrers.get(digest) || []) {
    if (protectedClosure.has(referrer)) continue;
    protectedClosure.add(referrer);
    queue.push(referrer);
  }
}
const candidates = [];
for (const [index, version] of versions.entries()) {
  const tags = version.metadata?.container?.tags || [];
  if (!graphComplete) continue;
  if (index < keep || Date.parse(version.created_at) > cutoff) continue;
  if (protectedNames.has(version.name) || tags.some((tag) => protectedTags.test(tag))) continue;
  if (protectedClosure.has(version.name)) continue;
  candidates.push({version, tags});
}
for (const {version, tags} of candidates) {
  process.stdout.write([version.id, version.name, version.created_at, tags.join(",")].join("\t") + "\n");
}
' "$versions_json" "$KEEP_COUNT" "$MIN_AGE_HOURS" "$PROTECTED_TAG_REGEX" "$PROTECTED_FILE" "$manifests_json" "$graph_complete" > "$candidates_tsv"

    version_count="$(node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(Array.isArray(v[0])?v.flat().length:v.length)' "$versions_json")"
    candidate_count="$(wc -l < "$candidates_tsv" | tr -d ' ')"
    TOTAL_CANDIDATES=$((TOTAL_CANDIDATES + candidate_count))
    echo "package=$package_name versions=$version_count candidates=$candidate_count keep=$KEEP_COUNT age=${MIN_AGE_HOURS}h graph_complete=$graph_complete"
    while IFS="$(printf '\t')" read -r version_id version_name created_at tags; do
        [ -n "$version_id" ] || continue
        if [ "$APPLY" = "1" ]; then
            set +e
            delete_version "$endpoint/$version_id"
            delete_status=$?
            set -e
            if [ "$delete_status" = "0" ]; then
                TOTAL_DELETED=$((TOTAL_DELETED + 1))
                echo "  deleted id=$version_id name=$version_name created=$created_at tags=${tags:--}"
            elif [ "$delete_status" = "2" ]; then
                TOTAL_CASCADED=$((TOTAL_CASCADED + 1))
                echo "  already-cascaded id=$version_id name=$version_name"
            else
                fail "删除 package=$package_name version=$version_id 失败"
            fi
        else
            echo "  would-delete id=$version_id name=$version_name created=$created_at tags=${tags:--}"
        fi
    done < "$candidates_tsv"
    rm -f "$versions_json" "$manifests_json" "$candidates_tsv"
    versions_json=""
    manifests_json=""
    candidates_tsv=""
done <<EOF
$PACKAGES
EOF

if [ "$APPLY" = "1" ]; then
    echo "✅ GHCR 清理完成：deleted=$TOTAL_DELETED already-cascaded=$TOTAL_CASCADED"
else
    echo "ℹ️  GHCR dry-run：candidates=${TOTAL_CANDIDATES}；确认后加 --apply"
fi
