#!/usr/bin/env bash
# scripts/bootstrap-rollback.sh — undo F-B2 in symmetric reverse order.
#
# Per Card 2 slice 7 + the A2 decision recorded in
# docs/plans/bootstrap/card-2-bootstrap.md (the boil-the-lake symmetry
# enforcer): every F-B2 side effect has a matching rollback step here,
# applied in reverse order. F-B1 (host bootstrap) is INDEPENDENT; this
# script never touches manifest.yml.
#
# Symmetry rule:
#   ANY future F-B2 step addition MUST add a matching rollback step
#   here in reverse order. The CI gate currently observes this contract
#   only via tests/test-bootstrap-rollback.sh + the end-to-end smoke;
#   reviewers also enforce it on PR. Drift = the rollback subset stops
#   matching the bootstrap superset, which leaves users with un-undoable
#   half-state on `bootstrap-rollback.sh`.
#
# Reverse order:
#   1. rm <repo>/.board-superpowers/config.yml
#   2. remove the bootstrap entry (and its leading header line) from
#      <repo>/.gitignore — leave the file even when it becomes empty
#   3. remove the routing block (between markers) from <repo>/AGENTS.md
#      AND <repo>/CLAUDE.md, preserving everything outside markers
#   4. rm ~/.board-superpowers/repos/<normalized>/state.yml
#   5. PROMPT before rm ~/.board-superpowers/credentials.yml — default =
#      no. Flags below short-circuit the prompt.
#
# What this script does NOT do:
#   - delete labels (cheap to keep, hard to know if user wants them gone)
#   - touch ~/.board-superpowers/manifest.yml (F-B1 is independent)
#   - delete ~/.board-superpowers/repos/<normalized>/audit-local.jsonl
#     (audit history is durable; rollback is for un-bootstrapping a
#     repo, not for forensic-grade purges)
#
# Argument vector:
#   bash scripts/bootstrap-rollback.sh \
#       --repo-root PATH      # absolute repo path; defaults to PWD
#       [--yes]               # auto-confirm credentials.yml prompt as YES (rm)
#       [--keep-credentials]  # NO without prompt (preserve credentials.yml)
#       [--rm-credentials]    # YES without prompt (rm credentials.yml)
#       [--plugin-root P]     # for testability; defaults to derived from
#                             # this file's location
#
# Default behavior with no credentials flag and no --yes:
#   - if credentials.yml is absent: silent no-op (no prompt fires).
#   - if credentials.yml is present: interactive prompt (default NO).
#
# Exit codes:
#   0  success (idempotent on a clean repo too).
#   1  bad args / unrecoverable filesystem failure (rare).
#   64 unknown argument.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

# --- Arg parsing --------------------------------------------------------

REPO_ROOT_ARG=""
YES_FLAG=0
KEEP_CREDS=0
RM_CREDS=0
PLUGIN_ROOT_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --repo-root)
            REPO_ROOT_ARG="${2:-}"
            [ -n "${REPO_ROOT_ARG}" ] || bsp_die "--repo-root requires a path"
            shift 2
            ;;
        --yes)
            YES_FLAG=1
            shift
            ;;
        --keep-credentials)
            KEEP_CREDS=1
            shift
            ;;
        --rm-credentials)
            RM_CREDS=1
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

if [ "${KEEP_CREDS}" -eq 1 ] && [ "${RM_CREDS}" -eq 1 ]; then
    bsp_die "--keep-credentials and --rm-credentials are mutually exclusive"
fi

# --- Resolve plugin root + repo root -----------------------------------

if [ -n "${PLUGIN_ROOT_ARG}" ]; then
    PLUGIN_ROOT="${PLUGIN_ROOT_ARG}"
else
    PLUGIN_ROOT="$(bsp_plugin_root)"
fi
[ -d "${PLUGIN_ROOT}" ] || bsp_die "plugin root not found: ${PLUGIN_ROOT}"

# Suppress shellcheck unused-var warning — kept for future extensibility
# (e.g., plugin-version-aware rollback messaging).
: "${PLUGIN_ROOT:?}"

bsp_require_cmd python3 "macOS / Linux ship python3 by default"
bsp_require_cmd git     "install git for your platform"

RAW_REPO_ROOT="${REPO_ROOT_ARG:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[ -d "${RAW_REPO_ROOT}" ] || bsp_die "repo root not found: ${RAW_REPO_ROOT}"
REPO_ROOT="$(cd "${RAW_REPO_ROOT}" && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${REPO_ROOT}" ]; then
    # Fall back to the literal directory if it is not a git repo. Rollback
    # ought to remain useful for partial-bootstrap cleanup even outside a
    # git workspace.
    REPO_ROOT="$(cd "${RAW_REPO_ROOT}" && pwd -P)"
fi

bsp_log "rollback starting for ${REPO_ROOT}"

# --- Step 1 (reverse): rm <repo>/.board-superpowers/config.yml ----------

CONFIG_FILE="${REPO_ROOT}/.board-superpowers/config.yml"
if [ -f "${CONFIG_FILE}" ]; then
    rm -f "${CONFIG_FILE}"
    bsp_log "removed ${CONFIG_FILE}"
    # Best-effort: if .board-superpowers/ is now empty (no claims/, no
    # other files), remove it. rmdir fails silently when non-empty.
    rmdir "${REPO_ROOT}/.board-superpowers" 2>/dev/null || true
else
    bsp_log "config.yml absent — skip"
fi

# --- Step 2 (reverse): remove bootstrap entry from <repo>/.gitignore ----

GITIGNORE_FILE="${REPO_ROOT}/.gitignore"
GITIGNORE_HEADER="# board-superpowers local state (claim markers are per-session)"
GITIGNORE_ENTRY=".board-superpowers/claims/"

if [ -f "${GITIGNORE_FILE}" ] && grep -Fxq "${GITIGNORE_ENTRY}" "${GITIGNORE_FILE}"; then
    # Remove BOTH the entry line AND its preceding header comment if
    # the header sits immediately above the entry. Atomic rewrite via
    # python3 (bash 3.2 lacks reliable in-place sed).
    GITIGNORE_FILE="${GITIGNORE_FILE}" \
    HEADER_LINE="${GITIGNORE_HEADER}" \
    ENTRY_LINE="${GITIGNORE_ENTRY}" \
    python3 - <<'PY'
import os
import sys
import tempfile

path   = os.environ["GITIGNORE_FILE"]
header = os.environ["HEADER_LINE"]
entry  = os.environ["ENTRY_LINE"]

with open(path, "rb") as f:
    raw = f.read()

# Preserve trailing-newline semantics: split on b"\n" so empty trailing
# is captured.
text = raw.decode("utf-8", errors="replace")
lines = text.split("\n")

out = []
i = 0
n = len(lines)
removed = False
while i < n:
    cur = lines[i]
    nxt = lines[i + 1] if i + 1 < n else None
    # Header followed immediately by entry → drop both.
    if cur == header and nxt == entry:
        i += 2
        removed = True
        # Skip a single trailing blank that exists ONLY because we
        # injected one as a separator on bootstrap. Conservative:
        # only drop when the previous emitted line is also blank or
        # nothing has been emitted yet.
        if i < n and lines[i] == "" and (not out or out[-1] == ""):
            i += 1
        continue
    # Entry alone (no header above) → drop the entry only.
    if cur == entry:
        i += 1
        removed = True
        continue
    out.append(cur)
    i += 1

new_text = "\n".join(out)

# Collapse a run of multiple trailing blank lines down to a single
# trailing newline (cosmetic — rollback should not leave a forest of
# empty lines behind).
while new_text.endswith("\n\n\n"):
    new_text = new_text[:-1]

# If the file was non-empty originally and we collapsed everything,
# leave it as a single empty line so the file still exists per spec
# ("leave the file even if it becomes empty").
if not removed:
    sys.exit(0)

# Atomic write.
parent = os.path.dirname(path) or "."
fd, tmp = tempfile.mkstemp(prefix=".bsp-rollback-", dir=parent)
try:
    with os.fdopen(fd, "wb") as fh:
        fh.write(new_text.encode("utf-8"))
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY
    bsp_log "removed bootstrap entry from ${GITIGNORE_FILE}"
else
    bsp_log ".gitignore bootstrap entry absent — skip"
fi

# --- Step 3 (reverse): remove routing block from AGENTS.md + CLAUDE.md --

remove_routing_block() {
    local target="$1"
    if [ ! -f "${target}" ]; then
        bsp_log "${target} absent — skip"
        return 0
    fi
    if ! grep -Fq '<!-- board-superpowers:routing -->' "${target}" \
        && ! grep -Fq '<!-- /board-superpowers:routing -->' "${target}"
    then
        bsp_log "${target} has no routing markers — skip"
        return 0
    fi
    BSP_TARGET="${target}" python3 - <<'PY'
import os
import tempfile

target = os.environ["BSP_TARGET"]
OPEN  = b"<!-- board-superpowers:routing -->"
CLOSE = b"<!-- /board-superpowers:routing -->"
BOM   = b"\xef\xbb\xbf"

with open(target, "rb") as f:
    raw = f.read()

bom_prefix = b""
body = raw
if body.startswith(BOM):
    bom_prefix = BOM
    body = body[len(BOM):]

# Best-effort cleanup. We accept any of:
#   - both markers present (the standard case): excise the block + a
#     leading blank line if one immediately precedes the OPEN marker.
#   - only OPEN present (orphan): strip the OPEN marker line only.
#   - only CLOSE present (orphan): strip the CLOSE marker line only.
#   - multiple pairs: greedy-strip the FIRST pair; leave subsequent
#     ones to a re-run. Not the steady-state we expect, but rollback
#     should make progress, not block on partial-bootstrap pathology.

def _strip_pair(buf: bytes) -> bytes:
    o = buf.find(OPEN)
    c = buf.find(CLOSE)
    if o == -1 or c == -1 or c < o:
        return buf  # caller falls through to orphan handling
    # Extend the OPEN slice backwards over a single preceding LF so the
    # blank line bootstrap inserted gets cleaned too.
    open_start = o
    if open_start > 0 and buf[open_start - 1:open_start] == b"\n":
        # Walk back across an additional blank-line LF if present.
        if open_start - 2 >= 0 and buf[open_start - 2:open_start - 1] == b"\n":
            open_start -= 1
    close_end = c + len(CLOSE)
    # Eat one trailing newline immediately after CLOSE so we don't leave
    # a stray blank line where the block lived.
    if close_end < len(buf) and buf[close_end:close_end + 1] == b"\n":
        close_end += 1
    return buf[:open_start] + buf[close_end:]

def _strip_orphan_line(buf: bytes, marker: bytes) -> bytes:
    idx = buf.find(marker)
    if idx == -1:
        return buf
    line_start = buf.rfind(b"\n", 0, idx) + 1  # works when idx == 0
    line_end = buf.find(b"\n", idx)
    if line_end == -1:
        line_end = len(buf)
    else:
        line_end += 1  # include the trailing newline
    return buf[:line_start] + buf[line_end:]

# Strip pairs greedily until no more remain.
while True:
    new = _strip_pair(body)
    if new == body:
        break
    body = new

# Any orphan markers left behind? Strip their lines.
body = _strip_orphan_line(body, OPEN)
body = _strip_orphan_line(body, CLOSE)

# Collapse runaway blank lines at EOF down to a single trailing newline.
while body.endswith(b"\n\n\n"):
    body = body[:-1]
# Guarantee a final newline if any content remains.
if body and not body.endswith(b"\n"):
    body += b"\n"

payload = bom_prefix + body

parent = os.path.dirname(target) or "."
fd, tmp = tempfile.mkstemp(prefix=".bsp-rollback-", dir=parent)
try:
    with os.fdopen(fd, "wb") as fh:
        fh.write(payload)
    os.replace(tmp, target)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY
    bsp_log "removed routing block from ${target}"
}

remove_routing_block "${REPO_ROOT}/AGENTS.md"
remove_routing_block "${REPO_ROOT}/CLAUDE.md"

# --- Step 4 (reverse): rm host-local state.yml --------------------------

STATE_DIR="$(bsp_host_state_dir "${REPO_ROOT}")"
STATE_FILE="${STATE_DIR}/state.yml"
if [ -f "${STATE_FILE}" ]; then
    rm -f "${STATE_FILE}"
    bsp_log "removed ${STATE_FILE}"
    # rmdir up the chain best-effort — only succeeds when empty.
    rmdir "${STATE_DIR}" 2>/dev/null || true
    # Don't rmdir the parent ~/.board-superpowers/repos/ — it might
    # legitimately still hold other repos' subdirs.
else
    bsp_log "state.yml absent — skip"
fi

# --- Step 5 (reverse): credentials.yml prompt ---------------------------

CRED_FILE="${HOME}/.board-superpowers/credentials.yml"

if [ ! -f "${CRED_FILE}" ]; then
    bsp_log "credentials.yml absent — skip"
elif [ "${KEEP_CREDS}" -eq 1 ]; then
    bsp_log "--keep-credentials: leaving ${CRED_FILE} in place"
elif [ "${RM_CREDS}" -eq 1 ]; then
    rm -f "${CRED_FILE}"
    bsp_log "--rm-credentials: removed ${CRED_FILE}"
elif [ "${YES_FLAG}" -eq 1 ]; then
    rm -f "${CRED_FILE}"
    bsp_log "--yes: removed ${CRED_FILE}"
else
    # Interactive prompt — DEFAULT NO. credentials.yml might predate
    # this bootstrap or apply to other repos.
    {
        printf '\n'
        printf '[bsp] %s exists.\n' "${CRED_FILE}"
        printf '[bsp] It might predate this bootstrap or apply to other repos.\n'
        printf '[bsp] Remove it? [y/N] '
    } >&2
    input_source="/dev/stdin"
    if [ -t 0 ] && [ -r /dev/tty ]; then
        input_source="/dev/tty"
    fi
    answer=""
    if ! IFS= read -r answer < "${input_source}"; then
        answer=""
    fi
    case "${answer}" in
        y|Y|yes|YES|Yes)
            rm -f "${CRED_FILE}"
            bsp_log "removed ${CRED_FILE}"
            ;;
        *)
            bsp_log "leaving ${CRED_FILE} in place (default)"
            ;;
    esac
fi

bsp_log "rollback complete for ${REPO_ROOT}"
exit 0
