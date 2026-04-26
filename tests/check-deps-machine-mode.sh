#!/usr/bin/env bash
# tests/check-deps-machine-mode.sh — assert scripts/check-deps.sh --machine
# output contract per docs/architecture/0005-contracts/01-script-contracts.md
# § "scripts/check-deps.sh" Stdout/stderr table (lines 90-97) and per
# 0002-product-features-and-flows/05-bootstrap-surface.md lines 173-183.
#
# Contract under test:
#   - exit code is ALWAYS 0 (output channel signals state, not exit code)
#   - empty stdout when everything is OK (callers test `-z`)
#   - exactly three lines, key order MISSING / ROUTING_INJECTED / PROJECT,
#     when at least one of:
#       * a dependency is missing (PATH or runtime-scope failure)
#       * the routing block is missing on an existing AGENTS.md / CLAUDE.md
#   - MISSING value: comma-separated bare tool names (gh, python3, git);
#     same token whether the tool is absent from PATH or fails a runtime
#     check (so the hook side sees `gh` flagged either way).
#   - ROUTING_INJECTED is `yes` or `no`. Asymmetric skip semantics: no
#     AGENTS.md AND no CLAUDE.md → yes; non-git CLAUDE_PROJECT_DIR → yes.
#   - PROJECT: absolute path of git toplevel when CLAUDE_PROJECT_DIR is
#     inside a repo, else the path itself.
#
# Hermeticity: every scenario sets up its own tmp dirs + stubs. NO
# scenario depends on host gh credentials, PWD inheritance, or repo state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK_DEPS="${PLUGIN_ROOT}/scripts/check-deps.sh"

if [ ! -f "${CHECK_DEPS}" ]; then
    printf 'FATAL: %s not found\n' "${CHECK_DEPS}" >&2
    exit 99
fi

PASS=0
FAIL=0

assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "${actual}" = "${expected}" ]; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n' "${label}" >&2
        printf '    expected: %q\n' "${expected}" >&2
        printf '    actual:   %q\n' "${actual}" >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_match() {
    local label="$1"
    local pattern="$2"
    local actual="$3"
    if printf '%s' "${actual}" | grep -qE "${pattern}"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n' "${label}" >&2
        printf '    pattern:  %s\n' "${pattern}" >&2
        printf '    actual:   %q\n' "${actual}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# Helper: write a `gh` stub into <dir>. Reports the given scopes string on
# `gh auth status` (real gh emits scopes on stderr). Same shape as the
# stub used by tests/check-deps-exit-codes.sh.
stub_gh() {
    local dir="${1:?usage: stub_gh <dir> <scopes>}"
    local scopes="${2:?usage: stub_gh <dir> <scopes>}"
    cat > "${dir}/gh" <<STUB
#!/usr/bin/env bash
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

# Helper: capture (stdout, exit-code) of `check-deps.sh --machine` invoked
# in a controlled environment. Sets PATH, cwd, CLAUDE_PROJECT_DIR.
# Args: <stub-dir> <project-dir> <claude-project-dir>
# Returns stdout via STDOUT_CAPTURE, exit via RC_CAPTURE (globals).
run_machine() {
    local stub_dir="${1:?}"
    local project_dir="${2:?}"
    local claude_project_dir="${3:?}"
    local rc=0
    STDOUT_CAPTURE="$(
        cd "${project_dir}"
        env -i \
            HOME="${HOME}" \
            PATH="${stub_dir}:/usr/bin:/bin" \
            CLAUDE_PROJECT_DIR="${claude_project_dir}" \
            bash "${CHECK_DEPS}" --machine 2>/dev/null
    )" || rc=$?
    RC_CAPTURE="${rc}"
}

# Same, but with a bare PATH (no stub dir) so `gh` is genuinely absent.
run_machine_no_stub() {
    local project_dir="${1:?}"
    local claude_project_dir="${2:?}"
    local rc=0
    STDOUT_CAPTURE="$(
        cd "${project_dir}"
        env -i \
            HOME="${HOME}" \
            PATH="/usr/bin:/bin" \
            CLAUDE_PROJECT_DIR="${claude_project_dir}" \
            bash "${CHECK_DEPS}" --machine 2>/dev/null
    )" || rc=$?
    RC_CAPTURE="${rc}"
}

# --- Scenario 1: hermetic happy path ------------------------------------
# Tmp git repo + routing block + stubbed gh with project scope. Empty
# stdout, exit 0.

scenario_happy_hermetic() {
    printf 'Scenario: hermetic happy path → empty stdout, exit 0\n'
    local tmp project_dir stub_dir
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    project_dir="${tmp}/project"
    stub_dir="${tmp}/stubs"
    mkdir -p "${project_dir}" "${stub_dir}"
    (
        cd "${project_dir}"
        git init -q
        printf '## board-superpowers session routing\n\nstub.\n' > AGENTS.md
    )
    stub_gh "${stub_dir}" "'gist', 'project', 'repo'"
    run_machine "${stub_dir}" "${project_dir}" "${project_dir}"
    assert_eq "happy path → exit 0" "0" "${RC_CAPTURE}"
    assert_eq "happy path → empty stdout" "" "${STDOUT_CAPTURE}"
}

# --- Scenario 2: missing dep --------------------------------------------
# PATH lacks gh; routing block present. → exit 0, three lines emitted with
# MISSING=gh, ROUTING_INJECTED=yes.

scenario_missing_dep() {
    printf 'Scenario: missing dep (PATH lacks gh) → MISSING=gh, ROUTING_INJECTED=yes\n'
    local tmp project_dir
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
    run_machine_no_stub "${project_dir}" "${project_dir}"
    assert_eq "missing dep → exit 0" "0" "${RC_CAPTURE}"
    assert_match "stdout has MISSING=gh line" "^MISSING=gh\$" "${STDOUT_CAPTURE}"
    assert_match "stdout has ROUTING_INJECTED=yes" "^ROUTING_INJECTED=yes\$" "${STDOUT_CAPTURE}"
    assert_match "stdout has PROJECT=<absolute>" "^PROJECT=/" "${STDOUT_CAPTURE}"
    # Assert exactly three keyed lines. Bash command substitution strips
    # the trailing LF from STDOUT_CAPTURE, so a 3-line output becomes a
    # string with 2 internal LFs. Count by appending a sentinel LF and
    # using `wc -l`, which then sees exactly 3 newlines.
    local line_count
    line_count="$(printf '%s\n' "${STDOUT_CAPTURE}" | wc -l | tr -d ' ')"
    assert_eq "stdout is exactly 3 lines" "3" "${line_count}"
}

# --- Scenario 3: missing routing ----------------------------------------
# AGENTS.md present without heading; deps OK. → exit 0, MISSING= empty,
# ROUTING_INJECTED=no.

scenario_missing_routing() {
    printf 'Scenario: AGENTS.md without routing heading → MISSING=, ROUTING_INJECTED=no\n'
    local tmp project_dir stub_dir
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
    run_machine "${stub_dir}" "${project_dir}" "${project_dir}"
    assert_eq "missing routing → exit 0" "0" "${RC_CAPTURE}"
    assert_match "stdout has MISSING= (empty value)" "^MISSING=\$" "${STDOUT_CAPTURE}"
    assert_match "stdout has ROUTING_INJECTED=no" "^ROUTING_INJECTED=no\$" "${STDOUT_CAPTURE}"
    assert_match "stdout has PROJECT=<absolute>" "^PROJECT=/" "${STDOUT_CAPTURE}"
}

# --- Scenario 4: combined missing dep AND missing routing ----------------
# PATH lacks gh AND AGENTS.md lacks heading. → MISSING=gh, ROUTING_INJECTED=no.

scenario_combined() {
    printf 'Scenario: missing dep AND missing routing → MISSING=gh, ROUTING_INJECTED=no\n'
    local tmp project_dir
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    project_dir="${tmp}/project"
    mkdir -p "${project_dir}"
    (
        cd "${project_dir}"
        git init -q
        printf '# No routing here\n' > AGENTS.md
    )
    run_machine_no_stub "${project_dir}" "${project_dir}"
    assert_eq "combined → exit 0" "0" "${RC_CAPTURE}"
    assert_match "stdout has MISSING=gh" "^MISSING=gh\$" "${STDOUT_CAPTURE}"
    assert_match "stdout has ROUTING_INJECTED=no" "^ROUTING_INJECTED=no\$" "${STDOUT_CAPTURE}"
}

# --- Scenario 5: runtime failure (gh present without project scope) -----
# gh exists but lacks project scope. Routing block present. The runtime
# failure → MISSING=gh (same bucket as PATH-absent), ROUTING_INJECTED=yes.

scenario_runtime_failure() {
    printf 'Scenario: gh without project scope → MISSING=gh, ROUTING_INJECTED=yes\n'
    local tmp project_dir stub_dir
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
    run_machine "${stub_dir}" "${project_dir}" "${project_dir}"
    assert_eq "runtime failure → exit 0" "0" "${RC_CAPTURE}"
    assert_match "stdout has MISSING=gh" "^MISSING=gh\$" "${STDOUT_CAPTURE}"
    assert_match "stdout has ROUTING_INJECTED=yes" "^ROUTING_INJECTED=yes\$" "${STDOUT_CAPTURE}"
}

# --- Scenario 6: CLAUDE_PROJECT_DIR override ----------------------------
# cwd is an empty tmp dir; CLAUDE_PROJECT_DIR points at the routing-block
# repo. → ROUTING_INJECTED=yes; PROJECT is the CLAUDE_PROJECT_DIR's git
# toplevel.

scenario_claude_project_dir_override() {
    printf 'Scenario: CLAUDE_PROJECT_DIR override → PROJECT reflects override path\n'
    local tmp empty_dir routing_dir stub_dir
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    empty_dir="${tmp}/empty"
    routing_dir="${tmp}/routing"
    stub_dir="${tmp}/stubs"
    mkdir -p "${empty_dir}" "${routing_dir}" "${stub_dir}"
    (
        cd "${routing_dir}"
        git init -q
        printf '## board-superpowers session routing\n' > AGENTS.md
    )
    stub_gh "${stub_dir}" "'gist', 'project', 'repo'"
    # All deps + routing OK against routing_dir → empty stdout expected.
    run_machine "${stub_dir}" "${empty_dir}" "${routing_dir}"
    assert_eq "override happy → exit 0" "0" "${RC_CAPTURE}"
    assert_eq "override happy → empty stdout (everything OK)" "" "${STDOUT_CAPTURE}"

    # Now flip: routing_dir without heading → must surface ROUTING_INJECTED=no
    # AND PROJECT pointing at routing_dir, not empty_dir.
    rm "${routing_dir}/AGENTS.md"
    printf '# No heading\n' > "${routing_dir}/AGENTS.md"
    run_machine "${stub_dir}" "${empty_dir}" "${routing_dir}"
    assert_eq "override missing routing → exit 0" "0" "${RC_CAPTURE}"
    assert_match "stdout has ROUTING_INJECTED=no" "^ROUTING_INJECTED=no\$" "${STDOUT_CAPTURE}"
    # macOS resolves /tmp via /private/tmp, so match the basename suffix.
    assert_match "stdout PROJECT references routing dir" "^PROJECT=.*/routing\$" "${STDOUT_CAPTURE}"
}

# --- Scenario 7: non-git CLAUDE_PROJECT_DIR -----------------------------
# Non-git dir → routing check skipped → ROUTING_INJECTED=yes. With deps
# all OK, stdout is empty. Verify by also creating a missing-dep variant
# to confirm PROJECT keeps the literal path (not a git toplevel).

scenario_non_git_project_dir() {
    printf 'Scenario: non-git CLAUDE_PROJECT_DIR → ROUTING_INJECTED=yes (skip)\n'
    local tmp non_git_dir stub_dir
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    non_git_dir="${tmp}/not-a-repo"
    stub_dir="${tmp}/stubs"
    mkdir -p "${non_git_dir}" "${stub_dir}"
    stub_gh "${stub_dir}" "'gist', 'project', 'repo'"
    # Deps OK, non-git project dir → routing skipped → empty stdout.
    run_machine "${stub_dir}" "${non_git_dir}" "${non_git_dir}"
    assert_eq "non-git happy → exit 0" "0" "${RC_CAPTURE}"
    assert_eq "non-git happy → empty stdout" "" "${STDOUT_CAPTURE}"

    # Now drop the gh stub so MISSING=gh trips. Must still emit
    # ROUTING_INJECTED=yes, plus PROJECT pointing at the non-git dir.
    run_machine_no_stub "${non_git_dir}" "${non_git_dir}"
    assert_eq "non-git missing dep → exit 0" "0" "${RC_CAPTURE}"
    assert_match "stdout has MISSING=gh" "^MISSING=gh\$" "${STDOUT_CAPTURE}"
    assert_match "stdout has ROUTING_INJECTED=yes" "^ROUTING_INJECTED=yes\$" "${STDOUT_CAPTURE}"
    assert_match "stdout PROJECT is the non-git path" "^PROJECT=.*/not-a-repo\$" "${STDOUT_CAPTURE}"
    # Spec 01-script-contracts.md line 93: PROJECT=<absolute path>.
    # Non-git CLAUDE_PROJECT_DIR must still emit an absolute path.
    local project_value
    project_value="$(printf '%s\n' "${STDOUT_CAPTURE}" | grep '^PROJECT=' | sed 's/^PROJECT=//')"
    case "${project_value}" in
        /*) assert_eq "PROJECT value is absolute (starts with /)" "absolute" "absolute" ;;
        *)  assert_eq "PROJECT value is absolute (starts with /)" "absolute" "relative: ${project_value}" ;;
    esac
}

# --- Scenario 8: relative CLAUDE_PROJECT_DIR (existing non-git dir) ------
# Caller passes a relative CLAUDE_PROJECT_DIR resolving to an existing
# non-git directory. Spec 01-script-contracts.md line 93 mandates
# PROJECT=<absolute path> regardless of how the caller spelled the input.
# Without the absolutize() fix the script leaks the literal `../foo`
# value into machine-mode stdout.

scenario_relative_existing_non_git() {
    printf 'Scenario: relative CLAUDE_PROJECT_DIR (existing non-git) → PROJECT absolute\n'
    local tmp non_git_dir cwd_dir
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    non_git_dir="${tmp}/sibling-non-git"
    cwd_dir="${tmp}/cwd"
    mkdir -p "${non_git_dir}" "${cwd_dir}"
    # cwd is ${cwd_dir}; relative path ../sibling-non-git points at
    # the existing non-git dir. Bare PATH so MISSING=gh trips and forces
    # machine-mode emission.
    local rc=0
    STDOUT_CAPTURE="$(
        cd "${cwd_dir}"
        env -i \
            HOME="${HOME}" \
            PATH="/usr/bin:/bin" \
            CLAUDE_PROJECT_DIR="../sibling-non-git" \
            bash "${CHECK_DEPS}" --machine 2>/dev/null
    )" || rc=$?
    RC_CAPTURE="${rc}"
    assert_eq "relative non-git → exit 0" "0" "${RC_CAPTURE}"
    assert_match "stdout has MISSING=gh" "^MISSING=gh\$" "${STDOUT_CAPTURE}"
    assert_match "stdout has ROUTING_INJECTED=yes" "^ROUTING_INJECTED=yes\$" "${STDOUT_CAPTURE}"
    assert_match "stdout PROJECT starts with /" "^PROJECT=/" "${STDOUT_CAPTURE}"
    assert_match "stdout PROJECT resolves to sibling-non-git" "^PROJECT=.*/sibling-non-git\$" "${STDOUT_CAPTURE}"
}

# --- Scenario 9: nonexistent CLAUDE_PROJECT_DIR --------------------------
# Caller passes a path that doesn't exist. Per spec, PROJECT= must still
# be absolute. Routing check is skipped (dir doesn't exist) →
# ROUTING_INJECTED=yes. We use a bare PATH so MISSING=gh trips and forces
# the three-line emission.

scenario_nonexistent_project_dir() {
    printf 'Scenario: nonexistent CLAUDE_PROJECT_DIR → PROJECT absolute, ROUTING_INJECTED=yes\n'
    local tmp cwd_dir bogus
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    cwd_dir="${tmp}/cwd"
    mkdir -p "${cwd_dir}"
    bogus="/nonexistent/path-that-does-not-exist-$$"
    local rc=0
    STDOUT_CAPTURE="$(
        cd "${cwd_dir}"
        env -i \
            HOME="${HOME}" \
            PATH="/usr/bin:/bin" \
            CLAUDE_PROJECT_DIR="${bogus}" \
            bash "${CHECK_DEPS}" --machine 2>/dev/null
    )" || rc=$?
    RC_CAPTURE="${rc}"
    assert_eq "nonexistent → exit 0" "0" "${RC_CAPTURE}"
    assert_match "stdout has MISSING=gh" "^MISSING=gh\$" "${STDOUT_CAPTURE}"
    assert_match "stdout has ROUTING_INJECTED=yes" "^ROUTING_INJECTED=yes\$" "${STDOUT_CAPTURE}"
    assert_match "stdout PROJECT starts with /" "^PROJECT=/" "${STDOUT_CAPTURE}"
}

# --- Run ----------------------------------------------------------------

scenario_happy_hermetic
scenario_missing_dep
scenario_missing_routing
scenario_combined
scenario_runtime_failure
scenario_claude_project_dir_override
scenario_non_git_project_dir
scenario_relative_existing_non_git
scenario_nonexistent_project_dir

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
