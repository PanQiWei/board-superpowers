#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPREPO="$(mktemp -d)"
mkdir -p "${TMPREPO}/.board-superpowers"

# Strip uv from PATH. Cover common install locations:
#   /opt/homebrew/bin (brew), ~/.local/bin (curl installer), astral paths.
PATH_NO_UV="$(echo "${PATH}" | tr ':' '\n' | grep -v '/uv$' | grep -vE '/(homebrew|astral|\.local/bin)' | tr '\n' ':')"

env PATH="${PATH_NO_UV}" bash -c "
    set -uo pipefail
    source ${SCRIPT_DIR}/scripts/lib/common.sh
    bsp_ensure_venv ${TMPREPO}
    rc=\$?
    [ \$rc -eq 5 ] || { echo 'FAIL: expected rc=5, got '\$rc; exit 1; }
    echo PASS
"
