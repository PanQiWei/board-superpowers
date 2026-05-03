---
name: board-canon
description: Use whenever any board operation in board-superpowers needs the canonical contract — the 6-state machine, the Card body schema, the branch-naming convention (claim/<kanban-id>-<key-slug>-<title-slug>), or the WIP counting formula. This is the read-only source of truth that every other board-superpowers skill consults before transitioning a card, validating a claim, or checking WIP. Use it even when the user doesn't say "schema" or "state machine" — any time card, branch, Status, or WIP comes up, this is what defines the rules.
when_to_use: Use whenever a card transition, claim push, branch name, WIP cap check, or PR-to-card linkage is being reasoned about. Also when validating that a manual edit to the board respects the contract.
user-invocable: false
---

# board-canon

Consult this skill before any card transition, claim push, branch name, or WIP check. It answers "what is the contract" — it does not perform actions itself. Read the relevant § below to settle the rule, then return to the calling skill to act.

## How to apply this skill

| What you need to do | Look up here |
|---------------------|--------------|
| Validate a card transition (e.g., Backlog → Ready) | § State machine + `references/state-machine.md` |
| Resolve a claim conflict or release a stale claim | § Claim protocol + `references/claim-protocol.md` |
| Generate a claim branch name from a card | § Branch naming + `references/branch-naming.md` |
| Compute a Consumer's WIP count vs cap | § WIP counting + `references/wip-counting.md` |
| Validate a card body's section shape | § Card body schema + `references/card-body-schema.md` |

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
| Ready | In Progress | A Consumer claims the card by pushing a `claim/<kanban-id>-<key-slug>-<title-slug>` branch (per § Claim protocol). Consumer's WIP count + 1 must not exceed the cap; no other Consumer may already hold a claim branch on this card |
| In Progress | Blocked | An external dependency is unresolved. The blocker MUST be named in a card comment; "I haven't started yet" is not a blocker |
| Blocked | In Progress | The named blocker is resolved |
| In Progress | In Review | The Consumer opens a PR from the card's claim branch whose body passes the three-section PR contract (see the `enforcing-pr-contract` skill) |
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

<!-- board-superpowers:audit-trail -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:audit-trail -->
```

The 5 visible sections (Goal / Acceptance criteria / Out of scope / Dependencies / Notes) are MANDATORY. An optional 6th section, `## Execution Hints`, may appear before `## Notes` for Producer-to-Consumer signals (recommended skill, known gotcha, conditional-gate routing tags). The thin-pointer block at the top and the bottom marker are auto-generated by tooling — hand edits to the bottom marker are explicitly rejected.

When a Card is read from the backend, the projection may also surface read-only display metadata (`display_parent`, `display_children_count`, `display_hierarchy_path`) — these are agent-readable for context only and never participate in state, claim, WIP, or PR-linkage decisions. See `references/card-body-schema.md` § "Display-only metadata" for the field contract and absence semantics.

Two bottom-region marker pairs are reserved (machine-managed):

- `<!-- board-superpowers:creator-trace -->` — platform + session id of the creating session (per card #44; new cards only — see `references/card-body-schema.md` § "Creator-trace marker").
- `<!-- board-superpowers:audit-trail -->` — query pointer to the audit log (existing behavior).

The `creator-trace` marker is **auto-prepended by intake tooling**
(via `bsp_render_creator_trace_block` in `scripts/lib/common.sh`)
at `gh issue create` time and is NOT part of the manual
schema-block template above. The `audit-trail` marker IS part of
the manual schema and appears in every Card body authored by
hand or by decomposition tooling.

`references/card-body-schema.md` documents the filler-detection rules applied to each section + the INVEST checklist for Acceptance criteria.

## Claim protocol

A Consumer claims a card by pushing an empty branch named per § Branch naming below to origin. **The branch push is the claim signal** — the board's Status field flip is a downstream effect, not the source of truth.

Why a branch push, not a Status edit:

1. **Atomic + audit-friendly**: a git push is logged in `git reflog` + the backend's event stream; a Status edit alone is harder to forensically trace later.
2. **Conflict-detectable**: two Consumers attempting to claim the same card hit a non-fast-forward push rejection (one wins; the loser sees the rejection).
3. **Cheap to undo**: `git push origin --delete <claim-branch>` releases the claim cleanly.

The transactional write order (performed by `scripts/claim-card.sh`):

1. Set the Status field → "In Progress" (via the active backend's projection).
2. Create a local worktree at `$HOME/.config/superpowers/worktrees/<repo>/<claim-branch>` (override base path with `BOARD_SP_WORKTREE_DIR`).
3. Create the claim branch (named per § Branch naming) from `origin/main` inside the worktree.
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

Canonical format: `claim/<kanban-id>-<key-slug>-<title-slug>`

Where:
- `<kanban-id>` is the local id of the active kanban this card belongs to (read from `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`). For repos with one active kanban, the id is typically `primary`.
- `<key-slug>` is `slugify(Card.key)` — `Card.key` is the backend's display-stable opaque card identifier (GitHub Project v2: the issue number `42`; Linear: `eng-42`; Jira: `proj-42`). The slugifier (`bsp_slugify` in `scripts/lib/common.sh`) lowercases and reduces to alphanumeric + hyphens.
- `<title-slug>` is the card title slugified by the same rules: lowercase, alphanumeric + hyphens, max 40 characters.

Examples:

| Active kanban | Card key | Card title | Branch |
|---------------|----------|------------|--------|
| `primary` (GitHub Project v2) | `12` | `Implement board-canon SKILL.md` | `claim/primary-12-implement-board-canon-skill-md` |
| `primary` (GitHub Project v2) | `47` | `Fix issue with WIP counter (race)` | `claim/primary-47-fix-issue-with-wip-counter-race` |
| `legal` (future Jira projection) | `comp-7` | `Audit log retention review` | `claim/legal-comp-7-audit-log-retention-review` |

Banned characters in branch names (replaced with hyphens by the slugifier; runs collapsed): spaces, `/`, `:`, `?`, `[`, `]`, `^`, `~`, `\`, `*`, control characters.

The same card uses exactly **one** claim branch across its lifetime, including rework. Push new commits to the same branch on a "request changes" review — do NOT create a `-v2` suffixed variant.

A two-segment legacy form exists on repos authored under earlier plugin versions; the parser accepts both, and only the canonical three-segment form is emitted for new claims. See `references/branch-naming.md` § "Legacy two-segment form" for the parser contract and migration path.

`references/branch-naming.md` documents the slugifier edge cases, the legacy-form parser contract, and the rare exception flow for materially-renamed cards.

## What this skill does NOT cover

- **WHO transitions a card** — that depends on the role (Producer vs Consumer), which is decided by other skills.
- **WHEN to transition** — that's per-routine in the four Producer routines (`briefing-daily`, `intaking-requirement`, `reviewing-pr-queue`, `triaging-board`) and `consuming-card` (Consumer).
- **HOW to communicate decisions** — that's `enforcing-pr-contract` for PR shape and the audit log writer for the trace.

This skill defines **WHAT** the contract is. The other skills decide when and how to act on it.
