---
name: board-canon
description: Use whenever any board operation in board-superpowers needs the canonical contract — the 6-state machine, the Card body schema, the branch-naming convention (claim/<N>-<slug>), or the WIP counting formula. This is the read-only source of truth that every other board-superpowers skill consults before transitioning a card, validating a claim, or checking WIP. Use it even when the user doesn't say "schema" or "state machine" — any time card, branch, Status, or WIP comes up, this is what defines the rules.
when_to_use: Use whenever a card transition, claim push, branch name, WIP cap check, or PR-to-card linkage is being reasoned about. Also when validating that a manual edit to the board respects the contract.
user-invocable: false
---

# board-canon

This skill is the schema authority for the board-superpowers plugin. It answers "what is the contract" — it does not perform actions itself. Other skills consult it before mutating the board.

## Quick reference

| Question | Where |
|----------|-------|
| What states does a card pass through? | § State machine (below) + `references/state-machine.md` |
| What does a Card body look like? | § Card body schema (below) + `references/card-body-schema.md` |
| How is a claim signaled? | § Claim protocol (below) + `references/claim-protocol.md` |
| How is WIP counted? | § WIP counting (below) + `references/wip-counting.md` |
| What's the branch name format? | § Branch naming (below) + `references/branch-naming.md` |

## State machine

A card lives in **exactly one** of six Status field values at any moment. Every transition writes one entry to the plugin's audit log (a local JSON-lines file at `~/.board-superpowers/repos/<normalized>/audit-local.jsonl`).

```
Backlog ─────► Ready ─────► In Progress ─────► In Review ─────► Done
                                │   ▲              │
                                │   │              │
                                ▼   │              ▼
                              Blocked              (rework loops back to In Progress)
```

Legal transitions:

| From | To | Trigger |
|------|-----|--------|
| Backlog | Ready | Card body has all 5 mandatory sections + Acceptance criteria pass INVEST (Independent / Negotiable / Valuable / Estimable / Small / Testable) + an Estimate is set + no hard `depends-on` is still in Backlog or Ready |
| Ready | In Progress | A Consumer claims the card by pushing a `claim/<N>-<slug>` branch (per § Claim protocol). Consumer's WIP count + 1 must not exceed the cap; no other Consumer may already hold a claim branch on this card |
| In Progress | Blocked | An external dependency is unresolved. The blocker MUST be named in a card comment; "I haven't started yet" is not a blocker |
| Blocked | In Progress | The named blocker is resolved |
| In Progress | In Review | The Consumer opens a PR from `claim/<N>-...` whose body passes the three-section PR contract (see the `enforcing-pr-contract` skill) |
| In Review | In Progress | Reviewer requests changes (rework loop). The Consumer addresses comments on the same claim branch, NOT a new branch |
| In Review | Done | The PR is merged (NOT closed without merge); no outstanding "request changes" review remains |

**Illegal transitions** (the plugin's scripts and CI gates reject these):

- Backlog → In Progress directly (must pass through Ready — this is the INVEST gate)
- In Review → Done without a merged PR (Done is post-merge only)
- Done → anything (cards in Done are immutable; create a new card if rework is needed)
- Any state → Backlog (Backlog is for new cards only)

`references/state-machine.md` documents each transition's checklist + audit catalogue.

## Card body schema

Every Card body MUST have this structure. Sections appear in this order. The Producer writes them at intake; the Consumer reads them at claim time.

```markdown
<!-- thin-pointer -->
**Spec**: <relative path to the spec / design doc, with section anchor>
**Owner**: @<github-handle>
**Estimate**: XS | S | M | L
<!-- /thin-pointer -->

## Goal
<one-sentence outcome statement; what the user will be able to do once this card is Done>

## Acceptance criteria
- [ ] criterion 1 (verifiable independently; not "tests pass" — be specific)
- [ ] criterion 2
- [ ] ...

## Out of scope
<things this card explicitly does NOT do, even though they're tempting>

## Dependencies
- depends-on: #<other-card-N>     (hard — cannot start until that card is Done)
- depends-on (soft): #<other-card-M>  (preferable but not required)
- depended-on-by: #<other-card-K>     (this card unblocks K)

## Execution Hints
(optional — Producer-to-Consumer signals: recommended execution skill, known gotcha, type tag for conditional gate routing like `## Execution Hints: ui` or `: security`)

## Notes
<free-form context the Consumer will need; design rationale; gotchas>

<!-- board-superpowers:card -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:card -->
```

The 5 visible sections (Goal / Acceptance criteria / Out of scope / Dependencies / Notes) are MANDATORY. An optional 6th section, `## Execution Hints`, may appear before `## Notes` for Producer-to-Consumer signals (recommended skill, known gotcha, conditional-gate routing tags). The thin-pointer block at the top and the bottom marker are auto-generated by tooling — hand edits to the bottom marker are explicitly rejected.

`references/card-body-schema.md` documents the filler-detection rules applied to each section + the INVEST checklist for Acceptance criteria.

## Claim protocol

A Consumer claims a card by pushing an empty branch named `claim/<N>-<slug>` to origin. **The branch push is the claim signal** — the board's Status field flip is a downstream effect, not the source of truth.

Why a branch push, not a Status edit:

1. **Atomic + audit-friendly**: a git push is logged in `git reflog` + the GitHub event stream; a Status edit alone is harder to forensically trace later.
2. **Conflict-detectable**: two Consumers attempting to claim the same card hit a non-fast-forward push rejection (one wins; the loser sees the rejection).
3. **Cheap to undo**: `git push origin --delete claim/N-slug` releases the claim cleanly.

The transactional write order (performed by `scripts/claim-card.sh`):

1. Set the Status field → "In Progress" (via `gh project item-edit`).
2. Create a local worktree at `$HOME/.config/superpowers/worktrees/<repo>/claim/<N>-<slug>` (override base path with `BOARD_SP_WORKTREE_DIR`).
3. Create branch `claim/<N>-<slug>` from `origin/main` inside the worktree.
4. Push the branch to origin so the claim is publicly visible.

If step 4 fails, steps 1-3 are NOT rolled back automatically — the Consumer must explicitly surface the partial state to the architect rather than silently retry.

`references/claim-protocol.md` documents the conflict-resolution playbook for race conditions and stale-claim release.

## WIP counting

The plugin enforces a per-Consumer WIP cap. The formula:

```
WIP_count(consumer) =
    (cards in In Progress claimed by this consumer)
  + (cards in In Progress with the `suspended` label, claimed by this consumer)
  + (cards in In Review whose PR was authored by this consumer and is still open)
```

Cards in `Blocked` are **excluded** from the count — being blocked is not active work; the Consumer should be picking up something else while waiting.

The default cap is 5 per Consumer (per spec). Each architect overrides per-repo by writing `wip_limit: <N>` in `.board-superpowers/config.local.yml` — this file is **per-user** (gitignored via the project-wide `*.local.*` pattern), so Alice running 5 parallel sessions and Bob running 1 do not impose their preferences on each other. A Consumer attempting to claim a card past their `wip_limit` gets a hard rejection at the agent layer (this skill enforces it before invoking `claim-card.sh`).

`references/wip-counting.md` documents corner cases (suspended cards, abandoned worktrees, post-merge accounting lag, override mechanism).

## Branch naming

Format: `claim/<N>-<slug>`

Where:
- `<N>` is the card's GitHub issue number (no `#` prefix)
- `<slug>` is the card title slugified by `bsp_slugify` (defined in `scripts/lib/common.sh`): lowercase, alphanumeric + hyphens, max 40 characters

Examples:

| Card title | Branch |
|------------|--------|
| `Implement board-canon SKILL.md` | `claim/12-implement-board-canon-skill-md` |
| `Fix issue with WIP counter (race)` | `claim/47-fix-issue-with-wip-counter-race` |
| `[urgent] add audit log fallback` | `claim/103-urgent-add-audit-log-fallback` |

Banned characters in branch names (replaced with hyphens by the slugifier; runs collapsed): spaces, `/`, `:`, `?`, `[`, `]`, `^`, `~`, `\`, `*`, control characters.

The same card uses exactly **one** `claim/N-slug` branch across its lifetime, including rework. Push new commits to the same branch on a "request changes" review — do NOT create `claim/N-slug-v2`.

`references/branch-naming.md` documents the slugifier edge cases and the rare exception flow for materially-renamed cards.

## What this skill does NOT cover

- **WHO transitions a card** — that depends on the role (Producer vs Consumer), which is decided by other skills.
- **WHEN to transition** — that's per-routine in `managing-board` (Producer) and `consuming-card` (Consumer).
- **HOW to communicate decisions** — that's `enforcing-pr-contract` for PR shape and the audit log writer for the trace.

This skill defines **WHAT** the contract is. The other skills decide when and how to act on it.
