#!/usr/bin/env bash
# tests/check-deps-exit-codes.sh — assert scripts/check-deps.sh exit-code
# contract per docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § "Layer 1 dep check (§1.5.0)" and 0005-contracts/02-hook-contracts.md.
#
# Contract under test:
#   0 — all deps present, routing block present (or no AGENTS.md/CLAUDE.md exists)
#   2 — required binary missing OR AGENTS.md/CLAUDE.md exists without routing marker
#   3 — required binary present but a runtime invariant fails
#       (e.g., `gh` exists but lacks the `project` / `read:project` scope)
#
# This test is hermetic: each scenario sets up its own environment in a
# tmp dir + manipulates PATH, runs check-deps.sh, captures $?, and tears
# down via trap. No global state is mutated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK_DEPS="${PLUGIN_ROOT}/scripts/check-deps.sh"

if [ ! -x "${CHECK_DEPS}" ] && [ ! -f "${CHECK_DEPS}" ]; then
    printf 'FATAL: %s not found\n' "${CHECK_DEPS}" >&2
    exit 99
fi

PASS=0
FAIL=0

assert_exit_code() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "${actual}" = "${expected}" ]; then
        printf '  PASS — %s (exit=%s)\n' "${label}" "${actual}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s: expected exit=%s, got exit=%s\n' "${label}" "${expected}" "${actual}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# --- Scenario 1: happy path ---------------------------------------------
# cwd = plugin repo (AGENTS.md routing block + all deps + gh has project scope).

scenario_happy() {
    printf 'Scenario: happy path (cwd=plugin repo, all deps OK)\n'
    local rc=0
    ( cd "${PLUGIN_ROOT}" && bash "${CHECK_DEPS}" >/dev/null 2>&1 ) || rc=$?
    assert_exit_code "happy path returns 0" "0" "${rc}"
}

# --- Scenario 2: missing dep ---------------------------------------------
# Shadow `gh` by setting PATH to dirs containing python3 + git but not gh.
# /usr/bin has python3 + git on macOS; gh lives in /opt/homebrew/bin which
# we exclude. The cwd stays inside the plugin repo so the routing check
# passes; only the missing dep should trip.

scenario_missing_dep() {
    printf 'Scenario: missing dep (PATH lacks gh)\n'
    local rc=0
    (
        cd "${PLUGIN_ROOT}"
        # /usr/bin + /bin gives us python3 + git but NOT gh.
        PATH="/usr/bin:/bin" bash "${CHECK_DEPS}" >/dev/null 2>&1
    ) || rc=$?
    assert_exit_code "missing gh → exit 2" "2" "${rc}"
}

# --- Scenario 3: missing routing block ----------------------------------
# Per spec: AGENTS.md / CLAUDE.md exists but lacks the
# "## board-superpowers session routing" heading → exit 2.
# (If neither file exists the check is skipped — that case lives in
# scenario_happy_no_md below.)

scenario_missing_routing_block() {
    printf 'Scenario: AGENTS.md present but no routing-block heading\n'
    local tmp rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # tmp is already set; expansion at trap-set time is intentional.
    trap "rm -rf '${tmp}'" RETURN
    (
        cd "${tmp}"
        git init -q
        printf '# Bare project agents file\n\nNo routing block here.\n' > AGENTS.md
        bash "${CHECK_DEPS}" >/dev/null 2>&1
    ) || rc=$?
    assert_exit_code "AGENTS.md without routing → exit 2" "2" "${rc}"
}

# --- Scenario 4: skipped routing check (no markdown files) --------------
# Spec asymmetric rule: no AGENTS.md AND no CLAUDE.md → routing check is
# skipped entirely (exit 0 if deps OK). This guards against the dep check
# becoming noisy in repos that don't use these files at all.

scenario_no_md_skipped() {
    printf 'Scenario: no AGENTS.md / CLAUDE.md (routing check skipped)\n'
    local tmp rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # tmp is already set; expansion at trap-set time is intentional.
    trap "rm -rf '${tmp}'" RETURN
    (
        cd "${tmp}"
        git init -q
        # No AGENTS.md, no CLAUDE.md — routing check should be skipped.
        bash "${CHECK_DEPS}" >/dev/null 2>&1
    ) || rc=$?
    assert_exit_code "no AGENTS.md / CLAUDE.md → exit 0" "0" "${rc}"
}

# --- Scenario 5: runtime cmd unavailable (gh present, no project scope) -
# Stub `gh` so `command -v gh` succeeds but `gh auth status` reports
# scopes without the required `project` / `read:project` token. Per spec
# this is a runtime failure (the binary is installed but the invariant
# the script depends on doesn't hold) → exit 3.

scenario_runtime_unavailable() {
    printf 'Scenario: gh exists but lacks project scope (runtime failure)\n'
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # tmp is already set; expansion at trap-set time is intentional.
    trap "rm -rf '${tmp}'" RETURN
    cat > "${tmp}/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: report no project scope.
case "${1:-}" in
    auth)
        # Mimic real gh: scopes line on stderr.
        printf 'github.com\n  Logged in to github.com\n  Token scopes: '\''gist'\'', '\''repo'\''\n' >&2
        exit 0
        ;;
    *)
        printf 'stub gh: subcommand %s unsupported\n' "$1" >&2
        exit 0
        ;;
esac
STUB
    chmod +x "${tmp}/gh"
    local rc=0
    (
        cd "${PLUGIN_ROOT}"
        # Prepend stub dir BEFORE /usr/bin so the stub wins for `gh`,
        # but real python3/git remain reachable.
        PATH="${tmp}:/usr/bin:/bin" bash "${CHECK_DEPS}" >/dev/null 2>&1
    ) || rc=$?
    assert_exit_code "gh without project scope → exit 3" "3" "${rc}"
}

# --- Run ---------------------------------------------------------------

scenario_happy
scenario_missing_dep
scenario_missing_routing_block
scenario_no_md_skipped
scenario_runtime_unavailable

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
