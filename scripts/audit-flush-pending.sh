#!/usr/bin/env bash
# scripts/audit-flush-pending.sh — outbox flush worker.
#
# Scans all per-repo audit-local.jsonl files, transitions status:pending
# rows -> DB INSERT (idempotent via event_uuid UNIQUE) -> status:processed.
# Preserves rows (no deletion) per audit-log retroactive-record contract.
#
# Failure modes:
#   retry_count incremented per failed row; >=5 -> mode=audit-dead-letter
#   pending_since > 24h ago -> mode=audit-dead-letter (TTL)
#
# Per Task 6a: single-process correctness + cross-driver dispatch.
#   flock concurrency mutex is Task 6b's territory.
#
# Exit codes:
#   0 - flush complete (or no pending rows)
#   1 - corrupt jsonl rows detected (transitioned to audit-dead-letter)
#   2 - partial INSERT failure (rows kept pending or sent to dead-letter)
#   3 - audit_db_url not configured (no target DB)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

QUIET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet) QUIET=1; shift ;;
        *) shift ;;
    esac
done

# Find venv-python (use current PWD's repo to locate venv)
REPO_ROOT="$(bsp_primary_repo_root "${PWD}" 2>/dev/null || echo "${PWD}")"
VENV_PYTHON="$(bsp_ensure_venv "${REPO_ROOT}" 2>/dev/null || echo "")"
if [ -z "${VENV_PYTHON}" ]; then
    [ "${QUIET}" = 1 ] || bsp_warn "audit-flush-pending: venv unavailable; cannot flush"
    exit 2
fi

# Scan all per-repo jsonl
EXIT_CODE=0
HAS_PENDING_ANY=0
# Match both `"status": "pending"` (Python json.dumps default) and
# `"status":"pending"` (compact form) — the worker treats them as
# equivalent per the SoT json schema (whitespace not load-bearing).
PENDING_PATTERN='"status"[[:space:]]*:[[:space:]]*"pending"'

for jsonl in "${HOME}/.board-superpowers/repos/"*"/audit-local.jsonl"; do
    [ -f "${jsonl}" ] || continue
    # Quick check before invoking Python
    grep -qE "${PENDING_PATTERN}" "${jsonl}" 2>/dev/null || continue
    HAS_PENDING_ANY=1

    rc=0
    BSP_JSONL="${jsonl}" "${VENV_PYTHON}" "${SCRIPT_DIR}/audit-flush-impl.py" || rc=$?
    case "${rc}" in
        0) ;;
        1) [ "${EXIT_CODE}" -lt 1 ] && EXIT_CODE=1 ;;
        2) [ "${EXIT_CODE}" -lt 2 ] && EXIT_CODE=2 ;;
        *) EXIT_CODE=2 ;;
    esac
done

# Sentinel cleanup if no pending remains across ALL jsonl
SENTINEL="${HOME}/.board-superpowers/audit-pending.sentinel"
if [ -f "${SENTINEL}" ]; then
    REMAINING=0
    for jsonl in "${HOME}/.board-superpowers/repos/"*"/audit-local.jsonl"; do
        [ -f "${jsonl}" ] || continue
        if grep -qE "${PENDING_PATTERN}" "${jsonl}" 2>/dev/null; then
            REMAINING=1
            break
        fi
    done
    [ "${REMAINING}" = 0 ] && rm -f "${SENTINEL}"
fi

# Reference unused variable so shellcheck does not complain about
# HAS_PENDING_ANY (kept for future telemetry / Task 6b lock-skip logic).
: "${HAS_PENDING_ANY}"

exit "${EXIT_CODE}"
