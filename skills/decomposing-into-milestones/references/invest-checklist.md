# INVEST checklist — refusal conditions per Wake 2003

> **Source**: Bill Wake, "INVEST in Good Stories, and SMART Tasks" (2003) — <https://xp123.com/articles/invest-in-good-stories-and-smart-tasks/>.
> Wake's framing is **refusal conditions**: a story FAILS if any letter does not pass. Not a checklist to "improve" a story; a gate that rejects ill-shaped stories.

## The 6 letters — Wake's words + operationalization

### I — Independent

**Wake**: > "Stories are easiest to work with if they are independent. That is, we'd like them to not overlap in concept, and we'd like to be able to schedule and implement them in any order."

**Refusal condition**: two or more cards in the batch overlap conceptually OR cannot be scheduled in any order, AND no `depends-on` declares the coupling.

**Operationalization for board-superpowers**:
- Walk pairwise across the batch. For each pair, ask: "could a Consumer reasonably claim card B before card A is `Done`?"
- If "no, B's implementation needs A's behavior", then card B MUST declare `depends-on: #A` in its `## Dependencies` section. Otherwise refuse — independence is broken silently.
- Concept overlap = two cards both add a "session token cache" or both define an "OAuth callback handler" without one claiming primacy. Refuse.

**Wake's nuance often dropped**: Independence is an *ideal*, not absolute. Wake explicitly allows tiered estimates ("3 points for the first report, then 1 each") to handle inherent shared scaffolding. Declared coupling via `depends-on` is the escape valve — silent coupling is what's refused.

### N — Negotiable

**Wake**: > "[A card is] not an explicit contract for features; rather, details will be co-created by the customer and programmer during development." A card is "a token promising a future conversation."

**Refusal condition**: card body reads as an explicit upfront contract — paragraphs of implementation prose, every detail nailed down, no room for the implementer to discover a better shape.

**Operationalization**:
- Card body should read as a **placeholder for conversation**, not a commit-message-shaped specification.
- Acceptance criteria are **post-conditions on the finished world** ("login button persists session token in cookie store"), not procedural recipes ("step 1: install nextauth; step 2: configure callback URL...").
- If the body reads as a transcript of what to type, refuse — it's over-specified.

**Wake's nuance often dropped**: "Negotiable" does NOT mean "we can renegotiate scope mid-sprint". It means the card's body is intentionally under-specified at draft time so the implementer can co-create the spec during implementation. Scope is fixed; details are negotiable.

### V — Valuable

**Wake**: > "Each story has to be valuable to the customer (either the user or the purchaser). One way is to have customers write the stories. Another approach is to make sure each story is written so as to reflect value to the customer."

**Refusal condition**: merging the card alone does not improve any user-visible / developer-visible state. Layer-only slices (frontend / backend / schema) typically fail this letter.

**Operationalization**:
- For each card, articulate the **observable state change** that lands when the card's PR merges. If the answer is "no observable change yet, downstream cards finish the chain", refuse.
- "Vertical slice" (Cohn) is the operational shape that satisfies V — each slice cuts through the full layer stack, so its merge moves the user-visible state.
- "Customer" in board-superpowers context can be the **architect** (developer-experience improvements), not just an end user. Internal tool cards are valuable if they improve the architect's loop.

### E — Estimable

**Wake**: > "We have to be able to estimate the size of a story. (Just enough to help the customer rank and schedule its implementation.) Things that can make it inestimable include: lack of domain knowledge ... lack of technical knowledge ... the story is just too big."

**Refusal condition**: card body contains "TBD", "figure out", "we'll see", "depends on what we find" — any phrasing that admits the size is not yet known.

**Operationalization**:
- Apply the 4-bin calibration in `references/size-calibration.md`. If the card cannot be confidently placed in `XS|S|M|L`, it's inestimable — refuse.
- For inestimable cards driven by **domain ignorance**, run a **spike** first (a research card with `Estimate: S` and AC = "we have an answer to question X"). Spikes are legitimate; "TBD" cards are not.
- For inestimable cards driven by **size**, the card is too big — split via SPIDR.

**Wake's nuance often dropped**: Estimable and Small are coupled — "bigness" itself causes inestimability ("above this size, and it seems to be too hard to know what's in the story's scope"). Treat them as one gate, not two.

### S — Small

**Wake**: > "Stories typically represent at most a few person-weeks worth of work. (Some teams restrict them to a few person-days of work.) Above this size, and it seems to be too hard to know what's in the story's scope."

**Refusal condition**: estimated size exceeds the L ceiling (per `references/size-calibration.md`).

**Operationalization**:
- L is the ceiling — past L, refuse. Find a SPIDR axis (Paths / Data / Rules) and split.
- The ceiling is calibrated for "an architect can verify the PR in one sitting". This translates to ~500 LOC + 10-15 files for board-superpowers cards.
- AI-orchestration reframe: under AI cadence, the human-team "few person-weeks" is meaningless. The recalibration is on **architect verification capacity**, not implementer execution time. (See `size-calibration.md` § "AI-cadence reframe" — original framing.)

### T — Testable

**Wake**: > "I understand what I want well enough that I could write a test for it." If a story isn't testable, "you usually don't understand it well enough" or "it's not really about something the customer values."

**Refusal condition**: AC contains feeling-words or vague qualifiers — "feels good", "works well", "is reasonable", "looks correct", "performs well".

**Operationalization**:
- Each AC bullet must be a concrete, post-condition statement that can be checked by a script OR by an explicit human observation list (e.g., "[ ] PR's `bash test/x.sh` exits 0", "[ ] open the page; observe the form field shows the saved email").
- Untestable signals one of two things: (a) the team doesn't yet understand the requirement well enough — refuse and clarify; (b) the requirement is not actually about user-value — refuse and reframe.
- Non-functional requirements (performance, security) MUST be operationalized: "page loads under 200ms p50" is testable; "page loads quickly" is not.

## Reframe playbook

When a card fails one letter, use these reframes to fix the shape without restarting the whole pipeline:

| Failed letter | Reframe move |
|---|---|
| **I** | Add explicit `depends-on` to declare the coupling, or merge the cards if coupling is too tight. |
| **N** | Strip implementation detail from body; restate AC as post-conditions. |
| **V** | Find a vertical seam; restate the card so its merge changes observable state. |
| **E** | Split a spike out as a separate `S`-sized card; let it land first. |
| **S** | Split via SPIDR axis — Paths (alt user paths), Data (subset formats), Rules (defer rules). |
| **T** | Replace feeling-words with concrete checks; if no concrete check exists, the AC is not actually about a user-visible behavior. |

If two or more letters fail, the card's shape is structurally wrong. Restart from Step 2 of the SKILL pipeline.

## AI-orchestration reframe (original framing — no canonical source)

> ⚠️ **No canonical primary source found.** The 2003 INVEST framing assumes a human-team / customer-developer dialogue. Under AI orchestration, several letter semantics shift. The reframe below is **original framing** from board-superpowers (per memory `feedback_research_canonical_practice_first.md`).

| Letter | Human-team semantics | AI-orchestration recalibration |
|---|---|---|
| I | "schedulable in any order by humans" | "claimable in any order by AI Consumer sessions; coupling declared via `depends-on`" |
| N | "co-created by customer + programmer in conversation" | "co-created by architect + Consumer in PR rework loop; AC are post-conditions, not procedure" |
| V | "valuable to the customer (user or purchaser)" | "valuable to the architect (developer-experience) OR end user; both count" |
| E | "team can estimate from domain + tech knowledge" | "fits in 4-bin calibration; spikes are legitimate first-cards for unknowns" |
| S | "few person-weeks max" | "architect can verify PR in one sitting (~500 LOC, 15 files ceiling)" — recalibrated on **verification capacity**, not implementer execution time |
| T | "team can write a test" | "AC are concrete post-conditions checkable by script OR explicit human observation" |

The Independence / Negotiability / Value / Testability semantics are **platform-agnostic** — a layer-only card is just as broken whether a human or AI implements it. The Size and Estimability recalibrations are AI-specific because human-team time-based sizing breaks under AI cadence.
