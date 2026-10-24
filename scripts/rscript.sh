#!/bin/bash
set -euo pipefail
RDATACRAFT_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RDATACRAFT_R_FILE="$1"
shift
exec "$RDATACRAFT_SCRIPT_DIR/r.sh" --vanilla --slave --file="$RDATACRAFT_R_FILE" --args "$@"
