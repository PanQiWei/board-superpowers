---
name: bootstrapping-repo
description: Use when board-superpowers needs to run setup stages — first session, plugin upgrade with new stages, interrupted session resume, or explicit architect request. Triggers automatically when SessionStart hook emits `INVOKE: bootstrapping-repo`. Also triggers on: "set up board-superpowers", "bootstrap this repo", "first time on this repo", "configure the plugin", "run setup stages". Apply whenever plugin setup or reconfiguration is wanted, even without the word "bootstrap". Do NOT use once all stages are applied with no upgrade pending.
when_to_use: |
  Use when:
  - SessionStart hook injected `INVOKE: bootstrapping-repo` (hook detected pending or drifted stages).
  - Entry skill detects absent settings files during lifecycle probe.
  - Architect says "set up board-superpowers", "bootstrap this repo", "first time on this repo", "configure the plugin", "run setup again", or similar.
  - After a plugin upgrade (hook sees newly-added stages as pending, fires marker automatically).
  - Interrupted bootstrap resumes (prior session left stages in failed or blocked state).
arguments:
  - resume
argument-hint: "[resume] — pass 'resume' to skip already-applied stages and continue from the first pending stage"
---

# bootstrapping-repo

This is the molecular skill that is the **sole executor** for all setup stages in board-superpowers. It covers first-time setup, plugin-upgrade reconvergence, and agentic configuration (WIP limits, kanban projection choice, autonomy presets) through one unified mechanism:

1. Read the lifecycle state of every stage in the registry.
2. Find all stages in `pending` or `drifted` state.
3. Topologically order them.
4. Execute each in character order (automated, then agentic as encountered).

There is no separate migration skill. Plugin upgrades that add new stages or bump existing stage generations are handled by this exact same flow — the lifecycle detects the drift automatically.

## Trigger paths

Two paths route the architect here:

1. **Hook fast path**: `hooks/session-start.sh` reads the partitioned settings files, runs the lifecycle diff, and emits `INVOKE: bootstrapping-repo / REASON: N stages need running (...)` when any stage is `pending` or `drifted`. The entry skill `board-superpowers:using-board-superpowers` consumes this marker and routes here.
2. **Architect-spoken fallback**: architect phrases like "set up board-superpowers", "bootstrap this repo", "run setup stages". The entry skill matches the phrase and routes here.

Both paths arrive at the same procedure below. No re-probe is needed once control reaches this skill.

## Stage registry overview

The stage registry lives at `scripts/stages-registry.yml` and is the single source of truth for which stages exist, their characters, locality, dependencies, and generation numbers. Stages are organized into modules (M1..M11). The SKILL does not hardcode the module list — it reads the registry dynamically by loading `scripts/stages-registry.yml` via `yaml.safe_load()`, then passes the resulting dict to `stages_lib._lifecycle.evaluate_all_stages()`.

Key fields consumed by this SKILL per stage:

| Field | Purpose |
|-------|---------|
| `stage_id` | Canonical identifier (e.g., `m6.repo.append-gitignore`) |
| `character` | `automated` or `agentic` — determines dispatch path |
| `locality` | Which of the four settings files stores completed state |
| `generation` | Monotonic int; bump triggers re-run on upgrade |
| `depends_on[]` | Other stages that must be `applied` first |
| `applicable_when` | Optional predicate; absence means always-applicable |
| `platforms[]` | `cc` / `codex` / `both` — gates `not-applicable` states |

The `platforms[]` field is evaluated once at session start; stages excluded on the current platform are never surfaced.

Form A (`setting_path` + `equals`/`one_of`) and Form B (`kanban_projection_capability`) are the predicate types currently implemented; Form C (`python`) is reserved for stages requiring custom logic that Forms A and B cannot express.

## Public API surface

The following are the stable Python entry points and bash helpers that stage executors and this SKILL invoke. Do not call private helpers (`_load_persisted`, `_eval_form_a`, etc.) directly.

```
Python (invoke via uv run inside <repo>/.board-superpowers/.venv/):
  stages_lib._lifecycle.evaluate_all_stages(registry, *, home, repo_root, repo_identity) -> list[dict]
  stages_lib._lifecycle.evaluate_stage(stage, *, home, repo_root, repo_identity, helper_module) -> dict
  stages_lib._lifecycle.evaluate_applicability(stage, *, home, repo_root, repo_identity) -> bool
  stages_lib._canonical.fingerprint(obj) -> str   # sha256 hex digest of canonical YAML emit
  stages_lib._canonical.canonicalize(obj) -> bytes
  stages_lib._partitioned_settings.read_settings(locality, *, home, repo_root, repo_identity) -> dict
  stages_lib._partitioned_settings.write_settings(locality, data, *, home, repo_root, repo_identity) -> None
  stages_lib._partitioned_settings.get_module_section(locality, module_id, *, home, repo_root, repo_identity) -> dict
  stages_lib._partitioned_settings.update_module_section(locality, module_id, section, *, home, repo_root, repo_identity) -> None

Bash (source scripts/lib/common.sh first):
  bsp_settings_path <locality> <home> <repo_root> <repo_identity>
  bsp_stage_state_set <stage_id> <status> <generation> <target_state_hash>
  bsp_stage_state_get <stage_id>

Registry: loaded inline via yaml.safe_load(open('scripts/stages-registry.yml'))
         No _registry module — there is no stages_lib._registry.
```

## Lifecycle vocabulary

Each stage has one of the following lifecycle states. The SKILL reads these from the lifecycle diff output; it never guesses or infers them independently.

| State | When it applies |
|-------|----------------|
| `pending` | No completed entry found for this stage. First time it will run. |
| `applied` | Recorded generation and target-state hash match the registry. Nothing to do — skip. |
| `drifted` | Registry generation or hash changed since last run (plugin upgrade or stage edit). Re-run needed. |
| `not-applicable` | `applicable_when` predicate evaluated false (e.g., an M3 stage whose required kanban projection capability is absent from the active projection's capability set), OR stage excluded by its `platforms` field on the current platform. Skipped gracefully; never surfaced as an error. |
| `failed` | Prior executor run returned non-zero. `last_error` recorded. Retried on next SKILL invocation. |

Two mid-flow transient states the SKILL writes:

| State | When written |
|-------|-------------|
| `blocked` | Agentic stage where the architect response was unavailable or failed validation twice. Flow halts here; re-prompts on next session. This is distinct from `not-applicable` — `blocked` is an agentic-input-pending state, NOT a predicate-false state. |
| `failed` | Executor returned non-zero mid-session. Retried next invocation. |

## On-disk settings layout

The lifecycle diff reads four partitioned settings files. The SKILL reads and writes the same files via Python's `_partitioned_settings.read_settings()` / `write_settings()` (Python callers) or `bsp_settings_path` + `bsp_stage_state_set` / `bsp_stage_state_get` (bash callers in `scripts/lib/common.sh`):

| Locality | File path | Committed? |
|----------|-----------|------------|
| host-shared | `~/.board-superpowers/settings.yml` | No (host-local) |
| repo-shared | `~/.board-superpowers/repos/<repo-identity>/settings.yml` | No (host-local per-repo) |
| repo-git | `<repo>/.board-superpowers/settings.yml` | Yes (in git) |
| repo-clone | `<repo>/.board-superpowers/settings.local.yml` | No (gitignored) |

Each file has two sections:
- `modules.lifecycle.<stage_id>` — keyed-dict of per-stage lifecycle state (status, generation, target_state_hash, last_applied_at, last_diff if drifted).
- `modules.<id>` — architect-readable projection of each module's current configuration.

## Sequential per-stage execution

### Step 1 — Read lifecycle state

```python
# Invoke via uv-run inside <repo>/.board-superpowers/.venv/
import yaml
from pathlib import Path
from stages_lib._lifecycle import evaluate_all_stages

# Load registry directly — no _registry module; just yaml.safe_load
registry = yaml.safe_load(open('scripts/stages-registry.yml'))

# evaluate_all_stages handles topological sort, cascade, and per-stage diff
# home / repo_root / repo_identity are resolved by the calling script
results = evaluate_all_stages(
    registry,
    home=Path.home(),
    repo_root=Path(REPO_ROOT),
    repo_identity=REPO_IDENTITY,
)
pending = [r for r in results if r['state'] in ('pending', 'drifted')]
# results are already topologically ordered by evaluate_all_stages
```

If the venv is absent (fresh repo), run `uv sync` first (stage `m2.repo.sync-venv`), then retry the lifecycle computation.

### Step 2 — Announce

Surface to the architect before starting:

```
Setting up board-superpowers on this repo.
Stages to run: <N> (pending: <list>, drifted: <list>)
Already applied: <M> stages (skipped)
```

### Step 3 — Execute each stage

For each stage in topological order:

#### Automated stage (character: automated)

```
Announce: "▶ Running <stage_id> — <stage_name>"
Execute:  uv run python3 -c "from stages_lib import <module>; <module>.executor(repo_path=REPO_PATH)"
On exit 0:
  - Compute target_state via the stage's helper module's compute_target_state(ctx)
  - Strip hash_excluded_fields from target_state, then compute target_state_hash via _canonical.fingerprint(hashable)
  - Write completed entry to the stage's locality settings file via _partitioned_settings.write_settings()
  - Record status → applied
  - Classify via board-superpowers:classifying-actions (action_id per catalog)
  - Audit via board-superpowers:auditing-actions
  - Announce: "  ✓ <stage_id> applied"
On non-zero:
  - Record status → failed; capture last_error
  - Announce: "  ✗ <stage_id> failed — <last_error>"
  - Skip any downstream stage whose depends_on includes this stage_id
  - Continue with the next independent stage
```

#### Agentic stage (character: agentic)

```
Announce: "⚙ Setup choice — <stage_name>"
Call helper.executor(ctx) — returns {applied: False, requires_input: True, prompt: {...}, default: ...}
  when the stage is not yet configured.
Surface the prompt to the architect verbatim.
Wait for architect response.
Validate the response against target_state_schema using helper.target_state_predicate(value)
  (see references/config-item-protocol.md for validation rules per prompt kind).
On valid:
  - Call helper.apply_choice(ctx, validated_value) — the helper persists the choice to the
    stage's locality settings file via _partitioned_settings.update_module_section.
  - Subsequent executor(ctx) calls return {applied: False} (no-op — already configured).
  - Record status → applied
  - Classify + audit (same as automated)
  - Announce: "  ✓ <stage_id> applied"
On invalid (first try):
  - Show validation error; re-prompt once
On invalid (second try) or architect unreachable:
  - Record status → blocked
  - Announce: "  ⏸ <stage_id> awaiting architect input — will re-prompt next session"
  - HALT. Do not substitute defaults — architect input is required.
  - Next session's hook will detect blocked and emit INVOKE marker again.
```

#### M3 stage with kanban_projection_capability predicate

M3 stages (`m3.repo.ensure-labels`, `m3.repo.validate-status-field`) carry `applicable_when: { kanban_projection_capability: <name> }`. Before execution, the lifecycle diff has already evaluated the predicate:

1. Read `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.<kanban-id>.projection` using `bsp_resolve_active_projection` (helper in `scripts/lib/common.sh`).
2. Load `skills/operating-kanban/references/<projection-id>.md § "Setup capabilities"` — the declared capability set for the active projection.
3. If the required capability is declared: stage enters `pending`/`drifted` and runs normally.
4. If not declared, or if M10 has not yet been applied: the lifecycle has already recorded `not-applicable` for this stage (per ADR-0020). No additional action needed — include in the "Skipped" summary bucket.

M3 stage executors route board reads through `board-superpowers:operating-kanban` protocol actions (e.g., `read_board` for Status options validation). Never call `gh` commands inline — dispatch through the operating-kanban projection layer.

### Step 4 — Final summary

After all stages complete:

```
Setup stages complete.
  Applied:            <N>  (<stage_ids>)
  Skipped (applied):  <M>  (<stage_ids> — already applied)
  Skipped (not-applicable): <B>  (<stage_ids> — predicate evaluated false, e.g., kanban projection capability unavailable or platform mismatch)
  Failed:             <F>  (<stage_ids> — see errors above; will retry next session)
  Awaiting:           <A>  (<stage_ids> — pending architect input; will re-prompt next session)
```

If this is a first-time setup and all stages applied, deliver the first-time user guide from `references/first-time-user-guide.md`.

## Action governance

Every mutating stage action follows the five-step governance sequence:

1. Resolve the `action_id` from the 200-208 bootstrap range (see the action-id catalog in `board-superpowers:classifying-actions references/action-id-catalog.md`).
2. Invoke `board-superpowers:classifying-actions` with the action_id; receive A / R / N.
3. If A: act → invoke `board-superpowers:auditing-actions` to record one entry.
4. If R: invoke `board-superpowers:auditing-actions` to record the proposal; surface to architect; wait; on approve: act + audit resolve; on decline: audit decline; mark stage `failed`.
5. If N: refuse the action; no audit entry; mark stage `failed`.

Bootstrap audit rows (200-208) use the outbox path (`--mode bootstrap-pending`) because the `audit_log` table may not yet exist when early stages run. The audit-flush worker reconciles outbox rows into the DB after the M4 audit DDL stage applies.

Action_id 200 (host manifest write) additionally passes `--repo-root "${HOME}/.board-superpowers/__host__"` to pin the audit row to the canonical host location before any per-repo settings exist.

```
200 → M1  host manifest write
201 → M3  labels provisioning (ensure-labels)
202 → M3  Status field validation (validate-status-field)
203 → M6  .gitignore append
204 → M4  audit DDL apply
205 → M8  autonomy presets write
206 → M7  routing-block injection (CLAUDE.md + AGENTS.md)
207 → M2  per-repo venv create (uv sync)
208 → M10 kanban projection choice persist
```

For the full A/R default classification of each, consult the action-id catalog in `board-superpowers:classifying-actions`.

## Cross-skill references

- `board-superpowers:board-canon` — state machine and Card body schema authority. Read when validating Status field options during M3 stage execution.
- `board-superpowers:operating-kanban` — backend-projection dispatch. Route all board reads (e.g., `read_board` for M3 Status validation) through this skill. Never inline `gh` calls in stage executors.
- `board-superpowers:classifying-actions` — D-AUTONOMY-1 matrix + override parsing. Invoked at every mutating action.
- `board-superpowers:auditing-actions` — audit log schema + two-entry rule. Invoked immediately after classifying-actions returns A or R.

## Failure modes

| Failure | Behavior |
|---------|----------|
| DB unavailable during audit | Write goes to local jsonl fallback (`audit-local.jsonl`); row's `mode` field records the degradation cause. Session continues. |
| Network unavailable during M3 label sync | M3 stage records `failed`; lifecycle marks it for retry. Other stages continue. |
| Custom Status field options on the kanban board | M3 validate-status-field stage surfaces the mismatch to the architect; waits for fix before retrying. |
| Agentic stage with architect unreachable (CI / scripted env) | Stage records `blocked`; flow halts cleanly. Next interactive session re-prompts. |
| Stage executor exits non-zero | Stage records `failed` + `last_error`. Downstream `depends_on` stages are skipped. All other stages continue. |
| M10 stage not yet applied when M3 runs | M3 stages are `not-applicable` (predicate false, not `failed` and not `blocked`). They transition to `pending` automatically once M10 applies; next session's lifecycle diff finds them and runs them. |

## Plugin-upgrade reconvergence

When a plugin upgrade adds a new stage or bumps an existing stage's `generation`:

- The hook detects the drift on next session start and emits `INVOKE: bootstrapping-repo`.
- This skill runs the lifecycle diff, finds the new / drifted stages, and executes only those.
- Already-applied stages are skipped (their generation and target-state hash still match).
- No separate migration skill is needed.

This property replaces what earlier plugin versions referred to as a separate migration path. The lifecycle SoT fully encodes which stages need running; this skill is the single executor for all of them.

## References

- `references/stage-execution-flow.md` — detailed per-character execution algorithm; failure-mode table; topological ordering worked example; platform (CC vs Codex) dispatch differences.
- `references/config-item-protocol.md` — the five-element config-item protocol for agentic stages; the five prompt kinds (single-choice, multi-choice, free-text, boolean, numeric-range); validation and persistence rules.
- `references/intro.md` — conceptual onboarding (what this plugin is, cross-plugin composition, common first-time questions). Surface inline if the architect asks "what does this thing actually do."
- `references/first-time-user-guide.md` — post-setup orientation: how to create the first card, how to claim a card, where state files live, two-role mental model. Deliver at end of first-time setup run.
- `references/changelog/v0.5.0.md` — what changed from v0.4.x for architects migrating from that version.
