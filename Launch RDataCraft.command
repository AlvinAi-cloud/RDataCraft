#!/bin/bash
set -euo pipefail
RDATACRAFT_ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ "$(uname -m)" == "arm64" ]]; then
  RDATACRAFT_CANDIDATES=("RDataCraft 0.3 Apple Silicon.app")
else
  RDATACRAFT_CANDIDATES=("RDataCraft 0.3 Intel.app")
fi
RDATACRAFT_CANDIDATES+=("RDataCraft v0.31.app")
for RDATACRAFT_NAME in "${RDATACRAFT_CANDIDATES[@]}"; do
  RDATACRAFT_APP="$RDATACRAFT_ROOT/dist/$RDATACRAFT_NAME"
  if [[ -d "$RDATACRAFT_APP" ]]; then
    exec /usr/bin/open "$RDATACRAFT_APP" "$@"
  fi
done
printf 'Extract the matching Mac ZIP in dist/ or build the native app as described in PLATFORM_SUPPORT.md.\n' >&2
exit 1
