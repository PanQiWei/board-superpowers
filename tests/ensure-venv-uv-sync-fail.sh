#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPREPO="$(mktemp -d)"
trap 'rm -rf "${TMPREPO}"' EXIT
mkdir -p "${TMPREPO}/.board-superpowers"
export CLAUDE_PLUGIN_ROOT="${SCRIPT_DIR}"

# Inject a broken pyproject.toml (intentional syntax error) to make uv sync fail.
cp "${SCRIPT_DIR}/scripts/templates/pyproject.toml" "${TMPREPO}/.board-superpowers/pyproject.toml"
echo "this is not valid TOML !!!" >> "${TMPREPO}/.board-superpowers/pyproject.toml"

source "${SCRIPT_DIR}/scripts/lib/common.sh"
set +e
bsp_ensure_venv "${TMPREPO}"
rc=$?
set -e
[ ${rc} -eq 7 ] || { echo "FAIL: expected rc=7, got ${rc}"; exit 1; }
echo "PASS"
