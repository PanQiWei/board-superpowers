#!/usr/bin/env bash
# scripts/submit-pr.sh — open a PR with three-section contract enforced.
#
# Called by consuming-card skill (F-C12). Validates that the in-memory PR
# body contains the three required sections per
# docs/architecture/0002-product-features-and-flows/08-pr-contract.md
# AND per the enforcing-pr-contract atomic skill.
#
# Three required sections (order matters for review):
#   ## Automated Verification    (required, non-empty, ≥ 1 checked or unchecked item)
#   ## Human Verification TODO   (optional, but if present must not be filler)
#   ## Retro Notes               (required when reusable lessons exist; explicit "n/a" allowed)
#
# Args:
#   --title <text>       PR title (≤ 70 chars, action-style)
#   --body-file <path>   Path to a markdown file containing the PR body
#   --base <branch>      Base branch for the PR (default: main)
#   --card <N>           Card number — referenced in the auto-generated trailer
#
# Exit codes:
#   0 — PR opened
#   1 — body validation failed / gh failure / bad args

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

TITLE=""
BODY_FILE=""
BASE="main"
CARD=""

while [ $# -gt 0 ]; do
    case "$1" in
        --title)     TITLE="$2";     shift 2 ;;
        --body-file) BODY_FILE="$2"; shift 2 ;;
        --base)      BASE="$2";      shift 2 ;;
        --card)      CARD="$2";      shift 2 ;;
        *) bsp_die "unknown arg: $1" ;;
    esac
done

[ -n "${TITLE}" ]     || bsp_die "missing --title"
[ -n "${BODY_FILE}" ] || bsp_die "missing --body-file"
[ -n "${CARD}" ]      || bsp_die "missing --card"
[ -f "${BODY_FILE}" ] || bsp_die "body file not found: ${BODY_FILE}"

bsp_require_cmd gh
bsp_require_cmd python3

# --- Validate PR body shape ---------------------------------------------
#
# Validation rules live in skills/enforcing-pr-contract/references/
# validation-rules.md. This script enforces a subset; the full filler
# detection is delegated to the SKILL body.

# Pass BODY_FILE as the positional arg to `python3 -`. The arg MUST sit
# between `python3 -` and the here-doc opener: bash treats tokens after
# the closing here-doc delimiter as the *next* command, not as args to
# the here-doc-receiving command. The previous "PY\n${BODY_FILE})" form
# silently dropped the arg, producing IndexError on sys.argv[1] and a
# spurious "Permission denied" as bash tried to execute the body file.
VALIDATION_OUTPUT="$(python3 - "${BODY_FILE}" <<'PY'
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
    # Ensure the section has *some* content beyond the heading itself.
    pattern = re.escape(heading) + r"\s*\n+(.*?)(?=\n##\s|\Z)"
    m = re.search(pattern, body, re.DOTALL)
    if not m or not m.group(1).strip():
        errors.append(f"section is empty: {heading}")

# Filler detection — minimal subset (full set is in the SKILL body).
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
)" || bsp_die "PR body validation failed — fix before retry"

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
#   - if the body already contains `Closes|Fixes|Resolves #<CARD>`
#     (case-insensitive, conjugations Close/Fix/Resolve also accepted),
#     no second trailer is appended;
#   - otherwise, the canonical trailer is appended once.
TMP_BODY="$(mktemp)"
trap 'rm -f "${TMP_BODY}"' EXIT
cp "${BODY_FILE}" "${TMP_BODY}"

if python3 - "${TMP_BODY}" "${CARD}" <<'PY'
import re, sys
body = open(sys.argv[1]).read()
card = sys.argv[2]
keyword_re = re.compile(
    r"(?im)^\s*(?:Closes|Fixes|Resolves|Close|Fix|Resolve)\s+#" +
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
