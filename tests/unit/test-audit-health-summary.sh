#!/usr/bin/env bash
# tests/unit/test-audit-health-summary.sh — AC5 audit-health summary.
#
# Verifies bsp_audit_health_summary helper:
# - Reports DB_ROWS / TOTAL ratio for bootstrap action_ids (200-208)
#   queried from the audit_log table after the bootstrap window's
#   start timestamp (filters out prior-bootstrap noise).
# - Falls back to a "no DB configured" message when the URL is unset.
# - Emits a "no rows in window" message when start_ts is in the
#   future of all rows (so the summary differentiates "all failed"
#   from "nothing happened in this window").
#
# Per design.md §3.5 (Codex blocker fix): the original AC5 plan
# counted jsonl rows as TOTAL; that approach broke after Task 6+
# flush deletes/transitions rows. We pivot to a DB-side range query
# anchored on bootstrap_start_ts.

set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
export HOME="${TMPDIR}/fake-home"
mkdir -p "${HOME}/.board-superpowers"

DB="${TMPDIR}/audit.db"
sqlite3 "${DB}" < "${ROOT}/scripts/lib/audit-schema.sqlite.sql"
export BOARD_SP_AUDIT_DB_URL="sqlite:////${DB}"

# shellcheck source=/dev/null
. "${ROOT}/scripts/lib/common.sh"

# --- Test 1 — happy path: 9 of 9 rows landed in DB after start_ts -------
START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sleep 1
ROW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for i in 200 201 202 203 204 205 206 207 208; do
    sqlite3 "${DB}" "INSERT INTO audit_log (timestamp,project,session_id,actor_role,action_id,payload,outcome,approval_stage,event_uuid) VALUES ('${ROW_TS}','p/1','s1','producer',${i},'{}','success','auto','uuid-${i}')"
done

OUTPUT=$(bsp_audit_health_summary "${START_TS}" 2>&1)
echo "Output (Test 1 happy): ${OUTPUT}"
echo "${OUTPUT}" | grep -qE '9 of 9|9/9' \
    || { echo "FAIL: missing '9 of 9' in happy path"; exit 1; }
echo "${OUTPUT}" | grep -qE '0 remain|0 in jsonl' \
    || { echo "FAIL: missing '0 remain' in happy path"; exit 1; }

# --- Test 2 — degraded mode: DB URL unset --------------------------------
unset BOARD_SP_AUDIT_DB_URL
OUTPUT2=$(bsp_audit_health_summary "${START_TS}" 2>&1)
echo "Output (Test 2 no-db): ${OUTPUT2}"
echo "${OUTPUT2}" | grep -qE 'no DB|0 of 9|jsonl only' \
    || { echo "FAIL: missing degraded mode message; got: ${OUTPUT2}"; exit 1; }

# --- Test 3 — start_ts filter: future window has no rows -----------------
export BOARD_SP_AUDIT_DB_URL="sqlite:////${DB}"
sleep 1
NEW_START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OUTPUT3=$(bsp_audit_health_summary "${NEW_START_TS}" 2>&1)
echo "Output (Test 3 future-window): ${OUTPUT3}"
echo "${OUTPUT3}" | grep -qE '0 of 0|no.*audit|nothing to report|no rows in window' \
    || { echo "FAIL: filter by start_ts didn't isolate to fresh window; got: ${OUTPUT3}"; exit 1; }

# --- Test 4 — DSN unreachable + jsonl has pending rows -------------------
# Regression for #43 followup-1: when DSN is configured but the DB
# query returns 0 (unreachable / table missing / throw), the summary
# MUST surface the jsonl backlog instead of "nothing to report".
JSONL_DIR="${HOME}/.board-superpowers/repos/test-repo-followup1"
mkdir -p "${JSONL_DIR}"
JSONL="${JSONL_DIR}/audit-local.jsonl"
PENDING_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sleep 1
TEST4_START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sleep 1
NEW_PENDING_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Write 3 pending bootstrap rows in window + 1 outside (older) + 1 with
# action_id outside 200..208 (must NOT be counted)
{
    printf '{"ts":"%s","action_id":"200","status":"pending","mode":"bootstrap-pending","event_uuid":"u-200"}\n' "${NEW_PENDING_TS}"
    printf '{"ts":"%s","action_id":"205","status":"pending","mode":"bootstrap-pending","event_uuid":"u-205"}\n' "${NEW_PENDING_TS}"
    printf '{"ts":"%s","action_id":"208","status":"pending","mode":"bootstrap-pending","event_uuid":"u-208"}\n' "${NEW_PENDING_TS}"
    printf '{"ts":"%s","action_id":"200","status":"pending","mode":"bootstrap-pending","event_uuid":"u-200-old"}\n' "${PENDING_TS}"
    printf '{"ts":"%s","action_id":"100","status":"pending","mode":"bootstrap-pending","event_uuid":"u-100"}\n' "${NEW_PENDING_TS}"
} > "${JSONL}"
# Point at a non-existent SQLite DB to simulate DSN-unreachable (so DB query throws).
export BOARD_SP_AUDIT_DB_URL="sqlite:////${TMPDIR}/no-such-dir/unreachable.db"
OUTPUT4=$(bsp_audit_health_summary "${TEST4_START_TS}" 2>&1)
echo "Output (Test 4 DSN-unreachable+jsonl-pending): ${OUTPUT4}"
echo "${OUTPUT4}" | grep -qE '3 remain in jsonl' \
    || { echo "FAIL: expected '3 remain in jsonl' for DSN-unreachable+3-pending; got: ${OUTPUT4}"; exit 1; }
echo "${OUTPUT4}" | grep -qE 'check connectivity|DB query returned 0' \
    || { echo "FAIL: expected DB-query-zero hint; got: ${OUTPUT4}"; exit 1; }

# --- Test 5 — DSN unset + jsonl has pending rows -------------------------
# Regression for #43 followup-1: even with DSN unset the summary should
# surface the jsonl backlog (was previously a quiet "0 of 9 ... jsonl only").
unset BOARD_SP_AUDIT_DB_URL
OUTPUT5=$(bsp_audit_health_summary "${TEST4_START_TS}" 2>&1)
echo "Output (Test 5 DSN-unset+jsonl-pending): ${OUTPUT5}"
echo "${OUTPUT5}" | grep -qE '3 remain in jsonl' \
    || { echo "FAIL: expected '3 remain in jsonl' for DSN-unset+3-pending; got: ${OUTPUT5}"; exit 1; }

# Cleanup test 4/5 jsonl so it doesn't leak to other test scripts.
rm -rf "${JSONL_DIR}"

echo "PASS"
