#!/usr/bin/env bash
# tests/audit-local-migration.sh — assert bsp_audit_local_write
# performs the legacy → new path migration per Card 1 Phase D Slice 4c.
#
# Migration heuristic:
#   - When new path (~/.board-superpowers/repos/<normalized>/audit-local.jsonl)
#     does not exist, scan ~/.board-superpowers/*/*/audit-local.jsonl
#     (legacy <host>/<repo> layout) and pick the file whose owning
#     directory's basename matches basename of <repo_root>. If multiple
#     match, prefer the one whose owning-grandparent matches the GitHub
#     org slug derivable from `git remote get-url origin`. Fallback:
#     basename only.
#   - On match: mkdir -p new dir, mv legacy → new; subsequent calls
#     see new path exists and skip detection (idempotent).
#   - On no match: do not migrate; just create new path and append.
#
# Hermeticity: every scenario uses a fresh tmp HOME and a fresh tmp
# repo_root; nothing touches the real ~/.board-superpowers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMMON_SH="${PLUGIN_ROOT}/scripts/lib/common.sh"

if [ ! -f "${COMMON_SH}" ]; then
    printf 'FATAL: %s not found\n' "${COMMON_SH}" >&2
    exit 99
fi

PASS=0
FAIL=0

# check <label> <cmd...> — run cmd; PASS on exit 0, FAIL otherwise.
# Avoids SC2319 (condition $? capture) and SC2251 (! masking errexit) by
# never relying on the test's own $? after the conditional executes.
check() {
    local label="$1"
    shift
    if "$@"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# check_not <label> <cmd...> — inverse: PASS when cmd fails.
check_not() {
    local label="$1"
    shift
    if "$@"; then
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    else
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    fi
}

# Helpers for line-count checks (avoids inline arithmetic in callers).
file_line_count() {
    local f="$1"
    [ -f "${f}" ] || { printf '0\n'; return 0; }
    wc -l < "${f}" | tr -d ' '
}

count_eq() {
    local f="$1"
    local expected="$2"
    [ "$(file_line_count "${f}")" = "${expected}" ]
}

# normalize_path: bash port of bsp_normalize_repo_path for test setup.
# Tests verify the helper itself in tests/common-helpers.sh; here we
# only need a normalized name to assert paths.
normalize_path() {
    local p="$1"
    p="${p#/}"
    p="${p%/}"
    p="${p//\//-}"
    printf '%s' "${p}"
}

run_audit_write() {
    local home="$1"; shift
    local repo_root="$1"; shift
    # Args: <action_id> <decision> <skill> <summary>
    bash -c "
        set -euo pipefail
        export HOME='${home}'
        source '${COMMON_SH}'
        bsp_audit_local_write '${repo_root}' '$1' '$2' '$3' '$4'
    " >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Scenario 1: migration triggers when legacy file exists and new doesn't
# ---------------------------------------------------------------------------
printf 'Scenario 1: migration triggers (legacy exists, new does not)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/board-superpowers"
mkdir -p "${HOME_DIR}/.board-superpowers/somehost/board-superpowers"
mkdir -p "${REPO_ROOT}"
LEGACY_FILE="${HOME_DIR}/.board-superpowers/somehost/board-superpowers/audit-local.jsonl"
printf '{"ts":"old","action_id":"100"}\n' > "${LEGACY_FILE}"

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '100' 'R' 'managing-board' 'first-write'

# Legacy file gone (moved)
check_not 'legacy file moved (no longer at old path)' test -f "${LEGACY_FILE}"

# New file exists with both old line + new line
check 'new file exists at canonical path' test -f "${NEW_FILE}"

check 'new file contains both legacy + new entries (2 lines)' \
    count_eq "${NEW_FILE}" 2

# Verify legacy content preserved
check 'legacy entry preserved in migrated file' \
    grep -q '"ts":"old"' "${NEW_FILE}"

# Verify new entry appended
check 'new entry appended after migration' \
    grep -q '"action_id": "100"' "${NEW_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 2: no migration when new path already exists
# ---------------------------------------------------------------------------
printf 'Scenario 2: no migration when new file already exists\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/board-superpowers"
mkdir -p "${REPO_ROOT}"

# Seed both legacy AND new
mkdir -p "${HOME_DIR}/.board-superpowers/somehost/board-superpowers"
LEGACY_FILE="${HOME_DIR}/.board-superpowers/somehost/board-superpowers/audit-local.jsonl"
printf '{"ts":"legacy-untouched"}\n' > "${LEGACY_FILE}"

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"
mkdir -p "$(dirname "${NEW_FILE}")"
printf '{"ts":"already-migrated"}\n' > "${NEW_FILE}"

run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '101' 'R' 'managing-board' 'second-write'

# Legacy still there, untouched
check 'legacy file untouched when new already exists' \
    test -f "${LEGACY_FILE}"

check 'legacy file size unchanged' count_eq "${LEGACY_FILE}" 1

# New has the pre-existing line + new line
check 'new file got the new entry appended' count_eq "${NEW_FILE}" 2

check 'pre-existing migrated content preserved' \
    grep -q '"ts":"already-migrated"' "${NEW_FILE}"

check 'new entry appended to existing new file' \
    grep -q '"action_id": "101"' "${NEW_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 2b: race tolerance — both legacy AND new path exist before invoke
# ---------------------------------------------------------------------------
# Differs from Scenario 2 in intent. Scenario 2 asserts: "when new exists,
# don't even look at legacy" (the migration block is skipped wholesale —
# legacy stays untouched). Scenario 2b simulates the narrow race window
# where this writer's earlier `[ ! -f "${path}" ]` check passed, then
# another concurrent writer migrated, then we got the cpu and tried to
# `mv legacy → new`. The mv should fail-but-tolerated; the appended line
# still lands on the canonical new path; no error escapes.
#
# Hard to deterministically simulate the in-flight race in a test harness,
# so we approximate by pre-populating BOTH paths to the state the racer
# would leave behind. The first call's `[ ! -f "${path}" ]` check will
# evaluate against the new path; if it sees new exists, the migration
# block is skipped and we get Scenario 2 behavior. To genuinely exercise
# the mv race-tolerance branch we need the migration block to enter, then
# fail. We do that by making the new path NOT exist when bsp_audit_local_write
# starts, then watch behavior when legacy disappears mid-flight: in real
# systems this is the racer beating us. In the test harness the mv simply
# fails (legacy actually present, but if we delete legacy between the
# scan loop and the mv, it errors). Practical assertion below:
#   - both files seeded → outer `[ ! -f "${path}" ]` is false, migration
#     block is skipped, we hit the append directly. New path receives the
#     new entry; legacy untouched. This already covers Scenario 2.
#   - The race-tolerance branch fires when an external writer races us
#     between the existence check and the mv. Mocking that needs a
#     coprocess; out of scope for a single-file bash test.
#
# Concrete behavior we CAN assert: bsp_audit_local_write must not ERROR
# when both paths happen to exist at function-entry time. Asserting
# error-free completion + correct append covers the externally observable
# guarantee.
printf 'Scenario 2b: race tolerance — both paths seeded, no error, append succeeds\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/board-superpowers"
mkdir -p "${REPO_ROOT}"

mkdir -p "${HOME_DIR}/.board-superpowers/somehost/board-superpowers"
LEGACY_FILE="${HOME_DIR}/.board-superpowers/somehost/board-superpowers/audit-local.jsonl"
printf '{"ts":"legacy-pre-race"}\n' > "${LEGACY_FILE}"

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"
mkdir -p "$(dirname "${NEW_FILE}")"
printf '{"ts":"new-pre-race"}\n' > "${NEW_FILE}"

# Run with stderr captured separately so we can fail loud on errors.
RUN_ERR="$(mktemp)"
set +e
bash -c "
    set -euo pipefail
    export HOME='${HOME_DIR}'
    source '${COMMON_SH}'
    bsp_audit_local_write '${REPO_ROOT}' '199' 'R' 'managing-board' 'race-tolerant'
" >/dev/null 2>"${RUN_ERR}"
RC=$?
set -e

if [ "${RC}" = "0" ]; then
    printf '  PASS — bsp_audit_local_write succeeded with both paths present (rc=0)\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL — bsp_audit_local_write errored (rc=%s). stderr:\n%s\n' \
        "${RC}" "$(cat "${RUN_ERR}")" >&2
    FAIL=$((FAIL + 1))
fi
rm -f "${RUN_ERR}"

# Append landed on new path (was 1 line, now 2).
check 'race scenario: append landed on canonical new path' \
    count_eq "${NEW_FILE}" 2

check 'race scenario: pre-existing new entry preserved' \
    grep -q '"ts":"new-pre-race"' "${NEW_FILE}"

check 'race scenario: new entry written' \
    grep -q '"action_id": "199"' "${NEW_FILE}"

# Legacy stays untouched — the outer `[ ! -f "${path}" ]` short-circuits
# the migration block when new exists.
check 'race scenario: legacy file untouched' \
    test -f "${LEGACY_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 3: no legacy match → no migration
# ---------------------------------------------------------------------------
printf 'Scenario 3: unrelated legacy file → no migration\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/board-superpowers"
mkdir -p "${REPO_ROOT}"

# Seed unrelated legacy file (different repo basename)
mkdir -p "${HOME_DIR}/.board-superpowers/host/some-other-repo"
UNRELATED="${HOME_DIR}/.board-superpowers/host/some-other-repo/audit-local.jsonl"
printf '{"ts":"unrelated"}\n' > "${UNRELATED}"

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '102' 'R' 'managing-board' 'fresh'

# Unrelated legacy untouched
check 'unrelated legacy file untouched (no basename match)' \
    test -f "${UNRELATED}"

# New file created with single new entry
check 'new file created at canonical path' test -f "${NEW_FILE}"

check 'new file has single entry (no prepended legacy)' \
    count_eq "${NEW_FILE}" 1

check 'new entry written' \
    grep -q '"action_id": "102"' "${NEW_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 4: repeat call after migration is no-op for migration logic
# ---------------------------------------------------------------------------
printf 'Scenario 4: repeat call is migration no-op (idempotent)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/board-superpowers"
mkdir -p "${REPO_ROOT}"
mkdir -p "${HOME_DIR}/.board-superpowers/somehost/board-superpowers"
LEGACY_FILE="${HOME_DIR}/.board-superpowers/somehost/board-superpowers/audit-local.jsonl"
printf '{"ts":"original"}\n' > "${LEGACY_FILE}"

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

# First write triggers migration
run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '103' 'R' 'mgr' 'first'

# Second write: legacy is gone, new exists; should NOT re-look for legacy
run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '104' 'R' 'mgr' 'second'

# Third write: same
run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '105' 'R' 'mgr' 'third'

# 1 legacy + 3 new = 4 lines
check 'subsequent writes append without re-migration (4 lines)' \
    count_eq "${NEW_FILE}" 4

# Re-create a stale legacy: simulate accidental reappearance.
# This SHOULD NOT be re-migrated, because new exists.
mkdir -p "${HOME_DIR}/.board-superpowers/somehost/board-superpowers"
printf '{"ts":"stray"}\n' > "${LEGACY_FILE}"

run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '106' 'R' 'mgr' 'fourth'

# Stray legacy still there (unmoved)
check 'stray legacy not re-migrated (new path already canonical)' \
    test -f "${LEGACY_FILE}"

check 'fourth write appended cleanly (5 lines)' \
    count_eq "${NEW_FILE}" 5

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 5: JSON line shape — drops host/repo, adds repo_root
# ---------------------------------------------------------------------------
printf 'Scenario 5: JSON entry shape after signature change\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/some-app"
mkdir -p "${REPO_ROOT}"

run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '200' 'A' 'managing-board' 'shape-check'

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

check 'audit file created' test -f "${NEW_FILE}"

# repo_root field present
check 'repo_root field present' \
    grep -Fq "\"repo_root\": \"${REPO_ROOT}\"" "${NEW_FILE}"

# host / repo fields absent
check_not 'no separate host field' \
    grep -q '"host":' "${NEW_FILE}"

check_not 'no separate repo field' \
    grep -q '"repo":' "${NEW_FILE}"

# action_id, decision_class, skill, summary, mode, ts still present
check 'action_id preserved' \
    grep -q '"action_id": "200"' "${NEW_FILE}"

check 'decision_class preserved' \
    grep -q '"decision_class": "A"' "${NEW_FILE}"

check 'mode field preserved' \
    grep -q '"mode": "v1-minimum-degraded"' "${NEW_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6: 3-level legacy path — owner/name split from old caller signature
# ---------------------------------------------------------------------------
# Per issue #27: v0.1.0-minimum's `bsp_audit_local_write <host> <repo>`
# signature accepted a `<repo>` arg containing a slash. Callers that
# passed `<repo>=<owner>/<name>` (e.g. `PanQiWei/board-superpowers`)
# ended up with a THREE-level legacy path:
#
#   ~/.board-superpowers/<host>/<owner>/<name>/audit-local.jsonl
#
# The migration scan glob was previously two-levels-only
# (`/*/*/audit-local.jsonl`) and silently missed these paths. Seeded
# legacy persisted; new path started fresh; legacy entries were lost
# from the canonical timeline until manually merged.
#
# Migration MUST detect 3-level legacy paths whose innermost segment
# (the "<name>" part) matches basename(repo_root). The intermediate
# "<owner>" segment is the org slug; preferred match still uses
# `git remote get-url origin` org parsing (now compared against
# the parent of the innermost dir, not its grandparent).
printf 'Scenario 6: 3-level legacy path (host/owner/name) — migration triggers\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/board-superpowers"
mkdir -p "${REPO_ROOT}"
# Seed a 3-level legacy path mimicking v0.1.0-minimum caller that
# passed <repo>="PanQiWei/board-superpowers".
mkdir -p "${HOME_DIR}/.board-superpowers/somehost/PanQiWei/board-superpowers"
LEGACY_FILE="${HOME_DIR}/.board-superpowers/somehost/PanQiWei/board-superpowers/audit-local.jsonl"
printf '{"ts":"3-level-legacy","action_id":"100"}\n' > "${LEGACY_FILE}"

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '101' 'R' 'managing-board' 'first-write-after-3-level'

check_not '3-level legacy file moved (no longer at old path)' test -f "${LEGACY_FILE}"
check '3-level new file exists at canonical path' test -f "${NEW_FILE}"
check '3-level new file has both legacy + new entries (2 lines)' \
    count_eq "${NEW_FILE}" 2
check '3-level legacy entry preserved in migrated file' \
    grep -q '"ts":"3-level-legacy"' "${NEW_FILE}"
check '3-level new entry appended after migration' \
    grep -q '"action_id": "101"' "${NEW_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6b: 3-level legacy AND owner-aware match preference
# ---------------------------------------------------------------------------
# When git remote points at github.com:<owner>/<repo>, and TWO 3-level
# candidates have matching innermost basenames but only one matches the
# org slug, prefer the org-matching one.
printf 'Scenario 6b: 3-level legacy with owner-slug preference\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/board-superpowers"
mkdir -p "${REPO_ROOT}"
# Make repo a real git repo with a github remote so owner_slug parses.
git -C "${REPO_ROOT}" init --quiet
git -C "${REPO_ROOT}" remote add origin "git@github.com:PanQiWei/board-superpowers.git"

# Two 3-level legacy candidates: only one is under PanQiWei.
mkdir -p "${HOME_DIR}/.board-superpowers/host1/SomeoneElse/board-superpowers"
mkdir -p "${HOME_DIR}/.board-superpowers/host2/PanQiWei/board-superpowers"
WRONG_LEGACY="${HOME_DIR}/.board-superpowers/host1/SomeoneElse/board-superpowers/audit-local.jsonl"
RIGHT_LEGACY="${HOME_DIR}/.board-superpowers/host2/PanQiWei/board-superpowers/audit-local.jsonl"
printf '{"ts":"wrong-owner"}\n' > "${WRONG_LEGACY}"
printf '{"ts":"correct-owner"}\n' > "${RIGHT_LEGACY}"

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '102' 'R' 'managing-board' 'owner-aware'

check_not 'owner-aware: PanQiWei legacy moved' \
    test -f "${RIGHT_LEGACY}"
check 'owner-aware: SomeoneElse legacy NOT moved' \
    test -f "${WRONG_LEGACY}"
check 'owner-aware: new file has the correct legacy entry' \
    grep -q '"ts":"correct-owner"' "${NEW_FILE}"
check_not 'owner-aware: new file does NOT contain wrong-owner entry' \
    grep -q '"ts":"wrong-owner"' "${NEW_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6c: 2-level legacy STILL works (no regression on existing path layout)
# ---------------------------------------------------------------------------
# This is a regression guard for Scenario 1: the glob extension MUST
# keep matching 2-level legacy paths. Re-runs Scenario 1's exact shape
# to make the regression coverage explicit.
printf 'Scenario 6c: 2-level legacy STILL migrates (regression guard)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/board-superpowers"
mkdir -p "${HOME_DIR}/.board-superpowers/somehost/board-superpowers"
mkdir -p "${REPO_ROOT}"
LEGACY_FILE="${HOME_DIR}/.board-superpowers/somehost/board-superpowers/audit-local.jsonl"
printf '{"ts":"2-level-still-works"}\n' > "${LEGACY_FILE}"

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

run_audit_write "${HOME_DIR}" "${REPO_ROOT}" '103' 'R' 'managing-board' '2-level-regress-guard'

check_not '2-level regression: legacy file moved' test -f "${LEGACY_FILE}"
check '2-level regression: new file exists' test -f "${NEW_FILE}"
check '2-level regression: legacy entry preserved' \
    grep -q '"ts":"2-level-still-works"' "${NEW_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 7: idempotent — second invocation does NOT re-emit migration log line
# ---------------------------------------------------------------------------
# Per PR #30 Human Verification TODO: confirm `bsp_log` migration line
# lands in stderr exactly ONCE. The first invocation discovers + moves
# the legacy file; the second invocation sees the new path exists and
# never enters the migration block, so no migration log line is emitted.
printf 'Scenario 7: migration log line emits exactly once (idempotent stderr)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
REPO_ROOT="${TMP}/checkout/board-superpowers"
mkdir -p "${HOME_DIR}/.board-superpowers/somehost/board-superpowers"
mkdir -p "${REPO_ROOT}"
LEGACY_FILE="${HOME_DIR}/.board-superpowers/somehost/board-superpowers/audit-local.jsonl"
printf '{"ts":"legacy"}\n' > "${LEGACY_FILE}"

NORMALIZED="$(normalize_path "${REPO_ROOT}")"
NEW_FILE="${HOME_DIR}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"

# First invocation — captures stderr, expects "migrated legacy file" line.
ERR1="$(bash -c "
    set -euo pipefail
    export HOME='${HOME_DIR}'
    source '${COMMON_SH}'
    bsp_audit_local_write '${REPO_ROOT}' '300' 'R' 'managing-board' 'first-emits-migration'
" 2>&1 1>/dev/null)"

check 'idempotent log: first invocation emits migration line' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'migrated legacy file'" -- "${ERR1}"
check 'idempotent log: legacy file moved after first invocation' \
    test ! -f "${LEGACY_FILE}"
check 'idempotent log: new file exists after first invocation' \
    test -f "${NEW_FILE}"

# Second invocation — no legacy left to migrate; stderr must NOT
# contain the migration log line.
ERR2="$(bash -c "
    set -euo pipefail
    export HOME='${HOME_DIR}'
    source '${COMMON_SH}'
    bsp_audit_local_write '${REPO_ROOT}' '301' 'R' 'managing-board' 'second-no-migration'
" 2>&1 1>/dev/null)"

check_not 'idempotent log: second invocation does NOT emit migration line' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'migrated legacy file'" -- "${ERR2}"
check_not 'idempotent log: second invocation does NOT emit "completed by another process" line' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'completed by another process'" -- "${ERR2}"
check_not 'idempotent log: second invocation does NOT emit "migration mv failed" warn' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'migration mv failed'" -- "${ERR2}"

# Also verify the new file grew by one line (the second append landed).
check 'idempotent log: new file has 3 lines (legacy + first + second)' \
    count_eq "${NEW_FILE}" 3

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
