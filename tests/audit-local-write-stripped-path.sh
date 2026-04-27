#!/usr/bin/env bash
# Regression test: bsp_audit_local_write must work when caller has stripped PATH.
# Bug history: session f92cce12 saw `command not found` for dirname/mkdir/python3
# when sourced from a process with empty PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPREPO="$(mktemp -d)"
git -C "${TMPREPO}" init -q
git -C "${TMPREPO}" remote add origin git@github.com:test/test-repo.git

# Stripped PATH invocation. Must succeed.
env -i HOME="${HOME}" bash -c "
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

# Verify entry was written. Compute the normalized dir name explicitly
# (mirrors bsp_normalize_repo_path: strip leading /, replace remaining / with -)
# so the check is portable across macOS (where mktemp returns /var/folders/...
# paths whose basename appears as a SUFFIX of the normalized name, not a prefix).
NORMALIZED="${TMPREPO#/}"
NORMALIZED="${NORMALIZED%/}"
NORMALIZED="${NORMALIZED//\//-}"
JSONL="${HOME}/.board-superpowers/repos/${NORMALIZED}/audit-local.jsonl"
[ -f "${JSONL}" ] || { echo "FAIL: jsonl not written at ${JSONL}"; exit 1; }

echo "PASS"
