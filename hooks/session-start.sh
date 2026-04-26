#!/usr/bin/env bash
# hooks/session-start.sh — board-superpowers SessionStart hook.
#
# Fires once per CC session at startup. Performs:
#   1. Dependency check (delegated to scripts/check-deps.sh).
#   2. State inspection (host-local state.yml + per-repo config.yml).
#   3. Optional intent injection — emits one of the legal INVOKE markers
#      per docs/architecture/0005-contracts/02-hook-contracts.md
#      § "Intent-injection markers".
#
# In v1-minimum, intent injection is INTENTIONALLY DEGRADED:
#   - bootstrapping-repo / migrating-repo-version markers are NOT emitted
#     because those skills are deferred to v1-complete. Instead, the hook
#     emits a friendly comment for first-time users so they aren't left
#     wondering what to do.
#
# Output protocol: JSON to stdout per
# https://code.claude.com/docs/en/hooks (additionalContext rides as
# extra system prompt for the session).
#
# The hook MUST exit 0 even when checks fail — non-zero exit blocks the
# session, which is a worse failure mode than an unconfigured plugin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Dep check (best-effort) --------------------------------------------
DEP_OUTPUT=""
if bash "${PLUGIN_ROOT}/scripts/check-deps.sh" >/tmp/bsp-deps-$$.txt 2>&1; then
    DEP_OUTPUT="$(cat /tmp/bsp-deps-$$.txt)"
    DEP_OK="yes"
else
    DEP_OUTPUT="$(cat /tmp/bsp-deps-$$.txt)"
    DEP_OK="no"
fi
rm -f /tmp/bsp-deps-$$.txt

# --- State inspection ---------------------------------------------------
# v1-minimum: we don't yet have a manifest.yml convention; the deferred
# bootstrapping-repo skill defines that. Instead we look for the
# per-repo config.yml as a presence signal.
REPO_ROOT="$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
HAS_CONFIG="no"
if [ -n "${REPO_ROOT}" ] && [ -f "${REPO_ROOT}/.board-superpowers/config.yml" ]; then
    HAS_CONFIG="yes"
fi

# --- Build the additionalContext payload --------------------------------
# Use a heredoc + python escape to avoid jq dependency.
python3 - <<PY
import json
dep_ok = "${DEP_OK}"
has_config = "${HAS_CONFIG}"
dep_output = """${DEP_OUTPUT}"""

lines = ["board-superpowers v0.1.0-minimum loaded."]
if dep_ok != "yes":
    lines.append("⚠️  Dependency check failed:")
    lines.append(dep_output)
    lines.append("Run scripts/check-deps.sh to see what to install.")

if has_config == "no":
    lines.append("")
    lines.append("ℹ️  No .board-superpowers/config.yml in this repo yet.")
    lines.append("   In v1-complete, the bootstrapping-repo skill auto-handles first-time setup.")
    lines.append("   In v1-minimum, set up the GitHub Project + standard labels manually,")
    lines.append("   then create .board-superpowers/config.yml with your project's owner/number.")

# Routing hint — board-superpowers session routing block lives in CLAUDE.md
# / AGENTS.md. The hook does NOT inject INVOKE markers in v1-minimum
# because the deferred entry-skill consumers (bootstrapping-repo /
# migrating-repo-version) don't exist yet. The molecular routing
# (managing-board / consuming-card) is driven by user prompt content,
# not by hook intent injection in v1-minimum.

payload = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "\n".join(lines)
    }
}
print(json.dumps(payload))
PY

exit 0
