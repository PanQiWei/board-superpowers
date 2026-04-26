#!/usr/bin/env bash
# tests/setup-labels-idempotent.sh — assert scripts/setup-labels.sh ships
# the canonical 13-label set (4 ops + 9 type+size) idempotently per
# docs/architecture/0005-contracts/05-github-artifact-schemas.md
# § "Standard label set" and 0005-contracts/01-script-contracts.md.
#
# Contract under test:
#   - Cold start (label list empty) creates all 13 labels exactly once.
#   - Re-running the script after success creates 0 labels (idempotent).
#   - Running with 4 ops labels pre-seeded creates exactly the 9 type+size
#     labels (matches v0.1.0-minimum repo state on this very plugin).
#
# Hermeticity policy: every scenario stubs `gh` onto a tmp PATH and keeps
# all label state in a tmp JSON file. NO scenario calls real GitHub or
# requires gh auth. Suite passes on a vanilla CI runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SETUP_LABELS="${PLUGIN_ROOT}/scripts/setup-labels.sh"

if [ ! -f "${SETUP_LABELS}" ]; then
    printf 'FATAL: %s not found\n' "${SETUP_LABELS}" >&2
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
        printf '  FAIL — %s: expected %s, got %s\n' "${label}" "${expected}" "${actual}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# Helper: write a `gh` stub that maintains a JSON list of label names in
# ${LABELS_FILE} (path passed via env). Mirrors real gh behavior:
#   - `gh label list --json name`        → emit current JSON list to stdout
#   - `gh label create NAME --color X --description D [--repo R]`
#                                        → append {"name":"NAME"} to the list
#                                          OR exit 1 with "name already used"
#                                          if NAME already present
#   - any other subcommand               → exit 0 silently (not invoked here)
#
# Args: <stub-dir> <labels-file>
stub_gh() {
    local dir="${1:?usage: stub_gh <dir> <labels-file>}"
    local labels_file="${2:?usage: stub_gh <dir> <labels-file>}"
    cat > "${dir}/gh" <<STUB
#!/usr/bin/env bash
# Hermetic gh stub — keeps label state in ${labels_file}.
set -eu
LABELS_FILE='${labels_file}'

if [ ! -f "\${LABELS_FILE}" ]; then
    printf '[]\n' > "\${LABELS_FILE}"
fi

case "\${1:-}" in
    label)
        shift
        case "\${1:-}" in
            list)
                cat "\${LABELS_FILE}"
                exit 0
                ;;
            create)
                shift
                NAME="\${1:?label create needs NAME}"
                shift
                # ignore --color / --description / --repo flags + values
                EXISTS="\$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print('1' if any(l['name']==sys.argv[2] for l in data) else '0')
" "\${LABELS_FILE}" "\${NAME}")"
                if [ "\${EXISTS}" = "1" ]; then
                    printf 'error: name "%s" already used by another label\n' "\${NAME}" >&2
                    exit 1
                fi
                python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data.append({'name': sys.argv[2]})
with open(sys.argv[1], 'w') as f:
    json.dump(data, f)
" "\${LABELS_FILE}" "\${NAME}"
                printf 'label "%s" created\n' "\${NAME}"
                exit 0
                ;;
            *)
                printf 'stub gh label: subcommand %s unsupported\n' "\${1:-}" >&2
                exit 0
                ;;
        esac
        ;;
    *)
        # other gh subcommands not invoked by setup-labels.sh
        exit 0
        ;;
esac
STUB
    chmod +x "${dir}/gh"
}

# Helper: count labels in the JSON file.
labels_count() {
    local file="${1:?}"
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(len(json.load(f)))
" "${file}"
}

# Helper: emit sorted label names, one per line.
labels_list() {
    local file="${1:?}"
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print('\n'.join(sorted(l['name'] for l in data)))
" "${file}"
}

# Canonical 13-label set per spec.
EXPECTED_LABELS_SORTED='pr-contract-override
security
size:L
size:M
size:S
size:XS
suspended
type:bug
type:chore
type:epic
type:feature
type:refactor
wip-override'

# Helper: run setup-labels.sh in a controlled environment.
#   - PATH = <stub-dir>:/usr/bin:/bin (stub gh wins; real python3 + bash)
#   - Working dir is irrelevant (script doesn't read cwd)
run_setup_labels_in() {
    local stub_dir="${1:?}"
    env -i \
        HOME="${HOME}" \
        PATH="${stub_dir}:/usr/bin:/bin" \
        bash "${SETUP_LABELS}" >/dev/null 2>&1
}

# --- Scenario 1: cold start --------------------------------------------
# Empty labels file → all 13 labels created on first run.

scenario_cold_start() {
    printf 'Scenario: cold start (empty label list)\n'
    local tmp stub_dir labels_file rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    stub_dir="${tmp}/stubs"
    labels_file="${tmp}/labels.json"
    mkdir -p "${stub_dir}"
    printf '[]\n' > "${labels_file}"
    stub_gh "${stub_dir}" "${labels_file}"
    run_setup_labels_in "${stub_dir}" || rc=$?
    assert_eq "cold start exits 0" "0" "${rc}"
    assert_eq "cold start creates 13 labels" "13" "$(labels_count "${labels_file}")"
    assert_eq "cold start label set matches spec" \
        "${EXPECTED_LABELS_SORTED}" \
        "$(labels_list "${labels_file}")"
}

# --- Scenario 2: re-run idempotent --------------------------------------
# After scenario 1's state (13 labels), re-running creates 0 new labels
# and exits 0.

scenario_rerun_idempotent() {
    printf 'Scenario: re-run idempotent (13 labels already present)\n'
    local tmp stub_dir labels_file rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    stub_dir="${tmp}/stubs"
    labels_file="${tmp}/labels.json"
    mkdir -p "${stub_dir}"
    printf '[]\n' > "${labels_file}"
    stub_gh "${stub_dir}" "${labels_file}"
    # First run — get to 13 labels.
    run_setup_labels_in "${stub_dir}" || rc=$?
    if [ "${rc}" != "0" ]; then
        printf '  FAIL — pre-condition: first run did not exit 0 (rc=%s)\n' "${rc}" >&2
        FAIL=$((FAIL + 1))
        return
    fi
    # Second run — must remain at 13 with exit 0.
    rc=0
    run_setup_labels_in "${stub_dir}" || rc=$?
    assert_eq "re-run exits 0" "0" "${rc}"
    assert_eq "re-run keeps label count at 13" "13" "$(labels_count "${labels_file}")"
}

# --- Scenario 3: partial pre-existing -----------------------------------
# Seed the labels file with the 4 ops labels (mirrors v0.1.0-minimum repo
# state on this plugin). Run script. Result: 9 type+size labels added,
# total = 13, exit 0.

scenario_partial_preexisting() {
    printf 'Scenario: partial pre-existing (4 ops labels seeded)\n'
    local tmp stub_dir labels_file rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    stub_dir="${tmp}/stubs"
    labels_file="${tmp}/labels.json"
    mkdir -p "${stub_dir}"
    cat > "${labels_file}" <<'JSON'
[{"name":"wip-override"},{"name":"suspended"},{"name":"security"},{"name":"pr-contract-override"}]
JSON
    stub_gh "${stub_dir}" "${labels_file}"
    run_setup_labels_in "${stub_dir}" || rc=$?
    assert_eq "partial pre-existing exits 0" "0" "${rc}"
    assert_eq "partial pre-existing reaches 13 labels" "13" "$(labels_count "${labels_file}")"
    assert_eq "partial pre-existing final set matches spec" \
        "${EXPECTED_LABELS_SORTED}" \
        "$(labels_list "${labels_file}")"
}

# --- Run ---------------------------------------------------------------

scenario_cold_start
scenario_rerun_idempotent
scenario_partial_preexisting

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
