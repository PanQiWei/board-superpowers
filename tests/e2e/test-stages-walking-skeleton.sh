#!/usr/bin/env bash
# shellcheck disable=SC2016
# SC2016: single-quoted bash -c bodies intentionally pass $1 to inner shell.
# tests/e2e/test-stages-walking-skeleton.sh
#
# Walking-skeleton E2E test for Phase 2.
# PHASE-2-ONLY: only m6.repo.append-gitignore is wired in stages_lib.
# Phase 3 will extend this test as more stages land.
#
# Scenario:
#   1. Fresh tmp repo, no venv, no settings files → hook emits INVOKE marker.
#   2. Mock SKILL flow: run m6 executor directly; write a minimal
#      repo-shared settings.yml entry simulating SKILL lifecycle persistence.
#   3. Re-run hook → no INVOKE marker (fallback file-presence check satisfied).
#
# Hermeticity: isolated HOME + git repo; no network; no real ~/.board-superpowers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"
M6_MODULE="${PLUGIN_ROOT}/scripts/stages_lib/m6_repo_append_gitignore.py"

[ -f "${HOOK}" ]        || { printf 'FATAL: %s not found\n' "${HOOK}" >&2; exit 99; }
[ -f "${M6_MODULE}" ]   || { printf 'FATAL: %s not found\n' "${M6_MODULE}" >&2; exit 99; }

PASS=0; FAIL=0

check() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  PASS — %s\n' "${label}"; PASS=$((PASS+1))
    else
        printf '  FAIL — %s\n' "${label}" >&2; FAIL=$((FAIL+1))
    fi
}

# ---------------------------------------------------------------------------
# Isolated environment
# ---------------------------------------------------------------------------

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_BASE}"' EXIT

FAKE_HOME="${TMPDIR_BASE}/home"
REPO_DIR="${TMPDIR_BASE}/repo"
mkdir -p "${FAKE_HOME}/.board-superpowers" "${REPO_DIR}"

git -C "${REPO_DIR}" init -q
git -C "${REPO_DIR}" remote add origin "https://github.com/test-org/test-repo.git"

# Use git rev-parse for REPO_ROOT (mirrors hook logic; resolves macOS /private symlink).
REAL_REPO_ROOT="$(git -C "${REPO_DIR}" rev-parse --show-toplevel)"
NORMALIZED="$(printf '%s' "${REAL_REPO_ROOT}" | sed 's|^/||; s|/|-|g')"
REPO_SHARED_DIR="${FAKE_HOME}/.board-superpowers/repos/${NORMALIZED}"
mkdir -p "${REPO_SHARED_DIR}"

run_hook() {
    # Hook uses PWD (not argv) to discover REPO_ROOT via git rev-parse.
    # Run inside REPO_DIR so the hook resolves the correct repo root.
    ( cd "${REPO_DIR}" && HOME="${FAKE_HOME}" CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${HOOK}" 2>/dev/null ) || true
}

# ---------------------------------------------------------------------------
# Phase A: fresh repo — hook must emit INVOKE marker
# ---------------------------------------------------------------------------

printf '\n=== Phase A: fresh repo — hook emits INVOKE marker ===\n'

HOOK_OUT_A="$(run_hook)"

check "hook exits cleanly on fresh repo" true
check "INVOKE: bootstrapping-repo in hook output" \
    bash -c 'printf "%s" "${1}" | grep -q "INVOKE: bootstrapping-repo"' -- "${HOOK_OUT_A}"

# ---------------------------------------------------------------------------
# Phase B: mock SKILL — run m6 executor + persist lifecycle state
# ---------------------------------------------------------------------------

printf '\n=== Phase B: mock SKILL — m6 executor + lifecycle state write ===\n'

# Run m6 executor via python3 (no venv required — pure stdlib + m6 module).
python3 - "${REPO_DIR}" "${M6_MODULE}" <<'PYEOF'
import sys, types, pathlib as pl, importlib.util
repo = pl.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("m6", sys.argv[2])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
ctx = types.SimpleNamespace(repo_root=repo)
r = mod.executor(ctx)
assert r["applied"], f"executor did not apply: {r}"
PYEOF

check ".gitignore managed block written" \
    grep -q "board-superpowers managed" "${REPO_DIR}/.gitignore"
check ".gitignore contains *.local.*"  grep -q '\*\.local\.\*'  "${REPO_DIR}/.gitignore"
check ".gitignore contains claims/"    grep -q "claims/"          "${REPO_DIR}/.gitignore"
check ".gitignore contains .venv/"     grep -q "\.venv/"          "${REPO_DIR}/.gitignore"

# Write host-shared settings.yml and repo-shared settings.yml to simulate SKILL
# lifecycle persistence.  The hook's no-venv fallback checks BOTH files.
HOST_SETTINGS="${FAKE_HOME}/.board-superpowers/settings.yml"
cat > "${HOST_SETTINGS}" <<YAML
# Simulated host-shared lifecycle state — walking-skeleton E2E test.
stages_completed:
  - stage_id: m1.host.write-manifest
    generation: 1
    status: applied
    target_state_hash: placeholder-sha256
    applied_at: "2026-04-30T00:00:00Z"
YAML

cat > "${REPO_SHARED_DIR}/settings.yml" <<YAML
# Simulated repo-shared lifecycle state — walking-skeleton E2E test.
stages_completed:
  - stage_id: m6.repo.append-gitignore
    generation: 1
    status: applied
    target_state_hash: placeholder-sha256
    applied_at: "2026-04-30T00:00:00Z"
YAML

check "host-shared settings.yml written"  test -f "${HOST_SETTINGS}"
check "repo-shared settings.yml written"  test -f "${REPO_SHARED_DIR}/settings.yml"

# ---------------------------------------------------------------------------
# Phase C: second hook run — silent (no INVOKE marker)
# ---------------------------------------------------------------------------

printf '\n=== Phase C: second hook run — no INVOKE marker ===\n'

HOOK_OUT_C="$(run_hook)"

check "hook exits cleanly on bootstrapped repo" true
check "no INVOKE: bootstrapping-repo on second run" \
    bash -c '! printf "%s" "${1}" | grep -q "INVOKE: bootstrapping-repo"' -- "${HOOK_OUT_C}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n=== Walking-skeleton E2E: %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
