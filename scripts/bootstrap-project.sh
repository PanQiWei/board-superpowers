#!/usr/bin/env bash
# scripts/bootstrap-project.sh — F-B2 per-repo bootstrap engine
# (slices 2 + 3 + 4 — steps 2a-2e, step 4 routing block injection,
# initial state.yml write with routing_blocks[]).
#
# Spec:
#   docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
#     § 1.5.2 F-B2. Per-repo bootstrap (steps 1, 2a-2e, 3 — initial
#     state.yml write).
#   docs/architecture/0005-contracts/03-config-schemas.md (config.yml,
#     credentials.yml, and state.yml shapes; 6-scheme allowlist).
#   docs/architecture/0005-contracts/05-github-artifact-schemas.md
#     § "Project v2 Status enum" (canonical 6-option contract).
#   docs/architecture/0005-contracts/07-path-conventions.md
#     § "Per-host layout" + "The .gitignore block".
#   docs/architecture/adr/0009-allow-sqlite-as-byo-audit-db.md
#     (6-scheme allowlist; SQLite 4-slash absolute-path convention).
#
# Capability: when invoked with --owner/--project/--repo-root, run
# F-B2 steps 2a-2e (standard labels via setup-labels.sh, Status field
# validation, config.yml write, .gitignore append, BYO-RDBMS credential
# UX), step 4 (dual-file routing block injection into AGENTS.md +
# CLAUDE.md with per-file SHA256 tamper hashes), and write the initial
# host-local state.yml with the recorded routing_blocks[] entries.
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
#       [--audit-db-url URL]  # non-interactive equivalent of typing
#                             # the DSN at the interactive prompt;
#                             # ALWAYS persists to credentials.yml
#                             # (chmod 0600) regardless of scheme. Use
#                             # $BOARD_SP_AUDIT_DB_URL for ephemeral /
#                             # runtime override that does NOT persist.
#
# --owner and --project are REQUIRED for step 2b (Status field check).
# --repo-root defaults to ${CLAUDE_PROJECT_DIR:-$PWD} resolved to
# `git rev-parse --show-toplevel`.
#
# Step 2e BYO-RDBMS resolution priority:
#   1. --audit-db-url FLAG (highest; PERSISTS to credentials.yml at
#      chmod 0600 — same end state as Path C accept).
#   2. $BOARD_SP_AUDIT_DB_URL env var (runtime override; does NOT
#      persist — ephemeral by design).
#   3. pre-existing ~/.board-superpowers/credentials.yml (with valid
#      audit_db_url).
#   4. interactive prompt (PERSISTS on accept; records decline on skip).
#
# Exit codes:
#   0  success
#   1  bad args / file write failure
#   2  Status field drift detected (step 2b)
#   3  step 2a (labels) delegation failed
#   4  step 2e BYO-RDBMS config invalid (bad scheme; sqlite parent
#      not writable; interactive retry budget exhausted)
#   5  step 4 routing block injection blocked by orphan markers
#      (only one of opening / closing marker present in target file)
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
AUDIT_DB_URL_FLAG=""

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
        --audit-db-url)
            AUDIT_DB_URL_FLAG="${2:-}"
            [ -n "${AUDIT_DB_URL_FLAG}" ] || bsp_die "--audit-db-url requires a value"
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

# --- Step 2c — write <repo>/.board-superpowers/config.yml + config.local.yml ----

CONFIG_DIR="${REPO_ROOT}/.board-superpowers"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
LOCAL_CONFIG_FILE="${CONFIG_DIR}/config.local.yml"

mkdir -p "${CONFIG_DIR}" || bsp_die "step 2c: cannot create ${CONFIG_DIR}"

write_config_yml() {
    cat > "${CONFIG_FILE}" <<EOF
# board-superpowers per-repo configuration (committed to git, team-shared).
# Managed by using-board-superpowers. Safe to edit by hand.
# See docs/architecture/0005-contracts/03-config-schemas.md for the
# full schema.
#
# Per-user fields (wip_limit, autonomy_overrides) live in
# config.local.yml — gitignored via the *.local.* pattern.

project: "${OWNER}/${PROJECT_NUM}"

# Future team-shared fields (uncomment when needed):
# audit_db_url: "postgresql://user:pwd@host:5432/db"
# base_branch: main
# default_execution_skill: superpowers:subagent-driven-development
EOF
}

write_local_config_yml() {
    cat > "${LOCAL_CONFIG_FILE}" <<'EOF'
# board-superpowers per-user override config (gitignored).
# Each architect on this repo may have different values here.
# See docs/architecture/0005-contracts/03-config-schemas.md
# § "config.local.yml — LocalRepoConfig" for the full schema.

# Personal capacity / parallelism choice (Soft cap; default 5).
# Counted as: In Progress + In Review; Blocked excluded.
wip_limit: 5

# Per-project autonomy overrides (per ADR-0006 §4).
# autonomy_overrides:
#   - action_id: 5
#     class: A
#     since: "YYYY-MM-DDTHH:MM:SSZ"
#     evolved_by: "github_username"
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

if [ -f "${LOCAL_CONFIG_FILE}" ] && [ "${FORCE}" -eq 0 ]; then
    bsp_log "step 2c: ${LOCAL_CONFIG_FILE} already exists — leaving alone (use --force to overwrite)"
else
    if [ -f "${LOCAL_CONFIG_FILE}" ]; then
        bsp_log "step 2c: --force overwriting ${LOCAL_CONFIG_FILE}"
    else
        bsp_log "step 2c: writing ${LOCAL_CONFIG_FILE} (gitignored, per-user)"
    fi
    write_local_config_yml
fi

# --- Step 2d — append to <repo>/.gitignore (idempotent) ------------------
#
# Two distinct entries land independently:
#   1. Project-wide *.local.* per-user override pattern.
#   2. board-superpowers-specific .board-superpowers/claims/ rule.
# Each is checked + appended on its own so partial state (one
# entry already present, the other missing) is handled correctly.

GITIGNORE_FILE="${REPO_ROOT}/.gitignore"
LOCAL_PATTERN_HEADER="# Per-user local override files — convention: <name>.local.<ext>"
LOCAL_PATTERN_ENTRY="*.local.*"
CLAIMS_HEADER="# board-superpowers local state (claim markers are per-session)"
CLAIMS_ENTRY=".board-superpowers/claims/"
VENV_HEADER="# board-superpowers per-repo Python venv (created by step 2f)"
VENV_ENTRY=".board-superpowers/.venv/"

ensure_trailing_newline() {
    if [ -s "${GITIGNORE_FILE}" ]; then
        tail -c1 "${GITIGNORE_FILE}" | od -An -c | tr -d ' ' | grep -q '\\n' \
            || printf '\n' >> "${GITIGNORE_FILE}"
    fi
}

append_block() {
    # $1 = header line; $2 = entry line; $3 = "1" to prepend blank line.
    local header="$1"
    local entry="$2"
    local prepend_blank="$3"
    {
        if [ "${prepend_blank}" = "1" ]; then
            printf '\n'
        fi
        printf '%s\n%s\n' "${header}" "${entry}"
    } >> "${GITIGNORE_FILE}"
}

# Bootstrap: create file with all blocks if absent.
if [ ! -f "${GITIGNORE_FILE}" ]; then
    bsp_log "step 2d: creating ${GITIGNORE_FILE} with board-superpowers blocks"
    append_block "${LOCAL_PATTERN_HEADER}" "${LOCAL_PATTERN_ENTRY}" 0
    append_block "${CLAIMS_HEADER}" "${CLAIMS_ENTRY}" 1
    append_block "${VENV_HEADER}" "${VENV_ENTRY}" 1
else
    # Append-on-missing for each entry independently.
    if grep -Fxq "${LOCAL_PATTERN_ENTRY}" "${GITIGNORE_FILE}"; then
        bsp_log "step 2d: .gitignore already contains '${LOCAL_PATTERN_ENTRY}' — no change"
    else
        ensure_trailing_newline
        bsp_log "step 2d: appending '${LOCAL_PATTERN_ENTRY}' block to ${GITIGNORE_FILE}"
        append_block "${LOCAL_PATTERN_HEADER}" "${LOCAL_PATTERN_ENTRY}" 1
    fi

    if grep -Fxq "${CLAIMS_ENTRY}" "${GITIGNORE_FILE}"; then
        bsp_log "step 2d: .gitignore already contains '${CLAIMS_ENTRY}' — no change"
    else
        ensure_trailing_newline
        bsp_log "step 2d: appending '${CLAIMS_ENTRY}' block to ${GITIGNORE_FILE}"
        append_block "${CLAIMS_HEADER}" "${CLAIMS_ENTRY}" 1
    fi

    # F6: .venv/ must not leak into git. Step 2f creates
    # <repo>/.board-superpowers/.venv/ — ensure it is gitignored.
    if grep -Fxq "${VENV_ENTRY}" "${GITIGNORE_FILE}"; then
        bsp_log "step 2d: .gitignore already contains '${VENV_ENTRY}' — no change"
    else
        ensure_trailing_newline
        bsp_log "step 2d: appending '${VENV_ENTRY}' block to ${GITIGNORE_FILE}"
        append_block "${VENV_HEADER}" "${VENV_ENTRY}" 1
    fi
fi

# --- Step 2e — BYO-RDBMS audit-log credential UX -------------------------
#
# Per spec § 1.5.2 step 2e + 03-config-schemas.md credentials.yml schema +
# ADR-0009. Three paths:
#   A. --audit-db-url FLAG or $BOARD_SP_AUDIT_DB_URL env var   →
#      validate scheme, do NOT write credentials.yml (the runtime
#      override IS the credential).
#   B. pre-existing ~/.board-superpowers/credentials.yml with valid
#      audit_db_url                                            →
#      re-use; warn on loose mode (don't auto-tighten — user-managed).
#   C. interactive prompt                                      →
#      validate, write credentials.yml chmod 0600, OR record decline.
#
# Aborts (exit 4) on invalid scheme, sqlite parent dir unwritable,
# or interactive retry budget exhausted. State.yml is NOT written
# on abort — same semantics as step 2a/2b.

# 6-scheme allowlist per ADR-0009 + 03-config-schemas.md.
BSP_AUDIT_SCHEMES="postgresql:// postgres:// mysql:// mysql+pymysql:// sqlite:// sqlite3://"

# Validate a DSN structurally via python3 + urllib.parse.
# Returns 0 on accept, 1 on reject. The DSN is passed via env var
# (not heredoc interpolation) so shell metacharacters in the DSN
# can't break the python source.
#
# Accept rules:
#   - scheme ∈ {postgresql, postgres, mysql, mysql+pymysql, sqlite, sqlite3}
#   - non-sqlite schemes: urlparse(dsn).hostname must be non-empty
#   - sqlite / sqlite3: urlparse(dsn).path must start with "/"
#     (the 4-slash form `sqlite:////abs/path` yields path='//abs/path'
#     which still starts with '/'; 3-slash relative form yields
#     path='relative/...' and is rejected)
audit_dsn_validate() {
    local dsn="$1"
    BSP_AUDIT_DSN="${dsn}" python3 - <<'PY' 2>/dev/null
import os, sys
from urllib.parse import urlparse

dsn = os.environ.get("BSP_AUDIT_DSN", "")
allowed = {"postgresql", "postgres", "mysql", "mysql+pymysql",
           "sqlite", "sqlite3"}
try:
    u = urlparse(dsn)
except (ValueError, TypeError):
    sys.exit(1)
if u.scheme not in allowed:
    sys.exit(1)
if u.scheme in ("sqlite", "sqlite3"):
    # Per ADR-0009: require the 4-slash absolute form
    # (sqlite:////abs/path). urlparse on the 4-slash form yields
    # path='//abs/path' (two leading slashes); the 3-slash relative
    # form (sqlite:///rel/path) yields path='/rel/path' (one leading
    # slash). Require two leading slashes so the 3-slash form is
    # rejected even though it technically begins with '/'.
    if not u.path or not u.path.startswith("//"):
        sys.exit(1)
else:
    if not u.hostname:
        sys.exit(1)
    # Catch malformed port-position garbage — e.g.
    # `postgres://user@host:5432:wrong/db`. urlparse extracts
    # hostname='host' but accessing .port raises ValueError because
    # '5432:wrong' isn't a valid integer port.
    try:
        _ = u.port
    except ValueError:
        sys.exit(1)
sys.exit(0)
PY
}

print_scheme_allowlist() {
    local target="${1:-stderr}"
    if [ "${target}" = "stdout" ]; then
        printf 'Accepted schemes (per ADR-0009 + 03-config-schemas.md):\n'
        # shellcheck disable=SC2086
        for s in ${BSP_AUDIT_SCHEMES}; do
            printf '  - %s\n' "${s}"
        done
    else
        printf 'Accepted schemes (per ADR-0009 + 03-config-schemas.md):\n' >&2
        # shellcheck disable=SC2086
        for s in ${BSP_AUDIT_SCHEMES}; do
            printf '  - %s\n' "${s}" >&2
        done
    fi
}

# Extract sqlite absolute path from a 4-slash sqlite DSN.
# `sqlite:////abs/path` → `/abs/path`. Returns empty on shape mismatch.
audit_sqlite_path_extract() {
    local dsn="$1"
    case "${dsn}" in
        sqlite:////*)
            printf '%s' "/${dsn#sqlite:////}"
            ;;
        sqlite3:////*)
            printf '%s' "/${dsn#sqlite3:////}"
            ;;
        *)
            printf ''
            ;;
    esac
}

# Verify a sqlite DSN's parent dir is writable. Returns 0/1; on
# failure prints an error to stderr explaining which dir was rejected.
audit_sqlite_parent_writable() {
    local dsn="$1"
    local abs_path parent
    abs_path="$(audit_sqlite_path_extract "${dsn}")"
    if [ -z "${abs_path}" ]; then
        # Not a sqlite DSN, or 3-slash form (which we reject elsewhere).
        printf '[bsp ERROR] step 2e: SQLite DSN must use 4-slash absolute form (got: %s)\n' "${dsn}" >&2
        return 1
    fi
    parent="$(dirname "${abs_path}")"
    if [ ! -d "${parent}" ]; then
        printf '[bsp ERROR] step 2e: SQLite parent directory does not exist: %s\n' "${parent}" >&2
        return 1
    fi
    if [ ! -w "${parent}" ]; then
        printf '[bsp ERROR] step 2e: SQLite parent directory is not writable: %s\n' "${parent}" >&2
        return 1
    fi
    return 0
}

# Reject a sqlite DSN whose absolute path resolves under ${REPO_ROOT}.
# Per spec 07-path-conventions § forbidden-destinations + 03-config-schemas.md
# credentials.yml: a SQLite audit DB inside the repo's own working tree
# would bleed audit data into git history.
# Returns 0 (safe), 1 (rejected — prints error to stderr).
audit_sqlite_not_under_repo() {
    local dsn="$1"
    local abs_path
    abs_path="$(audit_sqlite_path_extract "${dsn}")"
    # Only applies to sqlite DSNs; non-sqlite forms are silently OK here.
    [ -z "${abs_path}" ] && return 0

    # Canonicalise REPO_ROOT to an absolute path with trailing slash so
    # the prefix test is unambiguous.
    local repo_canonical
    repo_canonical="$(cd "${REPO_ROOT}" && pwd -P)/"

    # Resolve abs_path as far as possible; the file may not yet exist so
    # we only resolve up to the existing parent.
    local abs_canonical
    local abs_parent
    abs_parent="$(dirname "${abs_path}")"
    if [ -d "${abs_parent}" ]; then
        abs_canonical="$(cd "${abs_parent}" && pwd -P)/$(basename "${abs_path}")"
    else
        abs_canonical="${abs_path}"
    fi
    # Normalise: ensure trailing / on the repo prefix before comparing.
    case "${abs_canonical}/" in
        "${repo_canonical}"*)
            printf '[bsp ERROR] step 2e: SQLite DB path resolves under the repo root (%s).\n' \
                "${REPO_ROOT}" >&2
            printf '[bsp]   Audit data must be stored outside the working tree (spec 07-path-conventions\n' >&2
            printf '[bsp]   § forbidden-destinations). Suggested default path:\n' >&2
            printf '[bsp]   sqlite:////%s/.board-superpowers/repos/<normalized>/audit.db\n' \
                "${HOME#/}" >&2
            return 1
            ;;
    esac
    return 0
}

# Read top-level audit_db_url from a flat YAML credentials file.
# Empty stdout if absent or unparseable. Same shape as yaml_get
# helpers below but inlined here so step 2e is self-contained.
credentials_yml_dsn() {
    local file="$1"
    [ -f "${file}" ] || return 0
    grep -E '^audit_db_url[[:space:]]*:' "${file}" 2>/dev/null \
        | head -n1 \
        | sed -E 's/^audit_db_url[[:space:]]*:[[:space:]]*//; s/^"//; s/"$//; s/^'\''//; s/'\''$//'
}

# Atomic write of credentials.yml at chmod 0600. Same mktemp+mv
# pattern as state.yml (step 3 below) and bootstrap-host's manifest.
write_credentials_yml() {
    local dsn="$1"
    local cred_dir="${HOME}/.board-superpowers"
    local cred_file="${cred_dir}/credentials.yml"

    mkdir -p "${cred_dir}" || bsp_die "step 2e: cannot create ${cred_dir}"
    chmod 0700 "${cred_dir}"

    if [ -d "${cred_file}" ]; then
        bsp_die "step 2e: refuses to write — ${cred_file} exists as a directory"
    fi

    local tmp
    tmp="$(mktemp "${cred_file}.tmp.XXXXXX")" \
        || bsp_die "step 2e: could not create temp credentials file in ${cred_dir}"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" EXIT INT TERM

    cat > "${tmp}" <<EOF
# board-superpowers BYO-RDBMS credentials (host-local, NEVER tracked in git).
# Per ADR-0006 §5 + ADR-0009 + 03-config-schemas.md credentials.yml schema.
# chmod 0600 (read+write owner only). Never share.

audit_db_url: "${dsn}"
EOF

    chmod 0600 "${tmp}"

    if ! mv "${tmp}" "${cred_file}" 2>/dev/null; then
        rm -f "${tmp}"
        trap - EXIT INT TERM
        bsp_die "step 2e: atomic mv to ${cred_file} failed"
    fi
    trap - EXIT INT TERM
    bsp_log "step 2e: wrote ${cred_file} (chmod 0600)"
}

# Run the interactive prompt. Returns 0 on success (with credentials.yml
# written or decline acknowledged) or invokes exit 4 on retry exhaustion
# / unwritable sqlite parent.
audit_interactive_prompt() {
    # Read attempts from stdin (or /dev/tty if available + interactive).
    # In test scenarios stdin is preloaded via heredoc-string and there
    # is no controlling tty; honor that path.
    local input_source="/dev/stdin"
    if [ -t 0 ] && [ -r /dev/tty ]; then
        input_source="/dev/tty"
    fi

    local attempt max_attempts=3
    attempt=0

    while [ "${attempt}" -lt "${max_attempts}" ]; do
        attempt=$((attempt + 1))

        # Show the prompt block on stderr so it doesn't pollute stdout
        # consumers (none here, but consistent with bsp_log convention).
        {
            printf '\n'
            printf '[bsp] step 2e: BYO-RDBMS audit-log credential setup\n'
            printf '[bsp]\n'
            printf '[bsp] Per ADR-0006 §5 + ADR-0009. The architect provisions an\n'
            printf '[bsp] RDBMS for the audit log. Six accepted schemes:\n'
            for s in ${BSP_AUDIT_SCHEMES}; do
                printf '[bsp]   - %s\n' "${s}"
            done
            printf '[bsp]\n'
            printf '[bsp] SQLite default suggestion (4-slash absolute path):\n'
            printf '[bsp]   sqlite:////%s/.board-superpowers/repos/<normalized>/audit.db\n' "${HOME#/}"
            printf '[bsp]\n'
            printf '[bsp] Enter a DSN, or leave blank / type "skip" to decline\n'
            printf '[bsp] (every A-class action will degrade to R-class until\n'
            printf '[bsp] you re-run F-B2 with --rebootstrap-db).\n'
            printf '[bsp] DSN> '
        } >&2

        local dsn
        if ! IFS= read -r dsn < "${input_source}"; then
            # EOF / unreadable input: treat as decline (same as empty).
            dsn=""
        fi
        # Strip leading/trailing whitespace.
        dsn="${dsn#"${dsn%%[![:space:]]*}"}"
        dsn="${dsn%"${dsn##*[![:space:]]}"}"

        case "${dsn}" in
            ""|skip|SKIP|Skip)
                bsp_warn "step 2e: BYO-RDBMS declined — every A-class action will degrade to R-class until you re-run F-B2 with --rebootstrap-db"
                BSP_AUDIT_DECLINED=1
                return 0
                ;;
        esac

        if ! audit_dsn_validate "${dsn}"; then
            printf '[bsp ERROR] step 2e: DSN is malformed or has unsupported scheme: %s\n' "${dsn}" >&2
            print_scheme_allowlist stderr
            printf '[bsp]   non-sqlite schemes require a host part\n' >&2
            printf '[bsp]   sqlite/sqlite3 require the 4-slash absolute form (sqlite:////abs/path) per ADR-0009\n' >&2
            if [ "${attempt}" -lt "${max_attempts}" ]; then
                printf '[bsp] retry (%d of %d remaining)\n' \
                    "$((max_attempts - attempt))" "${max_attempts}" >&2
                continue
            fi
            printf '[bsp ERROR] step 2e: retry budget exhausted (%d attempts)\n' \
                "${max_attempts}" >&2
            exit 4
        fi

        # SQLite checks: under-repo guard + parent-dir writability.
        case "${dsn}" in
            sqlite://*|sqlite3://*)
                if ! audit_sqlite_not_under_repo "${dsn}"; then
                    # Under-repo: re-prompt so the architect can pick a
                    # safe path.
                    if [ "${attempt}" -lt "${max_attempts}" ]; then
                        printf '[bsp] retry (%d of %d remaining)\n' \
                            "$((max_attempts - attempt))" "${max_attempts}" >&2
                        continue
                    fi
                    printf '[bsp ERROR] step 2e: retry budget exhausted (%d attempts)\n' \
                        "${max_attempts}" >&2
                    exit 4
                fi
                if ! audit_sqlite_parent_writable "${dsn}"; then
                    # Hard fail — don't re-prompt; spec says abort on
                    # unwritable parent dir before any credentials.yml
                    # write attempt.
                    exit 4
                fi
                ;;
        esac

        write_credentials_yml "${dsn}"
        BSP_AUDIT_DECLINED=0
        return 0
    done
}

bsp_log "step 2e: starting BYO-RDBMS audit-log credential UX"

# Resolve precedence: flag > env var > pre-existing credentials.yml >
# interactive. BSP_AUDIT_DECLINED records whether the architect
# declined BYO-RDBMS during the interactive prompt (Path C decline);
# slice 7 may surface it as a state.yml field. Today it's set as a
# trace for log forensics — referenced via "${BSP_AUDIT_DECLINED:-0}"
# downstream consumers.
# shellcheck disable=SC2034  # consumed in slice 7 (state.yml degradation flag)
BSP_AUDIT_DECLINED=0
CREDENTIALS_FILE="${HOME}/.board-superpowers/credentials.yml"

if [ -n "${AUDIT_DB_URL_FLAG}" ]; then
    if ! audit_dsn_validate "${AUDIT_DB_URL_FLAG}"; then
        printf '[bsp ERROR] step 2e: --audit-db-url is malformed or has unsupported scheme: %s\n' \
            "${AUDIT_DB_URL_FLAG}" >&2
        print_scheme_allowlist stderr
        printf '[bsp]   non-sqlite schemes require a host part\n' >&2
        printf '[bsp]   sqlite/sqlite3 require the 4-slash absolute form (sqlite:////abs/path) per ADR-0009\n' >&2
        exit 4
    fi
    # SQLite-only filesystem-side checks: under-repo guard + parent writable.
    case "${AUDIT_DB_URL_FLAG}" in
        sqlite://*|sqlite3://*)
            if ! audit_sqlite_not_under_repo "${AUDIT_DB_URL_FLAG}"; then
                exit 4
            fi
            if ! audit_sqlite_parent_writable "${AUDIT_DB_URL_FLAG}"; then
                exit 4
            fi
            ;;
    esac
    # Flag is the non-interactive equivalent of typing the DSN at the
    # prompt — persist for ALL valid schemes (chmod 0600). Use
    # $BOARD_SP_AUDIT_DB_URL for ephemeral / runtime overrides that
    # should NOT be written to disk.
    write_credentials_yml "${AUDIT_DB_URL_FLAG}"
elif [ -n "${BOARD_SP_AUDIT_DB_URL:-}" ]; then
    if ! audit_dsn_validate "${BOARD_SP_AUDIT_DB_URL}"; then
        printf '[bsp ERROR] step 2e: BOARD_SP_AUDIT_DB_URL is malformed or has unsupported scheme: %s\n' \
            "${BOARD_SP_AUDIT_DB_URL}" >&2
        print_scheme_allowlist stderr
        printf '[bsp]   non-sqlite schemes require a host part\n' >&2
        printf '[bsp]   sqlite/sqlite3 require the 4-slash absolute form (sqlite:////abs/path) per ADR-0009\n' >&2
        exit 4
    fi
    # Under-repo guard for env var path too.
    case "${BOARD_SP_AUDIT_DB_URL}" in
        sqlite://*|sqlite3://*)
            if ! audit_sqlite_not_under_repo "${BOARD_SP_AUDIT_DB_URL}"; then
                exit 4
            fi
            ;;
    esac
    bsp_log "step 2e: BOARD_SP_AUDIT_DB_URL env var present; using as runtime override (no credentials.yml write)"
elif [ -f "${CREDENTIALS_FILE}" ]; then
    EXISTING_DSN="$(credentials_yml_dsn "${CREDENTIALS_FILE}")"
    if [ -n "${EXISTING_DSN}" ] && audit_dsn_validate "${EXISTING_DSN}"; then
        # Pre-existing valid file. Under-repo guard for pre-existing creds.
        case "${EXISTING_DSN}" in
            sqlite://*|sqlite3://*)
                if ! audit_sqlite_not_under_repo "${EXISTING_DSN}"; then
                    bsp_warn "step 2e: pre-existing credentials.yml has a SQLite DSN under the repo root — falling through to interactive prompt for a new DSN"
                    audit_interactive_prompt
                    EXISTING_DSN=""  # mark as handled by prompt
                fi
                ;;
        esac
        if [ -n "${EXISTING_DSN}" ]; then
            # Check mode; warn if loose.
            EXISTING_MODE=""
            if EXISTING_MODE="$(stat -f '%A' "${CREDENTIALS_FILE}" 2>/dev/null)"; then
                :
            else
                EXISTING_MODE="$(stat -c '%a' "${CREDENTIALS_FILE}" 2>/dev/null || true)"
            fi
            if [ -n "${EXISTING_MODE}" ] && [ "${EXISTING_MODE}" != "600" ]; then
                bsp_warn "step 2e: ${CREDENTIALS_FILE} mode is 0${EXISTING_MODE} (expected 0600); proceeding without auto-tightening — user-managed file. chmod 0600 yourself when convenient."
            fi
            bsp_log "step 2e: re-using pre-existing credentials.yml (no prompt)"
        fi
    else
        bsp_warn "step 2e: ${CREDENTIALS_FILE} exists but audit_db_url is missing or has an invalid scheme; falling through to interactive prompt"
        audit_interactive_prompt
    fi
else
    audit_interactive_prompt
fi

# Derive RESOLVED_DB_URL for downstream steps (2g):
#   - FLAG and env paths are captured directly from their vars.
#   - credentials.yml path (new or pre-existing) is read from disk.
#   - Interactive decline (BSP_AUDIT_DECLINED=1) → empty.
RESOLVED_DB_URL=""
if [ -n "${AUDIT_DB_URL_FLAG}" ]; then
    RESOLVED_DB_URL="${AUDIT_DB_URL_FLAG}"
elif [ -n "${BOARD_SP_AUDIT_DB_URL:-}" ]; then
    RESOLVED_DB_URL="${BOARD_SP_AUDIT_DB_URL}"
elif [ "${BSP_AUDIT_DECLINED:-0}" != "1" ] && [ -f "${CREDENTIALS_FILE}" ]; then
    RESOLVED_DB_URL="$(credentials_yml_dsn "${CREDENTIALS_FILE}")"
fi

# --- Step 2f — uv sync per-repo venv ------------------------------------
#
# Copies plugin-shipped pyproject.toml + uv.lock to
# <repo>/.board-superpowers/ (only if not already present), then runs
# `uv sync` to materialise the per-repo Python venv.
#
# On failure: rolls back ONLY the files this step copied (newly-created
# pyproject.toml / uv.lock / partial .venv). credentials.yml from step
# 2e is NOT touched — per Codex round-2 #14 fix discipline.
# Rollback NEVER deletes a pre-existing .venv (VENV_PREEXISTED=1).

TARGET_PYPROJECT="${REPO_ROOT}/.board-superpowers/pyproject.toml"
TARGET_LOCK="${REPO_ROOT}/.board-superpowers/uv.lock"
TEMPLATE_PYPROJECT="${PLUGIN_ROOT}/scripts/templates/pyproject.toml"
TEMPLATE_LOCK="${PLUGIN_ROOT}/scripts/templates/uv.lock"

# Track whether THIS step created the files (for rollback).
COPIED_PYPROJECT=0
COPIED_LOCK=0

# Track whether a .venv already existed before this step so rollback
# never destroys a working venv the architect had before re-running
# bootstrap. Only remove .venv on rollback if THIS step created it.
VENV_PREEXISTED=0
if [ -f "${REPO_ROOT}/.board-superpowers/.venv/bin/python3" ]; then
    VENV_PREEXISTED=1
fi

if [ ! -f "${TARGET_PYPROJECT}" ]; then
    [ -f "${TEMPLATE_PYPROJECT}" ] || bsp_die "step 2f: plugin template missing: ${TEMPLATE_PYPROJECT}"
    cp "${TEMPLATE_PYPROJECT}" "${TARGET_PYPROJECT}"
    COPIED_PYPROJECT=1
fi
if [ ! -f "${TARGET_LOCK}" ] && [ -f "${TEMPLATE_LOCK}" ]; then
    cp "${TEMPLATE_LOCK}" "${TARGET_LOCK}"
    COPIED_LOCK=1
fi

# Run uv sync. On failure, roll back ONLY this step's writes; preserve
# credentials.yml from step 2e (already-confirmed standalone outcome).
if (cd "${REPO_ROOT}/.board-superpowers/" && uv sync 2>&1) >&2; then
    bsp_log "step 2f: venv ready at ${REPO_ROOT}/.board-superpowers/.venv"
else
    bsp_warn "step 2f: uv sync failed; rolling back step-2f-created files"
    [ "${COPIED_PYPROJECT}" = "1" ] && rm -f "${TARGET_PYPROJECT}"
    [ "${COPIED_LOCK}" = "1" ] && rm -f "${TARGET_LOCK}"
    # Only remove .venv if THIS step created it — never clobber a
    # pre-existing working venv the architect had before re-running.
    if [ "${VENV_PREEXISTED}" = "0" ]; then
        rm -rf "${REPO_ROOT}/.board-superpowers/.venv"
    fi
    bsp_die "step 2f: venv setup failed; investigate uv (network / proxy / lock conflict / disk full); credentials.yml from step 2e preserved; re-run bootstrap-project.sh after fix"
fi

# --- Step 2g — apply audit DDL (when audit_db_url set) ------------------
#
# Invokes audit-init.sh inline to create the 8-column audit_log table.
# On DDL failure (exit 1 or 3): warns and continues — architect can
# re-run audit-init.sh manually after fixing the DB. credentials.yml
# is preserved regardless.
# On exit 2 (script bug): bootstrap-project exits 1 (hard failure).

if [ -n "${RESOLVED_DB_URL}" ]; then
    bsp_log "step 2g: applying audit DDL via audit-init.sh"
    AUDIT_INIT_RC=0
    BOARD_SP_AUDIT_DB_URL="${RESOLVED_DB_URL}" \
        bash "$(bsp_plugin_root)/scripts/audit-init.sh" || AUDIT_INIT_RC=$?
    case "${AUDIT_INIT_RC}" in
        0)
            bsp_log "step 2g: audit DB initialized"
            ;;
        2)
            bsp_die "step 2g: audit-init.sh exited 2 (script bug); inspect scripts/audit-init.sh"
            ;;
        *)
            bsp_warn "step 2g: audit DDL apply failed (exit ${AUDIT_INIT_RC}); audit DB not usable until fixed (run 'bash scripts/audit-init.sh' manually after resolving)"
            # Do NOT roll back credentials.yml — architect can reattempt.
            # Bootstrap as a whole still succeeds.
            ;;
    esac
fi

# --- Step 4 — dual-file routing block injection --------------------------
#
# Per spec § 1.5.2 step 4: inject the canonical routing block into
# <repo>/AGENTS.md AND <repo>/CLAUDE.md between the marker pair, record
# per-file SHA256 hashes for state.yml:routing_blocks[].
#
# Source-of-truth file:
#   <plugin-root>/skills/using-board-superpowers/references/agentsmd-routing.md
#
# Helper: bsp_inject_routing_block (in scripts/lib/common.sh) — handles
# normalization, marker scan, atomic write. Returns exit 5 on orphan
# markers (one but not both); on that we abort step 4 BEFORE any
# state.yml write so the repo stays in pre-bootstrap state.

ROUTING_SOURCE="${PLUGIN_ROOT}/skills/using-board-superpowers/references/agentsmd-routing.md"
if [ ! -f "${ROUTING_SOURCE}" ]; then
    bsp_die "step 4: routing source not found at ${ROUTING_SOURCE}"
fi

bsp_log "step 4: injecting routing block into AGENTS.md + CLAUDE.md"

ROUTING_HASH_AGENTS=""
ROUTING_HASH_CLAUDE=""

# AGENTS.md.
set +e
ROUTING_HASH_AGENTS="$(bsp_inject_routing_block "${REPO_ROOT}/AGENTS.md" "${ROUTING_SOURCE}")"
RC_AGENTS=$?
set -e
if [ "${RC_AGENTS}" -eq 5 ]; then
    # Orphan marker — error already printed verbatim by helper. Pass
    # through the same exit code so end-to-end tests can grep for
    # "F-B2 step 4" in stderr.
    exit 5
fi
if [ "${RC_AGENTS}" -ne 0 ]; then
    bsp_die "step 4: routing injection into ${REPO_ROOT}/AGENTS.md failed (exit ${RC_AGENTS})"
fi

# CLAUDE.md.
set +e
ROUTING_HASH_CLAUDE="$(bsp_inject_routing_block "${REPO_ROOT}/CLAUDE.md" "${ROUTING_SOURCE}")"
RC_CLAUDE=$?
set -e
if [ "${RC_CLAUDE}" -eq 5 ]; then
    exit 5
fi
if [ "${RC_CLAUDE}" -ne 0 ]; then
    bsp_die "step 4: routing injection into ${REPO_ROOT}/CLAUDE.md failed (exit ${RC_CLAUDE})"
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
    local hash_agents="$3"
    local hash_claude="$4"
    local routing_ts="$5"

    if [ -d "${STATE_FILE}" ]; then
        bsp_die "refuses to write: ${STATE_FILE} exists as a directory, not a file"
    fi

    local tmp
    tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")" \
        || bsp_die "could not create temp state file in ${STATE_DIR}"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" EXIT

    {
        printf 'schema_version: 1\n'
        printf 'repo_bootstrapped_at: "%s"\n' "${ts}"
        printf 'last_seen_version_in_repo: "%s"\n' "${version}"
        printf 'features_enabled:\n'
        printf '  - bootstrap.host\n'
        printf '  - bootstrap.per_repo\n'
        if [ -n "${hash_agents}" ] || [ -n "${hash_claude}" ]; then
            printf 'routing_blocks:\n'
            if [ -n "${hash_agents}" ]; then
                printf '  - target_file: "AGENTS.md"\n'
                printf '    block_hash: "sha256:%s"\n' "${hash_agents}"
                printf '    injected_at: "%s"\n' "${routing_ts}"
            fi
            if [ -n "${hash_claude}" ]; then
                printf '  - target_file: "CLAUDE.md"\n'
                printf '    block_hash: "sha256:%s"\n' "${hash_claude}"
                printf '    injected_at: "%s"\n' "${routing_ts}"
            fi
        else
            printf 'routing_blocks: []\n'
        fi
    } > "${tmp}"

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
        write_state_yml "${EXISTING_TS}" "${PLUGIN_VERSION}" \
            "${ROUTING_HASH_AGENTS}" "${ROUTING_HASH_CLAUDE}" "${NOW_TS}"
        bsp_log "wrote ${STATE_FILE}"
    fi
else
    bsp_log "writing initial state.yml at ${STATE_FILE}"
    write_state_yml "${NOW_TS}" "${PLUGIN_VERSION}" \
        "${ROUTING_HASH_AGENTS}" "${ROUTING_HASH_CLAUDE}" "${NOW_TS}"
    bsp_log "wrote ${STATE_FILE}"
fi

bsp_log "F-B2 slice 4 complete (steps 2a-2g + step 4 routing block injection + state.yml with routing_blocks)."
exit 0
