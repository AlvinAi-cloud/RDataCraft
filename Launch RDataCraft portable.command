#!/bin/bash
set -euo pipefail
RDATACRAFT_PORTABLE_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$RDATACRAFT_PORTABLE_ROOT"
export RDATACRAFT_PORTABLE=1
exec ./scripts/rscript.sh scripts/portable.R "$@"
