#!/usr/bin/env bash
# hooks/session-start.sh — board-superpowers SessionStart hook (Layer 1).
#
# Fires once per CC / Codex session at startup. Per
# docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md
# § "Hook lifecycle diff" the hook performs TWO roles:
#   (a) dep alert — surface a banner when a dependency is missing or
#       the consuming repo's AGENTS.md / CLAUDE.md lacks the routing block.
#   (b) intent injection — lifecycle-diff-based: runs
#       `python3 -m stages_lib lifecycle-probe` to evaluate all 22 registered
#       stages against persisted state, and emits INVOKE: bootstrapping-repo
#       with the first non-applied stage as REASON. Per ADR-0012, the
#       formerly-deferred migrating-repo-version SKILL is absorbed into
#       bootstrapping-repo as the single executor for setup-stages, so there
#       is only one marker grammar in use.
#
#       GRACEFUL DEGRADATION (fresh-repo no-venv):
#       Before attempting lifecycle-probe, the hook checks whether the
#       per-repo venv (<repo>/.board-superpowers/.venv/bin/python3) exists.
#       If absent the hook falls back to the v0.4.x file-presence heuristic
#       (host-shared settings.yml + repo-shared settings.yml absent → emit
#       INVOKE: bootstrapping-repo with a fresh-repo REASON). This preserves
#       the first-time-user UX without requiring the venv.
#   (c) audit outbox observer — surfaces pending jsonl rows (unchanged).
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
# 05-bootstrap-surface.md § "Cross-cutting principles". A broken
# or missing lib must never prevent session startup. The path
# normalization helper bsp_normalize_repo_path (defined in
# scripts/lib/common.sh) is duplicated INLINE below as
# normalize_repo_path. The primary-repo-root resolver
# bsp_primary_repo_root is duplicated inline as primary_repo_root.
# The REASON-line sanitizer sanitize_reason_line is also duplicated
# inline. Keep the implementations in lockstep —
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

# sanitize_reason_line — per 02-hook-contracts.md § "Intent-injection
# markers" lines 213-216 grammar rule: REASON value is "plain ASCII,
# ≤120 chars, punctuation only `. , ; : - ( )`. No newlines, no JSON,
# no markup." Drop everything outside that whitelist; truncate to 200
# chars (well over the spec's 120-char ceiling, leaves headroom for the
# REASON: prefix accounting elsewhere).
#
# Note: sanitize_dep_name's 32-char truncation is too aggressive for a
# REASON sentence; this helper exists separately. DUPLICATION NOTICE:
# duplicated as bsp_sanitize_reason_line in scripts/lib/common.sh —
# keep the two implementations in lockstep per the self-containment
# contract.
sanitize_reason_line() {
    local raw="${1:-}"
    LC_ALL=C printf '%s' "${raw}" \
        | LC_ALL=C tr -cd 'a-zA-Z0-9 .,;:\-()' \
        | head -c 200
}

# primary_repo_root — resolve PWD to the absolute path of the PRIMARY
# repo root, NOT the worktree root. From inside a `git worktree`,
# `git rev-parse --show-toplevel` returns the worktree path; that
# path normalizes to a different `<normalized>` than the canonical
# repo, so the hook's per-repo state.yml lookup misses and the hook
# falsely emits INVOKE: bootstrapping-repo for an already-bootstrapped
# repo. This helper uses `git rev-parse --git-common-dir` (which
# always points at the primary repo's .git/ regardless of worktree
# vs primary) and walks up one level to the primary working tree.
#
# Args: <cwd>
# Stdout: absolute primary-repo-root path on success; nothing on failure.
# Returns: 0 on success, 1 if not in a git repo (caller should fall
#   back to `pwd -P`).
#
# DUPLICATION NOTICE: duplicated as bsp_primary_repo_root in
# scripts/lib/common.sh — keep the two implementations in lockstep
# per the self-containment contract (02-hook-contracts.md
# § "Self-containment" lines 295-303).
primary_repo_root() {
    local cwd="${1:-${PWD}}"
    command -v git >/dev/null 2>&1 || return 1
    local common_dir
    common_dir="$(git -C "${cwd}" rev-parse --git-common-dir 2>/dev/null || true)"
    [ -n "${common_dir}" ] || return 1
    # --git-common-dir may return absolute or relative; canonicalize.
    case "${common_dir}" in
        /*) ;;
        *) common_dir="${cwd}/${common_dir}" ;;
    esac
    # `dirname` of the primary `.git/` directory is the primary
    # working tree. Run through `pwd -P` to resolve symlinks (macOS
    # /var → /private/var bites here otherwise).
    (cd "$(dirname "${common_dir}")" 2>/dev/null && pwd -P) || return 1
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

# --- Layer 1b: lifecycle-diff intent injection (REWRITE from v0.4.x) -----
# Per 05-bootstrap-surface.md § "Hook lifecycle diff" and ADR-0012.
#
# v0.5.0+ behavior:
#   1. Resolve primary repo root (worktree-safe, same as before).
#   2. Fresh-repo no-venv graceful degradation: if the per-repo venv is
#      absent → emit INVOKE: bootstrapping-repo immediately (same UX as
#      v0.4.x; no Python lifecycle needed).
#   3. If venv present → invoke `python3 -m stages_lib lifecycle-probe`
#      from the venv to evaluate all 22 registered stages.
#      The probe returns one of:
#        INVOKE: bootstrapping-repo\nREASON: <stage_id> is <state>...
#        (or nothing if all stages are applied / not-applicable)
#   4. Append the probe output to LINES if non-empty.
#
# The lifecycle-probe subcommand lives in scripts/stages_lib/__main__.py
# and is invoked as `python3 -m stages_lib lifecycle-probe ...`.  This
# choice keeps the hook bash side minimal and puts all lifecycle logic in
# testable Python.
#
# SELF-CONTAINED: this layer still MUST NOT source common.sh. The inline
# bsp_repo_identity equivalent (git remote get-url origin → python3 parse)
# is replicated inline below per the self-containment contract. Keep in
# lockstep with bsp_repo_identity in scripts/lib/common.sh.
#
# REASON grammar (02-hook-contracts.md lines 213-216):
#   plain ASCII, ≤120 chars, punctuation only `. , ; : - ( )`.
#   No newlines, no JSON, no markup.
# The lifecycle-probe sanitizes its own REASON output before returning it;
# this hook emits the probe's line verbatim (the probe is trusted output
# from our own Python, same-process sanitization).

# Resolve PWD to the PRIMARY repo root, not a worktree root.
# `git rev-parse --show-toplevel` returns the worktree path when run
# inside a worktree; use primary_repo_root() defined above to find the
# canonical repo root regardless.
REPO_ROOT=""
if REPO_ROOT="$(primary_repo_root "${PWD}")" && [ -n "${REPO_ROOT}" ]; then
    :
else
    REPO_ROOT=""
fi

# --- Fresh-repo / no-venv graceful degradation ----------------------------
# If the per-repo venv is absent (bootstrap has never run), fall back to
# the v0.4.x file-presence heuristic. The lifecycle-probe requires PyYAML
# (from the venv); without it we cannot evaluate stages. Emitting
# INVOKE: bootstrapping-repo without lifecycle eval is correct here —
# the venv's absence is itself a "not bootstrapped" signal.
#
# Per v0.5.0 schema, the host-level settings.yml replaces manifest.yml, and
# the repo-shared settings.yml replaces state.yml. We check both to preserve
# the v0.4.x two-condition (host + repo) first-time-user experience.
VENV_PYTHON=""
if [ -n "${REPO_ROOT}" ]; then
    CANDIDATE="${REPO_ROOT}/.board-superpowers/.venv/bin/python3"
    if [ -x "${CANDIDATE}" ]; then
        VENV_PYTHON="${CANDIDATE}"
    fi
fi

LIFECYCLE_INVOKE=""  # will hold "INVOKE: bootstrapping-repo\nREASON: ..." or ""

if [ -z "${VENV_PYTHON}" ]; then
    # No venv — fresh repo or incomplete M2 bootstrap.
    # Check v0.5.0 settings.yml presence (host-shared + repo-shared).
    # Per ADR-0024 Part A: host-shared = ~/.board-superpowers/settings.yml;
    # repo-shared = ~/.board-superpowers/repos/<normalized>/settings.yml.
    # We check repo-shared using the NORMALIZED path helper for consistency
    # with the v0.4.x logic that was previously here.
    HOST_SETTINGS="${HOME}/.board-superpowers/settings.yml"
    HOST_SETTINGS_PRESENT="no"
    if [ -f "${HOST_SETTINGS}" ]; then
        HOST_SETTINGS_PRESENT="yes"
    fi
    # Also accept legacy manifest.yml (v0.4.x install still in use)
    if [ -f "${HOME}/.board-superpowers/manifest.yml" ]; then
        HOST_SETTINGS_PRESENT="yes"
    fi

    REPO_SETTINGS_PRESENT="yes"
    if [ -n "${REPO_ROOT}" ]; then
        NORMALIZED="$(normalize_repo_path "${REPO_ROOT}" 2>/dev/null || true)"
        if [ -n "${NORMALIZED}" ]; then
            REPO_SETTINGS="${HOME}/.board-superpowers/repos/${NORMALIZED}/settings.yml"
            # Also check legacy state.yml path
            REPO_STATE="${HOME}/.board-superpowers/repos/${NORMALIZED}/state.yml"
            if [ -f "${REPO_SETTINGS}" ] || [ -f "${REPO_STATE}" ]; then
                REPO_SETTINGS_PRESENT="yes"
            else
                REPO_SETTINGS_PRESENT="no"
            fi
        fi
    fi

    if [ "${HOST_SETTINGS_PRESENT}" = "no" ] || [ "${REPO_SETTINGS_PRESENT}" = "no" ]; then
        raw_reason=""
        if [ "${HOST_SETTINGS_PRESENT}" = "no" ] && [ "${REPO_SETTINGS_PRESENT}" = "no" ]; then
            raw_reason="fresh repo - host and per-repo settings absent; venv not yet created."
        elif [ "${HOST_SETTINGS_PRESENT}" = "no" ]; then
            raw_reason="host bootstrap pending; host-shared settings absent; venv not yet created."
        else
            raw_reason="per-repo bootstrap pending; repo-shared settings absent; venv not yet created."
        fi
        LIFECYCLE_INVOKE="$(printf 'INVOKE: bootstrapping-repo\nREASON: %s' \
            "$(sanitize_reason_line "${raw_reason}")")"
    fi
else
    # Venv present — run full lifecycle-diff probe.
    # Resolve repo_identity inline (MUST NOT source common.sh).
    # Inline equivalent of bsp_repo_identity: parse git remote URL with python3.
    # DUPLICATION NOTICE: keep in lockstep with bsp_repo_identity in
    # scripts/lib/common.sh per the self-containment contract.
    REPO_IDENTITY=""
    if [ -n "${REPO_ROOT}" ] && command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        ORIGIN_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
        if [ -n "${ORIGIN_URL}" ]; then
            REPO_IDENTITY="$(printf '%s' "${ORIGIN_URL}" | python3 -c '
import re, sys
url = sys.stdin.read().strip()
url = re.sub(r"\.git$", "", url)
m = re.search(r"github\.com[:/](.+/[^/]+)$", url)
if m:
    print(m.group(1).lower())
    sys.exit(0)
parts = re.split(r"[:/]", url.rstrip("/"))
if len(parts) >= 2:
    print("/".join(parts[-2:]).lower())
    sys.exit(0)
sys.exit(1)
' 2>/dev/null || true)"
        fi
    fi
    # Fallback: use normalized repo path as identity if git remote unavailable.
    if [ -z "${REPO_IDENTITY}" ] && [ -n "${REPO_ROOT}" ]; then
        REPO_IDENTITY="$(normalize_repo_path "${REPO_ROOT}" 2>/dev/null || true)"
    fi

    if [ -n "${REPO_ROOT}" ] && [ -n "${REPO_IDENTITY}" ]; then
        # Invoke lifecycle-probe via the venv Python.
        # The probe returns "INVOKE: bootstrapping-repo\nREASON: ..." or empty.
        # The venv Python is invoked with PYTHONPATH set to scripts/ so that
        # `python3 -m stages_lib` resolves against the plugin's stages_lib package.
        RAW_PROBE="$(PYTHONPATH="${PLUGIN_ROOT}/scripts" "${VENV_PYTHON}" -m stages_lib lifecycle-probe \
            --plugin-root "${PLUGIN_ROOT}" \
            --home "${HOME}" \
            --repo-root "${REPO_ROOT}" \
            --repo-identity "${REPO_IDENTITY}" \
            2>/dev/null || true)"
        if [ -n "${RAW_PROBE}" ]; then
            LIFECYCLE_INVOKE="${RAW_PROBE}"
        fi
    fi
fi

# --- Build the additionalContext payload --------------------------------
# Order, per 02-hook-contracts.md "additionalContext body":
#   1. Version banner (always).
#   2. Dep / routing alert (when something is wrong) — most urgent.
#   3. Intent-injection marker (at most one, from lifecycle diff above).
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
# 02-hook-contracts.md line 218-222). LIFECYCLE_INVOKE holds the probe
# output (two-line "INVOKE: ...\nREASON: ..." or "").
if [ -n "${LIFECYCLE_INVOKE}" ]; then
    LINES+=("")
    # Append each line of the two-line marker separately so the joined
    # output preserves the "INVOKE: ...\nREASON: ..." line structure.
    while IFS= read -r invoke_line; do
        LINES+=("${invoke_line}")
    done <<< "${LIFECYCLE_INVOKE}"
fi

# --- Layer 1c: audit outbox observer (Task 7 / AC4) --------------------
# Self-contained: NO source common.sh (per 02-hook-contracts.md
# § "Self-containment"). Observer-only — emits a dep-alert text block
# when the wakeup sentinel is present. Does NOT call
# audit-flush-pending.sh because flush latency (DB INSERT round trip)
# is incompatible with the 10s hook budget.
#
# Implementation uses only file stat + integer arithmetic; no helper
# from common.sh is required, so the self-containment contract holds.
# All filesystem accesses use `|| true` shape so a transient stat
# error degrades to a silent no-op rather than blocking session start.
SENTINEL="${HOME}/.board-superpowers/audit-pending.sentinel"
LAST_FLUSH_FILE="${HOME}/.board-superpowers/audit-last-flush"
if [ -f "${SENTINEL}" ]; then
    NOW_SEC="$(date +%s 2>/dev/null || echo 0)"
    LAST_FLUSH_SEC="0"
    if [ -r "${LAST_FLUSH_FILE}" ]; then
        LAST_FLUSH_SEC="$(head -n1 "${LAST_FLUSH_FILE}" 2>/dev/null || echo 0)"
    fi
    # Defensive: any non-numeric content collapses to 0 so the age
    # math below cannot crash the hook.
    case "${LAST_FLUSH_SEC}" in
        ''|*[!0-9]*) LAST_FLUSH_SEC=0 ;;
    esac
    case "${NOW_SEC}" in
        ''|*[!0-9]*) NOW_SEC=0 ;;
    esac
    if [ "${LAST_FLUSH_SEC}" -gt 0 ] && [ "${NOW_SEC}" -ge "${LAST_FLUSH_SEC}" ]; then
        AGE_MIN=$(( (NOW_SEC - LAST_FLUSH_SEC) / 60 ))
    else
        AGE_MIN=-1
    fi
    LINES+=("")
    if [ "${AGE_MIN}" -ge 0 ]; then
        LINES+=("audit-pending: outbox has unflushed rows (last flush ${AGE_MIN}m ago); run scripts/audit-flush-pending.sh to drain manually.")
    else
        LINES+=("audit-pending: outbox has unflushed rows; run scripts/audit-flush-pending.sh to drain manually.")
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
