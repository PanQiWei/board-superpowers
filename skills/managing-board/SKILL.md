---
name: managing-board
description: Use when the user wants to plan today's work, asks "what should I work on", asks for a morning briefing, wants to review the board state, wants to triage what's blocked, wants to review or merge open PRs, OR brings a new requirement / idea / feature for the board. Apply this skill even when the user doesn't say "manage the board" — any message that reads as Producer-side board orchestration (vs claiming and implementing a single card) routes here. Do NOT use this skill when the user names a specific card and wants to work on it — that's the consuming-card skill.
when_to_use: Use when the user says "what should I work on", "morning briefing", "today's plan", "review the PRs", "what's in In Review", "merge ready", "new requirement", "intake this idea", "I have a feature for the board", "what's blocked", "triage the board", "release stale claims", "weekly view".
argument-hint: "[routine]"
---

# managing-board

This is the Producer-session main skill for board-superpowers. It runs four routines:

| Routine | When to pick |
|---------|--------------|
| **daily** | "what should I work on" / "morning briefing" / "today's plan" |
| **review-queue** | "review the PRs" / "what's in In Review" / "merge ready" |
| **intake** | "new requirement" / "intake this idea" / "I have a feature" |
| **triage** | "what's blocked" / "triage the board" / "release stale claims" |

If the user invokes via `/board-superpowers:managing-board <routine>`, the routine name arrives as the first argument. Otherwise pick the routine from the user's prompt vocabulary using the table above. If the prompt is genuinely ambiguous (e.g., "let's look at the board"), **ask the Producer** which routine they want — do NOT pick a default. The cost of asking is low; routing wrong burns more attention.

**Required sub-skills**: `board-superpowers:board-canon` (read schema before any transition decision), `board-superpowers:enforcing-pr-contract` (review-queue contract validation).

## Daily routine

Goal: produce a one-screen briefing of the board's current state that helps the Producer decide what to do next.

1. **Read the board**. Run `bash scripts/read-board.sh --owner <owner> --project <number>`. The owner + project number live in the repo's `.board-superpowers/config.yml`. Parse the JSON output.

2. **Group by Status field**. Produce a markdown summary in this format:

   ```markdown
   ## Board state — <YYYY-MM-DD>

   ### In Progress (<count>)
   - #<N> <title> — claimed by <consumer>, <age>

   ### In Review (<count>)
   - #<N> <title> — PR #<P>, <age> since opened

   ### Blocked (<count>)
   - #<N> <title> — blocker: <one-line>

   ### Ready (<count>)
   - #<N> <title> — <estimate>

   ### Backlog (<count>)
   - <count> cards — names omitted unless ≤ 5 total
   ```

3. **Highlight WIP situations**. Per `board-superpowers:board-canon` § "WIP counting", flag any Consumer at their cap. Flag any Consumer with stale claims (>72h with no commits beyond the empty claim marker).

4. **Recommend ONE next action** from this priority list:
   - "Review the review queue" (if `In Review` count > 0)
   - "Triage Blocked" (if `Blocked` count > 0)
   - "Claim a Ready card" (if `Ready` count > 0 and the Producer wants to context-switch into Consumer mode)
   - "Run intake" (if all the above are empty — the board is idle)

5. **Audit-log entry**. Append one line to `~/.board-superpowers/<host>/<repo>/audit-local.jsonl` recording that the daily routine ran (helper: `bsp_audit_local_write` from `scripts/lib/common.sh`).

`references/daily.md` covers the empty-board case, single-Consumer projects, stale-claim detection mechanics, and tone notes.

## Review-queue routine

Goal: validate every open PR linked to a card against the three-section PR contract, surface violations, route cards back to `In Progress` for rework when needed.

1. **List open PRs linked to cards**. `gh pr list --state open --json number,title,body,headRefName`. Filter to branches matching `claim/<N>-...`.

2. **For each PR**: invoke `board-superpowers:enforcing-pr-contract` to validate the body. (See that skill's § "How the Producer enforces" for the exact rules.)

3. **For each violation**:
   - Comment on the PR pointing at the failing section + the fix template from the `enforcing-pr-contract` skill's references.
   - Do NOT immediately transition the card from `In Review` back to `In Progress` — that's a mutating action; propose the transition to the architect, await acknowledgement, then act.
   - Append an audit-log entry recording the violation (decision class R, reason `pr-contract-violation: <section>`).

4. **For each compliant PR**: no action — leave the card in `In Review` for human merge approval.

5. **Summarize** — return a count of (compliant / violated / total).

`references/review-queue.md` covers merge-conflict handling, multi-card PRs, Producer-self-review (when Producer = Consumer), and the approve-vs-request-changes boundary (this skill never auto-merges; merge stays a human decision).

## Intake routine

Goal: turn a new requirement (text, design doc, idea) into a shape decision: spec doc / design conversation / direct card.

1. **Acknowledge the requirement** — repeat back what the Producer said in 1-2 sentences. Confirm understanding before shaping.

2. **Pick the routing** based on signal type (`references/intake.md` has the full decision tree):

   - **Idea / vision** → `gstack:/office-hours` for direction-setting. Produces an "is this worth building" verdict.
   - **Architecture decision** → `gstack:/plan-eng-review`. Produces an architecture lock.
   - **Multi-step requirement** that's already direction-set → `superpowers:brainstorming` for sharper decomposition. Then the architect hand-decomposes the result into Ready cards.
   - **Single-card-sized work** that's clearly defined → propose a card body to the architect using the schema from `board-superpowers:board-canon` § "Card body schema"; after acknowledgement, run `gh issue create` and add it to the project as Backlog.

3. **NOT this skill's job to do the work itself**. The intake routine ends with the work being either a spec / design artifact or a Ready card on the board. If the architect tries to "just do it" mid-intake, push back: the design rests on intake → decompose → claim being separate acts.

4. **Audit-log entry** for the intake decision.

## Triage routine

Goal: scan Blocked cards + stale claims; recommend either unblocking actions or release.

1. **Read Blocked cards**: `bash scripts/read-board.sh --status Blocked`. For each, inspect the card body for the named blocker (per `board-superpowers:board-canon` state machine, Blocked entries name their blocker in a card comment). Recommend an action.

2. **Read stale claims**: list `claim/N-...` branches; check commit count beyond the initial empty claim marker; flag any > 72h with no progress.

3. **Recommend release** for stale claims older than 7 days with the original Consumer notified — release is a mutating action; propose to the architect first.

`references/triage.md` covers blocker classification (external-dependency / decision-pending / stale-block), the release procedure, suspended-card review, and what's intentionally NOT in this routine (estimate calibration, velocity tracking — those are out of scope).

## How mutating actions are handled

Every mutating action this skill performs (Status flips, card body writes, PR comments, branch deletes, audit-log writes) follows this discipline:

1. **Propose** the action to the architect with a one-line description.
2. **Wait** for explicit acknowledgement.
3. **Act**.
4. **Append an audit-log entry** to `~/.board-superpowers/<host>/<repo>/audit-local.jsonl` via `bsp_audit_local_write` (defined in `scripts/lib/common.sh`).

Some actions may be classified as auto-act-OK by per-repo or per-user override rules in `.board-superpowers/config.yml`; until those overrides are configured, treat every action as requiring acknowledgement.
