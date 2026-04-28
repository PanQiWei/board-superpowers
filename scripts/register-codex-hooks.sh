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

# Codex parity gap (intentional): Codex CLI has no Skill tool that
# fires PostToolUse — the skills are loaded by Codex's runtime, not
# called as a model-facing tool. So the gate's flag-file lifecycle
# (post-tool-use.sh writes flag on Skill, pre-tool-use.sh reads flag
# on Edit/Write) cannot complete on Codex; the gate would block
# without ever clearing. We therefore do NOT register PreToolUse +
# PostToolUse on the Codex side. The Process gate stays
# doctrine-only (skills/AGENTS.md "⛔ STOP" block) on Codex; CC users
# get tool-level enforcement via hooks/hooks.json. See
# docs/architecture/0005-contracts/02-hook-contracts.md § "Codex
# parity gap — gate enforcement".

[ -f "${HOOK_SCRIPT}" ] || bsp_die "hook script not found: ${HOOK_SCRIPT}"

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
print(json.dumps({
    'hooks': {
        'SessionStart': [
            {
                'type': 'command',
                'command': f'bash {sys.argv[1]}',
                'timeout': 10,
                'name': 'board-superpowers'
            }
        ]
    }
}, indent=2))
" "${HOOK_SCRIPT}")"

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
        # hooks, abort on board-superpowers entry already present.
        # Codex registration covers SessionStart only — see top-of-file
        # rationale "Codex parity gap" for why PreToolUse + PostToolUse
        # are not registered on Codex.
        python3 - "${TARGET}" "${HOOK_SCRIPT}" <<'PY'
import json, sys, os, shutil

target, hook_script = sys.argv[1], sys.argv[2]
with open(target) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"existing {target} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)

data.setdefault('hooks', {})
data['hooks'].setdefault('SessionStart', [])

# Idempotency: if a board-superpowers entry already exists, replace it.
existing = [h for h in data['hooks']['SessionStart']
            if h.get('name') == 'board-superpowers']
if existing:
    print(f"replacing existing board-superpowers entry in {target}", file=sys.stderr)
    data['hooks']['SessionStart'] = [
        h for h in data['hooks']['SessionStart']
        if h.get('name') != 'board-superpowers'
    ]

data['hooks']['SessionStart'].append({
    'type': 'command',
    'command': f'bash {hook_script}',
    'timeout': 10,
    'name': 'board-superpowers'
})

# Defensive cleanup: previous register-codex-hooks.sh versions briefly
# also registered PreToolUse + PostToolUse on Codex. Those entries are
# now known to deadlock the Process gate (no Skill tool on Codex →
# flag never written → gate never clears). Remove them on every
# install to drain any pre-existing rollouts.
for stale_event in ('PreToolUse', 'PostToolUse'):
    if stale_event in data['hooks']:
        kept = [h for h in data['hooks'][stale_event]
                if h.get('name') != 'board-superpowers']
        if kept:
            data['hooks'][stale_event] = kept
        else:
            del data['hooks'][stale_event]

# Atomic write: stage to .tmp, then rename.
tmp = target + '.tmp'
backup = target + '.bak'
shutil.copy2(target, backup)
with open(tmp, 'w') as f:
    json.dump(data, f, indent=2)
os.replace(tmp, target)
print(f"updated {target} (backup at {backup})", file=sys.stderr)
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
# Drain SessionStart entries (the canonical Codex registration target)
# AND any stale PreToolUse / PostToolUse entries from a prior rollout
# that briefly registered them — those are known-broken on Codex
# (Codex parity gap; see top-of-file rationale).
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
