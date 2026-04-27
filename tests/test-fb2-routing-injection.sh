#!/usr/bin/env bash
# tests/test-fb2-routing-injection.sh — assert F-B2 step 4
# (routing block injection + tamper hash) satisfies the contract per
# docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § 1.5.2 step 4 + 02-hook-contracts.md § "Intent-injection markers"
# (marker pair grammar) + 03-config-schemas.md (state.yml
# routing_blocks[] schema).
#
# Scope: Slice 4 of Card 2 — bsp_inject_routing_block helper in
# scripts/lib/common.sh + bootstrap-project.sh step 4 invocation +
# state.yml routing_blocks[] population.
#
# Helper-level scenarios (1-13):
#   1. Fresh AGENTS.md (target absent): file created with marker-wrapped
#      content, hash printed to stdout.
#   2. Fresh CLAUDE.md too: both files created independently.
#   3. AGENTS.md exists with NO markers: block APPENDED with markers,
#      original content preserved above the new block.
#   4. AGENTS.md exists with BOTH markers: content between markers
#      REPLACED, content outside markers preserved verbatim.
#   5. AGENTS.md exists with OPENING marker but NO CLOSING: exit 5,
#      verbatim error message printed to stderr (with line number of
#      the present marker), file unchanged.
#   6. AGENTS.md exists with CLOSING marker but NO OPENING: exit 5,
#      same orphan error with the closing marker's actual line number
#      printed (no `?` placeholder), file unchanged.
#   7. CRLF source-of-truth file (with fence sentinels): helper
#      LF-normalizes for hashing AND for injection.
#   8. UTF-8 BOM at start of AGENTS.md: BOM preserved at byte 0 after
#      injection; BOM NOT in the hashed region.
#   9. Hash determinism: same source content → same hash across two
#      independent target injections.
#  10. Idempotent re-run: inject into AGENTS.md, then inject again
#      with same source. Same hash; resulting bytes byte-identical.
#  11. Source file MISSING fence markers: helper aborts with fatal
#      error pointing at source file path (exit 1), no target written.
#  12. Target file with TWO marker pairs: exit 5 with multi-pair error,
#      file unchanged.
#  13. Source file with literal target marker INSIDE the fence:
#      helper aborts with fatal error pointing at source path (exit 1).
#
# End-to-end scenarios (14-15):
#  14. Full F-B2 against tmp repo with no AGENTS.md / CLAUDE.md:
#      state.yml routing_blocks[] has 2 entries with correct hashes.
#  15. Full F-B2 against tmp repo where AGENTS.md has orphan markers:
#      F-B2 aborts non-zero; state.yml NOT written.
#
# Hermeticity: tmp dirs only; helper-level tests source common.sh
# directly; end-to-end tests use the same stub-gh / tmp HOME shape as
# test-fb2-byo-rdbms.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMMON_LIB="${PLUGIN_ROOT_REAL}/scripts/lib/common.sh"
SOURCE_FILE_REAL="${PLUGIN_ROOT_REAL}/skills/using-board-superpowers/references/agentsmd-routing.md"
BOOTSTRAP_SCRIPT="${PLUGIN_ROOT_REAL}/scripts/bootstrap-project.sh"

if [ ! -f "${COMMON_LIB}" ]; then
    printf 'FATAL: %s not found\n' "${COMMON_LIB}" >&2
    exit 99
fi
if [ ! -f "${SOURCE_FILE_REAL}" ]; then
    printf 'FATAL: %s not found\n' "${SOURCE_FILE_REAL}" >&2
    exit 99
fi

PASS=0
FAIL=0

check() {
    local label="$1"; shift
    if "$@"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

check_not() {
    local label="$1"; shift
    if "$@"; then
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    else
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    fi
}

assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "${actual}" = "${expected}" ]; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n    expected: %q\n    actual:   %q\n' \
            "${label}" "${expected}" "${actual}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# Source the helper into a subshell-style invocation. We can't just
# source common.sh into THIS shell because it might pollute global
# state; instead each call invokes a fresh subshell that sources it.
inject_in_subshell() {
    local target="$1"
    local source="$2"
    bash -c '
        set -euo pipefail
        SCRIPT_DIR="$(cd "$(dirname "$1")" && pwd)"
        # shellcheck source=/dev/null
        . "$1"
        bsp_inject_routing_block "$2" "$3"
    ' _ "${COMMON_LIB}" "${target}" "${source}"
}

# Cross-platform sha256 of a file
sha256_of_file() {
    python3 -c '
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
' "$1"
}

# ---------------------------------------------------------------------------
# Scenario 1: Fresh AGENTS.md — target absent, file created
# ---------------------------------------------------------------------------
printf 'Scenario 1: Fresh AGENTS.md created from scratch\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

set +e
HASH1="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>"${TMP}/err1")"
RC=$?
set -e

assert_eq 'fresh AGENTS.md: exit 0' '0' "${RC}"
check 'fresh AGENTS.md: file created' test -f "${TARGET}"
check 'fresh AGENTS.md: opening marker present' \
    grep -Fq '<!-- board-superpowers:routing -->' "${TARGET}"
check 'fresh AGENTS.md: closing marker present' \
    grep -Fq '<!-- /board-superpowers:routing -->' "${TARGET}"
check 'fresh AGENTS.md: stdout produced 64-char hex hash' \
    bash -c "printf '%s' \"\$1\" | grep -Eq '^[0-9a-f]{64}$'" _ "${HASH1}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 2: Fresh CLAUDE.md alongside AGENTS.md — both created independently
# ---------------------------------------------------------------------------
printf 'Scenario 2: Fresh CLAUDE.md alongside AGENTS.md\n'

TMP="$(mktemp -d)"
AGENTS="${TMP}/AGENTS.md"
CLAUDE="${TMP}/CLAUDE.md"

set +e
HA="$(inject_in_subshell "${AGENTS}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
HC="$(inject_in_subshell "${CLAUDE}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
set -e

check 'fresh both: AGENTS.md exists' test -f "${AGENTS}"
check 'fresh both: CLAUDE.md exists' test -f "${CLAUDE}"
assert_eq 'fresh both: hashes equal (same source)' "${HA}" "${HC}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 3: AGENTS.md exists, NO markers — APPEND with markers
# ---------------------------------------------------------------------------
printf 'Scenario 3: AGENTS.md exists without markers — APPEND\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

cat > "${TARGET}" <<'EOF'
# Existing AGENTS.md

This is some pre-existing project content. It MUST be preserved.

## A second section

End of pre-existing content.
EOF
ORIG_BYTES="$(wc -c < "${TARGET}")"

set +e
HASH3="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
RC=$?
set -e

assert_eq 'no-markers append: exit 0' '0' "${RC}"
check 'no-markers append: original content preserved' \
    grep -Fq 'This is some pre-existing project content' "${TARGET}"
check 'no-markers append: original second section preserved' \
    grep -Fq '## A second section' "${TARGET}"
check 'no-markers append: opening marker present' \
    grep -Fq '<!-- board-superpowers:routing -->' "${TARGET}"
check 'no-markers append: closing marker present' \
    grep -Fq '<!-- /board-superpowers:routing -->' "${TARGET}"
NEW_BYTES="$(wc -c < "${TARGET}")"
check 'no-markers append: file grew (block was appended)' \
    test "${NEW_BYTES}" -gt "${ORIG_BYTES}"
# Markers must come AFTER the original content (append, not prepend).
ORIG_LINE_NUM="$(grep -n 'A second section' "${TARGET}" | head -n1 | cut -d: -f1)"
OPEN_LINE_NUM="$(grep -n '<!-- board-superpowers:routing -->' "${TARGET}" | head -n1 | cut -d: -f1)"
check 'no-markers append: markers AFTER original content' \
    test "${OPEN_LINE_NUM}" -gt "${ORIG_LINE_NUM}"
check 'no-markers append: stdout is 64-char hex' \
    bash -c "printf '%s' \"\$1\" | grep -Eq '^[0-9a-f]{64}$'" _ "${HASH3}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 4: AGENTS.md exists with BOTH markers — REPLACE between markers
# ---------------------------------------------------------------------------
printf 'Scenario 4: AGENTS.md exists with both markers — REPLACE\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

cat > "${TARGET}" <<'EOF'
# Existing AGENTS.md

Pre-block content goes here.

<!-- board-superpowers:routing -->
This is a STALE routing block that MUST be replaced wholesale.
Old plugin version v0.0.1.
<!-- /board-superpowers:routing -->

Post-block content goes here.
EOF

set +e
HASH4="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
RC=$?
set -e

assert_eq 'both-markers replace: exit 0' '0' "${RC}"
check_not 'both-markers replace: stale content removed' \
    grep -Fq 'STALE routing block' "${TARGET}"
check_not 'both-markers replace: stale version string removed' \
    grep -Fq 'v0.0.1' "${TARGET}"
check 'both-markers replace: pre-block content preserved' \
    grep -Fq 'Pre-block content goes here' "${TARGET}"
check 'both-markers replace: post-block content preserved' \
    grep -Fq 'Post-block content goes here' "${TARGET}"
# Idempotency: hash3 (append) and hash4 (replace) should equal — same source.
assert_eq 'both-markers replace: hash matches scenario-3 hash (same source)' \
    "${HASH3}" "${HASH4}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 5: Orphan opening marker — exit 5
# ---------------------------------------------------------------------------
printf 'Scenario 5: Orphan opening marker — exit 5\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

cat > "${TARGET}" <<'EOF'
# Existing AGENTS.md

Some content.

<!-- board-superpowers:routing -->
Routing content but no closing marker after this.

End of file (no closing marker).
EOF

ORIG="$(cat "${TARGET}")"

set +e
ERR_OUT="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>&1 1>/dev/null)"
RC=$?
set -e

assert_eq 'orphan-open: exit 5' '5' "${RC}"
check 'orphan-open: error mentions "F-B2 step 4"' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'F-B2 step 4'" _ "${ERR_OUT}"
check 'orphan-open: error mentions "cannot proceed"' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'cannot proceed'" _ "${ERR_OUT}"
check 'orphan-open: error names the target file path' \
    bash -c "printf '%s' \"\$1\" | grep -Fq \"\$2\"" _ "${ERR_OUT}" "${TARGET}"
check 'orphan-open: error mentions Recovery options' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'Recovery options'" _ "${ERR_OUT}"
check 'orphan-open: error mentions "state.yml" not written' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'state.yml'" _ "${ERR_OUT}"
assert_eq 'orphan-open: file unchanged' "${ORIG}" "$(cat "${TARGET}")"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6: Orphan closing marker — exit 5, error names actual line number
# ---------------------------------------------------------------------------
printf 'Scenario 6: Orphan closing marker — exit 5 with line number\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

cat > "${TARGET}" <<'EOF'
# Existing AGENTS.md

Some content with a stray closing marker only.

<!-- /board-superpowers:routing -->

End of file.
EOF

# The closing marker is on line 5 of the file above.
EXPECTED_LINE=5

ORIG="$(cat "${TARGET}")"

set +e
ERR_OUT="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>&1 1>/dev/null)"
RC=$?
set -e

assert_eq 'orphan-close: exit 5' '5' "${RC}"
check 'orphan-close: error mentions "F-B2 step 4"' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'F-B2 step 4'" _ "${ERR_OUT}"
check 'orphan-close: error names "closing" as the present marker kind' \
    bash -c "printf '%s' \"\$1\" | grep -Fq \"closing marker '<!-- /board-superpowers:routing -->'\"" _ "${ERR_OUT}"
# shellcheck disable=SC2016  # backticks here are markdown, not command substitution
check 'orphan-close: error prints actual line number (no `?` placeholder)' \
    bash -c "printf '%s' \"\$1\" | grep -Eq \"present at line ${EXPECTED_LINE}\"" _ "${ERR_OUT}"
# shellcheck disable=SC2016  # backticks here are markdown, not command substitution
check_not 'orphan-close: error does NOT contain a `?` placeholder for line number' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'present at line ?'" _ "${ERR_OUT}"
assert_eq 'orphan-close: file unchanged' "${ORIG}" "$(cat "${TARGET}")"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 7: CRLF source — helper LF-normalizes for hashing AND injection
# ---------------------------------------------------------------------------
printf 'Scenario 7: CRLF source-of-truth file — LF normalization\n'

TMP="$(mktemp -d)"
SOURCE_LF="${TMP}/source-lf.md"
SOURCE_CRLF="${TMP}/source-crlf.md"
TARGET_LF="${TMP}/AGENTS-lf.md"
TARGET_CRLF="${TMP}/AGENTS-crlf.md"

# LF source — fence-bounded routing block content.
printf '# header docstring\n\n<!-- routing-block:start -->\nline one\nline two\nline three\n<!-- routing-block:end -->\n\nfooter notes\n' > "${SOURCE_LF}"
# Same content with CRLF endings everywhere.
printf '# header docstring\r\n\r\n<!-- routing-block:start -->\r\nline one\r\nline two\r\nline three\r\n<!-- routing-block:end -->\r\n\r\nfooter notes\r\n' > "${SOURCE_CRLF}"

set +e
H_LF="$(inject_in_subshell "${TARGET_LF}" "${SOURCE_LF}" 2>/dev/null)"
H_CRLF="$(inject_in_subshell "${TARGET_CRLF}" "${SOURCE_CRLF}" 2>/dev/null)"
set -e

check 'CRLF normalize: target_lf created' test -f "${TARGET_LF}"
check 'CRLF normalize: target_crlf created' test -f "${TARGET_CRLF}"
assert_eq 'CRLF normalize: hashes equal (LF-only contract)' \
    "${H_LF}" "${H_CRLF}"
# Resulting target file must contain NO CR byte (LF-only).
check_not 'CRLF normalize: target contains no CR bytes' \
    bash -c "tr -dc '\r' < \"\$1\" | grep -q '.'" _ "${TARGET_CRLF}"
# Injected content must be exactly the three fence-bounded lines, NOT
# the docstring header or footer notes (those live outside the fence).
check_not 'CRLF normalize: docstring header NOT injected' \
    grep -Fq 'header docstring' "${TARGET_LF}"
check_not 'CRLF normalize: footer notes NOT injected' \
    grep -Fq 'footer notes' "${TARGET_LF}"
check 'CRLF normalize: fence-bounded line one IS injected' \
    grep -Fq 'line one' "${TARGET_LF}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 8: UTF-8 BOM at byte 0 of target — preserved; not hashed
# ---------------------------------------------------------------------------
printf 'Scenario 8: UTF-8 BOM at start of AGENTS.md — preserved\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

# Build a target with BOM + both markers + stale content between.
python3 - "${TARGET}" <<'PY'
import sys
p = sys.argv[1]
data = b'\xef\xbb\xbf' + b"# Title\n\n<!-- board-superpowers:routing -->\nold\n<!-- /board-superpowers:routing -->\n\nMore content.\n"
open(p, "wb").write(data)
PY

set +e
HASH8="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
RC=$?
set -e

assert_eq 'BOM preserve: exit 0' '0' "${RC}"
# Verify byte 0..2 are still EF BB BF.
BOM_HEX="$(python3 -c "import sys; b=open(sys.argv[1],'rb').read(3); print(b.hex())" "${TARGET}")"
assert_eq 'BOM preserve: bytes 0-2 are EF BB BF' 'efbbbf' "${BOM_HEX}"
# Hash must equal scenario-3 hash (same source-of-truth file).
assert_eq 'BOM preserve: hash equals canonical source hash' \
    "${HASH3}" "${HASH8}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 9: Hash determinism across two independent injections
# ---------------------------------------------------------------------------
printf 'Scenario 9: Hash determinism across two injections\n'

TMP="$(mktemp -d)"
T1="${TMP}/A.md"
T2="${TMP}/B.md"

set +e
H1="$(inject_in_subshell "${T1}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
H2="$(inject_in_subshell "${T2}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
set -e

assert_eq 'hash determinism: H1 == H2' "${H1}" "${H2}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 10: Idempotent re-run (inject twice; bytes identical)
# ---------------------------------------------------------------------------
printf 'Scenario 10: Idempotent re-run produces byte-identical output\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

set +e
HA="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
SHA_A="$(sha256_of_file "${TARGET}")"
HB="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
SHA_B="$(sha256_of_file "${TARGET}")"
set -e

assert_eq 'idempotent: same hash returned both times' "${HA}" "${HB}"
assert_eq 'idempotent: file bytes byte-identical after second inject' \
    "${SHA_A}" "${SHA_B}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 11: Source file MISSING fence markers — fatal error, exit 1
# ---------------------------------------------------------------------------
printf 'Scenario 11: Source missing fence markers — fatal error\n'

TMP="$(mktemp -d)"
SOURCE_NO_FENCE="${TMP}/no-fence.md"
TARGET="${TMP}/AGENTS.md"

# Source without any fence sentinels.
cat > "${SOURCE_NO_FENCE}" <<'EOF'
# Just a markdown file with no fence sentinels.

Some routing-block-ish content but no fences anywhere.
EOF

set +e
ERR_OUT="$(inject_in_subshell "${TARGET}" "${SOURCE_NO_FENCE}" 2>&1 1>/dev/null)"
RC=$?
set -e

assert_eq 'no-fence: exit 1' '1' "${RC}"
check 'no-fence: error mentions "missing fence markers"' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'missing fence markers'" _ "${ERR_OUT}"
check 'no-fence: error names source file path' \
    bash -c "printf '%s' \"\$1\" | grep -Fq \"\$2\"" _ "${ERR_OUT}" "${SOURCE_NO_FENCE}"
check 'no-fence: error mentions routing-block:start sentinel' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'routing-block:start'" _ "${ERR_OUT}"
check 'no-fence: error mentions routing-block:end sentinel' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'routing-block:end'" _ "${ERR_OUT}"
check_not 'no-fence: target file NOT created' test -f "${TARGET}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 12: Target file with TWO marker pairs — multi-pair detection, exit 5
# ---------------------------------------------------------------------------
printf 'Scenario 12: Target with two marker pairs — multi-pair error\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

cat > "${TARGET}" <<'EOF'
# Existing AGENTS.md

First copy of routing block:

<!-- board-superpowers:routing -->
Old content #1.
<!-- /board-superpowers:routing -->

Some intervening content.

Second copy (oops, copy-paste duplication):

<!-- board-superpowers:routing -->
Old content #2.
<!-- /board-superpowers:routing -->

End of file.
EOF

ORIG="$(cat "${TARGET}")"

set +e
ERR_OUT="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>&1 1>/dev/null)"
RC=$?
set -e

assert_eq 'multi-pair: exit 5' '5' "${RC}"
check 'multi-pair: error mentions "F-B2 step 4"' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'F-B2 step 4'" _ "${ERR_OUT}"
check 'multi-pair: error reports 2 opening markers' \
    bash -c "printf '%s' \"\$1\" | grep -Fq '2 opening markers'" _ "${ERR_OUT}"
check 'multi-pair: error reports 2 closing markers' \
    bash -c "printf '%s' \"\$1\" | grep -Fq '2 closing markers'" _ "${ERR_OUT}"
check 'multi-pair: error mentions "Expected exactly 0 or 1 of each"' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'Expected exactly 0 or 1 of each'" _ "${ERR_OUT}"
check 'multi-pair: error mentions Recovery options' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'Recovery options'" _ "${ERR_OUT}"
check 'multi-pair: error names the target file path' \
    bash -c "printf '%s' \"\$1\" | grep -Fq \"\$2\"" _ "${ERR_OUT}" "${TARGET}"
assert_eq 'multi-pair: file unchanged' "${ORIG}" "$(cat "${TARGET}")"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 13: Source has literal target marker INSIDE the fence — abort
# ---------------------------------------------------------------------------
printf 'Scenario 13: Source has nested target marker inside fence — abort\n'

TMP="$(mktemp -d)"
SOURCE_NESTED="${TMP}/source-nested.md"
TARGET="${TMP}/AGENTS.md"

# Build source where the fenced content includes a literal target
# marker — this would otherwise inject nested markers.
cat > "${SOURCE_NESTED}" <<'EOF'
# Source-of-truth with a maintainer mistake.

<!-- routing-block:start -->
Some routing content.

Oops, a literal target marker leaked into the body:
<!-- board-superpowers:routing -->

More content.
<!-- routing-block:end -->

Maintainer notes.
EOF

set +e
ERR_OUT="$(inject_in_subshell "${TARGET}" "${SOURCE_NESTED}" 2>&1 1>/dev/null)"
RC=$?
set -e

assert_eq 'marker-in-source: exit 1' '1' "${RC}"
check 'marker-in-source: error mentions "literal target-file marker"' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'literal target-file marker'" _ "${ERR_OUT}"
check 'marker-in-source: error names source file path' \
    bash -c "printf '%s' \"\$1\" | grep -Fq \"\$2\"" _ "${ERR_OUT}" "${SOURCE_NESTED}"
check 'marker-in-source: error mentions a line number' \
    bash -c "printf '%s' \"\$1\" | grep -Eq 'at line [0-9]+'" _ "${ERR_OUT}"
check_not 'marker-in-source: target file NOT created' test -f "${TARGET}"

rm -rf "${TMP}"

# ===========================================================================
# End-to-end: full F-B2 invocation populates state.yml routing_blocks[]
# ===========================================================================

# Replicate the make_stub_plugin_root + stub_gh + canonical Status helpers
# from test-fb2-byo-rdbms.sh / test-fb2-per-repo.sh.

make_stub_plugin_root() {
    local version="$1"
    local target_dir="$2"
    mkdir -p "${target_dir}/.claude-plugin"
    cat > "${target_dir}/.claude-plugin/plugin.json" <<EOF
{
  "name": "board-superpowers",
  "version": "${version}",
  "description": "stub for tests",
  "license": "MIT"
}
EOF
    mkdir -p "${target_dir}/scripts/lib"
    cp "${PLUGIN_ROOT_REAL}/scripts/lib/common.sh" "${target_dir}/scripts/lib/common.sh"
    cp "${PLUGIN_ROOT_REAL}/scripts/setup-labels.sh" "${target_dir}/scripts/setup-labels.sh"
    cp "${BOOTSTRAP_SCRIPT}" "${target_dir}/scripts/bootstrap-project.sh"
    chmod +x "${target_dir}/scripts/setup-labels.sh"
    chmod +x "${target_dir}/scripts/bootstrap-project.sh"

    # The injection source-of-truth file MUST live at the canonical
    # path inside the plugin tree. Copy it.
    mkdir -p "${target_dir}/skills/using-board-superpowers/references"
    cp "${SOURCE_FILE_REAL}" \
       "${target_dir}/skills/using-board-superpowers/references/agentsmd-routing.md"
}

init_tmp_repo() {
    local repo_root="$1"
    local owner_name="$2"
    mkdir -p "${repo_root}"
    git -C "${repo_root}" init --quiet
    git -C "${repo_root}" remote add origin "https://github.com/${owner_name}.git"
    git -C "${repo_root}" config user.email "test@example.com"
    git -C "${repo_root}" config user.name  "test"
}

stub_gh() {
    local dir="$1"
    cat > "${dir}/gh" <<'STUB'
#!/usr/bin/env bash
set -eu

STUB_DIR="$(cd "$(dirname "$0")" && pwd)"
LABELS_FILE="${STUB_DIR}/labels.json"
STATUS_OPTS_FILE="${STUB_DIR}/status_opts"

if [ ! -f "${LABELS_FILE}" ]; then
    printf '[]\n' > "${LABELS_FILE}"
fi

case "${1:-}" in
    label)
        shift
        case "${1:-}" in
            list)
                cat "${LABELS_FILE}"
                exit 0
                ;;
            create)
                shift
                NAME="${1:?label create needs NAME}"
                shift
                EXISTS="$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print('1' if any(l['name']==sys.argv[2] for l in data) else '0')
" "${LABELS_FILE}" "${NAME}")"
                if [ "${EXISTS}" = "1" ]; then
                    printf 'error: name "%s" already used by another label\n' "${NAME}" >&2
                    exit 1
                fi
                python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data.append({'name': sys.argv[2]})
with open(sys.argv[1], 'w') as f:
    json.dump(data, f)
" "${LABELS_FILE}" "${NAME}"
                exit 0
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
    project)
        shift
        case "${1:-}" in
            field-list)
                python3 -c "
import json, sys, os
opts_path = sys.argv[1]
options = []
if os.path.exists(opts_path):
    with open(opts_path) as f:
        for line in f:
            line = line.rstrip('\n')
            if line:
                options.append({'id': 'opt-' + line.replace(' ', '-').lower(),
                                'name': line})
fields = []
if options:
    fields.append({'id': 'fld-status', 'name': 'Status', 'options': options})
print(json.dumps({'fields': fields}))
" "${STATUS_OPTS_FILE}"
                exit 0
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${dir}/gh"
}

CANONICAL_STATUS="Backlog
Ready
In Progress
In Review
Done
Blocked"

# Run bootstrap-project.sh against a tmp env. Stdin is /dev/null so
# the BYO-RDBMS interactive prompt declines (Path C decline).
run_bootstrap() {
    local home_dir="$1"; shift
    local plugin_root="$1"; shift
    local stubs_dir="$1"; shift
    env -i HOME="${home_dir}" PATH="${stubs_dir}:/usr/bin:/bin" \
        bash "${plugin_root}/scripts/bootstrap-project.sh" \
            --plugin-root "${plugin_root}" \
            "$@" </dev/null
}

normalized_state_dir() {
    local home_dir="$1"
    local repo_root="$2"
    local canonical
    canonical="$(cd "${repo_root}" && git rev-parse --show-toplevel 2>/dev/null)"
    if [ -z "${canonical}" ]; then
        canonical="$(cd "${repo_root}" && pwd -P)"
    fi
    local stripped="${canonical#/}"
    stripped="${stripped%/}"
    local normalized="${stripped//\//-}"
    printf '%s/.board-superpowers/repos/%s\n' "${home_dir}" "${normalized}"
}

# ---------------------------------------------------------------------------
# Scenario 14: Full F-B2 — state.yml routing_blocks[] populated for both files
# ---------------------------------------------------------------------------
printf 'Scenario 14: end-to-end F-B2 routing injection populates state.yml\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '%s\n' "${CANONICAL_STATUS}" > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

set +e
ALL_OUT="$(run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1)"
RC=$?
set -e

assert_eq 'e2e: bootstrap exit 0' '0' "${RC}"
check 'e2e: AGENTS.md created in repo' test -f "${REPO_ROOT}/AGENTS.md"
check 'e2e: CLAUDE.md created in repo' test -f "${REPO_ROOT}/CLAUDE.md"
check 'e2e: AGENTS.md has marker pair' \
    bash -c "grep -Fq '<!-- board-superpowers:routing -->' \"\$1\" && grep -Fq '<!-- /board-superpowers:routing -->' \"\$1\"" _ "${REPO_ROOT}/AGENTS.md"
check 'e2e: CLAUDE.md has marker pair' \
    bash -c "grep -Fq '<!-- board-superpowers:routing -->' \"\$1\" && grep -Fq '<!-- /board-superpowers:routing -->' \"\$1\"" _ "${REPO_ROOT}/CLAUDE.md"

STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE_FILE="${STATE_DIR}/state.yml"
check 'e2e: state.yml created' test -f "${STATE_FILE}"

# Parse routing_blocks count via python (flat YAML).
COUNT="$(python3 -c "
import sys
data = open(sys.argv[1]).read()
# Simple YAML-ish scan: count list items under 'routing_blocks:'.
lines = data.splitlines()
in_rb = False
n = 0
for line in lines:
    if line.startswith('routing_blocks:'):
        in_rb = True
        continue
    if in_rb:
        if line.startswith('  - target_file:'):
            n += 1
        elif line and not line.startswith(' '):
            break
print(n)
" "${STATE_FILE}")"
assert_eq 'e2e: state.yml has 2 routing_blocks entries' '2' "${COUNT}"

# Verify the recorded hashes use sha256: prefix and 64 hex chars.
HASH_LINES="$(grep -E 'block_hash:' "${STATE_FILE}" || true)"
HASH_COUNT="$(printf '%s\n' "${HASH_LINES}" | grep -c '^' || true)"
assert_eq 'e2e: state.yml has 2 block_hash entries' '2' "${HASH_COUNT}"
check 'e2e: every block_hash is sha256:<64-hex>' \
    bash -c "printf '%s\n' \"\$1\" | grep -Eq 'sha256:[0-9a-f]{64}'" _ "${HASH_LINES}"

# Verify state.yml also lists target_file: AGENTS.md and CLAUDE.md.
check 'e2e: state.yml mentions AGENTS.md target' \
    bash -c "grep -Eq 'target_file:.*AGENTS\\.md' \"\$1\"" _ "${STATE_FILE}"
check 'e2e: state.yml mentions CLAUDE.md target' \
    bash -c "grep -Eq 'target_file:.*CLAUDE\\.md' \"\$1\"" _ "${STATE_FILE}"

# Suppress warnings about unused vars
: "${ALL_OUT:-}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 15: Full F-B2 with orphan markers — abort, no state.yml written
# ---------------------------------------------------------------------------
printf 'Scenario 15: end-to-end F-B2 with orphan markers — abort\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '%s\n' "${CANONICAL_STATUS}" > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

# Pre-seed AGENTS.md with orphan opening marker.
cat > "${REPO_ROOT}/AGENTS.md" <<'EOF'
# Existing project AGENTS.md

<!-- board-superpowers:routing -->
Half a routing block — closing marker missing.

Some other content.
EOF

set +e
ERR_OUT="$(run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1 1>/dev/null)"
RC=$?
set -e

# Bootstrap should abort non-zero.
check 'orphan e2e: exit non-zero' bash -c "[ \"\$1\" != '0' ]" _ "${RC}"
check 'orphan e2e: stderr mentions "F-B2 step 4"' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'F-B2 step 4'" _ "${ERR_OUT}"

STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE_FILE="${STATE_DIR}/state.yml"
check_not 'orphan e2e: state.yml NOT written' test -f "${STATE_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 16: Stub-redirect target — helper skips, prints empty stdout, exit 0
# ---------------------------------------------------------------------------
# A target file that is a stub redirect (short + contains `@<file>.md`
# CC @-include line) should NOT receive routing-block injection. The
# helper recognizes the stub shape and:
#   - leaves the target file byte-identical
#   - prints NOTHING to stdout (no hash)
#   - exits 0 (not an error — the architect's intent is "redirect")
# Caller (bootstrap-project.sh) interprets empty stdout as "skip this
# target's routing_blocks[] entry" via existing `[ -n "${hash}" ]`
# guard at write_state_yml.
#
# Stub definition (per scripts/lib/common.sh:bsp_inject_routing_block):
#   - File total line count ≤ 30
#   - File contains at least one line matching `^@[A-Za-z0-9./_-]+\.md$`
#     (Claude Code @-include syntax for another markdown file)
# Both conditions required.
printf 'Scenario 16: Stub-redirect target — skip + empty stdout + exit 0\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/CLAUDE.md"

# Build a representative stub redirect identical in shape to
# board-superpowers' own CLAUDE.md (13 lines, ends with `@AGENTS.md`).
cat > "${TARGET}" <<'EOF'
# CLAUDE.md (redirect to AGENTS.md)

This file exists only so **Claude Code** auto-loads the project's
canonical instructions, which live in **`AGENTS.md`** — a single
source of truth for both Claude Code and OpenAI Codex CLI sessions.

> **Make all edits in `AGENTS.md`, not here.**
> Claude Code resolves the `@` reference below and pulls AGENTS.md
> into context automatically. Codex CLI loads AGENTS.md natively per
> its own auto-load convention (see `PLUGIN_DEVELOPMENT.md` for the
> exact lookup order).

@AGENTS.md
EOF

ORIG_BYTES="$(sha256_of_file "${TARGET}")"

set +e
STDOUT_OUT="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
RC=$?
set -e

assert_eq 'stub-redirect: exit 0' '0' "${RC}"
assert_eq 'stub-redirect: stdout is empty (no hash)' '' "${STDOUT_OUT}"
NEW_BYTES="$(sha256_of_file "${TARGET}")"
assert_eq 'stub-redirect: file bytes unchanged' "${ORIG_BYTES}" "${NEW_BYTES}"
check_not 'stub-redirect: opening marker NOT injected' \
    grep -Fq '<!-- board-superpowers:routing -->' "${TARGET}"
check_not 'stub-redirect: closing marker NOT injected' \
    grep -Fq '<!-- /board-superpowers:routing -->' "${TARGET}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 16b: Negative — short file WITHOUT @-include is NOT a stub
# ---------------------------------------------------------------------------
# A file can be short (≤ 30 lines) without being a stub redirect; it
# might be a near-empty template the architect intends to populate.
# Without an `@<file>.md` line the helper MUST proceed with normal
# injection (case-C: append marker-wrapped block).
printf 'Scenario 16b: short file without @-include is NOT a stub — normal append\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

cat > "${TARGET}" <<'EOF'
# AGENTS.md

Project notes go here.
EOF

set +e
HASH16B="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
RC=$?
set -e

assert_eq 'short-no-include: exit 0' '0' "${RC}"
check 'short-no-include: stdout produced 64-char hex hash (NOT empty)' \
    bash -c "printf '%s' \"\$1\" | grep -Eq '^[0-9a-f]{64}$'" _ "${HASH16B}"
check 'short-no-include: opening marker present (block was appended)' \
    grep -Fq '<!-- board-superpowers:routing -->' "${TARGET}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 16c: Negative — long file WITH @-include is NOT a stub
# ---------------------------------------------------------------------------
# Similarly, a substantive file (> 30 lines) that happens to mention an
# `@<file>.md` line for legitimate cross-reference reasons should NOT
# be classified as a stub. Normal injection proceeds.
printf 'Scenario 16c: long file containing @-include is NOT a stub — normal append\n'

TMP="$(mktemp -d)"
TARGET="${TMP}/AGENTS.md"

{
    printf '# AGENTS.md\n\n'
    for i in $(seq 1 35); do
        printf 'Long-form content line %d. The full project guide.\n' "${i}"
    done
    printf '\nSee also @ARCHITECTURE.md for architecture details.\n'
    printf '\nMore content.\n'
} > "${TARGET}"

set +e
HASH16C="$(inject_in_subshell "${TARGET}" "${SOURCE_FILE_REAL}" 2>/dev/null)"
RC=$?
set -e

assert_eq 'long-with-include: exit 0' '0' "${RC}"
check 'long-with-include: stdout produced 64-char hex hash (NOT empty)' \
    bash -c "printf '%s' \"\$1\" | grep -Eq '^[0-9a-f]{64}$'" _ "${HASH16C}"
check 'long-with-include: opening marker present (block was appended)' \
    grep -Fq '<!-- board-superpowers:routing -->' "${TARGET}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 17: end-to-end F-B2 with stub CLAUDE.md — only 1 routing_blocks entry
# ---------------------------------------------------------------------------
printf 'Scenario 17: end-to-end F-B2 with stub CLAUDE.md — 1 entry only\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '%s\n' "${CANONICAL_STATUS}" > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

# Pre-seed CLAUDE.md as a stub redirect (matches board-superpowers'
# own CLAUDE.md form). AGENTS.md is absent — created fresh by F-B2.
cat > "${REPO_ROOT}/CLAUDE.md" <<'EOF'
# CLAUDE.md (redirect to AGENTS.md)

This file exists only so **Claude Code** auto-loads the project's
canonical instructions, which live in **`AGENTS.md`** — a single
source of truth for both Claude Code and OpenAI Codex CLI sessions.

> **Make all edits in `AGENTS.md`, not here.**

@AGENTS.md
EOF

CLAUDE_ORIG_SHA="$(sha256_of_file "${REPO_ROOT}/CLAUDE.md")"

set +e
ALL_OUT="$(run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1)"
RC=$?
set -e

assert_eq 'stub-e2e: bootstrap exit 0' '0' "${RC}"
check 'stub-e2e: AGENTS.md created with marker pair' \
    bash -c "grep -Fq '<!-- board-superpowers:routing -->' \"\$1\" && grep -Fq '<!-- /board-superpowers:routing -->' \"\$1\"" _ "${REPO_ROOT}/AGENTS.md"
check_not 'stub-e2e: stub CLAUDE.md NOT given marker pair' \
    grep -Fq '<!-- board-superpowers:routing -->' "${REPO_ROOT}/CLAUDE.md"
CLAUDE_NEW_SHA="$(sha256_of_file "${REPO_ROOT}/CLAUDE.md")"
assert_eq 'stub-e2e: stub CLAUDE.md bytes byte-identical (untouched)' \
    "${CLAUDE_ORIG_SHA}" "${CLAUDE_NEW_SHA}"

STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE_FILE="${STATE_DIR}/state.yml"
check 'stub-e2e: state.yml created' test -f "${STATE_FILE}"

# routing_blocks should have ONLY AGENTS.md (1 entry). CLAUDE.md skipped.
COUNT="$(python3 -c "
import sys
data = open(sys.argv[1]).read()
lines = data.splitlines()
in_rb = False
n = 0
for line in lines:
    if line.startswith('routing_blocks:'):
        in_rb = True
        continue
    if in_rb:
        if line.startswith('  - target_file:'):
            n += 1
        elif line and not line.startswith(' '):
            break
print(n)
" "${STATE_FILE}")"
assert_eq 'stub-e2e: state.yml has exactly 1 routing_blocks entry (AGENTS.md only)' '1' "${COUNT}"
check 'stub-e2e: state.yml mentions AGENTS.md target' \
    bash -c "grep -Eq 'target_file:.*AGENTS\\.md' \"\$1\"" _ "${STATE_FILE}"
check_not 'stub-e2e: state.yml does NOT mention CLAUDE.md target' \
    bash -c "grep -Eq 'target_file:.*CLAUDE\\.md' \"\$1\"" _ "${STATE_FILE}"

: "${ALL_OUT:-}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 18: end-to-end with substantive (non-stub) CLAUDE.md preserved
# ---------------------------------------------------------------------------
# The TODO in PR #29 asked to verify F-B2 still injects normally when
# CLAUDE.md is a substantive (non-stub) file. Hermetic version: pre-seed
# CLAUDE.md as a 50-line developer-doc-style file (no @-include), run
# F-B2, expect (1) markers injected after the existing content, (2)
# state.yml routing_blocks contains both AGENTS.md AND CLAUDE.md, (3)
# original CLAUDE.md content preserved verbatim above the markers.
printf 'Scenario 18: end-to-end F-B2 with substantive CLAUDE.md — both files injected\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '%s\n' "${CANONICAL_STATUS}" > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

# Pre-seed CLAUDE.md as a substantive developer guide. > 30 lines so
# the line-count predicate trips, no @-include line so the stub
# predicate fails — must NOT be classified as stub.
{
    printf '# Project CLAUDE.md\n\n'
    for i in $(seq 1 50); do
        printf 'Substantive developer guidance line %d.\n' "${i}"
    done
    printf '\n## Architecture overview\n\nMore content here.\n'
} > "${REPO_ROOT}/CLAUDE.md"

CLAUDE_PRE_SHA="$(sha256_of_file "${REPO_ROOT}/CLAUDE.md")"

set +e
ALL_OUT="$(run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1)"
RC=$?
set -e

assert_eq 'substantive-CLAUDE: bootstrap exit 0' '0' "${RC}"
check 'substantive-CLAUDE: AGENTS.md created with marker pair' \
    bash -c "grep -Fq '<!-- board-superpowers:routing -->' \"\$1\"" _ "${REPO_ROOT}/AGENTS.md"
check 'substantive-CLAUDE: CLAUDE.md HAS marker pair (substantive → injected)' \
    bash -c "grep -Fq '<!-- board-superpowers:routing -->' \"\$1\" && grep -Fq '<!-- /board-superpowers:routing -->' \"\$1\"" _ "${REPO_ROOT}/CLAUDE.md"
check 'substantive-CLAUDE: original "Substantive developer guidance" content preserved' \
    grep -Fq 'Substantive developer guidance line 25' "${REPO_ROOT}/CLAUDE.md"
check 'substantive-CLAUDE: original "## Architecture overview" heading preserved' \
    grep -Fq '## Architecture overview' "${REPO_ROOT}/CLAUDE.md"
# File grew (because the routing block was appended).
CLAUDE_POST_BYTES="$(wc -c < "${REPO_ROOT}/CLAUDE.md" | tr -d ' ')"
CLAUDE_PRE_BYTES="$(wc -c <<< "${CLAUDE_PRE_SHA}")"  # placeholder; we want pre-file size
# Recompute pre size from the seeded content cleanly.
PRE_SIZE_FILE="${TMP}/pre-claude.txt"
{
    printf '# Project CLAUDE.md\n\n'
    for i in $(seq 1 50); do
        printf 'Substantive developer guidance line %d.\n' "${i}"
    done
    printf '\n## Architecture overview\n\nMore content here.\n'
} > "${PRE_SIZE_FILE}"
CLAUDE_PRE_BYTES="$(wc -c < "${PRE_SIZE_FILE}" | tr -d ' ')"
check 'substantive-CLAUDE: file grew (block appended, content NOT replaced)' \
    test "${CLAUDE_POST_BYTES}" -gt "${CLAUDE_PRE_BYTES}"

STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE_FILE="${STATE_DIR}/state.yml"

COUNT="$(python3 -c "
import sys
data = open(sys.argv[1]).read()
lines = data.splitlines()
in_rb = False
n = 0
for line in lines:
    if line.startswith('routing_blocks:'):
        in_rb = True
        continue
    if in_rb:
        if line.startswith('  - target_file:'):
            n += 1
        elif line and not line.startswith(' '):
            break
print(n)
" "${STATE_FILE}")"
assert_eq 'substantive-CLAUDE: state.yml has 2 routing_blocks entries' '2' "${COUNT}"
check 'substantive-CLAUDE: state.yml mentions AGENTS.md target' \
    bash -c "grep -Eq 'target_file:.*AGENTS\\.md' \"\$1\"" _ "${STATE_FILE}"
check 'substantive-CLAUDE: state.yml mentions CLAUDE.md target' \
    bash -c "grep -Eq 'target_file:.*CLAUDE\\.md' \"\$1\"" _ "${STATE_FILE}"

: "${ALL_OUT:-}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 19: dual stub redirects — routing_blocks empty + check-deps warns
# ---------------------------------------------------------------------------
# The TODO in PR #29 asked to verify the degenerate case where BOTH
# AGENTS.md AND CLAUDE.md are stub redirects (mutually pointing). F-B2
# must produce routing_blocks: [] (no injection happened anywhere) and
# check-deps must warn that the routing block is missing — because
# functionally the routing IS missing: neither file carries the markers.
printf 'Scenario 19: dual stub redirects — empty routing_blocks + check-deps warns\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '%s\n' "${CANONICAL_STATUS}" > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

# Pre-seed BOTH files as stub redirects pointing at each other.
cat > "${REPO_ROOT}/AGENTS.md" <<'EOF'
# AGENTS.md (stub redirect)

This file is a stub redirect. The substantive content lives elsewhere.

@CLAUDE.md
EOF

cat > "${REPO_ROOT}/CLAUDE.md" <<'EOF'
# CLAUDE.md (stub redirect)

This file is a stub redirect. The substantive content lives elsewhere.

@AGENTS.md
EOF

AGENTS_PRE_SHA="$(sha256_of_file "${REPO_ROOT}/AGENTS.md")"
CLAUDE_PRE_SHA="$(sha256_of_file "${REPO_ROOT}/CLAUDE.md")"

set +e
ALL_OUT="$(run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1)"
RC=$?
set -e

assert_eq 'dual-stub: bootstrap exit 0' '0' "${RC}"
AGENTS_POST_SHA="$(sha256_of_file "${REPO_ROOT}/AGENTS.md")"
CLAUDE_POST_SHA="$(sha256_of_file "${REPO_ROOT}/CLAUDE.md")"
assert_eq 'dual-stub: AGENTS.md untouched (stub preserved)' \
    "${AGENTS_PRE_SHA}" "${AGENTS_POST_SHA}"
assert_eq 'dual-stub: CLAUDE.md untouched (stub preserved)' \
    "${CLAUDE_PRE_SHA}" "${CLAUDE_POST_SHA}"
check_not 'dual-stub: AGENTS.md has NO routing markers' \
    grep -Fq '<!-- board-superpowers:routing -->' "${REPO_ROOT}/AGENTS.md"
check_not 'dual-stub: CLAUDE.md has NO routing markers' \
    grep -Fq '<!-- board-superpowers:routing -->' "${REPO_ROOT}/CLAUDE.md"

STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE_FILE="${STATE_DIR}/state.yml"
check 'dual-stub: state.yml created' test -f "${STATE_FILE}"
check 'dual-stub: state.yml has routing_blocks: []' \
    bash -c "grep -Fq 'routing_blocks: []' \"\$1\"" _ "${STATE_FILE}"
check_not 'dual-stub: state.yml mentions NO target_file entries' \
    bash -c "grep -Eq 'target_file:' \"\$1\"" _ "${STATE_FILE}"

# Now run check-deps.sh against this repo and verify it reports
# "routing block missing" (the dual-stub case is functionally a repo
# without injected routing — the asymmetric rule MUST trip, since at
# least one of AGENTS.md / CLAUDE.md exists but neither carries the
# canonical heading).
# Use the real plugin root for check-deps.sh — make_stub_plugin_root
# only copies the bootstrap-related scripts. check-deps.sh is plugin-
# version-agnostic and only inspects CLAUDE_PROJECT_DIR's repo state.
CHECK_DEPS_OUT="$(env -i HOME="${HOME_DIR}" \
    PATH="${STUBS_DIR}:/usr/bin:/bin" \
    CLAUDE_PROJECT_DIR="${REPO_ROOT}" \
    bash "${PLUGIN_ROOT_REAL}/scripts/check-deps.sh" --machine 2>&1 || true)"
check 'dual-stub: check-deps machine mode emits ROUTING_INJECTED=no' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'ROUTING_INJECTED=no'" _ "${CHECK_DEPS_OUT}"

: "${ALL_OUT:-}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n— TOTALS —\nPASS: %d\nFAIL: %d\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
