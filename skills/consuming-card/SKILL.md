---
name: consuming-card
description: Use when this session is dispatched to implement one specific board card — one session = one card = one PR. Triggers include the first user message containing `[board-card:#N]`, "claim card N", "work on card N", "pick up #N", "start on the board card". Owns the whole lifecycle end-to-end; delegates TDD, code review, and PR mechanics to the relevant superpowers / gstack skills.
---

# consuming-card

You are a Board Consumer session. One card, one PR, done.

You are not in a chat with a human during implementation. You get
dispatched, you deliver, you report back through the PR. The only
times you speak to the user:

1. **At start** — to confirm the card and surface protocol violations
   that stop you before work begins.
2. **At end** — to hand over the PR URL and note any blockers.
3. **Mid-flight only on BLOCKED / NEEDS_CONTEXT** from a delegated
   execution skill that you cannot resolve yourself. Exhaust local
   recovery first.

## Lifecycle

```
┌──────────────────────────────────────────────────────────────┐
│ 1. PREFLIGHT       check-deps · board-protocol · read card   │
│ 2. CLAIM (atomic)  claim-card.sh → branch = lock = feature   │
│                    transition card → In Progress             │
│ 3. DELEGATE IMPL   superpowers:subagent-driven-development   │
│                    (default) / executing-plans / gstack QA   │
│ 4. PR              finishing-a-development-branch / /ship,   │
│                    then APPEND protocol sections             │
│ 5. UPDATE BOARD    transition card → In Review, comment PR   │
└──────────────────────────────────────────────────────────────┘
```

## Step 1 — Preflight

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"   # exit 2 → abort, surface banner
```

Then invoke the `board-protocol` skill — it loads the card / PR schema
and state machine into context.

### Read and validate the card

Extract `N` from the kick-off prompt (`[board-card:#N]`). Load:

```bash
gh issue view <N> --json number,title,body,state,labels
```

Abort if any of these fails:

- Body lacks `<!-- board-superpowers:card -->` marker (not a managed card).
- Body missing any required section (Context / Acceptance Criteria /
  Out of Scope / Size) — tell the architect to fix via Manager.
- Card status is not `Ready`. `Backlog` bypasses the architect's
  sanity gate; `In Progress` means already claimed; `In Review` /
  `Done` means already shipped.

### Check dependencies

Parse `Depends on #D, #E` lines in the Context section. For each:

```bash
gh issue view <DEP> --json state,labels
```

A dep is satisfied iff `state == closed` AND a merged PR closed it.
If any dep is unsatisfied, abort and ask the architect to unblock first.

## Step 2 — Claim (atomic)

Derive a short slug from the card title (lowercase, hyphenated, first
~5 meaningful words, ≤ 40 chars per board-protocol) and run the
claim script:

```bash
TITLE="$(gh issue view <N> --json title --jq .title)"
SLUG="$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
        | cut -d'-' -f1-5)"

export BOARD_SP_SESSION_SLUG="s-$(openssl rand -hex 2)"
BRANCH="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/claim-card.sh" <N> "$SLUG")"
```

Interpret the script's exit code:

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | Claimed — `$BRANCH` is the feature branch | Continue |
| 10 | Another session beat you | Stop. Tell the architect who won (script stdout says). Do not retry. |
| 20 | Git / network error | Surface the error. Do not retry automatically. |
| 30 | Script-arg bug (our bug) | Report it to the architect. |

You are now on the claim branch. Transition the card and comment:

```bash
PROJECT="$(grep '^project:' .board-superpowers/config.yml | awk '{print $2}')"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/transition-card.sh" \
  --issue <N> --project "$PROJECT" --to "In Progress"
gh issue comment <N> --body "🔵 Claimed by Consumer session \`$BOARD_SP_SESSION_SLUG\` on branch \`$BRANCH\`."
```

## Step 3 — Delegate implementation

**You do not write the implementation.** Delegate. Just-in-time dep
check first (`check-deps.sh`), then pick the path:

| Execution skill | When to pick |
|-----------------|--------------|
| `superpowers:subagent-driven-development` | **Default.** TDD, two-stage review, context isolation. Fits ~80% of cards. |
| `superpowers:executing-plans` | Fallback when subagents unavailable (rare on Claude Code). |
| `gstack:/review` then `gstack:/qa` | UI-heavy / visual cards, or when `## Execution Hints` names this path. |

See [references/handoff-to-superpowers.md](references/handoff-to-superpowers.md) for details on stacking and trade-offs.

### Build the plan brief

The execution skill wants a spec, not a card. Synthesize a plan from
the card's sections:

```markdown
# Plan: Card #<N> — <title>

<paste Context>

## Acceptance Criteria (from card)
<paste Acceptance Criteria>

## Out of Scope (from card — do NOT do these)
<paste Out of Scope>

## Target branch
<$BRANCH> (already created and claimed)

## Size ceiling
<Size label>. If work feels bigger, STOP and report NEEDS_CONTEXT —
the card may need re-splitting.

## Execution hints (from card)
<paste Execution Hints, or "none">
```

Save to `docs/board-superpowers/plans/card-<N>.md` and commit it as a
separate commit (before any implementation commits) so the plan is
part of the PR's history.

### Handle the execution skill's status signals

| Status | Action |
|--------|--------|
| DONE | Continue to Step 4. |
| DONE_WITH_CONCERNS | Continue; record concerns for Retro Notes. |
| NEEDS_CONTEXT | Provide it (from card / linked design doc) if possible. If not, escalate. |
| BLOCKED | Unrecoverable; escalate. |

## Step 4 — PR

Delegate the PR mechanics too:

| PR skill | When |
|----------|------|
| `superpowers:finishing-a-development-branch` | **Default.** Lightweight. |
| `gstack:/ship` | Project configured for gstack's release flow (VERSION file, CHANGELOG conventions). |

Both produce a base PR body. **Do not replace** — **append** the three
protocol-required sections:

```
## Automated Verification     (what you actually ran + outcomes)
## Human Verification TODO    (concrete E2E steps, or the exact
                              string "None — fully covered by
                              automated tests.")
## Retro Notes                (estimate vs actual · surprises ·
                              suggested decomposition)

Closes #<N>.

<!-- board-superpowers:pr -->
```

Full template, per-section rules, examples of good/bad items, and the
closing-line rationale: see [references/pr-template.md](references/pr-template.md).

Apply by editing the PR:

```bash
gh pr edit <PR_NUMBER> --body-file /tmp/final-pr-body.md
```

## Step 5 — Update the board and stop

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/transition-card.sh" \
  --issue <N> --project "$PROJECT" --to "In Review"
gh issue comment <N> --body "🟢 PR #<PR> opened by session \`$BOARD_SP_SESSION_SLUG\`. Moved to In Review."
```

Report back to the architect:

> "Card #<N> delivered as PR #<PR>. Branch: `<BRANCH>`. Board updated
> to In Review. Human Verification TODO: `<count>` item(s).
>
> This session is done. Close it, or hand it another `[board-card:#M]`
> to pick up another card."

Do **not** start another card in this session unless the architect
explicitly dispatches one. One session = one PR is the contract that
makes the whole scheduling model work.

## Escalation — BLOCKED or irrecoverable NEEDS_CONTEXT

1. Do not delete the claim branch; leave the partial work.
2. Move the card to `Blocked`:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/transition-card.sh" \
     --issue <N> --project "$PROJECT" --to "Blocked"
   ```
3. Comment with specifics: what blocked you, how many commits of
   partial progress are on the branch, what's needed to unblock.
4. Stop and tell the architect.

## Abandonment — architect says cancel

1. Confirm: "Abandon card #N and discard partial work? This deletes
   the claim branch, releases the card to `Ready`, and nothing is
   recoverable."
2. On confirm:
   ```bash
   git checkout main
   git push origin --delete "$BRANCH"
   git branch -D "$BRANCH"
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/transition-card.sh" \
     --issue <N> --project "$PROJECT" --to "Ready"
   gh issue comment <N> --body "🔄 Released by session \`$BOARD_SP_SESSION_SLUG\`: <reason if given>. Available to re-claim."
   ```

## Out of scope

- TDD, code review, git worktree setup, PR body writing from scratch —
  all delegated. Your job is to compose their output with the board
  contract.
- Merging PRs. Humans merge.
- Skipping the Human Verification TODO section even for trivial cards.
  Writing "None — fully covered by automated tests." is allowed;
  omitting the section is not.
- Working on more than one card in one session.
