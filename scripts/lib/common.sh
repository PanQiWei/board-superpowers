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

# --- Host-local + per-repo state paths ----------------------------------
#
# Per AGENTS.md Architecture-at-a-glance and ADR-0006 path conventions:
#   ~/.board-superpowers/<host>/<repo>/state.yml         (host-local, not in git)
#   <repo>/.board-superpowers/config.yml                  (per-repo, in git)
#   ~/.board-superpowers/<host>/<repo>/audit-local.jsonl  (degraded audit)
#
# For v1-minimum the (host, repo) tuple is derived from `gh repo view`.

bsp_host_state_dir() {
    local host="${1:?usage: bsp_host_state_dir <host> <repo>}"
    local repo="${2:?usage: bsp_host_state_dir <host> <repo>}"
    printf '%s/.board-superpowers/%s/%s\n' "${HOME}" "${host}" "${repo}"
}

bsp_repo_config_path() {
    local repo_root="${1:?usage: bsp_repo_config_path <repo-root>}"
    printf '%s/.board-superpowers/config.yml\n' "${repo_root}"
}

bsp_audit_local_path() {
    local host="${1:?usage: bsp_audit_local_path <host> <repo>}"
    local repo="${2:?usage: bsp_audit_local_path <host> <repo>}"
    local dir
    dir="$(bsp_host_state_dir "${host}" "${repo}")"
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
# Appends one JSON line per action to the host-local audit-local.jsonl.
#
# Args: <host> <repo> <action_id> <decision_class> <skill> <summary>
#
# decision_class ∈ {A, R, N} (per ADR-0006 D-AUTONOMY-1).
# action_id catalog lives inline in each v1-minimum molecular skill.

bsp_audit_local_write() {
    local host="${1:?usage: bsp_audit_local_write <host> <repo> <action_id> <class> <skill> <summary>}"
    local repo="${2:?}"
    local action_id="${3:?}"
    local decision="${4:?}"
    local skill="${5:?}"
    local summary="${6:?}"

    local path
    path="$(bsp_audit_local_path "${host}" "${repo}")"
    mkdir -p "$(dirname "${path}")"

    bsp_require_cmd python3
    python3 -c "
import json, sys, time
entry = {
    'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'host': sys.argv[1],
    'repo': sys.argv[2],
    'action_id': sys.argv[3],
    'decision_class': sys.argv[4],
    'skill': sys.argv[5],
    'summary': sys.argv[6],
    'mode': 'v1-minimum-degraded',
}
with open(sys.argv[7], 'a') as f:
    f.write(json.dumps(entry) + '\n')
" "${host}" "${repo}" "${action_id}" "${decision}" "${skill}" "${summary}" "${path}"

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
