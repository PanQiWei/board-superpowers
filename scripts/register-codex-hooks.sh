#!/usr/bin/env bash
# scripts/register-codex-hooks.sh — register board-superpowers SessionStart
# hook into a Codex CLI configuration.
#
# Why this exists: Claude Code auto-discovers <plugin-root>/hooks/hooks.json.
# Codex CLI does NOT — Codex hooks must live in ~/.codex/hooks.json (user
# scope) or <repo>/.codex/hooks.json (per-repo scope, requires repo trust).
# The plugin can't auto-register; the user runs this script once after
# installing the plugin on Codex.
#
# Usage:
#   bash scripts/register-codex-hooks.sh                 # print snippet + instructions
#   bash scripts/register-codex-hooks.sh --install-user  # merge into ~/.codex/hooks.json
#   bash scripts/register-codex-hooks.sh --install-repo  # write to ./.codex/hooks.json
#   bash scripts/register-codex-hooks.sh --uninstall-user # remove from ~/.codex/hooks.json
#
# Exit codes: 0 OK, 1 bad args / config conflict / write error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

PLUGIN_ROOT="$(bsp_plugin_root)"
HOOK_SCRIPT="${PLUGIN_ROOT}/hooks/session-start.sh"
PRE_TOOL_HOOK="${PLUGIN_ROOT}/hooks/pre-tool-use.sh"
POST_TOOL_HOOK="${PLUGIN_ROOT}/hooks/post-tool-use.sh"

[ -f "${HOOK_SCRIPT}" ]    || bsp_die "hook script not found: ${HOOK_SCRIPT}"
[ -f "${PRE_TOOL_HOOK}" ]  || bsp_die "hook script not found: ${PRE_TOOL_HOOK}"
[ -f "${POST_TOOL_HOOK}" ] || bsp_die "hook script not found: ${POST_TOOL_HOOK}"

bsp_require_cmd python3

MODE="print"
case "${1:-}" in
    "")                MODE="print" ;;
    --install-user)    MODE="install-user" ;;
    --install-repo)    MODE="install-repo" ;;
    --uninstall-user)  MODE="uninstall-user" ;;
    -h|--help)
        sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
        exit 0
        ;;
    *) bsp_die "unknown arg: $1 (try --help)" ;;
esac

# --- Snippet generation -------------------------------------------------
#
# Codex hooks.json format mirrors CC's hooks.json closely. Per
# <https://developers.openai.com/codex/hooks>:
#   - top-level "hooks" object keyed by event name
#   - each event maps to an array of hook configs
#   - hook config has "type" (command | http | mcp) and event-specific fields
#
# We register the same SessionStart shell hook CC uses, but with the
# absolute path baked in (Codex has no ${CLAUDE_PLUGIN_ROOT} equivalent).

SNIPPET="$(python3 -c "
import json, sys
session_hook, pre_hook, post_hook = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    'hooks': {
        'SessionStart': [
            {
                'type': 'command',
                'command': f'bash {session_hook}',
                'timeout': 10,
                'name': 'board-superpowers'
            }
        ],
        'PreToolUse': [
            {
                'type': 'command',
                'command': f'bash {pre_hook}',
                'matcher': matcher,
                'timeout': 5,
                'name': 'board-superpowers'
            }
            for matcher in ('Edit', 'Write', 'MultiEdit')
        ],
        'PostToolUse': [
            {
                'type': 'command',
                'command': f'bash {post_hook}',
                'matcher': 'Skill',
                'timeout': 5,
                'name': 'board-superpowers'
            }
        ]
    }
}, indent=2))
" "${HOOK_SCRIPT}" "${PRE_TOOL_HOOK}" "${POST_TOOL_HOOK}")"

case "${MODE}" in
    print)
        cat <<EOF
board-superpowers Codex hook registration snippet
=================================================

Append the following to ~/.codex/hooks.json (user scope) OR
<your-repo>/.codex/hooks.json (per-repo scope, requires trust).
If the file already exists, merge the "hooks" entries — do NOT
overwrite other plugins' hooks.

For automatic merge:
  bash ${BASH_SOURCE[0]} --install-user      # ~/.codex/hooks.json
  bash ${BASH_SOURCE[0]} --install-repo      # ./.codex/hooks.json

Manual snippet:

${SNIPPET}

After installing, verify by opening a fresh Codex session in any repo:
  codex
The board-superpowers status banner should appear in the session's
initial context. If it doesn't, check ~/.codex/hooks.json syntax with
'python3 -m json.tool ~/.codex/hooks.json'.
EOF
        ;;

    install-user|install-repo)
        if [ "${MODE}" = "install-user" ]; then
            TARGET="${HOME}/.codex/hooks.json"
        else
            TARGET="$(pwd)/.codex/hooks.json"
        fi
        mkdir -p "$(dirname "${TARGET}")"

        if [ ! -f "${TARGET}" ]; then
            bsp_log "creating new ${TARGET}"
            printf '%s\n' "${SNIPPET}" > "${TARGET}"
            bsp_log "registered. Test with: codex (open a fresh session)"
            exit 0
        fi

        # Merge into existing file. Use python to preserve other plugins'
        # hooks; idempotently replace any existing board-superpowers entries
        # across all three events (SessionStart + PreToolUse + PostToolUse).
        python3 - "${TARGET}" "${HOOK_SCRIPT}" "${PRE_TOOL_HOOK}" "${POST_TOOL_HOOK}" <<'PY'
import json, sys, os, shutil

target, session_hook, pre_hook, post_hook = sys.argv[1:5]
with open(target) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"existing {target} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)

# Define the full set of board-superpowers entries to install.
bsp_entries = {
    'SessionStart': [
        {'type': 'command', 'command': f'bash {session_hook}',
         'timeout': 10, 'name': 'board-superpowers'},
    ],
    'PreToolUse': [
        {'type': 'command', 'command': f'bash {pre_hook}',
         'matcher': matcher, 'timeout': 5,
         'name': 'board-superpowers'}
        for matcher in ('Edit', 'Write', 'MultiEdit')
    ],
    'PostToolUse': [
        {'type': 'command', 'command': f'bash {post_hook}',
         'matcher': 'Skill', 'timeout': 5,
         'name': 'board-superpowers'},
    ],
}

data.setdefault('hooks', {})
for event, entries in bsp_entries.items():
    data['hooks'].setdefault(event, [])
    # Idempotency: drop any existing board-superpowers entries for this event.
    data['hooks'][event] = [
        h for h in data['hooks'][event]
        if h.get('name') != 'board-superpowers'
    ]
    data['hooks'][event].extend(entries)

# Atomic write: stage to .tmp, then rename.
tmp = target + '.tmp'
backup = target + '.bak'
shutil.copy2(target, backup)
with open(tmp, 'w') as f:
    json.dump(data, f, indent=2)
os.replace(tmp, target)
print(f"updated {target} with 3 events (backup at {backup})", file=sys.stderr)
PY
        bsp_log "registered. Test with: codex (open a fresh session)"
        ;;

    uninstall-user)
        TARGET="${HOME}/.codex/hooks.json"
        if [ ! -f "${TARGET}" ]; then
            bsp_log "no ${TARGET} — nothing to uninstall"
            exit 0
        fi
        python3 - "${TARGET}" <<'PY'
import json, sys, os, shutil
target = sys.argv[1]
with open(target) as f:
    data = json.load(f)
hooks_block = data.get('hooks') or {}
removed_count = 0
for event in ('SessionStart', 'PreToolUse', 'PostToolUse'):
    entries = hooks_block.get(event, [])
    before = len(entries)
    kept = [h for h in entries if h.get('name') != 'board-superpowers']
    removed_count += before - len(kept)
    if kept:
        hooks_block[event] = kept
    elif event in hooks_block:
        # Empty after removal — drop the key entirely.
        del hooks_block[event]
if removed_count == 0:
    print(f"no board-superpowers entry found in {target}", file=sys.stderr)
    sys.exit(0)
if hooks_block:
    data['hooks'] = hooks_block
elif 'hooks' in data:
    del data['hooks']
backup = target + '.bak'
shutil.copy2(target, backup)
tmp = target + '.tmp'
with open(tmp, 'w') as f:
    json.dump(data, f, indent=2)
os.replace(tmp, target)
print(f"removed {removed_count} board-superpowers entry/entries from {target} (backup at {backup})", file=sys.stderr)
PY
        ;;
esac
