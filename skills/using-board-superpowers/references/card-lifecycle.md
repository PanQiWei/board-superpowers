# Card lifecycle

The full narrative from "user has an idea" to "PR merged, Card closed". The entry skill body's "How a Card flows" diagram shows the shape; this reference walks each step in prose, naming who drives it and which cross-plugin handoffs happen along the way.

## Step 1 — Idea (no Card yet)

The user (or the architect via observation, retro, customer feedback, or upstream spec change) has a need. There is no Card yet — only intent.

If the idea is half-formed or the user wants to explore "is this even worth doing", the right next step is `superpowers:brainstorming` (mental model + requirements clarification) or `gstack:/office-hours` (founder-mode forcing questions). These are pre-board steps. The Card does not exist yet because the architect has not committed to building this.

## Step 2 — Design (still no Card, but artifact emerging)

Once the architect commits to "yes, build something here", the design conversation produces an artifact: a brainstorming transcript, an `office-hours` design doc, an eng-review architecture decision, or a written requirements summary. Where the artifact lives is local discipline (the project's `docs/plans/<feature>/` directory is one common convention; gitignored scratch is another).

For non-trivial work, two more cross-plugin invocations sharpen the design before any Card is created:

- `gstack:/plan-eng-review` — locks the architecture: data flow, edge cases, performance, test coverage.
- `gstack:/plan-design-review` — for UI work, validates the design system and visual hierarchy.

The output is a stable design surface that decomposition can act on. Going from idea → design → Cards in one pass without this step typically produces under-shaped Cards that need re-decomposition mid-flight.

## Step 3 — Decomposition into Ready Cards

`board-superpowers:decomposing-into-milestones` consumes the design artifact and emits one or more Cards into the GitHub Project, each with the canonical body schema:

- A thin SpecPointer to the authoritative design doc (when one exists).
- A Goal section saying what success looks like.
- An Acceptance criteria checklist of testable conditions.
- An Out of scope section so reviewers know what was deliberately deferred.
- A Dependencies block (`depends-on:` / `depended-on-by:`).
- A Notes section for caveats and design-time observations.

Each Card lands in `Backlog` initially, then transitions to `Ready` once the architect confirms it satisfies INVEST: independently demoable, negotiable, valuable on its own, estimable, small, testable. Cards that fail INVEST go back into the design loop or get re-split. The decomposition skill prefers vertical slices (each Card delivers an end-to-end thin sliver of value) over horizontal layers.

## Step 4 — Claim (Ready → In Progress)

When a Consumer is ready to start work, the claim transaction runs. It is a 4-step atomic operation:

1. Flip the Card's GitHub Project Status from `Ready` to `In Progress`.
2. Create a `git worktree` at the resolved base directory.
3. Cut a `claim/<N>-<slug>` branch from `origin/main` inside the worktree.
4. Push the empty claim branch so the board sees a single observable signal that the Card is now claimed.

Idempotent: re-running with the same Card and slug is a no-op when the same branch already owns the Card. Either all 4 steps succeed or the script aborts and rolls back what it can; partial states get surfaced rather than left to drift.

The claim is what activates the WIP cap arithmetic. Once `In Progress`, this Card is counted against `wip_limit` (along with any `In Review` Cards and any Cards holding a `suspended` label). `Blocked` Cards do not count.

## Step 5 — Implementation

The Consumer is now in its worktree. The implementation loop is a pure cross-plugin composition:

- `superpowers:writing-plans` — turn the Card's Acceptance criteria into an executable plan.
- `superpowers:test-driven-development` — Red → Green → Refactor.
- `superpowers:systematic-debugging` (when stuck) or `gstack:/investigate` (for a different angle).
- `superpowers:dispatching-parallel-agents` (Mode-1 only) when independent subtasks within the Card can be parallelized.

board-superpowers does not reimplement any of these. TDD is mandatory inside this loop; an adjacent planning skill saying "ready, start coding" does NOT excuse skipping Red → Green → Refactor.

If the Consumer hits a hard external blocker, the action is to transition the Card to `Blocked` and surface the reason in a Card comment. `Blocked` is not a terminal state — once unblocked, the Card transitions back to `In Progress` and work continues on the same `claim/<N>-<slug>` branch.

## Step 6 — Pre-PR verification chain

Before opening the PR, the Consumer runs an iron-law verification chain. Skipping any link makes "I'm done" a claim the architect would have to verify themselves — defeating the parallel-Consumer model.

- `superpowers:verification-before-completion` — evidence first; the actual checks named in the Acceptance criteria run, with their output captured.
- `gstack:/review` — production-bug viewpoint over the diff.
- `superpowers:requesting-code-review` — independent second-pair-of-eyes.

For non-trivial diffs, also `gstack:/codex` (cross-platform review). For UI cards, `gstack:/qa <url>`. For security-flagged cards (label `security` or auth/crypto/PII content), `gstack:/cso`.

## Step 7 — PR submit (In Progress → In Review)

The Consumer drafts the PR body satisfying the three-section contract: Automated Verification (with PASS evidence), Human Verification TODO (non-filler — either real eyeball items or an explicit "doc-only refactor, no behavior change — empty by intent"), Retro Notes (lessons worth keeping). Then `${CLAUDE_PLUGIN_ROOT}/scripts/submit-pr.sh` validates the contract and opens the PR. The script also auto-appends a `Closes #<N>` trailer at PR-OPEN time so GitHub's PR-merge → Issue-close → ProjectV2 Auto-close webhook fires when the PR merges. Hand-running `gh pr create` would skip the trailer and silently break the close link.

The Card transitions to `In Review` when the PR opens. Status updates happen via the GitHub Project's webhook integration, not an explicit script call.

## Step 8 — Review cycles

The architect (or a delegated reviewer) reviews the PR. Typical outcomes:

- **Approve + merge** — Card transitions to `Done` via webhook; Consumer runs post-merge cleanup (worktree removal, local branch delete, terminal audit row).
- **Request changes** — the Consumer pulls feedback into the same worktree, re-runs steps 5 + 6 + 7 on the same `claim/<N>-<slug>` branch (no new branch). The Card stays in `In Review`.
- **Close without merge** — the Card transitions to `Done` (closed) without a merge; Consumer runs cleanup. This path is rarer but legitimate (e.g., upstream made the change unnecessary).

## Step 9 — Post-merge cleanup

Once the PR is merged the Consumer:

1. Verifies PR state is `MERGED` via `gh pr view --json state`.
2. Verifies the Card transitioned to `Done` (Status webhook usually flips within 30 seconds; a 5-minute wait covers webhook lag).
3. Removes the local worktree (`git worktree remove`) and deletes the local `claim/<N>-<slug>` branch (the remote was deleted by the merge).
4. Writes the terminal audit row for the cleanup action.

If the Card Status did not flip, two distinct causes need different responses: a missing `Closes #<N>` trailer at PR-OPEN time means the webhook chain never registered the link (manual recovery required); a present link but a still-`In Review` Status means webhook delivery lag (wait, do not race the webhook by manually flipping Status). The `consuming-card` skill body has the diagnostic procedure.

## Failure paths

- **Stale claim** — Consumer abandoned mid-implementation. Architect runs the `managing-board` triage routine to release the claim, which re-flips Status to `Ready` and (optionally) preserves the worktree for human takeover.
- **Failed PR** — verification chain failed to pass; Consumer surfaces the failure to the architect rather than opening a half-baked PR.
- **Blocked card cycle** — repeated `Blocked` ↔ `In Progress` cycling on the same Card is a smell; the architect should re-shape or split the Card.

The lifecycle is designed so that every transition writes an audit row, every state has a clear owner, and no state requires the architect to be in the loop continuously — only at the planning bookend (decomposition) and the delivery bookend (review + merge).
