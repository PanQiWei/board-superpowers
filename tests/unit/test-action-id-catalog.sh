#!/usr/bin/env bash
# unit: 验证 200-208 在所有 6 处 SoT 都已注册
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"

FAIL=0
for src in \
    "${ROOT}/skills/classifying-actions/references/matrix.md" \
    "${ROOT}/skills/classifying-actions/references/action-id-catalog.md" \
    "${ROOT}/skills/auditing-actions/references/db-write-conventions.md" \
    "${ROOT}/docs/architecture/0005-contracts/06-audit-log-schema.md" \
    "${ROOT}/docs/architecture/adr/0006-producer-autonomy-boundary.md" \
    "${ROOT}/skills/bootstrapping-repo/SKILL.md"
do
    for id in 200 201 202 203 204 205 206 207 208; do
        if ! grep -qE "(^| )${id}( |\\|)" "${src}"; then
            echo "FAIL: ${id} not in ${src}"
            FAIL=1
        fi
    done
    # 209 必须不存在 (SPOT 不预留)
    if grep -qE "(^| )209( |\\|)" "${src}"; then
        echo "FAIL: 209 reserved still in ${src}"
        FAIL=1
    fi
done
[ "${FAIL}" = 0 ] && echo "PASS: 200-208 in 6 SoTs; 209 absent"
exit ${FAIL}
