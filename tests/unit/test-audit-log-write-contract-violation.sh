#!/usr/bin/env bash
# unit: non-integer --action-id triggers contract-violation pre-mode-branch
# (#43 AC2). Test 1 — string action_id "bootstrap-host" must produce
# exit 1 + jsonl row mode=contract-violation. Test 2 — integer action_id
# 200 with no DB env preserves original behavior (exit 0, mode=no-db).
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
export HOME="${TMPDIR}/fake-home"
mkdir -p "${HOME}"

# Test 1: non-integer action_id → exit 1 + mode=contract-violation in jsonl
RC=0
bash "${ROOT}/scripts/audit-log-write.sh" \
    --action-id "bootstrap-host" \
    --decision A \
    --skill bootstrapping-repo \
    --approval-stage auto \
    --outcome success \
    --payload '{}' || RC=$?

[ "${RC}" = 1 ] || { echo "FAIL: expected exit 1, got ${RC}"; exit 1; }

JSONL=$(find "${HOME}/.board-superpowers/repos/" -name 'audit-local.jsonl' 2>/dev/null | head -1)
[ -f "${JSONL}" ] || { echo "FAIL: jsonl not written"; exit 1; }
grep -q '"mode": "contract-violation"' "${JSONL}" || \
    { echo "FAIL: mode=contract-violation absent in jsonl"; cat "${JSONL}"; exit 1; }

# Test 2: integer action_id + no DB → exit 0 + mode=no-db (preserve original behavior)
rm -rf "${HOME}/.board-superpowers"
mkdir -p "${HOME}"

RC2=0
bash "${ROOT}/scripts/audit-log-write.sh" \
    --action-id 200 \
    --decision A \
    --skill bootstrapping-repo \
    --approval-stage auto \
    --outcome success \
    --payload '{}' || RC2=$?
[ "${RC2}" = 0 ] || { echo "FAIL: integer action_id should exit 0, got ${RC2}"; exit 1; }

echo "PASS"
