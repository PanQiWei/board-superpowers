# consuming-card — Stage 2: Implement (TDD-driven)

Full detail for the Implementation stage (nodes B1-B5, F1 stakeholder routing).

## B1 — Plan synthesis (C1 handoff)

Before writing any production code, synthesize an executable plan:

1. Invoke `board-superpowers:composing-siblings` to check Mode-2 compatibility and
   confirm `superpowers:writing-plans` is procedural.
2. Delegate to `superpowers:writing-plans`. Input: the card's Acceptance criteria
   section + any spec docs resolved in Stage 1 (A3). Output: a step-by-step
   TDD-shaped plan with failing-test assertions for each AC.
3. Save the plan to `docs/board-superpowers/plans/card-<N>-brief.md` in the
   worktree (gitignored — ephemeral per-session scaffolding).

This plan is the executable specification the TDD cycle operates against. Do not
skip it even for "obvious" implementations — the plan surfaces hidden ambiguities
in the ACs before code is written, not after.

## B2 — TDD mutation cycle (C2 handoff)

Execute the plan using the mandatory TDD loop:

1. Invoke `board-superpowers:composing-siblings` to confirm compatibility.
2. Delegate to `superpowers:test-driven-development` for the Red → Green → Refactor
   cycle on each acceptance criterion.
   - **Red**: write a failing test that validates the AC.
   - **Green**: write the minimal production code to make the test pass.
   - **Refactor**: clean up without losing the green state.
3. Repeat B2 for each AC in the plan.

**When stuck mid-implementation**:

- Invoke `board-superpowers:composing-siblings`, then choose:
  - `superpowers:systematic-debugging` — for bugs, test failures, unexpected behavior.
  - `gstack:/investigate` — for a different investigative angle (broader context,
    external API issues, environment questions).
- Document the investigation in a card comment if a decision or finding is durable.

**Mutating action governance during B2**:

Every commit, file change, or state mutation runs through the classify-then-audit protocol:

1. Resolve `action_id` for the action (from `board-superpowers:classifying-actions`
   `references/action-id-catalog.md`).
2. Invoke `board-superpowers:classifying-actions` → A / R / N.
3. A: act → `board-superpowers:auditing-actions` (1 entry).
4. R: audit propose → surface to architect → await ack → on approve: act + audit
   resolve; on decline: audit decline + abort.
5. N: refuse and surface block reason; no audit entry.

## B3 — TDD-skip refusal

When under pressure ("it's obvious," "no tests needed for this," "just ship it"):

**Do not bypass TDD.** The verification chain in Stage 3 validates behavior against
tests. Without a test, "done" becomes a claim the next session cannot verify. The
architect delegates card delivery precisely because the Consumer's "done" is backed
by a machine-executable verification chain — that guarantee evaporates without tests.

If the AC genuinely has no testable surface (pure documentation, configuration-only
change), document that explicitly in the plan and in the PR's Automated Verification
section. Do not silently skip.

## B4 — Cross-card refusal

The claim transaction owns the card's slice of work. Files, modules, and
infrastructure outside this card's scope are NOT yours to modify:

- **Shared infrastructure** (CI configs, shared libs, common utilities): surface to
  architect as an R-class proposal before modifying. If the change is clearly required
  by this card's AC, propose the boundary-crossing explicitly and let the architect
  decide scope.
- **Files claimed by another card**: check `git branch -r | grep claim/` and `gh
  issue list --label "in-progress"` to identify live claims. Do NOT modify files
  another Consumer is actively changing.
- When cross-card touch is genuinely necessary: invoke
  `board-superpowers:classifying-actions` for the cross-card modification and treat
  as R-class regardless of its normal classification. Architect ack required.

## B5 — Permission-boundary preservation

Every mutating action flows through `board-superpowers:classifying-actions`. This is
not optional:

- The autonomy classification matrix (in `board-superpowers:classifying-actions`)
  determines which actions the Consumer can take silently (A-class) vs which require
  architect acknowledgement (R-class).
- "I'm confident it's safe" does not substitute for the classifier. The classifier
  encodes project-level norms the architect set; overriding them ad-hoc violates
  the governance contract.
- If you believe a classification is wrong, surface the concern to the architect via
  an R-class proposal comment — do NOT self-reclassify.

## F1 — Stakeholder routing (mid-implementation)

When external feedback arrives during Stage 2 (PR comment, direct message, scope question):

**Decision framework**:

1. **Integrate within current card slice** — if the feedback targets behavior
   already in this card's ACs and the fix fits the worktree. Act without escalation.
2. **Escalate as cross-card touch** — if the feedback requires modifying files
   outside this card's scope. Treat as B4 (cross-card refusal → R-class proposal).
3. **Defer to follow-up card** — if the feedback is a new requirement beyond this
   card's ACs. Acknowledge, create a comment on the card noting the deferred scope,
   and continue. Do NOT expand the card's scope unilaterally.

Judgment call on in-slice vs cross-card requires high architect taste (design judgment
that is hard to automate). When in doubt, surface the question rather than decide
silently. A wrong in-slice call costs
a rework loop; a wrong cross-card call costs a broken neighbor's work.

## In-flight blocker handling

If the card is blocked (waiting on external dependency, API outage, blocked on architect decision):

1. Comment on the card naming the specific blocker: "Blocked on <X> — <one-line description>."
2. Invoke `board-superpowers:classifying-actions` (action_id 6 — transition to Blocked).
3. Invoke `board-superpowers:operating-kanban` with action `transition_card` and target
   `Blocked`. For the `github-project-v2` projection this updates the ProjectV2 Status field.
4. Invoke `board-superpowers:auditing-actions` (action_id 6, resolve).
5. Surface the blocker to the architect.

When the blocker clears:
1. Invoke `board-superpowers:classifying-actions` (action_id — Blocked → In Progress).
2. Invoke `board-superpowers:operating-kanban` action `transition_card` with target `In Progress`.
3. Audit the transition.
4. Resume Stage 2.

Do NOT churn the Status field on every commit. Status reflects the gross state of
the work, not internal progress ticks.
