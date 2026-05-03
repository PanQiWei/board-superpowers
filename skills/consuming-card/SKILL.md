---
name: consuming-card
description: Use when the user wants to claim, work on, or implement a specific card from the board-superpowers GitHub Project. Triggers immediately on any message containing the literal token [board-card:#N] OR phrases like "claim card 12", "work on card 47", "implement #N from the board", "let me take #N", "let's pick up 12", "let me grab card N". Apply the moment the message names a card number AND signals intent to do the work — do NOT pre-discuss; claim first, then work in the worktree the skill creates. Use even when the user phrases it casually ("ok 12") — the claim signal is what matters, not formality. Do NOT use when the user wants to plan / triage / review the board generally — that's a Producer routine SKILL (`briefing-daily` for daily briefing, `intaking-requirement` for new ideas, `reviewing-pr-queue` for PR review, `triaging-board` for triage / blocked-card investigation).
when_to_use: Use when the user types `[board-card:#N]`, "claim card N", "work on card N", "implement card N", "let me take #N", "let's pick up #N", "I'll do card N", "grab card N", or any phrasing that names a specific card number AND signals intent to start the work.
argument-hint: "[card-number]"
arguments: [card_number]
---

# consuming-card

Consumer-session skill: carries one card from claim through PR submit. All 23
lifecycle nodes are hosted here — stages F1-F4, bootstrap B1-B5, governance
G1-G5, and cross-plugin handoffs C1-C4. Stage detail lives in the four
`references/stage-*.md` files loaded on demand.

This SKILL hosts the 23 journey nodes (A1-A3, B1-B5, C1-C4, D1-D3, E1-E2,
F1, G1-G5) per `04-consumer-surface-redesign.md` archetype catalog as 4
stages × multiple nodes per stage. G1-G5 are cross-cutting governance nodes
that apply uniformly across all stages; see § "G1-G3 — Governance" and
§ "G4 — Mode topology" below. G5 (cross-platform parity verification) tracks
that both Claude Code and Codex CLI consumer paths are exercised for non-trivial
cards. See `references/migration-fc0-to-23-nodes.md` for the full
old-feature-code → 23-node mapping.

## G4 — Mode topology (cross-cutting, applies to every stage)

**Mode-1 (architect-spawned)** — architect types `[board-card:#N]` or
`/board-superpowers:consuming-card N`. Runs as the architect's primary session.
Full tool budget; sub-skill spawning allowed at depth 1. Supported on both
Claude Code and Codex CLI.

**Mode-2 (Producer-spawned)** — a Producer routine SKILL session (any of
`briefing-daily` / `intaking-requirement` / `reviewing-pr-queue` /
`triaging-board`) spawns this skill as a CC subagent via `Agent` tool. The subagent runs with isolated context and
`max_depth=1`, meaning it CANNOT itself spawn further subagents. Every
cross-plugin sub-skill invocation MUST be procedural (load the sibling SKILL.md
into this agent's own context; do NOT call `Agent` again). Verify each sibling
skill is procedural before invoking it from Mode-2 — consult
`board-superpowers:composing-siblings` `references/procedural-fallback-rules.md`.
Mode-2 is Claude Code only.

**Mode-2 R-class callback protocol**: A Producer-spawned Consumer cannot pause and
ask the architect directly — the subagent context has no architect in the loop.
When a mutating action is R-class in Mode-2:
1. The Consumer subagent prepares a structured proposal JSON.
2. The Consumer subagent calls `report_agent_job_result` with the proposal payload.
3. The Producer skill receives the result, evaluates it against
   `autonomy_overrides` in `<repo>/.board-superpowers/config.yml`, and either
   acknowledges autonomously (if override allows) or surfaces to the architect.
4. On architect approval, the Producer re-spawns the Consumer subagent (new
   isolated context) with an explicit "act on the previously-proposed action"
   prompt.
The audit log records two entries: propose (written before step 2) and resolve
(written after step 4's execution). This 4-step dance is expensive; cards
selected for Mode-2 overnight-dispatch should have a high ratio of A-class
actions. The subagent-spawn constraint is the `max_depth=1` rule: a subagent
already at depth 1 cannot itself spawn further subagents.

**Mode-2 procedural fallback table** (SKILL invocation is always safe; the risk is a sibling skill's body instructing an `Agent` spawn, which would push past the depth-1 budget):

| Sibling | Mode-2 safe? | If not safe |
|---------|-------------|------------|
| `superpowers:writing-plans` | Yes | n/a |
| `superpowers:test-driven-development` | Yes | n/a |
| `superpowers:systematic-debugging` | Yes | n/a |
| `superpowers:verification-before-completion` | Yes | n/a |
| `superpowers:requesting-code-review` | Verify first | If spawning: use `gstack:/review` only; surface gap as Retro Note |
| `superpowers:subagent-driven-development` | procedural-verified (per composing-siblings/references/procedural-fallback-rules.md, dated 2026-04-26; re-verify on superpowers release) | n/a — safe if still procedural |
| `gstack:/review` | Yes | n/a |
| `gstack:/investigate` | Yes | n/a |
| `gstack:/qa` | Yes | n/a |
| `gstack:/cso` | Yes | n/a |
| `gstack:/codex` | No | Mode-1 only; in Mode-2 ask architect to run it |
| `superpowers:dispatching-parallel-agents` | NOT usable (Mode-2 itself runs as a subagent; spawning parallel subagents from within a subagent exceeds the depth-1 budget) | Raise to architect; do not invoke from Consumer Mode-2 |

## Required sub-skills (atomic layer)

- `board-superpowers:board-canon` — canonical state machine + Card schema + branch naming + WIP rules.
- `board-superpowers:operating-kanban` — protocol-action dispatch: `read_card` (F1/F2 entry), `claim_card` (F1 claim transaction embedded in `claim-card.sh`), `transition_card` (F3 → Blocked / In Review), `link_pr_to_card` (F4 PR submit embedded in `submit-pr.sh`).
- `board-superpowers:composing-siblings` — cross-plugin handoff rules and Mode-2 compatibility check; invoke at every C1-C4 point.
- `board-superpowers:enforcing-pr-contract` — Contract A (PR three-section shape) + Contract B (AC terminal-state sync) at F4 submit.
- `board-superpowers:classifying-actions` — autonomy classification for every mutating action.
- `board-superpowers:auditing-actions` — audit row write after every A/R decision.

## Stage F1 — Claim

Detailed procedure: `references/stage-1-claim.md`.

**F1 summary (nodes A1-A3, B1-first):**

1. Resolve card number: from `$card_number` arg, or `$ARGUMENTS` first token,
   or parse `#N` from the prompt. Ambiguous → ask.
2. Read card via `board-superpowers:operating-kanban` action `read_card`.
   Status MUST be `Ready`; unmet `depends-on` → stop, surface to architect.
3. Invoke `board-superpowers:classifying-actions` (action_id 100 — claim).
   If R: propose → await architect ack → proceed.
4. Run `bash scripts/claim-card.sh --owner <owner> --project <num> --repo <repo> --card <N> --title "<title>"`. The script executes the 4-step claim transaction (branch push → Status flip to `In Progress` via `transition_card`). On failure: read stderr and surface.
5. Enter the worktree at `$HOME/.config/superpowers/worktrees/<repo>/claim/<kanban-id>-<key-slug>-<title-slug>`. Do NOT return to repo root for work. See `board-superpowers:board-canon` § "Branch naming" for the canonical slug format.
6. Audit row via `board-superpowers:auditing-actions` (action_id 100).

## Stage F2 — Implement (TDD-driven)

Detailed procedure: `references/stage-2-implement.md`.

**F2 summary (nodes A3, B1-B5):**

B1 — Plan synthesis: invoke `board-superpowers:composing-siblings` then
delegate to `superpowers:writing-plans`. Turns the card's acceptance criteria
into an executable TDD plan. (C1 handoff)

B2 — TDD mutation cycle: invoke `board-superpowers:composing-siblings` then
delegate to `superpowers:test-driven-development` for Red → Green → Refactor.
When stuck: `superpowers:systematic-debugging` or `gstack:/investigate`. (C2 handoff)

B3 — TDD-skip refusal: Do not bypass TDD even when implementation feels
"obvious." The verification chain's integrity depends on every AC having a
failing test first. This is a non-negotiable governance reflex.

B4 — Cross-card refusal: Edits are restricted to files claimed by this card.
Refuse to modify infrastructure or files claimed by other cards without explicit
architect authorization. Surface as R-class proposal if boundary crossing is
genuinely necessary.

B5 — Permission-boundary: Every mutating action passes through
`board-superpowers:classifying-actions` first. Do not bypass for convenience.
R-class actions require architect acknowledgement before acting.

**In-flight blocker (transition to Blocked)**: invoke
`board-superpowers:classifying-actions` (action_id 103 — Consumer Blocked/terminate-failure),
then `board-superpowers:operating-kanban` action `transition_card` with target
`Blocked`. Comment on the card naming the blocker. Audit via
`board-superpowers:auditing-actions`.

**How every mutating action is handled:**

1. Resolve `action_id` (catalog in `board-superpowers:classifying-actions` `references/action-id-catalog.md`).
2. Invoke `board-superpowers:classifying-actions` → receive A / R / N.
3. A: act → invoke `board-superpowers:auditing-actions` (1 entry).
4. R: audit propose → surface → await ack → on approve: act + audit resolve; on decline: audit decline + abort.
5. N: refuse, surface block reason.

Consumer action_id range: 100-113 (100-111 review cycle + 112 PR-submit pre-flight + 113 post-merge cleanup). Full catalog: `board-superpowers:classifying-actions` `references/action-id-catalog.md`.

## Stage F3 — Verify

Detailed procedure: `references/stage-3-verify.md`.

**F3 summary (nodes C1-C4, D3 rework):**

**Iron law: never open a PR without completing the full verification chain.**

C1 — Verification chain: invoke `board-superpowers:composing-siblings`, then:
- `superpowers:verification-before-completion` (evidence-first; run actual checks named in ACs)
- `gstack:/review` (production-bug viewpoint)
- `superpowers:requesting-code-review` (independent second-pair-of-eyes)
All three required. None optional.

C2 — Cross-platform review (non-trivial cards): invoke
`board-superpowers:composing-siblings`, then `gstack:/codex` (from CC). Mode-2:
not possible from subagent; ask architect to run it. Skip for 1-line fixes.

C3 — Conditional QA: invoke `board-superpowers:composing-siblings`, then
`gstack:/qa <url>` for any UI-touching card (label or path heuristic). Mandatory
when the card changes any user-visible surface.

C4 — Conditional security audit: invoke `board-superpowers:composing-siblings`,
then `gstack:/cso` for cards with `security` label or body mentioning auth / crypto / PII.

Status transition to `In Review`: invoke `board-superpowers:operating-kanban`
action `transition_card` with target `In Review` after verification chain
completes and PR is ready to submit.

### Common rationalizations to reject

| Rationalization | Reality |
|-----------------|---------|
| "Small change — verification is overkill" | Small changes hide gaps. Chain calibrated for smallest meaningful card. |
| "Skip code-review, let the human reviewer do it" | Consumer hasn't reduced architect load — just passed it through. |
| "Tests pass = done" | Name which tests, which edge cases, which integration points. |

## Stage F4 — Submit PR

Detailed procedure: `references/stage-4-submit.md`.

**F4 summary (nodes D1-D3, E1-E2):**

D1+D2 — PR-submit pre-flight (action_id 112, A-class):
1. Toggle all AC checkboxes to `[x]` or `[!]<reason>`. Bare `[ ]` is forbidden.
2. If Notes invites a summary, append 3-5 line implementation summary.
3. Compute before/after SHA256 and `gh issue edit <N> --body-file <path>`.
4. Audit via `board-superpowers:auditing-actions` (action_id 112).

D1 — PR submit with three-section contract. Invoke
`board-superpowers:enforcing-pr-contract` for templates. Then:
```bash
bash scripts/submit-pr.sh --title "<title>" --body-file <path> --card <N>
```
The script validates Contract A (three-section shape) + Contract B (AC terminal
state) before opening the PR. Retry with corrected body if validation fails.
The script auto-appends the `Closes #<N>` trailer — do NOT hand-add it or use
`gh pr create` / `gh pr edit --body-file` directly (both strip the trailer,
breaking the GitHub auto-close webhook chain). For post-OPEN body updates:
`bash scripts/submit-pr.sh --update-body --pr <PR-N> --body-file <path> --card <N>`.

The `link_pr_to_card` protocol action IS `bash scripts/submit-pr.sh` for the
`github-project-v2` projection — the auto-trailer registers the PR↔Issue link.

D3 — Review-feedback rework loop: pull changes into the SAME worktree (do NOT
create a new branch). Re-run F2 implement + F3 verify + F4 submit. Card stays
`In Review`; re-pushing triggers re-review.

E1 — Post-merge cleanup (action_id 113, A-class):
1. Verify `gh pr view <PR-N> --json state` returns `MERGED`.
2. Verify card Status flipped to `Done` (webhook; 30 s typical; surface lag after 5 min).
3. Local cleanup: `git worktree remove <path>` + `git branch -d claim/<...>`.
4. Audit via `board-superpowers:auditing-actions` (action_id 113).
See `references/stage-4-submit.md` for the full Stage (a) / Stage (b)
PR↔Issue link verification procedure and manual-recovery path.

E2 — Crash / failure path: surface partial state to architect via card comment;
record a heartbeat audit row; leave the worktree intact for next-session pickup.

## G1-G3 — Governance (cross-cutting reflexes)

G1 — Every mutating action produces an audit row via `board-superpowers:auditing-actions`.

G2 — R-class actions surface a propose-await before acting. Proposal records an
audit entry; architect ack records a second entry.

G3 — A-class actions execute without interruption (no architect-visible gate).
Both G2 + G3 use `board-superpowers:classifying-actions` as the single classifier.

## v1.x roadmap stubs

Three SPOT-watchlist items deliberately kept inline (not extracted to atomics):
- `scope-judgment` (F1 stakeholder routing node) — extract when ≥2 callers emerge.
- `mode-projection` (G4) — extract when Producer overnight-dispatch ships (2nd caller).
- `refusing-out-of-scope` (B3 + B4 + B5) — extract when a 4th refusal node lands AND ≥3 share same-rhythm pattern.

## References

| File | When to read |
|------|-------------|
| `references/stage-1-claim.md` | Full Stage 1 claim protocol detail (card read → claim transaction → worktree entry) |
| `references/stage-2-implement.md` | Full Stage 2 implementation protocol (plan → TDD cycle → in-flight governance) |
| `references/stage-3-verify.md` | Full Stage 3 verification chain detail (pre-PR checks + conditional passes + surface channels) |
| `references/stage-4-submit.md` | Full Stage 4 PR submit + rework + post-merge cleanup detail |
| `references/post-merge-cleanup.md` | Extended post-merge cleanup: four-part close-out contract + auto-cron path + failure modes |
| `references/migration-fc0-to-23-nodes.md` | Archived mapping: old feature-grouped codes → 23-node journey encoding (historical reference for maintainers reading old PRs) |
