#!/bin/bash
set -euo pipefail
RDATACRAFT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RDATACRAFT_RUNTIME_ROOT="${RDATACRAFT_RUNTIME:-$RDATACRAFT_ROOT/runtime}"
export R_USER_CACHE_DIR="${TMPDIR:-/tmp}/RDataCraft/cache"
export XDG_CACHE_HOME="${TMPDIR:-/tmp}/RDataCraft/cache"
export FONTCONFIG_FILE="$RDATACRAFT_ROOT/config/fonts.conf"
if [[ -d "$RDATACRAFT_RUNTIME_ROOT/R.framework/Resources" ]]; then
  export R_HOME="$RDATACRAFT_RUNTIME_ROOT/R.framework/Resources"
  export R_SHARE_DIR="$R_HOME/share"
  export R_INCLUDE_DIR="$R_HOME/include"
  export R_DOC_DIR="$R_HOME/doc"
  export DYLD_LIBRARY_PATH="$R_HOME/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  export R_LIBS_USER="$RDATACRAFT_RUNTIME_ROOT/library"
  exec "$R_HOME/bin/exec/R" "$@"
elif command -v R >/dev/null 2>&1; then
  export R_LIBS_USER="$RDATACRAFT_RUNTIME_ROOT/library"
  exec R "$@"
else
  printf 'RDataCraft needs its bundled R runtime. Run python3 scripts/bootstrap.py first.\n' >&2
  exit 1
fi
