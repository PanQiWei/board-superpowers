# ADR 0010: Re-anchor ADR-0005 Consequences deadlines to v1 GA + project-wide AI cadence 100x convention (supersedes ADR-0005 § Consequences partial)

**Status:** accepted
**Date:** 2026-04-27
**Deciders:** PanQiWei (maintainer)

## Context

ADR-0005 § Consequences pinned two human-cadence anchors when
the contract surface was first accepted on 2026-04-25:

- **GitHubProjectAdapter wrapper port** — "Hard deadline:
  wrapper port lands within 60 days of this ADR's acceptance
  (i.e., by **2026-06-24**), or P2a is downgraded from
  'present commitment' to 'aspirational'."
- **6-month falsification check** — "If no second adapter has
  been seriously attempted by **2026-10-25**, file a retro
  card reconsidering whether P2a + P4a are honest commitments
  or aspiration. Mechanism: a `chore` Backlog card titled
  `P2a/P4a falsification check (2026-10-25)`…"

Two days of dogfood reality on this very repo — plus the
project's now-explicit cadence expectations — surface a
mismatch the original anchors did not anticipate:

- **Deadlines were sized in human-team cadence.** A 60-day
  hard deadline approximates one sprint-length; a 6-month
  falsification check approximates a quarterly retrospective.
  Both shapes presuppose throughput that an AI-orchestrated
  solo project does not have — neither the bottleneck nor the
  release rhythm matches the assumption baked into those
  numbers.
- **Observed cadence on this repo is ~100x compressed.**
  Between v0.1.0-minimum (2026-04-24) and v0.2.0 (2026-04-26),
  the project shipped roughly a sprint's worth of
  spec + implementation in two days. ADR-0009 itself landed
  two days after ADR-0006. At that cadence, "60 days" and "6
  months" no longer behave as deadlines — they behave as
  forgotten footnotes.
- **The architect's natural-language intervals already
  presume AI cadence.** Phrases like "in two weeks" or "by
  next quarter" stated in conversation reflect AI-cadence
  intentions, not the human-team intervals the same words
  imply when read literally. Without a project-level
  convention, future spec authors silently re-import
  human-cadence semantics into new ADRs and re-introduce the
  same anchor mismatch.
- **Anchor types matter as much as anchor sizes.** The
  wrapper port's deadline is *internal* (it gates a P2a
  downgrade); the falsification check's anchor is *external*
  (it asks "did anyone outside try"). The right anchors are
  not just "smaller numbers" — they are anchors whose
  triggering events are observable and *meaningful* under the
  observed cadence: "before v1 GA" for an internal gate;
  "v1 GA + 1 week" for a market-facing observation window.

These forces require re-anchoring without re-litigating the
rest of ADR-0005. The contract surface (type definitions,
method signatures, error semantics, status mapping policy)
remains immutable per ADR-0005's own immutability gate. Only
the two deadline anchors in § Consequences move, and a
project-wide cadence convention is added so future ADRs
inherit the new semantics by default.

## Decision

Three things land in this ADR. Each is stated as a positive
present-tense claim.

### 1. Re-anchor the wrapper-port deadline

ADR-0005 § Consequences "GitHubProjectAdapter wrapper port"
item's `Hard deadline` sub-bullet is replaced with:

> **Hard deadline:** wrapper port lands **before v1 GA**, or
> P2a is downgraded from "present commitment" to
> "aspirational" via a 0001-positioning.md amendment.

No fixed calendar date. The anchor is the v1 GA milestone
itself; the wrapper port is internal architecture and gates
the P2a commitment, so the natural anchor is the moment
P2a's "present commitment" first faces external readers (the
GA announcement), not an arbitrary calendar offset from the
ADR's acceptance date.

### 2. Re-anchor the falsification check

ADR-0005 § Consequences "6-month falsification check" item is
replaced with:

> **Falsification check (v1 GA + 1 week, AI cadence).** If no
> second adapter has been seriously attempted by **v1 GA +
> 1 week**, file a retro card reconsidering whether P2a + P4a
> are honest commitments or aspiration. Mechanism: a `chore`
> Backlog card titled `P2a/P4a falsification check (v1 GA +
> 1w)` is filed in the same Backlog the day this ADR's PR
> merges; the title is **edited to** `P2a/P4a falsification
> check (YYYY-MM-DD)` once v1 GA is declared and the absolute
> date becomes computable.

The two-stage title (placeholder before GA → absolute date
after GA) is a deliberate choice: while v1 GA is unscheduled
the title carries a stable symbolic anchor visible in any
Backlog scan; once v1 GA lands the title self-updates to a
concrete date that grep tools and humans can act on.

### 3. Project-wide AI cadence 100x convention

The following is hereby a project-level convention,
spec-level binding on all docs under `docs/architecture/`
and `docs/board-superpowers/`:

> All time estimates, deadlines, and intervals in this
> project's specs assume AI orchestration acceleration of
> ~100x vs human-team baselines unless explicitly noted
> otherwise. User-stated natural-language intervals are
> AI-cadence native and not further compressed.

Scope coverage extends beyond time. The same 100x
compression applies to **scope-shaped quantities** that are
sized by analogy with human-team estimation conventions:

- **Card count per batch.** Human-team backlog grooming sizes
  a sprint at 8–15 cards; AI-cadence batches are sized 1/100
  of that envelope and re-decomposed each session, not
  pre-loaded for two-week windows.
- **Decomposition density.** Human-team story splitting aims
  for ~1-week stories; AI-cadence cards target the equivalent
  of "complete in one consumed card" (S-size cards mapping to
  hours of architect interaction, not weeks of solo work).
- **Batch granularity.** "Sprint-shaped" plan grouping
  (multiple weekly sub-deliveries) collapses to a single
  ad-hoc batch when the AI-orchestration throughput makes
  the multi-week shape vestigial.

User-stated quantities of any of the above (time, card count,
batch size) are AI-cadence native — when the architect says
"two weeks" or "five cards" or "this batch", those
expressions reference the post-100x reality already and are
**not** to be re-divided by a future spec author.

The convention's intent: prevent future spec authors from
reaching for human-team rules of thumb and silently
re-importing the wrong cadence assumptions. When in doubt,
spec authors cite this ADR as the canonical source of the
convention.

### What this ADR does not change

- **ADR-0005 contract surface** — type definitions, method
  signatures, error semantics, status-mapping policy. All
  immutable per ADR-0005's own immutability gate. This ADR
  touches only the two § Consequences deadline anchors.
- **No other ADR's contract surface.** ADR-0001 P2a / P4a
  framing stays as-is; the falsification mechanism stays;
  only the trigger date shape changes.
- **No chore card is filed by this ADR.** Filing the chore
  card titled `P2a/P4a falsification check (v1 GA + 1w)` is
  the responsibility of card #32, which is queued and waits
  for this ADR to land so the title is contract-compliant.
- **No 0001-positioning.md amendment.** The 100x convention
  is a cadence convention, not a P-level commitment; it goes
  into spec's ADR layer because that is where conventions
  binding on future spec authors live.

## Consequences

**Same-PR companion edits required:**

- `docs/architecture/adr/0005-board-adapter-contract.md`:
  - Header `Status:` field amended to
    `accepted; § Consequences amended by ADR-0010`.
  - § Consequences "GitHubProjectAdapter wrapper port" item:
    `Hard deadline` sub-bullet's anchor replaced per
    Decision §1 above. The 60-day calendar date
    (`2026-06-24`) is removed.
  - § Consequences "6-month falsification check" item:
    anchor + chore card title replaced per Decision §2 above.
    The 6-month calendar date (`2026-10-25`) is removed.
- `docs/architecture/adr/README.md`:
  - Index table appended with row for ADR-0010.

**What this enables:**

- Future spec authors cite this ADR as the canonical source
  of the AI-cadence convention; "by next quarter" and "in
  two weeks" stop carrying ambiguous semantics across
  authors.
- Wrapper-port and falsification-check anchors become
  observable under the project's actual release shape rather
  than aging into forgotten calendar dates.
- Card #32 unblocks: it can be filed with a contract-
  compliant title once this ADR lands.

**What this constrains:**

- When v1 GA is declared, the chore card titled `P2a/P4a
  falsification check (v1 GA + 1w)` MUST be edited to
  `P2a/P4a falsification check (YYYY-MM-DD)` with the
  absolute date computed as GA + 7 days. This is a one-shot
  edit, not a recurring obligation; tracking lives on the
  chore card itself, not in this ADR.
- Spec authors quoting human-team timing references in new
  docs MUST either translate to AI cadence or annotate the
  reference with `(human-team baseline; AI cadence applies
  per ADR-0010)` so the divergence is visible at read time.

**What this rules out:**

- Silent re-introduction of human-cadence numbers in new
  ADRs. Calendar-shaped deadlines that presume human-team
  throughput are rejected at PR review unless the deadline's
  context (e.g., a vendor's external SLA) is genuinely human-
  cadence-bound and explicitly so noted.
- Treating the 100x convention as a fudge factor. The
  convention is not an excuse to under-spec; it is a unit
  conversion. Decomposition rigor (INVEST, vertical slicing)
  and verification rigor (verification chain in
  `consuming-card`) are unaffected.

## Alternatives considered

**Leave ADR-0005 § Consequences anchors unchanged; rely on
the architect to remember the dates.** Rejected: at observed
cadence both anchors age out of relevance within days of the
ADR landing. A deadline that the architect "remembers to
ignore" defeats the purpose of recording the deadline at
spec level.

**Update only the dates (e.g., "30 days" → "3 days") and
keep calendar anchors.** Rejected: smaller numbers do not
fix the *kind* of anchor mismatch. The wrapper port's
correct anchor is "before v1 GA" (it gates a public
commitment); the falsification check's correct anchor is
"v1 GA + 1 week" (it observes a market-facing window). Both
are event-relative, not calendar-relative; mechanically
shrinking the calendar offset misses that.

**Bulk-revise every human-cadence anchor across all 9
existing ADRs in this PR.** Rejected on scope grounds: the
"one ADR per architectural decision" rule (ADR-0001 § Notes,
ADR-README.md) means each anchor revision should be its own
ADR with its own context. Card #31 is scoped to ADR-0005's
two anchors; other ADRs that need similar re-anchoring get
their own cards.

**Codify the 100x convention only in `AGENTS.md` /
`CLAUDE.md` instead of an ADR.** Rejected: those files are
developer-onboarding guides, not spec-level decisions.
Conventions binding on future spec authors live in ADRs so
they survive guide rewrites and so their rationale is
preserved alongside other architectural decisions. AGENTS.md
may cross-reference this ADR; the canonical source stays
here.

**Restrict the convention to time only; leave scope-shaped
quantities (card count, batch granularity) for a later
ADR.** Rejected after architect feedback during the
pre-claim brainstorm for this card: time and scope share
the same human-team-baseline source, and splitting them into
two ADRs would replay the same context twice. Coverage of
both at first drafting is cheaper and clearer; if either
dimension produces emergent friction later, a follow-up ADR
narrows or extends as evidence accumulates.

## Notes

- The driver for this ADR is recurring architect feedback
  during the v1-complete intake batch — captured both in
  the user's `feedback_ai_cadence_100x.md` auto-memory entry
  for cross-session continuity and in spec form here. The
  auto-memory entry is an agent-side convenience; this ADR
  is the project-level binding source.
- Scope coverage of the 100x convention (Decision §3
  "scope-shaped quantities" sub-list) reflects the
  architect's amended intent — `feedback_ai_cadence_100x.md`
  was updated mid-claim from "time only" to "time AND
  scope," and this ADR follows the amended intent rather
  than the card's original AC text. This is a permitted
  one-step expansion (still within the ADR-0010 charter of
  "establish project-wide AI cadence convention") and is
  surfaced in the PR's Retro Notes for review-time
  visibility.
- This ADR ships before v1 GA is declared. The GA-relative
  anchors are deliberate forward references; they activate
  semantically the moment v1 GA is announced. Until then
  the chore card filed by #32 carries the placeholder title
  per Decision §2.
- Future ADRs that need to re-introduce human-cadence
  numbers (e.g., a vendor SLA, an external regulatory
  deadline) MUST annotate them per the convention's
  divergence rule above; otherwise PR review treats the
  number as suspect.

## Related

- ADR-0001 — Pluggable board backend (P2a / P4a are the
  premises whose falsifiability this ADR protects).
- ADR-0005 — v1 BoardAdapter contract surface
  (§ Consequences partially superseded by this ADR;
  contract surface unchanged).
- ADR-0006 — Producer autonomy boundary (the ADR that
  defines AI-orchestration's mutation semantics; this ADR
  formalizes the cadence side of the same orchestration).
- ADR-0009 — Allow SQLite as a BYO audit DB scheme
  (precedent template for "partial supersession of an
  earlier ADR's specific section").
- `0001-positioning.md` P2a, P4a, P3 — substrate-commitment
  and solo / small-team scale framing whose cadence is now
  explicitly AI-baseline.
- `feedback_ai_cadence_100x.md` (auto-memory) — agent-side
  cross-session record of the convention; spec-level binding
  source is this ADR.
