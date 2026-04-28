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
#
# DUPLICATION NOTICE: this function is duplicated INLINE inside
# hooks/session-start.sh as `normalize_repo_path` because the hook
# is contractually self-contained (per
# docs/architecture/0005-contracts/02-hook-contracts.md
# § "Self-containment" line 297-298). DO NOT deduplicate by sourcing
# common.sh from the hook — a broken lib must never block session
# start. When the rule changes here it MUST also change in the hook.

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

# bsp_primary_repo_root <cwd> — resolve a working directory to its
# PRIMARY repo root (the original `git init`-ed working tree), NOT
# the worktree root the caller may currently sit in. Required because
# `git rev-parse --show-toplevel` returns the WORKTREE root from
# inside a `git worktree`, and the worktree's absolute path normalizes
# (via bsp_normalize_repo_path) to a different `<normalized>` than the
# canonical repo. Any per-repo state lookup keyed by `<normalized>`
# (host-local state.yml, audit-local.jsonl) MUST use this helper —
# otherwise a worktree-launched session sees a fresh "no state.yml
# yet" path and false-emits a bootstrap prompt.
#
# Mechanics: `git rev-parse --git-common-dir` always points at the
# primary repo's `.git/` directory (regardless of worktree vs primary
# linked checkout). dirname of that is the primary working tree.
#
# Args:   <cwd>
# Stdout: absolute primary-repo-root path on success; nothing on failure.
# Returns: 0 on success, 1 if not in a git repo (caller should fall
#   back to whatever the surrounding context calls for).
#
# DUPLICATION NOTICE: this function is duplicated INLINE inside
# hooks/session-start.sh as `primary_repo_root` because the hook is
# contractually self-contained (per 02-hook-contracts.md
# § "Self-containment" lines 295-303). DO NOT deduplicate by sourcing
# common.sh from the hook. When the rule changes here it MUST also
# change in the hook.

bsp_primary_repo_root() {
    local cwd="${1:?usage: bsp_primary_repo_root <cwd>}"
    command -v git >/dev/null 2>&1 || return 1
    local common_dir
    common_dir="$(git -C "${cwd}" rev-parse --git-common-dir 2>/dev/null || true)"
    [ -n "${common_dir}" ] || return 1
    case "${common_dir}" in
        /*) ;;
        *) common_dir="${cwd}/${common_dir}" ;;
    esac
    # `dirname` of the primary `.git/` directory is the primary
    # working tree. Run through `pwd -P` so symlinks (macOS
    # /var → /private/var) don't bite.
    (cd "$(dirname "${common_dir}")" 2>/dev/null && pwd -P) || return 1
}

# bsp_sanitize_reason_line <raw> — sanitize a string for use as the
# value portion of a hook-injected `REASON:` marker. Per
# 02-hook-contracts.md § "Intent-injection markers" lines 213-216:
#   plain ASCII, ≤120 chars, punctuation only `. , ; : - ( )`.
#   No newlines, no JSON, no markup.
#
# Drops any character outside the whitelist (alnum + space +
# `. , ; : - ( )`); truncates to 200 chars (well over the spec's
# 120-char ceiling, leaves headroom).
#
# Note: bsp_sanitize_dep_name's 32-char truncation is too aggressive
# for a sentence-shaped REASON line; this helper exists separately.
#
# DUPLICATION NOTICE: duplicated INLINE inside hooks/session-start.sh
# as `sanitize_reason_line`. Keep the implementations in lockstep
# (per 02-hook-contracts.md § "Self-containment").

bsp_sanitize_reason_line() {
    local raw="${1:-}"
    LC_ALL=C printf '%s' "${raw}" \
        | LC_ALL=C tr -cd 'a-zA-Z0-9 .,;:\-()' \
        | head -c 200
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
#   canonical new path exists. If not, it scans for legacy paths
#   (excluding the new ~/.board-superpowers/repos/ subtree). Two legacy
#   layouts are recognized:
#
#     2-level:  ~/.board-superpowers/<host>/<repo>/audit-local.jsonl
#                  (v0.1.0+ caller signature: <repo> = bare basename)
#     3-level:  ~/.board-superpowers/<host>/<owner>/<name>/audit-local.jsonl
#                  (v0.1.0-minimum caller that passed <repo>=<owner>/<name>;
#                  per issue #27 this layout was previously unmatched and
#                  silently lost during migration)
#
#   Match heuristic (applied uniformly across both layouts):
#     - The legacy path's INNERMOST directory segment (the "<repo>"
#       or "<name>" part — i.e. `basename(dirname(candidate))`) must
#       equal `basename(repo_root)`.
#     - On ambiguity (multiple matches), prefer the one whose
#       owner-position segment matches the owner slug parsed from
#       `git -C <repo_root> remote get-url origin` (when the remote
#       is reachable and parseable). The owner-position segment is:
#         * 2-level: the GRANDPARENT (= `<host>` in that layout's
#           naming, but functionally an owner-style identifier);
#         * 3-level: the PARENT-OF-INNERMOST (= `<owner>`).
#     - Fallback: basename-only match (first one wins).
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
    local repo_root="${1:?usage: bsp_audit_local_write <repo_root> <action_id> <class> <skill> <summary> [<mode>] [--event-uuid <uuid>] [--status <s>] [--retry-count <n>] [--pending-since <ts>]}"
    local action_id="${2:?}"
    local decision="${3:?}"
    local skill="${4:?}"
    local summary="${5:?}"
    # Optional mode field (6th arg). Defaults to legacy 'v1-minimum-degraded'
    # for back-compat with callers (e.g., bootstrap scripts) that haven't
    # been updated to pass an explicit mode. New callers (audit-log-write.sh)
    # pass one of the v0.3.0 enum values: no-db / degraded-db-unavailable /
    # degraded-uv-missing / degraded-venv-create-failed. v0.4.0 adds three
    # more: contract-violation (caller passed non-integer action_id) /
    # bootstrap-pending (outbox row awaiting flush) / audit-dead-letter
    # (pending row exhausted retries / TTL).
    local mode="${6:-v1-minimum-degraded}"
    shift $(( $# < 6 ? $# : 6 ))

    # Optional outbox-shaped fields (#43 AC4 write). Empty by default; only
    # emitted into the jsonl row when set. Caller (audit-log-write.sh in
    # mode=bootstrap-pending branch) passes all four together.
    local event_uuid="" status="" retry_count="" pending_since=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --event-uuid)    event_uuid="$2"; shift 2 ;;
            --status)        status="$2"; shift 2 ;;
            --retry-count)   retry_count="$2"; shift 2 ;;
            --pending-since) pending_since="$2"; shift 2 ;;
            *)
                bsp_warn "bsp_audit_local_write: unknown arg '$1'"
                return 2
                ;;
        esac
    done

    # Per AC3 (#43): explicit mode whitelist. Unknown modes are rejected
    # (return 2) to prevent silent jsonl pollution by typos / outdated
    # callers. The whitelist runs BEFORE any side effects (mkdir / write
    # / log) so a rejected call leaves no trace.
    case "${mode}" in
        no-db|degraded-db-unavailable|degraded-uv-missing|degraded-venv-create-failed|\
v1-minimum-degraded|contract-violation|bootstrap-pending|audit-dead-letter) ;;
        *)
            bsp_warn "bsp_audit_local_write: unknown mode '${mode}' (allowed: no-db, degraded-db-unavailable, degraded-uv-missing, degraded-venv-create-failed, v1-minimum-degraded, contract-violation, bootstrap-pending, audit-dead-letter)"
            return 2
            ;;
    esac

    # Re-derive PATH defensively. Caller may have a stripped PATH; we need
    # dirname / mkdir / python3 / git regardless. Append caller PATH so
    # caller's overrides still win. `local` scopes the override to this
    # function call so consecutive invocations don't keep prepending.
    local PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin${PATH:+:${PATH}}"

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

            # Scan legacy paths. Two layouts are checked (per issue #27):
            #   2-level: <legacy_root>/<host>/<repo>/audit-local.jsonl
            #   3-level: <legacy_root>/<host>/<owner>/<name>/audit-local.jsonl
            # Bash globs return the literal pattern when no matches exist,
            # so each candidate is guarded by `[ -f "${candidate}" ]`.
            # The new layout root (~/.board-superpowers/repos/...) is
            # excluded by checking for a leading "repos/" in the relative
            # path under legacy_root.
            local candidate
            for candidate in \
                "${legacy_root}"/*/*/audit-local.jsonl \
                "${legacy_root}"/*/*/*/audit-local.jsonl
            do
                [ -f "${candidate}" ] || continue

                # Relative directory under legacy_root (drop the prefix +
                # the trailing /audit-local.jsonl). This is the
                # depth-aware key used to classify the layout.
                local rel_dir="${candidate#"${legacy_root}/"}"
                rel_dir="${rel_dir%/audit-local.jsonl}"

                # Skip the new layout root.
                case "${rel_dir}" in
                    repos|repos/*) continue ;;
                esac

                local repo_seg owner_pos_seg
                case "${rel_dir}" in
                    */*/*)
                        # 3-level: host/owner/name. The owner-position
                        # segment is the directory immediately above
                        # the innermost (`name`).
                        repo_seg="${rel_dir##*/}"
                        local _without_name="${rel_dir%/*}"
                        owner_pos_seg="${_without_name##*/}"
                        ;;
                    */*)
                        # 2-level: host/repo. The owner-position segment
                        # is the grandparent (`host` in the legacy naming
                        # but treated as owner-style for matching).
                        repo_seg="${rel_dir##*/}"
                        owner_pos_seg="${rel_dir%/*}"
                        ;;
                    *)
                        # Anything shallower can't host a legacy file.
                        continue
                        ;;
                esac

                # Basename match required.
                [ "${repo_seg}" = "${repo_basename}" ] || continue

                # Strong match: owner-position segment equals owner_slug.
                if [ -n "${owner_slug}" ] && [ "${owner_pos_seg}" = "${owner_slug}" ]; then
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
    BSP_REPO_ROOT="${repo_root}" \
    BSP_ACTION_ID="${action_id}" \
    BSP_DECISION="${decision}" \
    BSP_SKILL="${skill}" \
    BSP_SUMMARY="${summary}" \
    BSP_MODE="${mode}" \
    BSP_PATH="${path}" \
    BSP_EVENT_UUID="${event_uuid}" \
    BSP_STATUS="${status}" \
    BSP_RETRY_COUNT="${retry_count}" \
    BSP_PENDING_SINCE="${pending_since}" \
    python3 -c '
import json, os, time
entry = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "repo_root": os.environ["BSP_REPO_ROOT"],
    "action_id": os.environ["BSP_ACTION_ID"],
    "decision_class": os.environ["BSP_DECISION"],
    "skill": os.environ["BSP_SKILL"],
    "summary": os.environ["BSP_SUMMARY"],
    "mode": os.environ["BSP_MODE"],
}
# Outbox-shaped optional fields (#43 AC4 write). Emit only when set, so
# legacy rows stay byte-identical to their pre-AC4 shape.
if os.environ.get("BSP_EVENT_UUID"):
    entry["event_uuid"] = os.environ["BSP_EVENT_UUID"]
if os.environ.get("BSP_STATUS"):
    entry["status"] = os.environ["BSP_STATUS"]
rc = os.environ.get("BSP_RETRY_COUNT", "")
if rc != "":
    entry["retry_count"] = int(rc)
if os.environ.get("BSP_PENDING_SINCE"):
    entry["pending_since"] = os.environ["BSP_PENDING_SINCE"]
with open(os.environ["BSP_PATH"], "a") as f:
    f.write(json.dumps(entry) + "\n")
'

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

# --- Routing block injection ---------------------------------------------
#
# Injects the canonical routing block from a source file (typically
# skills/using-board-superpowers/references/agentsmd-routing.md) into a
# target file (typically <repo>/AGENTS.md or <repo>/CLAUDE.md) between
# the marker pair:
#
#     <!-- board-superpowers:routing -->
#     ...
#     <!-- /board-superpowers:routing -->
#
# Source-file fence extraction:
#   The source file MUST contain a fence sentinel pair distinct from
#   the target marker pair so a naive find() for the target markers
#   against the source returns nothing:
#
#     <!-- routing-block:start -->
#     ...content the helper extracts and injects...
#     <!-- routing-block:end -->
#
#   Any prose ABOVE the start fence is plugin-maintainer-facing
#   docstring (NOT injected). Any prose BELOW the end fence is
#   maintainer notes (NOT injected).
#
# Source-file normalization (always applied to the fence-bounded
# content before hashing AND before injection — see spec
# docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § 1.5.2 step 4):
#   1. Strip leading UTF-8 BOM (EF BB BF) if present.
#   2. Replace every CRLF / CR with LF.
#   3. Strip leading/trailing newlines so the injected block is tight.
# The post-normalization bytes ARE the canonical routing block and
# are SHA256-hashed to populate state.yml:routing_blocks[].block_hash.
#
# Source-file fatal errors:
#   - Fence sentinels missing → fatal error pointing at the source
#     file path.
#   - Fence-bounded content contains a literal target marker
#     (<!-- board-superpowers:routing --> or its closing form) → fatal
#     error (would otherwise produce nested markers in the target).
#
# Target-file rules:
#   - Absent: create with marker pair wrapping the block content.
#   - Existing, recognized as STUB-REDIRECT (file ≤ 30 lines AND
#     contains a Claude Code @-include line `@<file>.md`): no-op. The
#     file is left byte-identical, NO hash is printed to stdout, exit
#     0. Caller's `[ -n "${hash}" ]` guard at write_state_yml elides
#     the routing_blocks[] entry. Per
#     docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
#     § 1.5.2 step 4 "Stub-redirect target".
#   - Existing, exactly 1 OPEN + exactly 1 CLOSE: replace bytes
#     between markers with normalized block content. Bytes OUTSIDE
#     markers (including BOM at byte 0, original line endings) are
#     preserved verbatim.
#   - Existing, 0 OPEN + 0 CLOSE: append the marker-wrapped block
#     to the file (preserving original ending).
#   - Existing, exactly ONE marker but not both (orphan): emit
#     verbatim error pointing at the actual line number of the
#     present marker, and return exit 5 — DO NOT modify the file.
#   - Existing, 2+ OPEN OR 2+ CLOSE: emit multi-pair error
#     (user copy-pasted the block twice; only the first pair would
#     be updated, second would silently rot) and return exit 5.
#
# Stdout on success: the hex SHA256 hash (no "sha256:" prefix), one
# line — OR empty (no hash) when the target is a stub redirect. Caller
# is expected to prepend "sha256:" when recording into state.yml, and
# to skip the routing_blocks[] entry on empty stdout.
#
# Args: <target_file> <source_file>
# Exit codes:
#   0  success — hash printed to stdout (OR empty for stub-redirect)
#   1  bad args / source file unreadable / source missing fences /
#      source has nested target markers / target write failure
#   5  target has orphan marker (one but not both) OR multiple marker
#      pairs (2+ open or 2+ close)

bsp_inject_routing_block() {
    local target="${1:?usage: bsp_inject_routing_block <target_file> <source_file>}"
    local source="${2:?usage: bsp_inject_routing_block <target_file> <source_file>}"

    if [ ! -f "${source}" ]; then
        bsp_die "bsp_inject_routing_block: source file not found: ${source}"
    fi

    # Stub-redirect early-out. A target file that is short (≤ 30 lines)
    # AND carries a CC @-include line of shape `@<file>.md` is a
    # deliberate redirect (e.g. board-superpowers' own CLAUDE.md →
    # @AGENTS.md). Injecting a routing block would defeat its
    # single-source-of-truth purpose. No write, no stdout, exit 0; the
    # caller's `[ -n "${hash}" ]` guard then elides the routing_blocks
    # entry for this target.
    if [ -f "${target}" ]; then
        local _bsp_line_count
        _bsp_line_count="$(wc -l < "${target}" | tr -d ' ')"
        if [ "${_bsp_line_count}" -le 30 ]; then
            if grep -Eq '^@[A-Za-z0-9./_-]+\.md[[:space:]]*$' "${target}"; then
                bsp_log "skipping routing injection: ${target} is a stub redirect (≤30 lines + @<file>.md)"
                return 0
            fi
        fi
    fi

    bsp_require_cmd python3 "macOS / Linux ship python3 by default"

    # Hand the entire injection to python3: reading binary, BOM
    # stripping, LF normalization, SHA256 over the post-normalization
    # bytes, marker scan, byte-precise replacement, atomic write via
    # mktemp+os.replace are all easier in python than bash. The script
    # writes the hex hash to stdout; bash captures it.
    BSP_TARGET="${target}" BSP_SOURCE="${source}" python3 - <<'PY'
import hashlib
import os
import sys
import tempfile

target = os.environ["BSP_TARGET"]
source = os.environ["BSP_SOURCE"]

OPEN        = b"<!-- board-superpowers:routing -->"
CLOSE       = b"<!-- /board-superpowers:routing -->"
FENCE_OPEN  = b"<!-- routing-block:start -->"
FENCE_CLOSE = b"<!-- routing-block:end -->"
BOM         = b"\xef\xbb\xbf"

def normalize(data: bytes) -> bytes:
    # Strip leading UTF-8 BOM if present.
    if data.startswith(BOM):
        data = data[len(BOM):]
    # Normalize CRLF / lone CR to LF.
    data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return data

# Read source bytes.
try:
    with open(source, "rb") as f:
        raw_source = f.read()
except OSError as e:
    sys.stderr.write(f"[bsp ERROR] cannot read source: {e}\n")
    sys.exit(1)

# Locate the fence sentinels in the source. Both must be present and
# must appear on their own lines (start of line + end of line) so that
# documentation prose mentioning the sentinel keywords (e.g. inside
# backticks for explanatory purposes elsewhere in the source file)
# does not accidentally satisfy the find. The "own line" rule is:
#   - preceded by a newline OR start-of-file
#   - followed by a newline OR end-of-file (with optional trailing
#     whitespace before the newline)
# We implement this by scanning line-by-line over normalized bytes.
def find_standalone(buf: bytes, sentinel: bytes) -> int:
    """Return absolute byte offset of `sentinel` on a line by itself,
    or -1 if no such occurrence exists. Trailing whitespace on the
    line is tolerated. Raw `buf` is expected to use LF line endings —
    callers may normalize CRLF first if needed.
    """
    pos = 0
    n = len(buf)
    while pos < n:
        nl = buf.find(b"\n", pos)
        line_end = nl if nl != -1 else n
        line = buf[pos:line_end].rstrip(b" \t\r")
        if line == sentinel:
            return pos
        if nl == -1:
            return -1
        pos = nl + 1
    return -1

# Normalize source line endings BEFORE the fence scan so a CRLF
# source still matches the fence sentinels on standalone-line basis.
normalized_source = raw_source.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

fence_open_idx  = find_standalone(normalized_source, FENCE_OPEN)
fence_close_idx = find_standalone(normalized_source, FENCE_CLOSE)

if fence_open_idx == -1 or fence_close_idx == -1:
    sys.stderr.write(
        "ERROR: F-B2 step 4 (routing block injection) cannot proceed.\n"
        "\n"
        f"Source-of-truth file at {source}\n"
        "missing fence markers; expected\n"
        f"  `{FENCE_OPEN.decode('utf-8')}` and\n"
        f"  `{FENCE_CLOSE.decode('utf-8')}`\n"
        "to bracket the routing block content (each on its own line).\n"
        "The docstring header outside the fence is plugin-maintainer\n"
        "documentation and is NOT injected; only fence-bounded bytes are.\n"
        "\n"
        "Fix the source file, then re-run F-B2.\n"
    )
    sys.exit(1)

if fence_close_idx < fence_open_idx:
    sys.stderr.write(
        "ERROR: F-B2 step 4 (routing block injection) cannot proceed.\n"
        "\n"
        f"Source-of-truth file at {source}\n"
        "has fence markers in the wrong order: closing fence\n"
        f"  `{FENCE_CLOSE.decode('utf-8')}`\n"
        "appears BEFORE opening fence\n"
        f"  `{FENCE_OPEN.decode('utf-8')}`.\n"
        "\n"
        "Fix the source file, then re-run F-B2.\n"
    )
    sys.exit(1)

# Extract bytes BETWEEN the fences (exclusive of fence markers).
# Use the normalized source so the slice indices match the bytes we
# analyzed. The fenced region runs from the byte after the opening
# fence's newline to the byte before the closing fence.
fence_open_line_end = normalized_source.find(b"\n", fence_open_idx)
if fence_open_line_end == -1:
    fence_open_line_end = fence_open_idx + len(FENCE_OPEN)
fenced = normalized_source[fence_open_line_end + 1 : fence_close_idx]

# Normalize: strip leading BOM (defensive), strip leading/trailing
# newlines so the injected block is tight. Source already had CRLF→LF
# normalization applied above before the fence scan.
block_content = fenced
if block_content.startswith(BOM):
    block_content = block_content[len(BOM):]
block_content = block_content.strip(b"\n")

# Sanity: fence-bounded content MUST NOT contain literal target
# markers — that would produce nested markers in the target file.
def find_line(buf: bytes, needle: bytes) -> int:
    """Return 1-based line number of needle in buf, or -1 if absent."""
    idx = buf.find(needle)
    if idx == -1:
        return -1
    return buf[:idx].count(b"\n") + 1

target_open_in_src  = find_line(block_content, OPEN)
target_close_in_src = find_line(block_content, CLOSE)
if target_open_in_src != -1 or target_close_in_src != -1:
    if target_open_in_src != -1:
        bad_marker = OPEN.decode("utf-8")
        bad_line   = target_open_in_src
    else:
        bad_marker = CLOSE.decode("utf-8")
        bad_line   = target_close_in_src
    sys.stderr.write(
        "ERROR: F-B2 step 4 (routing block injection) cannot proceed.\n"
        "\n"
        f"Source-of-truth file at {source}\n"
        f"has literal target-file marker `{bad_marker}`\n"
        f"inside the fence at line {bad_line} of the fenced content.\n"
        "Injecting it would produce nested markers in the target file.\n"
        "\n"
        "Remove the literal target marker from inside the fence, then\n"
        "re-run F-B2. The fence sentinels (routing-block:start /\n"
        "routing-block:end) are the source-side delimiters; the target\n"
        "marker pair (board-superpowers:routing) wraps injected content\n"
        "in the consumer repo's AGENTS.md / CLAUDE.md and must not\n"
        "appear inside the source fence.\n"
    )
    sys.exit(1)

# block_content is the canonical routing block bytes. Hash it as-is
# (no trailing newline), then assemble the bytes that go between
# target markers (with exactly one trailing newline so the closing
# marker sits on its own line).
block_hash = hashlib.sha256(block_content).hexdigest()
between = block_content + b"\n"

def atomic_write(path, payload):
    parent = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(prefix=".bsp-inject-", dir=parent)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(payload)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

if not os.path.exists(target):
    payload = OPEN + b"\n" + between + CLOSE + b"\n"
    try:
        atomic_write(target, payload)
    except OSError as e:
        sys.stderr.write(f"[bsp ERROR] cannot write target: {e}\n")
        sys.exit(1)
    print(block_hash)
    sys.exit(0)

# Existing target — read, scan, classify.
try:
    with open(target, "rb") as f:
        original = f.read()
except OSError as e:
    sys.stderr.write(f"[bsp ERROR] cannot read target: {e}\n")
    sys.exit(1)

# Preserve a leading BOM at byte 0 of the target file. It's NOT part
# of the marker scan and NOT part of the hashed region. The scan
# happens against `body`; final write reattaches the BOM unchanged.
bom_prefix = b""
body = original
if body.startswith(BOM):
    bom_prefix = BOM
    body = body[len(BOM):]

# Count occurrences of OPEN and CLOSE in body (unique non-overlapping).
def count_occurrences(buf: bytes, needle: bytes) -> int:
    count = 0
    start = 0
    n = len(needle)
    while True:
        idx = buf.find(needle, start)
        if idx == -1:
            return count
        count += 1
        start = idx + n

open_count  = count_occurrences(body, OPEN)
close_count = count_occurrences(body, CLOSE)

def line_of(buf: bytes, idx_no_bom: int) -> int:
    """1-based line number, accounting for an optional preserved BOM."""
    if idx_no_bom == -1:
        return -1
    idx = idx_no_bom + len(bom_prefix)
    return buf[:idx].count(b"\n") + 1

# Multi-pair detection: if either marker appears more than once, the
# target is in an ambiguous state (e.g. user copy-pasted the routing
# block twice). Refuse to silently update only the first occurrence.
if open_count > 1 or close_count > 1:
    sys.stderr.write(
        "ERROR: F-B2 step 4 (routing block injection) cannot proceed.\n"
        "\n"
        f"Target file:    {target}\n"
        f"Detected:       {open_count} opening markers and {close_count} closing markers\n"
        f"                in {target}. Expected exactly 0 or 1 of each.\n"
        "\n"
        "This indicates either:\n"
        "  (1) the routing block was copy-pasted into the target multiple\n"
        "      times — only the first pair would be updated, leaving the\n"
        "      others to silently drift\n"
        "  (2) hand-edited duplication\n"
        "  (3) a merge artifact left two stale blocks\n"
        "\n"
        "Recovery options (pick one, then re-run F-B2):\n"
        "  (a) Strip the duplicate marker pairs — keep at most ONE\n"
        "      `<!-- board-superpowers:routing -->` /\n"
        "      `<!-- /board-superpowers:routing -->` block.\n"
        "  (b) Delete the entire file — F-B2 will re-create it with just\n"
        "      the routing block. Use only if AGENTS.md content was\n"
        "      minimal.\n"
        "  (c) Strip ALL marker pairs — F-B2 will then treat the file as\n"
        "      case-C (no markers, will append a fresh block).\n"
        "\n"
        "F-B2 has NOT written state.yml. Repo state remains pre-bootstrap.\n"
        "Re-run after fixing.\n"
    )
    sys.exit(5)

open_idx  = body.find(OPEN)  if open_count  == 1 else -1
close_idx = body.find(CLOSE) if close_count == 1 else -1

# Orphan detection: exactly one of OPEN / CLOSE present, the other
# absent.
if (open_count == 1) ^ (close_count == 1):
    if open_count == 1:
        kind            = "opening"
        present_marker  = OPEN.decode("utf-8")
        other_kind      = "closing"
        absent_marker   = CLOSE.decode("utf-8")
        present_line    = line_of(original, open_idx)
    else:
        kind            = "closing"
        present_marker  = CLOSE.decode("utf-8")
        other_kind      = "opening"
        absent_marker   = OPEN.decode("utf-8")
        present_line    = line_of(original, close_idx)

    sys.stderr.write(
        "ERROR: F-B2 step 4 (routing block injection) cannot proceed.\n"
        "\n"
        f"Target file:    {target}\n"
        f"Detected:       {kind} marker '{present_marker}' present at line {present_line},\n"
        f"                but matching {other_kind} marker '{absent_marker}'\n"
        "                is absent.\n"
        "\n"
        "This indicates either:\n"
        "  (1) a partial or corrupted previous injection\n"
        "  (2) hand-edited markers (one removed, one left)\n"
        "  (3) a third party stripped one marker\n"
        "\n"
        "Recovery options (pick one, then re-run F-B2):\n"
        "  (a) Restore both markers — add the missing marker AT or AFTER the\n"
        "      content you want preserved as plugin-managed.\n"
        "  (b) Delete the entire file — F-B2 will re-create it with just the\n"
        "      routing block. Use only if AGENTS.md content was minimal.\n"
        "  (c) Strip the orphan marker — manually remove the lone marker.\n"
        "      F-B2 will then treat the file as case-C (no markers, will\n"
        "      append fresh block).\n"
        "\n"
        "F-B2 has NOT written state.yml. Repo state remains pre-bootstrap.\n"
        "Re-run after fixing.\n"
    )
    sys.exit(5)

if open_count == 0 and close_count == 0:
    # Append marker-wrapped block. Preserve everything before; tack
    # on a leading newline if the file doesn't already end with one.
    suffix = b""
    if body and not body.endswith(b"\n"):
        suffix += b"\n"
    suffix += b"\n"  # blank line separator between existing content + marker
    suffix += OPEN + b"\n" + between + CLOSE + b"\n"
    payload = bom_prefix + body + suffix
    try:
        atomic_write(target, payload)
    except OSError as e:
        sys.stderr.write(f"[bsp ERROR] cannot write target: {e}\n")
        sys.exit(1)
    print(block_hash)
    sys.exit(0)

# Both markers present (exactly one of each) — replace bytes between
# them.
if open_idx > close_idx:
    sys.stderr.write(
        "ERROR: F-B2 step 4 (routing block injection) cannot proceed.\n"
        f"Target file:    {target}\n"
        "Detected:       closing marker appears BEFORE opening marker.\n"
        "                Markers are reversed or the file is corrupted.\n"
        "\n"
        "Fix the file manually (markers must appear in the order\n"
        "open-then-close), then re-run F-B2.\n"
        "\n"
        "F-B2 has NOT written state.yml. Repo state remains pre-bootstrap.\n"
    )
    sys.exit(5)

# Inclusive end position: keep everything through CLOSE marker bytes.
close_end = close_idx + len(CLOSE)

before = body[: open_idx]
after  = body[close_end :]

# Strip the immediate newline AFTER the OPEN marker we are removing
# (start of region to replace) and the immediate newline BEFORE the
# CLOSE marker we are keeping start-of (end of region) is implicit in
# how we slice; we replace bytes between OPEN and CLOSE wholesale.
new_middle = OPEN + b"\n" + between + CLOSE

# Ensure the file ends with a single trailing newline. Don't double
# up if `after` already starts with content, just preserve.
payload = bom_prefix + before + new_middle + after
# Guarantee single trailing newline at EOF.
if not payload.endswith(b"\n"):
    payload += b"\n"
else:
    # Trim accidental trailing-newline doubling at EOF only.
    while payload.endswith(b"\n\n"):
        payload = payload[:-1]

try:
    atomic_write(target, payload)
except OSError as e:
    sys.stderr.write(f"[bsp ERROR] cannot write target: {e}\n")
    sys.exit(1)
print(block_hash)
sys.exit(0)
PY
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

# --- venv self-healing ---------------------------------------------------
#
# Ensure the per-repo venv at <repo>/.board-superpowers/.venv/ exists and
# return its python3 absolute path on stdout. Self-healing: if missing,
# copies plugin-shipped pyproject.toml + uv.lock and runs `uv sync`.
#
# Args:   <repo_root>
# Stdout: absolute path to venv-python on success
# Returns:
#   0 - venv ready (path on stdout)
#   5 - uv missing on PATH (architect must run bootstrap-host.sh)
#   6 - plugin template corruption (templates/pyproject.toml absent)
#   7 - uv sync failed (network / proxy / lock conflict / disk full)

bsp_ensure_venv() {
    local repo_root="${1:?usage: bsp_ensure_venv <repo_root>}"
    local venv_python="${repo_root}/.board-superpowers/.venv/bin/python3"

    if [ -x "${venv_python}" ]; then
        printf '%s\n' "${venv_python}"
        return 0
    fi

    command -v uv >/dev/null 2>&1 || return 5

    local plugin_root
    plugin_root="$(bsp_plugin_root)"
    local template_pyproject="${plugin_root}/scripts/templates/pyproject.toml"
    local template_lock="${plugin_root}/scripts/templates/uv.lock"
    [ -f "${template_pyproject}" ] || return 6

    # Acquire mkdir-based lock to serialize parallel callers against the
    # same repo (e.g., two SKILL invocations triggering venv create
    # simultaneously). mkdir is atomic on POSIX. Best-effort 60s timeout;
    # on timeout treat as create-fail so caller falls back to
    # jsonl mode=degraded-venv-create-failed.
    local lockdir="${repo_root}/.board-superpowers/.venv-create.lock"
    mkdir -p "${repo_root}/.board-superpowers" 2>/dev/null || true
    local elapsed=0
    while ! mkdir "${lockdir}" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ "${elapsed}" -ge 60 ]; then
            return 7
        fi
    done

    # Re-check after acquiring lock — another caller may have already
    # created the venv between our first check and lock acquisition.
    if [ -x "${venv_python}" ]; then
        rmdir "${lockdir}" 2>/dev/null || true
        printf '%s\n' "${venv_python}"
        return 0
    fi

    local target_pyproject="${repo_root}/.board-superpowers/pyproject.toml"
    if [ ! -f "${target_pyproject}" ]; then
        cp "${template_pyproject}" "${target_pyproject}"
        # uv.lock is best-effort — its absence is not fatal (uv sync can
        # regenerate). Plugin should always ship it though.
        cp "${template_lock}" "${repo_root}/.board-superpowers/uv.lock" 2>/dev/null || true
    fi

    if (cd "${repo_root}/.board-superpowers/" && uv sync 2>&1) >&2; then
        rmdir "${lockdir}" 2>/dev/null || true
        printf '%s\n' "${venv_python}"
        return 0
    fi
    rmdir "${lockdir}" 2>/dev/null || true
    return 7
}

# --- audit DB URL resolution --------------------------------------------
#
# Per docs/architecture/0005-contracts/03-config-schemas.md § credentials.yml:
#   1. BOARD_SP_AUDIT_DB_URL env var (highest precedence)
#   2. ~/.board-superpowers/credentials.yml:audit_db_url
#   3. (none) → caller falls back to jsonl mode=no-db
#
# Stdout: the URL on success; empty string when neither source has a value.
# Returns: 0 always (absence is a legitimate state, not an error).

bsp_resolve_audit_db_url() {
    if [ -n "${BOARD_SP_AUDIT_DB_URL:-}" ]; then
        printf '%s\n' "${BOARD_SP_AUDIT_DB_URL}"
        return 0
    fi
    local creds="${HOME}/.board-superpowers/credentials.yml"
    if [ -f "${creds}" ]; then
        # yaml_get is defined in bootstrap-host.sh + bootstrap-project.sh.
        # Inline the same grep+sed shape here to avoid a cross-file dep.
        local url
        url="$(grep -E '^audit_db_url[[:space:]]*:' "${creds}" 2>/dev/null \
                | head -n1 \
                | sed -E 's/^audit_db_url[[:space:]]*:[[:space:]]*//; s/^"//; s/"$//')"
        if [ -n "${url}" ]; then
            printf '%s\n' "${url}"
            return 0
        fi
    fi
    return 0
}

# --- autonomy class resolution ------------------------------------------
#
# Resolve the effective A/R/N class for an action_id by layering:
#   1. ADR-0006 §3 matrix defaults (hardcoded below)
#   2. ~/.board-superpowers/overrides.yml autonomy_overrides[]   (user layer)
#   3. <repo>/.board-superpowers/config.local.yml autonomy_overrides[]  (project layer; wins)
#
# Args:   <action_id> [<repo_root>]
# Stdout: A | R | N
# Returns: 0 on success, non-zero on usage error
#
# Implementation: invokes venv-python with PyYAML (per design doc § 6.1).
# Falls back to ADR-0006 default when venv unavailable.

bsp_resolve_autonomy_class() {
    local action_id="${1:?usage: bsp_resolve_autonomy_class <action_id> [<repo_root>]}"
    local repo_root="${2:-${PWD}}"

    # ADR-0006 §3 matrix defaults (Producer rows 1-14 + Consumer 100-111).
    # 'A' default rows: 1, 2, 5, 9, 11, 13, 14, 100, 102, 104, 105, 106, 107, 108, 109, 110, 111
    # 'R' default rows: 3, 4, 6, 7, 8, 10, 12, 101, 103
    local default_class
    case "${action_id}" in
        1|2|5|9|11|13|14|100|102|104|105|106|107|108|109|110|111) default_class="A" ;;
        3|4|6|7|8|10|12|101|103) default_class="R" ;;
        *) printf '%s\n' "A"; return 0 ;;  # unknown rows fall through to A per ADR-0006 triage rule step 5
    esac

    # Try venv-python for yaml-aware override merge. Falls back to default.
    local venv_python
    if venv_python="$(bsp_ensure_venv "${repo_root}" 2>/dev/null)"; then
        local override_class
        override_class="$(BSP_REPO_ROOT="${repo_root}" \
                          BSP_ACTION_ID="${action_id}" \
                          "${venv_python}" - <<'PY'
import os, sys
try:
    import yaml
except ImportError:
    sys.stderr.write(
        '[bsp WARN] PyYAML missing in venv; autonomy_overrides not applied '
        '(falling back to ADR-0006 matrix default). Run uv sync in '
        '<repo>/.board-superpowers/ to install.\n'
    )
    sys.exit(0)

repo_root = os.environ['BSP_REPO_ROOT']
action_id = int(os.environ['BSP_ACTION_ID'])
home = os.path.expanduser('~')

def load_overrides(path):
    if not os.path.isfile(path):
        return []
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
        return data.get('autonomy_overrides', []) or []
    except Exception:
        return []

user_overrides = load_overrides(os.path.join(home, '.board-superpowers', 'overrides.yml'))
project_overrides = load_overrides(os.path.join(repo_root, '.board-superpowers', 'config.local.yml'))

# Project layer wins on conflict per spec 03 § Merge semantics. Validate
# class enum BEFORE assignment so a malformed entry (missing or bad
# `class`) does NOT silently overwrite a valid earlier entry.
VALID_CLASSES = ('A', 'R', 'N')
chosen = None
for layer_name, entries in (('user', user_overrides), ('project', project_overrides)):
    for entry in entries:
        if entry.get('action_id') != action_id:
            continue
        klass = entry.get('class')
        if klass in VALID_CLASSES:
            chosen = klass
        else:
            sys.stderr.write(
                f'[bsp WARN] {layer_name}-layer override entry for '
                f'action_id={action_id} has invalid class {klass!r}; ignoring.\n'
            )

if chosen in VALID_CLASSES:
    print(chosen)
PY
)"
        if [ -n "${override_class}" ]; then
            printf '%s\n' "${override_class}"
            return 0
        fi
    fi

    printf '%s\n' "${default_class}"
    return 0
}

# --- audit-health summary (AC5 — bootstrap末尾) ---------------------------
#
# Emit one [bsp] log line summarizing how many bootstrap audit rows
# (action_id 200..208) reached the BYO RDBMS during the just-closed
# bootstrap window.
#
# Per design.md §3.5 (Codex blocker fix): the original AC5 plan
# computed TOTAL by counting jsonl rows, but Task 6+ flush
# deletes/transitions rows after success → TOTAL=0 in the normal path
# → "9 of 9" never printed. The pragmatic fix anchors the query on a
# bootstrap-session start timestamp recorded by the caller before any
# audit emit happens, then counts DB rows in the [start_ts, now]
# window with action_id BETWEEN 200 AND 208. Prior bootstraps' rows
# are filtered out by the timestamp predicate.
#
# Args:
#   $1 — bootstrap_start_ts (ISO 8601 UTC; rows with timestamp >= this
#        are counted). Required.
#
# Side effects:
#   - bsp_log line on stderr (no stdout output by design — caller
#     should not depend on parse-able output).
#
# Behavior matrix:
#   - audit_db_url unset             → "0 of 9 ... no DB configured (jsonl only)"
#   - venv unavailable               → "9 bootstrap rows; venv unavailable (cannot query DB; check jsonl)"
#   - DB query returns N (>=1)       → "${N} of 9 bootstrap audit rows landed in DB; $((9-N)) remain in jsonl"
#   - DB query returns 0             → "0 of 0 bootstrap audit rows since <start_ts> (no rows in window; nothing to report)"
#     (distinguishes "all failed" from "nothing happened in this window")
#
# Returns: 0 always (summary is observational; caller never aborts on it).

bsp_audit_health_summary() {
    local start_ts="${1:-}"
    local TOTAL=9  # bootstrap action_id range 200..208 (9 inclusive rows)
    local audit_db_url
    audit_db_url="$(bsp_resolve_audit_db_url 2>/dev/null || true)"

    if [ -z "${audit_db_url}" ]; then
        bsp_log "audit health: 0 of ${TOTAL} bootstrap audit rows landed in DB; no DB configured (jsonl only)"
        return 0
    fi

    local repo_root venv_python
    repo_root="$(bsp_primary_repo_root "${PWD}" 2>/dev/null || echo "${PWD}")"
    venv_python="$(bsp_ensure_venv "${repo_root}" 2>/dev/null || true)"
    if [ -z "${venv_python}" ]; then
        bsp_log "audit health: ${TOTAL} bootstrap rows; venv unavailable (cannot query DB; check jsonl)"
        return 0
    fi

    local db_rows
    db_rows="$(BSP_AUDIT_DB_URL="${audit_db_url}" \
               BSP_START_TS="${start_ts}" \
               "${venv_python}" - <<'PY' 2>/dev/null || echo 0
import os
from urllib.parse import urlparse

url_str = os.environ.get('BSP_AUDIT_DB_URL', '')
start_ts = os.environ.get('BSP_START_TS', '')
url = urlparse(url_str)
scheme = url.scheme
try:
    if scheme in ('sqlite', 'sqlite3'):
        import sqlite3
        # Strip scheme://; sqlite URLs use 4-slash absolute path
        # convention (sqlite:////abs/path/db.sqlite). After scheme
        # strip we get either /abs/path or //abs/path; normalize.
        db_path = url_str.split('://', 1)[1] if '://' in url_str else url_str
        if not db_path.startswith('/'):
            db_path = '/' + db_path.lstrip('/')
        conn = sqlite3.connect(db_path)
        n = conn.execute(
            "SELECT COUNT(*) FROM audit_log "
            "WHERE action_id BETWEEN 200 AND 208 AND timestamp >= ?",
            (start_ts,)
        ).fetchone()[0]
        print(int(n))
        conn.close()
    elif scheme in ('postgresql', 'postgres'):
        import psycopg2
        conn = psycopg2.connect(url_str)
        with conn.cursor() as c:
            c.execute(
                "SELECT COUNT(*) FROM audit_log "
                "WHERE action_id BETWEEN 200 AND 208 AND timestamp >= %s",
                (start_ts,)
            )
            print(int(c.fetchone()[0]))
        conn.close()
    elif scheme in ('mysql', 'mysql+pymysql'):
        import pymysql
        canonical = url_str.replace('mysql+pymysql://', 'mysql://')
        u = urlparse(canonical)
        conn = pymysql.connect(
            host=u.hostname, port=u.port or 3306,
            user=u.username, password=u.password,
            database=u.path.lstrip('/'),
        )
        with conn.cursor() as c:
            c.execute(
                "SELECT COUNT(*) FROM audit_log "
                "WHERE action_id BETWEEN 200 AND 208 AND timestamp >= %s",
                (start_ts,)
            )
            print(int(c.fetchone()[0]))
        conn.close()
    else:
        print(0)
except Exception:
    print(0)
PY
)"

    case "${db_rows}" in
        ''|*[!0-9]*) db_rows=0 ;;
    esac

    if [ "${db_rows}" = 0 ]; then
        # Distinguish "no rows in window" (start_ts after all rows;
        # nothing happened) from "all failed". With anchored start_ts
        # zero rows usually means nothing happened in this window;
        # emit a quieter summary so the caller doesn't read it as
        # "all 9 lost".
        bsp_log "audit health: 0 of 0 bootstrap audit rows since ${start_ts} (no rows in window; nothing to report)"
        return 0
    fi

    local remaining=$((TOTAL - db_rows))
    if [ "${remaining}" -lt 0 ]; then
        # Defensive: more than 9 rows in range is unexpected (would
        # mean another concurrent bootstrap), but we still emit a
        # clean line.
        remaining=0
    fi
    bsp_log "audit health: ${db_rows} of ${TOTAL} bootstrap audit rows landed in DB; ${remaining} remain in jsonl"
    return 0
}
