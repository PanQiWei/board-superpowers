# board-canon — Card body schema reference

Filler-detection rules + INVEST checklist that the parent `SKILL.md` § "Card body schema" points at.

## Filler detection per section

A section fails review if its content matches any of these patterns:

| Section | Filler examples (reject) | Acceptable shape |
|---------|--------------------------|------------------|
| Goal | "TBD" / "Build the feature" / "Make it work" | "Users can claim a card by typing `/board-superpowers:consuming-card 12` — branch + worktree + Status flip happen automatically." |
| Acceptance criteria | "All tests pass" / "It works" / single bullet | ≥ 2 bullets, each verifiable independently, each names a concrete behavior |
| Out of scope | "(none)" / "N/A" without justification | Either "(none — first card in this area)" with reason, or list of tempting-but-deferred items |
| Dependencies | (empty when there ARE dependencies) | Either "(none)" or `depends-on: #N` lines per relationship |
| Notes | "See spec" without link | Concrete pointers (file paths, PR numbers) OR genuine "(none — straightforward)" |

## INVEST checklist for Acceptance criteria

A card's Acceptance criteria block passes INVEST when:

- **I**ndependent: card can be Done without other Ready cards being Done
- **N**egotiable: criteria describe outcome shape, not exact implementation
- **V**aluable: each criterion ties to a user-visible change
- **E**stimable: Producer can size the card S/M/L confidently
- **S**mall: card fits in one Consumer session (1-3 days at most)
- **T**estable: each criterion is mechanically verifiable

Cards that fail INVEST get sent back to Backlog for re-decomposition. The architect splits oversized cards by hand.

## Thin-pointer block

The thin-pointer at the top of the body is a CONTRACT, not free-form. Three required keys:

- `**Spec**:` — relative path to the spec doc + section anchor
- `**Owner**:` — GitHub @-handle of the Producer who owns the card
- `**Estimate**:` — `S` / `M` / `L`

Optional keys (used when applicable):

- `**Risk**:` — `low` / `medium` / `high` if non-default
- `**External-dep**:` — name of any external service this card touches

## Bottom marker

The bottom marker is auto-generated. Hand edits to it are explicitly rejected by `enforcing-pr-contract` — the Producer's tooling owns this block. The block points the reader at the audit-log entry stream for forensic queries on the card's history.
