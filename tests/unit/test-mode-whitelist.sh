#!/usr/bin/env bash
# unit: bsp_audit_local_write enforces explicit mode whitelist
# (#43 AC3). Verifies:
#   - 3 new modes (contract-violation, bootstrap-pending,
#     audit-dead-letter) accepted
#   - 5 existing modes (no-db, degraded-db-unavailable,
#     degraded-uv-missing, degraded-venv-create-failed,
#     v1-minimum-degraded) still accepted
#   - unknown modes rejected (return non-zero)
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
export HOME="${TMPDIR}/fake-home"
mkdir -p "${HOME}"

source "${ROOT}/scripts/lib/common.sh"

# All 3 new modes should be accepted
for mode in contract-violation bootstrap-pending audit-dead-letter; do
    bsp_audit_local_write "/tmp/fakerepo" 200 A bootstrapping-repo \
        "approval=auto outcome=success payload={}" "${mode}" \
        || { echo "FAIL: mode=${mode} rejected"; exit 1; }
done

# 5 existing modes still accepted
for mode in no-db degraded-db-unavailable degraded-uv-missing degraded-venv-create-failed v1-minimum-degraded; do
    bsp_audit_local_write "/tmp/fakerepo" 200 A bootstrapping-repo \
        "approval=auto outcome=success payload={}" "${mode}" \
        || { echo "FAIL: existing mode=${mode} regressed"; exit 1; }
done

# Unknown mode should be rejected (return non-zero)
RC=0
bsp_audit_local_write "/tmp/fakerepo" 200 A bootstrapping-repo \
    "approval=auto outcome=success payload={}" "definitely-not-a-mode" 2>/dev/null \
    || RC=$?
[ "${RC}" != 0 ] || { echo "FAIL: unknown mode should be rejected, but bsp_audit_local_write returned 0"; exit 1; }

echo "PASS"
