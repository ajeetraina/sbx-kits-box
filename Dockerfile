# Local-only image carrying the private Box agent-mount client.
#
# The agent-mount binary (~34 MB) can't ship in the kit's files/ (4 MB injection
# limit), so it is baked into an image built FROM the stock shell sandbox
# template. The binary's architecture MUST match the sbx runtime (arm64 on Apple
# Silicon); a mismatched binary will not exec inside the sandbox.
#
# Build + load via: ./scripts/build-and-load.sh
# Or manually:
#   docker build --platform linux/amd64 -t sbx-box-agentmount:local .
#   docker save sbx-box-agentmount:local -o /tmp/img.tar && sbx template load /tmp/img.tar
#
# Then run the sandbox with this image + the mixin kit:
#   sbx run shell --template sbx-box-agentmount:local --kit ./ .

ARG BASE=docker/sandbox-templates:shell-docker
FROM ${BASE}

# The private Box client. Build context is the repo root. The template runs as a
# non-root user, so set ownership/mode at copy time rather than with RUN chmod.
ARG BIN=agentmount/linux/agent-mount
COPY --chown=root:root --chmod=0755 ${BIN} /usr/local/bin/agent-mount
