#!/usr/bin/env bash
# Build the Box Mount image and push it to Docker Hub as a MULTI-ARCH image.
#
# Unlike scripts/build-and-load.sh (which loads the image into the local sbx
# runtime and pushes nothing), this publishes a multi-arch manifest to Docker Hub
# so users on either Apple Silicon (arm64) or Intel/amd64 pull the binary matching
# their sbx runtime automatically.
#
# The private box-mount binaries are baked in per platform via the TARGETARCH-aware
# Dockerfile. Stage them (git-ignored, obtain from Box) at:
#   box-mount/linux/amd64/box-mount   (linux/amd64)
#   box-mount/linux/arm64/box-mount   (linux/arm64)
# Only the platforms whose binary is present get built; missing ones are skipped.
#
# Auth: pass Docker Hub creds via env for non-interactive login, e.g.
#   export DOCKERHUB_USERNAME=<your-hub-user>
#   export DOCKERHUB_TOKEN=<access-token>      # a Hub access token, NOT your password
# If those are unset the script assumes you are already logged in (docker login).
#
# The target namespace is NOT hard-coded: pass it as the first argument or via
# NAMESPACE=. Use whichever Docker Hub org you own (e.g. `box`).
#
# Usage:
#   ./scripts/push-to-dockerhub.sh box                    # push box/sbx-box :v0.4.0 + :latest
#   NAMESPACE=box ./scripts/push-to-dockerhub.sh          # same, via env
#   VERSION=v0.4.1 ./scripts/push-to-dockerhub.sh box     # override the version tag
#   PLATFORMS=linux/arm64 ./scripts/push-to-dockerhub.sh box   # single-arch push
set -euo pipefail

# Namespace comes from $1 or NAMESPACE= (no default — this script is not tied to
# any one Docker Hub account).
NAMESPACE="${1:-${NAMESPACE:-}}"
if [ -z "$NAMESPACE" ]; then
  echo "ERROR: no Docker Hub namespace given." >&2
  echo "       Usage: $0 <namespace>   (or NAMESPACE=<namespace> $0)" >&2
  echo "       e.g.:  $0 box" >&2
  exit 1
fi
IMAGE_NAME="${IMAGE_NAME:-sbx-box}"
REPO="${REPO:-${NAMESPACE}/${IMAGE_NAME}}"
VERSION="${VERSION:-v0.4.0}"
BASE="${BASE:-docker/sandbox-templates:shell-docker}"
BUILDER="${BUILDER:-sbx-box-builder}"
# Space-separated list of platforms to publish. Only those with a matching binary
# on disk are actually built.
PLATFORMS="${PLATFORMS:-linux/arm64 linux/amd64}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# Map a docker platform -> the private binary that must be staged for it.
bin_for_platform() {
  case "$1" in
    linux/amd64) echo "box-mount/linux/amd64/box-mount" ;;
    linux/arm64) echo "box-mount/linux/arm64/box-mount" ;;
    *) echo "" ;;
  esac
}

command -v docker >/dev/null || { echo "ERROR: docker not found on PATH" >&2; exit 1; }
docker buildx version >/dev/null 2>&1 || {
  echo "ERROR: 'docker buildx' is required for the multi-arch push." >&2
  echo "       Install/enable buildx, then re-run." >&2
  exit 1
}

# Keep only platforms whose binary is actually staged.
build_platforms=()
for plat in $PLATFORMS; do
  bin="$(bin_for_platform "$plat")"
  if [ -z "$bin" ]; then
    echo "!! WARNING: no binary mapping for platform '$plat'; skipping" >&2
    continue
  fi
  if [ ! -f "$bin" ]; then
    echo "!! WARNING: binary for $plat not staged ($bin); skipping this platform" >&2
    continue
  fi
  build_platforms+=("$plat")
done
[ "${#build_platforms[@]}" -gt 0 ] || { echo "ERROR: no platforms staged; nothing to push." >&2; exit 1; }

# Non-interactive login if creds were provided; otherwise trust an existing session.
if [ -n "${DOCKERHUB_TOKEN:-}" ]; then
  echo ">> logging in to Docker Hub as ${DOCKERHUB_USERNAME:-$NAMESPACE}"
  echo "$DOCKERHUB_TOKEN" | docker login -u "${DOCKERHUB_USERNAME:-$NAMESPACE}" --password-stdin
else
  echo ">> DOCKERHUB_TOKEN not set; assuming an existing 'docker login' session"
fi

# Ensure a buildx builder that can drive multi-platform builds exists.
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  echo ">> creating buildx builder '$BUILDER'"
  docker buildx create --name "$BUILDER" --driver docker-container >/dev/null
fi

plat_csv="$(IFS=,; echo "${build_platforms[*]}")"
echo ">> building + pushing $REPO ($plat_csv) as :$VERSION and :latest"
# One multi-arch build+push; the TARGETARCH Dockerfile bakes the right binary per arch.
docker buildx --builder "$BUILDER" build \
  --platform "$plat_csv" \
  --provenance=false \
  --build-arg BASE="$BASE" \
  -t "${REPO}:${VERSION}" \
  -t "${REPO}:latest" \
  --push .

echo ">> done. Published:"
echo "     ${REPO}:${VERSION}"
echo "     ${REPO}:latest"
cat <<EOF

Pull + run from Docker Hub (any arch — the manifest selects the match):
  docker pull ${REPO}:${VERSION}
  docker save ${REPO}:${VERSION} -o /tmp/sbx-box.tar && sbx template load /tmp/sbx-box.tar
  sbx run shell --template ${REPO}:${VERSION} --kit ./ .
EOF
