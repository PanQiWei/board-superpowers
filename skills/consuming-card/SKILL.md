---
name: consuming-card
description: Use when this session is dispatched to implement one specific board card OR when the user asks to pull a card from the board without naming one — one session = one card = one PR. Triggers include the first user message containing `[board-card:#N]`, "claim card N", "work on card N", "pick up #N", "start on the board card", "pull a card", "pick something from the board". Owns the whole lifecycle end-to-end, including self-selecting a card from the Ready column when none is specified; delegates TDD, code review, and PR mechanics to the relevant superpowers / gstack skills.
---

# consuming-card

You are a Board Consumer session. One card, one PR, done.

You are not in a chat with a human during implementation. You get
dispatched, you deliver, you report back through the PR. The only
times you speak to the user:

1. **At start** — to confirm the card (and, if no card number was
   given in the kick-off, to surface Ready candidates and ask which
   one to pull). To surface protocol violations that stop you before
   work begins.
2. **At end** — to hand over the PR URL and note any blockers.
3. **Mid-flight only on BLOCKED / NEEDS_CONTEXT** from a delegated
   execution skill that you cannot resolve yourself. Exhaust local
   recovery first.

## Lifecycle

```
┌──────────────────────────────────────────────────────────────┐
│ 0. SELECT (opt.)    query Ready cards, surface candidates,   │
│                     user picks one  (skipped if kick-off     │
│                     already carried [board-card:#N])         │
│ 1. PREFLIGHT        check-deps · board-protocol · read card  │
│ 2. CLAIM + ISOLATE  claim-card.sh → branch + worktree        │
│                     cd into worktree · transition → In Progress│
│ 3. DELEGATE IMPL    superpowers:subagent-driven-development  │
│                     (default) / executing-plans / gstack QA  │
│ 4. PR               finishing-a-development-branch / /ship,  │
│                     then APPEND protocol sections            │
│ 5. UPDATE BOARD     transition card → In Review, comment PR  │
└──────────────────────────────────────────────────────────────┘
```

All steps after CLAIM run **inside** the worktree that `claim-card.sh`
creates. A Consumer session never writes implementation code into
the caller's primary working tree — that is how parallel sessions
stay out of each other's way.

## Step 0 — Card Selection (only when no `#N` was given)

Skip this step if the kick-off prompt already carries
`[board-card:#N]` or a literal card number ("card 42", "#42",
"pick up 42"). `N` is already bound — go to Step 1.

Otherwise: the user said "pull a card", "start on the board card",
"work on the board", or similar. **You pull; you never silently
pick.** The contract is: query Ready cards, surface candidates, ask
for a one-shot confirmation. Anything else risks claiming the wrong
card and burning another Consumer's attention on the undo.

### Query Ready candidates

Load the project from config:

```bash
PROJECT="$(grep '^project:' .board-superpowers/config.yml | awk '{print $2}')"
```

Use `gh issue list` (or the Manager skill's MCP path when available)
to fetch open issues with the project's Ready status. Filter in this
order:

1. **Status = Ready.** Never surface `Backlog` cards — those haven't
   been sanity-checked by the architect.
2. **Dependencies satisfied.** Parse `Depends on #D, #E` lines in
   each candidate's Context section. Drop cards where any dep is
   still open or not-yet-merged.
3. **Size hint (if any).** If the kick-off included a hint like
   "pick a small one", "something quick", "a warm-up", prefer
   `size:XS` / `size:S` labels.
4. **Oldest first** among remaining candidates. Cards that have sat
   in Ready longest get pulled first — queue fairness.

Take the top 3. If there are zero Ready cards after filtering, tell
the user — do not downgrade to Backlog or claim anyway.

### Surface + confirm

Present the candidates, then stop and wait for the user's pick:

```
Ready cards you could claim right now:

  [1] #42 (size:S)  Add /dashboard email preference toggle
      no deps · in Ready since 2026-04-20
  [2] #43 (size:XS) Fix typo in marketing copy
      no deps · in Ready since 2026-04-21
  [3] #45 (size:M)  Wire up webhook retry queue
      no deps · in Ready since 2026-04-17 (oldest)

Which should I pick up? Reply with a number, or "none" to stop.
```

Do **not** claim anything in this step. No branch is pushed, no card
is transitioned. If the user replies `none`, stop the session cleanly
with no side effects.

Once the user answers with a number, bind that card's number to `N`
and proceed to Step 1.

## Step 1 — Preflight

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"   # exit 2 → abort, surface banner
```

Then invoke the `board-protocol` skill — it loads the card / PR schema
and state machine into context.

### Read and validate the card

`N` is already bound — either from the kick-off prompt
(`[board-card:#N]`, "claim card N", etc.) or from Step 0's
selection. Load:

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

## Step 2 — Claim + Isolate

`claim-card.sh` does two things in one atomic step:

1. **Lock** the card by pushing a new remote branch (`claim/<N>-<slug>`).
   Creating a remote branch is atomic in git — race losers fail
   cleanly with exit code 10.
2. **Create a dedicated worktree** for this session. Every Consumer
   runs in its own isolated checkout so parallel sessions cannot
   clobber each other's HEAD or WIP.

Derive a short slug from the card title (lowercase, hyphenated, first
~5 meaningful words, ≤ 40 chars per board-protocol) and run the script:

```bash
TITLE="$(gh issue view <N> --json title --jq .title)"
SLUG="$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
        | cut -d'-' -f1-5)"

export BOARD_SP_SESSION_SLUG="s-$(openssl rand -hex 2)"
CLAIM_OUT="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/claim-card.sh" <N> "$SLUG")"
BRANCH="$(printf '%s\n' "$CLAIM_OUT"    | sed -n 's/^branch=//p')"
WORKTREE="$(printf '%s\n' "$CLAIM_OUT"  | sed -n 's/^worktree=//p')"
```

Stdout contract on success (two lines, in order):

```
branch=claim/<N>-<slug>
worktree=<absolute path to the worktree>
```

The worktree sits at one of three locations (script picks per priority):

| Priority | Location | When |
|----------|----------|------|
| 1 | `$BOARD_SP_WORKTREE_DIR/<branch>` | Env var set by caller (CI, manual override). |
| 2 | `<primary>/.worktrees/<branch>` | `.worktrees/` exists in the repo AND is gitignored. Opt-in project convention. |
| 3 | `$HOME/.config/superpowers/worktrees/<project>/<branch>` | **Default** — global, outside repo, no gitignore concern. |

Interpret exit code:

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | Claimed — `$BRANCH` is the feature branch, `$WORKTREE` is the isolated checkout | Continue |
| 10 | Another session beat you | Stop. Tell the architect who won (script stderr says). Do not retry. |
| 20 | Git / network / worktree-setup error | Surface the error. Do not retry automatically. |
| 30 | Script-arg bug (our bug) | Report it to the architect. |

### Enter the worktree

**Before anything else**, move this session into the worktree:

```bash
cd "$WORKTREE"
```

All subsequent steps — reading the card, writing the plan brief,
invoking the execution skill, opening the PR — happen **inside**
`$WORKTREE`. If a step tries to run from the caller's primary
working tree, you will either trample another Consumer's WIP or
create diffs against the wrong branch. The script's whole point is
that you never have to worry about either.

### Transition + comment

```bash
PROJECT="$(grep '^project:' .board-superpowers/config.yml | awk '{print $2}')"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/transition-card.sh" \
  --issue <N> --project "$PROJECT" --to "In Progress"
gh issue comment <N> \
  --body "🔵 Claimed by Consumer session \`$BOARD_SP_SESSION_SLUG\` on branch \`$BRANCH\` (worktree \`$WORKTREE\`)."
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

Save to `docs/board-superpowers/plans/card-<N>.md` **without committing**.
The path is gitignored so `subagent-driven-development` can read it on
disk while main stays clean — the card body on GitHub is the source of
truth, and the plan brief is Consumer-session scratch. If the
architect wants a trace of your reasoning, paste a short version into
the PR's Summary section rather than shipping the full brief.

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

> "Card #<N> delivered as PR #<PR>. Branch: `<BRANCH>`. Worktree:
> `<WORKTREE>`. Board updated to In Review. Human Verification TODO:
> `<count>` item(s).
>
> This session is done. Close it, or hand it another `[board-card:#M]`
> to pick up another card (which will get its own new worktree)."

Do **not** start another card in this session unless the architect
explicitly dispatches one. One session = one PR = one worktree is the
contract that makes the whole scheduling model work.

### After the PR merges (reference for the architect)

The worktree is safe to leave around until merge. Once the PR
lands, the architect (or any future Consumer session in the same
project) can reclaim the disk:

```bash
git -C <primary-repo> worktree remove --force "$WORKTREE"
git -C <primary-repo> branch -D "$BRANCH"  # optional — keep if you want the local ref
```

Automating this on merge is a future card; for now treat it as a
manual housekeeping step (the cost is just disk, no correctness
issue).

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

1. Confirm: "Abandon card #N and discard partial work? This removes
   the worktree at `$WORKTREE`, deletes the claim branch, releases
   the card to `Ready`, and nothing is recoverable."
2. On confirm — note the order: remove worktree first (while we
   still know its path), then delete branches, then update the card:
   ```bash
   PRIMARY="$(git -C "$WORKTREE" rev-parse --git-common-dir)/.."
   git -C "$PRIMARY" worktree remove --force "$WORKTREE"
   git -C "$PRIMARY" branch -D "$BRANCH"
   git -C "$PRIMARY" push origin --delete "$BRANCH"
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/transition-card.sh" \
     --issue <N> --project "$PROJECT" --to "Ready"
   gh issue comment <N> --body "🔄 Released by session \`$BOARD_SP_SESSION_SLUG\`: <reason if given>. Available to re-claim."
   ```
   This session's cwd may be inside `$WORKTREE` — once the worktree
   is removed, cd out of it or just end the session.

## Out of scope

- TDD, code review, PR body writing from scratch — all delegated.
  Your job is to compose their output with the board contract.
- Merging PRs. Humans merge.
- Skipping the Human Verification TODO section even for trivial cards.
  Writing "None — fully covered by automated tests." is allowed;
  omitting the section is not.
- Working on more than one card in one session.
- Silently picking a card in Step 0. If no `#N` was given, always
  surface candidates and get one-shot user confirmation before
  claiming.
- Running implementation steps in the caller's primary working tree
  after CLAIM completes. Everything happens in the worktree
  `claim-card.sh` creates.
