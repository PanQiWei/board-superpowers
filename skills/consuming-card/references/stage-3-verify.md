# consuming-card — Stage 3: Verify

Full detail for the Verify stage (nodes C1-C4, transition to In Review).

## Iron law

**Never open a PR without completing the full verification chain.** The architect
delegates card delivery because the Consumer's "done" claim is backed by evidence.
Skipping verification turns the architect back into the QA bottleneck this skill
exists to remove. Pressure ("just ship it," "it's minor") does not override this
rule.

## C1 — Verification chain

Invoke `board-superpowers:composing-siblings` before each sub-skill to confirm
Mode-2 compatibility and namespace prefix correctness.

Run all three steps in sequence:

**Step 1 — `superpowers:verification-before-completion`**

Evidence-first pre-check. Do not claim "done" without running the actual checks
named in the card's Acceptance criteria:

- Name the specific test commands run and their output.
- Identify which ACs are verified by which test assertions.
- Flag any AC that has no automated check and explain what manual validation
  confirms it.

**Step 2 — `gstack:/review`**

Production-bug viewpoint. This skill examines the diff from the angle of "what
could go wrong in production" — SQL injection, LLM trust boundaries, N+1 queries,
error handling gaps. Run it on the full diff from `main` to the claim branch.

**Step 3 — `superpowers:requesting-code-review`**

Independent second-pair-of-eyes on the diff. This step is what makes
Producer-spawned mode (overnight batches) worthwhile — without it, Consumer has
just passed the review burden to the human architect unchanged.

Mode-2 note: verify `superpowers:requesting-code-review` is procedural before
invoking. If non-procedural in the installed version, fall back to `gstack:/review`
only and surface the gap as a Retro Note in the PR.

**All three must pass before proceeding to C2/C3/C4.**

### Common rationalizations to reject

| Rationalization | Reality |
|-----------------|---------|
| "Small change — verification is overkill" | Small changes hide gaps exactly because they get fewer eyes. The chain is calibrated for the smallest meaningful card. |
| "I'll skip step 3 and let the human reviewer catch it" | Then the Consumer hasn't reduced the architect's load — just deferred it. |
| "Tests pass = done" | Name which tests, which edge cases, which integration points. "`bun test` passes" is a start, not evidence. |
| "The card said 'trivial'" | Trivial-seeming changes break production regularly. Trivial = smaller scope, not fewer checks. |

## C2 — Cross-platform review (non-trivial cards)

For changes larger than a 1-line mechanical fix:

1. Invoke `board-superpowers:composing-siblings` for mode check.
2. If running in Mode-1 on Claude Code: invoke `gstack:/codex` to dispatch a
   Codex session against the same diff. The cross-platform review catches
   platform-specific assumptions (Claude-tool-name references, environment
   assumptions, path conventions).
3. If running in Mode-2: `gstack:/codex` spawns a Codex session and is NOT safe
   in Mode-2. Ask the architect to run it on the diff, or surface the gap as a
   Retro Note.

Skip this step for genuinely trivial changes (documentation-only, 1-line constant
fix with no behavior change). If in doubt, run it.

## C3 — Conditional QA (UI-touching cards)

Gate condition: card has `ui` label, OR card body mentions user-visible surfaces
(components, routes, views, CSS, HTML), OR the diff touches any file under
`src/components/`, `app/`, `public/`, `static/`, or similar UI paths.

If the gate fires:

1. Invoke `board-superpowers:composing-siblings`.
2. Delegate to `gstack:/qa <url>` — real-browser QA of the affected surface.
   Provide the URL of the locally-running or staging deployment. If no deployment
   is available, surface to the architect before opening the PR.
3. Document the QA result in the PR's Automated Verification section.

Mode-2: `gstack:/qa` is procedural and safe to invoke from a Mode-2 subagent.

## C4 — Conditional security audit (security-flagged cards)

Gate condition: card has `security` label, OR card body mentions authentication,
authorization, cryptography, PII, secrets management, or input sanitization, OR
the diff touches auth handlers, crypto utilities, or input-processing middleware.

If the gate fires:

1. Invoke `board-superpowers:composing-siblings`.
2. Delegate to `gstack:/cso` — OWASP / STRIDE audit of the change set.
3. Document findings and mitigations in the PR's Automated Verification section.
   If the audit surfaces a high-severity finding that blocks safe delivery, surface
   to architect as R-class proposal before opening the PR.

Mode-2: `gstack:/cso` is procedural and safe to invoke from a Mode-2 subagent.

## Transition to In Review

After all passing verification steps:

1. Invoke `board-superpowers:classifying-actions` (action_id — transition to
   In Review).
2. Invoke `board-superpowers:operating-kanban` action `transition_card` with target
   `In Review`.
3. Invoke `board-superpowers:auditing-actions` (transition record).
4. Proceed to Stage 4 (PR submit).

## Surface channels

How to surface information back to the architect during Stage 3:

| Event | Channel | Format |
|-------|---------|--------|
| Verification step failed | Conversation + card comment if durable | "Verification failed: `<command>` returned `<err>`. Investigating." |
| Blocker found during verification | R-class proposal in conversation + card comment | Same as Stage 2 blocker handling |
| Security audit finding blocks submit | R-class proposal in conversation | Structured: "Finding: <description>. Risk: <level>. Proposed mitigation: <X>. Proceed?" |
| All verifications pass | (no surface — PR open does this) | n/a |

## Cross-session continuity

If Stage 3 is interrupted (compaction, session end):

- The verification steps produce no persistent state changes (they are read-only
  analysis). Restart Stage 3 from the beginning.
- The worktree and claim branch are still valid; resume from `cd` into the worktree.
- Re-read the card body + comments before re-running verification to pick up any
  intervening architect feedback.
