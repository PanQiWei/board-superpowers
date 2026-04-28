#!/usr/bin/env bash
# scripts/audit-log-write.sh — per-mutating-action audit row writer.
#
# Self-healing: invokes bsp_ensure_venv to recreate venv if missing.
# jsonl fallback on any DB / venv / config failure (exit 0 always when
# at least one row was written somewhere).
#
# Args:
#   --action-id <int>             1-14 producer / 100-113 consumer / 200-208 bootstrap
#   --decision A|R|N
#   --skill <name>
#   --approval-stage auto|propose|approved|rejected
#   --outcome success|failure
#   --payload <json>
#   [--repo-root <path>]          default: bsp_primary_repo_root from PWD
#   [--mode <bootstrap-pending>]  outbox path (#43 AC4 write); writes a
#                                 jsonl row with event_uuid + status=pending
#                                 + retry_count=0 + pending_since and
#                                 short-circuits the DB INSERT path. Only
#                                 'bootstrap-pending' is permitted
#                                 externally; other internal modes
#                                 (no-db / contract-violation / etc.) are
#                                 chosen by this script based on runtime
#                                 conditions.
#
# Exit codes:
#   0 — written (DB or jsonl)
#   1 — contract violation (e.g., non-integer --action-id); a
#       mode=contract-violation jsonl row is still written for forensics
#   2 — bad args (including --mode value not in the external whitelist)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
source "${SCRIPT_DIR}/lib/common.sh"

# --- parse args -----------------------------------------------------------
ACTION_ID=""
DECISION=""
SKILL=""
APPROVAL_STAGE=""
OUTCOME=""
PAYLOAD=""
REPO_ROOT=""
MODE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --action-id)        ACTION_ID="$2"; shift 2 ;;
        --decision)         DECISION="$2"; shift 2 ;;
        --skill)            SKILL="$2"; shift 2 ;;
        --approval-stage)   APPROVAL_STAGE="$2"; shift 2 ;;
        --outcome)          OUTCOME="$2"; shift 2 ;;
        --payload)          PAYLOAD="$2"; shift 2 ;;
        --repo-root)        REPO_ROOT="$2"; shift 2 ;;
        --mode)             MODE="$2"; shift 2 ;;
        *) bsp_warn "unknown arg: $1"; exit 2 ;;
    esac
done

# Validate required args. Use indirect reference via eval for bash 3.2 compat.
for v in ACTION_ID DECISION SKILL APPROVAL_STAGE OUTCOME PAYLOAD; do
    eval "_val=\"\${${v}:-}\""
    if [ -z "${_val}" ]; then
        # Lowercase the variable name for the error message (bash 3.2 safe).
        vlow="$(printf '%s' "${v}" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
        bsp_warn "missing required arg: --${vlow}"
        exit 2
    fi
done

[ -z "${REPO_ROOT}" ] && REPO_ROOT="$(bsp_primary_repo_root "${PWD}" 2>/dev/null || echo "${PWD}")"

# Integer validation — MUST happen before any mode/DB branching.
# Per design.md §3.2 + Codex blocker fix: non-integer action_id is a contract
# violation distinguishable from DB outage. The check must be pre-mode-branch
# so future --mode flags (e.g. AC4 bootstrap-pending which bypasses DB) cannot
# circumvent it. Defense in depth — the Python heredoc still does
# int(BSP_ACTION_ID) downstream, but that path is now unreachable for
# non-integers because the shell-side rejection runs first.
if ! [[ "${ACTION_ID}" =~ ^[0-9]+$ ]]; then
    bsp_warn "contract violation: --action-id is not integer: ${ACTION_ID}"
    bsp_audit_local_write "${REPO_ROOT}" "${ACTION_ID}" "${DECISION}" "${SKILL}" \
        "approval=${APPROVAL_STAGE} outcome=${OUTCOME} payload=${PAYLOAD}" \
        "contract-violation"
    exit 1
fi

# --- --mode whitelist (caller-provided) ----------------------------------
# Only 'bootstrap-pending' is allowed externally. All other modes
# (no-db / degraded-* / contract-violation / audit-dead-letter) are
# selected internally by this script based on runtime state. Rejecting
# unknown caller-provided values keeps the outbox path's invariant
# (status=pending + event_uuid + retry_count=0 + pending_since) tied to
# exactly one named mode.
if [ -n "${MODE}" ] && [ "${MODE}" != "bootstrap-pending" ]; then
    bsp_warn "audit-log-write.sh: --mode value '${MODE}' not allowed (only 'bootstrap-pending' permitted externally)"
    exit 2
fi

# --- opportunistic flush guard -------------------------------------------
# Per #43 AC4 design: every audit-log-write call checks whether outbox
# rows are pending and bg-forks the flush daemon when the 60s backoff
# window has elapsed. The sentinel is touched after each
# bootstrap-pending row write (below); audit-last-flush is owned by
# audit-flush-pending.sh and updated each flush attempt. The
# BSP_SKIP_GUARD env guard prevents the flush script from re-entering
# itself when it invokes audit-log-write.sh internally.
SENTINEL="${HOME}/.board-superpowers/audit-pending.sentinel"
LAST_FLUSH_FILE="${HOME}/.board-superpowers/audit-last-flush"
FLUSH_SCRIPT="${SCRIPT_DIR}/audit-flush-pending.sh"
if [ -f "${SENTINEL}" ] && [ -x "${FLUSH_SCRIPT}" ] && [ -z "${BSP_SKIP_GUARD:-}" ]; then
    NOW_SEC=$(date +%s)
    LAST_FLUSH_SEC=$(cat "${LAST_FLUSH_FILE}" 2>/dev/null || echo 0)
    case "${LAST_FLUSH_SEC}" in
        ''|*[!0-9]*) LAST_FLUSH_SEC=0 ;;
    esac
    if [ $((NOW_SEC - LAST_FLUSH_SEC)) -gt 60 ]; then
        echo "${NOW_SEC}" > "${LAST_FLUSH_FILE}"
        BSP_SKIP_GUARD=1 bash "${FLUSH_SCRIPT}" --quiet >/dev/null 2>&1 &
    fi
fi

# --- mode=bootstrap-pending outbox path ----------------------------------
# When the caller is the bootstrap path (DB credentials not yet
# resolvable), short-circuit the DB INSERT and write a single
# outbox-shaped jsonl row tagged with event_uuid + status=pending.
# Touch the sentinel so the next non-guarded audit-log-write call
# (after the 60s backoff window) fires the flush daemon.
if [ "${MODE}" = "bootstrap-pending" ]; then
    EVENT_UUID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
    PENDING_SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    bsp_audit_local_write "${REPO_ROOT}" "${ACTION_ID}" "${DECISION}" "${SKILL}" \
        "approval=${APPROVAL_STAGE} outcome=${OUTCOME} payload=${PAYLOAD}" \
        "bootstrap-pending" \
        --event-uuid "${EVENT_UUID}" \
        --status "pending" \
        --retry-count 0 \
        --pending-since "${PENDING_SINCE}"
    mkdir -p "$(dirname "${SENTINEL}")"
    : > "${SENTINEL}"
    exit 0
fi

# --- resolve venv (self-healing) ------------------------------------------
VENV_PYTHON=""
VENV_RC=0
if VENV_PYTHON="$(bsp_ensure_venv "${REPO_ROOT}" 2>/dev/null)"; then
    :
else
    VENV_RC=$?
fi

# --- handle venv missing modes --------------------------------------------
if [ -z "${VENV_PYTHON}" ]; then
    case ${VENV_RC} in
        5) MODE="degraded-uv-missing"; bsp_warn "uv missing on PATH; degrading to jsonl" ;;
        6) bsp_die "plugin template corruption (templates/pyproject.toml absent)" ;;
        7) MODE="degraded-venv-create-failed"; bsp_warn "uv sync failed; degrading to jsonl" ;;
        # Unknown rc collapses into the create-failed bucket so the wire
        # format stays inside the documented 4-value current enum
        # (spec 06 § "jsonl fallback mode-field"). The real rc value
        # surfaces via the bsp_warn log line below for forensic use.
        *) MODE="degraded-venv-create-failed"; bsp_warn "venv unavailable (rc=${VENV_RC}); degrading to jsonl" ;;
    esac
    bsp_audit_local_write "${REPO_ROOT}" "${ACTION_ID}" "${DECISION}" "${SKILL}" \
        "approval=${APPROVAL_STAGE} outcome=${OUTCOME} payload=${PAYLOAD}" \
        "${MODE}"
    exit 0
fi

# --- resolve audit_db_url -------------------------------------------------
AUDIT_DB_URL="$(bsp_resolve_audit_db_url)"
if [ -z "${AUDIT_DB_URL}" ]; then
    bsp_warn "audit_db_url unset; degrading to jsonl mode=no-db"
    bsp_audit_local_write "${REPO_ROOT}" "${ACTION_ID}" "${DECISION}" "${SKILL}" \
        "approval=${APPROVAL_STAGE} outcome=${OUTCOME} payload=${PAYLOAD}" \
        "no-db"
    exit 0
fi

# Resolve project identifier as `OWNER/NUMBER` per the BoardAdapter
# contract (spec 06 § Core schema). Read from <repo>/.board-superpowers/
# config.yml; fall back to repo basename only when the config.yml is
# missing or has no project: field (e.g., bootstrap not yet run on a
# fresh repo, or non-BoardAdapter context).
# `|| true` suppresses pipefail when grep finds no match (no config.yml,
# or no project: line).
PROJECT_FROM_CONFIG="$( { grep -E '^project[[:space:]]*:' "${REPO_ROOT}/.board-superpowers/config.yml" 2>/dev/null \
        | head -n1 \
        | sed -E 's/^project[[:space:]]*:[[:space:]]*//; s/^"//; s/"$//'; } || true)"
PROJECT_NAME="${PROJECT_FROM_CONFIG:-$(basename "${REPO_ROOT}")}"

# --- INSERT via venv-python -----------------------------------------------
INSERT_RC=0
BSP_REPO_ROOT="${REPO_ROOT}" \
BSP_AUDIT_DB_URL="${AUDIT_DB_URL}" \
BSP_PROJECT="${PROJECT_NAME}" \
BSP_SESSION_ID="${CLAUDE_SESSION_ID:-${PWD//\//-}}" \
BSP_ACTOR_ROLE="$( [ "${SKILL}" = "consuming-card" ] && echo consumer || echo producer )" \
BSP_ACTION_ID="${ACTION_ID}" \
BSP_PAYLOAD="${PAYLOAD}" \
BSP_OUTCOME="${OUTCOME}" \
BSP_APPROVAL_STAGE="${APPROVAL_STAGE}" \
"${VENV_PYTHON}" - <<'PY' || INSERT_RC=$?
import os, sys, time, sqlite3, subprocess
from urllib.parse import urlparse

url_str = os.environ['BSP_AUDIT_DB_URL']
url = urlparse(url_str)
scheme = url.scheme

ts = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
project = os.environ['BSP_PROJECT']
session_id = os.environ['BSP_SESSION_ID']
actor_role = os.environ['BSP_ACTOR_ROLE']
action_id = int(os.environ['BSP_ACTION_ID'])
payload = os.environ['BSP_PAYLOAD']
outcome = os.environ['BSP_OUTCOME']
approval_stage = os.environ['BSP_APPROVAL_STAGE']

values = (ts, project, session_id, actor_role, action_id, payload, outcome, approval_stage)

if scheme in ('sqlite', 'sqlite3'):
    db_path = url_str.replace(scheme + '://', '', 1)
    if not db_path.startswith('/'):
        # 4-slash absolute form: sqlite:////abs/path
        db_path = '/' + db_path.lstrip('/')
    conn = sqlite3.connect(db_path)
    conn.execute(
        "INSERT INTO audit_log "
        "(timestamp, project, session_id, actor_role, action_id, payload, outcome, approval_stage) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        values,
    )
    conn.commit()
    conn.close()
elif scheme in ('postgresql', 'postgres'):
    # Use psql -v parameterization. Each value passed as variable.
    args = ['psql', url_str, '-v', 'ON_ERROR_STOP=1']
    for k, v in zip(['ts', 'project', 'session_id', 'actor_role', 'action_id',
                     'payload', 'outcome', 'approval_stage'], values):
        args.extend(['-v', '{k}={v}'.format(k=k, v=v)])
    args.extend(['-c',
        "INSERT INTO audit_log "
        "(timestamp, project, session_id, actor_role, action_id, payload, outcome, approval_stage) "
        "VALUES (:'ts', :'project', :'session_id', :'actor_role', :'action_id'::int, "
        ":'payload', :'outcome', :'approval_stage')"
    ])
    r = subprocess.run(args, capture_output=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr.decode())
        sys.exit(r.returncode)
elif scheme in ('mysql', 'mysql+pymysql'):
    import pymysql
    canonical_url = url_str.replace('mysql+pymysql://', 'mysql://')
    u = urlparse(canonical_url)
    conn = pymysql.connect(
        host=u.hostname or 'localhost',
        port=u.port or 3306,
        user=u.username,
        password=u.password,
        database=u.path.lstrip('/'),
    )
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO audit_log "
            "(timestamp, project, session_id, actor_role, action_id, payload, outcome, approval_stage) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
            values,
        )
    conn.commit()
    conn.close()
else:
    sys.stderr.write('unsupported scheme: {}\n'.format(scheme))
    sys.exit(1)
PY

# --- handle DB error → jsonl fallback ------------------------------------
if [ ${INSERT_RC} -ne 0 ]; then
    bsp_warn "DB insert failed (rc=${INSERT_RC}); degrading to jsonl mode=degraded-db-unavailable"
    bsp_audit_local_write "${REPO_ROOT}" "${ACTION_ID}" "${DECISION}" "${SKILL}" \
        "approval=${APPROVAL_STAGE} outcome=${OUTCOME} payload=${PAYLOAD}" \
        "degraded-db-unavailable"
    exit 0
fi

[ "${BOARD_SP_VERBOSE:-}" = "1" ] && bsp_log "audit: ${SKILL} action_id=${ACTION_ID} → ${AUDIT_DB_URL}"
exit 0
