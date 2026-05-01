# bootstrapping-repo — stage execution flow

Reference for the SKILL body's "Sequential per-stage execution" section. Read this when you need the detailed algorithm, failure-mode table, topological ordering logic, or platform dispatch differences.

## How the lifecycle diff works

The lifecycle diff is computed by `stages_lib._lifecycle.compute_lifecycle(registry, partitioned_settings, platform)`. For each stage in the registry it:

1. Finds the `stages_completed` entry (if any) in the stage's `locality` settings file.
2. Compares the entry's `generation` to the registry's declared `generation` for that stage. If they differ → `drifted`.
3. Compares the entry's `target_state_hash` to the SHA256 of `compute_target_state()` evaluated now. If they differ → `drifted`.
4. If the `applicable_when` predicate evaluates false → `blocked`.
5. If the stage is excluded by `platforms[]` on the current platform → `not-applicable`.
6. If no completed entry and none of the above → `pending`.
7. If all checks pass (generation match + hash match) → `applied`.
8. If a prior completed entry has `status: failed` → `failed`.

The SKILL reads the diff output; it never re-evaluates the predicates itself.

## Topological ordering algorithm

Stages declare dependencies via `depends_on: [stage_id, ...]`. The topological sort is a standard Kahn's algorithm over the pending stages only. Applied stages that are listed as dependencies are treated as "already satisfied" — they are not re-run.

The sort guarantees:
- M1 (host manifest) runs before M2 (per-repo venv) — M1 is host-scoped, M2 is repo-scoped, but venv creation requires plugin root path from manifest.
- M10 (kanban projection choice) runs before M3 (label provisioning, Status validation) — M3 uses `applicable_when: { kanban_projection_capability: ... }` which cannot be evaluated until M10 is applied.
- M4 (audit DDL) runs before audit rows enter the real DB.
- M6 (gitignore) is independent of M3 / M4 / M7 — it runs in parallel slot if ordering allows.

If a dependency stage is in `failed` state, all stages that `depends_on` it are skipped without error (they remain `pending`; the next session retry attempts the failed stage first).

## Per-character execution algorithm

### Automated stages

```
function run_automated_stage(stage, repo_path, settings):
    announce("▶ Running {stage.stage_id} — {stage.name}")

    try:
        result = uv_run(
            stage.executor,
            repo_path=repo_path,
            settings=settings
        )
    except ExecutorError as e:
        state = write_stage_state(stage, "failed", last_error=str(e))
        classify_and_audit(stage, "propose", state)
        announce("  ✗ {stage.stage_id} failed — {e}")
        mark_dependents_skipped(stage.stage_id)
        return  # continue with next independent stage

    # Success path
    target_state = stage.compute_target_state(repo_path=repo_path)
    target_hash  = canonical_sha256(target_state, stage.hash_excluded_fields)
    state = write_stage_state(stage, "applied",
                              generation=stage.generation,
                              target_state=target_state,
                              target_state_hash=target_hash)
    classify_and_audit(stage, "resolve", state)
    announce("  ✓ {stage.stage_id} applied")
```

The `uv_run` call executes `python3 -c "from stages_lib import <module>; <module>.executor(repo_path=repo_path)"` inside `<repo>/.board-superpowers/.venv/`. If the venv does not exist (fresh repo), the SKILL runs the M2 venv-create stage first.

### Agentic stages

Agentic stages use the five-element config-item protocol. See `references/config-item-protocol.md` for the full protocol. The execution algorithm is:

```
function run_agentic_stage(stage, repo_path, settings, architect):
    announce("⚙ Setup choice — {stage.name}")
    surface_prompt(stage.interactive_prompt)

    response = wait_for_architect_response(timeout=session_lifetime)
    if response is None:  # architect unreachable / CI env
        write_stage_state(stage, "pending-architect-input")
        announce("  ⏸ {stage.stage_id} awaiting architect input — will re-prompt next session")
        HALT  # do not continue — agentic stages are HALT points

    validation_error = validate(response, stage.target_state_schema)
    if validation_error:
        surface_validation_error(validation_error)
        response = wait_for_architect_response()  # re-prompt once
        validation_error = validate(response, stage.target_state_schema)

    if validation_error:  # second try also failed
        write_stage_state(stage, "pending-architect-input",
                          last_error=validation_error)
        announce("  ⏸ {stage.stage_id} — invalid input; will re-prompt next session")
        HALT

    # Valid input — persist and record
    result = stage.executor(response, repo_path=repo_path, settings=settings)
    target_state = stage.compute_target_state(repo_path=repo_path)
    target_hash  = canonical_sha256(target_state, stage.hash_excluded_fields)
    state = write_stage_state(stage, "applied",
                              generation=stage.generation,
                              target_state=target_state,
                              target_state_hash=target_hash)
    classify_and_audit(stage, "resolve", state)
    announce("  ✓ {stage.stage_id} applied")
```

Key invariant: **HALT on first agentic stage that cannot be immediately resolved.** Do not skip agentic stages or substitute defaults. The architect's answer is load-bearing — the stage's target_state represents a real configuration decision that affects all subsequent stages (notably M10 → M3 dependency).

### M3 kanban-capability stages

M3 stages run as automated stages once the `blocked` state clears. The lifecycle diff re-evaluates the `kanban_projection_capability` predicate on every session. When M10 applies, the next session's diff finds M3 stages as `pending` (not `blocked`) and includes them in the execution list.

M3 executors route board reads through `board-superpowers:operating-kanban` (ADR-0027). The operating-kanban skill reads `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.<id>.projection`, loads the per-projection reference file, and dispatches the action. This indirection is mandatory — never call `gh project` commands directly in stage executor code.

## Failure-mode table

| Failure | Stage state | Downstream | Session behavior |
|---------|-------------|-----------|-----------------|
| `uv sync` fails (M2) | `failed` | All stages that depend on M2 are skipped | Session continues; next session retries M2 first |
| Executor exits non-zero | `failed` + `last_error` captured | Dependent stages skipped | Remaining independent stages run |
| DB unavailable at audit row | No stage state change; audit degrades to jsonl | None | Session continues; `mode` field in jsonl records cause |
| Network unavailable during M3 label sync | `failed` | M3 siblings independent (no cross-M3 depends_on) | Other stages continue |
| Status field drift on M3 validate | Executor surfaces mismatch to architect | Waits for fix, then retries; does not auto-correct | Stage blocks in `pending-architect-input` until fix confirmed |
| Agentic stage in CI / scripted env | `pending-architect-input` | HALT at agentic stage | Remaining stages after the HALT point are not run in this session |
| M10 not yet applied when M3 evaluated | `blocked` (not `failed`) | No downstream effect | M3 auto-clears to `pending` once M10 is `applied` on any session |
| Duplicate marker in CLAUDE.md (M7) | Executor surfaces duplicate; asks resolve/keep | Waits for architect choice | Does not inject second block; always prompts on ambiguity |

## Platform dispatch differences

| Aspect | Claude Code | Codex CLI |
|--------|-------------|-----------|
| Hook delivery | `SessionStart` fires reliably; INVOKE marker consumed by entry skill | `SessionStart` fires via `~/.codex/hooks.json`; same INVOKE consumption |
| `Skill` tool availability | Available; SKILL invocations are in-process | Available; same behavior |
| Agentic stage I/O | Message stream (chat turn) | Message stream (same) |
| venv path | `<repo>/.board-superpowers/.venv/` (both platforms) | Same |
| Platform filter | `cc` or `both` stages run | `codex` or `both` stages run |

Stages marked `platforms: [cc]` are silently skipped on Codex (they enter `not-applicable`). No error; the lifecycle diff never surfaces them.

## Worked topological ordering example

Registry declares:
```yaml
- stage_id: m1.host.write-manifest   generation: 1   depends_on: []
- stage_id: m2.repo.sync-venv        generation: 1   depends_on: [m1.host.write-manifest]
- stage_id: m4.repo.apply-audit-ddl  generation: 1   depends_on: [m2.repo.sync-venv]
- stage_id: m6.repo.append-gitignore generation: 1   depends_on: []
- stage_id: m7.repo.inject-routing   generation: 2   depends_on: [m2.repo.sync-venv]
- stage_id: m10.repo.choose-kanban   generation: 1   depends_on: [m2.repo.sync-venv]
- stage_id: m3.repo.ensure-labels    generation: 1   depends_on: [m10.repo.choose-kanban]
                                                      applicable_when:
                                                        kanban_projection_capability: ensure_labels
```

On a fresh repo, all stages are `pending`. Topological order:

1. `m1.host.write-manifest` (no deps)
2. `m6.repo.append-gitignore` (no deps — runs concurrently with m1 if implementation allows; currently sequential)
3. `m2.repo.sync-venv` (after m1)
4. `m4.repo.apply-audit-ddl` (after m2)
5. `m7.repo.inject-routing` (after m2)
6. `m10.repo.choose-kanban` (after m2; **agentic** — HALT if architect unavailable)
7. `m3.repo.ensure-labels` (after m10; **blocked** until m10 `applied` and projection capability confirmed)

After m10 applies, the next session's diff finds m3 as `pending` (predicate now evaluates true) and runs it in slot 7.
