#!/usr/bin/env bash
# tests/test-fb2-byo-rdbms.sh — assert scripts/bootstrap-project.sh
# step 2e (BYO-RDBMS credential UX) satisfies the contract per
# docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § 1.5.2 step 2e + 03-config-schemas.md credentials.yml schema +
# adr/0009-allow-sqlite-as-byo-audit-db.md.
#
# Scope: Slice 3 of Card 2 — extend bootstrap-project.sh with three
# step 2e paths + the --audit-db-url flag + BOARD_SP_AUDIT_DB_URL env
# var handling. Step 2e runs AFTER 2a-2d but BEFORE the state.yml
# write so abort cleanly leaves no half-state behind.
#
# Path A — env var present     → validate scheme, no credentials.yml.
# Path B — credentials.yml     → re-use; warn on loose mode.
# Path C — interactive prompt  → write credentials.yml chmod 0600,
#                                or surface degradation.
# CLI flag — --audit-db-url    → highest precedence; same scheme rules.
#
# Contracts under test (~10 scenarios):
#   1. Path A — valid postgres env var: bootstrap silent on step 2e,
#      no credentials.yml written, state.yml IS written.
#   2. Path A — invalid scheme env var: exit 4, error lists the 6
#      schemes, no state.yml written.
#   3. Path B — pre-existing credentials.yml chmod 0600 + valid
#      mysql DSN: step 2e re-uses; no warning; state.yml written.
#   4. Path B — pre-existing credentials.yml chmod 0644: warning
#      emitted, but bootstrap proceeds; file mode is NOT auto-tightened.
#   5. Path C — interactive sqlite happy: pipe a sqlite:////tmp DSN
#      pointing into a writable parent; credentials.yml written
#      with chmod 0600, content matches.
#   6. Path C — interactive sqlite parent dir unwritable: exit 4,
#      error mentions parent dir, no credentials.yml written, no
#      state.yml written.
#   7. Path C — decline (empty input): degradation notice printed;
#      no credentials.yml written; state.yml IS written.
#   8. --audit-db-url flag: takes precedence; non-interactive;
#      credentials.yml written with chmod 0600.
#   9. CLI flag for non-sqlite postgres: bootstrap silent on
#      step 2e, no credentials.yml written, state.yml IS written.
#  10. Path A precedence vs pre-existing credentials.yml: env var
#      wins, no credentials.yml mutation.
#
# Hermeticity: tmp HOME + tmp git repo + stub gh on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_UNDER_TEST="${PLUGIN_ROOT_REAL}/scripts/bootstrap-project.sh"

if [ ! -f "${SCRIPT_UNDER_TEST}" ]; then
    printf 'FATAL: %s not found\n' "${SCRIPT_UNDER_TEST}" >&2
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

# Cross-platform "stat" helper (BSD vs GNU).
file_mode() {
    local path="$1"
    if stat -f '%A' "${path}" >/dev/null 2>&1; then
        stat -f '%A' "${path}"
    else
        stat -c '%a' "${path}"
    fi
}

# Replica of make_stub_plugin_root from test-fb2-per-repo.sh.
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
    cp "${SCRIPT_UNDER_TEST}" "${target_dir}/scripts/bootstrap-project.sh"
    chmod +x "${target_dir}/scripts/setup-labels.sh"
    chmod +x "${target_dir}/scripts/bootstrap-project.sh"
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

# Stub gh — same shape as test-fb2-per-repo.sh; canonical Status field
# always returned so step 2b is never the failing party here.
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

# Run bootstrap with optional stdin redirected from a string.
#   $1 — HOME dir
#   $2 — plugin root
#   $3 — stubs dir
#   $4 — stdin payload (use empty string for /dev/null)
#   $5 — env var line ("KEY=VALUE" or "")
#   $@ — additional args to bootstrap-project.sh
run_bootstrap_input() {
    local home_dir="$1"; shift
    local plugin_root="$1"; shift
    local stubs_dir="$1"; shift
    local stdin_payload="$1"; shift
    local env_line="$1"; shift

    local extra_env=()
    if [ -n "${env_line}" ]; then
        extra_env=("${env_line}")
    fi

    if [ -z "${stdin_payload}" ]; then
        env -i HOME="${home_dir}" PATH="${stubs_dir}:/usr/bin:/bin" \
            "${extra_env[@]+"${extra_env[@]}"}" \
            bash "${plugin_root}/scripts/bootstrap-project.sh" \
                --plugin-root "${plugin_root}" \
                "$@" </dev/null
    else
        env -i HOME="${home_dir}" PATH="${stubs_dir}:/usr/bin:/bin" \
            "${extra_env[@]+"${extra_env[@]}"}" \
            bash "${plugin_root}/scripts/bootstrap-project.sh" \
                --plugin-root "${plugin_root}" \
                "$@" <<< "${stdin_payload}"
    fi
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
# Scenario 1: Path A — env var present, valid postgres
# ---------------------------------------------------------------------------
printf 'Scenario 1: Path A — env var valid postgres\n'

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
ALL_OUT="$(run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "" "BOARD_SP_AUDIT_DB_URL=postgresql://user:pwd@host:5432/db" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1)"
RC=$?
set -e

assert_eq 'envvar valid: exit 0' '0' "${RC}"
check_not 'envvar valid: no credentials.yml written' \
    test -f "${HOME_DIR}/.board-superpowers/credentials.yml"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check 'envvar valid: state.yml written' \
    test -f "${STATE_DIR}/state.yml"
check 'envvar valid: log mentions env var precedence' \
    bash -c "printf '%s' \"\$1\" | grep -Eqi 'BOARD_SP_AUDIT_DB_URL|env var'" _ "${ALL_OUT}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 2: Path A — env var invalid scheme
# ---------------------------------------------------------------------------
printf 'Scenario 2: Path A — env var invalid scheme (mongodb)\n'

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
ERR_OUT="$(run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "" "BOARD_SP_AUDIT_DB_URL=mongodb://localhost:27017/audit" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1 1>/dev/null)"
RC=$?
set -e

assert_eq 'envvar invalid: exit 4' '4' "${RC}"
check 'envvar invalid: stderr mentions postgres scheme' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'postgresql://'" _ "${ERR_OUT}"
check 'envvar invalid: stderr mentions sqlite scheme' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'sqlite://'" _ "${ERR_OUT}"
check 'envvar invalid: stderr mentions mysql+pymysql scheme' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'mysql+pymysql://'" _ "${ERR_OUT}"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check_not 'envvar invalid: no state.yml written' \
    test -f "${STATE_DIR}/state.yml"
check_not 'envvar invalid: no credentials.yml written' \
    test -f "${HOME_DIR}/.board-superpowers/credentials.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 3: Path B — pre-existing credentials.yml chmod 0600
# ---------------------------------------------------------------------------
printf 'Scenario 3: Path B — pre-existing credentials.yml chmod 0600\n'

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

# Seed a properly-permissioned credentials.yml.
mkdir -p "${HOME_DIR}/.board-superpowers"
chmod 0700 "${HOME_DIR}/.board-superpowers"
cat > "${HOME_DIR}/.board-superpowers/credentials.yml" <<'EOF'
audit_db_url: "mysql://prod:secret@db.example.com:3306/audit"
EOF
chmod 0600 "${HOME_DIR}/.board-superpowers/credentials.yml"
ORIG_CONTENT="$(cat "${HOME_DIR}/.board-superpowers/credentials.yml")"

set +e
ALL_OUT="$(run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "" "" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1)"
RC=$?
set -e

assert_eq 'pre-existing 0600: exit 0' '0' "${RC}"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check 'pre-existing 0600: state.yml written' \
    test -f "${STATE_DIR}/state.yml"
assert_eq 'pre-existing 0600: credentials.yml unchanged' \
    "${ORIG_CONTENT}" "$(cat "${HOME_DIR}/.board-superpowers/credentials.yml")"
assert_eq 'pre-existing 0600: file mode still 0600' \
    '600' "$(file_mode "${HOME_DIR}/.board-superpowers/credentials.yml")"
check_not 'pre-existing 0600: NO loose-mode warning' \
    bash -c "printf '%s' \"\$1\" | grep -Eqi 'mode|chmod|0600|0644|loose|permissions'" _ "${ALL_OUT}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 4: Path B — pre-existing credentials.yml chmod 0644
# ---------------------------------------------------------------------------
printf 'Scenario 4: Path B — pre-existing credentials.yml looser mode\n'

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

mkdir -p "${HOME_DIR}/.board-superpowers"
chmod 0700 "${HOME_DIR}/.board-superpowers"
cat > "${HOME_DIR}/.board-superpowers/credentials.yml" <<'EOF'
audit_db_url: "postgresql://u:p@h:5432/d"
EOF
chmod 0644 "${HOME_DIR}/.board-superpowers/credentials.yml"

set +e
ALL_OUT="$(run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "" "" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1)"
RC=$?
set -e

assert_eq 'looser-mode: exit 0 (proceed)' '0' "${RC}"
check 'looser-mode: WARN about file mode' \
    bash -c "printf '%s' \"\$1\" | grep -Eqi 'WARN.*credentials\.yml.*(mode|0600|chmod|loose)'" _ "${ALL_OUT}"
# Spec says we must NOT auto-tighten — file is user-managed.
assert_eq 'looser-mode: file mode NOT auto-tightened (still 0644)' \
    '644' "$(file_mode "${HOME_DIR}/.board-superpowers/credentials.yml")"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check 'looser-mode: state.yml written' \
    test -f "${STATE_DIR}/state.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 5: Path C — interactive sqlite happy path
# ---------------------------------------------------------------------------
printf 'Scenario 5: Path C — interactive sqlite happy path\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"
DB_PARENT="${TMP}/dbparent"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}" "${DB_PARENT}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '%s\n' "${CANONICAL_STATUS}" > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

DSN="sqlite:////${DB_PARENT#/}/audit.db"

set +e
ALL_OUT="$(run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "${DSN}
" "" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1)"
RC=$?
set -e

assert_eq 'interactive sqlite: exit 0' '0' "${RC}"
CRED="${HOME_DIR}/.board-superpowers/credentials.yml"
check 'interactive sqlite: credentials.yml written' test -f "${CRED}"
assert_eq 'interactive sqlite: credentials.yml mode 0600' \
    '600' "$(file_mode "${CRED}")"
check 'interactive sqlite: credentials.yml has audit_db_url' \
    grep -Fq "audit_db_url:" "${CRED}"
check 'interactive sqlite: credentials.yml has the DSN we entered' \
    grep -Fq "${DSN}" "${CRED}"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check 'interactive sqlite: state.yml written' \
    test -f "${STATE_DIR}/state.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6: Path C — interactive sqlite parent dir unwritable
# ---------------------------------------------------------------------------
printf 'Scenario 6: Path C — interactive sqlite parent dir unwritable\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"
DB_PARENT="${TMP}/locked"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}" "${DB_PARENT}"
chmod 0500 "${DB_PARENT}"  # readable + executable, but NOT writable
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '%s\n' "${CANONICAL_STATUS}" > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

DSN="sqlite:////${DB_PARENT#/}/audit.db"

set +e
ERR_OUT="$(run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "${DSN}
" "" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1 1>/dev/null)"
RC=$?
set -e

# Cleanup so mktemp's deleter can remove the dir.
chmod 0700 "${DB_PARENT}" 2>/dev/null || true

assert_eq 'unwritable parent: exit 4' '4' "${RC}"
check 'unwritable parent: stderr mentions parent dir path' \
    bash -c "printf '%s' \"\$1\" | grep -Fq '${DB_PARENT}'" _ "${ERR_OUT}"
check_not 'unwritable parent: NO credentials.yml leak' \
    test -f "${HOME_DIR}/.board-superpowers/credentials.yml"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check_not 'unwritable parent: NO state.yml leak' \
    test -f "${STATE_DIR}/state.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 7: Path C — decline (empty input)
# ---------------------------------------------------------------------------
printf 'Scenario 7: Path C — decline (empty input)\n'

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
# Empty input: a single newline (so the read() consumes it but yields "").
ALL_OUT="$(run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "
" "" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1)"
RC=$?
set -e

assert_eq 'decline: exit 0' '0' "${RC}"
check_not 'decline: no credentials.yml written' \
    test -f "${HOME_DIR}/.board-superpowers/credentials.yml"
check 'decline: degradation notice (R-class) printed' \
    bash -c "printf '%s' \"\$1\" | grep -Eqi 'R-class|degrad'" _ "${ALL_OUT}"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check 'decline: state.yml IS written' \
    test -f "${STATE_DIR}/state.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 8: --audit-db-url flag (sqlite happy)
# ---------------------------------------------------------------------------
printf 'Scenario 8: --audit-db-url flag (sqlite happy)\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"
DB_PARENT="${TMP}/flagdb"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}" "${DB_PARENT}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '%s\n' "${CANONICAL_STATUS}" > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

FLAG_DSN="sqlite:////${DB_PARENT#/}/audit.db"

set +e
ALL_OUT="$(run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "" "" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" \
    --audit-db-url "${FLAG_DSN}" 2>&1)"
RC=$?
set -e

assert_eq 'flag sqlite: exit 0' '0' "${RC}"
CRED="${HOME_DIR}/.board-superpowers/credentials.yml"
check 'flag sqlite: credentials.yml written' test -f "${CRED}"
assert_eq 'flag sqlite: mode 0600' '600' "$(file_mode "${CRED}")"
check 'flag sqlite: contains the DSN we passed' \
    grep -Fq "${FLAG_DSN}" "${CRED}"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check 'flag sqlite: state.yml written' \
    test -f "${STATE_DIR}/state.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 9: --audit-db-url flag (postgres) PERSISTS to credentials.yml
# ---------------------------------------------------------------------------
# Spec contract (per BLOCKER 1 fix): the --audit-db-url flag is the
# non-interactive equivalent of typing the DSN at the interactive
# prompt. It ALWAYS persists to credentials.yml at chmod 0600,
# regardless of scheme. Use BOARD_SP_AUDIT_DB_URL for ephemeral /
# runtime overrides that should NOT touch disk.
printf 'Scenario 9: --audit-db-url flag (postgres) persists like sqlite\n'

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

PG_DSN="postgresql://u:p@h:5432/d"

set +e
run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "" "" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" \
    --audit-db-url "${PG_DSN}" >/dev/null 2>&1
RC=$?
set -e

assert_eq 'flag postgres: exit 0' '0' "${RC}"
CRED="${HOME_DIR}/.board-superpowers/credentials.yml"
check 'flag postgres: credentials.yml written (flag persists)' \
    test -f "${CRED}"
assert_eq 'flag postgres: credentials.yml mode 0600' \
    '600' "$(file_mode "${CRED}")"
check 'flag postgres: credentials.yml has the DSN we passed' \
    grep -Fq "${PG_DSN}" "${CRED}"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check 'flag postgres: state.yml written' \
    test -f "${STATE_DIR}/state.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 10: env var precedence over pre-existing credentials.yml
# ---------------------------------------------------------------------------
printf 'Scenario 10: env var precedence over pre-existing credentials.yml\n'

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

mkdir -p "${HOME_DIR}/.board-superpowers"
chmod 0700 "${HOME_DIR}/.board-superpowers"
cat > "${HOME_DIR}/.board-superpowers/credentials.yml" <<'EOF'
audit_db_url: "mysql://prod:secret@db.example.com:3306/audit"
EOF
chmod 0600 "${HOME_DIR}/.board-superpowers/credentials.yml"
ORIG="$(cat "${HOME_DIR}/.board-superpowers/credentials.yml")"

set +e
run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "" "BOARD_SP_AUDIT_DB_URL=postgres://envuser:envpwd@envhost/d" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" >/dev/null 2>&1
RC=$?
set -e

assert_eq 'envvar+file: exit 0' '0' "${RC}"
assert_eq 'envvar+file: credentials.yml NOT mutated' \
    "${ORIG}" "$(cat "${HOME_DIR}/.board-superpowers/credentials.yml")"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check 'envvar+file: state.yml written' \
    test -f "${STATE_DIR}/state.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 11: structural DSN validation — malformed network DSNs reject
# ---------------------------------------------------------------------------
# Per BLOCKER 2 fix: scheme-prefix matching alone is insufficient. We
# require urlparse(dsn).hostname for non-sqlite schemes, so loose
# strings that happen to start with `postgres://` but have no host or
# malformed authority are rejected with exit 4.
printf 'Scenario 11: malformed network DSN rejected (no hostname)\n'

run_validation_reject() {
    local label="$1"
    local dsn="$2"

    local tmp home_dir plugin_root stubs_dir repo_root
    tmp="$(mktemp -d)"
    home_dir="${tmp}/home"
    plugin_root="${tmp}/plugin"
    stubs_dir="${tmp}/stubs"
    repo_root="${tmp}/repo"

    mkdir -p "${home_dir}" "${stubs_dir}"
    make_stub_plugin_root "0.2.0" "${plugin_root}"
    init_tmp_repo "${repo_root}" "foo/bar"
    stub_gh "${stubs_dir}"
    printf '%s\n' "${CANONICAL_STATUS}" > "${stubs_dir}/status_opts"
    printf '[]\n' > "${stubs_dir}/labels.json"

    set +e
    local err_out rc
    err_out="$(run_bootstrap_input "${home_dir}" "${plugin_root}" "${stubs_dir}" \
        "" "BOARD_SP_AUDIT_DB_URL=${dsn}" \
        --owner foo --project 1 --repo-root "${repo_root}" 2>&1 1>/dev/null)"
    rc=$?
    set -e

    assert_eq "${label}: exit 4" '4' "${rc}"
    local state_dir
    state_dir="$(normalized_state_dir "${home_dir}" "${repo_root}")"
    check_not "${label}: NO state.yml leak" \
        test -f "${state_dir}/state.yml"
    check_not "${label}: NO credentials.yml leak" \
        test -f "${home_dir}/.board-superpowers/credentials.yml"
    # Suppress unused-var warning for err_out — we keep it captured for
    # ad-hoc print-on-failure debugging.
    : "${err_out:-}"

    rm -rf "${tmp}"
}

run_validation_accept() {
    local label="$1"
    local dsn="$2"

    local tmp home_dir plugin_root stubs_dir repo_root
    tmp="$(mktemp -d)"
    home_dir="${tmp}/home"
    plugin_root="${tmp}/plugin"
    stubs_dir="${tmp}/stubs"
    repo_root="${tmp}/repo"

    mkdir -p "${home_dir}" "${stubs_dir}"
    make_stub_plugin_root "0.2.0" "${plugin_root}"
    init_tmp_repo "${repo_root}" "foo/bar"
    stub_gh "${stubs_dir}"
    printf '%s\n' "${CANONICAL_STATUS}" > "${stubs_dir}/status_opts"
    printf '[]\n' > "${stubs_dir}/labels.json"

    set +e
    run_bootstrap_input "${home_dir}" "${plugin_root}" "${stubs_dir}" \
        "" "BOARD_SP_AUDIT_DB_URL=${dsn}" \
        --owner foo --project 1 --repo-root "${repo_root}" >/dev/null 2>&1
    local rc=$?
    set -e

    assert_eq "${label}: exit 0" '0' "${rc}"
    local state_dir
    state_dir="$(normalized_state_dir "${home_dir}" "${repo_root}")"
    check "${label}: state.yml written" \
        test -f "${state_dir}/state.yml"

    rm -rf "${tmp}"
}

# Rejects: malformed network forms.
run_validation_reject 'malformed: postgres://user@host:5432:wrong/db' \
    'postgres://user@host:5432:wrong/db'
run_validation_reject 'malformed: mysql:// (no hostname)' \
    'mysql://'
run_validation_reject 'malformed: postgresql:/single-slash (no ://)' \
    'postgresql:/single-slash'

# ---------------------------------------------------------------------------
# Scenario 12: 3-slash sqlite (relative path) is rejected
# ---------------------------------------------------------------------------
# Per ADR-0009 + BLOCKER 2: SQLite must use the 4-slash absolute form
# (sqlite:////abs/path). The 3-slash form (sqlite:///rel/path) parses
# to a relative path and is rejected; the error message must reference
# ADR-0009's 4-slash convention so the architect knows the fix.
printf 'Scenario 12: 3-slash sqlite (relative path) rejected; error references 4-slash convention\n'

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
ERR_OUT="$(run_bootstrap_input "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    "" "BOARD_SP_AUDIT_DB_URL=sqlite:///relative/path/audit.db" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1 1>/dev/null)"
RC=$?
set -e

assert_eq 'sqlite 3-slash: exit 4' '4' "${RC}"
check 'sqlite 3-slash: error references ADR-0009 4-slash convention' \
    bash -c "printf '%s' \"\$1\" | grep -Fq '4-slash'" _ "${ERR_OUT}"
check 'sqlite 3-slash: error mentions ADR-0009' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'ADR-0009'" _ "${ERR_OUT}"
check_not 'sqlite 3-slash: no state.yml' \
    test -f "$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")/state.yml"
check_not 'sqlite 3-slash: no credentials.yml' \
    test -f "${HOME_DIR}/.board-superpowers/credentials.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 13: structural DSN validation — well-formed DSNs accept
# ---------------------------------------------------------------------------
# Per BLOCKER 2 fix: the validator must continue to accept the
# canonical well-formed shapes. Sqlite 4-slash + postgres with full
# auth/port/db/query + minimal postgres host-only.
printf 'Scenario 13: well-formed DSNs accept (4-slash sqlite, full + minimal postgres)\n'

# 4-slash sqlite (absolute path): accept. Use a writable parent.
TMP_SQLITE_PARENT="$(mktemp -d)"
run_validation_accept 'accept: 4-slash sqlite' \
    "sqlite:////${TMP_SQLITE_PARENT#/}/audit.db"
rm -rf "${TMP_SQLITE_PARENT}"

run_validation_accept 'accept: postgres with auth+port+db+query' \
    'postgresql://user:pwd@host:5432/db?ssl=true'

run_validation_accept 'accept: postgres host-only (no port/auth)' \
    'postgresql://localhost/db'

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
