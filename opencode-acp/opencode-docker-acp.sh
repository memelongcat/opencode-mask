#!/usr/bin/env bash
set -euo pipefail

OPENCODE_IMAGE="opencode-mask:1.19.5"
ENV_FILE="/opt/opencode/opencode-acp/.acp.env"
PERSISTANCE_VOLUME="opencode_opencode"

exec docker run --rm -i \
  --cap-add SYS_ADMIN \
  --mount "type=volume,source=${PERSISTANCE_VOLUME},target=/root/.local/share/opencode" \
  --volume "$PWD:$PWD" \
  --workdir "$PWD" \
  --env-file "$ENV_FILE" \
  "$OPENCODE_IMAGE" \
  --print-logs acp
