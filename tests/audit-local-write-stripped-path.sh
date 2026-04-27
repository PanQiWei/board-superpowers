#!/usr/bin/env bash
# Regression test: bsp_audit_local_write must work when caller has stripped PATH.
# Bug history: session f92cce12 saw `command not found` for dirname/mkdir/python3
# when sourced from a process with empty PATH.
#
# Test isolation: uses a TMPHOME so the regression test does NOT pollute the
# architect's real ~/.board-superpowers/ directory. trap cleans up on exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPHOME="$(mktemp -d)"
TMPREPO="$(mktemp -d)"
trap 'rm -rf "${TMPHOME}" "${TMPREPO}"' EXIT

git -C "${TMPREPO}" init -q
git -C "${TMPREPO}" remote add origin git@github.com:test/test-repo.git

# Stripped PATH invocation against an isolated HOME. Must succeed.
env -i HOME="${TMPHOME}" bash -c "
    set -euo pipefail
    PATH=
    source ${SCRIPT_DIR}/scripts/lib/common.sh
    bsp_audit_local_write \
        '${TMPREPO}' \
        'test.action' \
        'A' \
        'test-skill' \
        'PATH-strip regression test'
"

# Verify entry was written under TMPHOME (not the real $HOME). NORMALIZED
# computation mirrors bsp_normalize_repo_path: strip leading /, replace
# remaining / with -. macOS-portable.
NORMALIZED="${TMPREPO#/}"
NORMALIZED="${NORMALIZED%/}"
NORMALIZED="${NORMALIZED//\//-}"
JSONL="${TMPHOME}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"
[ -f "${JSONL}" ] || { echo "FAIL: jsonl not written at ${JSONL}"; exit 1; }

echo "PASS"
