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
# The Skill tool input field name is NOT canonically documented in
# https://code.claude.com/docs/en/hooks.md § PreToolUse — the doc
# enumerates schemas for Bash / Write / Edit / Read / Glob / Grep /
# WebFetch / WebSearch / Agent / AskUserQuestion / ExitPlanMode but
# omits Skill. To stay robust against the field name being "skill",
# "skill_name", "name", or future variants, scan ALL string values
# in tool_input for a value ending in "skill-creator" (with optional
# namespace prefix like "example-skills:"). Defense: a *skill-creator
# match in any string field is a strong-enough signal that this
# PostToolUse fired for skill-creator invocation.
sk = ""
if isinstance(ti, dict):
    for v in ti.values():
        if isinstance(v, str):
            stripped = v.strip()
            if stripped.endswith("skill-creator"):
                sk = stripped
                break
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

# SKILL_NAME comes from the defensive scan in the python block — it
# already endswith("skill-creator") if a match was found. Empty means
# no skill-creator-like value was present in tool_input.
if [ -z "${SKILL_NAME}" ]; then
    exit 0
fi

STATE_DIR="${TMPDIR:-/tmp}/board-superpowers-sessions/${SESSION_ID}"
mkdir -p "${STATE_DIR}" 2>/dev/null || exit 0
: > "${STATE_DIR}/skill-creator-invoked.flag" 2>/dev/null || exit 0

exit 0
