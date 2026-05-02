# ADR 0014: Stage registry contract — YAML metadata + Python helpers + JSON Schema validation

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

The unified check-script trigger model (ADR-0012) walks a stage
registry every `SessionStart` and emits an
`INVOKE: bootstrapping-repo` marker for any stage the lifecycle
model (ADR-0013) reports as `never-run` or `stale`. The registry
is the single declaration of every bootstrap stage — its
`(module, character, locality)` 3-tuple identity (per
[`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
§ "The three axes"), dependencies, executor, and the five
callables the lifecycle requires from each stage.

Three constraints shape how it must be stored:

1. **Multiple consumers, one source of truth.** Read by (a)
   `hooks/session-start.sh` — bash that must stay cheap (~200ms
   per ADR-0012 § "Positive"), (b) the `bootstrapping-repo`
   SKILL — Python needing typed function references for
   `idempotency_check`, `target_state_predicate`,
   `compute_target_state`, `executor`, and (c) architects
   auditing the Stages table without launching Python. No
   single language owns discovery.
2. **Hash stability across runtimes.** ADR-0013's layer-2
   fingerprint is sha256 of canonical YAML emit of
   `compute_target_state()` output. Python emits, bash hashes;
   a format that lets them diverge silently breaks the
   lifecycle.
3. **Load-time validation.** Enum typos, missing `depends_on`
   targets, malformed per-stage `target_state` shapes must fail
   at CI time, not hook time, so a corrupt registry never
   reaches a session start (per ADR-0012's hook-always-exits-0
   invariant).

These constraints place the registry in the
**markup-as-contract** family — declarative YAML for the cheap
consumer, sibling source files for typed callables, JSON Schema
gating the seam.

## Decision

The stage registry is stored as **three artifacts**, split so
each consumer reads only what it needs:

1. **`scripts/stages-registry.yml`** — single declarative
   metadata file carrying every `(table)` column plus the
   `(prose, registry)` fields enumerated in design doc § "Column
   / field semantics" (`stage_id`, `stage_name`, `description`,
   `module`, `character`, `locality`, `platforms`, `flags`,
   `introduced_in_version`, `deprecated_in_version`,
   `depends_on`, `executor`, `generation`, `target_state_schema`,
   `target_state_schema_version`, `hash_excluded_fields`,
   `external_ttl_seconds`, plus M7-only `kind` /
   `block_max_bytes`, plus the conditional-applicability
   `applicable_when` predicate and the architect-projection
   `module_section_path` field per ADR-0020 / ADR-0021).
   Bash hooks parse it with `pyyaml` (in the per-repo venv)
   without invoking any stage module.
2. **`scripts/stages_lib/<stage_id>.py`** — one Python module
   per stage with four typed callables: `executor`,
   `idempotency_check`, `target_state_predicate`,
   `compute_target_state`. Naming: stage_id with `.` and `-`
   replaced by `_` (e.g., `m4_repo_apply_audit_ddl.py` for
   `m4.repo.apply-audit-ddl`). Shared canonicalization helper:
   `scripts/stages_lib/_canonical.py`.
3. **`scripts/stages-registry.schema.json`** — JSON Schema
   validating `stages-registry.yml` at load time. CI-gated
   (every PR) and runtime-gated (SKILL re-validates before the
   first executor invocation each session). Catches enum typos,
   missing required fields, `depends_on` references to
   nonexistent stage_ids, `target_state_schema` divergence.

**Canonicalization invariant for hash stability.** Hashes
into ADR-0013's layer-2 fingerprint come from canonical YAML
emit of `compute_target_state()` output, computed in five
steps (per design doc § "Canonicalization invariant for hash
stability"):

1. Deep-sort all keys alphabetically.
2. Fixed indent (2 spaces), fixed flow style (block).
3. Normalize line endings to `\n`; strip trailing whitespace.
4. Strip `hash_excluded_fields` paths.
5. sha256 the result.

`scripts/stages_lib/_canonical.py` is the **single producer**;
stages bypassing it (ad-hoc `yaml.dump`, hand-rolled templates)
break hash stability silently and get caught by CI round-trip
tests.

**Five-callable contract.** Each stage MUST provide what the
lifecycle model requires (ADR-0013 + design doc § "What the
lifecycle model asks of each stage"):

- A `generation` int — declared in YAML; bumped when *any*
  aspect of the expected target changes (schema, executor,
  content template). Layer-1 fast-path.
- A `target_state_schema` — declarative JSON-Schema-style shape
  embedded in the registry entry, validated at load time.
- `compute_target_state()` — returns current expected
  `target_state`; output validated against the schema and fed
  to `_canonical.py` for the layer-2 hash.
- `idempotency_check()` — pure function from local state to
  bool; cheap; lets the executor short-circuit re-runs.
- `target_state_predicate()` — confirms the outcome landed; on
  `external`-locality stages it performs the GitHub / RDBMS
  query feeding the lifecycle's layer-3 structural diff.

Each stage MAY additionally provide (per ADR-0020 / ADR-0021):

- An `applicable_when` predicate (declarative setting-path,
  declarative board-capability, or Python escape hatch) —
  conditional gate that resolves to `not-applicable` when
  false. Cheap to evaluate (hook-side); never blocks for IO.
- A `module_section_path` — overrides the default
  `modules.<derived>` projection target if the stage's
  `target_state` should be visible to architects under a
  custom path in the settings file's modular layering.
- An `apply_choice(ctx, validated_value) -> dict` callable
  (optional 5th callable for stages with `character: agentic`)
  — invoked by the SKILL after the architect provides input and
  `target_state_predicate` confirms the value's shape. The
  helper persists to the stage's locality settings file via
  `_partitioned_settings.update_module_section` and returns
  `{applied: True, message: ..., side_effects: [...]}`. This
  split ensures agentic stages use a prompt-mediated
  persistence path: `executor(ctx)` signals `requires_input`
  (never writes); `apply_choice` writes (never prompts). The
  four standard callables remain mandatory; `apply_choice` is
  opt-in for agentic stages only.

The schema validates declarative fields; CI round-trip-tests
each callable to validate the dynamic contract.

## Consequences

### Positive

- **Hook stays cheap.** Bash reads YAML directly and never
  imports a per-stage Python module; ADR-0012's hook-cheap
  invariant is structurally preserved.
- **Typed callables where they belong.** Python sees ordinary
  functions with type hints — no reflection, no string-keyed
  dispatch, no embedded shell-in-YAML; `mypy` and IDE
  autocomplete work.
- **Errors fail at CI, not session start.** Schema catches
  malformed registries in PR review; combined with ADR-0012's
  hook-always-exits-0, the architect sees a working marker or a
  clear upstream CI failure — never a silent broken hook.
- **Adding a stage is one PR with three matched edits.** YAML
  row + `stages_lib/` module + occasional schema update; CI
  gates the seams; per-stage boundary makes review natural.
- **Registry is human-readable.** Architects see the same
  fields they read in markdown.

### Negative

- **Three artifacts to keep aligned.** Discipline cost bounded
  by the schema (gates two of three seams); only Python ↔ YAML
  stage_id naming is CI-test-enforced.
- **Two parsers must agree on canonical form.** Bash hashes
  what Python emits; `_canonical.py` drift breaks layer-2
  fingerprints. Mitigated by single-producer + CI round-trip.
- **No decorator ergonomics.** Authors edit YAML and the paired
  module separately rather than `@stage(...)` above a function.
  Sacrificed to keep bash cheap.

## Alternatives considered

The chosen option (α — YAML + Python + JSON Schema) is in § Decision.

### β — Pure-Python decorator registry (Dagster `@op`, Prefect `@flow`, Airflow `@dag`, Click commands)

Rejected. Decorator-as-registry is correct when one Python
runtime owns discovery — Dagster's job graph, Prefect's flow
registry, Airflow's DAGbag, Click's command tree are all walked
by a single process importing every module to find decorated
callables. Bootstrap has multi-runtime consumers (bash hooks,
Python executors, markdown-reading humans); forcing every
consumer to shell out to Python for stage enumeration would
push hook latency into seconds (Python startup alone ~50-150ms)
and break ADR-0012's hook-cheap invariant. Right pattern, wrong
niche.

### γ — Embedded shell array (bash `declare -A` or `stages.sh` table)

Rejected. Bash makes multi-line nested data structurally
painful — `declare -A` is flat key-value; the workarounds
(`IFS`-parsed records, here-docs populating parallel arrays)
are well-known footguns. Per-stage `target_state_schema` is
nested data bash cannot represent without inventing a
serialization on top of bash. No IDE / autocomplete /
type-check support. A malformed `stages.sh` at session start
is exactly the failure mode this redesign exists to eliminate.

### δ — Pure-YAML with executor inline as shell snippet

Rejected. The five-callable contract needs
`idempotency_check`, `target_state_predicate`,
`compute_target_state`, `executor` as type-checked function
references with structured I/O — they read configuration, query
GitHub / RDBMS, emit structured `target_state` dicts. Embedding
bash snippets in YAML inverts the seam: cheap consumer stays
cheap, expensive consumer now shells out to evaluate snippets —
the tradeoff that made β untenable, applied in reverse.

## Notes

The three-artifact pattern matches mature multi-consumer
markup-as-contract registries: **Tekton CRDs** (OpenAPI v3 in
the CRD; admission-time validation), **Helm `Chart.yaml` +
`values.schema.json`**, **npm `package.json`**, **Cargo
`Cargo.toml`**, **Poetry `pyproject.toml`** (each paired with
sibling source files), **Ansible playbooks** with Python under
`library/`. Each chose the same split for the same reason:
cheap consumer reads markup, expensive consumer reads code,
schema gates the gap.

## Related

- [ADR-0006](./0006-producer-autonomy-boundary.md) — registry's
  `character` axis (`automated` / `agentic`) declares which
  stages need agent mediation.
- [ADR-0007](./0007-plugin-runtime-derived-constraints.md) — CC
  `SessionStart` ≤5s soft limit is the C-PLUGIN constraint
  driving bash-reads-YAML-only.
- [ADR-0008](./0008-plugin-to-plugin-skill-invocation.md) —
  SKILL invocation contract; `executor: SKILL: ...` routes
  through it.
- ADR-0012 — unified check-script trigger model; hook consumes
  this registry every `SessionStart`.
- ADR-0013 — 5-state lifecycle + three-layer fingerprint;
  defines what the lifecycle asks, this ADR specifies how it
  is stored.
- ADR-0015..ADR-0019 — companion bootstrap-redesign ADRs (audit
  per-repo locality, repo identity, M7 routing-block protocol,
  M8 autonomy presets, M9 hook registration); each adds stages
  this contract describes.
- [`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
  § "Stage registry contract" — authoritative reference for
  column semantics, canonicalization invariant, five-callable
  contract.
