#!/usr/bin/env bash
# hooks/session-start.sh — board-superpowers SessionStart hook (Layer 1).
#
# Fires once per CC / Codex session at startup. Per
# docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § "three-layer alert + intent-injection strategy" the hook performs
# TWO roles:
#   (a) dep alert — surface a banner when a dependency is missing or
#       the consuming repo's AGENTS.md / CLAUDE.md lacks the routing block.
#   (b) intent injection — when on-disk state implies a specific
#       skill should be invoked, emit one of the legal markers per
#       docs/architecture/0005-contracts/02-hook-contracts.md
#       § "Intent-injection markers". v0.2.0 emits only
#       INVOKE: bootstrapping-repo (manifest.yml or per-repo state.yml
#       absent). INVOKE: migrating-repo-version is reserved for a future
#       slice once schema-aware version comparison ships.
#
# Output protocol: ONE JSON object on stdout per
# https://code.claude.com/docs/en/hooks (additionalContext rides as
# extra system prompt for the session).
#
# The hook MUST exit 0 even when checks fail — non-zero exit blocks
# the session, which is a worse failure mode than an unconfigured
# plugin. Per 02-hook-contracts.md § "Exit codes": "board-superpowers'
# invariant: hook failures MUST NEVER block session start."
#
# SELF-CONTAINED: this script MUST NOT source scripts/lib/common.sh,
# per 02-hook-contracts.md § "Self-containment" (line 297-298) and
# 05-bootstrap-surface.md § "Cross-cutting principles". A broken or
# missing lib must never prevent session startup. The path
# normalization helper bsp_normalize_repo_path (defined in
# scripts/lib/common.sh) is duplicated INLINE below as
# normalize_repo_path. Keep the two implementations in lockstep —
# DO NOT deduplicate by sourcing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# --- Inline helpers (intentionally NOT sourced from scripts/lib/common.sh)

# normalize_repo_path — duplicate of bsp_normalize_repo_path in
# scripts/lib/common.sh. Per spec the hook is self-contained; do not
# refactor by sourcing common.sh. Strip leading "/", replace remaining
# "/" with "-". Defensive trailing-slash strip.
normalize_repo_path() {
    local p="${1:-}"
    [ -n "${p}" ] || return 1
    case "${p}" in
        /*) ;;
        *) return 1 ;;
    esac
    p="${p%/}"
    p="${p#/}"
    printf '%s\n' "${p//\//-}"
}

# sanitize_dep_name — per 02-hook-contracts.md § "Sanitization
# expectation". Replace any char outside [a-zA-Z0-9_-] with `-`,
# truncate to 32 chars, drop the value entirely if it has no
# alphanumeric content.
sanitize_dep_name() {
    local raw="${1:-}"
    # Replace non-allowed chars with `-`.
    local cleaned
    cleaned="$(printf '%s' "${raw}" | LC_ALL=C tr -c 'a-zA-Z0-9_-' '-')"
    # Truncate to 32 chars.
    cleaned="${cleaned:0:32}"
    # Drop if no alphanumeric content.
    case "${cleaned}" in
        *[a-zA-Z0-9]*) printf '%s' "${cleaned}" ;;
        *) return 1 ;;
    esac
}

# NOTE: 02-hook-contracts.md § "Sanitization expectation" cites a
# pure-bash json_escape_string helper. We delegate JSON shaping to
# Python's json.dumps below (which handles RFC 8259 §7 quoting,
# control-char escaping, and \uXXXX for non-ASCII automatically), so
# no shell-side escaper is needed. The sanitize_dep_name helper
# above guards against control chars / markup leaking into
# additionalContext at the value-extraction layer; json.dumps then
# serializes the resulting string safely.

# --- Plugin version (read from plugin.json; default to "unknown") ------
PLUGIN_VERSION="unknown"
PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
if [ -r "${PLUGIN_JSON}" ] && command -v python3 >/dev/null 2>&1; then
    PLUGIN_VERSION="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get("version", "unknown"))
except Exception:
    print("unknown")
' "${PLUGIN_JSON}" 2>/dev/null || printf 'unknown')"
fi

# --- Layer 1a: dep check (best-effort) ---------------------------------
# Use --machine mode per 01-script-contracts.md so we get structured
# output. Exit code is always 0 in machine mode; stdout is empty when
# all is well, three lines (MISSING= / ROUTING_INJECTED= / PROJECT=)
# when something is wrong.
DEP_RAW=""
DEP_SCRIPT="${PLUGIN_ROOT}/scripts/check-deps.sh"
if [ -x "${DEP_SCRIPT}" ] || [ -r "${DEP_SCRIPT}" ]; then
    DEP_RAW="$(bash "${DEP_SCRIPT}" --machine 2>/dev/null || true)"
fi

DEP_MISSING=""
DEP_ROUTING="yes"
if [ -n "${DEP_RAW}" ]; then
    while IFS= read -r line; do
        case "${line}" in
            MISSING=*) DEP_MISSING="${line#MISSING=}" ;;
            ROUTING_INJECTED=*) DEP_ROUTING="${line#ROUTING_INJECTED=}" ;;
            PROJECT=*) ;;
        esac
    done <<< "${DEP_RAW}"
fi

# --- Layer 1b: state probe ---------------------------------------------
# Per 05-bootstrap-surface.md § "State files":
#   ~/.board-superpowers/manifest.yml             → manifest_present
#   ~/.board-superpowers/repos/<normalized>/state.yml → state_present
#
# <normalized> derives from the repo root via the inline helper above.
# A non-git working directory yields no state probe (state_present=yes
# defensively — the hook only INVOKEs bootstrapping-repo when we are
# certain a repo bootstrap is missing).

REPO_ROOT=""
if command -v git >/dev/null 2>&1; then
    REPO_ROOT="$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
fi

MANIFEST_PRESENT="no"
if [ -f "${HOME}/.board-superpowers/manifest.yml" ]; then
    MANIFEST_PRESENT="yes"
fi

STATE_PRESENT="yes"
NORMALIZED=""
if [ -n "${REPO_ROOT}" ]; then
    if NORMALIZED="$(normalize_repo_path "${REPO_ROOT}" 2>/dev/null)"; then
        if [ -f "${HOME}/.board-superpowers/repos/${NORMALIZED}/state.yml" ]; then
            STATE_PRESENT="yes"
        else
            STATE_PRESENT="no"
        fi
    fi
fi

# --- Build the additionalContext payload --------------------------------
# Order, per 02-hook-contracts.md "additionalContext body":
#   1. Version banner (always).
#   2. Dep / routing alert (when something is wrong) — most urgent.
#   3. Intent-injection marker (when state files absent) — at most one.
LINES=()
LINES+=("board-superpowers v${PLUGIN_VERSION} loaded.")

if [ -n "${DEP_MISSING}" ] || [ "${DEP_ROUTING}" = "no" ]; then
    LINES+=("")
    LINES+=("⚠️  dependency check or routing-block issue detected.")
    if [ -n "${DEP_MISSING}" ]; then
        # Sanitize each comma-separated dep name before interpolating.
        clean_csv=""
        IFS=',' read -ra raw_parts <<< "${DEP_MISSING}"
        for raw in "${raw_parts[@]}"; do
            if clean="$(sanitize_dep_name "${raw}")" && [ -n "${clean}" ]; then
                if [ -n "${clean_csv}" ]; then
                    clean_csv="${clean_csv},${clean}"
                fi
                if [ -z "${clean_csv}" ]; then
                    clean_csv="${clean}"
                fi
            fi
        done
        if [ -n "${clean_csv}" ]; then
            LINES+=("Missing: ${clean_csv}")
        fi
    fi
    if [ "${DEP_ROUTING}" = "no" ]; then
        LINES+=("Routing block missing from AGENTS.md / CLAUDE.md.")
    fi
    LINES+=("Run scripts/check-deps.sh for details.")
fi

# Intent-injection marker: at most one INVOKE: per payload (per
# 02-hook-contracts.md line 218-222). manifest absent or state.yml
# absent both route to bootstrapping-repo; pick a single REASON line.
if [ "${MANIFEST_PRESENT}" = "no" ] || [ "${STATE_PRESENT}" = "no" ]; then
    LINES+=("")
    LINES+=("INVOKE: bootstrapping-repo")
    if [ "${MANIFEST_PRESENT}" = "no" ]; then
        LINES+=("REASON: ~/.board-superpowers/manifest.yml absent (host bootstrap pending).")
    else
        LINES+=("REASON: per-repo state.yml absent for this (host, repo) pair.")
    fi
fi

# --- Emit JSON via Python (RFC 8259 quoting) ---------------------------
# Python is part of our dep set; if it is missing, the hook silently
# no-ops (we don't have a JSON-emitter fallback and emitting hand-
# escaped JSON without python is fragile per the inline json_escape
# helper above — which we use only for status-line interpolation, not
# top-level JSON shape).
if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

joined=""
for ln in "${LINES[@]}"; do
    if [ -z "${joined}" ]; then
        joined="${ln}"
    else
        joined="${joined}"$'\n'"${ln}"
    fi
done

PAYLOAD_TEXT="${joined}" python3 - <<'PY' || true
import json, os, sys
text = os.environ.get("PAYLOAD_TEXT", "")
out = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": text,
    }
}
sys.stdout.write(json.dumps(out))
sys.stdout.write("\n")
PY

exit 0
