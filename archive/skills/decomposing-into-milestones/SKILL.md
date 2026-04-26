---
name: decomposing-into-milestones
description: Use when the architect (or Board Manager) brings a design doc, spec, or multi-point requirement that needs to be turned into GitHub Project cards. Triggers include "decompose this", "turn this into cards", "break this down into milestones", "what cards do we need for this feature". Produces cards sized so one Consumer session delivers one as one PR; enforces INVEST and vertical slicing.
---

# decomposing-into-milestones

Turn a design doc into N GitHub Project cards, each sized so a single
Consumer session can deliver it as one PR.

This is the plugin's single most load-bearing skill. Whether the board
works lives or dies by how well decomposition obeys INVEST and vertical
slicing — the downstream skills assume the cards they read were
produced here.

## Preflight

1. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"` — exit 2 → abort.
2. Invoke `board-protocol` to load the card schema into context. Every
   card you emit must pass that protocol.
3. Confirm `.board-superpowers/config.yml` exists. If not, redirect to
   `using-board-superpowers` for bootstrap — label creation must happen
   first or `create-card.sh --label` calls will silently fail.

## Source material — what you can decompose

In order of preference:

1. Design doc from `superpowers:brainstorming`
   (`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`).
2. Design doc from `gstack:/office-hours` or `gstack:/plan-eng-review`.
3. Pasted design-doc content.
4. Multi-paragraph plain-text description.
5. **Not acceptable**: a one-liner like "add OAuth". Refuse and route
   back through intake — design pass first.

Read the source fully. Do not proceed until you can answer: **what is
the user-visible capability being delivered?**

## The INVEST gate

Every card you emit must pass every letter. If a candidate card fails
one, split it further or fold it into a sibling.

| Letter | Question | Fails if... |
|--------|----------|-------------|
| **I**ndependent | Doable in isolation, any order, relative to siblings (minus explicit deps)? | Requires a sibling merged first for reasons beyond a listed dependency |
| **N**egotiable | Describes outcomes, not a prescribed implementation? | Reads like a commit message or a checklist of files to edit |
| **V**aluable | Merging this card alone improves something user-visible or developer-visible? | Pure scaffolding — fold it into the first card that uses it |
| **E**stimable | An unfamiliar engineer can read it and know roughly the shape of the work? | Has "TBD" or "figure out" in the criteria |
| **S**mall | One Consumer session can finish in one PR without heroics? | Expected diff > ~500 LOC or > ~10 files |
| **T**estable | Every acceptance criterion is an automatable check? | "Feels good", "is reasonable", "works well" |

## Vertical slicing — the non-negotiable heuristic

The most common decomposition mistake is splitting by **layer** (front,
back, schema) instead of by **capability** (one user-visible thing,
end-to-end, thin).

Correct:

```
Card 1: user can sign in with Google (happy path, minimal UI,
        skeleton DB schema just enough to store the session)
Card 2: user sees an avatar after sign-in (extends schema, adds UI)
Card 3: user can sign out (button, revocation, redirect)
Card 4: sign-in handles denied-consent error (error UI + backend)
```

Anti-pattern to reject:

```
Card A: add user table to DB
Card B: add OAuth backend routes
Card C: add sign-in UI
Card D: wire them together
```

The anti-pattern means A–C produce zero user value alone — they
violate **V**. Until D merges, nothing works; the whole sprint is a
big-bang merge in disguise. The architect cannot verify end-to-end
after any of A–C.

When the design doc tempts you toward layer splits, re-slice vertically
before writing any cards. The question to ask: **"what is the thinnest
thing a user could do after Card 1 alone merges?"** That answers what
Card 1 is.

**Pattern library** — common capability shapes and their canonical
decompositions: [references/decomposition-patterns.md](references/decomposition-patterns.md).
Skim first when the design matches a pattern (new user-facing feature,
data model migration, new surface, refactor, bug fix, dep upgrade,
feature flag, CRUD, async job).

## Size calibration

Target distribution:

| Label | Diff | Files | Intent |
|-------|------|-------|--------|
| **XS** | < 50 LOC | 1–2 | Tiny wire-ups, single-function adds |
| **S** | 50–200 LOC | 2–5 | Typical card — aim here |
| **M** | 200–400 LOC | 5–10 | Acceptable; look once more for a split |
| **L** | 400–500 LOC | up to 10 | Ceiling. If you feel pressure to exceed, stop and split |

Never emit XL. The ceiling is the commit the architect can still verify
in one sitting; past 500 LOC that breaks down. If a capability genuinely
needs more, it's more than one vertical slice — find the slices.

## Procedure

### 1. Identify capabilities

Read the design doc. List every user-visible (or developer-visible, for
internal tools) capability. Present to the architect:

> "I see `<N>` capabilities in this design:
>   1. `<one line>`
>   2. ...
>
> Any missing? Any that shouldn't be here? Any that should be merged?"

Do not proceed until the list is confirmed.

### 2. Order by dependency

For each capability, note hard deps on others. Hard = "cannot
demonstrate B without A already working". Not = "would be nicer to
build A first for cleanliness".

Present the dep graph as a simple list and confirm.

### 3. Slice each capability

For each confirmed capability, propose a thinnest-possible first
slice, then successive slices. One capability at a time:

> "Capability: `<name>`. Proposed slices:
>
> **Slice 1:** `<thinnest demonstrable version>`
> **Slice 2:** `<next increment>`
> ...
>
> OK to draft cards for this?"

Let the architect push back before anything lands on paper.

### 4. Draft each card

For each confirmed slice, fill in the five-section card body. See the
full template, per-section rules, and a worked OAuth example in
[references/card-schema.md](references/card-schema.md).

Key reminders while drafting:

- **Context** references the design doc by path, names 2–4 files the
  Consumer will touch, lists deps as `Depends on #<N>`.
- **Acceptance Criteria** are post-conditions ("X is true in the
  finished world"), not tasks. Every one is automatable.
- **Out of Scope** pre-empts gold-plating. List anything a Consumer
  might be tempted to fix "while in here".
- **Size** is a label: XS / S / M / L only.
- **Execution Hints** is optional — name a recommended execution skill
  and any known gotcha. Do not put acceptance criteria or scope here.

### 5. Review the set with the architect

Before pushing anything to the board:

> "`<N>` cards, total estimated diff ~`<X>` LOC across ~`<Y>` files.
> Dependency chain:
>   #A → #B → #C
>   #D (independent)
>   #E → #F
>
> Thoughts before I push these?"

Common pushback and how to respond:

| Architect says | Response |
|----------------|----------|
| "Card C is too big" | Back to step 3 for that card, split further |
| "A and B should be one card" | Both probably too small alone (violates **V**); merge, revisit **S** |
| "What about capability X?" | Add to step 1 list, redo step 2 |
| "Push them, looks good" | Proceed to step 6 |

### 6. Push to the board

For each card:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/create-card.sh" \
  --title "<title>" \
  --body-file /tmp/card-body.md \
  --project "$PROJECT" \
  --label "type:feature" \
  --label "size:S"
```

After creation, resolve cross-references: `Depends on #<SLICE_2>`
placeholders → real issue numbers once both cards exist.

All cards land in **Backlog**, never `Ready`. The architect promotes
to `Ready` in a separate move so that `Ready` always means "I looked
at this again and decided it's actionable now".

### 7. Report

> "`<N>` cards created in Backlog: #<first>–#<last>. Promote to Ready
> when you want, and I can generate kick-off prompts."

Do not promote to Ready automatically. Do not generate kick-off prompts
here — hand back to `managing-board` and let the architect drive.

## Anti-patterns

- ❌ Decomposing before the capability list is confirmed. You'll split
  along the design doc's structure instead of along user value.
- ❌ Splitting by layer (front/back/db). Always by capability.
- ❌ Cards bigger than L. Always split further.
- ❌ Acceptance criteria in "will do X" form. They must be "X is true",
  testable post-conditions.
- ❌ Skipping step 5. Creating 15 cards the architect didn't agree with
  is a loud, expensive mistake on GitHub.
- ❌ Adding cards for things the design doc didn't cover. Surface the
  gap in step 1, not as a silent new card later.
