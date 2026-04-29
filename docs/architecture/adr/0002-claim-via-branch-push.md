# ADR 0002: Atomic claim via remote branch push

**Status:** accepted; branch-naming convention generalized by ADR-0025
**Date:** 2026-04-26
**Deciders:** PanQiWei (maintainer)

> **Reading note (2026-04-28).** This ADR's claim primitive (`git
> push --force-with-lease=<ref>:`) is unchanged by ADR-0025; the
> claim is git-layer, board-agnostic, and the atomicity argument
> still holds across GitHub / GitLab / Bitbucket. What ADR-0025
> generalized is the **branch-name format**: `claim/<N>-<slug>` →
> `claim/<key-slug>-<title-slug>` where `<key-slug>` =
> `slugify(Card.key)`. For GitHub Project v2, `Card.key` is the
> issue number string and slugifies identically to the old `<N>`,
> so existing branches remain valid. References to `claim/<N>-<slug>`
> in this ADR's `Decision` section should be read as
> `claim/<key-slug>-<title-slug>` with `<key-slug>` populated from
> `Card.key` per the abstraction in
> [`../0005-contracts/00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md)
> § Identity § Branch naming. The board-canon skill is the SPOT
> for the slugifier rule.

## Context

The Consumer flow needs a **distributed lock**: when N Consumer
sessions race to claim the same Card, exactly one must win, and
the loser must learn it lost without corrupting state. The lock
must work across CC and Codex sessions, across machines, and
without any board-superpowers-owned server-side component (per
ADR-0007 C-PLUGIN-2 — no daemon).

The git server's `push` semantics for a not-yet-existing branch
are atomic in the relevant sense: if two pushes race, exactly
one returns success and the other returns "ref already exists".
The push primitive is **free** (already a deployed dependency for
PR creation), **durable** (committed to origin), and **observable
to every other session** without separate reads (Manager's
`git ls-remote | grep claim/` is the read).

Consumers also need a feature branch to push the eventual PR
against. Coupling the lock and the feature branch into one ref
eliminates double-bookkeeping and makes the claim self-
documenting: anyone fetching can grep for `claim/<N>-<slug>`
and know exactly which Card is being worked on, by which
session, on what slug.

## Decision

The Consumer claim primitive is implemented as:

```
git push --force-with-lease=<ref>: origin <ref>
```

where `<ref>` is `claim/<key-slug>-<title-slug>` (per ADR-0025's
branch-naming abstraction; was `claim/<N>-<slug>` before
2026-04-28). `<key-slug>` is `slugify(Card.key)` — for GitHub
Project v2, `Card.key` is the issue number string and slugifies
identically to the old `<N>` (existing claim branches remain
valid). `<title-slug>` is a ≤40-char slug derived from the Card
title; the slugifier rule is SPOT'd in
[`board-canon`](../../../skills/board-canon/SKILL.md) § Branch
naming. The empty expected-value
(`--force-with-lease=<ref>:`) makes the semantics explicit:
**push only if the ref does not yet exist on origin.** First
push wins; second push gets a clean rejection that
`scripts/claim-card.sh` translates into exit code 10.

The claim branch IS:

- The **distributed lock** — the ref's existence on origin is the
  authoritative claim; loss of the ref releases the claim.
- The **feature branch** — the PR (F-C12) targets this branch
  against `main`.
- The **observable artifact** — Manager preflight (F-03 area)
  reads claim state via `git ls-remote`.

A `ClaimMarker` file (`.board-superpowers/claims/<N>.claim`,
gitignored locally but **force-added** to the claim branch) is
included in the claim's first commit as on-origin proof of
claim. The marker's body fields are documented in
`0003-domain-model/01-ubiquitous-language.md` (ClaimMarker entry).

`scripts/claim-card.sh` exit-code contract:

| Exit | Meaning |
|------|---------|
| 0 | Claim succeeded; stdout has `branch=` and `worktree=` lines |
| 10 | Race lost (ref already exists); caller MUST stop and report who won |
| 20 | Git / network error |
| 30 | Bad args / missing dep |

## Consequences

**What this enables:**

- **No external lock service** — the lock is a side effect of
  ordinary git push semantics, free with the existing dependency
  on `gh` / `git`.
- **Cross-machine claim** — the lock works for any Consumer
  pushing to the same `origin` from any machine, with no shared
  filesystem requirement.
- **Manager observation is read-only** — `git ls-remote` /
  `git fetch` is the read; no Manager-side write needed.
- **Self-documenting** — the claim branch name + ClaimMarker
  body together describe who is working on what, observable by
  any session.

**What this constrains:**

- **Claim ↔ branch lifecycles are coupled.** Abandoning a claim
  means deleting the branch. Stale claim is observable: branch
  exists, no live session pushing to it. Triage routine
  (Producer F-15 area) handles surfacing this.
- **Manager observation has lag.** There is a small window
  between Consumer's push and Manager's next `ls-remote` read.
  This is acceptable because the claim IS held during the
  window — the lag affects observability, not correctness.
- **Branch deletion releases the claim.** Per ADR-0006 row 8,
  cancel-claim is R-class — Producer cannot auto-delete a
  claim branch without architect approval.

**What this forbids:**

- **Re-claim after release without re-pushing the branch.** A
  Consumer that lost its claim via branch deletion cannot resume
  by re-creating local state; it must re-push the branch (which
  may now race against another Consumer that picked up the same
  Card).

## Alternatives considered

- **GitHub Issue `assignees` field write.** REST API write of
  the assignees field is single-step but doesn't have
  compare-and-swap semantics — two simultaneous writes both
  succeed and one silently overwrites the other. No atomicity
  guarantee across racing sessions.
- **Project v2 custom `claimed_by` field write.** Same race
  problem as Issue assignees; also requires extending the
  Project v2 schema, which we already have to do manually
  (ADR-0001's substrate-commitment limitation).
- **File-based lock committed to `main`.** Lossy under merge
  conflicts; requires multi-step write (lock file + push +
  PR + merge) for what should be a single atomic operation.
  Also makes lock acquisition slow (PR review cycle for a
  lock).
- **External lock service (Redis / Consul / dedicated server).**
  Overkill for a CC / Codex plugin; introduces a new
  dependency every architect must operate; violates P5
  (distribution stays minimal).

## Notes

- This ADR documents an already-shipped behavior in
  `scripts/claim-card.sh`. Promoting from `stub` to `accepted`
  retroactively captures the canonical rationale.
- Force-adding the gitignored `ClaimMarker` to the claim
  branch is deliberate (`tests/test-claim-card-worktree.sh`
  covers the invariant): the marker exists on-origin only on
  the claim branch, never on `main`.

## Related

- ADR-0003 — One worktree per Consumer (composes filesystem
  isolation onto this lock)
- ADR-0007 — Plugin-runtime-derived constraints (C-PLUGIN-1 / -2
  shape why this is the only feasible distributed lock)
- [`0003-domain-model/`](../0003-domain-model/README.md) —
  ClaimBranch + ClaimMarker live as member entities of the
  ConsumerLogical aggregate (§ 3.3.3); the `Card.Claimed` domain
  event is § 3.4.4.
- [`0002-product-features-and-flows/04-consumer-surface.md`](../0002-product-features-and-flows/04-consumer-surface.md)
  F-C1 (atomic claim primitive) + F-C14 (failure path releases
  claim)
- [`0002-product-features-and-flows/07-cross-cutting-invariants.md`](../0002-product-features-and-flows/07-cross-cutting-invariants.md)
  I-1 (one card = one Consumer session = one PR)
- `0006-failure-modes.md` (stub) — F-01 stale claim, F-03
  marker race
- `tests/test-claim-card-worktree.sh` — race-loss exit-10
  test + marker info-leak guard
- `scripts/claim-card.sh` — implementation
