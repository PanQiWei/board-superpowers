### 1.6 Decomposition surface

The Producer-side capability for converting confirmed design
artifacts into Ready-state cards. This is the plugin's single
most load-bearing skill (per `decomposing-into-milestones`'s
SKILL.md): downstream Consumer correctness presupposes that the
cards Consumer reads were produced under the rules below.

The decomposition surface composes Producer F-09 (Decomposition
into cards) with the four rules below. Where F-09 names the
sequencing and the autonomy mapping, this section names the
content invariants the cards themselves must satisfy.

#### 1.6.1 INVEST criteria

- **Capability**: every emitted card passes Bill Wake's INVEST
  checklist (Wake 2003,
  *<https://xp123.com/articles/invest-in-good-stories-and-smart-tasks/>*).
  Each letter is a refusal condition — failing any letter forces
  a re-split or merge before the card lands on the board.
- **Operationalization** (per
  `decomposing-into-milestones/SKILL.md` "The INVEST gate"):

  | Letter | board-superpowers operational definition |
  |--------|------------------------------------------|
  | **I**ndependent | Doable in any order relative to siblings minus explicit `Depends on #N` lines in the Context section. No upstream-PR-must-merge-first hidden coupling. |
  | **N**egotiable | Card body describes outcomes, not prescribed implementation. Reads like a spec, not a commit message or file checklist. |
  | **V**aluable | Merging the card alone improves something user-visible or developer-visible. Pure scaffolding cards (no end-user observable outcome) are folded into the first card that consumes the scaffold. |
  | **E**stimable | An unfamiliar engineer can read the card and know roughly what shape the work takes. "TBD" / "figure out" in the criteria fails this letter. |
  | **S**mall | Fits one Consumer session, one PR, one working day at most. Under ~500 LOC / ~10 files (the L ceiling). If pressure to exceed L appears, the card is split before claim. |
  | **T**estable | Every Acceptance Criterion is an automatable check. "Feels good", "is reasonable", "works well" fail this letter. |
- **Maps to (canonical)**: Wake 2003 (INVEST as a heuristic
  checklist). Cohn 2004 *User Stories Applied* operationalizes
  the per-letter discipline (especially **S**mall and
  **T**estable) for backlog-grooming purposes; we apply the same
  per-letter rule to the per-card decomposition gate.
- **Original framing**: the **per-letter refusal-condition
  discipline** is borrowed verbatim; the
  board-superpowers-original move is making INVEST the *gate*
  (failing one letter blocks the card from landing in Backlog)
  rather than a *grooming heuristic* (something the team
  notices in passing). Gating-by-INVEST is what lets Consumer
  trust the card body without re-litigating it.
- **Autonomy**: N/A (criterion, not action). The owning action
  is F-09; the autonomy mapping lives there.

#### 1.6.2 Vertical slicing rule

- **Capability**: every card is a **vertical slice** —
  user-visible behavior end-to-end through whatever layers the
  feature crosses. Layer-split decompositions (frontend-only
  cards, backend-only cards, "set up the database" cards) are
  rejected at draft time and re-sliced before the card lands.
- **Maps to (canonical)**: Cohn 2004 *User Stories Applied*
  ch. 12 ("Splitting User Stories") — the vertical-slice
  argument as the standard refutation of waterfall layer splits.
  Patton 2014 *User Story Mapping* extends the practice to
  cross-cutting capability journeys. The canonical narrative
  picture (architect-can-verify-after-each-slice) is from Cohn.
- **Operational anti-patterns to flag** (per
  `decomposing-into-milestones/SKILL.md` "Vertical slicing"):
  - Backend-only card: "add OAuth backend routes" with no UI.
  - Frontend-only card: "add sign-in button" with no backend.
  - Schema-only card: "add user table to DB" with no read or
    write path that uses it.
  - "Wire them together" trailing card: the existence of this
    card means cards 1..N-1 each ship zero user value, and the
    sprint is a big-bang merge in disguise.
- **Operational positive pattern** (the canonical OAuth example
  from `decomposing-into-milestones/SKILL.md`): each card is a
  thinnest-possible end-to-end user-visible slice — happy-path
  sign-in (UI + minimal schema + minimal backend), profile
  surface (extends both), sign-out (button + revocation),
  error flows (UI + backend together).
- **Composes**: `decomposing-into-milestones/references/decomposition-patterns.md`
  ships a recipe library for the nine most common capability
  shapes (new feature, data model migration, new surface,
  refactor, bug fix, dep upgrade, feature flag, CRUD, async
  job). The library is a lookup, not a textbook — used as a
  shortcut when a design matches a pattern.
- **Original framing**: the **anti-pattern catalog** (the four
  layer-split shapes above) is board-superpowers-original
  scaffolding around the canonical Cohn rule. The rule itself
  is canon; the per-shape refusal list is operationalization.
- **Autonomy**: N/A (rule, not action). Owning action is F-09.

#### 1.6.3 Card body schema

- **Capability**: every emitted card body conforms to the
  thin-pointer + five-section template (plus one optional
  section and a marker comment). Defined canonically in
  `skills/board-canon/references/card-body-schema.md` (terminal
  schema, atomic SPOT) and elaborated in
  `skills/decomposing-into-milestones/references/card-schema.md`
  (decomposition-side authoring rules + filler detection); the
  schema's machine-readable bottom-marker
  (`<!-- board-superpowers:card -->`) is what lets `managing-board`
  and other tools distinguish board-superpowers cards from plain
  issues.
- **Thin-pointer block** (top of body, machine-readable):
  - `**Spec**:` — repo-relative path to the spec / plan / design
    doc, with section anchor. Multiple paths allowed (one per
    line). Repo-relative not URL (URLs go stale across branches).
  - `**Owner**:` — single GitHub @-handle of the Producer who
    owns the card.
  - `**Estimate**:` — exactly one of `XS` / `S` / `M` / `L` per
    §1.6.4. No XL, no story points, no fractional values.
  Spec docs may live in-repo under `docs/superpowers/specs/`,
  `docs/architecture/`, or in third-party storage configured at
  bootstrap. Consumer's F-C2 (Spec / plan / acceptance-criteria
  fetch) follows the pointer; Consumer never tries to re-derive
  a missing spec. Producer's Backlog → Ready transition (per
  ADR-0006 row 5 precondition) is what guarantees the pointer
  resolves.
- **Section structure** (the contract; see `card-body-schema.md`
  in `board-canon` for full per-section guidance and the OAuth
  worked example in `decomposing-into-milestones/references/`):
  - **Goal** — one-sentence outcome statement. The user-visible
    or developer-visible state-change that lands when the card's
    PR merges. Not procedural ("implement X"), not a feeling
    ("improve UX") — a concrete observable change.
  - **Acceptance criteria** — checkbox bullets; every bullet is
    a post-condition statement of a true thing in the finished
    world, automatable by check OR by an explicit human
    observation. Tasks ("implement X"), feelings ("works well"),
    and implicit items ("add tests") are forbidden.
  - **Out of scope** — bulleted list of things a Consumer
    might be tempted to fix mid-implementation. Inoculates
    against scope creep at draft time so Consumer's F-C6
    (cross-card touch hard refuse) has clear input.
  - **Dependencies** — three field types: `depends-on: #N`
    (hard — card cannot enter Ready until #N is Done);
    `depends-on (soft): #M` (preferred ordering, not required);
    `depended-on-by: #K` (reverse, informational mirror of #K's
    hard dep on this card).
  - **Execution Hints** (optional) — the one place Producer
    advises Consumer. Recommended execution skill, known
    gotcha, pre-empt-a-wrong-turn note, type tag for conditional
    gate routing (`## Execution Hints: ui` triggers Consumer's
    `/qa` gate; `: security` triggers `/cso`). Acceptance
    criteria and scope items are forbidden here (they belong in
    their own sections).
  - **Notes** — freeform rationale, driver, cross-card context,
    retro-folded lessons. Concrete pointers (file paths, PR
    numbers) over vague hand-waves. Genuine "(none —
    straightforward)" is acceptable.
- **Marker comment** — the trailing
  `<!-- board-superpowers:card -->` is protocol, not decoration.
  Tooling (managing-board's Review Queue routine, the daily
  briefing's filter logic) keys off the marker.
- **Maps to (canonical)**: Cohn 2004 (story format — the
  classic "As a <role>, I want <feature>, so that <reason>"
  narrative), but adapted: board-superpowers' Acceptance
  Criteria + Out of Scope are post-condition + scope-floor
  contracts rather than narrative-discovery surfaces.
- **Original framing**: the **machine-readable bottom marker**
  is original; canonical agile assumes humans read the cards.
  In an AI-orchestration context the marker lets tooling
  distinguish managed vs. plain issues without parsing prose.
- **Autonomy**: N/A (schema, not action). Owning action is F-09.

#### 1.6.4 Size labels (XS / S / M / L — never numeric)

- **Capability**: every card carries exactly one of four size
  labels — `XS`, `S`, `M`, `L`. No story points, no hours, no
  fractional values, no `XL` (its existence would indicate the
  card needs splitting; see ceiling rule below).
- **Calibration ranges** (per
  `decomposing-into-milestones/SKILL.md` "Size calibration"):

  | Label | Diff | Files | Intent |
  |-------|------|-------|--------|
  | XS | < 50 LOC | 1–2 | Tiny wire-ups, single-function adds, typo fixes |
  | S | 50–200 LOC | 2–5 | Typical card — the calibration target |
  | M | 200–400 LOC | 5–10 | Acceptable; Producer takes one more look for a possible split |
  | L | 400–500 LOC | up to 10 | **Ceiling.** Pressure to exceed → stop and split |
- **Ceiling rule**: 500 LOC is the empirical limit at which the
  architect can still verify a PR in one sitting (per
  `decomposing-into-milestones/SKILL.md`). If a capability
  genuinely needs more, by definition it is more than one
  vertical slice — find the slices.
- **No story points / velocity / KPI** — explicit non-goal per
  `0001-positioning.md` "Non-goals". board-superpowers does not
  track or surface velocity. This is consistent with the
  no-estimates movement (Magne Land 2010 onwards;
  *<https://martinfowler.com/bliki/NoEstimates.html>* is the
  canonical condensation) — the argument that point-based
  estimation is a low-information ritual that crowds out higher-
  signal practices like vertical slicing and continuous flow
  measurement.
- **"If a card doesn't fit one PR, split it"** — the rule that
  collapses size into a binary: does this fit one Consumer
  session, one PR, one PR-review by the architect? If yes, pick
  the matching label for retro-data calibration. If no, the
  card is wrong; splitting comes before sizing.
- **Maps to (canonical)**:
  - T-shirt sizing as practiced in Lean / Kanban (Anderson 2010
    *Kanban*).
  - **Reinertsen 2009** *Principles of Product Development Flow*
    principle B3 ("halving batch size halves cycle time") +
    Little's Law (`cycle_time = WIP / throughput`). Small batch
    size is the input-side lever; the 4-bin schema makes batch
    size architecturally explicit.
  - Refusal of points + velocity per the no-estimates movement
    (Land et al. 2010+; Fowler "StoryCounting" non-dogmatic
    condensation —
    *<https://martinfowler.com/bliki/StoryCounting.html>*).
- **Original framing**: the **fixed four-bin schema with hard
  upper bin = "split"** is operationalized for AI orchestration
  — at AI-throughput rates the architect's verification
  bottleneck is per-card, so the per-card ceiling is the
  load-bearing parameter, not the per-sprint capacity.
- **Autonomy**: N/A (label, not action). Producer's edits to
  the size label after creation are A per ADR-0006 row 2 (edit
  card body — forward incremental).

