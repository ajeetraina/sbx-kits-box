# Image carrying the private Box Mount client, built for amd64 and/or arm64.
#
# The box-mount binary (~20-34 MB) can't ship in the kit's files/ (4 MB injection
# limit), so it is baked into an image built FROM the stock shell sandbox template.
# The sbx runtime does NOT emulate, so the image arch must match the host it runs
# on. This Dockerfile is arch-agnostic: `buildx` sets TARGETARCH (amd64|arm64) per
# platform, so a single `--platform linux/amd64,linux/arm64` build bakes the right
# binary into each arch. `scripts/build-and-load.sh` drives that and loads the
# result into the sbx runtime; `scripts/push-to-dockerhub.sh` publishes it.
#
# Stage the private binaries first (git-ignored, obtain from Box):
#   box-mount/linux/amd64/box-mount   (linux/amd64)
#   box-mount/linux/arm64/box-mount   (linux/arm64)

ARG BASE=docker/sandbox-templates:shell-docker
FROM ${BASE}

# TARGETARCH is amd64 or arm64 (set automatically per platform by buildx). Selecting
# the binary by ${TARGETARCH} lets one build serve both arches.
#
# v0.4.0 note: the `mount` command self-invokes a helper executable named
# `box-mount` on PATH (the sync engine), so the binary MUST be installed under that
# name or `mount` fails with FileNotFoundError: 'box-mount'. We also install an
# `agent-mount` alias so the older CLI surface keeps working. COPY (not a RUN
# symlink) sets ownership/mode at copy time because the template's non-root user
# can't write /usr/local/bin at RUN time.
ARG TARGETARCH
COPY --chown=root:root --chmod=0755 box-mount/linux/${TARGETARCH}/box-mount /usr/local/bin/box-mount
COPY --chown=root:root --chmod=0755 box-mount/linux/${TARGETARCH}/box-mount /usr/local/bin/agent-mount
