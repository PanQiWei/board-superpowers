#!/usr/bin/env bash
# hooks/post-tool-use.sh — board-superpowers PostToolUse gate companion.
#
# Records example-skills:skill-creator invocations in the current
# session as a flag file under
# ${TMPDIR:-/tmp}/board-superpowers-sessions/<session_id>/skill-creator-invoked.flag.
# pre-tool-use.sh reads the flag to decide whether to allow Edit / Write /
# MultiEdit to skills/**.
#
# This hook is non-blocking by design — its only role is state capture.
# Exit 0 always, even on internal error.
#
# SELF-CONTAINED: this script MUST NOT source scripts/lib/common.sh,
# per hooks/AGENTS.md Invariant 1.

set -euo pipefail

PAYLOAD="$(cat 2>/dev/null || true)"
if [ -z "${PAYLOAD}" ]; then
    exit 0
fi

EXTRACT="$(printf '%s' "${PAYLOAD}" | python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
sid = (data.get("session_id") or "").strip()
tool = (data.get("tool_name") or "").strip()
ti = data.get("tool_input") or {}
# CC Skill tool input field name is "skill"; Codex variants may use
# "skill_name". Check both for cross-platform compatibility.
sk = (ti.get("skill") or ti.get("skill_name") or "").strip()
print(sid)
print(tool)
print(sk)
' 2>/dev/null)" || exit 0

SESSION_ID="$(printf '%s\n' "${EXTRACT}" | sed -n '1p')"
TOOL_NAME="$(printf '%s\n' "${EXTRACT}" | sed -n '2p')"
SKILL_NAME="$(printf '%s\n' "${EXTRACT}" | sed -n '3p')"

case "${SESSION_ID}" in
    ""|*[!a-zA-Z0-9_-]*) exit 0 ;;
esac

if [ "${TOOL_NAME}" != "Skill" ]; then
    exit 0
fi

# Match any namespace-qualified or bare skill-creator skill name —
# example-skills:skill-creator is the canonical name; future plugins
# may carry the skill under a different namespace.
case "${SKILL_NAME}" in
    *skill-creator) ;;
    *skill-creator/*) ;;
    *) exit 0 ;;
esac

STATE_DIR="${TMPDIR:-/tmp}/board-superpowers-sessions/${SESSION_ID}"
mkdir -p "${STATE_DIR}" 2>/dev/null || exit 0
: > "${STATE_DIR}/skill-creator-invoked.flag" 2>/dev/null || exit 0

exit 0
