# managing-board — intake routine reference

Decision tree for routing new requirements.

## Signal type → routing

```
Is the user proposing direction (vs implementation)?
├── YES → "is this worth building" question?
│   ├── YES → gstack:/office-hours
│   └── NO  → gstack:/plan-ceo-review
└── NO  → Is this an architecture decision?
    ├── YES → gstack:/plan-eng-review
    └── NO  → Is this multi-step work that needs decomposition?
        ├── YES → superpowers:brainstorming → architect hand-decomposes the result into Ready cards
        └── NO  → Single-card-sized → direct card creation
```

## Direct card creation (single-card-sized)

When the requirement clearly fits one card (small, well-defined, no design ambiguity):

1. Draft the card body using the Card body schema from `board-superpowers:board-canon`:
   - thin-pointer (Spec / Owner / Estimate)
   - Goal (1 sentence)
   - Acceptance criteria (≥ 2 verifiable bullets)
   - Out of scope
   - Dependencies
   - Notes
2. **Show the draft to the architect; do NOT create yet** (mutating action — needs acknowledgement).
3. After acknowledgement: `gh issue create --title <title> --body <body>` then add to project + set Status=Backlog.
4. Append an audit-log entry recording the card creation.

## Cross-plugin handoff syntax

When routing to a sibling plugin's skill, use the namespace prefix and explain WHY the routing applies:

```
This requirement reads as architecture-decision territory (which Postgres pooler should we adopt). Routing to `gstack:/plan-eng-review` for the design lock; report back with the artifact.
```

After the sibling skill completes, the Producer takes the artifact (a doc, a decision record) and continues the intake — usually returning to Step 1 above with a now-clearer scope.

## When to NOT route

If the requirement is genuinely just "fix this typo": skip intake entirely, do it in a 1-line PR yourself, no card needed. The intake routine assumes work that benefits from being tracked on the board.

## Decline policy

If the requirement is misaligned with the project's premises (per the project's positioning doc / non-goals), the intake routine produces a "we won't do this and here's why" response. The architect can override; the routine surfaces the conflict explicitly so the override is conscious.
