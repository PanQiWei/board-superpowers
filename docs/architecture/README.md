# board-superpowers — architecture

This directory holds the architectural specification of board-superpowers.

**Audience.** Plugin maintainers. End-users see the root `README.md`
and the runtime banner from `using-board-superpowers`.

**Scope.** What the system *is* and *why* it is structured this way.
For *how to do things* (change-impact matrix, maintenance checklists,
release flow), see `AGENTS.md` at the repo root — that file is
operational, this directory is foundational.

## Reading order

1. [`0001-positioning.md`](./0001-positioning.md) — what we're for, who we're
   for, what we're explicitly not. Every other doc here hangs off
   these answers; start here.
2. [`0002-product-features-and-flows/`](./0002-product-features-and-flows/README.md)
   — features the product offers (catalog) and user flows (journey).
   The architectural spec for the product surface; constrains every
   downstream decision. Split into per-section files inside the
   directory; start at the README index.
3. [`0003-domain-model/`](./0003-domain-model/README.md) — entities,
   bounded contexts, aggregates, domain events, relationships,
   invariants. Split into per-section files inside the directory;
   start at the README index.
4. [`0004-component-architecture.md`](./0004-component-architecture.md) — how
   the surfaces (hooks / scripts / skills / external plugins) compose,
   why this carving.
5. [`0005-contracts.md`](./0005-contracts.md) — every cross-component contract,
   pinned + versioned.
6. [`0006-failure-modes.md`](./0006-failure-modes.md) — known failure modes,
   detection signal, recovery, ownership.
7. [`0007-observability.md`](./0007-observability.md) — how a maintainer knows
   the plugin is healthy at runtime, not just installed.
8. [`0008-test-architecture.md`](./0008-test-architecture.md) — what gets
   tested at which layer, and why some layers have no tests yet.
9. [`adr/`](./adr/) — decision records for the choices that defined
   the shape. Read in numeric order.

## Evolving these docs

- Architecture changes land **before** the implementation that
  depends on them. PR order: ADR → architecture doc update → code.
- A new contract surface → new entry in `0005-contracts.md` AND a test
  in `tests/`.
- A new failure mode found in production → new row in
  `0006-failure-modes.md`, even if the recovery decision is "we accept
  this".
- ADRs are immutable once accepted. Superseding an ADR creates a
  new one; the old one's status field gets `superseded by ADR-N`.

## Status

Skeleton initialized; content fill-in is in progress. Each file
declares its own status at the top. Files with `Status: stub` are
awaiting the design conversation.
