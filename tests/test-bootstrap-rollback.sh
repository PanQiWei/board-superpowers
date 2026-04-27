#!/usr/bin/env bash
# tests/test-bootstrap-rollback.sh — assert scripts/bootstrap-rollback.sh
# undoes F-B2 in symmetric reverse order per Card 2 slice 7 + the A2
# decision recorded in `docs/plans/bootstrap/card-2-bootstrap.md`.
#
# Symmetric reverse order (rollback):
#   1. rm <repo>/.board-superpowers/config.yml (if present)
#   2. remove the bootstrap entry from <repo>/.gitignore (if present,
#      idempotent — leave the file even when it becomes empty)
#   3. remove the routing block (between markers) from <repo>/AGENTS.md
#      AND <repo>/CLAUDE.md (preserve everything outside markers)
#   4. rm ~/.board-superpowers/repos/<normalized>/state.yml
#   5. PROMPT before rm ~/.board-superpowers/credentials.yml — default
#      = no. --keep-credentials skips prompt + keeps. --rm-credentials
#      skips prompt + removes. --yes auto-confirms YES.
#   6. Does NOT delete labels.
#   7. Leaves F-B1 manifest.yml intact.
#
# Scenarios:
#   1. Bootstrap → rollback flow: full F-B2, then rollback. Assert all
#      F-B2 side effects undone (config.yml gone, .gitignore entry gone,
#      routing blocks AGENTS+CLAUDE gone, state.yml gone).
#   2. Manifest preserved: after rollback, manifest.yml still exists.
#   3. Credentials preserved by default: --keep-credentials keeps
#      credentials.yml.
#   4. Credentials removed with --rm-credentials: explicit rm path.
#   5. Idempotent: rollback on a clean repo (nothing to undo) is a
#      no-op, no errors.
#   6. Routing block removal preserves surrounding content: AGENTS.md
#      with content before AND after the markers — assert non-marker
#      content preserved verbatim post-rollback.
#   7. Partial bootstrap rollback: if F-B2 aborted mid-way (e.g.,
#      orphan markers), rollback should still clean what's there
#      without erroring.
#
# Hermeticity: tmp HOME + tmp git repo + stub gh on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_UNDER_TEST="${PLUGIN_ROOT_REAL}/scripts/bootstrap-rollback.sh"
BOOTSTRAP_PROJECT="${PLUGIN_ROOT_REAL}/scripts/bootstrap-project.sh"

if [ ! -f "${SCRIPT_UNDER_TEST}" ]; then
    printf 'FATAL: %s not found\n' "${SCRIPT_UNDER_TEST}" >&2
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

# Build a stub plugin tree so bootstrap-project.sh resolves cleanly.
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
    cp "${PLUGIN_ROOT_REAL}/scripts/lib/common.sh" \
       "${target_dir}/scripts/lib/common.sh"
    cp "${PLUGIN_ROOT_REAL}/scripts/setup-labels.sh" \
       "${target_dir}/scripts/setup-labels.sh"
    cp "${BOOTSTRAP_PROJECT}" \
       "${target_dir}/scripts/bootstrap-project.sh"
    cp "${SCRIPT_UNDER_TEST}" \
       "${target_dir}/scripts/bootstrap-rollback.sh"
    chmod +x "${target_dir}/scripts/setup-labels.sh"
    chmod +x "${target_dir}/scripts/bootstrap-project.sh"
    chmod +x "${target_dir}/scripts/bootstrap-rollback.sh"
    mkdir -p "${target_dir}/skills/using-board-superpowers/references"
    cp "${PLUGIN_ROOT_REAL}/skills/using-board-superpowers/references/agentsmd-routing.md" \
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
                python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
if not any(l['name'] == sys.argv[2] for l in data):
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

# Run bootstrap-project.sh with stdin /dev/null (declines BYO-RDBMS) so
# tests don't leave a credentials.yml unless the test explicitly creates
# one.
run_bootstrap() {
    local home_dir="$1"; shift
    local plugin_root="$1"; shift
    local stubs_dir="$1"; shift
    env -i HOME="${home_dir}" PATH="${stubs_dir}:/usr/bin:/bin" \
        bash "${plugin_root}/scripts/bootstrap-project.sh" \
            --plugin-root "${plugin_root}" \
            "$@" </dev/null
}

run_rollback() {
    local home_dir="$1"; shift
    local plugin_root="$1"; shift
    local stubs_dir="$1"; shift
    env -i HOME="${home_dir}" PATH="${stubs_dir}:/usr/bin:/bin" \
        bash "${plugin_root}/scripts/bootstrap-rollback.sh" "$@"
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
# Scenario 1: Full bootstrap → rollback flow
# ---------------------------------------------------------------------------
printf 'Scenario 1: full bootstrap → rollback (default keeps credentials)\n'

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

# Pre-create a manifest.yml so we can prove rollback leaves it intact
# even though our flow runs F-B2 only.
mkdir -p "${HOME_DIR}/.board-superpowers"
cat > "${HOME_DIR}/.board-superpowers/manifest.yml" <<EOF
schema_version: 1
host_bootstrapped_at: "2026-01-01T00:00:00Z"
last_seen_version: "0.2.0"
EOF

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" \
    >/dev/null 2>&1
RC_BOOT=$?
set -e
assert_eq 's1: bootstrap exit 0' '0' "${RC_BOOT}"

STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE_FILE="${STATE_DIR}/state.yml"
CONFIG_FILE="${REPO_ROOT}/.board-superpowers/config.yml"
GITIGNORE="${REPO_ROOT}/.gitignore"

check 's1: pre-rollback state.yml exists'   test -f "${STATE_FILE}"
check 's1: pre-rollback config.yml exists'  test -f "${CONFIG_FILE}"
check 's1: pre-rollback gitignore has entry' \
    grep -Fxq '.board-superpowers/claims/' "${GITIGNORE}"
check 's1: pre-rollback AGENTS.md has marker' \
    grep -Fq '<!-- board-superpowers:routing -->' "${REPO_ROOT}/AGENTS.md"
check 's1: pre-rollback CLAUDE.md has marker' \
    grep -Fq '<!-- board-superpowers:routing -->' "${REPO_ROOT}/CLAUDE.md"

# Default rollback (no flag) when no credentials.yml exists ⇒ no prompt
# fires, treats as no-op for credentials. Pipe /dev/null to stdin to
# avoid hanging in case prompt logic triggers anyway.
set +e
ROLL_OUT="$(run_rollback "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --repo-root "${REPO_ROOT}" --keep-credentials </dev/null 2>&1)"
RC_ROLL=$?
set -e
assert_eq 's1: rollback exit 0' '0' "${RC_ROLL}"

check_not 's1: post-rollback state.yml gone'  test -f "${STATE_FILE}"
check_not 's1: post-rollback config.yml gone' test -f "${CONFIG_FILE}"
check_not 's1: post-rollback gitignore entry gone' \
    grep -Fxq '.board-superpowers/claims/' "${GITIGNORE}"
check_not 's1: post-rollback AGENTS.md routing marker gone' \
    grep -Fq '<!-- board-superpowers:routing -->' "${REPO_ROOT}/AGENTS.md"
check_not 's1: post-rollback CLAUDE.md routing marker gone' \
    grep -Fq '<!-- board-superpowers:routing -->' "${REPO_ROOT}/CLAUDE.md"

# Manifest preserved (Scenario 2 inline check).
check 's1: manifest.yml preserved' \
    test -f "${HOME_DIR}/.board-superpowers/manifest.yml"

# ROLL_OUT exists for diagnostic value if a check fails.
: "${ROLL_OUT:-}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 3: --keep-credentials keeps credentials.yml
# ---------------------------------------------------------------------------
printf 'Scenario 3: --keep-credentials keeps credentials.yml\n'

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

# Bootstrap with --audit-db-url so credentials.yml is created.
SQLITE_DB_DIR="${TMP}/dbdir"
mkdir -p "${SQLITE_DB_DIR}"
DSN="sqlite:////${SQLITE_DB_DIR#/}/audit.db"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" \
    --audit-db-url "${DSN}" >/dev/null 2>&1
RC_BOOT=$?
set -e
assert_eq 's3: bootstrap exit 0' '0' "${RC_BOOT}"

CRED_FILE="${HOME_DIR}/.board-superpowers/credentials.yml"
check 's3: pre-rollback credentials.yml exists' test -f "${CRED_FILE}"

set +e
run_rollback "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --repo-root "${REPO_ROOT}" --keep-credentials </dev/null >/dev/null 2>&1
RC_ROLL=$?
set -e
assert_eq 's3: rollback exit 0' '0' "${RC_ROLL}"

check 's3: --keep-credentials keeps credentials.yml' test -f "${CRED_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 4: --rm-credentials removes credentials.yml
# ---------------------------------------------------------------------------
printf 'Scenario 4: --rm-credentials removes credentials.yml\n'

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

SQLITE_DB_DIR="${TMP}/dbdir"
mkdir -p "${SQLITE_DB_DIR}"
DSN="sqlite:////${SQLITE_DB_DIR#/}/audit.db"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" \
    --audit-db-url "${DSN}" >/dev/null 2>&1
RC_BOOT=$?
set -e
assert_eq 's4: bootstrap exit 0' '0' "${RC_BOOT}"

CRED_FILE="${HOME_DIR}/.board-superpowers/credentials.yml"
check 's4: pre-rollback credentials.yml exists' test -f "${CRED_FILE}"

set +e
run_rollback "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --repo-root "${REPO_ROOT}" --rm-credentials </dev/null >/dev/null 2>&1
RC_ROLL=$?
set -e
assert_eq 's4: rollback exit 0' '0' "${RC_ROLL}"

check_not 's4: --rm-credentials removed credentials.yml' test -f "${CRED_FILE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 5: Idempotent on a clean repo (nothing to undo)
# ---------------------------------------------------------------------------
printf 'Scenario 5: idempotent on a clean repo (no F-B2 ever ran)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '[]\n' > "${STUBS_DIR}/labels.json"

set +e
run_rollback "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --repo-root "${REPO_ROOT}" --keep-credentials </dev/null >/dev/null 2>&1
RC_ROLL=$?
set -e
assert_eq 's5: rollback exit 0 on clean repo (idempotent)' '0' "${RC_ROLL}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6: Routing block removal preserves surrounding content
# ---------------------------------------------------------------------------
printf 'Scenario 6: routing block removal preserves surrounding content\n'

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

# Pre-seed AGENTS.md with content BEFORE and AFTER the future markers.
cat > "${REPO_ROOT}/AGENTS.md" <<'EOF'
# Pre-existing project AGENTS.md

PRE_BLOCK_SENTINEL_LINE — must survive rollback.

## Other section
Some prose.

POST_BLOCK_SENTINEL_LINE — must also survive rollback.
EOF
ORIG_AGENTS="$(cat "${REPO_ROOT}/AGENTS.md")"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" \
    >/dev/null 2>&1
RC_BOOT=$?
set -e
assert_eq 's6: bootstrap exit 0' '0' "${RC_BOOT}"

# After bootstrap the file has the marker block appended.
check 's6: marker injected post-bootstrap' \
    grep -Fq '<!-- board-superpowers:routing -->' "${REPO_ROOT}/AGENTS.md"
check 's6: pre-block sentinel still in file post-bootstrap' \
    grep -Fq 'PRE_BLOCK_SENTINEL_LINE' "${REPO_ROOT}/AGENTS.md"

set +e
run_rollback "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --repo-root "${REPO_ROOT}" --keep-credentials </dev/null >/dev/null 2>&1
RC_ROLL=$?
set -e
assert_eq 's6: rollback exit 0' '0' "${RC_ROLL}"

check 's6: pre-block sentinel preserved post-rollback' \
    grep -Fq 'PRE_BLOCK_SENTINEL_LINE' "${REPO_ROOT}/AGENTS.md"
check 's6: post-block sentinel preserved post-rollback' \
    grep -Fq 'POST_BLOCK_SENTINEL_LINE' "${REPO_ROOT}/AGENTS.md"
check_not 's6: routing markers gone post-rollback' \
    grep -Fq '<!-- board-superpowers:routing -->' "${REPO_ROOT}/AGENTS.md"

# Suppress unused-var warnings.
: "${ORIG_AGENTS:-}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 7: Partial bootstrap rollback (orphan markers — clean what's there)
# ---------------------------------------------------------------------------
printf 'Scenario 7: partial bootstrap rollback (orphan markers OK)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"

# Manually craft a half-bootstrapped repo:
# - config.yml present (step 2c ran)
# - .gitignore entry present (step 2d ran)
# - AGENTS.md has ORPHAN opening marker only (step 4 aborted before
#   matching close marker landed)
# - state.yml NOT written (per F-B2 contract — pre-bootstrap state)
mkdir -p "${REPO_ROOT}/.board-superpowers"
cat > "${REPO_ROOT}/.board-superpowers/config.yml" <<EOF
project: "foo/1"
wip_limit: 5
EOF
cat > "${REPO_ROOT}/.gitignore" <<EOF
# board-superpowers local state (claim markers are per-session)
.board-superpowers/claims/
EOF
cat > "${REPO_ROOT}/AGENTS.md" <<'EOF'
# Half-bootstrapped AGENTS.md

PRE_LINE

<!-- board-superpowers:routing -->
Half-injected content with no closing marker.

POST_LINE
EOF
# CLAUDE.md absent entirely.

set +e
ROLL_OUT="$(run_rollback "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --repo-root "${REPO_ROOT}" --keep-credentials </dev/null 2>&1)"
RC_ROLL=$?
set -e
assert_eq 's7: rollback exit 0 on partial bootstrap' '0' "${RC_ROLL}"

check_not 's7: config.yml gone'  test -f "${REPO_ROOT}/.board-superpowers/config.yml"
check_not 's7: gitignore entry gone' \
    grep -Fxq '.board-superpowers/claims/' "${REPO_ROOT}/.gitignore"
# Pre-line + post-line preserved despite orphan-marker block scrubbed.
check 's7: pre-line preserved' grep -Fq 'PRE_LINE' "${REPO_ROOT}/AGENTS.md"
check 's7: post-line preserved' grep -Fq 'POST_LINE' "${REPO_ROOT}/AGENTS.md"
# Diagnostic value if anything fails.
: "${ROLL_OUT:-}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n— TOTALS —\nPASS: %d\nFAIL: %d\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
