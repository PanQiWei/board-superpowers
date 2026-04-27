#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPREPO="$(mktemp -d)"
mkdir -p "${TMPREPO}/.board-superpowers"

# Mock CLAUDE_PLUGIN_ROOT to a directory without templates/.
TMPPLUGIN="$(mktemp -d)"
export CLAUDE_PLUGIN_ROOT="${TMPPLUGIN}"

source "${SCRIPT_DIR}/scripts/lib/common.sh"
set +e
bsp_ensure_venv "${TMPREPO}"
rc=$?
set -e
[ ${rc} -eq 6 ] || { echo "FAIL: expected rc=6, got ${rc}"; exit 1; }
echo "PASS"
