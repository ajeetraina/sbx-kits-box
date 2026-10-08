#!/usr/bin/env bash
# Build the local-only Box Mount image and load it into the sbx runtime.
#
# The private box-mount binary is too big for kit files/ (4 MB injection limit),
# so it is baked into an image built FROM the stock shell template, then loaded
# into sbx's own image store with `sbx template load`. Nothing is pushed anywhere.
#
# ARCHITECTURE — works for both amd64 and arm64. The sbx runtime does NOT emulate,
# so the image arch must match the host it runs on. This script builds EVERY arch
# whose binary you have staged (see below) into ONE multi-arch image, so the loaded
# template — and the saved tar — run on both Apple Silicon (arm64) and Intel/amd64.
# Build once, and the same artifact works everywhere it is loaded.
#
# Stage the private binaries first (git-ignored, obtain from Box):
#   box-mount/linux/amd64/box-mount   (linux/amd64)
#   box-mount/linux/arm64/box-mount   (linux/arm64)
# Staging only one arch is fine — the image is then single-arch for that host.
set -euo pipefail

IMAGE="${IMAGE:-sbx-box:local}"
BASE="${BASE:-docker/sandbox-templates:shell-docker}"
TAR="${TAR:-/tmp/${IMAGE//[:\/]/_}.tar}"
BUILDER="${BUILDER:-sbx-box-builder}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# Detect which arches have a staged binary. TARGETARCH values: amd64 | arm64.
platforms=()
[ -f box-mount/linux/amd64/box-mount ] && platforms+=("linux/amd64")
[ -f box-mount/linux/arm64/box-mount ] && platforms+=("linux/arm64")
if [ "${#platforms[@]}" -eq 0 ]; then
  echo "ERROR: no box-mount binary staged." >&2
  echo "       Obtain the Box binaries and stage them (git-ignored) at:" >&2
  echo "         box-mount/linux/amd64/box-mount   (linux/amd64)" >&2
  echo "         box-mount/linux/arm64/box-mount   (linux/arm64)" >&2
  exit 1
fi

# Warn if THIS host's arch isn't among them — the image won't run here (no emulation).
case "$(uname -m)" in
  x86_64|amd64)  host_plat="linux/amd64" ;;
  arm64|aarch64) host_plat="linux/arm64" ;;
  *)             host_plat="" ;;
esac
if [ -n "$host_plat" ] && [[ " ${platforms[*]} " != *" $host_plat "* ]]; then
  echo "!! WARNING: no $host_plat binary staged; the image won't run on THIS host." >&2
  echo "!!          Stage box-mount/${host_plat}/box-mount to run it here." >&2
fi

plat_csv="$(IFS=,; echo "${platforms[*]}")"
echo ">> building $IMAGE for: $plat_csv"

# buildx drives the multi-arch build; TARGETARCH in the Dockerfile picks the binary.
docker buildx version >/dev/null 2>&1 || {
  echo "ERROR: 'docker buildx' is required (bundled with modern Docker)." >&2; exit 1;
}
# A container-driver builder can emit a multi-platform image; create one if needed.
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  echo ">> creating buildx builder '$BUILDER'"
  docker buildx create --name "$BUILDER" --driver docker-container >/dev/null
fi

# Export an OCI archive (carries all built arches) and load it straight into sbx.
docker buildx --builder "$BUILDER" build \
  --platform "$plat_csv" \
  --provenance=false \
  --build-arg BASE="$BASE" \
  -t "$IMAGE" \
  --output "type=oci,dest=$TAR" .

echo ">> loading into the sbx runtime"
sbx template load "$TAR"
rm -f "$TAR"

echo ">> done. Loaded template:"
sbx template ls | grep -i "${IMAGE%%:*}" || true
cat <<EOF

Next:
  echo "<your-box-developer-or-oauth-token>" | sbx secret set box
  sbx run shell --template $IMAGE --kit ./ .
  # inside the sandbox (box-mount; agent-mount is an alias):
  #   box-mount --version
  #   box-mount mount "/home/agent/workspace/box" "<box-folder-id>"   # root = 0
  #   box-mount status
EOF
