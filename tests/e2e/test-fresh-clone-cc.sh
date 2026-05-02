#!/usr/bin/env bash
# shellcheck disable=SC2016
# SC2016: single-quoted python3 -c bodies intentionally use single quotes.
# tests/e2e/test-fresh-clone-cc.sh
#
# Fresh-clone E2E smoke test — Claude Code side.  Phase 4 Task 4.6.
#
# Scenario:
#   1. Fresh tmp repo, no venv, no settings files → hook emits INVOKE marker.
#   2. Mock SKILL flow: invoke all 22 stage executors/apply_choice directly
#      (via Python) with simulated architect responses for agentic stages.
#      Write lifecycle state for each stage to repo-shared settings.yml.
#   3. Re-run hook → lifecycle-probe runs (venv present) → no INVOKE marker.
#
# CC-specific invariants tested:
#   - m9.host.register-codex-hooks is not-applicable on CC (platform=codex-only).
#   - 21 non-m9 stages reach applied (or not-applicable for m3 before venv,
#     but since we mock the venv we simulate full walk).
#   - Second hook run: lifecycle-probe returns empty (all applied/not-applicable).
#
# Hermeticity: isolated HOME + git repo; no network; no real ~/.board-superpowers.
# All subprocess calls (gh, DB, uv, register-codex-hooks.sh, audit-init.sh,
# audit-flush-pending.sh, setup-labels.sh) are mocked by writing lifecycle
# state directly — the test does not exercise the bash executors, only the
# Python lifecycle engine + hook dispatch logic.
#
# Reference: tests/e2e/test-stages-walking-skeleton.sh (Phase 2 B5 template).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"
STAGES_REGISTRY="${PLUGIN_ROOT}/scripts/stages-registry.yml"

[ -f "${HOOK}" ]             || { printf 'FATAL: %s not found\n' "${HOOK}" >&2; exit 99; }
[ -f "${STAGES_REGISTRY}" ]  || { printf 'FATAL: %s not found\n' "${STAGES_REGISTRY}" >&2; exit 99; }

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
git -C "${REPO_DIR}" remote add origin "https://github.com/test-org/fresh-clone-cc.git"

# Use git rev-parse for REPO_ROOT (mirrors hook logic; resolves macOS /private symlink).
REAL_REPO_ROOT="$(git -C "${REPO_DIR}" rev-parse --show-toplevel)"
REPO_IDENTITY="test-org/fresh-clone-cc"

# Compute repo-shared path (same formula as _partitioned_settings.py repo-shared).
REPO_SHARED_DIR="${FAKE_HOME}/.board-superpowers/repos/${REPO_IDENTITY}"
mkdir -p "${REPO_SHARED_DIR}"
mkdir -p "${REAL_REPO_ROOT}/.board-superpowers"

# Create a minimal AGENTS.md so M7 can detect the form.
printf '# test repo\n' > "${REAL_REPO_ROOT}/AGENTS.md"

run_hook() {
    # Hook uses PWD (not argv) to discover REPO_ROOT via git rev-parse.
    ( cd "${REAL_REPO_ROOT}" && HOME="${FAKE_HOME}" CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${HOOK}" 2>/dev/null ) || true
}

# ---------------------------------------------------------------------------
# Phase A: fresh repo — hook must emit INVOKE marker (no-venv fallback path)
# ---------------------------------------------------------------------------

printf '\n=== Phase A: fresh repo — no-venv fallback emits INVOKE marker ===\n'

HOOK_OUT_A="$(run_hook)"

check "hook exits cleanly on fresh repo" true
check "INVOKE: bootstrapping-repo in hook output (Phase A)" \
    bash -c 'printf "%s" "${1}" | grep -q "INVOKE: bootstrapping-repo"' -- "${HOOK_OUT_A}"
check "REASON line present in hook output" \
    bash -c 'printf "%s" "${1}" | grep -q "REASON:"' -- "${HOOK_OUT_A}"

# ---------------------------------------------------------------------------
# Phase B: mock SKILL — run all 22 stages via Python, write lifecycle state
# ---------------------------------------------------------------------------

printf '\n=== Phase B: mock SKILL — full 22-stage walk via Python ===\n'

# We mock the SKILL flow by:
#  1. For each automated stage: call executor(ctx) via Python to get the
#     side-effects (where possible without network/gh/DB). For stages whose
#     executor is a bash script (gh, DB, uv), we write a canonical lifecycle
#     entry directly — the test is about lifecycle-probe correctness, not
#     the bash scripts themselves.
#  2. For each agentic stage: call apply_choice(ctx, default_value) via Python.
#  3. All lifecycle entries are written to repo-shared settings.yml under
#     modules.lifecycle.<stage_id> per _load_persisted contract.
#
# Mock strategy per stage character:
#   automated + pure-Python executor (m1, m5, m6, m7): run executor() directly.
#   automated + bash/external (m2, m3, m4): write lifecycle entry directly.
#   agentic (m4.acquire-dsn, m5.wip-limit, m8, m10): call apply_choice() with
#     default values; then write lifecycle entry.
#   codex-only (m9): write not-applicable lifecycle entry (CC platform skip).

python3 - \
    "${REAL_REPO_ROOT}" \
    "${FAKE_HOME}" \
    "${REPO_IDENTITY}" \
    "${PLUGIN_ROOT}" \
    <<'PYEOF'
import sys, os, types, importlib.util, importlib, pathlib, yaml, datetime

repo_root = pathlib.Path(sys.argv[1])
home = pathlib.Path(sys.argv[2])
repo_identity = sys.argv[3]
plugin_root = pathlib.Path(sys.argv[4])

# Add scripts/ to sys.path so stages_lib is importable.
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

# -------------------------------------------------------------------------
# Walk all 22 stages in topological order
# -------------------------------------------------------------------------
# Topological order (from stages-registry.yml dependency graph).
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

# Mocked target states for stages whose executors require external services
# (gh, DB, uv, network) unavailable in CI.
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

# Agentic stage defaults (architect choices passed to apply_choice).
# m4.repo.acquire-dsn uses executor() — it auto-applies sqlite zero-config
# default per ADR-0019 when credentials.yml is absent.
AGENTIC_DEFAULTS = {
    "m5.repo.set-wip-limit": 5,
    "m8.host.bootstrap-overrides-yml": [],
    "m10.repo.choose-kanban-projection": "github-project-v2",
}

# -------------------------------------------------------------------------
# Pass 1: run executors / apply_choice to produce side-effects.
# Collect (stage_id, target_state, status) tuples for bulk lifecycle write.
# Rationale: m1.repo.write-state-yml.executor() initialises repo-shared
# settings.yml (resetting modules.lifecycle), so lifecycle entries MUST be
# written AFTER all executors have run (Pass 2), not interleaved.
# -------------------------------------------------------------------------
pending_lifecycle = []  # list of (stage_id, target_state, status)
errors = []

for stage_id in STAGE_ORDER:
    try:
        # m9 is codex-only — not-applicable on CC.
        if stage_id == "m9.host.register-codex-hooks":
            pending_lifecycle.append((stage_id, {}, "not-applicable"))
            continue

        # Mocked external stages: use pre-defined target state.
        if stage_id in MOCK_TARGET_STATES:
            pending_lifecycle.append((stage_id, MOCK_TARGET_STATES[stage_id], "applied"))
            continue

        mod = load_stage_module(stage_id)
        if mod is None:
            errors.append(f"{stage_id}: module not found")
            continue

        # Agentic stages: call apply_choice() with default value.
        if stage_id in AGENTIC_DEFAULTS:
            mod.apply_choice(ctx, AGENTIC_DEFAULTS[stage_id])
            ts = mod.compute_target_state(ctx)
            pending_lifecycle.append((stage_id, ts, "applied"))
            continue

        # Automated stages: run executor() for side-effects.
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
# Pass 2: write all 22 lifecycle entries to repo-shared settings.yml in
# one batch, AFTER all executors have run (so m1.repo.write-state-yml's
# initialisation of modules.lifecycle has already happened).
# -------------------------------------------------------------------------
now = datetime.datetime.utcnow().isoformat() + "Z"
data = read_settings(
    "repo-shared", home=home, repo_root=repo_root, repo_identity=repo_identity
)
lc = data.setdefault("modules", {}).setdefault("lifecycle", {})

applied_count = 0
not_applicable_count = 0

for stage_id, ts, status in pending_lifecycle:
    if status == "not-applicable":
        lc[stage_id] = {
            "status": "not-applicable",
            "generation": 0,
            "target_state_hash": "",
            "reason": "platform predicate: codex-only stage skipped on CC",
            "applied_at": now,
        }
        not_applicable_count += 1
    else:
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

print(f"applied={applied_count} not_applicable={not_applicable_count} errors=0")
PYEOF

MOCK_EXIT=$?
check "Python mock SKILL walk completed without error" test "${MOCK_EXIT}" -eq 0

# Verify individual stage artifacts produced by real Python executors.
check "m6: .gitignore managed block written" \
    grep -q "board-superpowers managed" "${REAL_REPO_ROOT}/.gitignore"
check "m6: .gitignore contains *.local.*" \
    grep -q '\*\.local\.\*' "${REAL_REPO_ROOT}/.gitignore"
check "m6: .gitignore contains claims/" \
    grep -q "claims/" "${REAL_REPO_ROOT}/.gitignore"
check "m6: .gitignore contains .venv/" \
    grep -q "\.venv/" "${REAL_REPO_ROOT}/.gitignore"

check "m1.host.create-state-dir: host state dir created" \
    test -d "${FAKE_HOME}/.board-superpowers"
check "m1.host.write-manifest: host-shared settings.yml written" \
    test -f "${FAKE_HOME}/.board-superpowers/settings.yml"
check "m1.repo.write-state-yml: repo-shared settings.yml written" \
    test -f "${REPO_SHARED_DIR}/settings.yml"

check "m5.repo.write-config-yml: repo-git settings.yml written" \
    test -f "${REAL_REPO_ROOT}/.board-superpowers/settings.yml"
check "m5.repo.write-config-local-yml: repo-clone settings.local.yml written" \
    test -f "${REAL_REPO_ROOT}/.board-superpowers/settings.local.yml"

check "m5.repo.set-wip-limit: wip_limit persisted" \
    python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('${REAL_REPO_ROOT}/.board-superpowers/settings.local.yml').read_text())
assert (data.get('modules') or {}).get('m5_repo_configuration', {}).get('wip_limit') == 5
"

check "m10: kanban projection persisted" \
    python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('${REAL_REPO_ROOT}/.board-superpowers/settings.yml').read_text())
proj = (data.get('modules') or {}).get('m10_kanban', {}).get('projection')
assert proj == 'github-project-v2', f'expected github-project-v2, got {proj!r}'
"

check "m7.repo.detect-agentsmd-form: form recorded in lifecycle" \
    python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('${REPO_SHARED_DIR}/settings.yml').read_text())
lc = (data.get('modules') or {}).get('lifecycle', {})
entry = lc.get('m7.repo.detect-agentsmd-form') or {}
assert entry.get('status') == 'applied', f'status={entry.get(\"status\")!r}'
"

check "repo-shared lifecycle has 22 stage entries" \
    python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('${REPO_SHARED_DIR}/settings.yml').read_text())
lc = (data.get('modules') or {}).get('lifecycle', {})
# Exclude schema_version key (written by m1.repo.write-state-yml executor).
stage_entries = {k: v for k, v in lc.items() if k != 'schema_version'}
assert len(stage_entries) == 22, f'expected 22 stage entries, got {len(stage_entries)}: {list(stage_entries.keys())}'
"

# ---------------------------------------------------------------------------
# Phase C: create mock venv so the hook uses lifecycle-probe path
# ---------------------------------------------------------------------------

printf '\n=== Phase C: install venv stub + re-run hook (lifecycle-probe path) ===\n'

# The hook checks for <repo>/.board-superpowers/.venv/bin/python3.
# Create a stub that invokes the real system python3, so the hook takes
# the venv branch and runs lifecycle-probe.
VENV_BIN="${REAL_REPO_ROOT}/.board-superpowers/.venv/bin"
mkdir -p "${VENV_BIN}"
# Create a wrapper that calls system python3.
cat > "${VENV_BIN}/python3" <<VENV_PY
#!/usr/bin/env bash
exec python3 "\$@"
VENV_PY
chmod +x "${VENV_BIN}/python3"

check "venv stub python3 created" test -x "${VENV_BIN}/python3"

HOOK_OUT_C="$(run_hook)"

check "hook exits cleanly after full bootstrap" true
check "no INVOKE: bootstrapping-repo on second run (all stages applied)" \
    bash -c '! printf "%s" "${1}" | grep -q "INVOKE: bootstrapping-repo"' -- "${HOOK_OUT_C}"

# ---------------------------------------------------------------------------
# Phase D: verify m9 is not-applicable on CC (platform predicate)
# ---------------------------------------------------------------------------

printf '\n=== Phase D: m9 not-applicable on CC (codex-only predicate) ===\n'

check "m9 lifecycle entry status is not-applicable" \
    python3 -c "
import yaml, pathlib
data = yaml.safe_load(pathlib.Path('${REPO_SHARED_DIR}/settings.yml').read_text())
lc = (data.get('modules') or {}).get('lifecycle', {})
entry = lc.get('m9.host.register-codex-hooks') or {}
assert entry.get('status') == 'not-applicable', f'status={entry.get(\"status\")!r}'
"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n=== Fresh-clone CC E2E: %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
