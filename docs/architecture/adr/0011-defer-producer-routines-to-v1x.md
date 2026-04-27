# ADR 0011: Defer Producer routines F-03..F-07 + F-10..F-15 to v1.x pending demand pull

**Status:** accepted
**Date:** 2026-04-27
**Deciders:** PanQiWei (maintainer)

## Context

The Producer surface (`docs/architecture/0002-product-features-and-flows/03-producer-surface.md`) inventories 15 numbered F-routines for the Manager session: F-01 (kanban query primitive), F-02 (pending PR queue / Review Queue), F-03 (blocked sessions inspection), F-04 (today's dispatch recommendation), F-05 (board health snapshot), F-06 (context briefing on switch-back), F-07 (end-of-day overnight batch dispatch), F-08 (interactive intake & design routing), F-09 (decomposition into cards), F-10 (triage with remediation ladder), F-11 (stale session detection), F-12 (retro routine), F-13 (weekly aggregated report), F-14 (harness setup & evolution conversation), F-15 (kanban hygiene & maintenance ops).

v1-minimum ships only F-01, F-02, F-08 (per `AGENTS.md` § "Project status — v1-minimum self-hosting active"). F-09 is deferred via the deferred molecular skill `decomposing-into-milestones` (per `SKILLS.md` § "v1 minimum vs v1 complete"). The remaining 11 routines (F-03..F-07 + F-10..F-15) currently sit in the spec without a pinned ship line — neither shipped, nor explicitly deferred with a re-open trigger.

Two forces converge to make a concrete deferral decision now, rather than leaving these routines in spec-limbo:

1. **Ceremony scrutiny.** The architect's auto-memory entry `feedback_question_human_team_ceremonies_in_ai_context` establishes that Sprint / standup / refinement / retro schedules nearly all presuppose human-team cadence (multiple humans, days-to-weeks WIP, calendar-driven coordination). The plugin's actual operating mode — single architect plus 1-2 Consumer sessions, sub-day card cycle times — inverts both throughput and bottleneck. Each ceremony-shaped routine MUST be re-evaluated against AI-orchestration reality before earning implementation budget. Borrowing the vocabulary without re-justifying the shape is "P2b cosplay" — the anti-pattern that memory exists to prevent.

2. **AI cadence 100x convention.** ADR-0010 § "Project-wide AI cadence 100x convention" establishes that scope-shaped quantities (card count per batch, decomposition density, batch granularity) inherit the same 100x compression as time. Several of the deferred routines are sized in human-team scope shapes — F-04's daily dispatch recommendation, F-13's weekly report, F-12's calendar-driven retrospective. Under 100x compression these surfaces collapse into either ad-hoc demand-pull (the architect asks once and gets the answer through F-01) or per-PR Retro Notes (already on the `enforcing-pr-contract` surface). Implementing them as scheduled routines would cement vestigial human-cadence shapes into v1.

These forces require an explicit deferral with a re-open trigger. Leaving the routines in spec-limbo invites a future Consumer to "just implement F-12" because the spec lists it, without re-asking whether the ceremony shape is honest under AI cadence.

## Decision

### 1. Defer 11 Producer routines from v1 to v1.x

The following 11 routines are deferred from v1 implementation scope and remain unimplemented until a re-open trigger fires per Decision §2. They are grouped by deferral rationale; each group carries a single one-sentence reason.

**Group A — Daily-flow extensions (4 routines).** F-03 (Blocked sessions inspection), F-04 (Today's dispatch recommendation), F-05 (Board health snapshot), F-06 (Context briefing on switch-back).
*Reason:* These extend the morning-briefing / Daily flow with cards-needing-attention surfaces; under AI cadence the architect runs morning briefing on demand through F-01 (one query, ad hoc), not as a recurring ceremony, and the extensions presume a daily-ritual shape that does not exist in observed practice.

**Group B — Overnight batch dispatch (1 routine).** F-07 (End-of-day overnight batch dispatch).
*Reason:* Depends on Mode-2 spawn-Consumer infrastructure which is currently Claude Code only and experimental (per the `consuming-card` SKILL's Mode-2 status note in SKILLS.md; the `max_depth=1` budget that bounds Mode-2's compositional shape is documented in `MULTI_AGENT_DEVELOPMENT.md` and consumed by ADR-0008's reasoning about cross-plugin invocation modes); this is a dependency-chain deferral, not a ceremony question, and reopens when the Producer→Consumer subagent surface stabilizes on both platforms.

**Group C — Triage & lifecycle (2 routines).** F-10 (Triage with remediation ladder), F-11 (Stale session detection).
*Reason:* Triage cadence presupposes multi-day idle cards as the typical case; AI-cadence cards rarely sit longer than hours, and on the rare occasion they do, the architect notices through F-02's Review Queue, so a separate triage routine has not earned its keep in dogfood operation.

**Group D — Retrospective & reporting (2 routines).** F-12 (Retro routine), F-13 (Weekly aggregated report).
*Reason:* Classic Sprint-ceremony shape rejected under the cadence-scrutiny test (`feedback_question_human_team_ceremonies_in_ai_context`); AI-cadence retrospection happens per-PR in the Retro Notes section of the PR contract (already on the `enforcing-pr-contract` surface), and weekly aggregation has no consumer in single-architect operation.

**Group E — Harness & hygiene (2 routines).** F-14 (Harness setup & evolution conversation), F-15 (Kanban hygiene & maintenance ops).
*Reason:* Harness setup is one-shot bootstrap-time work already covered by `bootstrapping-repo` (an "evolution conversation" routine duplicates that surface), and kanban hygiene is event-driven on observed drift during F-01 / F-02 (the Producer notices a stale label or mis-Status while running other routines), so a scheduled hygiene sweep is unmotivated.

### 2. Re-open trigger: concrete demand pull, not calendar

A deferred routine reopens for v1.x scope when one of:

- **Architect-observed demand.** The architect runs into the routine's gap during dogfood operation and files a card describing the demand — e.g., "tracking down stale claims by hand now eats >5 minutes per Daily; need F-11."
- **Outside contributor request.** A non-architect user reports the gap, which is itself evidence the operating mode has expanded beyond the single-architect baseline that justified the deferral.
- **Adapter-second falsification arrival.** A second BoardAdapter implementation lands (per ADR-0005 § Consequences re-anchored by ADR-0010 § 2 to "v1 GA + 1 week"); some deferred routines may need re-evaluation under multi-adapter operation, particularly any whose surface assumes a single-adapter view (F-13's aggregation could be such a case).

Calendar dates are explicitly NOT re-open triggers. "Six months after v1 GA" or "by Q3 2026" are exactly the human-cadence anchors ADR-0010 § 3 banned as a project-wide convention. Re-opening happens because someone hits the gap, not because a date arrives.

### 3. What this ADR does not change

- **The F-routine catalog in `03-producer-surface.md`.** All 15 routines remain documented; the deferral adds a `**Status:** deferred-to-v1.x — see ADR-0011` stamp at each deferred routine's section header. The design work survives so v1.x re-implementation does not start from zero.
- **F-09 (Decomposition into cards).** Already deferred via the molecular skill `decomposing-into-milestones`; its deferral rationale lives in `SKILLS.md` § "v1 minimum vs v1 complete" and is not duplicated here.
- **Consumer surface (`04-consumer-surface.md`).** The F-C0..F-C14 lifecycle is unaffected — that surface is consumer-driven, not ceremony-shaped, and is fully implemented at v1-minimum via the `consuming-card` molecular skill.
- **AGENTS.md routing block.** The user-facing "Manager mode triggers" continue to enumerate routine names; queries matching deferred routines should get a "not implemented in v1 — see ADR-0011" response from `managing-board`, not silent failure.

## Consequences

**Same-PR companion edits required:**

- `docs/architecture/0002-product-features-and-flows/03-producer-surface.md`: each of the 11 deferred routine section headers (the `###### F-NN. <title>` lines for F-03..F-07 + F-10..F-15) gets a `**Status:** deferred-to-v1.x — see ADR-0011` stamp on the line immediately following.
- `SKILLS.md` § "v1 minimum vs v1 complete" table: the `managing-board` row's "Why this scoping" cell appends `; deferred routines per ADR-0011` so the citation is grep-discoverable from the catalog.
- `docs/architecture/adr/README.md`: index table appended with row for ADR-0011.

**What this enables:**

- Future Consumer claims for "implement F-12" (or any deferred routine) fail at the intake / design-review phase with a clear pointer to ADR-0011 — preventing the implementation from happening without first re-justifying the ceremony shape under AI cadence.
- Architect's retro-shaped reflection moves entirely to per-PR Retro Notes, closer to the change being reflected on, with lower drift than weekly aggregation would produce.
- v1 release scope narrows to routines with proven demand, freeing budget for v1-minimum workaround removal (the v1 release gate per `feedback_v1_release_gate_no_workarounds`).

**What this constrains:**

- A future Consumer authoring a card for any deferred routine MUST attach evidence of demand (architect quote, dogfood incident, contributor request) in the card's Notes section. "We always planned to ship F-12" is not evidence.
- Spec authors editing `03-producer-surface.md` MUST preserve the deferral stamps; removing one without a corresponding "reopen" ADR is a contract violation flagged at PR review by `enforcing-pr-contract`.

**What this rules out:**

- Implementing any of the 11 deferred routines as part of v1 GA's release scope. v1 GA ships F-01, F-02, F-08, plus the deferred-skill atomic stack (`board-canon`, `enforcing-pr-contract` already shipped; `classifying-actions`, `auditing-actions` when those land per the v1 release gate).
- Treating "we deferred it" as "we'll definitely build it later." Some of the deferred routines may never ship if AI-cadence operation continues to render them vestigial; the deferral is honest about that possibility.

## Alternatives considered

**Implement all 15 F-routines in v1.** Rejected: borrows ceremony vocabulary (Sprint / retro / standup / weekly report) without re-justifying the shape under AI cadence. Per `feedback_question_human_team_ceremonies_in_ai_context`, that path silently re-imports human-team coordination assumptions and produces vestigial surfaces nobody uses, exactly the P2b-cosplay anti-pattern.

**Defer the routines without writing this ADR.** Rejected: leaving them in spec-limbo invites future Consumers to "just implement them" because the spec lists them. An explicit deferral with a re-open trigger is what makes the spec-listed-but-not-shipped state stable across maintainer turnover.

**Defer at the per-routine level (one ADR per routine).** Rejected on scope grounds: the deferral reasons cluster into five themes (daily-flow / overnight batch / triage / retro / harness), and grouping is more honest than per-routine ADRs that would each restate the same ceremony-cadence rationale. If a single routine's deferral reason later diverges from its group, a follow-up ADR can re-litigate that one specifically.

**Calendar-based re-open trigger (e.g., "re-evaluate at v1 GA + 6 months").** Rejected: ADR-0010 § 3 banned calendar-shaped anchors as a project-wide convention. The re-open trigger MUST be event-relative (demand pull) for the same reason ADR-0005 § Consequences had to be re-anchored.

**Drop the deferred routines from the spec entirely.** Rejected: keeping them documented preserves the architectural option. Some of these routines may earn implementation under v1.x given concrete demand; deleting the design work makes the future work more expensive without reducing risk now (the spec is cheap to keep, expensive to re-derive).

## Notes

- This ADR is authored as ADR-0011, not ADR-0009 as the originating card #33 named at intake. The renumbering happened at claim-time because ADR-0009 (`0009-allow-sqlite-as-byo-audit-db.md`) was already accepted before card #33 was filed and ADR-0010 was concurrently landing via card #31. The card body's Notes section records the renumber audit trail; this ADR uses the canonical first-vacant index per `adr/README.md` § Numbering.
- The deferral does not change `managing-board` SKILL.md content directly — that skill body already only documents the v1-minimum-shipped routines (F-01, F-02, F-08). What changes is the spec's claim about why F-03..F-15 are absent: from implicit "not yet" to explicit "deferred-to-v1.x pending demand pull."
- Observed dogfood signal informing the deferral: through v0.2.0, the architect has used F-01 and F-02 daily and F-08 on every intake; zero queries have reached for F-03..F-07 / F-10..F-15 surfaces in operation. This is not yet "evidence those routines will never be needed" — it is evidence that absence has not bitten yet, which is the bar for deferral, not for permanent removal.

## Related

- ADR-0001 — Pluggable board backend (P2a / P4a are the substrate commitments whose cadence applies to the deferred routines).
- ADR-0006 — Producer autonomy boundary (defines the autonomy classes; the deferred routines would be A-class actions if implemented, with the matrix specified there).
- ADR-0008 — Plugin-to-plugin SKILL invocation (gates F-07's overnight batch dispatch on Mode-2 cross-platform stability).
- ADR-0010 — AI cadence 100x convention (the load-bearing rationale for why ceremony-shaped routines are vestigial under observed cadence).
- `docs/architecture/0002-product-features-and-flows/03-producer-surface.md` — the F-routine catalog where the deferral stamps land.
- `docs/architecture/0006-failure-modes.md` — failure-mode catalog; the deferred routines' absence is an "intended absence," not a failure mode (cross-reference clarifies the distinction).
- `docs/architecture/0007-observability.md` — observability surface; deferred routines that would have produced metrics (F-05 health snapshot, F-13 weekly report) explicitly do not, and the in-session observability surface covers what remains.
- `docs/architecture/0008-test-architecture.md` — test surface; the deferred routines have no v1 test coverage by construction, and `0008` § "What v1 deliberately does NOT test" applies the same demand-pull deferral pattern to test-coverage thresholds.
- `feedback_question_human_team_ceremonies_in_ai_context` (auto-memory) — agent-side cross-session record of the ceremony scrutiny norm.
- `feedback_v1_release_gate_no_workarounds` (auto-memory) — the v1 release gate this deferral helps fit under (narrower scope = more budget for workaround removal).
