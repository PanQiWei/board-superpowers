# Intake Routine

Triggered by: "I have a new requirement", "Let's add X", "We need Y",
"Here's an idea", "Customer asked for Z".

This is the agile "sprint planning" adapted to continuous flow. There
is no sprint — cards flow continuously from idea → Ready → In Progress.
Intake is the gate between "someone's head" and "on the board".

## Contents

- The hard gate — why a design pass is required
- Step 1 — Classify the ask (bug · chore · trivial · everything else)
- Step 2 — Route to the right design skill
- Step 3 — Wait for the design doc
- Step 4 — Sanity-check before decomposing
- Step 5 — Hand off to decomposition
- Anti-patterns

## The hard gate

**You do NOT accept a new requirement directly onto the board.** Every
new requirement goes through one of two design skills first, then comes
back as a design doc, then gets decomposed into cards.

Skipping the design pass is the single biggest source of bad cards (fuzzy
acceptance criteria, wrong vertical slice, hidden coupling). Enforce it.

## Procedure

### Step 1 — Classify the ask

Ask yourself, from the architect's message:

- **Is this a bug report?** "X is broken", "Y doesn't work in Z".
  → Skip design. Create ONE card via `decomposing-into-milestones` with
  type `bug`. Bugs are allowed to bypass design because the "design"
  was done when the feature shipped.
- **Is this a chore?** "Upgrade dep X", "Rename directory Y".
  → Skip design. Create ONE card with type `chore`.
- **Is this a trivial addition?** The architect explicitly says "this
  is a one-liner" or similar.
  → Ask once: "Truly trivial — no design needed?". If yes, one card,
  type `feature` with Size XS.
- **Anything else** (a feature, a new page, a new subsystem, a refactor
  affecting more than one module, etc.)
  → Goes through design. Continue to Step 2.

### Step 2 — Route to the right design skill

Do a just-in-time dep check (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"`).
Both skills below must be available; refuse to continue if missing.

Present the two options to the architect with a short explanation of
which fits better. Both produce a design doc you can then decompose.

> "This needs a design pass first. Two options:
>
> 1. **`superpowers:brainstorming`** — Socratic refinement. Best when
>    you already have a rough shape and want it stress-tested and
>    written down. Produces `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`.
>
> 2. **`gstack:/office-hours`** — YC-style pressure test. Best when
>    you're not sure this is worth building, or the scope is still
>    wobbly. Forces the "what's the pain" conversation first.
>
> Which fits? Once you've got the design doc, come back with
> 'decompose this' and I'll turn it into cards."

Do NOT do the design pass yourself. Do NOT try to "save time" by
combining design + decomposition in one step.

### Step 3 — Wait for the design doc

The architect runs the design skill (possibly in the same session,
possibly in another window). They come back with either:

- A path to a design doc (`docs/superpowers/specs/...`), or
- Pasted design doc content, or
- "Here's the gist: ..." (if they decided design was overkill after all).

Load the doc's content (Read the file, or use what they pasted).

### Step 4 — Sanity-check before decomposing

Before invoking `decomposing-into-milestones`, verify:

- [ ] Design doc identifies at least one user-visible capability.
- [ ] Design doc does NOT describe multiple independent subsystems.
      If it does, say so:
      > "This design spans <subsystems>. Each should get its own
      > design→decompose cycle. Which do you want to tackle first?"
- [ ] Design doc is concrete enough to extract acceptance criteria.
      If it's still "we'll figure that out in implementation", push
      back — send it back to brainstorming for one more pass.

### Step 5 — Hand off to decomposition

Invoke `decomposing-into-milestones`. Pass the design doc. Let that
skill take over. Your job in this routine ends there.

## Anti-patterns

- ❌ Don't decompose the design yourself inline. That's what
  `decomposing-into-milestones` is for — it has the INVEST and
  vertical-slice heuristics.
- ❌ Don't let the architect skip design for a "small" feature that is
  actually three features in a trench coat. The design pass's job is
  partly to catch this.
- ❌ Don't push cards to Ready during Intake. Fresh cards land in
  Backlog. Manager promotes them to Ready during a separate move.
- ❌ Don't engage the design skill's arguments yourself ("I think the
  UX should..."). You are not the designer. You hand off.
