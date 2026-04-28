#!/usr/bin/env bash
# hooks/pre-tool-use.sh — board-superpowers PreToolUse gate.
#
# Blocks Edit / Write / MultiEdit to skills/** when
# example-skills:skill-creator has not yet been invoked in this session.
# Implements the structural enforcement of the skills/AGENTS.md
# "Process gate" — Doctrine #4 in AGENTS.md (root) prohibits skipping
# the entry skill, but until this hook landed enforcement was honor-system
# only and observed to fail repeatedly across consumer sessions.
#
# Companion hook: post-tool-use.sh records skill-creator invocations
# to ${TMPDIR:-/tmp}/board-superpowers-sessions/<session_id>/skill-creator-invoked.flag.
# pre-tool-use.sh reads the flag to decide whether to allow the edit.
#
# Failure-mode trade-off: this hook DELIBERATELY exits 2 to block when
# the gate fires — the inverse of session-start.sh's "never block"
# stance. See hooks/AGENTS.md Invariant 5. The trade-off:
#   SessionStart: blocking startup is worse than running unconfigured.
#   PreToolUse-gate: allowing ungated skill edits is worse than blocking.
#
# Failure-OPEN policy: the hook fails open on its own internal errors
# (missing python3, malformed JSON, parsing exceptions). Internal hook
# failure must NOT block the architect's edit — only the gate's positive
# match (skill-creator not invoked) blocks. See hooks/AGENTS.md Invariant
# 3 wording.
#
# SELF-CONTAINED: this script MUST NOT source scripts/lib/common.sh,
# per hooks/AGENTS.md Invariant 1.

set -euo pipefail

# Read JSON payload from stdin. Fail-open on read error.
PAYLOAD="$(cat 2>/dev/null || true)"
if [ -z "${PAYLOAD}" ]; then
    exit 0
fi

# Extract the three fields we need: session_id, tool_name, tool_input.file_path.
# Fail-open on parse error (python3 missing, malformed JSON, key absent).
EXTRACT="$(printf '%s' "${PAYLOAD}" | python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
sid = (data.get("session_id") or "").strip()
tool = (data.get("tool_name") or "").strip()
ti = data.get("tool_input") or {}
fp = (ti.get("file_path") or "").strip()
print(sid)
print(tool)
print(fp)
' 2>/dev/null)" || exit 0

SESSION_ID="$(printf '%s\n' "${EXTRACT}" | sed -n '1p')"
TOOL_NAME="$(printf '%s\n' "${EXTRACT}" | sed -n '2p')"
FILE_PATH="$(printf '%s\n' "${EXTRACT}" | sed -n '3p')"

# Defense-in-depth: SESSION_ID is interpolated into a path. Reject any
# non-[a-zA-Z0-9_-] character. Empty session_id also fails open.
case "${SESSION_ID}" in
    ""|*[!a-zA-Z0-9_-]*) exit 0 ;;
esac

# Only gate Edit / Write / MultiEdit (path-typed file mutations).
case "${TOOL_NAME}" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

# Match paths under skills/ — the gated tree. Both relative and absolute
# patterns are matched.
case "${FILE_PATH}" in
    */skills/*|skills/*) ;;
    *) exit 0 ;;
esac

# Check session state. The flag is set by post-tool-use.sh on a
# successful Skill tool call where skill_name matches *skill-creator*.
STATE_DIR="${TMPDIR:-/tmp}/board-superpowers-sessions/${SESSION_ID}"
FLAG_FILE="${STATE_DIR}/skill-creator-invoked.flag"

if [ -f "${FLAG_FILE}" ]; then
    exit 0
fi

# Gate fires. Emit reason on stderr and exit 2 to block the tool call.
# CC propagates stderr content to the model when the hook exits 2,
# per docs/architecture/0005-contracts/02-hook-contracts.md § "Exit codes".
cat >&2 <<'REASON'
skills/AGENTS.md Process gate fires.

You are about to edit a file under skills/, but example-skills:skill-creator
has NOT been invoked in this session. Per AGENTS.md (root) Doctrine #4,
the entry skill is mandatory before any edit under skills/ — even when
the work feels routine.

How to clear the gate:
  1. Invoke example-skills:skill-creator via the Skill tool.
  2. Re-attempt this Edit / Write / MultiEdit.

The gate self-clears once skill-creator is invoked in this session.

Why this hook exists: Doctrine #4 was previously honor-system; the gate
fired only as a system-reminder that the model could read past while
already in flow. This hook turns the doctrine into a tool-level
enforcement (board-superpowers v0.4.x ship gate-blocking PreToolUse;
contract documented at docs/architecture/0005-contracts/02-hook-contracts.md
§ "PreToolUse gate hook").
REASON
exit 2
