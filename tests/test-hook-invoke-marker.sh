#!/usr/bin/env bash
# tests/test-hook-invoke-marker.sh — assert hooks/session-start.sh
# emits the right INVOKE: marker (or none) per state-file presence,
# stays self-contained, sanitizes inputs, and never blocks on failure.
#
# Spec under test:
#   docs/architecture/0005-contracts/02-hook-contracts.md
#     § "Intent-injection markers" — marker grammar + at-most-one rule.
#   docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
#     § "three-layer alert + intent-injection strategy" — Layer 1 role.
#
# Hermeticity: every scenario uses a fresh tmp HOME, a fresh tmp git
# repo as PWD, a stub plugin root with a controllable plugin.json,
# and no reach-through to the real ~/.board-superpowers.
#
# shellcheck disable=SC2016
# Single-quoted bash -c bodies are intentional throughout: the literal
# `$1` must reach the inner shell, not be expanded by this one. The
# context value travels via the trailing positional arg.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT_REAL}/hooks/session-start.sh"

if [ ! -f "${HOOK}" ]; then
    printf 'FATAL: %s not found\n' "${HOOK}" >&2
    exit 99
fi

PASS=0
FAIL=0

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

assert_eq() {
    local label="$1"; local expected="$2"; local actual="$3"
    if [ "${actual}" = "${expected}" ]; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n    expected: %q\n    actual:   %q\n' \
            "${label}" "${expected}" "${actual}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# Build a tmp plugin-root tree containing the real check-deps.sh +
# session-start.sh + lib (we WILL NOT source it from the hook, but
# the dep-check script imports nothing). plugin.json carries a stub
# version. Returns path on stdout.
make_plugin_root() {
    local target="$1"
    local version="$2"
    mkdir -p "${target}/.claude-plugin"
    mkdir -p "${target}/hooks"
    mkdir -p "${target}/scripts/lib"
    cat > "${target}/.claude-plugin/plugin.json" <<EOF
{
  "name": "board-superpowers",
  "version": "${version}",
  "description": "stub for tests",
  "license": "MIT"
}
EOF
    cp "${PLUGIN_ROOT_REAL}/hooks/session-start.sh" "${target}/hooks/session-start.sh"
    cp "${PLUGIN_ROOT_REAL}/scripts/check-deps.sh" "${target}/scripts/check-deps.sh"
    # common.sh is referenced by other scripts, but NOT by the hook.
    # Copy it for parity even though we won't load it from the hook.
    cp "${PLUGIN_ROOT_REAL}/scripts/lib/common.sh" "${target}/scripts/lib/common.sh"
    chmod +x "${target}/hooks/session-start.sh" "${target}/scripts/check-deps.sh"
}

# Initialize a hermetic git repo with a routing-block-bearing
# AGENTS.md so check-deps.sh in --machine mode emits empty stdout
# (i.e. "all good") under default conditions. Caller may override.
make_repo() {
    local repo_dir="$1"
    mkdir -p "${repo_dir}"
    (
        cd "${repo_dir}"
        git init -q
        git config user.email test@example.com
        git config user.name 'test'
        cat > AGENTS.md <<'EOF'
# Test repo AGENTS.md

## board-superpowers session routing

Routing block contents.
EOF
        cat > CLAUDE.md <<'EOF'
# Test repo CLAUDE.md

## board-superpowers session routing

Routing block contents.
EOF
        git add . >/dev/null 2>&1
        git commit -q -m initial >/dev/null 2>&1 || true
    )
}

# Run the hook from a hermetic environment. Args:
#   $1 = plugin_root, $2 = home, $3 = repo (becomes PWD).
run_hook() {
    local plugin_root="$1"; local home_dir="$2"; local repo_dir="$3"
    (
        cd "${repo_dir}"
        HOME="${home_dir}" \
        CLAUDE_PLUGIN_ROOT="${plugin_root}" \
        bash "${plugin_root}/hooks/session-start.sh"
    )
}

# Extract additionalContext text from the JSON stdout payload.
extract_additional_context() {
    local payload="$1"
    PAYLOAD="${payload}" python3 -c '
import json, os, sys
data = json.loads(os.environ["PAYLOAD"])
sys.stdout.write(data["hookSpecificOutput"]["additionalContext"])
'
}

# Verify the payload parses as valid JSON.
assert_valid_json() {
    local label="$1"; local payload="$2"
    if PAYLOAD="${payload}" python3 -c '
import json, os, sys
json.loads(os.environ["PAYLOAD"])
' >/dev/null 2>&1; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s (invalid JSON)\n' "${label}" >&2
        printf '    payload: %s\n' "${payload}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# Resolve the normalized directory name for a repo path the same way
# the hook does (and the way bsp_normalize_repo_path in common.sh
# does). Used to write the per-repo state.yml under the right path.
normalize_for_test() {
    local p="$1"
    p="${p%/}"
    p="${p#/}"
    printf '%s\n' "${p//\//-}"
}

# A "clean" check-deps stub that emits empty output (everything OK) —
# used to capture happy-path fixtures whose dep-alert section stays
# silent. Hermetic-HOME real check-deps.sh otherwise flags `gh` as
# unauthenticated under the tmp HOME (its credential store is at
# $HOME/.config/gh/), which is a test artifact, not the user-facing
# steady state we want pinned in the fixture.
install_clean_check_deps() {
    local target_root="$1"
    cat > "${target_root}/scripts/check-deps.sh" <<'EOF'
#!/usr/bin/env bash
# Clean stub for fixture capture. Emits nothing in --machine mode
# (caller-side `[ -z "$output" ]` interprets this as "all good").
exit 0
EOF
    chmod +x "${target_root}/scripts/check-deps.sh"
}

# ---------------------------------------------------------------------------
# Scenario 1: both state files present → no INVOKE marker
# ---------------------------------------------------------------------------
printf 'Scenario 1: both state files present (no INVOKE marker)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
REPO_DIR="${TMP}/repo"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_plugin_root "${PLUGIN_ROOT}" "0.2.0"
install_clean_check_deps "${PLUGIN_ROOT}"
make_repo "${REPO_DIR}"

# Write manifest.yml
cat > "${HOME_DIR}/.board-superpowers/manifest.yml" <<EOF
schema_version: 1
host_bootstrapped_at: "2026-01-01T00:00:00Z"
last_seen_version: "0.2.0"
EOF

# Write per-repo state.yml at the normalized path. The repo's git
# toplevel may differ from REPO_DIR (e.g. macOS /private/var symlink
# resolution), so we have to use what the hook will actually compute.
NORM_REPO_DIR="$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)"
NORM="$(normalize_for_test "${NORM_REPO_DIR}")"
mkdir -p "${HOME_DIR}/.board-superpowers/repos/${NORM}"
cat > "${HOME_DIR}/.board-superpowers/repos/${NORM}/state.yml" <<EOF
schema_version: 1
repo_bootstrapped_at: "2026-01-01T00:00:00Z"
last_seen_version_in_repo: "0.2.0"
EOF

set +e
PAYLOAD="$(run_hook "${PLUGIN_ROOT}" "${HOME_DIR}" "${REPO_DIR}")"
RC=$?
set -e

assert_eq 'hook exit 0' '0' "$(printf '%d' "${RC}")"
assert_valid_json 'JSON shape valid' "${PAYLOAD}"

CONTEXT="$(extract_additional_context "${PAYLOAD}")"
check 'version banner present' \
    bash -c 'printf "%s" "$1" | grep -q "board-superpowers v0.2.0 loaded."' _ "${CONTEXT}"
check_not 'no INVOKE marker' \
    bash -c 'printf "%s" "$1" | grep -q "^INVOKE:"' _ "${CONTEXT}"
check_not 'no dep alert (clean check-deps stub)' \
    bash -c 'printf "%s" "$1" | grep -q "dependency check or routing-block"' _ "${CONTEXT}"

# Capture this payload as the post-bootstrap fixture.
mkdir -p "${PLUGIN_ROOT_REAL}/tests/fixtures"
printf '%s\n' "${PAYLOAD}" > "${PLUGIN_ROOT_REAL}/tests/fixtures/session-start-v0.2.0-post-bootstrap.txt"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 2: manifest absent → INVOKE: bootstrapping-repo with manifest reason
# ---------------------------------------------------------------------------
printf 'Scenario 2: manifest absent (INVOKE: bootstrapping-repo)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
REPO_DIR="${TMP}/repo"
mkdir -p "${HOME_DIR}"
make_plugin_root "${PLUGIN_ROOT}" "0.2.0"
install_clean_check_deps "${PLUGIN_ROOT}"
make_repo "${REPO_DIR}"

# manifest.yml absent. state.yml absent. Per spec, manifest-absent
# wins the REASON line.

set +e
PAYLOAD="$(run_hook "${PLUGIN_ROOT}" "${HOME_DIR}" "${REPO_DIR}")"
RC=$?
set -e

assert_eq 'hook exit 0' '0' "$(printf '%d' "${RC}")"
assert_valid_json 'JSON shape valid' "${PAYLOAD}"

CONTEXT="$(extract_additional_context "${PAYLOAD}")"
check 'INVOKE: bootstrapping-repo present' \
    bash -c 'printf "%s" "$1" | grep -qE "^INVOKE: bootstrapping-repo$"' _ "${CONTEXT}"
check 'REASON mentions manifest.yml' \
    bash -c 'printf "%s" "$1" | grep -qE "^REASON: .*manifest\\.yml"' _ "${CONTEXT}"

# At-most-one rule: only one INVOKE line in the payload.
INVOKE_COUNT="$(printf '%s' "${CONTEXT}" | grep -cE "^INVOKE:" || true)"
assert_eq 'exactly one INVOKE line' '1' "${INVOKE_COUNT}"

# Capture this payload as the pre-bootstrap fixture.
printf '%s\n' "${PAYLOAD}" > "${PLUGIN_ROOT_REAL}/tests/fixtures/session-start-v0.2.0-pre-bootstrap.txt"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 3: state.yml absent (manifest present)
# ---------------------------------------------------------------------------
printf 'Scenario 3: per-repo state.yml absent (manifest present)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
REPO_DIR="${TMP}/repo"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_plugin_root "${PLUGIN_ROOT}" "0.2.0"
make_repo "${REPO_DIR}"

cat > "${HOME_DIR}/.board-superpowers/manifest.yml" <<EOF
schema_version: 1
host_bootstrapped_at: "2026-01-01T00:00:00Z"
last_seen_version: "0.2.0"
EOF

set +e
PAYLOAD="$(run_hook "${PLUGIN_ROOT}" "${HOME_DIR}" "${REPO_DIR}")"
RC=$?
set -e

assert_eq 'hook exit 0' '0' "$(printf '%d' "${RC}")"
CONTEXT="$(extract_additional_context "${PAYLOAD}")"
check 'INVOKE: bootstrapping-repo present' \
    bash -c 'printf "%s" "$1" | grep -qE "^INVOKE: bootstrapping-repo$"' _ "${CONTEXT}"
check 'REASON mentions state.yml' \
    bash -c 'printf "%s" "$1" | grep -qE "^REASON: .*state\\.yml"' _ "${CONTEXT}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 4: both state files absent → exactly one marker emitted
# ---------------------------------------------------------------------------
printf 'Scenario 4: both state files absent (single marker)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
REPO_DIR="${TMP}/repo"
mkdir -p "${HOME_DIR}"
make_plugin_root "${PLUGIN_ROOT}" "0.2.0"
make_repo "${REPO_DIR}"

set +e
PAYLOAD="$(run_hook "${PLUGIN_ROOT}" "${HOME_DIR}" "${REPO_DIR}")"
RC=$?
set -e

assert_eq 'hook exit 0' '0' "$(printf '%d' "${RC}")"
CONTEXT="$(extract_additional_context "${PAYLOAD}")"
INVOKE_COUNT="$(printf '%s' "${CONTEXT}" | grep -cE "^INVOKE:" || true)"
REASON_COUNT="$(printf '%s' "${CONTEXT}" | grep -cE "^REASON:" || true)"
assert_eq 'exactly one INVOKE line (no double-emit)' '1' "${INVOKE_COUNT}"
assert_eq 'exactly one REASON line' '1' "${REASON_COUNT}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 5: dep-check failure (gh missing) → warning included, exit still 0
# ---------------------------------------------------------------------------
printf 'Scenario 5: dep-check missing dep (non-blocking warning)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
REPO_DIR="${TMP}/repo"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_plugin_root "${PLUGIN_ROOT}" "0.2.0"
make_repo "${REPO_DIR}"

cat > "${HOME_DIR}/.board-superpowers/manifest.yml" <<EOF
schema_version: 1
host_bootstrapped_at: "2026-01-01T00:00:00Z"
last_seen_version: "0.2.0"
EOF
NORM_REPO_DIR="$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)"
NORM="$(normalize_for_test "${NORM_REPO_DIR}")"
mkdir -p "${HOME_DIR}/.board-superpowers/repos/${NORM}"
cat > "${HOME_DIR}/.board-superpowers/repos/${NORM}/state.yml" <<EOF
schema_version: 1
last_seen_version_in_repo: "0.2.0"
EOF

# Drop gh from PATH for this invocation. Build a sanitized PATH that
# excludes any directory containing `gh`.
SANITIZED_PATH=""
IFS=':' read -ra PATH_PARTS <<< "${PATH}"
for p in "${PATH_PARTS[@]}"; do
    [ -z "${p}" ] && continue
    if [ -x "${p}/gh" ]; then
        continue
    fi
    if [ -z "${SANITIZED_PATH}" ]; then
        SANITIZED_PATH="${p}"
    else
        SANITIZED_PATH="${SANITIZED_PATH}:${p}"
    fi
done

set +e
PAYLOAD="$(cd "${REPO_DIR}" && \
    HOME="${HOME_DIR}" \
    CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
    PATH="${SANITIZED_PATH}" \
    bash "${PLUGIN_ROOT}/hooks/session-start.sh")"
RC=$?
set -e

assert_eq 'hook exit 0 even with missing gh' '0' "$(printf '%d' "${RC}")"
assert_valid_json 'JSON shape valid with dep failure' "${PAYLOAD}"

CONTEXT="$(extract_additional_context "${PAYLOAD}")"
check 'dep alert line present' \
    bash -c 'printf "%s" "$1" | grep -qE "dependency check or routing-block issue"' _ "${CONTEXT}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6: hook exits 0 even when check-deps.sh is missing
# ---------------------------------------------------------------------------
printf 'Scenario 6: check-deps.sh missing (hook still exits 0)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
REPO_DIR="${TMP}/repo"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_plugin_root "${PLUGIN_ROOT}" "0.2.0"
make_repo "${REPO_DIR}"

cat > "${HOME_DIR}/.board-superpowers/manifest.yml" <<EOF
schema_version: 1
host_bootstrapped_at: "2026-01-01T00:00:00Z"
last_seen_version: "0.2.0"
EOF
NORM_REPO_DIR="$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)"
NORM="$(normalize_for_test "${NORM_REPO_DIR}")"
mkdir -p "${HOME_DIR}/.board-superpowers/repos/${NORM}"
cat > "${HOME_DIR}/.board-superpowers/repos/${NORM}/state.yml" <<EOF
schema_version: 1
EOF

# Remove check-deps.sh entirely.
rm -f "${PLUGIN_ROOT}/scripts/check-deps.sh"

set +e
PAYLOAD="$(run_hook "${PLUGIN_ROOT}" "${HOME_DIR}" "${REPO_DIR}")"
RC=$?
set -e

assert_eq 'hook exit 0 with missing check-deps.sh' '0' "$(printf '%d' "${RC}")"
assert_valid_json 'JSON still valid' "${PAYLOAD}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 7: payload always parses as JSON
# ---------------------------------------------------------------------------
printf 'Scenario 7: JSON validity across permutations\n'

for manifest_state in present absent; do
    for state_yml in present absent; do
        TMP="$(mktemp -d)"
        HOME_DIR="${TMP}/home"
        PLUGIN_ROOT="${TMP}/plugin"
        REPO_DIR="${TMP}/repo"
        mkdir -p "${HOME_DIR}/.board-superpowers"
        make_plugin_root "${PLUGIN_ROOT}" "0.2.0"
        make_repo "${REPO_DIR}"

        if [ "${manifest_state}" = "present" ]; then
            cat > "${HOME_DIR}/.board-superpowers/manifest.yml" <<EOF
schema_version: 1
last_seen_version: "0.2.0"
EOF
        fi
        NORM_REPO_DIR="$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)"
        NORM="$(normalize_for_test "${NORM_REPO_DIR}")"
        if [ "${state_yml}" = "present" ]; then
            mkdir -p "${HOME_DIR}/.board-superpowers/repos/${NORM}"
            printf 'schema_version: 1\n' > "${HOME_DIR}/.board-superpowers/repos/${NORM}/state.yml"
        fi

        set +e
        PAYLOAD="$(run_hook "${PLUGIN_ROOT}" "${HOME_DIR}" "${REPO_DIR}")"
        set -e
        assert_valid_json "JSON valid (manifest=${manifest_state}, state=${state_yml})" "${PAYLOAD}"
        rm -rf "${TMP}"
    done
done

# ---------------------------------------------------------------------------
# Scenario 8: pathological dep-name input is sanitized before interpolation
# ---------------------------------------------------------------------------
printf 'Scenario 8: sanitization of pathological dep-name characters\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
REPO_DIR="${TMP}/repo"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_plugin_root "${PLUGIN_ROOT}" "0.2.0"
make_repo "${REPO_DIR}"

cat > "${HOME_DIR}/.board-superpowers/manifest.yml" <<EOF
schema_version: 1
last_seen_version: "0.2.0"
EOF
NORM_REPO_DIR="$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)"
NORM="$(normalize_for_test "${NORM_REPO_DIR}")"
mkdir -p "${HOME_DIR}/.board-superpowers/repos/${NORM}"
printf 'schema_version: 1\n' > "${HOME_DIR}/.board-superpowers/repos/${NORM}/state.yml"

# Replace the real check-deps.sh in the stub plugin root with a fake
# that emits hostile MISSING= contents. The hook must sanitize them
# before they hit additionalContext.
cat > "${PLUGIN_ROOT}/scripts/check-deps.sh" <<'EOF'
#!/usr/bin/env bash
# Fake check-deps emitting pathological characters.
printf 'MISSING=gh<script>alert(1)</script>,$(rm -rf /),python3\n'
printf 'ROUTING_INJECTED=yes\n'
printf 'PROJECT=/tmp/test\n'
exit 0
EOF
chmod +x "${PLUGIN_ROOT}/scripts/check-deps.sh"

set +e
PAYLOAD="$(run_hook "${PLUGIN_ROOT}" "${HOME_DIR}" "${REPO_DIR}")"
RC=$?
set -e

assert_eq 'hook exit 0 with pathological dep names' '0' "$(printf '%d' "${RC}")"
assert_valid_json 'JSON valid with pathological input' "${PAYLOAD}"

CONTEXT="$(extract_additional_context "${PAYLOAD}")"
check_not 'no <script> tag survives sanitization' \
    bash -c 'printf "%s" "$1" | grep -q "<script>"' _ "${CONTEXT}"
check_not 'no $( substring survives sanitization' \
    bash -c 'printf "%s" "$1" | grep -qF "\$("' _ "${CONTEXT}"
check_not 'no </script> closing tag survives' \
    bash -c 'printf "%s" "$1" | grep -q "</script>"' _ "${CONTEXT}"
check 'sanitized python3 token survives (alnum content kept)' \
    bash -c 'printf "%s" "$1" | grep -q "python3"' _ "${CONTEXT}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 9: version banner reads from plugin.json (stub override)
# ---------------------------------------------------------------------------
printf 'Scenario 9: version banner reflects plugin.json version\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
REPO_DIR="${TMP}/repo"
mkdir -p "${HOME_DIR}/.board-superpowers"
make_plugin_root "${PLUGIN_ROOT}" "9.9.9-test"
make_repo "${REPO_DIR}"

cat > "${HOME_DIR}/.board-superpowers/manifest.yml" <<EOF
schema_version: 1
last_seen_version: "9.9.9-test"
EOF
NORM_REPO_DIR="$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)"
NORM="$(normalize_for_test "${NORM_REPO_DIR}")"
mkdir -p "${HOME_DIR}/.board-superpowers/repos/${NORM}"
printf 'schema_version: 1\n' > "${HOME_DIR}/.board-superpowers/repos/${NORM}/state.yml"

set +e
PAYLOAD="$(run_hook "${PLUGIN_ROOT}" "${HOME_DIR}" "${REPO_DIR}")"
set -e
CONTEXT="$(extract_additional_context "${PAYLOAD}")"
check 'banner reflects plugin.json version 9.9.9-test' \
    bash -c 'printf "%s" "$1" | grep -q "board-superpowers v9.9.9-test loaded."' _ "${CONTEXT}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 10: hook does not source common.sh (self-contained invariant)
# ---------------------------------------------------------------------------
printf 'Scenario 10: hook is self-contained (does not source lib/common.sh)\n'

# Static check: the hook source MUST NOT contain a `. .../common.sh`
# or `source .../common.sh` line (allowing for whitespace variance).
check_not 'hook does not source common.sh' \
    grep -qE '^[[:space:]]*(\.|source)[[:space:]]+.*common\.sh' "${HOOK}"

# Runtime check: a hermetic invocation where lib/common.sh is REMOVED
# must still succeed and emit valid JSON.
TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
REPO_DIR="${TMP}/repo"
mkdir -p "${HOME_DIR}"
make_plugin_root "${PLUGIN_ROOT}" "0.2.0"
make_repo "${REPO_DIR}"

# Delete the lib entirely.
rm -rf "${PLUGIN_ROOT}/scripts/lib"

set +e
PAYLOAD="$(run_hook "${PLUGIN_ROOT}" "${HOME_DIR}" "${REPO_DIR}")"
RC=$?
set -e

assert_eq 'hook exit 0 with lib/ removed' '0' "$(printf '%d' "${RC}")"
assert_valid_json 'JSON valid with lib/ removed' "${PAYLOAD}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
