#!/usr/bin/env bash
# scripts/bootstrap-host.sh — F-B1 host bootstrap.
#
# Spec:
#   docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
#     § 1.5.1 F-B1. Host bootstrap
#   docs/architecture/0005-contracts/07-path-conventions.md
#     § "Per-host layout"
#
# Capability: when ~/.board-superpowers/manifest.yml is absent, run the
# cross-repo, per-machine initialization — create ~/.board-superpowers/
# (mode 0700) and write the initial manifest. When the manifest is
# present, refresh `last_seen_version` if the on-disk value is behind
# the running plugin's version (host_bootstrapped_at is preserved). The
# `--force` flag overwrites unconditionally; intended for dev / migration
# scenarios.
#
# Authoritative manifest.yml shape (per spec lines 122-126):
#
#   schema_version: 1
#   host_bootstrapped_at: "2026-04-26T10:30:00Z"
#   last_seen_version: "0.1.0"
#
# Path: ${HOME}/.board-superpowers/manifest.yml. Mode: dir 0700, file 0644.
#
# Atomicity: render to a per-process scratch file (mktemp) in the same
# directory, chmod, then atomic mv to the final path. If the mv fails
# the scratch file is removed so a Ctrl-C / crash never leaves a
# half-written manifest behind. Per-process tmp filenames mean two
# concurrent invocations on the same host never race on a shared
# scratch file — both render their own .tmp and then race on the final
# rename(2), which POSIX guarantees atomic for same-filesystem moves.
# Loser's manifest content overwrites winner's, but both writers
# produce semantically equivalent payloads (same plugin version,
# timestamps differ by at most µs), so the result is consistent.
#
# Argument vector:
#   bash scripts/bootstrap-host.sh                  # interactive default
#   bash scripts/bootstrap-host.sh --force          # overwrite even when
#                                                   # manifest is correct
#   bash scripts/bootstrap-host.sh --plugin-root P  # override
#                                                   # CLAUDE_PLUGIN_ROOT
#                                                   # for testability
#
# Exit codes:
#   0 — success (manifest written, refreshed, or already current).
#   1 — bad args / mkdir failure / write failure / bad plugin root.
#
# Output:
#   stderr — bsp_log progress lines (human-readable).
#   stdout — on success, the absolute path of the written / refreshed
#            manifest. Callers can pipe this to other scripts.
#
# Self-containment note: this script DOES source scripts/lib/common.sh.
# That is allowed because F-B1 runs AFTER the dep check (check-deps.sh)
# has already verified the lib's integrity (per spec § "Self-contained
# scripts at the dep-check layer" — only check-deps.sh and the
# SessionStart hook are barred from sourcing common.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

# --- Arg parsing --------------------------------------------------------

FORCE=0
PLUGIN_ROOT_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        --plugin-root)
            PLUGIN_ROOT_ARG="${2:-}"
            if [ -z "${PLUGIN_ROOT_ARG}" ]; then
                bsp_die "--plugin-root requires a path argument"
            fi
            shift 2
            ;;
        --help|-h)
            sed -n '2,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" >&2
            exit 0
            ;;
        *)
            bsp_die "unknown argument: $1 (try --help)"
            ;;
    esac
done

# --- Resolve plugin root + version --------------------------------------

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

# Read the version field. Errors out cleanly if the JSON is malformed
# or the version field is missing.
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

# --- Resolve target paths -----------------------------------------------

STATE_DIR="${HOME}/.board-superpowers"
MANIFEST="${STATE_DIR}/manifest.yml"
# MANIFEST_TMP is set per-call inside write_manifest() via mktemp so
# concurrent invocations never collide on a shared scratch file.
MANIFEST_TMP=""

# --- Helpers ------------------------------------------------------------

# Read a top-level scalar field from a flat YAML file using grep + sed.
# The shape is fully predictable (3 lines, no nesting); a real YAML
# parser is overkill. Returns empty string when absent.
#
# YAML tolerates whitespace on either side of the `:` separator
# (`key: value`, `key : value`, `key  :value` are all valid). The
# regex below admits any amount of whitespace before the colon so a
# hand-edited manifest with `last_seen_version : "0.2.0"` still
# parses; this matches what real YAML libraries do.
yaml_get() {
    local file="$1"
    local key="$2"
    [ -f "${file}" ] || return 0
    # Match `key<ws>*:<ws>*<value>` at line start; strip surrounding quotes.
    grep -E "^${key}[[:space:]]*:" "${file}" 2>/dev/null \
        | head -n1 \
        | sed -E "s/^${key}[[:space:]]*:[[:space:]]*//; s/^\"//; s/\"$//"
}

iso_utc_now() {
    # GNU/BSD `date -u +%FT%TZ` is portable.
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# write_manifest <bootstrapped_at> <version>
# Atomic: render to a unique per-process .tmp (mktemp), chmod, then mv.
# On mv failure, scrub the unique .tmp. Two concurrent F-B1 runs each
# get their own scratch file and never race on a shared path; the
# final rename(2) is POSIX-atomic.
write_manifest() {
    local ts="$1"
    local version="$2"

    # Defensive: refuse to proceed if the target path exists as a
    # directory. A bare `mv source dir/` succeeds on POSIX by moving
    # source INTO the directory rather than overwriting it — which
    # silently lands the new manifest at manifest.yml/manifest.yml.tmp
    # and corrupts the layout. Detect this up front.
    if [ -d "${MANIFEST}" ]; then
        bsp_die "refuses to write: ${MANIFEST} exists as a directory, not a file"
    fi

    # Per-process unique scratch file in the same directory as the
    # final manifest, so the subsequent mv is a same-filesystem move
    # (rename(2) atomic). The Xs MUST be trailing — BSD mktemp on
    # macOS only randomizes trailing Xs, not middle-of-template Xs,
    # so a `.tmp` suffix after the Xs would defeat uniqueness and
    # cause concurrent invocations to collide on a literal filename.
    # We use a `.tmp.` PREFIX before the random tail to keep the
    # scratch files identifiable in directory listings and easy to
    # clean up.
    MANIFEST_TMP="$(mktemp "${MANIFEST}.tmp.XXXXXX")" \
        || bsp_die "could not create temp manifest in ${STATE_DIR}"

    # Trap so any unexpected exit (Ctrl-C, write failure) cleans the
    # unique .tmp file. The trap reads MANIFEST_TMP at fire time.
    trap 'rm -f "${MANIFEST_TMP}"' EXIT

    cat > "${MANIFEST_TMP}" <<EOF
schema_version: 1
host_bootstrapped_at: "${ts}"
last_seen_version: "${version}"
EOF

    chmod 0644 "${MANIFEST_TMP}"

    # Atomic mv. If the target is otherwise not overwritable
    # (read-only filesystem, etc.), mv fails — surface the error and
    # clean the .tmp.
    if ! mv "${MANIFEST_TMP}" "${MANIFEST}" 2>/dev/null; then
        rm -f "${MANIFEST_TMP}"
        trap - EXIT
        bsp_die "atomic mv to ${MANIFEST} failed"
    fi

    trap - EXIT
}

# --- Main flow ----------------------------------------------------------

# Ensure state dir exists with mode 0700 (idempotent).
if ! mkdir -p "${STATE_DIR}"; then
    bsp_die "failed to create ${STATE_DIR}"
fi
chmod 0700 "${STATE_DIR}"

NOW_TS="$(iso_utc_now)"

if [ -f "${MANIFEST}" ] && [ "${FORCE}" -eq 0 ]; then
    # Manifest exists. Decide between idempotent no-op and version refresh.
    EXISTING_VERSION="$(yaml_get "${MANIFEST}" last_seen_version)"
    EXISTING_TS="$(yaml_get "${MANIFEST}" host_bootstrapped_at)"

    if [ "${EXISTING_VERSION}" = "${PLUGIN_VERSION}" ]; then
        # Defensive: even on the no-write fast path, converge file
        # mode to 0644 in case a hand-edit (or umask drift) left the
        # file at 0600 / 0400 / etc. Cheap, idempotent.
        chmod 0644 "${MANIFEST}"
        bsp_log "manifest current at ${MANIFEST} (last_seen_version=${PLUGIN_VERSION}); no write"
        printf '%s\n' "${MANIFEST}"
        exit 0
    fi

    # Version refresh — preserve host_bootstrapped_at, bump version.
    if [ -z "${EXISTING_TS}" ]; then
        # Defensive: if the file is malformed and the timestamp is
        # missing, regenerate one rather than write `""`.
        EXISTING_TS="${NOW_TS}"
        bsp_warn "existing manifest missing host_bootstrapped_at; regenerating"
    fi

    bsp_log "refreshing last_seen_version: ${EXISTING_VERSION:-<unset>} → ${PLUGIN_VERSION}"
    write_manifest "${EXISTING_TS}" "${PLUGIN_VERSION}"
    bsp_log "wrote ${MANIFEST}"
    printf '%s\n' "${MANIFEST}"
    exit 0
fi

# Either the manifest is absent OR --force was supplied.
if [ "${FORCE}" -eq 1 ] && [ -e "${MANIFEST}" ]; then
    bsp_log "--force: overwriting ${MANIFEST}"
else
    bsp_log "writing manifest.yml..."
fi

write_manifest "${NOW_TS}" "${PLUGIN_VERSION}"
bsp_log "wrote ${MANIFEST}"
printf '%s\n' "${MANIFEST}"
exit 0
