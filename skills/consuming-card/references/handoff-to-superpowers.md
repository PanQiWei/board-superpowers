# Handoff to superpowers & gstack

`consuming-card` does very little implementation work itself. Most of
its value comes from **delegating cleanly** to the right execution skill
and **wrapping** the result in the board contract.

This reference maps common decisions to the right handoff.

## Contents

- When to use which execution skill (subagent-driven-development · executing-plans · gstack /qa)
- When to use which PR skill (finishing-a-development-branch · /ship)
- Handing plan context without polluting it
- If the execution skill wants to change the card
- Preserving superpowers/gstack signatures

## When to use which execution skill

### Default: `superpowers:subagent-driven-development`

Pick this 80%+ of the time. It's the highest-quality execution path on
Claude Code.

What it gives you:

- Fresh subagent per implementation task (context isolation).
- Two-stage review: spec-compliance reviewer, then code-quality reviewer.
- Enforced TDD: RED→GREEN→REFACTOR, tests written before code.
- Status signals (DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED)
  you already know how to handle.

What it requires from you:

- A plan brief on disk (you produced one in Step 3 from the card).
- A working git worktree / branch (the claim branch, already set up).
- The `using-git-worktrees` superpowers skill may or may not engage;
  trust its routing.

### Fallback: `superpowers:executing-plans`

Only when subagents are unavailable on the current harness. On Claude
Code this is rare. If you're on Claude Code, prefer
`subagent-driven-development`.

### UI-heavy / visual cards: `gstack:/qa` after `/review`

If the card is primarily a UI concern and the `## Execution Hints`
suggest it, the gstack path gives you:

- `/review` for structural audit of the diff.
- `/qa` which uses a real browser (GStack Browser) for end-to-end
  verification.

When to pick gstack over superpowers:

- Card is about visual output, layout, or end-user interaction where
  screenshots matter more than unit tests.
- Card's hints say so.
- You've already implemented (perhaps with superpowers) and now need a
  browser-based verification pass before PR.

You can also **stack them** — use `subagent-driven-development` for the
core implementation, then `/qa` for the visual gate.

### Never: implement directly in consuming-card

Do NOT implement card logic, write tests, or make architectural decisions
in the Consumer session directly. Every time you're tempted to "just
make a small change" without delegating, you're eroding the isolation
that makes this whole structure work.

The one exception: tiny corrections during PR feedback. If the architect
comments on the PR and asks for a one-line fix, you may make it
directly. Anything larger, re-delegate.

## When to use which PR skill

### Default: `superpowers:finishing-a-development-branch`

Lightweight. Verifies tests, asks merge vs PR vs keep vs discard, runs
`gh pr create` with a basic body.

The generated body is intentionally minimal — that's why you have to
append. Don't try to inline the protocol sections by modifying the
skill's behavior; append after.

### Heavier path: `gstack:/ship`

Includes version bump, CHANGELOG update, diff review, push, PR create.
Use if:

- The project is configured for gstack's release flow (look for
  `VERSION` file, CHANGELOG.md conventions).
- The card is a release candidate, not a mid-flight feature.
- The architect's project has multiple release-signaling mechanisms
  (labels, milestones) that gstack integrates with.

Outside those cases, prefer `superpowers:finishing-a-development-branch`
— lighter, less risk of modifying state outside your card.

## Handing plan context without polluting it

The execution skills are sensitive to context window hygiene. When you
invoke them, give them:

- **The plan brief** (your synthesis of the card into a spec the
  execution skill expects).
- **The target branch name** (already created).
- **The test command(s) for this project** if discoverable (read
  `CLAUDE.md`, `package.json` scripts, `Makefile`, etc.).

Do NOT give them:

- Your conversation history.
- The full card body (the plan brief is already derived from it).
- Editorial comments about how you'd approach it.

The rule from superpowers docs: subagents don't inherit your context.
You construct exactly what they need. Apply the same discipline.

## If the execution skill wants to change the card

Sometimes subagent-driven-development notices the card is wrong — e.g.,
an acceptance criterion is untestable, or the card violates Out of Scope
by proxy.

Consumer's job when this happens:

1. Capture the execution skill's report.
2. Do NOT edit the card mid-flight. The card is the Manager's artifact.
3. Either:
   - Finish the card against the original acceptance criteria and flag
     the discrepancy in Retro Notes, OR
   - Treat it as a BLOCKED status, move the card to Blocked, and
     escalate to the architect to decide.

Choose (a) if the discrepancy is cosmetic/minor. Choose (b) if the
discrepancy means you can't credibly hit the acceptance criteria.

## Preserving superpowers/gstack signatures

Both systems announce themselves when invoked — "I'm using the
subagent-driven-development skill to execute this plan", "/ship: bumping
version, running tests...". Let those announcements happen. They tell
the architect what's running.

Do NOT suppress them. Do NOT paraphrase them. Do NOT add a
board-superpowers preamble that hides them.

Your job is to compose their capabilities into a milestone delivery,
not to re-brand them.
