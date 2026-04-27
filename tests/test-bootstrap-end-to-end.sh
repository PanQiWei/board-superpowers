#!/usr/bin/env bash
# tests/test-bootstrap-end-to-end.sh — gold-standard hermetic smoke
# wiring slices 1-6 outputs (F-B1 + F-B2 + rollback). Per Card 2
# slice 7 + acceptance criterion §1 of the card body.
#
# What this test asserts:
#   1. Tmp HOME + tmp git repo + stubbed gh with the canonical 6-option
#      Status field.
#   2. F-B1: bootstrap-host.sh writes ~/.board-superpowers/manifest.yml
#      with the expected schema fields.
#   3. F-B2 (steps 2a-2e + step 4 routing-block injection + initial
#      state.yml write): bootstrap-project.sh + --audit-db-url for the
#      BYO-RDBMS DSN. Asserts all 13+ files / state:
#        - manifest.yml (from step 2)
#        - <repo>/.board-superpowers/config.yml
#        - <repo>/.gitignore (with bootstrap entry)
#        - <repo>/AGENTS.md (with marker pair + injected block)
#        - <repo>/CLAUDE.md (with marker pair + injected block)
#        - ~/.board-superpowers/credentials.yml (chmod 0600)
#        - ~/.board-superpowers/repos/<normalized>/state.yml with
#          schema_version + repo_bootstrapped_at + last_seen_version_in_repo
#          + features_enabled + routing_blocks (2 entries with
#          sha256: prefixed hashes).
#   4. Re-run idempotency: re-running bootstrap-project.sh on the
#      same fixture is a no-op — file bytes for config.yml + state.yml
#      unchanged.
#   5. Rollback: bootstrap-rollback.sh --keep-credentials cleans every
#      F-B2 side effect AND leaves manifest.yml + credentials.yml in
#      place.
#
# Hermeticity: tmp dirs only; stubs gh via PATH. No real network. No
# real ~/.board-superpowers contact.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"

BOOTSTRAP_HOST="${PLUGIN_ROOT_REAL}/scripts/bootstrap-host.sh"
BOOTSTRAP_PROJECT="${PLUGIN_ROOT_REAL}/scripts/bootstrap-project.sh"
BOOTSTRAP_ROLLBACK="${PLUGIN_ROOT_REAL}/scripts/bootstrap-rollback.sh"

for script in "${BOOTSTRAP_HOST}" "${BOOTSTRAP_PROJECT}" "${BOOTSTRAP_ROLLBACK}"; do
    if [ ! -f "${script}" ]; then
        printf 'FATAL: %s not found\n' "${script}" >&2
        exit 99
    fi
done

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

file_mode() {
    local path="$1"
    if stat -f '%A' "${path}" >/dev/null 2>&1; then
        stat -f '%A' "${path}"
    else
        stat -c '%a' "${path}"
    fi
}

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
    cp "${BOOTSTRAP_HOST}"     "${target_dir}/scripts/bootstrap-host.sh"
    cp "${BOOTSTRAP_PROJECT}"  "${target_dir}/scripts/bootstrap-project.sh"
    cp "${BOOTSTRAP_ROLLBACK}" "${target_dir}/scripts/bootstrap-rollback.sh"
    chmod +x "${target_dir}/scripts/setup-labels.sh"
    chmod +x "${target_dir}/scripts/bootstrap-host.sh"
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
# Single-scenario gold-standard smoke
# ---------------------------------------------------------------------------
printf 'End-to-end smoke: F-B1 + F-B2 + idempotent re-run + rollback\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"
SQLITE_DIR="${TMP}/dbdir"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}" "${SQLITE_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
printf '%s\n' "${CANONICAL_STATUS}" > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

DSN="sqlite:////${SQLITE_DIR#/}/audit.db"

# --- F-B1 host bootstrap -------------------------------------------------
set +e
HOST_OUT="$(env -i HOME="${HOME_DIR}" PATH="${STUBS_DIR}:/usr/bin:/bin" \
    bash "${PLUGIN_ROOT}/scripts/bootstrap-host.sh" \
        --plugin-root "${PLUGIN_ROOT}" </dev/null 2>&1)"
RC_HOST=$?
set -e

assert_eq 'F-B1: bootstrap-host.sh exit 0' '0' "${RC_HOST}"
check 'F-B1: ~/.board-superpowers/manifest.yml present' \
    test -f "${HOME_DIR}/.board-superpowers/manifest.yml"
check 'F-B1: manifest.yml has schema_version: 1' \
    grep -Eq '^schema_version:[[:space:]]*1$' \
    "${HOME_DIR}/.board-superpowers/manifest.yml"
check 'F-B1: manifest.yml has last_seen_version: "0.2.0"' \
    grep -Eq '^last_seen_version:[[:space:]]*"0\.2\.0"$' \
    "${HOME_DIR}/.board-superpowers/manifest.yml"
check 'F-B1: manifest.yml has ISO 8601 host_bootstrapped_at' \
    grep -Eq '^host_bootstrapped_at:[[:space:]]*"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"$' \
    "${HOME_DIR}/.board-superpowers/manifest.yml"
check 'F-B1: ~/.board-superpowers dir mode 0700' \
    bash -c "[ \"\$(stat -f '%A' \"\$1\" 2>/dev/null || stat -c '%a' \"\$1\")\" = '700' ]" \
    _ "${HOME_DIR}/.board-superpowers"

: "${HOST_OUT:-}"

# --- F-B2 per-repo bootstrap ---------------------------------------------
set +e
PROJ_OUT="$(env -i HOME="${HOME_DIR}" PATH="${STUBS_DIR}:/usr/bin:/bin" \
    bash "${PLUGIN_ROOT}/scripts/bootstrap-project.sh" \
        --plugin-root "${PLUGIN_ROOT}" \
        --owner foo --project 1 --repo-root "${REPO_ROOT}" \
        --audit-db-url "${DSN}" </dev/null 2>&1)"
RC_PROJ=$?
set -e

assert_eq 'F-B2: bootstrap-project.sh exit 0' '0' "${RC_PROJ}"

# Per-repo writes:
CONFIG_FILE="${REPO_ROOT}/.board-superpowers/config.yml"
GITIGNORE="${REPO_ROOT}/.gitignore"
AGENTS="${REPO_ROOT}/AGENTS.md"
CLAUDE="${REPO_ROOT}/CLAUDE.md"
CRED_FILE="${HOME_DIR}/.board-superpowers/credentials.yml"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE_FILE="${STATE_DIR}/state.yml"

check 'F-B2: config.yml present' test -f "${CONFIG_FILE}"
check 'F-B2: config.yml has project: "foo/1"' \
    grep -Fq 'project: "foo/1"' "${CONFIG_FILE}"
check 'F-B2: config.yml has wip_limit: 5' \
    grep -Eq '^wip_limit:[[:space:]]*5$' "${CONFIG_FILE}"

check 'F-B2: .gitignore present with bootstrap entry' \
    grep -Fxq '.board-superpowers/claims/' "${GITIGNORE}"

check 'F-B2: AGENTS.md present with both markers' \
    bash -c "grep -Fq '<!-- board-superpowers:routing -->' \"\$1\" && grep -Fq '<!-- /board-superpowers:routing -->' \"\$1\"" \
    _ "${AGENTS}"
check 'F-B2: CLAUDE.md present with both markers' \
    bash -c "grep -Fq '<!-- board-superpowers:routing -->' \"\$1\" && grep -Fq '<!-- /board-superpowers:routing -->' \"\$1\"" \
    _ "${CLAUDE}"

check 'F-B2: credentials.yml present (chmod 0600)' test -f "${CRED_FILE}"
assert_eq 'F-B2: credentials.yml mode is 600' '600' "$(file_mode "${CRED_FILE}")"
check 'F-B2: credentials.yml carries the DSN' \
    bash -c "grep -Fq \"audit_db_url: \\\"\$1\\\"\" \"\$2\"" _ "${DSN}" "${CRED_FILE}"

check 'F-B2: state.yml present' test -f "${STATE_FILE}"
check 'F-B2: state.yml schema_version: 1' \
    grep -Eq '^schema_version:[[:space:]]*1$' "${STATE_FILE}"
check 'F-B2: state.yml last_seen_version_in_repo: "0.2.0"' \
    grep -Eq '^last_seen_version_in_repo:[[:space:]]*"0\.2\.0"$' "${STATE_FILE}"
check 'F-B2: state.yml has ISO 8601 repo_bootstrapped_at' \
    grep -Eq '^repo_bootstrapped_at:[[:space:]]*"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"$' "${STATE_FILE}"
check 'F-B2: state.yml features_enabled lists bootstrap.host' \
    grep -Fq -- '- bootstrap.host' "${STATE_FILE}"
check 'F-B2: state.yml features_enabled lists bootstrap.per_repo' \
    grep -Fq -- '- bootstrap.per_repo' "${STATE_FILE}"

# routing_blocks list count.
RB_COUNT="$(grep -c '^  - target_file:' "${STATE_FILE}" || true)"
assert_eq 'F-B2: state.yml routing_blocks has 2 entries' '2' "${RB_COUNT}"
check 'F-B2: state.yml mentions AGENTS.md target' \
    bash -c "grep -Eq 'target_file:.*AGENTS\\.md' \"\$1\"" _ "${STATE_FILE}"
check 'F-B2: state.yml mentions CLAUDE.md target' \
    bash -c "grep -Eq 'target_file:.*CLAUDE\\.md' \"\$1\"" _ "${STATE_FILE}"
check 'F-B2: every block_hash has sha256:<64-hex> shape' \
    bash -c "grep -Eq 'block_hash:[[:space:]]*\"sha256:[0-9a-f]{64}\"' \"\$1\"" \
    _ "${STATE_FILE}"

: "${PROJ_OUT:-}"

# --- Idempotent re-run ---------------------------------------------------
SHA_CONFIG_BEFORE="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${CONFIG_FILE}")"
SHA_STATE_BEFORE="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${STATE_FILE}")"
SHA_AGENTS_BEFORE="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${AGENTS}")"
SHA_CLAUDE_BEFORE="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${CLAUDE}")"

set +e
RERUN_OUT="$(env -i HOME="${HOME_DIR}" PATH="${STUBS_DIR}:/usr/bin:/bin" \
    bash "${PLUGIN_ROOT}/scripts/bootstrap-project.sh" \
        --plugin-root "${PLUGIN_ROOT}" \
        --owner foo --project 1 --repo-root "${REPO_ROOT}" </dev/null 2>&1)"
RC_RERUN=$?
set -e

assert_eq 're-run: bootstrap-project.sh exit 0' '0' "${RC_RERUN}"

SHA_CONFIG_AFTER="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${CONFIG_FILE}")"
SHA_STATE_AFTER="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${STATE_FILE}")"
SHA_AGENTS_AFTER="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${AGENTS}")"
SHA_CLAUDE_AFTER="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${CLAUDE}")"

assert_eq 're-run: config.yml byte-identical' \
    "${SHA_CONFIG_BEFORE}" "${SHA_CONFIG_AFTER}"
assert_eq 're-run: state.yml byte-identical (no rewrite when version matches)' \
    "${SHA_STATE_BEFORE}" "${SHA_STATE_AFTER}"
assert_eq 're-run: AGENTS.md byte-identical' \
    "${SHA_AGENTS_BEFORE}" "${SHA_AGENTS_AFTER}"
assert_eq 're-run: CLAUDE.md byte-identical' \
    "${SHA_CLAUDE_BEFORE}" "${SHA_CLAUDE_AFTER}"

: "${RERUN_OUT:-}"

# --- Rollback ------------------------------------------------------------
set +e
ROLL_OUT="$(env -i HOME="${HOME_DIR}" PATH="${STUBS_DIR}:/usr/bin:/bin" \
    bash "${PLUGIN_ROOT}/scripts/bootstrap-rollback.sh" \
        --repo-root "${REPO_ROOT}" --keep-credentials </dev/null 2>&1)"
RC_ROLL=$?
set -e

assert_eq 'rollback: bootstrap-rollback.sh exit 0' '0' "${RC_ROLL}"

check_not 'rollback: config.yml gone' test -f "${CONFIG_FILE}"
check_not 'rollback: state.yml gone'  test -f "${STATE_FILE}"
check_not 'rollback: gitignore entry gone' \
    grep -Fxq '.board-superpowers/claims/' "${GITIGNORE}"
check_not 'rollback: AGENTS.md routing markers gone' \
    grep -Fq '<!-- board-superpowers:routing -->' "${AGENTS}"
check_not 'rollback: CLAUDE.md routing markers gone' \
    grep -Fq '<!-- board-superpowers:routing -->' "${CLAUDE}"

# Manifest preserved (F-B1 is independent).
check 'rollback: manifest.yml preserved' \
    test -f "${HOME_DIR}/.board-superpowers/manifest.yml"
# --keep-credentials honored.
check 'rollback: credentials.yml preserved (--keep-credentials)' \
    test -f "${CRED_FILE}"

: "${ROLL_OUT:-}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n— TOTALS —\nPASS: %d\nFAIL: %d\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
