#!/usr/bin/env bash
# tests/test-skills-edit-gate.sh — assert hooks/pre-tool-use.sh blocks
# Edit / Write / MultiEdit on skills/** when example-skills:skill-creator
# has not been invoked in this session, allows them after invocation,
# and fails open on internal errors.
#
# Spec under test:
#   docs/architecture/0005-contracts/02-hook-contracts.md
#     § "PreToolUse gate hook" — gate semantics + flag-file lifecycle.
#   skills/AGENTS.md "Process gate" — Doctrine #4 enforcement.
#
# Hermeticity: each scenario uses a fresh TMPDIR + a fresh session_id
# so flag files do not leak between cases. No reach-through to the real
# /tmp/board-superpowers-sessions tree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_REAL="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRE="${PLUGIN_ROOT_REAL}/hooks/pre-tool-use.sh"
POST="${PLUGIN_ROOT_REAL}/hooks/post-tool-use.sh"

if [ ! -f "${PRE}" ] || [ ! -f "${POST}" ]; then
    printf 'FATAL: pre-tool-use.sh or post-tool-use.sh missing\n' >&2
    exit 99
fi

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if "$@"; then
        printf '  PASS — %s\n' "${label}"
        PASS=$((PASS + 1))
    else
        printf '  FAIL — %s\n' "${label}" >&2
        FAIL=$((FAIL + 1))
    fi
}

# shellcheck disable=SC2329
# run_pre_with_payload + run_post_with_payload are invoked indirectly via
# the `check` runner; shellcheck cannot trace through.
run_pre_with_payload() {
    # run_pre_with_payload <expected-exit> <payload-json>
    # Returns true iff pre-tool-use.sh exits with the expected code.
    local expected="$1"
    local payload="$2"
    local actual
    set +e
    printf '%s' "${payload}" | bash "${PRE}" >/dev/null 2>&1
    actual=$?
    set -e
    [ "${actual}" -eq "${expected}" ]
}

# shellcheck disable=SC2329
run_post_with_payload() {
    # run_post_with_payload <payload-json>
    # Returns true iff post-tool-use.sh exits 0.
    local payload="$1"
    local actual
    set +e
    printf '%s' "${payload}" | bash "${POST}" >/dev/null 2>&1
    actual=$?
    set -e
    [ "${actual}" -eq 0 ]
}

# shellcheck disable=SC2329
flag_exists() {
    # flag_exists <tmpdir> <session_id>
    [ -f "${1}/board-superpowers-sessions/${2}/skill-creator-invoked.flag" ]
}

# --- Scenarios ------------------------------------------------------------

printf '\nScenario A — Edit on skills/ without skill-creator → block (exit 2)\n'
TMPDIR_A="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_A}"' EXIT
SID_A="sess-a-$$"
PAYLOAD_A="$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/repo/skills/managing-board/references/intake.md"}}' "${SID_A}")"
TMPDIR="${TMPDIR_A}" check "Edit on skills/ without skill-creator → exit 2" \
    run_pre_with_payload 2 "${PAYLOAD_A}"

printf '\nScenario B — Edit OUTSIDE skills/ → allow (exit 0)\n'
PAYLOAD_B="$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/repo/docs/architecture/foo.md"}}' "${SID_A}")"
TMPDIR="${TMPDIR_A}" check "Edit on docs/ → exit 0 (no gate)" \
    run_pre_with_payload 0 "${PAYLOAD_B}"

printf '\nScenario C — post-tool-use records skill-creator invocation\n'
TMPDIR_C="$(mktemp -d)"
SID_C="sess-c-$$"
PAYLOAD_C="$(printf '{"session_id":"%s","tool_name":"Skill","tool_input":{"skill":"example-skills:skill-creator"}}' "${SID_C}")"
TMPDIR="${TMPDIR_C}" check "post-tool-use exits 0 on Skill skill-creator" \
    run_post_with_payload "${PAYLOAD_C}"
check "post-tool-use creates flag file" flag_exists "${TMPDIR_C}" "${SID_C}"

printf '\nScenario D — After skill-creator, Edit on skills/ → allow (exit 0)\n'
PAYLOAD_D="$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/repo/skills/foo/SKILL.md"}}' "${SID_C}")"
TMPDIR="${TMPDIR_C}" check "Edit on skills/ with flag set → exit 0" \
    run_pre_with_payload 0 "${PAYLOAD_D}"

printf '\nScenario E — Bash tool on skills/ → not gated (exit 0; documented gap)\n'
TMPDIR_E="$(mktemp -d)"
SID_E="sess-e-$$"
PAYLOAD_E="$(printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"echo > skills/foo.md"}}' "${SID_E}")"
TMPDIR="${TMPDIR_E}" check "Bash on skills/ → exit 0 (gap documented)" \
    run_pre_with_payload 0 "${PAYLOAD_E}"
rm -rf "${TMPDIR_E}"

printf '\nScenario F — fail-open on malformed JSON\n'
TMPDIR_F="$(mktemp -d)"
TMPDIR="${TMPDIR_F}" check "malformed JSON → exit 0 (fail-open)" \
    run_pre_with_payload 0 'not valid json'
TMPDIR="${TMPDIR_F}" check "empty payload → exit 0 (fail-open)" \
    run_pre_with_payload 0 ''
rm -rf "${TMPDIR_F}"

printf '\nScenario G — non-Edit tool on skills/ → not gated\n'
TMPDIR_G="$(mktemp -d)"
SID_G="sess-g-$$"
PAYLOAD_G="$(printf '{"session_id":"%s","tool_name":"Read","tool_input":{"file_path":"/repo/skills/foo/SKILL.md"}}' "${SID_G}")"
TMPDIR="${TMPDIR_G}" check "Read on skills/ → exit 0 (only Edit/Write/MultiEdit are gated)" \
    run_pre_with_payload 0 "${PAYLOAD_G}"
rm -rf "${TMPDIR_G}"

printf '\nScenario H — defense-in-depth: malicious session_id → fail-open, no path traversal\n'
TMPDIR_H="$(mktemp -d)"
SID_BAD="../etc/passwd"
PAYLOAD_H="$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/repo/skills/foo.md"}}' "${SID_BAD}")"
TMPDIR="${TMPDIR_H}" check "session_id with path-traversal chars → exit 0 (sanitized)" \
    run_pre_with_payload 0 "${PAYLOAD_H}"
rm -rf "${TMPDIR_H}"

printf '\nScenario I — MultiEdit and Write also gated\n'
TMPDIR_I="$(mktemp -d)"
SID_I="sess-i-$$"
PAYLOAD_WRITE="$(printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"/repo/skills/foo.md"}}' "${SID_I}")"
TMPDIR="${TMPDIR_I}" check "Write on skills/ without skill-creator → exit 2" \
    run_pre_with_payload 2 "${PAYLOAD_WRITE}"
PAYLOAD_MULTI="$(printf '{"session_id":"%s","tool_name":"MultiEdit","tool_input":{"file_path":"/repo/skills/foo.md"}}' "${SID_I}")"
TMPDIR="${TMPDIR_I}" check "MultiEdit on skills/ without skill-creator → exit 2" \
    run_pre_with_payload 2 "${PAYLOAD_MULTI}"
rm -rf "${TMPDIR_I}"

printf '\nScenario J — non-Skill PostToolUse calls → no flag written\n'
TMPDIR_J="$(mktemp -d)"
SID_J="sess-j-$$"
PAYLOAD_NONSKILL="$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/foo"}}' "${SID_J}")"
TMPDIR="${TMPDIR_J}" check "PostToolUse on non-Skill → exit 0" \
    run_post_with_payload "${PAYLOAD_NONSKILL}"
if flag_exists "${TMPDIR_J}" "${SID_J}"; then
    printf '  FAIL — flag should not exist after non-Skill PostToolUse\n' >&2
    FAIL=$((FAIL + 1))
else
    printf '  PASS — non-Skill PostToolUse does not create flag\n'
    PASS=$((PASS + 1))
fi
rm -rf "${TMPDIR_J}"

printf '\nScenario K — wrong skill name → no flag written\n'
TMPDIR_K="$(mktemp -d)"
SID_K="sess-k-$$"
PAYLOAD_WRONG="$(printf '{"session_id":"%s","tool_name":"Skill","tool_input":{"skill":"superpowers:test-driven-development"}}' "${SID_K}")"
TMPDIR="${TMPDIR_K}" check "PostToolUse on non-skill-creator skill → exit 0" \
    run_post_with_payload "${PAYLOAD_WRONG}"
if flag_exists "${TMPDIR_K}" "${SID_K}"; then
    printf '  FAIL — flag should not exist for unrelated Skill\n' >&2
    FAIL=$((FAIL + 1))
else
    printf '  PASS — wrong skill name does not create flag\n'
    PASS=$((PASS + 1))
fi
rm -rf "${TMPDIR_K}"

printf '\nScenario L — pre-tool-use emits canonical permissionDecision JSON on stdout\n'
TMPDIR_L="$(mktemp -d)"
SID_L="sess-l-$$"
PAYLOAD_L="$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/repo/skills/foo.md"}}' "${SID_L}")"
GATE_OUTPUT="$(TMPDIR="${TMPDIR_L}" printf '%s' "${PAYLOAD_L}" | bash "${PRE}" 2>/dev/null || true)"
if printf '%s' "${GATE_OUTPUT}" | python3 -c '
import json, sys
data = json.load(sys.stdin)
out = data.get("hookSpecificOutput") or {}
ok = (out.get("hookEventName") == "PreToolUse"
      and out.get("permissionDecision") == "deny"
      and isinstance(out.get("permissionDecisionReason"), str)
      and out.get("permissionDecisionReason"))
sys.exit(0 if ok else 1)
' 2>/dev/null; then
    printf '  PASS — stdout JSON shape matches CC canonical PreToolUse contract\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL — stdout JSON does not match CC canonical contract\n' >&2
    printf '  (got: %s)\n' "${GATE_OUTPUT}" >&2
    FAIL=$((FAIL + 1))
fi
rm -rf "${TMPDIR_L}"

printf '\nScenario M — post-tool-use defensive scan finds skill-creator in alternative field names\n'
# The Skill tool input field name is not canonically documented. The
# defensive scan looks at every string value in tool_input — should
# match regardless of whether the field is "skill", "skill_name",
# "name", or arbitrary future variants.
for field_name in skill skill_name name spice future_field_name; do
    TMPDIR_M="$(mktemp -d)"
    SID_M="sess-m-${field_name}-$$"
    PAYLOAD_M="$(printf '{"session_id":"%s","tool_name":"Skill","tool_input":{"%s":"example-skills:skill-creator"}}' "${SID_M}" "${field_name}")"
    TMPDIR="${TMPDIR_M}" check "post-tool-use scan via field=${field_name}" \
        run_post_with_payload "${PAYLOAD_M}"
    check "  flag created via field=${field_name}" flag_exists "${TMPDIR_M}" "${SID_M}"
    rm -rf "${TMPDIR_M}"
done

# --- Summary --------------------------------------------------------------
printf '\n--- summary: %d pass, %d fail ---\n' "${PASS}" "${FAIL}"
if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0
