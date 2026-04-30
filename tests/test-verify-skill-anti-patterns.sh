#!/usr/bin/env bash
# tests/test-verify-skill-anti-patterns.sh — fixture-driven assertions
# for scripts/verify-skill-anti-patterns.sh A9 detector.
#
# Spec under test:
#   SKILL_DEVELOPMENT.md § A9 — internal references in SKILL body.
#   B6 (PR #70 cleanup arc) — extends scan scope to references/**.md
#   and the cross-boundary patterns (docs/architecture/, ../../docs/,
#   *_DEVELOPMENT.md root markdowns, adr/0[0-9]{3} fragments).
#
# Hermeticity: each test uses BSP_TEST_PLUGIN_ROOT to point the gate at
# a temp fixture tree. The live skills/ tree is never modified or
# scanned by these tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"
GATE="${PLUGIN_ROOT_REAL}/scripts/verify-skill-anti-patterns.sh"

if [ ! -x "${GATE}" ]; then
    if [ ! -f "${GATE}" ]; then
        printf 'FATAL: gate script missing at %s\n' "${GATE}" >&2
        exit 99
    fi
fi

PASS=0
FAIL=0

# make_fixture <fixture_root>
# Lays down a minimal plugin-tree skeleton: skills/<one-skill>/SKILL.md
# plus references/. Caller mutates files afterward to set up scenarios.
make_fixture() {
    local root="$1"
    mkdir -p "${root}/skills/sample-skill/references"
    cat > "${root}/skills/sample-skill/SKILL.md" <<'EOF'
---
name: sample-skill
description: Use when testing the anti-pattern gate against fixtures.
---

This is a sample skill body with no internal references. The gate
should never flag this content unless a test mutates it.
EOF
}

run_gate() {
    # run_gate <fixture_root> — returns gate exit code.
    BSP_TEST_PLUGIN_ROOT="$1" bash "${GATE}" >/dev/null 2>&1
}

assert_fail() {
    local label="$1"
    local root="$2"
    if run_gate "${root}"; then
        printf '  FAIL — %s (gate exited 0; expected violation)\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    else
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    fi
}

assert_pass() {
    local label="$1"
    local root="$2"
    if run_gate "${root}"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s (gate exited 1; expected clean)\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# --- Positive case 1: internal ADR code in references/ ------------------
TMP1="$(mktemp -d)"
trap 'rm -rf "${TMP1}"' EXIT
make_fixture "${TMP1}"
cat > "${TMP1}/skills/sample-skill/references/foo.md" <<'EOF'
Per ADR-0026 § Schema, the kanban protocol mandates...
EOF
assert_fail "P1 ADR-0026 in references/ → fail" "${TMP1}"

# --- Positive case 2: docs/architecture/ markdown link ------------------
TMP2="$(mktemp -d)"
trap 'rm -rf "${TMP1}" "${TMP2}"' EXIT
make_fixture "${TMP2}"
cat > "${TMP2}/skills/sample-skill/references/foo.md" <<'EOF'
See [the spec](docs/architecture/0005-contracts/00-kanban-protocol.md)
for more.
EOF
assert_fail "P2 docs/architecture/ link in references/ → fail" "${TMP2}"

# --- Positive case 3: ../../docs/ relative traversal --------------------
TMP3="$(mktemp -d)"
trap 'rm -rf "${TMP1}" "${TMP2}" "${TMP3}"' EXIT
make_fixture "${TMP3}"
cat > "${TMP3}/skills/sample-skill/SKILL.md" <<'EOF'
---
name: sample-skill
description: Use when testing.
---

Refer to ../../docs/spec.md for the canonical contract.
EOF
assert_fail "P3 ../../docs/ in SKILL.md → fail" "${TMP3}"

# --- Positive case 4: BOARD_DEVELOPMENT.md filename mention --------------
TMP4="$(mktemp -d)"
trap 'rm -rf "${TMP1}" "${TMP2}" "${TMP3}" "${TMP4}"' EXIT
make_fixture "${TMP4}"
cat > "${TMP4}/skills/sample-skill/references/foo.md" <<'EOF'
The full design rationale lives in BOARD_DEVELOPMENT.md (root of repo).
EOF
assert_fail "P4 BOARD_DEVELOPMENT.md mention in references/ → fail" "${TMP4}"

# --- Negative case 1: maintainer-footnote escape hatch ------------------
TMP5="$(mktemp -d)"
trap 'rm -rf "${TMP1}" "${TMP2}" "${TMP3}" "${TMP4}" "${TMP5}"' EXIT
make_fixture "${TMP5}"
cat > "${TMP5}/skills/sample-skill/references/foo.md" <<'EOF'
The skill body is fully self-contained. **Maintainer reference (board-superpowers repo only; not shipped with plugin install)**: full design lives in ADR-0026 + ADR-0027 in `docs/architecture/adr/`.
EOF
assert_pass "N1 'not shipped with plugin install' footnote → pass" "${TMP5}"

# --- Negative case 2: clean SKILL.md ------------------------------------
TMP6="$(mktemp -d)"
trap 'rm -rf "${TMP1}" "${TMP2}" "${TMP3}" "${TMP4}" "${TMP5}" "${TMP6}"' EXIT
make_fixture "${TMP6}"
# Default SKILL.md from make_fixture is already clean. No references/ files.
assert_pass "N2 clean SKILL.md, no references → pass" "${TMP6}"

# --- Negative case 3: skills/AGENTS.md excluded -------------------------
TMP7="$(mktemp -d)"
trap 'rm -rf "${TMP1}" "${TMP2}" "${TMP3}" "${TMP4}" "${TMP5}" "${TMP6}" "${TMP7}"' EXIT
make_fixture "${TMP7}"
# skills/AGENTS.md sits at skills/ root, NOT under any references/
# subdirectory, so the references-glob naturally skips it. Assert that
# placing internal codes there does not cause the gate to fail.
cat > "${TMP7}/skills/AGENTS.md" <<'EOF'
# Maintainer contract

See ../docs/architecture/0005-contracts/02-hook-contracts.md for the
hook protocol. Per ADR-0023 the architect-UX gate gives ...
EOF
assert_pass "N3 skills/AGENTS.md ../docs/ ref → pass (excluded)" "${TMP7}"

# --- Summary ------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf '\n%d/%d passed (%d failed)\n' "${PASS}" "${TOTAL}" "${FAIL}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0
