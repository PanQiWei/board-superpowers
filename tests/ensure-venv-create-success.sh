#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPREPO="$(mktemp -d)"
trap 'rm -rf "${TMPREPO}"' EXIT
mkdir -p "${TMPREPO}/.board-superpowers"

# Verify uv is available; otherwise skip.
command -v uv >/dev/null || { echo "SKIP: uv not on PATH"; exit 0; }

# Mock CLAUDE_PLUGIN_ROOT to the repo root so template is found.
export CLAUDE_PLUGIN_ROOT="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/scripts/lib/common.sh"
out="$(bsp_ensure_venv "${TMPREPO}")"
[ -x "${out}" ] || { echo "FAIL: venv-python not executable: ${out}"; exit 1; }
[ -f "${TMPREPO}/.board-superpowers/pyproject.toml" ] || { echo "FAIL: pyproject not copied"; exit 1; }
echo "PASS"
