# Spec-first checklist — manager-side intake reference

> **Scope**: this file lists the must-have spec artifacts that
> have to land **before** a card can be created (or, in the
> spec-only case, **as** the card). It also documents when
> `docs/plans/<feature>/` is mandatory vs optional scaffolding.
>
> **Out of scope** — once a precondition is met and the card
> is created, the work itself is governed by the Consumer
> session's discipline; this file does not prescribe
> implementation order.

This reference is consumed by:

- The `intake.md` decision tree, after [`scope-shape-judgment.md`](./scope-shape-judgment.md)
  routes a requirement to "single card" or "multi-card" shape.
- The `decomposing-into-milestones` (#35) skill's Step 1 —
  before #35 ingests an artifact, the architect should have
  already cleared this checklist for the umbrella requirement.

## Why "spec first"

The board contract assumes that every card lands in a context
where the architect's reserved-power decisions (bounded-context
boundaries, cross-plugin edges, audit / autonomy / hook
contracts) are already settled. A card that needs one of
those decisions to be made *during* implementation puts the
Consumer session in an architect role it does not have — and
puts the architect into a debug role on someone else's
half-shipped work.

Spec-first eliminates that failure mode: the architect's
decisions land first (as ADRs, spec edits, or paired-PR
companion changes), then the implementation card claims the
work. Project history (#34 with ADR-0006 + spec 06; #43 with
F-B2 spec; #45 with this checklist itself) is the evidence
that the discipline pays for itself.

## Mandatory spec artifacts before card creation

Six rows. Run each row's *trigger check* against the
requirement; if the trigger fires, the named artifact MUST be
edited / created **first** (separate PR or same-PR companion,
architect's call) before the card is created. Each row cites
the change-impact matrix row in
[`docs/architecture/AGENTS.md`](../../../docs/architecture/AGENTS.md)
that owns the cross-reference graph for the artifact.

| # | Trigger | Artifact that must land first | Change-impact-matrix row | Worked example |
|---|---------|------------------------------|--------------------------|----------------|
| 1 | Touches multiple bounded contexts (per [`docs/architecture/0003-domain-model/02-bounded-contexts.md`](../../../docs/architecture/0003-domain-model/02-bounded-contexts.md) — Board / Session / Bootstrap / Audit / Spec) | ADR or §-level spec edit naming the cross-context contract | "ADR-0005 BoardAdapter contract surface" row | #34 (Audit + Spec contexts): ADR-0006 + `0005-contracts/06-audit-log-schema.md` landed first; the implementation card claimed against the settled spec. |
| 2 | Adds a new cross-plugin edge (this plugin's skill invokes a `superpowers:*` or `gstack:/*` skill that wasn't previously in the catalog) | [`SKILLS.md`](../../../SKILLS.md) § "Cross-plugin edges" gains the row | "Skill catalog (add / rename / split / merge)" row | #35: `decomposing-into-milestones` → `superpowers:writing-plans` and `gstack:/plan-eng-review` edges landed in `SKILLS.md` first (paired-PR contract). |
| 3 | Changes audit_log schema, `action_id` namespace, or autonomy matrix | ADR-0006 + [`docs/architecture/0005-contracts/06-audit-log-schema.md`](../../../docs/architecture/0005-contracts/06-audit-log-schema.md) edited first | "ADR-0006 D-AUTONOMY-1 matrix" row | #34: ADR-0006 + spec 06 landed first. The classifying-actions skill consumes both as authoritative. |
| 4 | Affects routing block (the `<!-- board-superpowers:routing -->` injection target) or hook intent injection (`INVOKE:` / `REASON:` markers) | [`docs/architecture/0005-contracts/02-hook-contracts.md`](../../../docs/architecture/0005-contracts/02-hook-contracts.md) § "Intent-injection markers" edited first | "Hook intent-injection marker grammar" row | bootstrapping-repo's routing-block injection landed against an existing spec 02 row; any new marker grammar (e.g., `INVOKE: migrating-repo-version`) requires the spec edit first. |
| 5 | Modifies `~/.board-superpowers/` host-local state layout (path conventions, file names, schema) | [`docs/architecture/0005-contracts/03-config-schemas.md`](../../../docs/architecture/0005-contracts/03-config-schemas.md) + [`docs/architecture/0005-contracts/07-path-conventions.md`](../../../docs/architecture/0005-contracts/07-path-conventions.md) edited first | "host-local state" row | bootstrap v0.2.0 (#28) and the per-repo config split (#39) both landed spec edits in the same PR as the implementation, satisfying the same-PR variant of "land first". |
| 6 | Spec-only PR (the work IS the spec — landing an ADR, a feature row, a contract page) | n/a — the artifact is itself the spec; no separate pre-card artifact | (matches multiple matrix rows depending on which spec section is touched) | #31 (ADR-0010), #33 (v1 design completeness — ADR-0011 + 0006/0007/0008 stub fills). The card body's Goal IS "land this spec"; AC is "spec page edited and reviewed". |

### Same-PR vs separate-PR for "land first"

Rows 1-5 say "land first". The architect chooses between two
shapes, both compliant with the spec-first discipline:

- **Separate PR, sequenced**: spec PR lands; implementation
  card is created against the merged spec; Consumer claims
  and ships against settled spec. Highest discipline; longest
  total flow time. Used when the spec change is itself
  load-bearing for multiple downstream cards (e.g., ADR-0006
  for #34 + #43 + future audit work).
- **Same PR, paired**: spec edit + implementation land in one
  PR. Lower flow time; relies on PR review to verify both
  halves are coherent. Used when the spec change is local to
  one card and not shared with siblings (e.g., #28's spec edit
  + bootstrap implementation).

Row 6 has no spec-first variant — the spec IS the artifact.

### Anti-patterns

- **Discovering the spec edit mid-implementation.** The
  Consumer session realizes "this card actually crosses two
  bounded contexts" or "this needs an ADR" while writing
  code. Stop, surface to architect, route the spec edit to
  managing-board intake, then resume the card after the spec
  lands. Don't ship a "we'll fix the spec later" PR.
- **Treating the change-impact matrix as a suggestion.** The
  matrix is the canonical cross-reference graph for the spec.
  If a row in this checklist says "this matrix row applies",
  the matrix's "you must also update" column is binding for
  the same PR — not a follow-up.
- **Backfilling spec after the fact.** Once a card lands
  without its spec precondition, the gap is hard to recover —
  the spec edit becomes archaeology rather than design. Catch
  the precondition at intake.

## When `docs/plans/<feature>/` is mandatory

The `docs/plans/<feature>/` scaffolding directory (gitignored,
per [`AGENTS.md`](../../../AGENTS.md) § "Implementation-facing
plans") is **mandatory** when:

| Condition | Why mandatory | Worked example |
|-----------|---------------|----------------|
| The card's AC includes a "design A/B" requirement (architect lists 2-N options + leaning + Consumer picks) | The rationale capture has to live somewhere durable enough to survive across the Consumer's session and the reviewer's read; gitignored scaffolding is the right vehicle (it's not spec — it's the work-in-progress that becomes spec if the decision is durable). | #43 AC4 — bootstrap audit-contract fix; #44 AC1 + AC3 — card schema platform field; #45 AC4 — design-left-to-consumer template (this card). |
| The card's intake produced brainstorming or eng-review artifacts (transcripts, sketches, alternatives explored) | Same reason — the artifacts have to land somewhere that the Consumer can read, but they aren't part of `docs/architecture/` (which is the durable, English-only, spec-quality store). | The audit at `docs/plans/manager-decision-frameworks/canonical-practice-audit.md` for this card (#45). |
| The decomposition produced 4+ cards | The decomposition rationale (which axis was used, what was rejected, the dep graph) lives in `docs/plans/<feature>/`. Single-card decompositions don't need it; large batches do. | When #35's decomposition pipeline produces ≥4 cards from one artifact, the audit lands in `docs/plans/<feature>/decomposition-rationale.md`. |

`docs/plans/<feature>/` is **optional** otherwise (single-card
intake with no design A/B and no extended brainstorming
artifact). The decision rests with the architect; over-using
the directory is a smell (it accumulates stale shadow-spec).

### Lifecycle

`docs/plans/<feature>/` lives only across the Manager → Consumer
cycle that produced it. When the feature's last card lands,
the architect deletes the directory in the cleanup PR.
Durable findings get promoted to `docs/architecture/` in the
PR that ships the relevant card; the rest is scaffolding that
served its purpose and gets pruned.

Per [`AGENTS.md`](../../../AGENTS.md) § "Implementation-facing
plans" — "stale plans decay silently and mislead future
readers. The feature's PRs preserve the durable record; plans
were scaffolding."

## Worked retrofit traces

Running the checklist on past cards to verify the rows
reproduce actual decisions:

- **#34** (governance skills + RDBMS). Row 1 fires (Audit
  + Spec contexts). Row 3 fires (audit_log schema +
  action_id catalog + autonomy matrix). ADR-0006 + spec 06
  + spec 03 + spec 07 + spec 02 all landed in PR #42's run-up.
  **Reproduces actual decision (separate-PR variant).**
- **#38** (v1 release-gate umbrella). Row 6 fires (the
  umbrella card body itself is the spec for the gate).
  Optional `docs/plans/v1-release-gate/` was not created
  (single umbrella card, no design A/B).
  **Reproduces actual decision.**
- **#43** (bootstrap audit drift fix). Row 1 fires (Bootstrap
  + Audit contexts). F-B2 spec edit was bundled in the same
  PR (paired-PR variant). `docs/plans/<feature>/` was
  mandatory (AC4 design-A/B). **Reproduces actual decision.**
- **#45** (this card). Row 6 partially fires — the new
  references files ARE manager-side spec, but they live under
  `skills/managing-board/references/`, not
  `docs/architecture/`; the references are SKILL-level spec
  (per [`SKILLS.md`](../../../SKILLS.md)'s SoT contract for
  skills) which falls under skill-authoring discipline, not
  spec-architecture discipline. The change-impact-matrix row
  added by AC6 is the spec-architecture artifact for this
  card; it lands in the same PR (paired). `docs/plans/<feature>/`
  is mandatory (canonical-practice audit + AC1 driving AC2-AC4).
  **Reproduces actual decision.**

## When this file is wrong

If a card lands without its spec precondition because this
checklist failed to flag the trigger, that's the signal to add
a row in the same PR that recovers the missed precondition.
The checklist is calibrated to actual misses, not to a
theoretical complete enumeration.
