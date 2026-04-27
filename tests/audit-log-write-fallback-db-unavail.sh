#!/usr/bin/env bash
# Test: audit_db_url points at unreachable DB → jsonl fallback with
# mode=degraded-db-unavailable.
#
# Isolation: uses TMPHOME + TMPREPO (both cleaned by trap on EXIT).
# TMPHOME stands in for $HOME so no real ~/.board-superpowers/ is touched.
# The venv is created inside TMPREPO/.board-superpowers/.venv — also cleaned.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPHOME="$(mktemp -d)"
TMPREPO="$(mktemp -d)"
trap 'rm -rf "${TMPHOME}" "${TMPREPO}"' EXIT

mkdir -p "${TMPREPO}/.board-superpowers"
git -C "${TMPREPO}" init -q

export CLAUDE_PLUGIN_ROOT="${SCRIPT_DIR}"
# Point at a nonexistent sqlite path whose parent directory doesn't exist,
# so sqlite3.connect() fails → INSERT_RC != 0 → degraded-db-unavailable.
export BOARD_SP_AUDIT_DB_URL="sqlite:////nonexistent/dir/audit.db"

# Pre-create venv via uv sync to avoid degraded-uv-missing path.
command -v uv >/dev/null || { echo "SKIP: uv not on PATH"; exit 0; }
cp "${SCRIPT_DIR}/scripts/templates/pyproject.toml" "${TMPREPO}/.board-superpowers/"
cp "${SCRIPT_DIR}/scripts/templates/uv.lock" "${TMPREPO}/.board-superpowers/" 2>/dev/null || true
(cd "${TMPREPO}/.board-superpowers" && uv sync --quiet 2>&1) >/dev/null

# Run audit-log-write.sh with HOME=TMPHOME so bsp_audit_local_write writes
# to TMPHOME/.board-superpowers/repos/... instead of real $HOME.
OUT="$(HOME="${TMPHOME}" bash "${SCRIPT_DIR}/scripts/audit-log-write.sh" \
    --action-id 100 --decision A --skill consuming-card \
    --approval-stage auto --outcome success --payload '{"k":"v"}' \
    --repo-root "${TMPREPO}" 2>&1)"

echo "${OUT}" | grep -q 'mode=degraded-db-unavailable' || {
    echo "FAIL: expected 'mode=degraded-db-unavailable' WARN in output"
    echo "--- captured output ---"
    echo "${OUT}"
    exit 1
}

# Verify jsonl entry was written under TMPHOME (not real $HOME).
# Mirror bsp_normalize_repo_path: strip leading /, replace / with -.
NORMALIZED="${TMPREPO#/}"
NORMALIZED="${NORMALIZED%/}"
NORMALIZED="${NORMALIZED//\//-}"
JSONL="${TMPHOME}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

[ -f "${JSONL}" ] || {
    echo "FAIL: jsonl not found at ${JSONL}"
    exit 1
}
grep -q 'degraded-db-unavailable' "${JSONL}" || {
    echo "FAIL: jsonl does not contain 'degraded-db-unavailable'"
    echo "--- jsonl content ---"
    cat "${JSONL}"
    exit 1
}

echo "PASS"
