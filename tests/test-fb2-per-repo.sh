#!/usr/bin/env bash
# tests/test-fb2-per-repo.sh — assert scripts/bootstrap-project.sh
# satisfies the F-B2 per-repo bootstrap engine contract per
# docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § 1.5.2 (steps 2a-2d + initial state.yml write) and the
# config / state schemas in 03-config-schemas.md.
#
# Scope: Slice 2 of Card 2 — F-B2 engine steps 2a-2d + initial
# state.yml write. Step 2e (BYO-RDBMS) is slice 3, step 4 (routing
# block injection) is slice 4 — both shipped now. The routing_blocks
# assertions below were tightened in slice 4 once injection wiring
# landed.
#
# Contracts under test (8 scenarios):
#   1. Cold start: tmp HOME + tmp git repo. Stubbed gh returns
#      canonical 6-option Status field. All 13 labels created;
#      config.yml + state.yml + .gitignore written; exit 0.
#   2. Status field drift: stubbed gh returns wrong option set.
#      Exit 2 with stderr listing the canonical 6.
#   3. Idempotent re-run: cold start, then re-run. config.yml
#      mtime unchanged; state.yml not rewritten when version is
#      already current; .gitignore not double-appended; labels
#      still 13.
#   4. --force overwrites config.yml: pre-existing config.yml with
#      hand-edited wip_limit: 7. After --force, config.yml regenerated
#      to wip_limit: 5.
#   5. .gitignore append idempotent: pre-existing .gitignore already
#      containing the canonical entry. Re-run leaves it unchanged.
#   6. .gitignore creation: tmp git repo with NO .gitignore. F-B2
#      creates it with the entries.
#   7. state.yml initial write: assert all 5 schema fields present,
#      routing_blocks has 2 entries (one per target file — wired by
#      slice 4), file mode 0644, parent dir 0700.
#   8. Labels delegation failure: stub gh fails on label create.
#      Exit 3; F-B2 aborts BEFORE writing state.yml (no state.yml
#      lingers).
#
# Hermeticity: every scenario uses tmp HOME + tmp git repo + stubbed
# gh on PATH. Nothing touches the real ~/.board-superpowers nor
# real GitHub.

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

file_mtime() {
    local path="$1"
    if stat -f '%m' "${path}" >/dev/null 2>&1; then
        stat -f '%m' "${path}"
    else
        stat -c '%Y' "${path}"
    fi
}

# Make a stub plugin root with .claude-plugin/plugin.json + the real
# scripts/lib/common.sh + the real scripts/setup-labels.sh + a copy of
# the script under test. We need bootstrap-project.sh to find a real
# setup-labels.sh sibling to delegate step 2a to.
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
    # Provide the real script directory so bootstrap-project.sh
    # can locate setup-labels.sh + lib/common.sh as siblings.
    mkdir -p "${target_dir}/scripts/lib"
    cp "${PLUGIN_ROOT_REAL}/scripts/lib/common.sh" "${target_dir}/scripts/lib/common.sh"
    cp "${PLUGIN_ROOT_REAL}/scripts/setup-labels.sh" "${target_dir}/scripts/setup-labels.sh"
    cp "${SCRIPT_UNDER_TEST}" "${target_dir}/scripts/bootstrap-project.sh"
    chmod +x "${target_dir}/scripts/setup-labels.sh"
    chmod +x "${target_dir}/scripts/bootstrap-project.sh"
    # Slice 4 — routing block injection requires the source-of-truth
    # file under the plugin tree. Copy it so bootstrap-project.sh
    # step 4 finds it.
    mkdir -p "${target_dir}/skills/using-board-superpowers/references"
    cp "${PLUGIN_ROOT_REAL}/skills/using-board-superpowers/references/agentsmd-routing.md" \
       "${target_dir}/skills/using-board-superpowers/references/agentsmd-routing.md"
}

# Initialize a tmp git repo with origin pointing at owner/name.
init_tmp_repo() {
    local repo_root="$1"
    local owner_name="$2"
    mkdir -p "${repo_root}"
    git -C "${repo_root}" init --quiet
    git -C "${repo_root}" remote add origin "https://github.com/${owner_name}.git"
    # Set a local user so commits (if any) don't fail; not used here
    git -C "${repo_root}" config user.email "test@example.com"
    git -C "${repo_root}" config user.name  "test"
}

# Build a `gh` stub that:
#   - `gh label list --json name`          → emit current labels file
#   - `gh label create NAME ...`            → append to labels file (or fail
#                                             if MUST_FAIL_LABELS=1)
#   - `gh project field-list NUM --owner OWNER --format json`
#                                          → emit the configured Status
#                                            field options JSON
# State files used:
#   ${stub_dir}/labels.json     — JSON array of {"name":...}
#   ${stub_dir}/status_opts     — newline-separated Status option names
#                                 (in order). Empty file → unknown
#                                 Status field (will emit no fields).
#   ${stub_dir}/must_fail_labels — if file exists, label create exits 1
stub_gh() {
    local dir="$1"
    cat > "${dir}/gh" <<'STUB'
#!/usr/bin/env bash
set -eu

STUB_DIR="$(cd "$(dirname "$0")" && pwd)"
LABELS_FILE="${STUB_DIR}/labels.json"
STATUS_OPTS_FILE="${STUB_DIR}/status_opts"
MUST_FAIL_LABELS="${STUB_DIR}/must_fail_labels"

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
                if [ -f "${MUST_FAIL_LABELS}" ]; then
                    printf 'error: stubbed label create failure for %s\n' "${NAME}" >&2
                    exit 1
                fi
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
                # Build a JSON document with a Status field whose
                # options come from STATUS_OPTS_FILE (one per line).
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

# Run bootstrap-project.sh with stubs in place.
#   $1 — HOME dir
#   $2 — plugin root
#   $3 — stubs dir (PATH first entry)
#   $@ — additional args to bootstrap-project.sh
run_bootstrap() {
    local home_dir="$1"; shift
    local plugin_root="$1"; shift
    local stubs_dir="$1"; shift
    HOME="${home_dir}" \
    PATH="${stubs_dir}:/usr/bin:/bin" \
        bash "${plugin_root}/scripts/bootstrap-project.sh" \
            --plugin-root "${plugin_root}" \
            "$@"
}

# Compute the host-state dir for a repo root, mirroring
# bsp_normalize_repo_path: strip leading /, replace remaining / with -.
# IMPORTANT: the script canonicalises the repo root via
# `git rev-parse --show-toplevel`, which on macOS resolves /var → /private/var.
# Mirror that here so the normalized path lines up with what the script
# actually wrote.
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
# Scenario 1: cold start — labels, config.yml, state.yml, .gitignore
# ---------------------------------------------------------------------------
printf 'Scenario 1: cold start (everything absent)\n'

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
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" >/dev/null 2>&1
RC=$?
set -e

assert_eq 'cold start exit 0' '0' "${RC}"

# Labels: 13 created
LABEL_COUNT="$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(len(json.load(f)))
" "${STUBS_DIR}/labels.json")"
assert_eq 'cold start: 13 labels created' '13' "${LABEL_COUNT}"

# config.yml: written with project: "foo/1" + wip_limit: 5
CONFIG="${REPO_ROOT}/.board-superpowers/config.yml"
check 'config.yml exists' test -f "${CONFIG}"
check 'config.yml has project: "foo/1"' \
    grep -Fxq 'project: "foo/1"' "${CONFIG}"
check 'config.yml has wip_limit: 5' \
    grep -Fxq 'wip_limit: 5' "${CONFIG}"

# .gitignore: created with the canonical entries
GITIGNORE="${REPO_ROOT}/.gitignore"
check '.gitignore exists' test -f "${GITIGNORE}"
check '.gitignore has comment header' \
    grep -Fxq '# board-superpowers local state (claim markers are per-session)' \
        "${GITIGNORE}"
check '.gitignore has claims/ entry' \
    grep -Fxq '.board-superpowers/claims/' "${GITIGNORE}"

# state.yml: written under host-local normalized path
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE="${STATE_DIR}/state.yml"
check 'state.yml exists' test -f "${STATE}"
check 'state.yml has schema_version: 1' \
    grep -Fxq 'schema_version: 1' "${STATE}"
check 'state.yml has last_seen_version_in_repo: "0.2.0"' \
    grep -Fxq 'last_seen_version_in_repo: "0.2.0"' "${STATE}"
check 'state.yml has features_enabled list' \
    grep -Fxq 'features_enabled:' "${STATE}"
check 'state.yml has bootstrap.host item' \
    grep -Fxq '  - bootstrap.host' "${STATE}"
check 'state.yml has bootstrap.per_repo item' \
    grep -Fxq '  - bootstrap.per_repo' "${STATE}"
check 'state.yml has routing_blocks with 2 entries (slice 4 wired)' \
    bash -c "grep -c '^  - target_file:' \"\$1\" | grep -Fxq '2'" _ "${STATE}"
check 'state.yml has ISO-8601 repo_bootstrapped_at' \
    grep -Eq '^repo_bootstrapped_at: "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"$' "${STATE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 2: Status field drift — exit 2 with clear error
# ---------------------------------------------------------------------------
printf 'Scenario 2: Status field drift\n'

TMP="$(mktemp -d)"
HOME_DIR="${TMP}/home"
PLUGIN_ROOT="${TMP}/plugin"
STUBS_DIR="${TMP}/stubs"
REPO_ROOT="${TMP}/repo"

mkdir -p "${HOME_DIR}" "${STUBS_DIR}"
make_stub_plugin_root "0.2.0" "${PLUGIN_ROOT}"
init_tmp_repo "${REPO_ROOT}" "foo/bar"
stub_gh "${STUBS_DIR}"
# Wrong order (Ready and Backlog swapped) — must trigger drift.
printf 'Ready\nBacklog\nIn Progress\nIn Review\nDone\nBlocked\n' \
    > "${STUBS_DIR}/status_opts"
printf '[]\n' > "${STUBS_DIR}/labels.json"

set +e
ERR_OUT="$(run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" 2>&1 1>/dev/null)"
RC=$?
set -e

assert_eq 'Status drift exit 2' '2' "${RC}"
check 'Status drift stderr mentions Status field' \
    bash -c "printf '%s' \"\$1\" | grep -Eqi 'status[[:space:]]+field|status[[:space:]]+option'" _ "${ERR_OUT}"
check 'Status drift stderr mentions canonical order' \
    bash -c "printf '%s' \"\$1\" | grep -Fq 'Backlog'" _ "${ERR_OUT}"
# state.yml MUST NOT be created when bootstrap aborts on Status drift
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check_not 'no state.yml after Status drift abort' \
    test -f "${STATE_DIR}/state.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 3: idempotent re-run
# ---------------------------------------------------------------------------
printf 'Scenario 3: idempotent re-run\n'

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

# First run
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" >/dev/null 2>&1

CONFIG="${REPO_ROOT}/.board-superpowers/config.yml"
GITIGNORE="${REPO_ROOT}/.gitignore"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE="${STATE_DIR}/state.yml"

CONFIG_MTIME_BEFORE="$(file_mtime "${CONFIG}")"
GITIGNORE_LINES_BEFORE="$(wc -l < "${GITIGNORE}" | tr -d ' ')"
STATE_MTIME_BEFORE="$(file_mtime "${STATE}")"
LABELS_BEFORE="$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(len(json.load(f)))
" "${STUBS_DIR}/labels.json")"

# Sleep so any rewrite would change mtime.
sleep 1.1

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" >/dev/null 2>&1
RC=$?
set -e

assert_eq 'idempotent re-run exit 0' '0' "${RC}"
assert_eq 'config.yml mtime unchanged on idempotent re-run' \
    "${CONFIG_MTIME_BEFORE}" "$(file_mtime "${CONFIG}")"
assert_eq '.gitignore line count unchanged on idempotent re-run' \
    "${GITIGNORE_LINES_BEFORE}" "$(wc -l < "${GITIGNORE}" | tr -d ' ')"
assert_eq 'state.yml mtime unchanged when version is current' \
    "${STATE_MTIME_BEFORE}" "$(file_mtime "${STATE}")"
LABELS_AFTER="$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(len(json.load(f)))
" "${STUBS_DIR}/labels.json")"
assert_eq 'labels still 13 after idempotent re-run' "${LABELS_BEFORE}" "${LABELS_AFTER}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 4: --force overwrites config.yml
# ---------------------------------------------------------------------------
printf 'Scenario 4: --force overwrites config.yml\n'

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

# Pre-existing config.yml with hand-edited wip_limit: 7
mkdir -p "${REPO_ROOT}/.board-superpowers"
cat > "${REPO_ROOT}/.board-superpowers/config.yml" <<'EOF'
# hand-edited
project: "foo/1"
wip_limit: 7
EOF

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" --force >/dev/null 2>&1
RC=$?
set -e

assert_eq '--force exit 0' '0' "${RC}"
CONFIG="${REPO_ROOT}/.board-superpowers/config.yml"
check '--force regenerated config.yml: wip_limit: 5' \
    grep -Fxq 'wip_limit: 5' "${CONFIG}"
check_not '--force erased hand-edited wip_limit: 7' \
    grep -Fxq 'wip_limit: 7' "${CONFIG}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 5: .gitignore append idempotent
# ---------------------------------------------------------------------------
printf 'Scenario 5: .gitignore append idempotent\n'

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

# Pre-existing .gitignore with the canonical entries already present.
cat > "${REPO_ROOT}/.gitignore" <<'EOF'
# user existing rule
node_modules/

# board-superpowers local state (claim markers are per-session)
.board-superpowers/claims/
EOF

GITIGNORE_BYTES_BEFORE="$(wc -c < "${REPO_ROOT}/.gitignore" | tr -d ' ')"
CLAIMS_LINES_BEFORE="$(grep -Fxc '.board-superpowers/claims/' "${REPO_ROOT}/.gitignore" || true)"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" >/dev/null 2>&1
RC=$?
set -e

assert_eq '.gitignore-already-present exit 0' '0' "${RC}"
assert_eq '.gitignore byte count unchanged (no double-append)' \
    "${GITIGNORE_BYTES_BEFORE}" \
    "$(wc -c < "${REPO_ROOT}/.gitignore" | tr -d ' ')"
CLAIMS_LINES_AFTER="$(grep -Fxc '.board-superpowers/claims/' "${REPO_ROOT}/.gitignore" || true)"
assert_eq 'claims/ entry count remains 1' "${CLAIMS_LINES_BEFORE}" "${CLAIMS_LINES_AFTER}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 6: .gitignore creation when absent
# ---------------------------------------------------------------------------
printf 'Scenario 6: .gitignore creation (absent file)\n'

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

# Make sure NO .gitignore exists.
rm -f "${REPO_ROOT}/.gitignore"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" >/dev/null 2>&1
RC=$?
set -e

assert_eq 'gitignore-creation exit 0' '0' "${RC}"
check '.gitignore was created' test -f "${REPO_ROOT}/.gitignore"
check '.gitignore has comment header' \
    grep -Fxq '# board-superpowers local state (claim markers are per-session)' \
        "${REPO_ROOT}/.gitignore"
check '.gitignore has claims/ entry' \
    grep -Fxq '.board-superpowers/claims/' "${REPO_ROOT}/.gitignore"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 7: state.yml initial write — schema, mode, parent dir mode
# ---------------------------------------------------------------------------
printf 'Scenario 7: state.yml initial write\n'

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
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" >/dev/null 2>&1
RC=$?
set -e

STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
STATE="${STATE_DIR}/state.yml"

assert_eq 'state.yml write exit 0' '0' "${RC}"
check 'state.yml exists' test -f "${STATE}"
assert_eq 'state.yml file mode 0644' '644' "$(file_mode "${STATE}")"
# The repos/<normalized>/ parent dir should be 0700 (the ~/.board-superpowers
# tree is mode 0700; new sub-dirs inherit through mkdir -p with the
# umask, but bootstrap-host.sh chmods 0700 on the root. Here we only
# require the per-(host, repo) dir is 0700 so secrets are protected.)
check 'state-dir parent ~/.board-superpowers is mode 0700' \
    test "$(file_mode "${HOME_DIR}/.board-superpowers")" = "700"
check 'state-dir per-(host,repo) dir is mode 0700' \
    test "$(file_mode "${STATE_DIR}")" = "700"

# All five required schema fields present.
check 'schema_version field' grep -Fxq 'schema_version: 1' "${STATE}"
check 'repo_bootstrapped_at field' \
    grep -Eq '^repo_bootstrapped_at: ' "${STATE}"
check 'last_seen_version_in_repo field' \
    grep -Fxq 'last_seen_version_in_repo: "0.2.0"' "${STATE}"
check 'features_enabled field' grep -Eq '^features_enabled:' "${STATE}"
check 'routing_blocks field populated with both target files (slice 4)' \
    bash -c "grep -c '^  - target_file:' \"\$1\" | grep -Fxq '2'" _ "${STATE}"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Scenario 8: labels delegation failure — exit 3, no state.yml leak
# ---------------------------------------------------------------------------
printf 'Scenario 8: labels delegation failure\n'

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
# Force the gh stub to fail every label create.
touch "${STUBS_DIR}/must_fail_labels"

set +e
run_bootstrap "${HOME_DIR}" "${PLUGIN_ROOT}" "${STUBS_DIR}" \
    --owner foo --project 1 --repo-root "${REPO_ROOT}" >/dev/null 2>&1
RC=$?
set -e

assert_eq 'labels-delegation-failure exit 3' '3' "${RC}"
STATE_DIR="$(normalized_state_dir "${HOME_DIR}" "${REPO_ROOT}")"
check_not 'no state.yml after labels failure' \
    test -f "${STATE_DIR}/state.yml"

rm -rf "${TMP}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
