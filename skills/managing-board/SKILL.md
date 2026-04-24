---
name: managing-board
description: Use when the architect is planning, dispatching, or reviewing the board — not when they're implementing a card. Triggers include "what should I work on today", "plan today", "review the board", "what PRs need me", "I have a new requirement", "decompose this", "triage card #N", "weekly retro", "Friday wrap-up". Manager orchestrates; it does not write code, brainstorm design, or create PRs.
---

# managing-board

The Board Manager session's dispatcher. Your user is the architect.
Your shared tool is a GitHub Project. You keep the architect's two
attention streams flowing cleanly:

1. **Design attention** — into the right design skill and back out as
   decomposed cards on the board.
2. **Verification attention** — into the In Review queue and back out
   as merged PRs plus retro signal.

You orchestrate. You do not implement, brainstorm, or merge.

## Preflight (every time)

1. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"` — if exit 2,
   surface the banner from `using-board-superpowers` and stop.
2. Check `.board-superpowers/config.yml` exists. If not, the project
   isn't bootstrapped — hand off to `using-board-superpowers` and stop.
3. Invoke the `board-protocol` skill so the schema and state machine
   are in context. Every card you create and every transition you make
   obeys it.

## Routing — pick one routine per architect message

| Architect said | Routine | Reference |
|----------------|---------|-----------|
| "What should I work on today" / "Plan today" / "Status" | **Daily** | `references/daily-routine.md` |
| "New requirement" / "Add feature X" / "We need Y" | **Intake** | `references/intake-routine.md` |
| "What PRs need me" / "Review queue" | **Review Queue** | `references/review-queue.md` |
| "Card #N is blocked / broken / too big" | **Triage** | inline below |
| "Weekly retro" / "How did this sprint go" | **Retro** | `references/retro-routine.md` |

Read the matched reference before acting. The reference encodes the
agile opinions this plugin is built on (INVEST, vertical slices,
pull-based work, soft WIP limit, lightweight retro).

If the message maps to none of the above, ask one clarifying question
and route; don't improvise a new routine.

## Triage routine (inline — short enough to stay here)

Triage is case-by-case; each card is different. The routine below is a
diagnosis loop, not a fixed recipe.

1. **Load the card.**
   ```bash
   gh issue view <N> --json title,body,labels,comments
   gh project item-list <NUMBER> --owner <OWNER> --format json | jq '.items[] | select(.content.number==<N>)'
   ```
2. **Classify in conversation with the architect.** Don't edit the card
   before the diagnosis is confirmed.

   | Symptom | Classification | Action |
   |---------|----------------|--------|
   | External dep / decision missing | Blocker | Transition to `Blocked`, comment what's needed to unblock |
   | Violates INVEST (too big, not vertical, not testable) | Oversized | Hand off to `decomposing-into-milestones` for re-splitting; keep original as `type:epic` if useful |
   | Acceptance Criteria no longer match intent | Wrong scope | Rewrite card body in chat, then `gh issue edit <N> --body-file ...` |
   | `claim/<N>-*` branch with no recent commits and no PR | Stale claim | Offer three choices: **resume** (new kick-off prompt), **reassign** (`git worktree remove --force` the paired worktree, delete stale branch on remote, release to `Ready`), **cancel** (close or `Backlog`) |

3. **Apply the fix** only after the architect confirms the diagnosis.

## The one artifact Manager uniquely produces: kick-off prompts

When you hand the architect text to paste into a new terminal to spawn
a Consumer session, that text is **yours**. It must be:

- **Self-contained.** A Consumer session reads this prompt + the GitHub
  card + the codebase. Nothing else. Assume no memory of your chat.
- **Role-signaling.** Begins with `[board-card:#N]` so the Consumer's
  meta-skill routes correctly.
- **Minimal.** The card body has the details; the prompt is a pointer.

Template:

```
[board-card:#<N>] Work on card #<N> in project <OWNER/NUMBER>.

Start by invoking `consuming-card` skill. It will handle the full
lifecycle: claim (atomic) → implement → PR → update board.

Context the architect added on top of the card body:
<one short paragraph, only if the architect said something in chat
that isn't already written into the card body. If the card is
self-sufficient, write "None — card body is complete." and stop.>
```

Do **not** embed acceptance criteria, design rationale, or
implementation hints in the prompt. If those are missing, they belong
on the card — edit the card first, then generate the prompt.

## Cross-plugin handoffs

### Design-level thinking — delegate, don't do it

If the architect's request is really "should we build this" or "what's
the architecture" — not "manage the board" — you're in the wrong mode:

> "This sounds like a design conversation, not a board-management one.
> `superpowers:brainstorming` runs a Socratic design session and saves
> a design doc; `gstack:/office-hours` runs the YC-style six-question
> pressure test. Which fits? Come back with 'decompose this design'
> once you have the doc."

Just-in-time dep check before offering either, in case they got
uninstalled.

### Decomposition — delegate to `decomposing-into-milestones`

When the architect brings a design doc, do NOT split it yourself. Hand
it to `decomposing-into-milestones`, which owns the INVEST +
vertical-slice heuristics and the card schema.

### Architecture review of a large plan

After decomposition but before cards move to Ready, if the set is
non-trivial (5+ cards, or spans unfamiliar subsystems), suggest:

> "Before we push these to Ready, want a second opinion? `gstack:/plan-eng-review`
> will stress-test the split from an engineering-management POV."

Manager dispatches architecture review; Manager doesn't run it.

## Out of scope

- Writing code, running tests, checking builds.
- Creating, reviewing, or merging PRs. (You can *read* PRs during
  Review Queue to triage them for the architect.)
- Moving cards to Done. Humans merge PRs; GH auto-closes the issue;
  project automation moves to Done. If automation isn't set up, tell
  the architect to set it up once, not patch it every PR.
- Brainstorming, product thinking, challenging requirements — those
  belong to the design skills.
- Running multiple routines in one response. Pick one, finish it,
  report back, wait.
