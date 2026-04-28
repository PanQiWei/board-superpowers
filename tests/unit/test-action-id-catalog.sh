#!/usr/bin/env bash
# unit: 验证 200-208 在 6 处 SoT 都已注册 (catalog row + payload template)
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"

FAIL=0

# Loop 1: catalog presence in 6 SoT files (tighter regex — anchors on action_id-shaped contexts)
for src in \
    "${ROOT}/skills/classifying-actions/references/matrix.md" \
    "${ROOT}/skills/classifying-actions/references/action-id-catalog.md" \
    "${ROOT}/skills/auditing-actions/references/db-write-conventions.md" \
    "${ROOT}/docs/architecture/0005-contracts/06-audit-log-schema.md" \
    "${ROOT}/docs/architecture/adr/0006-producer-autonomy-boundary.md" \
    "${ROOT}/skills/bootstrapping-repo/SKILL.md"
do
    for id in 200 201 202 203 204 205 206 207 208; do
        # Match if id appears in any of these structural contexts:
        #   - markdown table cell:        | 200 |
        #   - bullet header bold prefix:  - **200:
        #   - SKILL.md arrow form:        200 →
        #   - prose with explicit prefix: action_id 200 / action_id = 200 / `action_id = 200`
        if ! grep -qE "(\\| ${id} \\||- \\*\\*${id}:|^${id} →|action_id[[:space:]=]+${id}\\b|action_id = ${id})" "${src}"; then
            echo "FAIL: ${id} not in ${src} (no structural occurrence)"
            FAIL=1
        fi
    done
    # 209 must NOT appear in any structural context (SPOT 不预留)
    if grep -qE "(\\| 209 \\||- \\*\\*209:|^209 →|action_id[[:space:]=]+209\\b|action_id = 209)" "${src}"; then
        echo "FAIL: 209 reserved still in ${src}"
        FAIL=1
    fi
done

# Loop 2: payload template existence in db-write-conventions.md
DBWC="${ROOT}/skills/auditing-actions/references/db-write-conventions.md"
for id in 200 201 202 203 204 205 206 207 208; do
    if ! grep -qE "^### \\\`action_id = ${id}\\\`" "${DBWC}"; then
        echo "FAIL: payload template for action_id ${id} missing in db-write-conventions.md"
        FAIL=1
    fi
done

[ "${FAIL}" = 0 ] && echo "PASS: 200-208 in 6 SoTs (catalog + payload templates); 209 absent"
exit ${FAIL}
