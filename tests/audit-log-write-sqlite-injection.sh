#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPREPO="$(mktemp -d)"
TMPDB="$(mktemp -t audit.XXXXXX -u).db"

mkdir -p "${TMPREPO}/.board-superpowers"
git -C "${TMPREPO}" init -q

export CLAUDE_PLUGIN_ROOT="${SCRIPT_DIR}"
export BOARD_SP_AUDIT_DB_URL="sqlite:///${TMPDB}"

cd "${TMPREPO}"
bash "${SCRIPT_DIR}/scripts/audit-init.sh" >/dev/null

# Test payload with edge characters: ' \ \n \0 literal, Unicode é
# shellcheck disable=SC2016
PAYLOAD='{"text":"O'"'"'Brien said \\\"hi\\\"\nLine 2 é"}'

bash "${SCRIPT_DIR}/scripts/audit-log-write.sh" \
    --action-id 100 \
    --decision A \
    --skill consuming-card \
    --approval-stage auto \
    --outcome success \
    --payload "${PAYLOAD}" \
    --repo-root "${TMPREPO}"
rc=$?
[ $rc -eq 0 ] || { echo "FAIL: audit-log-write exit $rc"; rm -f "${TMPDB}"; rm -rf "${TMPREPO}"; exit 1; }

# Read back and verify byte-equal.
ROWBACK=$(sqlite3 "${TMPDB}" "SELECT payload FROM audit_log WHERE action_id=100 LIMIT 1")
if [ "${ROWBACK}" = "${PAYLOAD}" ]; then
    echo "PASS"
else
    echo "FAIL: round-trip mismatch"
    echo "in:  ${PAYLOAD}"
    echo "out: ${ROWBACK}"
    rm -f "${TMPDB}"
    rm -rf "${TMPREPO}"
    exit 1
fi

rm -f "${TMPDB}"
rm -rf "${TMPREPO}"
