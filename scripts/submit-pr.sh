#!/usr/bin/env bash
# scripts/submit-pr.sh — open a PR with three-section contract enforced,
# OR update an open PR's body while preserving the canonical Closes
# trailer (Contract C).
#
# Called by consuming-card skill — Step 10 (PR open) and any retro-note
# expansion / reviewer-finding writeup that updates the body after PR
# open. Validates the three-section shape per
# docs/architecture/0002-product-features-and-flows/08-pr-contract.md and
# the enforcing-pr-contract atomic skill.
#
# Three required sections (order matters for review):
#   ## Automated Verification    (required, non-empty, ≥ 1 checked or unchecked item)
#   ## Human Verification TODO   (optional, but if present must not be filler)
#   ## Retro Notes               (required when reusable lessons exist; explicit "n/a" allowed)
#
# Modes:
#   create (default)    Open a new PR.
#   --update-body       Update an existing PR's body. Idempotently strips
#                       any tail-anchored Closes/Fixes/Resolves #<CARD>
#                       block and re-appends the canonical trailer, so
#                       post-OPEN body edits do not tear down the
#                       PR↔Issue link GitHub keys its merge → Issue-close
#                       webhook chain on. Refuses if the PR's CURRENT
#                       body has no matching trailer at all — that means
#                       the OPEN-time body never had it (e.g., PR opened
#                       via direct `gh pr create`), so the chain is
#                       unrecoverable for it and silently re-injecting
#                       would mislead the audit trail (manual recovery
#                       per consuming-card Step 12 stage a).
#
# Args:
#   --title <text>       PR title (create mode; ≤ 70 chars, action-style)
#   --body-file <path>   Path to a markdown file containing the PR body
#   --base <branch>      Base branch for the PR (create mode; default: main)
#   --card <N>           Card number — referenced in the trailer
#   --update-body        Switch to update-body mode (no value)
#   --pr <N>             PR number (required in update-body mode)
#
# Exit codes:
#   0 — PR opened (create) / body updated (update-body)
#   1 — validation failed / gh failure / bad args

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

MODE="create"
TITLE=""
BODY_FILE=""
BASE="main"
CARD=""
PR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --title)       TITLE="$2";     shift 2 ;;
        --body-file)   BODY_FILE="$2"; shift 2 ;;
        --base)        BASE="$2";      shift 2 ;;
        --card)        CARD="$2";      shift 2 ;;
        --pr)          PR="$2";        shift 2 ;;
        --update-body) MODE="update-body"; shift ;;
        *) bsp_die "unknown arg: $1" ;;
    esac
done

[ -n "${BODY_FILE}" ] || bsp_die "missing --body-file"
[ -n "${CARD}" ]      || bsp_die "missing --card"
[ -f "${BODY_FILE}" ] || bsp_die "body file not found: ${BODY_FILE}"

bsp_require_cmd gh
bsp_require_cmd python3

# --- shared: Contract A body validation ---------------------------------
#
# Validates the markdown file at $1 satisfies Contract A (three-section
# shape — `## Automated Verification` mandatory + non-empty + non-filler;
# `## Human Verification TODO` optional but non-filler if present;
# `## Retro Notes` mandatory + non-empty). Used by both create mode (PR
# OPEN) and update-body mode (post-OPEN body update). Validation rules
# live in skills/enforcing-pr-contract/references/validation-rules.md;
# this enforces the regex subset.
#
# Exits 0 on pass with a one-line `PR body validation passed` on stdout;
# exits non-zero on fail with `FAIL: <reason>` lines on stderr. The
# python heredoc must NOT depend on shell vars beyond the file path.

bsp_validate_pr_body() {
    python3 - "$1" <<'PY'
import re, sys
body = open(sys.argv[1]).read()

required = [
    ('## Automated Verification', True),
    ('## Human Verification TODO', False),
    ('## Retro Notes', True),
]
errors = []
for heading, mandatory in required:
    if heading not in body:
        if mandatory:
            errors.append(f"missing required section: {heading}")
        continue
    pattern = re.escape(heading) + r"\s*\n+(.*?)(?=\n##\s|\Z)"
    m = re.search(pattern, body, re.DOTALL)
    if not m or not m.group(1).strip():
        errors.append(f"section is empty: {heading}")

filler_phrases = [
    "TBD", "todo: write tests", "no notes", "(none)", "n/a", "N/A",
]
auto_section_match = re.search(
    r"## Automated Verification\s*\n+(.*?)(?=\n##\s|\Z)",
    body, re.DOTALL)
if auto_section_match:
    auto_text = auto_section_match.group(1).strip()
    if any(f.lower() == auto_text.lower() for f in filler_phrases):
        errors.append("Automated Verification is filler — list the actual checks run")

if errors:
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    sys.exit(1)
print("PR body validation passed")
PY
}

# --- update-body mode ---------------------------------------------------
#
# The Contract C trailer (Closes/Fixes/Resolves #<CARD>) is what GitHub
# uses to register the PR↔Issue link in `closingIssuesReferences`. The
# link is re-derived on every body update — `gh pr edit` overwriting
# the trailer (e.g., a retro-note expansion that drops the trailing
# block) silently de-registers the link, and the next merge fires
# without the auto-close webhook chain. Once that has happened, the
# Issue must be closed manually and ProjectV2 Status flipped manually
# (consuming-card Step 12 stage a).
#
# This branch is the sanctioned update path: it strips ONLY the
# tail-anchored canonical block (mid-body Closes-style references in
# user prose are preserved), re-appends the canonical trailer, and
# writes back via `gh pr edit`. Repeated invocations against bodies
# that lack the trailer accumulate exactly one canonical block.
#
# Refuses when the CURRENT body has no matching trailer for the linked
# card — that diagnoses a PR that never had the trailer at OPEN, for
# which silently re-injecting would imply a webhook recovery that
# GitHub does not provide.

if [ "${MODE}" = "update-body" ]; then
    [ -n "${PR}" ] || bsp_die "missing --pr (required in --update-body mode)"

    # Contract A applies to body updates too — without this guard a
    # retro-note expansion that accidentally drops `## Automated
    # Verification` / `## Retro Notes` could overwrite the PR body and
    # silently violate the three-section contract. Fail before any
    # `gh pr edit` call so the live PR body never observes the bad shape.
    VALIDATION_OUTPUT="$(bsp_validate_pr_body "${BODY_FILE}")" \
        || bsp_die "PR body validation failed in update-body mode — fix before retry"
    bsp_log "${VALIDATION_OUTPUT}"

    CURRENT_BODY="$(gh pr view "${PR}" --json body --jq '.body')"

    if ! CARD="${CARD}" CURRENT_BODY="${CURRENT_BODY}" python3 - <<'PY'
import os, re, sys
body = os.environ['CURRENT_BODY']
card = os.environ['CARD']
keyword_re = re.compile(
    r'(?im)^\s*(?:Close[ds]?|Fix(?:e[ds])?|Resolve[ds]?)\s+#' +
    re.escape(card) + r'\b'
)
sys.exit(0 if keyword_re.search(body) else 1)
PY
    then
        bsp_die "PR #${PR} current body has no Closes/Fixes/Resolves #${CARD} trailer — the PR↔Issue auto-close webhook chain is unrecoverable for this PR. Manual recovery required (see consuming-card Step 12 stage a). Refusing to silently re-inject (would mislead audit trail)."
    fi

    NEW_BODY="$(mktemp)"
    trap 'rm -f "${NEW_BODY}"' EXIT

    CARD="${CARD}" python3 - "${BODY_FILE}" > "${NEW_BODY}" <<'PY'
import os, re, sys
body = open(sys.argv[1]).read()
card = os.environ['CARD']
# Strip ONLY the tail-anchored canonical trailer block (separator +
# auto-close keyword line for THIS card). Anchored to end-of-string
# via \Z (NOT (?m) + $, which would match end of any line and silently
# delete mid-body user prose that happens to start with `Closes #N`).
# The `\s*` before `\Z` consumes the trailer's own final newline; on
# mid-body matches `\s*` cannot reach `\Z` because non-whitespace
# follows on subsequent lines, so user prose is preserved.
trailer_block_re = re.compile(
    r'(?i)(?:\n+---\s*)?\n+[ \t]*(?:Close[ds]?|Fix(?:e[ds])?|Resolve[ds]?)\s+#' +
    re.escape(card) +
    r'[^\n]*\s*\Z'
)
while True:
    stripped = trailer_block_re.sub('', body)
    if stripped == body:
        break
    body = stripped
body = body.rstrip()
sys.stdout.write(body)
sys.stdout.write('\n\n---\n')
sys.stdout.write('Closes #' + card + ' — board-superpowers v0.4.0 claim trailer.\n')
PY

    bsp_log "updating PR #${PR} body (idempotent Closes #${CARD} trailer)"
    gh pr edit "${PR}" --body-file "${NEW_BODY}"
    exit 0
fi

# --- create mode (default) ----------------------------------------------

[ -n "${TITLE}" ] || bsp_die "missing --title"

# --- Validate PR body shape (Contract A) --------------------------------
#
# Delegates to bsp_validate_pr_body (defined above). Validation rules
# live in skills/enforcing-pr-contract/references/validation-rules.md.

VALIDATION_OUTPUT="$(bsp_validate_pr_body "${BODY_FILE}")" \
    || bsp_die "PR body validation failed — fix before retry"
bsp_log "${VALIDATION_OUTPUT}"

# --- Contract C — PR↔Issue auto-close keyword (idempotent) -------------
#
# GitHub fires the PR-merge → Issue-close → ProjectV2 Auto-close webhook
# chain ONLY when the PR body contains a `Closes #<N>` / `Fixes #<N>` /
# `Resolves #<N>` keyword AT PR-OPEN TIME. Retroactively appending the
# keyword after PR open does NOT retrigger the webhook (observed on PR
# #42 / card #34 — direct `gh pr create` bypassed this script, missed
# the trailer at OPEN time, broke the auto-close chain).
#
# This script idempotently injects the canonical `Closes #<N>` trailer
# at PR-OPEN time:
#   - if the body already contains any of the 9 GitHub-sanctioned
#     auto-close keyword forms (close / closes / closed / fix / fixes /
#     fixed / resolve / resolves / resolved — all case-insensitive)
#     referencing the linked card number, no second trailer is appended;
#   - otherwise, the canonical `Closes #<CARD>` trailer is appended once.
TMP_BODY="$(mktemp)"
trap 'rm -f "${TMP_BODY}"' EXIT
cp "${BODY_FILE}" "${TMP_BODY}"

if python3 - "${TMP_BODY}" "${CARD}" <<'PY'
import re, sys
body = open(sys.argv[1]).read()
card = sys.argv[2]
# Match all 9 GitHub-sanctioned forms — close|closes|closed|fix|fixes|
# fixed|resolve|resolves|resolved. Built via 3 noun-roots × 3 inflections
# (base / s / d|ed). See https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue
keyword_re = re.compile(
    r"(?im)^\s*(?:Close[ds]?|Fix(?:e[ds])?|Resolve[ds]?)\s+#" +
    re.escape(card) + r"\b"
)
sys.exit(0 if keyword_re.search(body) else 1)
PY
then
    bsp_log "Contract C — close-keyword for #${CARD} already present, skipping trailer injection"
else
    bsp_log "Contract C — injecting canonical Closes #${CARD} trailer at PR-OPEN time"
    {
        printf '\n\n---\n'
        printf 'Closes #%s — board-superpowers v0.4.0 claim trailer.\n' "${CARD}"
    } >> "${TMP_BODY}"
fi

# --- Open the PR ---------------------------------------------------------
bsp_log "opening PR (base=${BASE}, card=#${CARD})"
gh pr create --title "${TITLE}" --body-file "${TMP_BODY}" --base "${BASE}"
