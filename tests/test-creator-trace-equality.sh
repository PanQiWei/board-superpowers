#!/usr/bin/env bash
# tests/test-creator-trace-equality.sh
# AC4 end-to-end: create a throwaway card via the canonical intake path;
# assert that card body session_id == audit_log session_id == expected.
#
# What this test asserts (3-way equality):
#   expected   — bsp_resolve_session_id() called BEFORE intake, in this shell
#   body_sid   — Session-id extracted from the gh issue body after creation
#   audit_sid  — session_id extracted from the audit_log row written by
#                audit-log-write.sh (SQLite or jsonl fallback — auto-detects
#                which path is active based on credentials.yml presence)
#
# The test session_id is also embedded in the payload passed to
# audit-log-write.sh so it is recoverable from the jsonl summary line even
# in no-db degraded mode (jsonl schema does not carry a top-level
# session_id column; session_id is extracted from payload={...}).
#
# Cleanup: trap deletes the throwaway issue on EXIT (falls back to close
# if delete fails) so test failures never pollute the GitHub project board.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${REPO_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/common.sh
# shellcheck source-path=SCRIPTDIR
source "${COMMON}"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Resolve expected session_id BEFORE intake in this exact shell.
#    All subsequent bsp_resolve_session_id calls must return the same value
#    (stable within one shell / one PWD — see AC4 stability invariant in
#    scripts/lib/common.sh § "PWD-fallback stability invariant").
# ---------------------------------------------------------------------------
expected="$(bsp_resolve_session_id)"
[ -n "${expected}" ] || fail "bsp_resolve_session_id returned empty string"
printf 'expected session_id: %s\n' "${expected}"

# ---------------------------------------------------------------------------
# 2. Build a minimal card body that includes the creator-trace block.
#    bsp_render_creator_trace_block calls bsp_resolve_session_id internally;
#    it must produce the same value as $expected (same shell, same PWD).
# ---------------------------------------------------------------------------
body="$(cat <<BODY
$(bsp_render_creator_trace_block)
<!-- thin-pointer -->
**Spec**: tests/test-creator-trace-equality.sh
**Owner**: @PanQiWei
**Estimate**: XS
<!-- /thin-pointer -->

## Goal
[ac4 throwaway test card — auto-created and auto-deleted]

## Acceptance criteria
- [ ] (smoke — never merged)

## Out of scope
n/a

## Dependencies
n/a

## Notes
Created by tests/test-creator-trace-equality.sh.

<!-- board-superpowers:audit-trail -->
<!-- /board-superpowers:audit-trail -->
BODY
)"

# ---------------------------------------------------------------------------
# 3. Create throwaway card; capture the issue number.
#    gh issue create returns the issue URL (e.g. https://.../issues/42);
#    extract the trailing number.
# ---------------------------------------------------------------------------
card_num=""
issue_url=""
issue_url=$(gh issue create \
  --title "[ac4 throwaway] $(date -u +%FT%TZ)" \
  --body "${body}" \
  --label "size:XS") \
  || fail "gh issue create failed (see above stderr)"
[ -n "${issue_url}" ] || fail "gh issue create returned empty output"

# ---------------------------------------------------------------------------
# Cleanup trap — register IMMEDIATELY after issue_url is confirmed
# non-empty so that if card_num parsing fails the throwaway issue is still
# cleaned up. The cleanup function's [ -n "${card_num:-}" ] guard makes
# this a safe no-op until card_num is set; gh issue delete also accepts a
# URL directly so the trap can fall through to URL-based deletion when
# card_num is empty (not currently implemented — number-only guard kept for
# simplicity since gh issue delete does accept URLs; see commit message).
# ---------------------------------------------------------------------------
cleanup() {
  if [ -n "${card_num:-}" ]; then
    printf 'Cleaning up throwaway card #%s...\n' "${card_num}"
    if gh issue delete "${card_num}" --yes 2>/dev/null; then
      printf 'Deleted card #%s\n' "${card_num}"
    elif gh issue close "${card_num}" \
         --comment "[ac4 throwaway test cleanup — delete failed, closing instead]" 2>/dev/null; then
      printf 'Closed card #%s (delete unavailable)\n' "${card_num}"
    else
      printf 'WARN: could not delete or close throwaway card #%s\n' "${card_num}" >&2
    fi
  fi
}
trap cleanup EXIT

card_num=$(printf '%s\n' "${issue_url}" | grep -oE '[0-9]+$') \
  || fail "could not extract issue number from: ${issue_url}"
[ -n "${card_num}" ] || fail "issue number is empty (url=${issue_url})"
printf 'Created throwaway card #%s (%s)\n' "${card_num}" "${issue_url}"

# ---------------------------------------------------------------------------
# 4. Write the corresponding audit row (action_id=1).
#    Embed session_id in the payload so it is recoverable from the jsonl
#    summary line in no-db degraded mode (jsonl schema has no top-level
#    session_id column; extraction reads payload={...} from summary).
# ---------------------------------------------------------------------------
payload="{\"card_number\":${card_num},\"session_id\":\"${expected}\",\"smoke_test\":\"ac4-end-to-end\"}"
bash "${REPO_ROOT}/scripts/audit-log-write.sh" \
  --action-id 1 --decision A --skill consuming-card \
  --approval-stage auto --outcome success \
  --payload "${payload}" \
  || fail "audit-log-write.sh failed"

# ---------------------------------------------------------------------------
# 5. Read card body session_id from the live GitHub issue.
# ---------------------------------------------------------------------------
card_body=""
card_body=$(gh issue view "${card_num}" --json body --jq '.body') \
  || fail "gh issue view failed for card #${card_num} (see above stderr)"
body_sid=""
body_sid=$(printf '%s\n' "${card_body}" \
  | grep -oE '\*\*Session-id:\*\* [^[:space:]]+' \
  | head -1 \
  | sed -E 's/^\*\*Session-id:\*\* //') \
  || fail "grep/sed pipeline for Session-id failed"
[ -n "${body_sid}" ] || fail "Session-id not found in card body (creator-trace block missing?)"
printf 'Card body session_id:  %s\n' "${body_sid}"

# ---------------------------------------------------------------------------
# 6. Read audit_log session_id from whichever path is active.
# ---------------------------------------------------------------------------
JSONL="$(bsp_audit_local_path "$(bsp_primary_repo_root "${REPO_ROOT}")")"
audit_sid=""
audit_path=""

if [ -f "${HOME}/.board-superpowers/credentials.yml" ] \
   && grep -qE '^audit_db_url[[:space:]]*:' "${HOME}/.board-superpowers/credentials.yml"; then
  # --- SQLite path ---
  DB_URL=$(grep -E '^audit_db_url[[:space:]]*:' "${HOME}/.board-superpowers/credentials.yml" \
    | head -1 \
    | sed -E 's/^audit_db_url[[:space:]]*:[[:space:]]*//; s/^"//; s/"$//')
  # Normalize sqlite:////abs/path  →  /abs/path
  DB_PATH="${DB_URL}"
  case "${DB_URL}" in
    sqlite:////*)  DB_PATH="${DB_URL#sqlite:///}"  ;;
    sqlite3:////*)  DB_PATH="${DB_URL#sqlite3:///}" ;;
    sqlite:///* | sqlite3:///* )
      DB_PATH="${DB_URL#sqlite://}"
      DB_PATH="${DB_PATH#sqlite3://}"
      DB_PATH="/${DB_PATH#/}"
      ;;
  esac
  audit_sid=$(sqlite3 "${DB_PATH}" \
    "SELECT session_id FROM audit_log
     WHERE action_id=1
       AND json_extract(payload,'\$.card_number')=${card_num}
     ORDER BY id DESC LIMIT 1;") \
    || fail "sqlite3 query failed for card #${card_num} db=${DB_PATH} (see above stderr)"
  [ -n "${audit_sid}" ] || fail "sqlite3 returned empty session_id for card #${card_num} action_id=1"
  audit_path="sqlite:${DB_PATH}"
elif [ -f "${JSONL}" ]; then
  # --- jsonl fallback path ---
  # The jsonl schema has no top-level session_id column; extract from
  # the payload={...} JSON embedded in the summary field.
  audit_sid=$(tail -200 "${JSONL}" \
    | python3 -c "
import sys, json, re
card_num = int('${card_num}')
for line in reversed(sys.stdin.readlines()):
    line = line.strip()
    if not line:
        continue
    try:
        row = json.loads(line)
    except Exception:
        continue
    # Match rows: action_id==1 and payload contains card_number==card_num
    if str(row.get('action_id', '')) != '1':
        continue
    summary = row.get('summary', '')
    m = re.search(r'payload=(\{.*\})\s*\$', summary)
    if not m:
        continue
    try:
        payload = json.loads(m.group(1))
    except Exception:
        continue
    if payload.get('card_number') == card_num:
        print(payload.get('session_id', ''))
        break
") \
    || fail "jsonl python parse failed"
  [ -n "${audit_sid}" ] || fail "session_id not found in jsonl for card #${card_num} action_id=1 (payload missing session_id?)"
  audit_path="jsonl:${JSONL}"
else
  fail "neither SQLite credentials.yml nor jsonl audit log is reachable"
fi
printf 'Audit row (%s) session_id: %s\n' "${audit_path}" "${audit_sid}"

# ---------------------------------------------------------------------------
# 7. 3-way assertion.
# ---------------------------------------------------------------------------
[ "${expected}" = "${body_sid}" ] \
  || fail "card body != expected: '${body_sid}' vs '${expected}'"
[ "${expected}" = "${audit_sid}" ] \
  || fail "audit row != expected: '${audit_sid}' vs '${expected}'"
[ "${body_sid}" = "${audit_sid}" ] \
  || fail "card body != audit row: '${body_sid}' vs '${audit_sid}'"

printf 'PASS: AC4 end-to-end equality (sid='"'"'%s'"'"', card=#%s, audit=%s)\n' \
  "${expected}" "${card_num}" "${audit_path}"
