---
name: consuming-card
description: Use when the user wants to claim, work on, or implement a specific card from the board-superpowers GitHub Project — including any message containing the literal token [board-card:#N], or phrases like "claim card 12", "work on card N", "let me take #47", "implement issue 12 from the board". Apply this skill the moment the message includes a card identifier; do NOT pre-discuss the work — claim first, then work in the worktree. Use even when the user phrases it casually ("let's pick up 12") — claim signal is what matters, not formality. v1-minimum scope covers the full F-C0..F-C14 lifecycle from claim through PR submit.
when_to_use: Use when the user types `[board-card:#N]`, "claim card N", "work on card N", "implement #N from the board", "let's take card N", "pick up #N", or any variation that names a specific card number AND signals intent to do the work.
argument-hint: "[card-number]"
arguments: [card_number]
---

# consuming-card

> **Skeleton type**: A (pattern). Consumer-session main skill.
> Carries F-C0..F-C14 lifecycle from
> `docs/architecture/0002-product-features-and-flows/04-consumer-surface.md`.
>
> **REQUIRED SUB-SKILLS**:
> - `board-superpowers:board-canon` (state machine + claim
>   protocol + WIP rules — read before claiming)
> - `board-superpowers:enforcing-pr-contract` (F-C12 PR submit)
>
> **REQUIRED CROSS-PLUGIN SUB-SKILLS** (per AGENTS.md routing):
> - `superpowers:test-driven-development` (F-C4 — TDD is
>   mandatory inside the implementation loop)
> - `superpowers:verification-before-completion` (F-C9 — before
>   opening the PR)
> - `gstack:/review` + `superpowers:requesting-code-review`
>   (F-C9 verification chain)

## Lifecycle overview

```
F-C0 (resolve target) → F-C1 (read card)
                         ↓
F-C2 (claim) → F-C3 (worktree setup) → F-C4 (implement, TDD)
                                        ↓
F-C5..F-C8 (status updates / blockers as they emerge)
                         ↓
F-C9 (verify) → F-C10 (cross-platform review) → F-C11 (conditional QA / security)
                         ↓
F-C12 (submit PR with three-section contract) → F-C13 (rework loop if needed)
                         ↓
F-C14 (release after merge — worktree + branch cleanup)
```

## F-C0 — resolve the target card

The card number arrives one of three ways:

1. **Named argument**: `/board-superpowers:consuming-card 12`
   → `$card_number` = `12`. CC-only path; on Codex
   `$card_number` is literal — fall through to (2).
2. **From `$ARGUMENTS`**: parse first space-separated token as
   the card number. Always works (cross-platform).
3. **From the user's natural-language prompt**: extract the
   first integer following `card`, `#`, or `[board-card:#`.

If the card number cannot be resolved unambiguously, ask the
user — do NOT guess. A wrong card number = wrong worktree =
wasted setup.

## F-C1 — read the card

```bash
gh issue view <N> --json number,title,body,state,labels,comments
```

Inspect:

- **Status field** (must be `Ready` to claim; `In Progress`
  with a different `claim/N-...` branch means someone else has
  it; other states mean wait or escalate)
- **Card body** (read all 5 mandatory sections per
  `board-superpowers:board-canon` § "Card body schema")
- **Dependencies** — if any hard `depends-on` is not yet Done,
  STOP and surface to the architect

## F-C2 — claim

Run `bash scripts/claim-card.sh --owner <owner> --project
<number> --repo <repo> --card <N> --title "<title>"`. Owner +
project number live in `.board-superpowers/config.yml`.

The script performs the 4-step transaction per
`board-superpowers:board-canon` § "Claim protocol". Any failure
in steps 1-4 leaves a partial state — read the script's stderr
and surface to the architect (R-class — partial states are
never auto-recovered in v1-minimum).

## F-C3 — enter the worktree

```bash
cd "$HOME/.config/superpowers/worktrees/<repo>/claim/<N>-<slug>"
```

The worktree is your isolated work surface — do NOT `cd` back
to the repo root for any work. The repo root is permanently on
`main` per `AGENTS.md` "Working tree discipline".

## F-C4 — implement (TDD-driven)

This is the procedural core. Follow the gstack/superpowers
composition rules in `AGENTS.md` § "How to compose gstack and
superpowers":

1. **REQUIRED SUB-SKILL**: `superpowers:writing-plans` — turn
   the card's Acceptance criteria into an executable plan.
2. **REQUIRED SUB-SKILL**:
   `superpowers:test-driven-development` — drive the
   implementation Red → Green → Refactor.
3. When stuck: invoke `superpowers:systematic-debugging` OR
   `gstack:/investigate` for a different angle.

This skill does NOT re-implement TDD or planning — those are
sibling-plugin disciplines per ADR-0004. The composition is
permanent.

## F-C5..F-C8 — in-flight transitions

If the card hits a blocker mid-flight:

1. Comment on the card naming the blocker (per
   `board-superpowers:board-canon` § state machine, In Progress
   → Blocked transition rules).
2. Run `gh project item-edit ... Status=Blocked` (R-class —
   ask architect).
3. Audit-log: action_id 101, decision_class R.

Otherwise leave the card in `In Progress` for the duration of
the implementation. Do NOT churn the Status field on every
commit — Status reflects the gross state of the work, not its
internal progress.

## F-C9 — verify before completion

Required chain (each step is REQUIRED SUB-SKILL):

1. `superpowers:verification-before-completion` — evidence
   first; do not claim "done" without running the actual
   checks named in the card's Acceptance criteria.
2. `gstack:/review` — production-bug viewpoint.
3. `superpowers:requesting-code-review` — independent
   second-pair-of-eyes on the diff.

This skill does NOT inline these — they are the canonical
verification methods. The card is NOT ready for PR submit
until all three pass.

## F-C10 — cross-platform review (CC ↔ Codex)

If the change is non-trivial (more than a 1-line fix):

```
gstack:/codex   # if running on CC, dispatch a Codex session against the same diff
```

The cross-platform review catches platform-specific
assumptions. Skip for trivial changes.

## F-C11 — conditional QA / security

- **UI-touching cards**: `gstack:/qa <url>` — real-browser QA.
  Mandatory for any card that changes a user-visible surface.
- **Security-flagged cards** (label `security` OR card body
  mentions auth / crypto / PII): `gstack:/cso` — OWASP / STRIDE
  audit.

## F-C12 — submit PR with three-section contract

Draft the PR body using the templates in
`board-superpowers:enforcing-pr-contract` § "Section
templates". Save to a temp file, then:

```bash
bash scripts/submit-pr.sh --title "<title>" --body-file <path> --card <N>
```

The script validates the three-section contract before opening
the PR. If validation fails: re-edit the body to address the
specific failure (printed to stderr) and retry.

The script appends a trailer linking back to the card; do NOT
hand-add the trailer.

## F-C13 — rework loop (if reviewer requests changes)

If the reviewer comments "request changes":

1. Pull the changes back into the same worktree (do NOT create
   a new branch).
2. Re-run F-C4 + F-C9 + F-C12. Use the same claim branch — see
   `board-superpowers:board-canon` § "Branch naming" §
   "Single claim branch per card".
3. The card stays in `In Review`; re-pushing the PR commits
   triggers re-review.

## F-C14 — release after merge

Once the PR is merged:

1. The card auto-transitions to `Done` via GitHub's webhook
   (with up to 30s lag — see `board-superpowers:board-canon`
   § "WIP counting" § post-merge lag).
2. Clean up locally:
   ```bash
   cd ~/Dev/repos/<repo>           # back to repo root
   git worktree remove "$HOME/.config/superpowers/worktrees/<repo>/claim/<N>-<slug>"
   git branch -d claim/<N>-<slug>  # local cleanup; remote branch was already deleted by gh on merge
   ```
3. Audit-log: action_id 111, decision_class A.

The worktree cleanup is mandatory per AGENTS.md § "Working
tree discipline" — leaving stale worktrees pollutes the
worktrees directory.

## v1-minimum degradation block

> All mutating actions in this skill (Status flips, card body
> writes, PR creates / comments, worktree deletes, branch
> deletes, audit-log writes) run as R-class with the architect
> by default. The full D-AUTONOMY-1 matrix from
> `classifying-actions` is **deferred to v1-complete**. When
> that atomic ships, this block gets replaced with `Apply
> classifying-actions to the action; act on its A/R/N
> decision.`

> All audit log writes go to
> `~/.board-superpowers/<host>/<repo>/audit-local.jsonl` via
> `bsp_audit_local_write` from `scripts/lib/common.sh`. The
> full BYO RDBMS schema from `auditing-actions` is **deferred
> to v1-complete**. When that atomic ships, this block gets
> replaced with `Apply auditing-actions for the schema +
> two-entry rule.`

## Mode-2 constraint

Under Mode-2 (Producer-spawned Consumer subagent), this skill
runs as a CC subagent with `max_depth=1` per ADR-0008. That
means it CANNOT spawn further subagents — every cross-plugin
invocation MUST be procedural (the Consumer reads the sibling
plugin's SKILL.md content into its own context, follows the
procedure inline, rather than spawning a `superpowers:*` or
`gstack:*` subagent).

In v1-minimum, Mode-2 is CC-only. On Codex CLI only Mode-1
(architect-spawned Consumer) works. See
`references/permission-boundary.md` for the full Mode-1 vs
Mode-2 contract.
