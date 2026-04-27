#!/usr/bin/env bash
# scripts/check-deps.sh — verify required CLI dependencies + routing block
# for board-superpowers.
#
# Called by:
#   - hooks/session-start.sh (every session, fast-path verification)
#   - using-board-superpowers SKILL.md (fallback when hook output is missing)
#
# SELF-CONTAINED: this script MUST NOT source scripts/lib/common.sh, per
# docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § "Self-contained scripts at the dep-check layer". A broken lib must
# never break dependency detection. The same self-containment rule applies
# to hooks/session-start.sh.
#
# Inputs (per spec § 1.5.0):
#   $CLAUDE_PROJECT_DIR — project root for the routing-block check;
#                         defaults to $PWD if unset.
#   $HOME               — used implicitly by called tools.
#   $1                  — optional `--machine` flag (default = human mode).
#
# --- Modes --------------------------------------------------------------
#
# HUMAN MODE (default; bash check-deps.sh):
#   stdout — human-readable status banner suitable for hookSpecificOutput
#            additionalContext when invoked from session-start.sh.
#   exit 0 — all dependencies present + routing block present (or no
#            AGENTS.md / CLAUDE.md exists, in which case the routing
#            check is skipped — the asymmetric "no file is fine, file
#            without marker is not" rule keeps the dep check silent in
#            repos that don't use these files at all). Also reached
#            when $CLAUDE_PROJECT_DIR resolves to a non-git directory.
#   exit 2 — required binary is NOT installed, OR AGENTS.md / CLAUDE.md
#            exists but lacks the "## board-superpowers session routing"
#            heading.
#   exit 3 — required binary IS installed but a runtime invariant fails
#            (e.g., `gh` exists but lacks the `project` / `read:project`
#            scope, or `gh` is not authenticated).
#
# MACHINE MODE (bash check-deps.sh --machine):
#   exit 0 — ALWAYS. The output channel signals state, not the exit code,
#            per docs/architecture/0005-contracts/01-script-contracts.md
#            line 106.
#   stdout — empty when everything is OK (callers test `-z`); otherwise
#            exactly three LF-terminated lines:
#                MISSING=<csv>
#                ROUTING_INJECTED=<yes|no>
#                PROJECT=<absolute path>
#
#   The keys MISSING / ROUTING_INJECTED / PROJECT are protocol — renaming
#   any of them breaks hooks/session-start.sh's parser (per AGENTS.md
#   change-impact matrix entry "Hook intent-injection marker grammar").
#
#   MISSING bucketing rule (per spec line 93 + Slice 2 contract):
#     - tool absent from PATH (`command -v X` fails) → token = bare name
#     - tool present but failing a runtime check (e.g., gh lacking
#       project scope) → also token = bare name. The hook side sees
#       `gh` flagged either way; the install-vs-reauth distinction is
#       not surfaced through machine mode (human mode keeps it via
#       the exit-code split).
#
#   ROUTING_INJECTED semantics (asymmetric skip, mirrors human-mode logic):
#     yes — at least one of AGENTS.md / CLAUDE.md carries the heading
#     yes — neither file exists (silent-skip, same rule as human mode)
#     yes — $CLAUDE_PROJECT_DIR is not inside a git repo (skip semantics)
#     no  — at least one file exists but neither carries the heading
#
#   PROJECT semantics: absolute path of $CLAUDE_PROJECT_DIR; resolved to
#   the git toplevel when inside a repo, otherwise the directory as-is.
#
#   "Wrong" predicate (when machine mode emits the three lines):
#     MISSING is non-empty OR ROUTING_INJECTED is `no`. Otherwise the
#     stdout is empty so `[ -z "$output" ]` works in callers.

set -euo pipefail

# --- Arg parsing --------------------------------------------------------

MACHINE_MODE=0
case "${1:-}" in
    --machine)
        MACHINE_MODE=1
        ;;
    "")
        # No arg → human mode (default).
        ;;
    *)
        printf 'check-deps.sh: unknown argument: %s (only --machine is supported)\n' "$1" >&2
        exit 64  # EX_USAGE
        ;;
esac

# --- State accumulators -------------------------------------------------
# Both modes collect the same state; the bottom of the script picks an
# emitter based on $MACHINE_MODE.
#
# Counters drive human-mode exit code resolution:
#   MISSING_DEPS or MISSING_ROUTING → exit 2
#   else RUNTIME_FAILURES           → exit 3
#   else                            → exit 0
#
# MISSING_TOOLS collects the bare tool names (gh / python3 / git) that
# are unusable, in stable detection order. Used by machine mode to build
# the MISSING= csv. A tool failing a runtime check is recorded here too,
# bucketed under the same bare name as a PATH miss.

declare -i MISSING_DEPS=0
declare -i MISSING_ROUTING=0
declare -i RUNTIME_FAILURES=0
MISSING_TOOLS=()

# ROUTING_STATE: yes/no after check_routing_block runs. Default `yes`
# (the silent-skip default — flipped to `no` only when a file exists
# without the heading).
ROUTING_STATE="yes"

# PROJECT_PATH: absolute path of $CLAUDE_PROJECT_DIR, resolved to git
# toplevel when applicable. Computed once, shared by both modes.
PROJECT_PATH=""

# Append a tool name to MISSING_TOOLS if not already present.
record_missing_tool() {
    local tool="${1:?}"
    local existing
    for existing in "${MISSING_TOOLS[@]:-}"; do
        if [ "${existing}" = "${tool}" ]; then
            return
        fi
    done
    MISSING_TOOLS+=("${tool}")
}

# --- Checks -------------------------------------------------------------

check_cmd() {
    local cmd="${1:?}"
    local hint="${2:-}"
    if command -v "${cmd}" >/dev/null 2>&1; then
        if [ "${MACHINE_MODE}" -eq 0 ]; then
            printf '  ✓ %s\n' "${cmd}"
        fi
    else
        if [ "${MACHINE_MODE}" -eq 0 ]; then
            printf '  ✗ %s — MISSING (%s)\n' "${cmd}" "${hint}"
        fi
        MISSING_DEPS=$((MISSING_DEPS + 1))
        record_missing_tool "${cmd}"
    fi
}

check_gh_scope() {
    if ! command -v gh >/dev/null 2>&1; then
        return  # Already counted by check_cmd above as a missing dep.
    fi
    # gh auth status emits scopes on stderr; grep them.
    if gh auth status 2>&1 | grep -qE "'(read:project|project)'"; then
        if [ "${MACHINE_MODE}" -eq 0 ]; then
            printf '  ✓ gh auth has project scope\n'
        fi
    else
        if [ "${MACHINE_MODE}" -eq 0 ]; then
            printf '  ✗ gh auth missing project scope — run: gh auth refresh -s project,read:project\n'
        fi
        RUNTIME_FAILURES=$((RUNTIME_FAILURES + 1))
        # Bucket under the bare tool name so the hook sees `gh` flagged
        # whether the failure is install-time or runtime-time.
        record_missing_tool "gh"
    fi
}

# Absolutize a path. Existing dir → physical absolute (resolves
# symlinks via `pwd -P`). Non-existent or non-dir → cwd-joined when
# relative, kept as-is when already absolute. Output ALWAYS starts
# with `/` so the spec's `PROJECT=<absolute path>` invariant
# (01-script-contracts.md line 93) holds in every branch.
absolutize() {
    local p="$1"
    if [ -d "${p}" ]; then
        (cd "${p}" 2>/dev/null && pwd -P) && return 0
    fi
    case "${p}" in
        /*) printf '%s\n' "${p}" ;;
        *)  printf '%s/%s\n' "$(pwd -P)" "${p}" ;;
    esac
}

# Resolve PROJECT_PATH from $CLAUDE_PROJECT_DIR (or $PWD). Used by both
# the routing check and machine-mode emission. If the dir is inside a
# git repo, prefer the toplevel (already absolute — git rev-parse
# returns a physical path); otherwise absolutize via `absolutize()` so
# a relative CLAUDE_PROJECT_DIR like `../foo` never leaks into
# machine-mode `PROJECT=` output.
resolve_project_path() {
    local project_dir="${CLAUDE_PROJECT_DIR:-${PWD}}"
    if [ -d "${project_dir}" ]; then
        local toplevel
        if toplevel="$(git -C "${project_dir}" rev-parse --show-toplevel 2>/dev/null)"; then
            PROJECT_PATH="${toplevel}"
            return
        fi
    fi
    PROJECT_PATH="$(absolutize "${project_dir}")"
}

check_routing_block() {
    # Per spec § 1.5.0 Inputs: $CLAUDE_PROJECT_DIR (defaults to $PWD)
    # is the project root for the routing-block check. If the resolved
    # path is not a git repo, treat as outside-git and skip silently.
    # ROUTING_STATE stays at its `yes` default (silent-skip semantics).
    local project_dir="${CLAUDE_PROJECT_DIR:-${PWD}}"

    if [ ! -d "${project_dir}" ]; then
        # Defensive: caller pointed at a non-existent path — skip.
        return
    fi

    local toplevel
    if ! toplevel="$(git -C "${project_dir}" rev-parse --show-toplevel 2>/dev/null)"; then
        return
    fi

    # Asymmetric rule (per 05-bootstrap-surface.md):
    #   - no AGENTS.md AND no CLAUDE.md → skipped (silent, ROUTING_STATE=yes)
    #   - either file present without the heading → ROUTING_STATE=no
    # Detection is heading-presence only. The SHA-hash protocol lives
    # in F-B2 step 4 (state.yml:routing_blocks[]); for v0.2.0 the dep
    # check uses a literal heading match as a fast first-line signal.
    local agents="${toplevel}/AGENTS.md"
    local claude="${toplevel}/CLAUDE.md"
    local heading='## board-superpowers session routing'
    local saw_file=0
    local saw_marker=0

    if [ -f "${agents}" ]; then
        saw_file=1
        if grep -qF "${heading}" "${agents}"; then
            saw_marker=1
        fi
    fi
    if [ -f "${claude}" ]; then
        saw_file=1
        if grep -qF "${heading}" "${claude}"; then
            saw_marker=1
        fi
    fi

    if [ "${saw_file}" -eq 0 ]; then
        # Neither file exists — silent skip per spec.
        return
    fi

    if [ "${saw_marker}" -eq 1 ]; then
        if [ "${MACHINE_MODE}" -eq 0 ]; then
            printf '  ✓ board-superpowers routing block present\n'
        fi
    else
        if [ "${MACHINE_MODE}" -eq 0 ]; then
            printf '  ✗ AGENTS.md / CLAUDE.md present but routing block missing\n'
        fi
        MISSING_ROUTING=$((MISSING_ROUTING + 1))
        ROUTING_STATE="no"
    fi
}

# --- Run checks (mode-agnostic) ----------------------------------------

if [ "${MACHINE_MODE}" -eq 0 ]; then
    printf 'board-superpowers dependency check:\n'
fi

resolve_project_path
check_cmd gh "install via 'brew install gh'"
check_cmd python3 "macOS / Linux ship python3 by default"
check_cmd git "macOS ships git via Xcode CLT"
check_gh_scope
check_routing_block

# --- Emitters -----------------------------------------------------------

if [ "${MACHINE_MODE}" -eq 1 ]; then
    # Machine mode: ALWAYS exit 0. Emit the three lines only when the
    # "wrong" predicate trips (MISSING non-empty OR ROUTING_INJECTED=no).
    # Build the MISSING csv from the collected tool list, preserving the
    # detection order (gh, python3, git per check_cmd order).
    missing_csv=""
    if [ "${#MISSING_TOOLS[@]}" -gt 0 ]; then
        IFS=',' missing_csv="${MISSING_TOOLS[*]}"
    fi

    if [ -n "${missing_csv}" ] || [ "${ROUTING_STATE}" = "no" ]; then
        printf 'MISSING=%s\n' "${missing_csv}"
        printf 'ROUTING_INJECTED=%s\n' "${ROUTING_STATE}"
        printf 'PROJECT=%s\n' "${PROJECT_PATH}"
    fi
    exit 0
fi

# --- Human-mode exit-code resolution -----------------------------------
# Priority: install-time failures (deps / routing block) outrank runtime
# failures (auth / scope), because a fix-it prompt that says "install
# the binary" is meaningless if the binary is already installed.

if [ "${MISSING_DEPS}" -gt 0 ] || [ "${MISSING_ROUTING}" -gt 0 ]; then
    printf '\nDependency check failed: %d missing dep(s), %d missing routing block(s).\n' \
        "${MISSING_DEPS}" "${MISSING_ROUTING}" >&2
    exit 2
fi

if [ "${RUNTIME_FAILURES}" -gt 0 ]; then
    printf '\nRuntime check failed: %d runtime invariant(s) unsatisfied.\n' \
        "${RUNTIME_FAILURES}" >&2
    exit 3
fi

printf '\nAll dependencies satisfied (board-superpowers v0.2.0).\n'
exit 0
