# Triage rule — 5-step short-circuit

After the matrix lookup yields a default class, run these 5 tests in
order. The first match wins. If a test matches AND the default is A,
escalate to R. If the default is already R, no change.

## The 5 steps

1. **Touches an architect-reserved power**? (merge a PR, alter an
   architectural decision recorded in an ADR) → R
2. **Modifies a source-of-truth file**? (CLAUDE.md, AGENTS.md,
   `.board-superpowers/config.yml`, `.board-superpowers/config.local.yml`,
   any maintainer-side spec / ADR document) → R
3. **Interrupts or risks losing in-flight work**? (transitions a card to
   Blocked while a Consumer holds it; closes a card with an open claim
   branch; cancels an active claim that has uncommitted work) → R
4. **Cross-card structural change**? (splits one card into multiple,
   mutates a schema invariant that other cards depend on) → R
5. **Otherwise** → no change (use the matrix default).

## Why these 5 and not more

These 5 are a deliberate floor, not an exhaustive enumeration. Each maps
to a distinct concern (reserved power; truth-source integrity;
in-flight-work safety; cross-card structural integrity). New action
patterns that don't fit any of these and aren't already classified in
the matrix get the matrix default (A by fall-through). If a new pattern
needs special handling, it gets a new matrix row, not a new triage step.

## Examples

- "Edit card body to add an acceptance criterion" — matrix row 2 (A).
  None of the 5 steps match. Class: A.
- "Update AGENTS.md to add a new tech-stack item" — matrix row 4 (R).
  Step 2 matches. No change needed (already R). Class: R.
- "Backlog → Ready transition" — matrix row 5 (A). Step 4 does NOT
  match (status transition is single-card; doesn't mutate cross-card
  structure). Class: A.
- "Close a card that has an active claim branch" — matrix row 7 (R).
  Steps 3 + 4 match. Already R. Class: R.
