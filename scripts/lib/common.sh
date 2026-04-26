#!/usr/bin/env bash
# scripts/lib/common.sh — board-superpowers shared bash helpers.
#
# Sourced by every script under scripts/ and every hook under hooks/.
# Provides cross-platform path resolution (CC + Codex), GitHub Project
# field-id lookup, audit-log degraded-mode writer, and standard error
# / logging conventions.
#
# Conventions:
#   - Caller MUST `set -euo pipefail` BEFORE sourcing this file.
#   - All functions return 0 on success, non-zero on failure.
#   - All user-visible output goes to stderr; stdout is reserved for
#     structured data (JSON / values consumed by other scripts).
#   - Compatible with bash 3.2+ (macOS default).

# --- Plugin root resolution ---------------------------------------------
#
# Claude Code sets ${CLAUDE_PLUGIN_ROOT} during hook + script execution.
# Codex CLI does not, so we fall back to deriving the plugin root from
# this file's own location (one level above scripts/lib/).
#
# Always invoke this once at the top of any script that needs the path:
#   PLUGIN_ROOT="$(bsp_plugin_root)"

bsp_plugin_root() {
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then
        printf '%s\n' "${CLAUDE_PLUGIN_ROOT}"
        return 0
    fi
    # Fallback: derive from this file's location.
    # ${BASH_SOURCE[0]} is scripts/lib/common.sh; plugin root is two up.
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s\n' "${lib_dir%/scripts/lib}"
}

# --- Path normalization --------------------------------------------------
#
# Per docs/architecture/0005-contracts/07-path-conventions.md
# § "Path-normalization rule for the per-repo sub-directory":
#
#   1. Strip leading "/".
#   2. Replace remaining "/" with "-".
#
# Examples:
#   /Users/foo/bar-baz                                  -> Users-foo-bar-baz
#   /Users/panqiwei/Dev/repos/nemori-ai/board-superpowers
#                                                       -> Users-panqiwei-Dev-repos-nemori-ai-board-superpowers
#
# Defensive: strip any trailing "/" first so a path like "/Users/foo/"
# normalizes cleanly to "Users-foo" (instead of "Users-foo-").
#
# Input MUST be absolute (start with "/"); relative input is a usage
# error that exits non-zero.

bsp_normalize_repo_path() {
    local p="${1:?usage: bsp_normalize_repo_path <abs-repo-root>}"
    case "${p}" in
        /*) ;;
        *) bsp_die "bsp_normalize_repo_path: path must be absolute, got: ${p}" ;;
    esac
    # Strip trailing slash (defensive for "/Users/foo/" inputs).
    p="${p%/}"
    # Strip leading slash.
    p="${p#/}"
    # Replace remaining "/" with "-".
    printf '%s\n' "${p//\//-}"
}

# --- Host-local + per-repo state paths ----------------------------------
#
# Per AGENTS.md Architecture-at-a-glance + 07-path-conventions.md
# "Per-host layout" (post-Card 1 normalized layout):
#   ~/.board-superpowers/repos/<normalized>/state.yml         (host-local, not in git)
#   ~/.board-superpowers/repos/<normalized>/audit-local.jsonl (degraded audit)
#   <repo>/.board-superpowers/config.yml                       (per-repo, in git)
#
# <normalized> is computed from the repo's absolute path via
# bsp_normalize_repo_path (above). All three helpers below take a
# single <repo_root> argument and derive the canonical sub-directory
# name internally.

bsp_host_state_dir() {
    local repo_root="${1:?usage: bsp_host_state_dir <repo_root>}"
    local normalized
    normalized="$(bsp_normalize_repo_path "${repo_root}")"
    printf '%s/.board-superpowers/repos/%s\n' "${HOME}" "${normalized}"
}

bsp_repo_config_path() {
    local repo_root="${1:?usage: bsp_repo_config_path <repo-root>}"
    printf '%s/.board-superpowers/config.yml\n' "${repo_root}"
}

bsp_audit_local_path() {
    local repo_root="${1:?usage: bsp_audit_local_path <repo_root>}"
    local dir
    dir="$(bsp_host_state_dir "${repo_root}")"
    printf '%s/audit-local.jsonl\n' "${dir}"
}

# --- Logging --------------------------------------------------------------
#
# All user-facing messages go to stderr so they don't pollute stdout
# pipes (used by callers that consume JSON / structured output).

bsp_log() {
    printf '[bsp] %s\n' "$*" >&2
}

bsp_warn() {
    printf '[bsp WARN] %s\n' "$*" >&2
}

bsp_die() {
    printf '[bsp ERROR] %s\n' "$*" >&2
    exit 1
}

# --- Dependency checks ----------------------------------------------------
#
# Verify a binary is on PATH; die with a helpful install hint if not.

bsp_require_cmd() {
    local cmd="${1:?usage: bsp_require_cmd <cmd> [hint]}"
    local hint="${2:-}"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        if [ -n "${hint}" ]; then
            bsp_die "missing dependency: ${cmd} — ${hint}"
        else
            bsp_die "missing dependency: ${cmd}"
        fi
    fi
}

# --- gh CLI helpers -------------------------------------------------------
#
# bsp_gh_field_id: look up a GitHub Project field's GraphQL ID by name.
# Required because gh project item-edit needs --field-id, not --field-name.
#
# Args: <project-owner> <project-number> <field-name>
# Stdout: the field ID
#
# Example:
#   FIELD_ID="$(bsp_gh_field_id PanQiWei 1 Status)"

bsp_gh_field_id() {
    local owner="${1:?usage: bsp_gh_field_id <owner> <project-num> <field-name>}"
    local proj="${2:?usage: bsp_gh_field_id <owner> <project-num> <field-name>}"
    local field="${3:?usage: bsp_gh_field_id <owner> <project-num> <field-name>}"
    bsp_require_cmd gh "install via 'brew install gh'"
    bsp_require_cmd python3 "macOS / Linux ship python3 by default"
    gh project field-list "${proj}" --owner "${owner}" --format json \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
for f in data.get('fields', []):
    if f.get('name') == sys.argv[1]:
        print(f.get('id'))
        sys.exit(0)
sys.exit(1)
" "${field}"
}

# bsp_gh_field_option_id: look up a single-select field option ID by name.
#
# Args: <project-owner> <project-number> <field-name> <option-name>
# Stdout: the option ID

bsp_gh_field_option_id() {
    local owner="${1:?usage: bsp_gh_field_option_id <owner> <proj> <field> <option>}"
    local proj="${2:?usage: bsp_gh_field_option_id <owner> <proj> <field> <option>}"
    local field="${3:?usage: bsp_gh_field_option_id <owner> <proj> <field> <option>}"
    local option="${4:?usage: bsp_gh_field_option_id <owner> <proj> <field> <option>}"
    bsp_require_cmd gh
    bsp_require_cmd python3
    gh project field-list "${proj}" --owner "${owner}" --format json \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
for f in data.get('fields', []):
    if f.get('name') == sys.argv[1]:
        for opt in f.get('options', []) or []:
            if opt.get('name') == sys.argv[2]:
                print(opt.get('id'))
                sys.exit(0)
        sys.exit(1)
sys.exit(1)
" "${field}" "${option}"
}

# --- Audit log degraded-mode writer --------------------------------------
#
# v1-minimum substitute for the auditing-actions skill's BYO-RDBMS write.
# Appends one JSON line per action to the host-local audit-local.jsonl
# at ~/.board-superpowers/repos/<normalized>/audit-local.jsonl.
#
# Args: <repo_root> <action_id> <decision_class> <skill> <summary>
#
# decision_class ∈ {A, R, N} (per ADR-0006 D-AUTONOMY-1).
# action_id catalog lives inline in each v1-minimum molecular skill.
#
# Concurrency: writes use Python's open(path, 'a') which on POSIX
# uses O_APPEND. Single-line writes under PIPE_BUF (4096 bytes;
# audit lines are ~200) are atomic at the kernel level — multiple
# concurrent writers do not interleave. Migration mv is race-tolerant
# (see body).
#
# Schema: a migrated audit-local.jsonl can contain both legacy entries
# (with `host` + `repo` fields, mode=v1-minimum-degraded) and new
# entries (with `repo_root` field). Future readers must handle both.
#
# Inline legacy migration:
#   Before computing the new path, this function checks whether the
#   canonical new path exists. If not, it scans the legacy
#   ~/.board-superpowers/<host>/<repo>/audit-local.jsonl layout
#   (excluding paths under ~/.board-superpowers/repos/) for a match.
#
#   Match heuristic:
#     - The legacy path's last directory segment (the "<repo>" part)
#       must equal the basename of the supplied <repo_root>.
#     - On ambiguity (multiple matches), prefer the one whose
#       grandparent segment (the "<host>" part) matches the
#       owner slug parsed from `git -C <repo_root> remote get-url
#       origin` (when the remote is reachable and parseable).
#     - Fallback: basename-only match.
#
#   On match: mkdir -p the new directory and `mv` the legacy file
#   to the new path. Subsequent calls see the new path exists and
#   skip the migration scan entirely (idempotent). The mv is
#   race-tolerant: if another concurrent process beat us to the
#   migration (legacy gone, new now exists), we proceed without
#   error; the appended line lands on the canonical new path.
#
#   On no match: no migration; just create the new path and append.

bsp_audit_local_write() {
    local repo_root="${1:?usage: bsp_audit_local_write <repo_root> <action_id> <class> <skill> <summary>}"
    local action_id="${2:?}"
    local decision="${3:?}"
    local skill="${4:?}"
    local summary="${5:?}"

    local path
    path="$(bsp_audit_local_path "${repo_root}")"

    # --- Legacy migration (one-shot, idempotent) -------------------------
    if [ ! -f "${path}" ]; then
        local legacy_root="${HOME}/.board-superpowers"
        local repo_basename
        repo_basename="$(basename "${repo_root}")"
        local legacy_match=""

        if [ -d "${legacy_root}" ]; then
            # Try owner-aware match first when origin remote is parseable.
            local owner_slug=""
            if command -v git >/dev/null 2>&1; then
                local origin_url
                origin_url="$(git -C "${repo_root}" remote get-url origin 2>/dev/null || true)"
                if [ -n "${origin_url}" ]; then
                    # Strip protocol + host: works for https://github.com/owner/repo(.git)
                    # and git@github.com:owner/repo(.git).
                    local trimmed="${origin_url}"
                    trimmed="${trimmed%.git}"
                    trimmed="${trimmed##*github.com[:/]}"
                    trimmed="${trimmed##*/}"  # noop fallback if pattern didn't match
                    # Re-parse: take the segment immediately after github.com[:/]
                    case "${origin_url}" in
                        *github.com[:/]*)
                            trimmed="${origin_url##*github.com}"
                            trimmed="${trimmed#:}"
                            trimmed="${trimmed#/}"
                            owner_slug="${trimmed%%/*}"
                            ;;
                    esac
                fi
            fi

            # Scan legacy paths. Skip the new "repos/" subtree.
            local candidate
            for candidate in "${legacy_root}"/*/*/audit-local.jsonl; do
                [ -f "${candidate}" ] || continue
                # Path layout: <legacy_root>/<host>/<repo>/audit-local.jsonl
                local cand_dir host_seg repo_seg
                cand_dir="$(dirname "${candidate}")"
                repo_seg="$(basename "${cand_dir}")"
                host_seg="$(basename "$(dirname "${cand_dir}")")"
                # Skip the new layout root.
                [ "${host_seg}" = "repos" ] && continue
                # Basename match required.
                [ "${repo_seg}" = "${repo_basename}" ] || continue
                # Strong match: host_seg equals owner_slug.
                if [ -n "${owner_slug}" ] && [ "${host_seg}" = "${owner_slug}" ]; then
                    legacy_match="${candidate}"
                    break
                fi
                # Otherwise remember the first basename match as fallback.
                if [ -z "${legacy_match}" ]; then
                    legacy_match="${candidate}"
                fi
            done
        fi

        if [ -n "${legacy_match}" ]; then
            mkdir -p "$(dirname "${path}")"
            # Race-tolerant migration: another concurrent writer may
            # have beaten us to the mv between our [ ! -f "${path}" ]
            # check above and now. When that happens the mv fails
            # because the legacy source is gone; the canonical new
            # path is already in place, so we proceed normally.
            if mv "${legacy_match}" "${path}" 2>/dev/null; then
                bsp_log "audit-local: migrated legacy file ${legacy_match} → ${path}"
            elif [ -f "${path}" ]; then
                bsp_log "audit-local: migration was completed by another process — proceeding"
            else
                bsp_warn "audit-local: migration mv failed and new path absent — falling through to fresh write"
            fi
        fi
    fi
    # --- End migration ---------------------------------------------------

    mkdir -p "$(dirname "${path}")"

    bsp_require_cmd python3
    python3 -c "
import json, sys, time
entry = {
    'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'repo_root': sys.argv[1],
    'action_id': sys.argv[2],
    'decision_class': sys.argv[3],
    'skill': sys.argv[4],
    'summary': sys.argv[5],
    'mode': 'v1-minimum-degraded',
}
with open(sys.argv[6], 'a') as f:
    f.write(json.dumps(entry) + '\n')
" "${repo_root}" "${action_id}" "${decision}" "${skill}" "${summary}" "${path}"

    bsp_log "audit-local: ${decision}-class action ${action_id} (${skill}) → ${path}"
}

# --- Worktree path convention --------------------------------------------
#
# Per AGENTS.md Working tree discipline + ADR-0003 worktree-per-Consumer.
# Default location: $HOME/.config/superpowers/worktrees/<repo>/<branch>
# Overridable via $BOARD_SP_WORKTREE_DIR.

bsp_worktree_path() {
    local repo="${1:?usage: bsp_worktree_path <repo> <branch>}"
    local branch="${2:?usage: bsp_worktree_path <repo> <branch>}"
    local base="${BOARD_SP_WORKTREE_DIR:-${HOME}/.config/superpowers/worktrees}"
    printf '%s/%s/%s\n' "${base}" "${repo}" "${branch}"
}

# bsp_pick_worktree_dir [repo_root] — return BASE worktree dir (not
# per-repo or per-branch). Three-priority resolution per
# docs/architecture/0005-contracts/07-path-conventions.md lines 51-58
# and ADR-0003 § "Path resolution priority":
#
#   1. $BOARD_SP_WORKTREE_DIR (if set + non-empty)
#   2. Project-local <repo_root>/.worktrees/ — only when the directory
#      exists AND `git check-ignore -q .worktrees` (run from repo_root)
#      returns 0, i.e. the path is gitignored. This protects against a
#      stray .worktrees/ accidentally getting committed.
#   3. Default: ${HOME}/.config/superpowers/worktrees
#
# This helper is RICHER than bsp_worktree_path (which honors only env +
# default). bsp_worktree_path stays unchanged so existing callers
# (claim-card.sh) keep working with their current `<repo> <branch>`
# signature.
#
# NOTE: spec line 53 cites this helper as living in scripts/claim-card.sh;
# it actually lives here in scripts/lib/common.sh (where reusable helpers
# live). Spec drift to be reconciled in a later card.

bsp_pick_worktree_dir() {
    local repo_root="${1:-}"

    # Priority 1: env var. MUST be absolute (start with "/"). All
    # priority levels are contractually absolute (priority 2 inherits
    # absoluteness from <repo_root>; priority 3 derives from $HOME).
    # A relative env value would silently break audit-log writes and
    # other path consumers. Per spec lines 51-58 (07-path-conventions.md).
    #
    # Recovery: warn to stderr and fall through to priority 2/3 instead
    # of hard-fail — env var is user-set, a typo shouldn't break the
    # session; the warning preserves visibility.
    if [ -n "${BOARD_SP_WORKTREE_DIR:-}" ]; then
        case "${BOARD_SP_WORKTREE_DIR}" in
            /*)
                printf '%s\n' "${BOARD_SP_WORKTREE_DIR}"
                return 0
                ;;
            *)
                bsp_warn "BOARD_SP_WORKTREE_DIR=${BOARD_SP_WORKTREE_DIR} is not absolute, ignoring; falling through"
                ;;
        esac
    fi

    # Priority 2: project-local <repo_root>/.worktrees/ when it exists
    # AND is gitignored. `git check-ignore -q <path>` exits 0 iff the
    # path matches a gitignore rule; non-zero otherwise (including when
    # not in a git repo). Wrap in `2>/dev/null` to swallow git's stderr
    # when invoked outside a repo.
    if [ -n "${repo_root}" ] && [ -d "${repo_root}/.worktrees" ]; then
        if (cd "${repo_root}" && git check-ignore -q .worktrees) 2>/dev/null; then
            printf '%s\n' "${repo_root}/.worktrees"
            return 0
        fi
    fi

    # Priority 3: default.
    printf '%s\n' "${HOME}/.config/superpowers/worktrees"
}

# --- Card slug helper ----------------------------------------------------
#
# Convert a card title to a branch-safe slug per board-canon's
# branch-naming convention: lowercase, alphanumeric + hyphens, ≤40 chars.

bsp_slugify() {
    local title="${1:?usage: bsp_slugify <title>}"
    printf '%s' "${title}" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -c '[:alnum:]' '-' \
        | tr -s '-' \
        | sed 's/^-//;s/-$//' \
        | cut -c1-40
}
