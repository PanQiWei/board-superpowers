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
# Hermeticity policy: every scenario sets up its own tmp git repo + stubs
# `gh` onto a controlled PATH. NO scenario depends on the host's real gh
# auth state, on the plugin repo being checked out, or on any global env.
# This way the suite passes on a vanilla CI runner (no gh credentials).
#
# An optional real-environment scenario at the bottom is gated on
# BSP_TEST_REAL_ENV=1 for cases where the maintainer wants to additionally
# verify the script behaves correctly against the live plugin repo.

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

# Helper: write a `gh` stub into <dir> that responds to `gh auth status`
# with the given scopes string. Real gh emits scopes on stderr; mimic that
# so check-deps.sh's `gh auth status 2>&1 | grep` keeps working.
#
# Usage: stub_gh <dir> <scopes-string>
#   <scopes-string> example: "'gist', 'project', 'repo'"
stub_gh() {
    local dir="${1:?usage: stub_gh <dir> <scopes>}"
    local scopes="${2:?usage: stub_gh <dir> <scopes>}"
    cat > "${dir}/gh" <<STUB
#!/usr/bin/env bash
# Stub gh: report fixed scopes on auth status; no-op otherwise.
case "\${1:-}" in
    auth)
        printf 'github.com\n  Logged in to github.com\n  Token scopes: %s\n' "${scopes}" >&2
        exit 0
        ;;
    *)
        printf 'stub gh: subcommand %s unsupported\n' "\${1:-}" >&2
        exit 0
        ;;
esac
STUB
    chmod +x "${dir}/gh"
}

# Helper: run check-deps.sh in a fully controlled environment.
#   - PATH = <stub-dir>:/usr/bin:/bin (stub gh wins; real python3+git remain)
#   - cwd / CLAUDE_PROJECT_DIR = <project-dir>
# Args: <stub-dir> <project-dir> [extra-env-pair ...]
run_check_deps_in() {
    local stub_dir="${1:?}"
    local project_dir="${2:?}"
    shift 2
    (
        cd "${project_dir}"
        env -i \
            HOME="${HOME}" \
            PATH="${stub_dir}:/usr/bin:/bin" \
            CLAUDE_PROJECT_DIR="${project_dir}" \
            "$@" \
            bash "${CHECK_DEPS}" >/dev/null 2>&1
    )
}

# --- Scenario 1: hermetic happy path ------------------------------------
# Tmp git repo with synthetic AGENTS.md routing heading. Stubbed gh
# reports project scope. Real python3 + git on PATH. → exit 0.

scenario_happy_hermetic() {
    printf 'Scenario: hermetic happy path (synthetic repo + stubbed gh)\n'
    local tmp project_dir stub_dir rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    project_dir="${tmp}/project"
    stub_dir="${tmp}/stubs"
    mkdir -p "${project_dir}" "${stub_dir}"
    (
        cd "${project_dir}"
        git init -q
        printf '# Project agents file\n\n## board-superpowers session routing\n\nstub.\n' > AGENTS.md
    )
    stub_gh "${stub_dir}" "'gist', 'project', 'repo'"
    run_check_deps_in "${stub_dir}" "${project_dir}" || rc=$?
    assert_exit_code "happy path returns 0" "0" "${rc}"
}

# --- Scenario 2: missing dep --------------------------------------------
# Empty stub dir (no gh shadow). PATH stripped to /usr/bin:/bin which has
# python3 + git but not gh. Synthetic project with routing block so only
# the missing-dep failure trips. → exit 2.

scenario_missing_dep() {
    printf 'Scenario: missing dep (PATH lacks gh)\n'
    local tmp project_dir rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    project_dir="${tmp}/project"
    mkdir -p "${project_dir}"
    (
        cd "${project_dir}"
        git init -q
        printf '## board-superpowers session routing\n' > AGENTS.md
    )
    (
        cd "${project_dir}"
        env -i \
            HOME="${HOME}" \
            PATH="/usr/bin:/bin" \
            CLAUDE_PROJECT_DIR="${project_dir}" \
            bash "${CHECK_DEPS}" >/dev/null 2>&1
    ) || rc=$?
    assert_exit_code "missing gh → exit 2" "2" "${rc}"
}

# --- Scenario 3: missing routing block ----------------------------------
# Per spec: AGENTS.md / CLAUDE.md exists but lacks the
# "## board-superpowers session routing" heading → exit 2.

scenario_missing_routing_block() {
    printf 'Scenario: AGENTS.md present but no routing-block heading\n'
    local tmp project_dir stub_dir rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    project_dir="${tmp}/project"
    stub_dir="${tmp}/stubs"
    mkdir -p "${project_dir}" "${stub_dir}"
    (
        cd "${project_dir}"
        git init -q
        printf '# Bare project agents file\n\nNo routing block here.\n' > AGENTS.md
    )
    stub_gh "${stub_dir}" "'gist', 'project', 'repo'"
    run_check_deps_in "${stub_dir}" "${project_dir}" || rc=$?
    assert_exit_code "AGENTS.md without routing → exit 2" "2" "${rc}"
}

# --- Scenario 4: skipped routing check (no markdown files) --------------
# Spec asymmetric rule: no AGENTS.md AND no CLAUDE.md → routing check is
# skipped entirely (exit 0 if deps OK).

scenario_no_md_skipped() {
    printf 'Scenario: no AGENTS.md / CLAUDE.md (routing check skipped)\n'
    local tmp project_dir stub_dir rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    project_dir="${tmp}/project"
    stub_dir="${tmp}/stubs"
    mkdir -p "${project_dir}" "${stub_dir}"
    (
        cd "${project_dir}"
        git init -q
    )
    stub_gh "${stub_dir}" "'gist', 'project', 'repo'"
    run_check_deps_in "${stub_dir}" "${project_dir}" || rc=$?
    assert_exit_code "no AGENTS.md / CLAUDE.md → exit 0" "0" "${rc}"
}

# --- Scenario 5: runtime cmd unavailable (gh present, no project scope) -
# Stubbed gh reports scopes WITHOUT project. → exit 3.

scenario_runtime_unavailable() {
    printf 'Scenario: gh exists but lacks project scope (runtime failure)\n'
    local tmp project_dir stub_dir rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    project_dir="${tmp}/project"
    stub_dir="${tmp}/stubs"
    mkdir -p "${project_dir}" "${stub_dir}"
    (
        cd "${project_dir}"
        git init -q
        printf '## board-superpowers session routing\n' > AGENTS.md
    )
    stub_gh "${stub_dir}" "'gist', 'repo'"
    run_check_deps_in "${stub_dir}" "${project_dir}" || rc=$?
    assert_exit_code "gh without project scope → exit 3" "3" "${rc}"
}

# --- Scenario 6: CLAUDE_PROJECT_DIR overrides cwd -----------------------
# Per spec lines 161-162: $CLAUDE_PROJECT_DIR (defaults to $PWD) is the
# input for plugin / skill path resolution. The routing-block check MUST
# evaluate against $CLAUDE_PROJECT_DIR, not cwd. This scenario stands cwd
# in a "good" git repo (with routing block) and points CLAUDE_PROJECT_DIR
# at a different repo MISSING the routing block — the script must report
# the missing routing block from the CLAUDE_PROJECT_DIR repo.

scenario_claude_project_dir_overrides_cwd() {
    printf 'Scenario: CLAUDE_PROJECT_DIR overrides cwd for routing check\n'
    local tmp good_dir bad_dir stub_dir rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    good_dir="${tmp}/good"
    bad_dir="${tmp}/bad"
    stub_dir="${tmp}/stubs"
    mkdir -p "${good_dir}" "${bad_dir}" "${stub_dir}"

    # cwd-side repo: HAS the routing block (would pass on its own).
    (
        cd "${good_dir}"
        git init -q
        printf '## board-superpowers session routing\n' > AGENTS.md
    )
    # CLAUDE_PROJECT_DIR-side repo: MISSING the routing block.
    (
        cd "${bad_dir}"
        git init -q
        printf '# Bare project — no routing block.\n' > AGENTS.md
    )
    stub_gh "${stub_dir}" "'gist', 'project', 'repo'"

    # cwd = good_dir, CLAUDE_PROJECT_DIR = bad_dir → must report missing
    # routing block from bad_dir → exit 2.
    (
        cd "${good_dir}"
        env -i \
            HOME="${HOME}" \
            PATH="${stub_dir}:/usr/bin:/bin" \
            CLAUDE_PROJECT_DIR="${bad_dir}" \
            bash "${CHECK_DEPS}" >/dev/null 2>&1
    ) || rc=$?
    assert_exit_code "CLAUDE_PROJECT_DIR=bad_dir → exit 2 (not cwd's good_dir)" "2" "${rc}"
}

# --- Scenario 7: CLAUDE_PROJECT_DIR points at non-git dir ---------------
# Spec rule: "If CLAUDE_PROJECT_DIR is set but is not a git repo, treat
# as outside-git (skip routing check, exit 0 path stays valid)".

scenario_claude_project_dir_non_git() {
    printf 'Scenario: CLAUDE_PROJECT_DIR points at a non-git dir (skip routing)\n'
    local tmp non_git_dir stub_dir rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    non_git_dir="${tmp}/not-a-repo"
    stub_dir="${tmp}/stubs"
    mkdir -p "${non_git_dir}" "${stub_dir}"
    stub_gh "${stub_dir}" "'gist', 'project', 'repo'"
    (
        cd "${non_git_dir}"
        env -i \
            HOME="${HOME}" \
            PATH="${stub_dir}:/usr/bin:/bin" \
            CLAUDE_PROJECT_DIR="${non_git_dir}" \
            bash "${CHECK_DEPS}" >/dev/null 2>&1
    ) || rc=$?
    assert_exit_code "non-git CLAUDE_PROJECT_DIR → exit 0" "0" "${rc}"
}

# --- Optional Scenario: real-environment cross-check --------------------
# Gated on BSP_TEST_REAL_ENV=1. Verifies the plugin repo's actual state
# satisfies the dep contract end-to-end. Skipped by default for hermeticity.

scenario_real_env_optional() {
    if [ "${BSP_TEST_REAL_ENV:-0}" != "1" ]; then
        printf 'Scenario: real-environment cross-check (skipped — set BSP_TEST_REAL_ENV=1 to run)\n'
        return
    fi
    printf 'Scenario: real-environment cross-check (BSP_TEST_REAL_ENV=1)\n'
    local rc=0
    ( cd "${PLUGIN_ROOT}" && bash "${CHECK_DEPS}" >/dev/null 2>&1 ) || rc=$?
    assert_exit_code "real env happy path returns 0" "0" "${rc}"
}

# --- Run ---------------------------------------------------------------

scenario_happy_hermetic
scenario_missing_dep
scenario_missing_routing_block
scenario_no_md_skipped
scenario_runtime_unavailable
scenario_claude_project_dir_overrides_cwd
scenario_claude_project_dir_non_git
scenario_real_env_optional

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
