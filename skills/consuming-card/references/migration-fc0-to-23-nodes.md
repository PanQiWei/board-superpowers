# Migration: Old feature codes → 23-node encoding (F1-F4 / B1-B5 / G1-G5 / C1-C4)

Archived knowledge: how the old feature-grouped numbering maps to the
new journey-node encoding used in the `consuming-card` body refactor (PR #73).

This file is a maintainer-only historical reference for reading old PRs, ADRs, or
commit messages that use the old numbering scheme. Not shipped with plugin install.
The 23-node encoding is the canonical form; old codes in spec docs are historical.

## Mapping table

| Old name | New node(s) | Notes |
|----------|-------------|-------|
| Card assignment entry (Mode-1 / Mode-2 startup) | A1 | Direct mapping |
| Atomic claim primitive | A2 (claim transaction) | Direct mapping |
| Spec / plan / acceptance-criteria fetch | A3 | Direct mapping |
| Worktree entry + In Progress transition | A2 (worktree creation) | Composed into A2 |
| TDD-driven implementation delegation | B2 | Direct mapping; plan synthesis now explicitly B1 |
| TDD-skip refusal | B3 | Direct mapping |
| Cross-card touch hard refuse | B4 | Direct mapping |
| Permission boundary (three-layer) | B5 | Direct mapping |
| Verification chain entry | C1 (partial) | Composed into C1 |
| Pre-submit verification execution | C1 | Composed mapping (old entry + execution = C1) |
| Cross-platform adversarial review | C2 | Direct mapping |
| Conditional QA pass (UI) | C3 | Split: old conditional pass → C3 (QA) + C4 (security) |
| Conditional security pass | C4 | Split: old conditional pass → C3 (QA) + C4 (security) |
| PR submission with mandatory sections | D1 + D2 | D1 = PR submit; D2 = AC terminal-state sync (was Step 9.5) |
| Stakeholder routing / scope judgment | F1 | Direct mapping |
| Termination — post-merge branch | E1 | Direct mapping (success path) |
| Termination — crash / failure branch | E2 | Direct mapping (failure path) |
| Plan synthesis (was implicit at implementation entry) | B1 | New explicit node; was undocumented |
| Review-feedback response loop (was implicit in PR cycle) | D3 | New explicit node; was undocumented |
| Cross-cutting governance (none — surfaced by methodology) | G1-G5 | New explicit nodes from methodology cross-product |

## action_id coverage in the new encoding

Consumer action_id range 100-113 is fully covered in the 23-node encoding:

| action_id range | Description | New encoding location |
|----------------|-------------|----------------------|
| 100 | Claim card | A2 (Stage 1) |
| 101 | Edit card body during implementation | B2 (Stage 2) |
| 102 | Open PR | D1 (Stage 4) |
| 103 | PR closed without merge (failure path) | E2 (Stage 4) |
| 104 | Release claim (suspense or abandon) | E2 (Stage 4) |
| 105-111 | Review cycle actions | D3 (Stage 4 rework loop) |
| 112 | PR-submit pre-flight card body sync | D1+D2 pre-flight (Stage 4) |
| 113 | Post-merge cleanup | E1 (Stage 4) |

## Structural findings from the mapping

1. **7 nodes recovered from methodology cross-product** that had no equivalent in
   the old feature-grouped list: B1 (plan synthesis), D3 (review-feedback loop),
   G1-G5 (cross-cutting governance). These nodes existed in the implementation but
   were implicit or undocumented.

2. **Conditional pass split into two distinct nodes** (C3 QA + C4 security):
   different gating heuristics (UI label vs security label / path) and different
   sibling targets (`gstack:/qa` vs `gstack:/cso`).

3. **Verification chain entry + execution composed into C1**: the distinction was
   an internal implementation detail, not a meaningful journey node split.

4. **Worktree creation composed into A2**: worktree creation is part of the claim
   transaction, not a separate lifecycle node. The claim script handles both
   atomically.
