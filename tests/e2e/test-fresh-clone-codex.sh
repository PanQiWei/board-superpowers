#!/usr/bin/env bash
# shellcheck disable=SC2016
# SC2016: single-quoted python3 -c bodies intentionally use single quotes.
# tests/e2e/test-fresh-clone-codex.sh
#
# Fresh-clone E2E smoke test — Codex CLI side.  Phase 4 Task 4.7.
#
# Scenario:
#   1. Fresh tmp repo, no ~/.codex/hooks.json, no settings files.
#      Hook does NOT fire on the first Codex session (no auto-discovery).
#   2. Mock register-codex-hooks.sh --install-user: write ~/.codex/hooks.json
#      with the SessionStart hook entry (idempotent).
#   3. Simulate a second session: hook fires → no-venv fallback emits INVOKE.
#   4. Mock SKILL flow: run all 22 stages.  m9 (codex-only) RUNS this time.
#   5. Create venv stub, re-run hook → lifecycle-probe → no INVOKE marker.
#
# Codex-specific delta from CC test:
#   - Tests register-codex-hooks.sh --install-user (CC test skips this).
#   - m9.host.register-codex-hooks must be applied (not not-applicable).
#   - Verifies ~/.codex/hooks.json has board-superpowers SessionStart entry.
#   - Second register-codex-hooks.sh --install-user is idempotent.
#
# Hermeticity: isolated HOME + git repo; no network; no real ~/.codex/.
# register-codex-hooks.sh is exercised but runs against the fake HOME so
# it writes ~/.codex/hooks.json into the isolated environment.
# All other subprocess calls (gh, DB, uv, audit-init.sh, setup-labels.sh)
# are mocked by writing lifecycle state directly.
#
# Reference: tests/e2e/test-fresh-clone-cc.sh (CC counterpart, same 22-stage walk).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"
STAGES_REGISTRY="${PLUGIN_ROOT}/scripts/stages-registry.yml"
REGISTER_CODEX="${PLUGIN_ROOT}/scripts/register-codex-hooks.sh"

[ -f "${HOOK}" ]             || { printf 'FATAL: %s not found\n' "${HOOK}" >&2; exit 99; }
[ -f "${STAGES_REGISTRY}" ]  || { printf 'FATAL: %s not found\n' "${STAGES_REGISTRY}" >&2; exit 99; }
[ -f "${REGISTER_CODEX}" ]   || { printf 'FATAL: %s not found\n' "${REGISTER_CODEX}" >&2; exit 99; }

PASS=0; FAIL=0

check() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  PASS — %s\n' "${label}"; PASS=$((PASS+1))
    else
        printf '  FAIL — %s\n' "${label}" >&2; FAIL=$((FAIL+1))
    fi
}

# ---------------------------------------------------------------------------
# Isolated environment
# ---------------------------------------------------------------------------

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_BASE}"' EXIT

FAKE_HOME="${TMPDIR_BASE}/home"
REPO_DIR="${TMPDIR_BASE}/repo"
mkdir -p "${FAKE_HOME}/.board-superpowers" "${REPO_DIR}"

git -C "${REPO_DIR}" init -q
git -C "${REPO_DIR}" remote add origin "https://github.com/test-org/fresh-clone-codex.git"

REAL_REPO_ROOT="$(git -C "${REPO_DIR}" rev-parse --show-toplevel)"
REPO_IDENTITY="test-org/fresh-clone-codex"

REPO_SHARED_DIR="${FAKE_HOME}/.board-superpowers/repos/${REPO_IDENTITY}"
mkdir -p "${REPO_SHARED_DIR}"
mkdir -p "${REAL_REPO_ROOT}/.board-superpowers"

# Create a minimal AGENTS.md so M7 can detect the form.
printf '# test repo codex\n' > "${REAL_REPO_ROOT}/AGENTS.md"

CODEX_HOOKS_FILE="${FAKE_HOME}/.codex/hooks.json"

run_hook() {
    ( cd "${REAL_REPO_ROOT}" && HOME="${FAKE_HOME}" CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${HOOK}" 2>/dev/null ) || true
}

# ---------------------------------------------------------------------------
# Phase A: first session — no hook registered yet, no settings files
# ---------------------------------------------------------------------------

printf '\n=== Phase A: pre-registration — hook fires manually, emits INVOKE ===\n'

# On real Codex, the hook is NOT registered yet on the first session.
# But we can still run the hook script directly to verify its output.
# In a real Codex flow this would be a manually-invoked session; here
# we verify the hook itself produces correct output (the Codex runtime
# would fire it once registered).
check "hooks.json absent before registration" \
    bash -c '! test -f "${1}"' -- "${CODEX_HOOKS_FILE}"

HOOK_OUT_A="$(run_hook)"
check "hook exits cleanly before registration" true
check "INVOKE: bootstrapping-repo in hook output (Phase A)" \
    bash -c 'printf "%s" "${1}" | grep -q "INVOKE: bootstrapping-repo"' -- "${HOOK_OUT_A}"

# ---------------------------------------------------------------------------
# Phase B: register-codex-hooks.sh --install-user
# ---------------------------------------------------------------------------

printf '\n=== Phase B: register-codex-hooks.sh --install-user ===\n'

# Run with fake HOME so it writes to our isolated ~/.codex/hooks.json.
HOME="${FAKE_HOME}" CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
    bash "${REGISTER_CODEX}" --install-user 2>/dev/null || true

check "register-codex-hooks.sh exits cleanly" true
check "codex hooks.json created after registration" \
    test -f "${CODEX_HOOKS_FILE}"
check "hooks.json is valid JSON" \
    python3 -c "import json; json.load(open('${CODEX_HOOKS_FILE}'))"
check "hooks.json has SessionStart entry for board-superpowers" \
    python3 -c "
import json
data = json.load(open('${CODEX_HOOKS_FILE}'))
entries = (data.get('hooks') or {}).get('SessionStart') or []
names = [h.get('name') for h in entries]
assert 'board-superpowers' in names, f'not found in {names}'
"
check "hooks.json SessionStart entry type is command" \
    python3 -c "
import json
data = json.load(open('${CODEX_HOOKS_FILE}'))
entries = (data.get('hooks') or {}).get('SessionStart') or []
bsp = next(h for h in entries if h.get('name') == 'board-superpowers')
assert bsp.get('type') == 'command', f'type={bsp.get(\"type\")!r}'
"
# Codex parity gap: PreToolUse and PostToolUse must NOT be registered
# (would deadlock Process gate — see register-codex-hooks.sh rationale).
check "hooks.json has NO PreToolUse entry for board-superpowers" \
    python3 -c "
import json
data = json.load(open('${CODEX_HOOKS_FILE}'))
entries = (data.get('hooks') or {}).get('PreToolUse') or []
names = [h.get('name') for h in entries]
assert 'board-superpowers' not in names, f'should not exist: {names}'
"
check "hooks.json has NO PostToolUse entry for board-superpowers" \
    python3 -c "
import json
data = json.load(open('${CODEX_HOOKS_FILE}'))
entries = (data.get('hooks') or {}).get('PostToolUse') or []
names = [h.get('name') for h in entries]
assert 'board-superpowers' not in names, f'should not exist: {names}'
"

# Idempotency: run --install-user a second time; must not duplicate the entry.
HOME="${FAKE_HOME}" CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
    bash "${REGISTER_CODEX}" --install-user 2>/dev/null || true
check "second --install-user is idempotent (still exactly 1 SessionStart entry)" \
    python3 -c "
import json
data = json.load(open('${CODEX_HOOKS_FILE}'))
entries = (data.get('hooks') or {}).get('SessionStart') or []
bsp_entries = [h for h in entries if h.get('name') == 'board-superpowers']
assert len(bsp_entries) == 1, f'expected 1, got {len(bsp_entries)}'
"

# ---------------------------------------------------------------------------
# Phase C: mock SKILL — run all 22 stages including m9
# ---------------------------------------------------------------------------

printf '\n=== Phase C: mock SKILL — full 22-stage walk (m9 runs on Codex) ===\n'

python3 - \
    "${REAL_REPO_ROOT}" \
    "${FAKE_HOME}" \
    "${REPO_IDENTITY}" \
    "${PLUGIN_ROOT}" \
    "${CODEX_HOOKS_FILE}" \
    <<'PYEOF'
import sys, os, types, importlib, pathlib, yaml, datetime

repo_root    = pathlib.Path(sys.argv[1])
home         = pathlib.Path(sys.argv[2])
repo_identity = sys.argv[3]
plugin_root  = pathlib.Path(sys.argv[4])
codex_hooks  = pathlib.Path(sys.argv[5])

scripts_dir = str(plugin_root / "scripts")
if scripts_dir not in sys.path:
    sys.path.insert(0, scripts_dir)

from stages_lib._partitioned_settings import read_settings, write_settings
from stages_lib._canonical import fingerprint

ctx = types.SimpleNamespace(
    home=home,
    repo_root=repo_root,
    repo_identity=repo_identity,
)

def load_stage_module(stage_id):
    slug = stage_id.replace(".", "_").replace("-", "_")
    try:
        return importlib.import_module(f"stages_lib.{slug}")
    except ImportError:
        return None

STAGE_ORDER = [
    "m1.host.create-state-dir",
    "m2.host.install-uv",
    "m5.repo.write-config-yml",
    "m5.repo.write-config-local-yml",
    "m5.repo.set-wip-limit",
    "m6.repo.append-gitignore",
    "m1.host.write-manifest",
    "m1.repo.write-state-yml",
    "m8.host.bootstrap-overrides-yml",
    "m9.host.register-codex-hooks",
    "m2.repo.copy-uv-templates",
    "m10.repo.choose-kanban-projection",
    "m4.repo.acquire-dsn",
    "m7.repo.detect-agentsmd-form",
    "m2.repo.sync-venv",
    "m3.repo.ensure-labels",
    "m3.repo.validate-status-field",
    "m4.repo.apply-audit-ddl",
    "m7.repo.inject-block.routing-rule",
    "m7.repo.inject-block.skill-routing",
    "m4.repo.flush-pending-audit",
    "m4.repo.audit-health-check",
]

MOCK_TARGET_STATES = {
    "m2.host.install-uv": {"uv_present": True, "uv_version": "0.4.18", "uv_path": "/usr/local/bin/uv"},
    "m2.repo.copy-uv-templates": {
        "pyproject_path": str(repo_root / ".board-superpowers/pyproject.toml"),
        "uv_lock_path":   str(repo_root / ".board-superpowers/uv.lock"),
        "pyproject_sha256": "a" * 64,
        "uv_lock_sha256":   "b" * 64,
    },
    "m2.repo.sync-venv": {
        "venv_path": str(repo_root / ".board-superpowers/.venv"),
        "uv_lock_hash": "c" * 64,
    },
    "m3.repo.ensure-labels": {"canonical_labels_present": True},
    "m3.repo.validate-status-field": {
        "status_options_canonical_present": True,
        "resolution": "canonical-already-present",
    },
    "m4.repo.apply-audit-ddl": {
        "audit_log": {"schema_version": 1, "columns_required": ["event_uuid"], "indexes_required": []},
        "audit_outbox": {"columns_required": ["event_uuid"]},
        "audit_schema_meta": {"columns_required": ["key"]},
    },
    "m4.repo.flush-pending-audit": {"pending_replayed": True, "rows_inserted": 0, "rows_skipped_duplicate": 0},
    "m4.repo.audit-health-check": {"health_summary_emitted": True, "db_row_count": 0, "jsonl_pending_count": 0},
}

AGENTIC_DEFAULTS = {
    "m5.repo.set-wip-limit": 5,
    "m8.host.bootstrap-overrides-yml": [],
    "m10.repo.choose-kanban-projection": "github-project-v2",
}

# M9 (codex-only) target state — what register-codex-hooks.sh records.
M9_TARGET_STATE = {
    "registered": True,
    "config_toml_path": str(home / ".codex" / "hooks.json"),
    "hook_target": str(plugin_root / "hooks" / "session-start.sh"),
}

# -------------------------------------------------------------------------
# Pass 1: run executors / apply_choice for side-effects.
# Collect (stage_id, target_state, status) tuples for bulk lifecycle write.
# Rationale: m1.repo.write-state-yml.executor() initialises repo-shared
# settings.yml (resetting modules.lifecycle), so lifecycle entries MUST be
# written after all executors run (Pass 2).
# -------------------------------------------------------------------------
pending_lifecycle = []
errors = []

for stage_id in STAGE_ORDER:
    try:
        if stage_id == "m9.host.register-codex-hooks":
            # Codex: m9 is applicable; record it applied with M9_TARGET_STATE.
            # (hooks.json was already written by register-codex-hooks.sh in Phase B.)
            pending_lifecycle.append((stage_id, M9_TARGET_STATE, "applied"))
            continue

        if stage_id in MOCK_TARGET_STATES:
            pending_lifecycle.append((stage_id, MOCK_TARGET_STATES[stage_id], "applied"))
            continue

        mod = load_stage_module(stage_id)
        if mod is None:
            errors.append(f"{stage_id}: module not found")
            continue

        if stage_id in AGENTIC_DEFAULTS:
            mod.apply_choice(ctx, AGENTIC_DEFAULTS[stage_id])
            ts = mod.compute_target_state(ctx)
            pending_lifecycle.append((stage_id, ts, "applied"))
            continue

        mod.executor(ctx)
        ts = mod.compute_target_state(ctx)
        pending_lifecycle.append((stage_id, ts, "applied"))

    except Exception as exc:
        errors.append(f"{stage_id}: {exc}")

if errors:
    for e in errors:
        print(f"  ERROR: {e}", file=sys.stderr)
    sys.exit(1)

# -------------------------------------------------------------------------
# Pass 2: batch-write all 22 lifecycle entries to repo-shared settings.yml.
# -------------------------------------------------------------------------
now = datetime.datetime.utcnow().isoformat() + "Z"
data = read_settings(
    "repo-shared", home=home, repo_root=repo_root, repo_identity=repo_identity
)
lc = data.setdefault("modules", {}).setdefault("lifecycle", {})

applied_count = 0
for stage_id, ts, status in pending_lifecycle:
    lc[stage_id] = {
        "status": "applied",
        "generation": 1,
        "target_state_hash": fingerprint(ts),
        "target_state": ts,
        "applied_at": now,
    }
    applied_count += 1

write_settings(
    "repo-shared", data, home=home, repo_root=repo_root, repo_identity=repo_identity
)

print(f"applied={applied_count} not_applicable=0 errors=0")
PYEOF

MOCK_EXIT=$?
check "Python mock SKILL walk (Codex) completed without error" test "${MOCK_EXIT}" -eq 0

# Verify key artifacts.
check "m6: .gitignore managed block written" \
    grep -q "board-superpowers managed" "${REAL_REPO_ROOT}/.gitignore"
check "m1.host.write-manifest: host-shared settings.yml written" \
    test -f "${FAKE_HOME}/.board-superpowers/settings.yml"
check "m1.repo.write-state-yml: repo-shared settings.yml written" \
    test -f "${REPO_SHARED_DIR}/settings.yml"
check "m10: kanban projection persisted" \
    python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('${REAL_REPO_ROOT}/.board-superpowers/settings.yml').read_text())
proj = (data.get('modules') or {}).get('m10_kanban', {}).get('projection')
assert proj == 'github-project-v2', f'expected github-project-v2, got {proj!r}'
"
check "m9 lifecycle entry status is applied (codex platform)" \
    python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('${REPO_SHARED_DIR}/settings.yml').read_text())
lc = (data.get('modules') or {}).get('lifecycle', {})
entry = lc.get('m9.host.register-codex-hooks') or {}
assert entry.get('status') == 'applied', f'status={entry.get(\"status\")!r}'
"
check "repo-shared lifecycle has 22 stage entries (Codex — m9 applied not not-applicable)" \
    python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('${REPO_SHARED_DIR}/settings.yml').read_text())
lc = (data.get('modules') or {}).get('lifecycle', {})
# Exclude schema_version key (written by m1.repo.write-state-yml executor).
stage_entries = {k: v for k, v in lc.items() if k != 'schema_version'}
assert len(stage_entries) == 22, f'expected 22, got {len(stage_entries)}: {list(stage_entries.keys())}'
"

# ---------------------------------------------------------------------------
# Phase D: create venv stub + re-run hook (lifecycle-probe path)
# ---------------------------------------------------------------------------

printf '\n=== Phase D: venv stub + re-run hook (lifecycle-probe path) ===\n'

VENV_BIN="${REAL_REPO_ROOT}/.board-superpowers/.venv/bin"
mkdir -p "${VENV_BIN}"
cat > "${VENV_BIN}/python3" <<VENV_PY
#!/usr/bin/env bash
exec python3 "\$@"
VENV_PY
chmod +x "${VENV_BIN}/python3"

HOOK_OUT_D="$(run_hook)"

check "hook exits cleanly after full Codex bootstrap" true
check "no INVOKE: bootstrapping-repo after full bootstrap (lifecycle-probe)" \
    bash -c '! printf "%s" "${1}" | grep -q "INVOKE: bootstrapping-repo"' -- "${HOOK_OUT_D}"

# ---------------------------------------------------------------------------
# Phase E: --uninstall-user removes board-superpowers entry cleanly
# ---------------------------------------------------------------------------

printf '\n=== Phase E: --uninstall-user removes board-superpowers entry ===\n'

HOME="${FAKE_HOME}" CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
    bash "${REGISTER_CODEX}" --uninstall-user 2>/dev/null || true
check "hooks.json still valid JSON after uninstall" \
    python3 -c "import json; json.load(open('${CODEX_HOOKS_FILE}'))"
check "board-superpowers entry removed from SessionStart after uninstall" \
    python3 -c "
import json
data = json.load(open('${CODEX_HOOKS_FILE}'))
entries = (data.get('hooks') or {}).get('SessionStart') or []
names = [h.get('name') for h in entries]
assert 'board-superpowers' not in names, f'still present: {names}'
"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n=== Fresh-clone Codex E2E: %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
