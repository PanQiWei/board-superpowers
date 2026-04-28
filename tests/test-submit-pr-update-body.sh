#!/usr/bin/env bash
# tests/test-submit-pr-update-body.sh — exercise submit-pr.sh --update-body
# subcommand contract.
#
# Five scenarios per card #53 AC6:
#   (a) sanity — fresh PR-OPEN via submit-pr.sh leaves the canonical
#       Closes #<card> trailer in the body delivered to `gh pr create`.
#   (b) preservation — one --update-body invocation against a body that
#       lacks the trailer re-injects it before `gh pr edit`.
#   (c) idempotency — multiple consecutive --update-body invocations
#       leave exactly one trailer block in the final body (no
#       duplication / accumulation of `---` separators).
#   (d) refusal — --update-body refuses (exit 1) when the current PR
#       body lacks any auto-close keyword for the linked card; webhook
#       chain is unrecoverable in that case so re-injecting silently
#       would mislead the audit trail.
#   (e) wrong-card-number — --update-body with --card mismatching the
#       PR's linked card number fails fast (exit 1) without touching
#       `gh pr edit`.
#
# Hermeticity: tmp HOME, tmp git repo, fake `gh` PATH-shim that
# reads/writes a single PR_BODY_FILE. Never contacts real GitHub.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUBMIT_PR="${PLUGIN_ROOT}/scripts/submit-pr.sh"

if [ ! -f "${SUBMIT_PR}" ]; then
    printf 'FATAL: %s not found\n' "${SUBMIT_PR}" >&2
    exit 99
fi

TMPHOME="$(mktemp -d)"
TMPBIN="$(mktemp -d)"
TMPSCRATCH="$(mktemp -d)"
trap 'rm -rf "${TMPHOME}" "${TMPBIN}" "${TMPSCRATCH}"' EXIT

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

check_not() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        printf '  FAIL — %s (cmd unexpectedly succeeded)\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    else
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    fi
}

check_grep() {
    local label="$1"
    local pattern="$2"
    local file="$3"
    if [ -f "${file}" ] && grep -qE "${pattern}" "${file}"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s (pattern %q not in %s)\n' \
            "${label}" "${pattern}" "${file}" >&2
        FAIL=$((FAIL + 1))
    fi
}

count_grep() {
    # Print the count of lines matching $pattern in $file (0 when file missing).
    local pattern="$1"
    local file="$2"
    if [ -f "${file}" ]; then
        grep -cE "${pattern}" "${file}" || true
    else
        printf '0'
    fi
}

# ---------------------------------------------------------------------------
# Build fake gh shim
# ---------------------------------------------------------------------------
#
# State files (per-scenario reset via the SCENARIO_STATE_DIR env var the
# shim reads). The shim records the body of the most recent
# `gh pr create` / `gh pr edit` invocation in $PR_BODY_FILE, and emits it
# back on `gh pr view --json body --jq .body`.

cat > "${TMPBIN}/gh" <<'STUB'
#!/usr/bin/env bash
# Fake gh stub for submit-pr update-body tests.
set -euo pipefail
STATE_DIR="${SCENARIO_STATE_DIR:-/tmp/bsp-test-bad-state}"
PR_BODY_FILE="${STATE_DIR}/pr-body.md"
CALL_LOG="${STATE_DIR}/gh-calls.log"
mkdir -p "${STATE_DIR}"

printf '%s\n' "$*" >> "${CALL_LOG}"

case "${1:-}" in
    pr)
        shift
        case "${1:-}" in
            create)
                shift
                # Parse --body-file and write its content to PR_BODY_FILE.
                while [ $# -gt 0 ]; do
                    case "$1" in
                        --body-file) cp "$2" "${PR_BODY_FILE}"; shift 2 ;;
                        --title|--base) shift 2 ;;
                        *) shift ;;
                    esac
                done
                printf 'https://github.com/test/test/pull/123\n'
                exit 0
                ;;
            edit)
                shift
                # First positional is PR number.
                _PR="$1"; shift
                while [ $# -gt 0 ]; do
                    case "$1" in
                        --body-file) cp "$2" "${PR_BODY_FILE}"; shift 2 ;;
                        *) shift ;;
                    esac
                done
                printf 'edited PR #%s\n' "${_PR}"
                exit 0
                ;;
            view)
                shift
                # Args contain `<PR-N> --json body --jq .body`.
                # We just emit the recorded body.
                if [ -f "${PR_BODY_FILE}" ]; then
                    cat "${PR_BODY_FILE}"
                fi
                exit 0
                ;;
        esac
        ;;
esac
printf 'fake gh: unhandled command: %s\n' "$*" >&2
exit 1
STUB
chmod +x "${TMPBIN}/gh"

# ---------------------------------------------------------------------------
# Build a body file whose content is Contract-A compliant so submit-pr.sh
# regular mode validation passes. Lacks the trailer; submit-pr.sh injects.
# ---------------------------------------------------------------------------

CONTRACT_A_BODY="${TMPSCRATCH}/contract-a-body.md"
cat > "${CONTRACT_A_BODY}" <<'BODY'
## Summary

A concise summary of what this PR does for the test fixture.

## Automated Verification

- [x] `bash tests/test-submit-pr-update-body.sh` — pass

## Retro Notes

- Hermetic test fixture; no reusable lessons.
BODY

run_submit() {
    # Run submit-pr.sh with the fake gh on PATH and the given args.
    # Sets globals RC and OUT.
    local _state="$1"; shift
    set +e
    OUT="$(SCENARIO_STATE_DIR="${_state}" \
           HOME="${TMPHOME}" \
           PATH="${TMPBIN}:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
           bash "${SUBMIT_PR}" "$@" 2>&1)"
    RC=$?
    set -e
}

# ---------------------------------------------------------------------------
# Scenario (a) — sanity: fresh PR-OPEN injects canonical trailer
# ---------------------------------------------------------------------------
printf '\nScenario (a): fresh PR-OPEN leaves the canonical trailer\n'

STATE_A="${TMPSCRATCH}/state-a"
mkdir -p "${STATE_A}"
run_submit "${STATE_A}" \
    --title 'test fixture PR' \
    --body-file "${CONTRACT_A_BODY}" \
    --card 53

check "submit-pr.sh exits 0 on regular open" test "${RC}" -eq 0
check_grep "PR body delivered to gh pr create contains Closes #53" \
    '^Closes #53' "${STATE_A}/pr-body.md"
check_grep "PR body contains canonical separator before trailer" \
    '^---$' "${STATE_A}/pr-body.md"

TRAILER_COUNT_A="$(count_grep '^Closes #53' "${STATE_A}/pr-body.md")"
if [ "${TRAILER_COUNT_A}" = "1" ]; then
    printf '  PASS — exactly one Closes #53 line in PR body\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL — expected 1 Closes #53 line, got %s\n' "${TRAILER_COUNT_A}" >&2
    FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Scenario (b) — preservation: one --update-body re-injects the trailer
# ---------------------------------------------------------------------------
printf '\nScenario (b): one --update-body invocation preserves the trailer\n'

# Reuse state-a (PR was just "opened", body has trailer).
# Build a NEW body without the trailer (mimics a retro-note expansion that
# stripped the canonical block).
STRIPPED_BODY="${TMPSCRATCH}/stripped-body.md"
cat > "${STRIPPED_BODY}" <<'BODY'
## Summary

Updated summary after retro-note expansion.

## Automated Verification

- [x] `bash tests/test-submit-pr-update-body.sh` — pass

## Retro Notes

- Add a fresh lesson here that grew the body length.
- Another lesson worth recording.
BODY

run_submit "${STATE_A}" \
    --update-body \
    --pr 123 \
    --body-file "${STRIPPED_BODY}" \
    --card 53

check "exit 0 on first --update-body" test "${RC}" -eq 0
check_grep "trailer re-injected after update" '^Closes #53' "${STATE_A}/pr-body.md"
check_grep "updated body retains new retro-note content" \
    'Add a fresh lesson here' "${STATE_A}/pr-body.md"

TRAILER_COUNT_B="$(count_grep '^Closes #53' "${STATE_A}/pr-body.md")"
if [ "${TRAILER_COUNT_B}" = "1" ]; then
    printf '  PASS — exactly one Closes #53 line after one --update-body\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL — expected 1 trailer, got %s\n' "${TRAILER_COUNT_B}" >&2
    FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Scenario (c) — idempotency: multiple consecutive --update-body
# ---------------------------------------------------------------------------
printf '\nScenario (c): repeated --update-body keeps exactly one trailer\n'

# Run --update-body 3 more times back-to-back. Each time we feed a body
# that lacks the trailer; the script should idempotently append exactly
# one canonical trailer block.
for i in 1 2 3; do
    run_submit "${STATE_A}" \
        --update-body \
        --pr 123 \
        --body-file "${STRIPPED_BODY}" \
        --card 53
    check "iteration ${i}: exit 0" test "${RC}" -eq 0
done

TRAILER_COUNT_C="$(count_grep '^Closes #53' "${STATE_A}/pr-body.md")"
if [ "${TRAILER_COUNT_C}" = "1" ]; then
    printf '  PASS — still exactly one Closes #53 line after 3 more updates\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL — expected 1 trailer after idempotent updates, got %s\n' \
        "${TRAILER_COUNT_C}" >&2
    FAIL=$((FAIL + 1))
fi

SEPARATOR_COUNT_C="$(count_grep '^---$' "${STATE_A}/pr-body.md")"
if [ "${SEPARATOR_COUNT_C}" = "1" ]; then
    printf '  PASS — separator not duplicated across updates (one --- line)\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL — separator drift, found %s --- lines\n' "${SEPARATOR_COUNT_C}" >&2
    FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Scenario (d) — refusal: --update-body refuses on PR without OPEN trailer
# ---------------------------------------------------------------------------
printf '\nScenario (d): --update-body refuses when current PR body lacks trailer\n'

# New scenario state: simulate a PR opened via direct `gh pr create`
# (bypassing submit-pr.sh), so its body never had the trailer.
STATE_D="${TMPSCRATCH}/state-d"
mkdir -p "${STATE_D}"

cat > "${STATE_D}/pr-body.md" <<'BODY'
## Summary

This PR was opened via direct `gh pr create`; no trailer at OPEN time.

## Automated Verification

- [x] something
BODY

run_submit "${STATE_D}" \
    --update-body \
    --pr 999 \
    --body-file "${STRIPPED_BODY}" \
    --card 53

check_not "non-zero exit on PR without OPEN-time trailer" test "${RC}" -eq 0

if printf '%s' "${OUT}" | grep -qiE 'trailer|webhook|recover|manual'; then
    printf '  PASS — refusal message references the broken-webhook recovery path\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL — refusal message must point at the recovery context. stderr=%q\n' \
        "${OUT}" >&2
    FAIL=$((FAIL + 1))
fi

# Confirm no `gh pr edit` was issued — the body file should be unchanged.
if grep -q 'no trailer at OPEN time' "${STATE_D}/pr-body.md"; then
    printf '  PASS — gh pr edit was not invoked (body unchanged)\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL — body was mutated despite refusal\n' >&2
    FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Scenario (e) — wrong card number fails fast
# ---------------------------------------------------------------------------
printf '\nScenario (e): wrong --card vs PR-trailer fails fast\n'

# State E: PR body has Closes #53 trailer (opened via submit-pr.sh)
# AND a unique sentinel line we can use to detect mutation. We can't
# reuse state-a directly because the earlier scenarios already updated
# its body; this scenario needs a freshly-controlled fixture.
STATE_E="${TMPSCRATCH}/state-e"
mkdir -p "${STATE_E}"
cat > "${STATE_E}/pr-body.md" <<'BODY'
## Summary

state-e fixture sentinel: SCENARIO_E_ORIGINAL_BODY_KEEPS_THIS_LINE.

## Automated Verification

- [x] sentinel test

## Retro Notes

- sentinel.

---
Closes #53 — board-superpowers v0.4.0 claim trailer.
BODY

# Now invoke --update-body with --card 999 — the trailer lookup is
# card-specific, so the script should treat the PR body as "lacking the
# trailer for #999" and refuse.
run_submit "${STATE_E}" \
    --update-body \
    --pr 123 \
    --body-file "${STRIPPED_BODY}" \
    --card 999

check_not "non-zero exit on mismatched --card" test "${RC}" -eq 0

# Confirm the body was not edited — the sentinel line should still be
# there, and the new STRIPPED_BODY content (with "Add a fresh lesson
# here") should NOT have replaced it.
if grep -q 'SCENARIO_E_ORIGINAL_BODY_KEEPS_THIS_LINE' "${STATE_E}/pr-body.md" \
   && ! grep -q 'Add a fresh lesson here' "${STATE_E}/pr-body.md"; then
    printf '  PASS — body unchanged on mismatched-card refusal\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL — body was mutated despite mismatched-card refusal\n' >&2
    FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
