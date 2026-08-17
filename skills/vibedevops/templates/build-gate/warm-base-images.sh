#!/usr/bin/env bash
# warm-base-images.sh — pre-bake base/CI images on a build host so cross-border
# `FROM` pulls hit the local daemon instead of the upstream registry.
#
# What it does: pulls each image in the list through a registry mirror
# (REGISTRY_MIRROR, e.g. a China-region pass-through), then re-tags it to its
# canonical name (`python:3.12-slim`, `postgres:16`, ...). With the build driver
# set to the local daemon (see below), every `FROM canonical-name` in your
# Dockerfiles resolves against these warmed local images — zero re-pull, zero
# cross-border build traffic.
#
# Pairs with: CD_BUILDX_DRIVER=docker (daemon direct build, layer cache is
# persistent) vs. the buildx default `docker-container` driver (isolated cache
# that does NOT see the daemon's local image store, so warmed images don't help).
# Trade-off:
#   - driver=docker  → FROM hits these warmed local images; layer cache lives in
#     the daemon and survives across builds. Best when the build host is
#     long-lived and you control it.
#   - driver=docker-container → reproducible, isolated, supports advanced cache
#     export; but a fresh container won't see the local store, so warming is moot
#     unless you also wire up a registry/inline cache.
# Choose driver=docker on a dedicated build host to make this script pay off.
#
# Cache policy: on a build host with spare disk, do NOT prune the docker build
# cache or these warmed images. Any GC/cleanup job must exclude this host's build
# cache and the images in the list below — re-pulling them is the exact
# cross-border cost this script exists to avoid. Prune only if disk pressure is real.
#
# ---------------------------------------------------------------------------
# Placeholders to set for your environment:
#   REGISTRY_MIRROR  registry mirror host, no scheme (default: a China-region
#                    mirror; swap for your own or set to "" to pull upstream).
#   WARM_LOG         log file path (default: ./warm-base-images.log).
#   IMAGES           the canonical image list — edit to match what your repos
#                    actually `FROM`. Discover it with:
#                      grep -rhiE '^FROM ' --include=Dockerfile . \
#                        | awk '{print $2}' | grep -v '^scratch$' | sort -u
# Run on a schedule (e.g. weekly cron) to keep tags fresh.
# bash 3.2 compatible (works with macOS's stock bash); set -u.
# ---------------------------------------------------------------------------
set -u

REGISTRY_MIRROR="${REGISTRY_MIRROR:-docker.m.daocloud.io}"
WARM_LOG="${WARM_LOG:-./warm-base-images.log}"

# Canonical image names. Official (Docker Hub `library/`) images are written
# WITHOUT the `library/` prefix; non-official images keep their `org/` prefix.
# Edit this list per your fleet; the examples below are common defaults.
IMAGES="${IMAGES:-
python:3.12-slim
python:3.13-slim
node:20-alpine
node:22-alpine
nginx:alpine
redis:7-alpine
postgres:16-alpine
postgres:17-alpine
pgvector/pgvector:pg16
}"

log() { echo "[$(date '+%F %T')] $*" | tee -a "${WARM_LOG}"; }

ok=0; fail=0
for img in ${IMAGES}; do
  if [ -n "${REGISTRY_MIRROR}" ]; then
    case "${img}" in
      */*) src="${REGISTRY_MIRROR}/${img}" ;;      # non-official: org/name kept as-is
      *)   src="${REGISTRY_MIRROR}/library/${img}" ;;  # official: mirror needs library/ prefix
    esac
  else
    src="${img}"                                    # no mirror: pull upstream directly
  fi

  if docker pull --quiet "${src}" >>"${WARM_LOG}" 2>&1; then
    docker tag "${src}" "${img}"                    # retag to canonical so FROM matches
    ok=$((ok+1)); log "WARM ${img} <- ${src}"
  else
    # Keep the existing local copy on failure — a stale warm image still builds.
    fail=$((fail+1)); log "FAIL ${img} (pull via ${REGISTRY_MIRROR:-upstream} failed; kept local copy)"
  fi
done
log "done: warmed=${ok} failed=${fail} (failures fall back to existing local images)"
