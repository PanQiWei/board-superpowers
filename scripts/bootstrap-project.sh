#!/usr/bin/env bash
# scripts/bootstrap-project.sh — F-B2 per-repo bootstrap engine
# (slice 2 — steps 2a-2d + initial state.yml write).
#
# Spec:
#   docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
#     § 1.5.2 F-B2. Per-repo bootstrap (steps 1, 2a-2d, 3 — initial
#     state.yml write).
#   docs/architecture/0005-contracts/03-config-schemas.md (config.yml
#     and state.yml shapes).
#   docs/architecture/0005-contracts/05-github-artifact-schemas.md
#     § "Project v2 Status enum" (canonical 6-option contract).
#   docs/architecture/0005-contracts/07-path-conventions.md
#     § "Per-host layout" + "The .gitignore block".
#
# Capability: when invoked with --owner/--project/--repo-root, run
# F-B2 steps 2a-2d (standard labels via setup-labels.sh, Status field
# validation, config.yml write, .gitignore append) and write the
# initial host-local state.yml. Step 2e (BYO-RDBMS UX) and step 4
# (routing block injection) are deferred to slices 3 + 4 of the
# same card; routing_blocks is written as the empty list [] so the
# state file is valid v1 schema today.
#
# Argument vector:
#   bash scripts/bootstrap-project.sh \
#       --owner OWNER \
#       --project N \
#       --repo-root PATH      # absolute repo path
#       [--force]             # bypass idempotency guards (rewrite
#                             # config.yml even when present)
#       [--plugin-root P]     # for testability; defaults to derived
#                             # from this file's location
#
# --owner and --project are REQUIRED for step 2b (Status field check).
# --repo-root defaults to ${CLAUDE_PROJECT_DIR:-$PWD} resolved to
# `git rev-parse --show-toplevel`.
#
# Exit codes:
#   0  success
#   1  bad args / file write failure
#   2  Status field drift detected (step 2b)
#   3  step 2a (labels) delegation failed
#   64 unknown argument

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

# --- Arg parsing --------------------------------------------------------

OWNER=""
PROJECT_NUM=""
REPO_ROOT_ARG=""
FORCE=0
PLUGIN_ROOT_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --owner)
            OWNER="${2:-}"
            [ -n "${OWNER}" ] || bsp_die "--owner requires a value"
            shift 2
            ;;
        --project)
            PROJECT_NUM="${2:-}"
            [ -n "${PROJECT_NUM}" ] || bsp_die "--project requires a value"
            shift 2
            ;;
        --repo-root)
            REPO_ROOT_ARG="${2:-}"
            [ -n "${REPO_ROOT_ARG}" ] || bsp_die "--repo-root requires a path"
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --plugin-root)
            PLUGIN_ROOT_ARG="${2:-}"
            [ -n "${PLUGIN_ROOT_ARG}" ] || bsp_die "--plugin-root requires a path"
            shift 2
            ;;
        --help|-h)
            sed -n '2,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" >&2
            exit 0
            ;;
        *)
            printf '[bsp ERROR] unknown argument: %s (try --help)\n' "$1" >&2
            exit 64
            ;;
    esac
done

[ -n "${OWNER}" ]       || bsp_die "--owner is required"
[ -n "${PROJECT_NUM}" ] || bsp_die "--project is required"

# --- Resolve plugin root + repo root + plugin version --------------------

if [ -n "${PLUGIN_ROOT_ARG}" ]; then
    PLUGIN_ROOT="${PLUGIN_ROOT_ARG}"
else
    PLUGIN_ROOT="$(bsp_plugin_root)"
fi

if [ ! -d "${PLUGIN_ROOT}" ]; then
    bsp_die "plugin root not found: ${PLUGIN_ROOT}"
fi

PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
if [ ! -f "${PLUGIN_JSON}" ]; then
    bsp_die "plugin.json not found at ${PLUGIN_JSON}"
fi

bsp_require_cmd python3 "macOS / Linux ship python3 by default"
bsp_require_cmd gh      "install via 'brew install gh' (or your platform's package manager)"
bsp_require_cmd git     "install git for your platform"

PLUGIN_VERSION="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except (OSError, ValueError) as e:
    sys.stderr.write('cannot read plugin.json: ' + str(e) + '\n')
    sys.exit(1)
v = data.get('version')
if not v:
    sys.stderr.write('plugin.json missing version field\n')
    sys.exit(1)
print(v)
" "${PLUGIN_JSON}")" || bsp_die "failed to read version from ${PLUGIN_JSON}"

# Resolve repo root: explicit arg → CLAUDE_PROJECT_DIR → PWD; then
# canonicalise via `git rev-parse --show-toplevel` so the normalized
# host-state path uses the actual repo root rather than a sub-path.
RAW_REPO_ROOT="${REPO_ROOT_ARG:-${CLAUDE_PROJECT_DIR:-$PWD}}"
if [ ! -d "${RAW_REPO_ROOT}" ]; then
    bsp_die "repo root not found: ${RAW_REPO_ROOT}"
fi
REPO_ROOT="$(cd "${RAW_REPO_ROOT}" && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${REPO_ROOT}" ]; then
    bsp_die "${RAW_REPO_ROOT} is not inside a git repo"
fi

bsp_log "F-B2 starting for ${OWNER}/${PROJECT_NUM} in ${REPO_ROOT}"

# --- Step 2a — standard labels (delegate to setup-labels.sh) -------------

# Pass through --repo OWNER/NAME if we can derive it from origin. This
# lets setup-labels.sh target the right repo without assuming PWD.
ORIGIN_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
LABEL_REPO_ARGS=()
if [ -n "${ORIGIN_URL}" ]; then
    case "${ORIGIN_URL}" in
        *github.com[:/]*)
            trimmed="${ORIGIN_URL%.git}"
            trimmed="${trimmed##*github.com}"
            trimmed="${trimmed#:}"
            trimmed="${trimmed#/}"
            if [ -n "${trimmed}" ]; then
                LABEL_REPO_ARGS=(--repo "${trimmed}")
            fi
            ;;
    esac
fi

bsp_log "step 2a: ensuring 13 standard labels (delegating to setup-labels.sh)"
SETUP_LABELS="${PLUGIN_ROOT}/scripts/setup-labels.sh"
if [ ! -f "${SETUP_LABELS}" ]; then
    bsp_die "setup-labels.sh not found at ${SETUP_LABELS}"
fi
if ! bash "${SETUP_LABELS}" "${LABEL_REPO_ARGS[@]+"${LABEL_REPO_ARGS[@]}"}" >&2; then
    # shellcheck disable=SC2016
    printf '[bsp ERROR] step 2a failed: setup-labels.sh exited non-zero. Likely cause: gh auth missing or insufficient scope (needs `repo` scope for label create). Run `gh auth status` to check.\n' >&2
    exit 3
fi

# --- Step 2b — Status field validation -----------------------------------

bsp_log "step 2b: validating Project ${OWNER}/${PROJECT_NUM} Status field"

CANONICAL_STATUS="Backlog,Ready,In Progress,In Review,Done,Blocked"

# Capture gh output then validate. Errors at the gh layer surface as
# exit 3-equivalent "step failure" but with explanatory message.
STATUS_VALIDATION_OUTPUT="$(gh project field-list "${PROJECT_NUM}" \
    --owner "${OWNER}" --format json 2>&1)" || {
    # shellcheck disable=SC2016
    printf '[bsp ERROR] step 2b failed: `gh project field-list %s --owner %s` errored. Likely cause: gh auth missing the `project` scope. Run `gh auth refresh -s project` and retry.\n' \
        "${PROJECT_NUM}" "${OWNER}" >&2
    printf '%s\n' "${STATUS_VALIDATION_OUTPUT}" >&2
    exit 3
}

VALIDATION_RESULT="$(printf '%s' "${STATUS_VALIDATION_OUTPUT}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError as e:
    sys.stderr.write('cannot parse gh project field-list JSON: ' + str(e) + '\n')
    sys.exit(2)
canonical = sys.argv[1].split(',')
for f in data.get('fields', []) or []:
    if f.get('name') == 'Status':
        opts = [o.get('name') for o in (f.get('options') or [])]
        if opts == canonical:
            print('OK')
            sys.exit(0)
        print('DRIFT:' + ','.join(opts))
        sys.exit(0)
print('MISSING')
sys.exit(0)
" "${CANONICAL_STATUS}")" || {
    bsp_die "step 2b: failed to parse gh project field-list output"
}

case "${VALIDATION_RESULT}" in
    OK)
        bsp_log "step 2b: Status field options match canonical 6-option order"
        ;;
    MISSING)
        printf '[bsp ERROR] step 2b: Status field not found on Project %s/%s.\n' \
            "${OWNER}" "${PROJECT_NUM}" >&2
        printf '  Go to the Project settings on github.com → "Settings" → "Fields" → ensure a "Status" single-select field exists with these 6 options in this order:\n' >&2
        printf '    Backlog → Ready → In Progress → In Review → Done → Blocked\n' >&2
        exit 2
        ;;
    DRIFT:*)
        ACTUAL="${VALIDATION_RESULT#DRIFT:}"
        printf '[bsp ERROR] step 2b: Status field options drift detected on Project %s/%s.\n' \
            "${OWNER}" "${PROJECT_NUM}" >&2
        printf '  Expected (canonical 6-option order): Backlog → Ready → In Progress → In Review → Done → Blocked\n' >&2
        printf '  Actual: %s\n' "${ACTUAL}" >&2
        printf '  Go to the GitHub Project settings → Status field → ensure 6 options in this exact order, then re-run F-B2.\n' >&2
        exit 2
        ;;
    *)
        bsp_die "step 2b: unexpected validation result: ${VALIDATION_RESULT}"
        ;;
esac

# --- Step 2c — write <repo>/.board-superpowers/config.yml ----------------

CONFIG_DIR="${REPO_ROOT}/.board-superpowers"
CONFIG_FILE="${CONFIG_DIR}/config.yml"

mkdir -p "${CONFIG_DIR}" || bsp_die "step 2c: cannot create ${CONFIG_DIR}"

write_config_yml() {
    cat > "${CONFIG_FILE}" <<EOF
# board-superpowers per-repo configuration (committed to git).
# Managed by using-board-superpowers. Safe to edit by hand.
# See docs/architecture/0005-contracts/03-config-schemas.md for the
# full schema.

project: "${OWNER}/${PROJECT_NUM}"
wip_limit: 5

# Future fields (uncomment when needed):
# audit_db_url: "postgresql://user:pwd@host:5432/db"
# claim_branch_prefix: "claim/"
# worktree_dir: "/custom/worktrees"
EOF
}

if [ -f "${CONFIG_FILE}" ] && [ "${FORCE}" -eq 0 ]; then
    bsp_log "step 2c: ${CONFIG_FILE} already exists — leaving alone (use --force to overwrite)"
else
    if [ -f "${CONFIG_FILE}" ]; then
        bsp_log "step 2c: --force overwriting ${CONFIG_FILE}"
    else
        bsp_log "step 2c: writing ${CONFIG_FILE}"
    fi
    write_config_yml
fi

# --- Step 2d — append to <repo>/.gitignore (idempotent) ------------------

GITIGNORE_FILE="${REPO_ROOT}/.gitignore"
GITIGNORE_HEADER="# board-superpowers local state (claim markers are per-session)"
GITIGNORE_ENTRY=".board-superpowers/claims/"

write_gitignore_block() {
    # Append a leading blank line for visual separation only when the
    # file already has content. New files start with the block.
    local prepend_blank="$1"
    {
        if [ "${prepend_blank}" = "1" ]; then
            printf '\n'
        fi
        printf '%s\n%s\n' "${GITIGNORE_HEADER}" "${GITIGNORE_ENTRY}"
    } >> "${GITIGNORE_FILE}"
}

if [ -f "${GITIGNORE_FILE}" ]; then
    if grep -Fxq "${GITIGNORE_ENTRY}" "${GITIGNORE_FILE}"; then
        bsp_log "step 2d: .gitignore already contains '${GITIGNORE_ENTRY}' — no change"
    else
        # Defensive: ensure trailing newline before append so we don't
        # glue our block onto the last line of an unterminated file.
        if [ -s "${GITIGNORE_FILE}" ]; then
            tail -c1 "${GITIGNORE_FILE}" | od -An -c | tr -d ' ' | grep -q '\\n' \
                || printf '\n' >> "${GITIGNORE_FILE}"
        fi
        bsp_log "step 2d: appending board-superpowers block to ${GITIGNORE_FILE}"
        write_gitignore_block 1
    fi
else
    bsp_log "step 2d: creating ${GITIGNORE_FILE} with board-superpowers block"
    write_gitignore_block 0
fi

# --- Step 3 — initial state.yml write (host-local) -----------------------

# Ensure ~/.board-superpowers exists at mode 0700; mkdir -p is idempotent.
HOST_ROOT="${HOME}/.board-superpowers"
mkdir -p "${HOST_ROOT}" || bsp_die "cannot create ${HOST_ROOT}"
chmod 0700 "${HOST_ROOT}"

STATE_DIR="$(bsp_host_state_dir "${REPO_ROOT}")"
STATE_FILE="${STATE_DIR}/state.yml"
mkdir -p "${STATE_DIR}" || bsp_die "cannot create ${STATE_DIR}"
chmod 0700 "${STATE_DIR}"

iso_utc_now() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# Read a top-level scalar from a flat YAML file. Same shape as the
# helper in bootstrap-host.sh.
yaml_get() {
    local file="$1"
    local key="$2"
    [ -f "${file}" ] || return 0
    grep -E "^${key}[[:space:]]*:" "${file}" 2>/dev/null \
        | head -n1 \
        | sed -E "s/^${key}[[:space:]]*:[[:space:]]*//; s/^\"//; s/\"$//"
}

write_state_yml() {
    local ts="$1"
    local version="$2"

    if [ -d "${STATE_FILE}" ]; then
        bsp_die "refuses to write: ${STATE_FILE} exists as a directory, not a file"
    fi

    local tmp
    tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")" \
        || bsp_die "could not create temp state file in ${STATE_DIR}"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" EXIT

    cat > "${tmp}" <<EOF
schema_version: 1
repo_bootstrapped_at: "${ts}"
last_seen_version_in_repo: "${version}"
features_enabled:
  - bootstrap.host
  - bootstrap.per_repo
routing_blocks: []
EOF

    chmod 0644 "${tmp}"

    if ! mv "${tmp}" "${STATE_FILE}" 2>/dev/null; then
        rm -f "${tmp}"
        trap - EXIT
        bsp_die "atomic mv to ${STATE_FILE} failed"
    fi
    trap - EXIT
}

NOW_TS="$(iso_utc_now)"

if [ -f "${STATE_FILE}" ]; then
    EXISTING_VERSION="$(yaml_get "${STATE_FILE}" last_seen_version_in_repo)"
    EXISTING_TS="$(yaml_get "${STATE_FILE}" repo_bootstrapped_at)"

    if [ "${EXISTING_VERSION}" = "${PLUGIN_VERSION}" ] && [ "${FORCE}" -eq 0 ]; then
        chmod 0644 "${STATE_FILE}"
        bsp_log "state.yml current at ${STATE_FILE} (last_seen_version_in_repo=${PLUGIN_VERSION}); no write"
    else
        # Refresh path. Preserve repo_bootstrapped_at when present,
        # bump last_seen_version_in_repo to the running plugin version.
        if [ -z "${EXISTING_TS}" ]; then
            EXISTING_TS="${NOW_TS}"
            bsp_warn "existing state.yml missing repo_bootstrapped_at; regenerating"
        fi
        if [ "${FORCE}" -eq 1 ]; then
            bsp_log "state.yml: --force rewriting at ${STATE_FILE}"
        else
            bsp_log "state.yml refresh: ${EXISTING_VERSION:-<unset>} → ${PLUGIN_VERSION}"
        fi
        write_state_yml "${EXISTING_TS}" "${PLUGIN_VERSION}"
        bsp_log "wrote ${STATE_FILE}"
    fi
else
    bsp_log "writing initial state.yml at ${STATE_FILE}"
    write_state_yml "${NOW_TS}" "${PLUGIN_VERSION}"
    bsp_log "wrote ${STATE_FILE}"
fi

bsp_log "F-B2 slice 2 complete (steps 2a-2d + initial state.yml). Slice 3 (BYO-RDBMS) and slice 4 (routing block injection) deferred."
exit 0
