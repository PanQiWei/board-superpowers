# ADR 0023: Architect UX — sequential per-stage flow + 5-element config item protocol

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

At v0.4.0 the `bootstrapping-repo` SKILL handles every
architect-facing input through a bespoke prompt path baked into
the SKILL body. Each input — audit DSN scheme, autonomy override
presets, kanban backend, WIP limit — has its own inline prompt
code. There is no shared protocol for "the plugin needs the
architect to make a configuration choice"; new items can only
be added by editing the SKILL. Three structural costs follow:

1. **Per-item bespoke UX cost.** Every new architect-facing
   feature requires SKILL code changes — its own prompt string,
   validation, and persistence call; UX drifts subtly across
   items as the catalog grows.
2. **No SPOT for "did we already ask this?".** Each prompt path
   answers it its own way (file-presence check, field test,
   hand-rolled "needs setup" flag). ADR-0013's lifecycle (4-state
   when first sketched; extended to 5-state by ADR-0020) already
   answers it generically, but the v0.4.0 prompt paths predate
   the lifecycle and do not consume it.
3. **"Skip" was contemplated as a fifth lifecycle state.** Early
   redesign drafts considered a `skipped` / `deferred` state for
   "architect declined to configure this item" — a concession to
   the bespoke-prompt mental model where each path carries an
   implicit "skip me" branch.

Per
[`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
§ "Architect UX", the architect's interaction with bootstrap
**is** the interactive configuration surface for the plugin.
Every architect-facing item is the same shape of operation —
elicit a structured choice, validate, persist. The redesign
formalizes that operation as a protocol so future plugin
versions add new items by registry edit, not SKILL edit.

## Decision

The `bootstrapping-repo` SKILL processes pending agentic stages
**sequentially** — one at a time, in topological order by
`depends_on` — and every architect-facing decision is mediated
by an agentic stage that satisfies a fixed **5-element config
item protocol**.

### Reframe — agentic stage = config-item elicitation flow

A bootstrap stage's `character: agentic` (per Axis A) means
exactly: this stage requires architect input to compute its
`target_state`. From the architect's vantage point that input
is "make a configuration choice"; from the runtime's vantage
point it is "fill in this stage's `target_state` so the
lifecycle flips to `completed`". The two perspectives describe
the same operation with the same persistence and the same
lifecycle. There is no separate "settings" UX — agentic stages
**are** the settings UX.

### Sequential per-stage flow

The hook emits `INVOKE: bootstrapping-repo / REASON: <N> stages
need running` (per ADR-0012). The SKILL reads partitioned
settings files, recomputes the lifecycle diff, topologically
orders pending stages by `depends_on`, and iterates them one at
a time:

- **Automated**: invokes the executor via `Bash` autonomously;
  records completion.
- **Agentic**: renders the stage's `interactive_prompt` by kind
  (single-choice / multi-choice / free-text / boolean /
  numeric-range); validates the response against
  `target_state_schema`; persists `target_state`; marks
  completed.
- **Agentic, architect unreachable** (CI, scripted env):
  records `status: pending-architect-input`; stage stays pending
  until next session.

The SKILL emits a final summary (completed / dependency-blocked /
pending-architect-input counts). Architects interrupting
mid-flow resume from lifecycle state on the next session — the
lifecycle model (ADR-0013) **is** the resume primitive; there is
no wizard restart.

### 5-element config item protocol

Every architect-facing config item is encoded as an agentic
stage that satisfies all five elements. New plugin features add
a registry entry plus per-stage Python helpers (per ADR-0014);
no SKILL prompt code is written per item.

1. **Schema declaration** — the stage's `target_state_schema`
   field (per ADR-0014) declares the shape of the architect's
   choice (e.g., `{wip_limit: int (1..20)}`,
   `{kanban_backend: enum [github-project-v2, linear, jira]}`)
   plus required-or-optional, default, and enum option list
   with `introduced_in_version` per option for graceful
   enum-bump compatibility.
2. **Detection** — the lifecycle 5-state model (per ADR-0013
   + ADR-0020) computes whether the item needs eliciting.
   `never-run` / `stale` ⇒ elicit; `completed` ⇒ skip;
   `deprecated` / `not-applicable` ⇒ ignore. No bespoke "is
   this set?" code per item.
3. **Interaction** — a new `interactive_prompt` registry field
   declares the prompt template + kind (single-choice /
   multi-choice / free-text / boolean / numeric-range) +
   options-source (literal list, computed-from-
   `target_state_schema.enum`, or runtime-derived). The SKILL
   ships a single generic prompt-renderer that consumes the
   declaration and produces the architect-facing question.
4. **Persistence** — the stage's `locality` (Axis B; per
   ADR-0021's settings layering) decides which of the four
   `settings.yml` files receives the resolved `target_state`
   (`host-shared` / `repo-shared` / `repo-git` / `repo-clone`).
   Atomic `mktemp + mv` write.
5. **Re-prompt trigger** — three triggers, all derived from the
   lifecycle: (a) plugin upgrade bumps `generation` → `stale` →
   re-prompt; (b) manual settings-file edit fails
   `target_state_schema` validation at load time → `stale` →
   re-prompt; (c) explicit `scripts/bsp-stage-rerun.sh
   <stage_id>` forces the stage to `never-run`. No new
   re-prompt mechanism is introduced.

### Skip semantics are eliminated

An empty / null / "no presets selected" choice is itself a valid
`target_state` value (when the schema permits empty list / null)
and produces `completed`. The 5-state lifecycle (ADR-0013 +
ADR-0020) covers all observable architect states; no `skipped` /
`deferred` state is introduced.

### Future-feature inclusion procedure

When a future plugin version introduces a new feature that needs
architect input: (1) author the new agentic stage's registry
entry in `scripts/stages-registry.yml`, filling all five
protocol elements; (2) author the per-stage Python helpers in
`scripts/stages_lib/<stage_id>.py` per ADR-0014; (3) bump the
SKILL test fixture so the prompt-renderer + persistence path is
regression-tested. **No SKILL or hook code changes are
required** — the prompt-renderer reads the new stage's
`interactive_prompt` declaration and renders the question
generically.

## Consequences

### Positive

- **Adding a config item is a registry edit + Python helpers,
  not a SKILL feature.** The per-feature bespoke-UX cost the
  redesign exists to eliminate is structurally removed.
- **Mid-flow resume is free.** Sequential iteration over the
  lifecycle's pending list means an architect closing a session
  mid-bootstrap returns to a partial state with no bookkeeping;
  the next hook tick recomputes the diff and the SKILL picks up
  from the next pending stage.
- **One prompt-renderer, one persistence path.** UX drift
  across config items is structurally prevented.
- **No fifth lifecycle state for skip semantics.** Skip
  collapses into a valid `target_state`; ADR-0013's compact
  lifecycle is preserved.

### Negative

- **`interactive_prompt` is a new registry field.** ADR-0014's
  contract grows by one declarative field; the JSON Schema gate
  absorbs the new validation rule.
- **Generic prompt-renderer is a constraint.** Stages wanting
  non-standard interaction shapes (e.g., dynamic multi-step
  flows) cannot be expressed by the protocol's five prompt
  kinds. Intentional — non-standard UX is exactly the per-item
  drift the protocol prevents — but truly non-standard
  interactions would force a protocol extension.
- **Architect cannot "skip" by intent.** Every agentic stage is
  elicited until its `target_state` lands. Architects wanting
  to defer must use `applicable_when` predicates (lifecycle
  `not-applicable`) or accept the schema's permitted empty
  default; there is no "remind me later" bucket.

## Alternatives considered

### α — Sequential per-stage flow + 5-element config item protocol (chosen). The decision above.

### β — Batch wizard (all decisions presented upfront)

Rejected. A batch wizard front-loads every pending decision into
one continuous flow. Two problems: it fragments the lifecycle
resume primitive — a mid-flow interrupt loses partial progress
because the wizard owns transient state outside the lifecycle's
per-stage entries — and a single failure (architect closes the
session, schema validation rejects one answer) aborts the whole
wizard and forces a restart. The sequential model lets each
stage's completion land independently; interruption costs at
most the in-progress stage.

### γ — Bespoke prompt code per agentic stage (status quo at v0.4.0)

Rejected. The model the redesign exists to replace. Each stage
carries its own prompt string, validation, and persistence
call; UX drifts subtly across items; adding a new
architect-facing item requires SKILL code change. The protocol
exists exactly to retire this drift surface.

### δ — Separate "skipped" lifecycle state for opt-out semantics

Rejected. A fifth state purely to express "architect declined
to configure this" duplicates what the schema already permits.
Empty-list / null / "no presets selected" are valid
`target_state` values when the schema allows; producing
`completed` from such a value is the correct semantic. A
`skipped` state would force every prompt-renderer and every
settings consumer to handle "not really configured but also not
pending" — a synthetic distinction with no operational meaning.

## Notes

The 5th lifecycle state `not-applicable` (per the redesign's
`applicable_when` predicate decision) is unrelated to skip
semantics. `not-applicable` is computed from predicate
evaluation (e.g., M3 GitHub-Project stages become
`not-applicable` when the architect chooses Linear via
`m10.repo.choose-kanban-backend`); no architect interaction is
required or offered. Skip semantics, by contrast, would have
expressed "architect declined to interact with a stage that
**is** applicable" — the protocol replaces that with "valid
empty `target_state`."

## Related

- ADR-0012 — unified check-script trigger model; emits the
  `INVOKE: bootstrapping-repo` marker the SKILL consumes.
- ADR-0013 — 5-state lifecycle (extended from 4 by ADR-0020);
  supplies the detection element (item 2) and re-prompt trigger
  element (item 5).
- ADR-0014 — stage registry contract; supplies the schema
  declaration element (item 1) and absorbs the new
  `interactive_prompt` field for the interaction element
  (item 3).
- ADR-0020 — Stage applicability + `not-applicable` 5th
  lifecycle state; combined with ADR-0013 forms the lifecycle
  detection surface this protocol's element 2 consumes; clarifies
  that `not-applicable` is unrelated to skip semantics (see Notes
  above).
- ADR-0021 — settings layering; supplies the persistence
  element (item 4) by mapping `locality` to settings file
  internal layout (two-section split + `modules.<id>`
  projection).
- ADR-0024 — settings.yml rename + new config-item stages;
  the pre-v1 file-naming change that the protocol's persistence
  file paths consume, plus the two new stages
  (`m5.repo.set-wip-limit`, `m10.repo.choose-kanban-backend`)
  that exemplify the protocol.
- [`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
  § "Architect UX" — authoritative reference for the reframe,
  the sequential flow, the 5-element protocol, the
  future-feature inclusion procedure, the settings file
  naming, and the failure surfaces.
