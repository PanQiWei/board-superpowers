# SETUP_STAGES_DEVELOPMENT.md — plugin-wide development guide for the setup-stages system

> **Audience.** Plugin-maintainer agents (CC + Codex) editing
> any of: `scripts/stages-registry.yml`, `scripts/stages_lib/`,
> `scripts/stages-registry.schema.json`, `hooks/session-start.sh`'s
> lifecycle-diff path, `skills/bootstrapping-repo/`, the four
> partitioned `settings.yml` files, or any spec passage describing
> the same system. If your work touches none of those, you do
> not need to read this guide.
>
> **What this guide IS.** A *navigation layer* over the
> authoritative spec, plus the development-time judgment calls
> the spec cannot encode (when to add a stage vs. some other
> mechanism, common misclassifications across the three axes,
> graceful-degradation philosophy, anti-patterns).
>
> **What this guide IS NOT.** A second copy of the spec or the
> ADRs. Whenever a fact has a canonical home, this guide links
> there instead of restating it. If you find a contradiction,
> the canonical home wins; **patch this guide in the same PR**.

## Table of contents

1. [What "setup-stages" means and why the rename](#1-what-setup-stages-means-and-why-the-rename)
2. [Where the source-of-truth lives](#2-where-the-source-of-truth-lives)
3. [Mental model in one page](#3-mental-model-in-one-page)
4. [When to add a stage — and when NOT to](#4-when-to-add-a-stage--and-when-not-to)
5. [Picking the three axes — common misclassifications](#5-picking-the-three-axes--common-misclassifications)
6. [The 5-callable contract — judgment & traps](#6-the-5-callable-contract--judgment--traps)
7. [Agentic stage = config-item elicitation flow](#7-agentic-stage--config-item-elicitation-flow)
8. [`applicable_when` — when to use vs alternatives](#8-applicable_when--when-to-use-vs-alternatives)
9. [`platforms` — when something genuinely differs across CC and Codex](#9-platforms--when-something-genuinely-differs-across-cc-and-codex)
10. [Settings layering — where `target_state` lands](#10-settings-layering--where-target_state-lands)
11. [Kanban projection capability dispatch — M3-conditioning](#11-kanban-projection-capability-dispatch--m3-conditioning)
12. [Cross-version evolution — `generation` bumps & `schema_version`](#12-cross-version-evolution--generation-bumps--schema_version)
13. [The canonicalization invariant — agent footguns](#13-the-canonicalization-invariant--agent-footguns)
14. [Recipe — adding a new stage end-to-end](#14-recipe--adding-a-new-stage-end-to-end)
15. [Testing — what CI gates and what you must hand-test](#15-testing--what-ci-gates-and-what-you-must-hand-test)
16. [Anti-patterns](#16-anti-patterns)
17. [Failure-mode philosophy — graceful degradation](#17-failure-mode-philosophy--graceful-degradation)
18. [Cross-cutting reading map](#18-cross-cutting-reading-map)

---

## 1. What "setup-stages" means and why the rename

The system was originally called "bootstrap" because v0.2.0 only
did first-time setup. Since v0.4.0-redesign it has grown to
cover three independent runtime concerns:

- **First-time setup** — the original "bootstrap" use case.
- **Plugin-upgrade reconvergence** — when the registry's
  `generation` bumps or new stages are added in plugin v(N+1),
  existing repos see those stages as `pending` / `drifted` and
  the same machinery brings them current. Replaces the deferred
  `migrating-repo-version` SKILL ([ADR-0012](./docs/architecture/adr/0012-unified-check-script-trigger-model.md)).
- **Agentic config-item elicitation (the settings UX)** —
  `character: agentic` stages *are* the plugin's settings
  surface. There is no separate "settings" mechanism; the
  architect's interaction with bootstrap is itself the
  configuration UI ([ADR-0023](./docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md)).

"Bootstrap" understates the scope. The canonical name in v1
documentation is **setup-stages**; the legacy file
[`BOOTSTRAP_STAGES_DEVELOPMENT.md`](./BOOTSTRAP_STAGES_DEVELOPMENT.md)
is a one-line shim that redirects here.

> **Implication for SKILL naming.** The skill is still
> `bootstrapping-repo` because changing the SKILL id is a
> separate breaking change deferred to a later cleanup. The
> SKILL's body, however, owns the entire setup-stages flow
> including version reconvergence and agentic config-item
> elicitation. Don't be surprised by the name mismatch.

## 2. Where the source-of-truth lives

If a fact has a canonical home, link to it. Do not restate it
in the SKILL, in code comments, in commit messages, or in this
guide.

| Fact | Canonical home |
|------|----------------|
| Three axes (module / character / locality) — definitions | [`05-bootstrap-surface-redesign.md` § "The three axes"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#the-three-axes) |
| Stages table (the 22-row registry view) | [§ "Stages"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#stages) |
| Trigger model — hook flow + SKILL flow + hook–SKILL contract | [§ "Trigger model"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#trigger-model) + [ADR-0012](./docs/architecture/adr/0012-unified-check-script-trigger-model.md) |
| 6-state lifecycle + three-layer fingerprint | [§ "Stage lifecycle states"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#stage-lifecycle-states) + [ADR-0013](./docs/architecture/adr/0013-declarative-state-schema-and-lifecycle.md) + [ADR-0020](./docs/architecture/adr/0020-stage-applicability-and-not-applicable-state.md) |
| Stage registry contract (YAML + Python + JSON Schema) | [§ "Stage registry contract"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#stage-registry-contract) + [ADR-0014](./docs/architecture/adr/0014-stage-registry-contract.md) |
| Per-stage entry shape (what gets persisted) | [§ "Per-stage entry shape"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#per-stage-entry-shape) |
| Settings modular layering (4 files + `modules.<id>` + per-module `schema_version`) | [§ "Settings modular layering"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#settings-modular-layering-in-file-structure) + [ADR-0021](./docs/architecture/adr/0021-settings-modular-layering.md) |
| `applicable_when` predicate forms (3 of them) | [ADR-0020](./docs/architecture/adr/0020-stage-applicability-and-not-applicable-state.md) § Decision |
| `platforms` field semantics | [ADR-0016](./docs/architecture/adr/0016-cross-platform-parity-contract.md) |
| Architect UX flow + 5-element config item protocol | [§ "Architect UX"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#architect-ux) + [ADR-0023](./docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md) |
| Repo identity scheme + I-13 cross-clone state sharing | [§ "Repo identity"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#repo-identity) + [ADR-0017](./docs/architecture/adr/0017-i13-invariant-revision-cross-clone-state-sharing.md) |
| Kanban projection capability dispatch (M3) + M10 projection selection | [ADR-0027](./docs/architecture/adr/0027-m3-dispatch-via-kanban-protocol-projection.md) |
| M7 multi-stage AGENTS.md / CLAUDE.md routing-block protocol | [ADR-0018](./docs/architecture/adr/0018-m7-multi-stage-routing-block-protocol.md) |
| Zero-config SQLite default audit backend | [ADR-0019](./docs/architecture/adr/0019-zero-config-sqlite-default-audit-backend.md) + [ADR-0009](./docs/architecture/adr/0009-allow-sqlite-as-byo-audit-db.md) |
| M4 audit per-repo locality (replaces host-shared credentials) | [ADR-0015](./docs/architecture/adr/0015-m4-audit-per-repo-locality.md) |
| settings.yml family rename + new config-item stages | [ADR-0024](./docs/architecture/adr/0024-settings-rename-and-config-item-stages.md) |
| Producer autonomy boundary (D-AUTONOMY-1 matrix) | [ADR-0006](./docs/architecture/adr/0006-producer-autonomy-boundary.md) |

When in doubt: **read the design doc end-to-end** before
opening a stage-touching PR. It is ~1700 lines but the table of
contents is dense — you can skim non-relevant sections in
seconds.

## 3. Mental model in one page

```
                               ┌────────────────────────┐
   SessionStart hook ─────────▶│  hooks/session-start.sh │
                               └─────────┬───────────────┘
                                         │ reads partitioned settings,
                                         │ runs lifecycle diff,
                                         │ emits INVOKE marker if
                                         │ any stage is pending / drifted
                                         ▼
                               ┌────────────────────────┐
                               │ bootstrapping-repo SKILL│
                               └─────────┬───────────────┘
                                         │ topo-orders pending stages
                                         │ by depends_on, runs each
                                         ▼
              ┌──────────────────────────┴──────────────────────────┐
              │                                                     │
   character: automated                              character: agentic
   (executor runs autonomously)                      (5-element config item
   ─────────────────────────────                     protocol elicits choice;
   • Bash / DDL / file write                         result is target_state)
   • idempotency_check                               • interactive_prompt
   • compute_target_state                            • target_state_schema
   • target_state_predicate                          • locality decides
   • generation int                                    persistence file
                                                     • re-prompt = lifecycle
                                                       transition
              │                                                     │
              └──────────────────────────┬──────────────────────────┘
                                         │ writes target_state
                                         ▼
              4 partitioned settings.yml files (per locality)
              + status entries → next hook tick reads them
```

The **three axes** (module / character / locality) collectively
identify a stage. Two stages with the same `(module, character,
locality)` triple may not coexist; that uniqueness is the
identity invariant the registry's JSON Schema enforces.

The **6-state lifecycle** (`pending`, `applied`, `drifted`,
`deprecated`, `not-applicable`, `failed`/`blocked` as
transients) is computed by the hook from the partitioned
settings + the registry; the SKILL never guesses, it only
consumes the lifecycle output.

If you internalize one diagram, internalize the one above.
Everything else in this guide elaborates on a piece of it.

## 4. When to add a stage — and when NOT to

The single most common authoring mistake is adding a stage when
some lighter mechanism would do, or skipping a stage when a
heavier mechanism is being mis-applied. Run this decision tree
before opening a registry PR:

```
Is this configuration / setup work that the plugin needs done
on first install, on plugin upgrade, OR every time some
declarative invariant drifts?
│
├─ NO → don't add a stage. Use one of:
│      • A one-shot script callable from the SKILL body
│      • An idempotent shell helper in scripts/lib/
│      • A SKILL flow that runs each session (not a stage)
│
└─ YES → continue.
   │
   Does the work need to happen WITHOUT architect attention?
   (i.e., the agent can compute target_state from existing
    state alone, with no architect input)
   │
   ├─ NO  → character: agentic. Continue.
   │
   └─ YES → character: automated. Continue.
   │
   Does the work's "did it land" check require remote IO
   (GitHub API, RDBMS query) or only local file inspection?
   │
   ├─ Remote IO  → locality: external. Add `external_ttl_seconds`.
   │
   └─ Local file → locality is host-shared / repo-shared /
                   repo-clone (the storage axis), pick by
                   "where the artifact lives".
   │
   Does the SAME logical decision affect every clone of this
   repo on disk, or is it per-clone (e.g., per-architect's
   personal preference)?
   │
   ├─ Per-clone → locality: repo-clone (gitignored)
   ├─ Per-repo, shared across clones → locality: repo-shared
   │  (committed in repo)
   └─ Cross-repo on same host → locality: host-shared
      (in $HOME, gitignored at host level)
```

### Things that look like a stage but are NOT one

| Looks like… | Actually use… |
|-------------|---------------|
| One-time DB seed for a test fixture | A test setup helper, not a stage. Stages are about plugin operation, not test infrastructure. |
| Per-architect personal preference (e.g., "always use vim") | Out of scope. The plugin doesn't carry architect-personal config. |
| Logging verbosity flag | Environment variable. Stages are for declarative invariants, not runtime knobs. |
| Migration of legacy data on a schema bump | If the schema is owned by a stage, the migration belongs *inside* that stage's `compute_target_state` + `executor` (module-local migration per [ADR-0014](./docs/architecture/adr/0014-stage-registry-contract.md)). If it's truly one-shot data migration (will never re-run), it's a script, not a stage. |
| New SKILL prompt path that asks the architect a question | If the answer needs persistence + re-prompt on plugin upgrade, that's an agentic stage. If the answer is per-session ephemeral, it's regular SKILL prompting, not a stage. The litmus test: does the answer need to survive across sessions? |
| `gh` CLI not installed | Dependency check, not a stage. Use `scripts/check-deps.sh`. Stages assume their deps are present. |

If you read the above and your work falls in "actually use…",
**stop and use the lighter mechanism**. Adding a stage that
shouldn't be one creates registry noise that every architect
has to wade through on every plugin upgrade.

## 5. Picking the three axes — common misclassifications

### Module (functional axis)

The 10 modules (M1–M10) are listed in [§ "Axis C — Functional
module"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#axis-c--functional-module).
Common misclassifications:

- **"Audit DDL apply" feels like M1 plugin-runtime infra**
  because it sets up infrastructure. Wrong — it is M4 audit.
  M1 covers only the plugin's *own* runtime state files
  (`settings.yml`, `state.yml`, etc.). Anything an architect
  could opt out of (audit, kanban backend, autonomy presets)
  is its own module.
- **"Routing block injection" feels like M5 repo config**
  because it edits a config-shaped file. Wrong — it is M7
  agent routing. M5 is about plugin-internal repo config
  (e.g., WIP limits); M7 is specifically about the
  AGENTS.md/CLAUDE.md routing instructions agents read on
  session start.
- **"Codex hook registration" feels like M1 plugin-runtime
  infra**. Wrong — it is M9 hook registration. M9 is the
  parity-gap remediation module; if a separate codepath
  exists *because* CC and Codex differ, it lives in M9.

When in doubt, ask: "if this module disappeared, what
architect-facing capability disappears?" The answer names the
module.

### Character (automated vs agentic)

Mistake: adding `character: automated` because "the agent
runs it autonomously". `automated` means **no architect input
is required to compute target_state**. An agentic stage's
executor is also run by the agent — the difference is whether
the architect's choice is necessary input.

Examples often confused:

- **Writing a generated file from a template** = automated.
  Architect made no choice; agent computed everything.
- **Writing a routing block whose body is fixed** = automated.
- **Writing a routing block where the architect can opt out
  of certain block types** = agentic. The choice is
  architect-input.
- **Applying audit DDL in SQLite** = automated (the DSN is
  defaulted, no architect input on a fresh repo per
  [ADR-0019](./docs/architecture/adr/0019-zero-config-sqlite-default-audit-backend.md)).
- **Choosing audit backend (sqlite / postgres / mysql)** =
  agentic, because backend choice IS architect input.

### Locality (storage axis)

Mistake: putting credentials in `repo-shared` because "they
relate to this repo". Wrong — credentials are
`repo-clone` (per-clone, gitignored, never committed). The
locality axis answers **"where does this state live, given
git semantics?"**, not "what does this state describe?".

Recap of the four:

- `host-shared` — `$HOME/.board-superpowers/settings.yml`,
  shared across ALL repos on this host
- `repo-shared` — committed in the repo, identical for every
  clone of the repo
- `repo-clone` — gitignored, **per-clone-on-disk**, NEVER
  committed (revised I-13: same architect with two clones of
  the same repo gets different files; OK because the clone
  is the unit of locality, see [ADR-0017](./docs/architecture/adr/0017-i13-invariant-revision-cross-clone-state-sharing.md))
- `external` — not a settings file at all; lives in GitHub /
  RDBMS / etc., observed via API

If the artifact contains a secret or a path that is
host-specific or architect-specific, it is `repo-clone` or
`host-shared`. Never `repo-shared`.

## 6. The 5-callable contract — judgment & traps

Five required Python callables per stage in
`scripts/stages_lib/<stage_id>.py`. Signatures and intent:
[§ "What the lifecycle model asks of each stage"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#what-the-lifecycle-model-asks-of-each-stage).

The contract itself is in the spec; what follows is the
judgment the spec doesn't encode.

### `executor` — the work itself

Trap: "executor runs side effects, but partial-failure halfway
through corrupts everything." Mitigation: **always make
executor idempotent**. If the work is multi-step, sequence the
steps so a re-run from any intermediate state converges on the
same outcome. The 5-callable contract doesn't enforce
idempotency — `idempotency_check` is a *fast-path optimization*,
not a substitute. If your executor needs `idempotency_check` to
return False before it can safely run, you've broken the
invariant.

### `idempotency_check` — fast-path short-circuit

Trap: writing `idempotency_check` such that it returns True
only when target_state matches *exactly*. Wrong — that
duplicates `target_state_predicate`. The right shape is:
"would re-running executor be a no-op?" — usually a cheap
file-existence + magic-bytes check, NOT a full target_state
comparison.

If `idempotency_check` is expensive (network call, RDBMS
query), you've over-scoped it. Move the expense to
`target_state_predicate`.

### `target_state_predicate` — confirms outcome landed

Trap: implementing `target_state_predicate` with a stale cached
view of external state. For `external`-locality stages, the
predicate is the *only* way the lifecycle observes ground
truth. **Always do the live IO** (subject to `external_ttl_seconds`
caching at the lifecycle level, not inside the predicate).

### `compute_target_state` — what the registry expects to be true

Trap: making `compute_target_state` non-deterministic (e.g.,
including `datetime.now()` or random IDs). The output is
fed to `_canonical.py` for the layer-2 hash; non-determinism
makes the hash flap and every stage permanently `drifted`.

If you genuinely need a per-run-derived value (timestamps,
correlation IDs), put it in `hash_excluded_fields`
([§ "Hash-allowlist"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#hash-allowlist-fields-excluded-from-hash)).

### `generation` int — declared in YAML, not Python

Trap: forgetting to bump `generation` after editing
`compute_target_state` or `target_state_schema`. Without the
bump, the layer-1 fast-path keeps short-circuiting to
`applied` even though the expected target shape changed —
existing repos miss the migration silently.

**Rule**: every PR that edits the per-stage Python module's
`compute_target_state` or `target_state_schema` MUST bump
`generation`. CI enforces (paired diff). If you genuinely just
fixed a typo in a docstring, no bump — but `_canonical.py`
strips comments, so a docstring change doesn't affect the
hash anyway.

## 7. Agentic stage = config-item elicitation flow

Agentic stages are the plugin's settings UX. The
[5-element config item protocol](./docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md)
is mandatory for every agentic stage:

1. **Schema declaration** (`target_state_schema`)
2. **Detection** (lifecycle 6-state — see § 12)
3. **Interaction** (`interactive_prompt` registry field)
4. **Persistence** (`locality` chooses the settings file)
5. **Re-prompt trigger** (lifecycle transition to `drifted`)

See [ADR-0023](./docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md)
for full details.

### Judgment: when an agentic stage's `interactive_prompt` is wrong

Five `kind` values are supported:
`single-choice` / `multi-choice` / `free-text` /
`boolean` / `numeric-range`. If your stage needs:

- **A multi-step wizard** (e.g., "first answer A, then if A
  was X ask B, otherwise ask C") → split into multiple stages
  with `depends_on`. Each stage handles one decision; the
  `applicable_when` predicate handles the conditional branch.
- **A free-form code blob** (e.g., "paste your custom YAML
  predicate here") → don't. The protocol intentionally
  excludes this. If you need it, you're building a
  registry-of-registries; reconsider.
- **A choice that depends on live remote state** (e.g.,
  "pick from your existing GitHub Projects") →
  `kind: single-choice` with `options-source: runtime-derived`.
  The SKILL fetches the option list at prompt time. Be
  conservative — runtime-derived options break offline.

If none of the above five `kind` values fit, you have a
non-standard interaction shape — exactly the per-item drift
the protocol is designed to prevent. Push back on the
requirement before extending the protocol.

### Judgment: when "no choice made" is a valid `target_state`

If the schema permits empty list / null / "no presets selected"
as a valid value, an empty result is `applied`, not `skipped`.
There is no "skip" lifecycle state. See
[ADR-0023 § "Skip semantics are eliminated"](./docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md).

This means: if your stage's schema requires a non-empty value
(`minItems: 1`), the architect *must* make a choice — they
cannot defer. Choose carefully whether your schema permits
empty.

## 8. `applicable_when` — when to use vs alternatives

Three legal forms (per [ADR-0020](./docs/architecture/adr/0020-stage-applicability-and-not-applicable-state.md)):

```yaml
# Form 1: setting-path (preferred for declarative conditionals)
# Supports both `equals` (exact match) and `one_of` (list match).
applicable_when:
  setting_path: modules.m10_kanban.target_state.kanban_projection
  one_of: [github-project-v2, linear]

# Form 2: kanban-projection-capability (for M3-style capability dispatch)
# Uses the active kanban projection's declared capability set (ADR-0027).
applicable_when:
  kanban_projection_capability: pull_request_aggregate

# Form 3: Python escape hatch (last resort)
applicable_when:
  python: stages_lib.m3_repo_label_card_status._is_applicable
```

### Judgment matrix

| Situation | Use |
|-----------|-----|
| "Run this stage only if the architect chose X in stage Y" | Form 1 (setting-path). Cheapest, declarative. Use `equals` for a single value match, `one_of` for a list of permitted values. |
| "Run this stage only if the active kanban projection declares capability Z" | Form 2 (kanban-projection-capability). Reads the active projection's reference file under `skills/operating-kanban/references/<projection>.md § 'Setup capabilities'`. Maps cleanly to ADR-0027 M3-dispatch. |
| "Run this stage based on logic Forms 1+2 cannot express" | Form 3 (python). **Last resort.** Every Form-3 use accumulates registry-side complexity. Document why Forms 1+2 don't suffice in the per-stage Python module. |
| "Run this stage on Codex but not CC" | NOT `applicable_when` — that's the `platforms` field (see § 9). The two compose; `platforms` filters first, `applicable_when` filters second. |

### Trap: Form 1 chains

If you write `applicable_when: setting_path: A → applicable_when: setting_path: B → ...` chains across multiple stages, you've built a
mini decision tree. Two failure modes:

1. **Predicate cycles**. Stage X gates on Y's settings; Y
   gates on Z's; Z gates on X's. The hook can't make progress.
   The JSON Schema validator catches obvious cycles, but
   transitive cycles need design review.
2. **The tree shape isn't visible from any single stage's
   perspective**. An architect debugging "why didn't stage X
   run?" has to traverse the chain. If your tree is deeper
   than 2 levels, consolidate into one stage with a richer
   `target_state_schema`.

Rule of thumb: 1 level of `applicable_when` chaining is fine,
2 is suspicious, 3+ requires architecture review.

## 9. `platforms` — when something genuinely differs across CC and Codex

The dual-platform parity contract is in
[ADR-0016](./docs/architecture/adr/0016-cross-platform-parity-contract.md).

### Judgment: when is `platforms: both` wrong?

`platforms: both` is the default. It is wrong when:

- **The executor depends on a CC-only env var directly**
  (`${CLAUDE_PLUGIN_ROOT}` without going through
  `bsp_plugin_root()`). Mark `cc-only` and provide a Codex
  equivalent (or refactor to use `bsp_plugin_root()`).
- **The work is a CC-only or Codex-only platform-specific
  config write** (e.g., M9 hook registration is `codex-only`
  because CC auto-discovers).
- **The work depends on a SKILL invocation pattern only one
  platform supports** (rare; check
  [ADR-0008](./docs/architecture/adr/0008-plugin-to-plugin-skill-invocation.md)).

If you find yourself reaching for `platforms: cc-only` because
"the Codex equivalent is hard", **resist**. The CC/Codex parity
discipline ([ADR-0016](./docs/architecture/adr/0016-cross-platform-parity-contract.md))
demands you build the Codex path in the same PR or document
why parity is intentionally degraded (with an ADR amendment).

### Composition with `applicable_when`

The hook applies `platforms` BEFORE `applicable_when` (per
[ADR-0016 § "Composition with `applicable_when`"](./docs/architecture/adr/0016-cross-platform-parity-contract.md#decision)).
A stage filtered out by `platforms` does not appear in any
lifecycle state on the wrong platform — not even `not-applicable`.
This matters because `applicable_when: setting_path: ...` would
otherwise need to know the platform; instead, settings files
are platform-agnostic and `platforms` does platform discrimination
purely from runtime context.

## 10. Settings layering — where `target_state` lands

Per [ADR-0021](./docs/architecture/adr/0021-settings-modular-layering.md):

- **4 partitioned `settings.yml` files** — one per locality
  (host-shared, repo-shared, repo-clone; external is observed
  not stored).
- **Two-section split per file**:
  - `modules.lifecycle.<stage_id>` — machine-readable,
    authoritative lifecycle store (ADR-0013; the lifecycle
    reads this). Supersedes the earlier `stages_completed[]`
    flat-list design from the ADR-0021 v1-draft.
  - `modules.<id>` — architect-friendly projection (read-only
    derived view, written by the SKILL on every successful
    stage completion).
- **Per-module `schema_version`** — each module evolves its
  on-disk shape independently.

### Judgment: `module_section_path` overrides

Default projection: a stage's `target_state` lands at
`modules.<derived-from-module>` (e.g., `modules.audit` for an
M4 stage). The optional `module_section_path` overrides:

```yaml
# default — audit ddl lands at modules.audit
stage_id: m4.repo.apply-audit-ddl
# override — autonomy presets land at modules.autonomy_overrides
stage_id: m8.repo.set-autonomy-presets
module_section_path: modules.autonomy_overrides
```

**When to override**: the default is "module name = section
name". Override when the architect-facing concept name differs
from the internal module name (autonomy overrides, kanban
backend choice, etc.). Don't override capriciously — the
default is the readable contract.

### Per-module `schema_version` migration

Each module owns its own `schema_version`. When you bump it:

1. Implement the migration *inside* the stage's
   `compute_target_state` (read old shape, transform to new).
2. Bump the stage's `generation` (so existing repos see
   `drifted`).
3. The next hook tick → SKILL runs the stage → executor
   writes the new shape → `schema_version` bumps in the
   settings file.

There is **no central migration runner**. Per-module
schema migration is the entire migration story. If you find
yourself reaching for a central runner, you're probably trying
to coordinate cross-module changes — push them through
multiple stages with `depends_on` instead.

## 11. Kanban projection capability dispatch — M3-conditioning

[ADR-0027](./docs/architecture/adr/0027-m3-dispatch-via-kanban-protocol-projection.md)
defines the current M3-dispatch model (supersedes ADR-0022 BoardAdapter dispatch):

- **M10 kanban projection selection** — agentic stage
  `m10.repo.choose-kanban-projection` elicits which kanban projection the
  repo uses.
- **M3 stages declare capability dependencies** — e.g.,
  `m3.repo.label-card-status` declares
  `applicable_when: kanban_projection_capability: card_status_label`.
  Projections declare which capabilities they support in their reference file
  under `skills/operating-kanban/references/<projection-id>.md § 'Setup capabilities'`.

### Judgment: adding a new capability

When adding a new M3 stage:

1. Decide which capability it requires.
2. Check whether existing projections declare that capability in their
   reference files. If only some do, the stage gets `not-applicable` for repos
   using non-supporting projections — verify that's the intended UX.
3. If the capability is brand-new, add it to the supporting projection's
   reference file under `skills/operating-kanban/references/<projection-id>.md`
   and update the stage's `applicable_when` in the registry in the same PR.

### When you should NOT use capability dispatch

If the M3 work is universal across all backends (e.g.,
"create the GitHub Project itself"), it's not M3 capability
dispatch territory — that work is part of M10 backend setup.
Capability dispatch is for *features* the backend exposes,
not for the backend's existence.

## 12. Cross-version evolution — `generation` bumps & `schema_version`

The lifecycle's three-layer fingerprint is in
[ADR-0013](./docs/architecture/adr/0013-declarative-state-schema-and-lifecycle.md).
What you need to know operationally:

| Edit | Bump `generation`? | Bump `schema_version`? |
|------|-------------------|------------------------|
| Fixed a typo in a docstring | No | No |
| Renamed a field in `target_state_schema` | **Yes** | **Yes** (if persisted shape changed) |
| Changed `compute_target_state` to compute a new field | **Yes** | **Yes** (if persisted shape changed) |
| Tightened the schema (added `pattern: ^[a-z]+$` to an existing field) | **Yes** (existing values may now violate) | Maybe (depends on whether old values need migration) |
| Loosened the schema (removed a constraint) | **No** (existing values still valid) | No |
| Added a new field to `target_state_schema` with a default | **Yes** | **Yes** |
| Added a new option to an enum (graceful, with `introduced_in_version` tag per [ADR-0023](./docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md)) | No | No |

### The pre-v1 breaking change rule

Until v1 GA, **breaking changes are accepted without
in-place migration**. If you're tempted to write a v0.x → v0.y
migration helper, stop — the policy is to delete legacy state
and re-bootstrap. See [§ "Open design choices > Decided"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#decided-by-this-draft).

After v1 GA this changes — backward compatibility becomes
load-bearing. Plan the v1 GA cutover deliberately.

## 13. The canonicalization invariant — agent footguns

The five canonicalization steps are in
[§ "Canonicalization invariant for hash stability"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#canonicalization-invariant-for-hash-stability).

Footguns specific to agents writing stage code:

- **`yaml.dump(...)` directly** in your stage instead of going
  through `scripts/stages_lib/_canonical.py`. The hash will
  drift across pyyaml versions. Always use the shared helper.
- **Inserting timestamps / correlation IDs into
  `target_state`** without listing them in
  `hash_excluded_fields`. Hash flap → permanent `drifted`.
- **Writing `target_state` keys in non-deterministic order**.
  The canonicalizer sorts, so this *should* be safe, but if you
  bypass the canonicalizer for any reason (custom emit path,
  golden-file fixture in tests), you have to sort yourself.
- **Treating `compute_target_state` as a free-form Python
  function**. It must be **pure** (same input → same output)
  and **bounded** (no unbounded recursion, no async IO). If
  you need IO to compute target_state, that IO belongs in
  `target_state_predicate` — `compute_target_state` declares
  the *expected* shape, not the *observed* shape.

If you think you've found a case where the canonicalization
breaks, write a CI round-trip test that demonstrates the break
before patching. We've been burned by "well-intentioned" hash
fixes that broke other stages silently.

## 14. Recipe — adding a new stage end-to-end

The full procedure as a checklist for a PR-prep self-review:

```
□ 1. Decide axes: (module, character, locality). Re-read § 5
     for misclassifications. Locality = where target_state lands.
□ 2. Choose stage_id: <module>.<locality-bucket>.<verb-noun>.
     Examples: m4.repo.apply-audit-ddl, m9.host.register-codex-hooks.
     locality-bucket = host | repo (repo-shared and repo-clone
     both prefix "repo"; the locality field disambiguates).
□ 3. Write registry row in scripts/stages-registry.yml.
     Required fields per ADR-0014; optional fields per
     ADR-0020 (applicable_when), ADR-0021 (module_section_path),
     ADR-0023 (interactive_prompt for agentic).
□ 4. Write per-stage Python module at
     scripts/stages_lib/<stage_id_slug>.py with the 5 callables.
     Slug = stage_id with `.` and `-` → `_`.
□ 5. If you added a new field to the registry, update
     scripts/stages-registry.schema.json (JSON Schema gate).
□ 6. If character: agentic, fill all 5 protocol elements
     (§ 7). Per-prompt-renderer kind must be one of the 5.
□ 7. If locality: external, set external_ttl_seconds (per
     [§ "External stage TTL cache"](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md#external-stage-ttl-cache-in-repo-shared-stateyml)).
□ 8. Set platforms (default both, see § 9). For codex-only or
     cc-only, justify in the per-stage Python module's
     module-level docstring.
□ 9. depends_on — list every stage whose target_state is read
     by your stage's compute_target_state or
     idempotency_check or applicable_when.
□ 10. Set generation = 1 for new stages.
□ 11. Run CI gates locally:
      • python3 -m json scripts/stages-registry.schema.json
        validates scripts/stages-registry.yml
      • Round-trip test: compute_target_state output
        canonicalizes consistently across two runs
      • Stage-isolated test: idempotency_check returns True
        after one executor run
□ 12. If your stage is agentic, hand-test the prompt path
      in a CC and Codex session (interactive_prompt rendering
      varies by platform).
□ 13. Update the design doc § "Stages" table — the
      authoritative 22-row registry view. Same PR, paired
      diff. (The registry YAML is the runtime SoT; the design
      doc table is the architect-facing SoT — they MUST agree.)
□ 14. Update SKILLS.md if your stage adds a new
      bootstrapping-repo capability that affects the SKILL's
      role description.
□ 15. Commit message: `feat(stages): m<N>.<locality>.<verb> —
      <one-line>`. PR body cites the relevant ADR(s).
```

The PR review questions a reviewer should ask:

1. Is this work actually a stage, or should it be one of the
   alternatives in § 4?
2. Are the three axes correctly chosen (§ 5)?
3. If `character: agentic`, are all 5 protocol elements
   filled?
4. If `applicable_when` is used, is it the right form (§ 8)?
5. If `platforms` is not `both`, is the justification real?
6. Does `compute_target_state` look pure + bounded (§ 13)?
7. Is `generation` bumped if any persisted shape changed?
8. Is the design doc table updated to match?

## 15. Testing — what CI gates and what you must hand-test

CI-gated:

- **JSON Schema validation** — every PR runs the schema
  validator over `stages-registry.yml`. Catches typos,
  missing fields, enum mismatches, dangling `depends_on`.
- **Round-trip canonicalization** — each stage's
  `compute_target_state` output is canonicalized twice in CI;
  the two outputs must match byte-for-byte.
- **Idempotency** — for stages with deterministic local
  effects, a CI fixture runs executor twice and asserts the
  second run is a no-op.
- **shellcheck** over any new shell helpers.

NOT CI-gated (you must hand-test):

- **Architect prompt rendering** — `interactive_prompt`
  fields render differently on CC vs Codex (CC has Skill
  tool richer affordances; Codex is text-only). Hand-test
  both before submitting an agentic-stage PR.
- **External-locality stage observability** — RDBMS / GitHub
  query failures mid-flight (network drops, auth expiry).
  Manually simulate at least one failure mode and verify the
  lifecycle reports `drifted` rather than crashing.
- **Mid-flow architect interrupt** — open a session, let the
  SKILL prompt for an agentic stage's input, abandon the
  session before answering. Reopen — the stage should be
  re-prompted on the next session, not silently skipped.
- **First-time bootstrap on a fresh repo** — the recipe
  above is necessary but not sufficient; do a full clean
  bootstrap end-to-end at least once before opening a PR
  that adds an agentic stage.

## 16. Anti-patterns

### A1. "I'll add a stage just for this one debug helper."

Stages are operational machinery, not tooling. Debug helpers
go in `scripts/`, gated by an env var if needed. The stage
registry is read on every session — every entry costs
architect attention on every plugin upgrade.

### A2. "compute_target_state can call out to GitHub for the source-of-truth value."

No. `compute_target_state` is the *expected* shape; if the
expected shape requires live IO, your stage isn't really
declaring expectations, it's reflecting reality. That's the
job of `target_state_predicate` (paired with
`external_ttl_seconds` for caching).

### A3. "I'll embed bash inside YAML for the executor."

No. The 5-callable contract is typed Python. Bash inside YAML
is the exact failure mode [ADR-0014 § δ](./docs/architecture/adr/0014-stage-registry-contract.md)
rejects.

### A4. "I'll have my agentic stage write a bespoke prompt and persist directly to a custom file."

No. The 5-element protocol exists exactly to retire bespoke
prompt code. If your decision shape doesn't fit one of the
5 prompt kinds, **push back on the requirement**, don't
extend the protocol.

### A5. "I'll put credentials in `repo-shared` or `repo-clone` because they're related to this repo."

No. Credentials live in a separate `~/.board-superpowers/repos/<repo-identity>/credentials.yml`
(mode 0600), HOST-side per-repo. The four-locality settings.yml family (mode 0644) MUST NOT carry
secrets per ADR-0024 § Part A line 53-56 — the settings.yml files are committed or gitignored
plaintext; DSNs / tokens / passwords must not appear in them.

The locality axis governs the `settings.yml` family files only (`host-shared`, `repo-shared`,
`repo-git`, `repo-clone`). Credentials are in a separate file outside this family entirely —
not in any of the four settings.yml paths, not gitignored repo-clone, not host-shared settings.yml.

### A6. "I'll skip bumping `generation` because it's just a docstring change."

If you're not sure whether your edit affects the canonicalized
hash, run the round-trip test locally. When in doubt, bump.
Forgotten `generation` bumps cause silent staleness — far
worse than gratuitous re-runs.

### A7. "I'll add `applicable_when: python: ...` for this case where Form 1 would also work."

The Python escape hatch is permanent registry surface that
every reader has to context-switch into Python to understand.
Forms 1 + 2 are declarative and self-documenting; prefer them
unless they genuinely cannot express the conditional.

### A8. "I'll add a separate one-off migration script for this v0.x → v0.y schema bump."

No central migration runner. Module-local migration inside
`compute_target_state` is the only sanctioned migration
pattern. The pre-v1 breaking-change policy means you usually
don't need migration code at all — delete legacy state and
re-bootstrap.

### A9. "I want to gate one stage on multiple settings paths — I'll just nest applicable_when blocks."

The schema permits one `applicable_when` per stage. If you
need multi-condition logic, either:
(a) consolidate the conditions into one stage with a richer
`target_state_schema`, or
(b) split into multiple stages with `depends_on` chains.
Nested `applicable_when` is not supported and would be a
red flag in review.

### A10. "Two stages have the same `(module, character, locality)`; I'll distinguish by `stage_id` alone."

The (module, character, locality) triple is the identity
invariant. Two stages with the same triple cannot coexist;
collapse them into one stage with richer
`target_state_schema`, or split the module / re-classify the
locality so the triples differ.

## 17. Failure-mode philosophy — graceful degradation

The setup-stages system follows a strict graceful-degradation
discipline. Three principles:

### P1. The hook NEVER blocks session start

[ADR-0012](./docs/architecture/adr/0012-unified-check-script-trigger-model.md)
mandates the hook always exits 0. If the hook can't compute
the lifecycle diff (corrupt registry, missing settings file,
parser failure), it emits no marker and exits 0. The
architect sees "no progress" rather than "session frozen".

If you find yourself wanting the hook to "fail loudly" for
debuggability, write logging to stderr — never block.

### P2. The SKILL fails per-stage, not whole-session

If stage X's executor fails, stage X enters status `failed`
with a captured error. The SKILL **continues** with stage Y
(unless Y depends on X via `depends_on`). The architect sees
a final summary listing what completed, what failed, and
what's pending.

Avoid: "if any stage fails, abort the whole flow." That makes
debugging worse and forces architects to fix the first error
to even see the second.

### P3. External dependencies degrade to local fallback when possible

The audit module is the canonical example: if the BYO RDBMS is
unavailable, audit-log-write degrades to local jsonl + records
the degradation in the entry's `mode` field
([ADR-0019](./docs/architecture/adr/0019-zero-config-sqlite-default-audit-backend.md)
+ AGENTS.md root § "Architecture at a glance" item 4). The
session continues; observability isn't lost.

When designing a new stage with external dependencies, ask:
"if the external dependency is gone, what's the smallest
local fallback that preserves architect-visible progress?"
That's the failure mode you build.

### Architect-unreachable failure mode (CI / scripted env)

Agentic stages cannot complete without architect input. In a
CI run or scripted environment, the SKILL records
`status: blocked` (the v0.5.0 canonical name; previously
`pending-architect-input`) and exits cleanly. The
stage stays pending until the next interactive session. This
is a deliberate choice — see [ADR-0023 § Decision sub
"Agentic, architect unreachable"](./docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md).

Don't try to "handle" this with defaults / silent skips /
auto-continue. Architect-input stages exist *because* a
default would be wrong; substituting a default at agent-time
defeats the protocol.

## 18. Cross-cutting reading map

When your work touches setup-stages, the right reading order
depends on which seam you're modifying. Quick map:

| Modifying… | Read first |
|-----------|-----------|
| `scripts/stages-registry.yml` | This guide § 4–5, ADR-0014, design doc § "Stage registry contract" |
| `scripts/stages_lib/<stage_id>.py` | This guide § 6, ADR-0013, design doc § "What the lifecycle model asks of each stage" |
| `scripts/stages-registry.schema.json` | ADR-0014, JSON Schema docs |
| `hooks/session-start.sh` lifecycle-diff path | ADR-0012, design doc § "Trigger model > Hook flow", `hooks/AGENTS.md` |
| `skills/bootstrapping-repo/SKILL.md` | This guide § 7 + § 17, ADR-0023, design doc § "Architect UX", `skills/AGENTS.md` Process gate |
| `settings.yml` family layout | ADR-0021, ADR-0024, design doc § "Settings modular layering" |
| Adding a new module (M11+) | This guide § 5, ADR-0022 (if it's BoardAdapter-shaped), design doc § "Future-module inclusion procedure" |
| Adding a new BoardAdapter | ADR-0022, ADR-0005 (the core BoardAdapter contract) |
| Cross-version evolution / migration | This guide § 12 + § 13, ADR-0013 |

For everything else: **the design doc**
[`docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](./docs/architecture/0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
is the authoritative reference. The 13 setup-stages ADRs
(0012–0024) carry the per-decision rationale.

## Same-PR contract

If your stage-touching change makes a contract in this guide
stale (e.g., a new prompt-renderer kind ships, a new
applicable_when form lands, the recipe in § 14 grows a step),
fix this guide in the **same PR** — not a follow-up. Doc lag
is the failure mode this whole companion-doc pattern exists to
prevent.

This guide MUST cite the design doc + ADRs as authority and
MUST NOT carry contradictory claims. When in conflict, the
design doc / ADR wins; patch this guide.
