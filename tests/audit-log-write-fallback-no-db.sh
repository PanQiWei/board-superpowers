#!/usr/bin/env bash
# Test: audit_db_url unset → jsonl fallback with mode=no-db.
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
# Ensure no DB URL from either env or credentials file (TMPHOME has none).
unset BOARD_SP_AUDIT_DB_URL 2>/dev/null || true

# Pre-create venv via uv sync to avoid degraded-uv-missing path.
command -v uv >/dev/null || { echo "SKIP: uv not on PATH"; exit 0; }
cp "${SCRIPT_DIR}/scripts/templates/pyproject.toml" "${TMPREPO}/.board-superpowers/"
cp "${SCRIPT_DIR}/scripts/templates/uv.lock" "${TMPREPO}/.board-superpowers/" 2>/dev/null || true
(cd "${TMPREPO}/.board-superpowers" && uv sync --quiet 2>&1) >/dev/null

# Run audit-log-write.sh with HOME=TMPHOME so bsp_resolve_audit_db_url reads
# TMPHOME/.board-superpowers/credentials.yml (absent) → empty → no-db path.
# Capture stderr+stdout combined; the WARN line contains "mode=no-db".
OUT="$(HOME="${TMPHOME}" bash "${SCRIPT_DIR}/scripts/audit-log-write.sh" \
    --action-id 100 --decision A --skill consuming-card \
    --approval-stage auto --outcome success --payload '{"k":"v"}' \
    --repo-root "${TMPREPO}" 2>&1)"

echo "${OUT}" | grep -q 'mode=no-db' || {
    echo "FAIL: expected 'mode=no-db' WARN in output"
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
grep -q 'no-db' "${JSONL}" || {
    echo "FAIL: jsonl does not contain 'no-db'"
    echo "--- jsonl content ---"
    cat "${JSONL}"
    exit 1
}

echo "PASS"
