# Retro Routine

Triggered by: "Weekly retro", "How did this sprint go", "Friday wrap-up",
"Let's reflect on this week".

Lightweight retrospective. Not the full SCRUM retro ceremony — this is
signal aggregation from the retro notes Consumers left in their PRs,
plus a look at lifecycle metrics from the board.

Purpose: feed insights back into `decomposing-into-milestones` heuristics
and, if necessary, back into CLAUDE.md as project-specific decomposition
rules.

## Contents

- Step 1 — Pick the window
- Step 2 — Gather signals (merged PRs · closed cards · stuck cards)
- Step 3 — Cluster findings (decomposition · verification · flow)
- Step 4 — Render the report (fixed template)
- Step 5 — Offer follow-up actions
- Step 6 — Log the retro
- Anti-patterns

## Procedure

### Step 1 — Pick the window

Default: last 7 days. Architect can override ("retro for this month",
"retro on the checkout epic").

### Step 2 — Gather signals

**From merged PRs in window:**

```bash
gh pr list --state merged --search "merged:>$(date -d '7 days ago' +%Y-%m-%d)" \
  --json number,title,body,mergedAt,files,additions,deletions
```

For each PR with `<!-- board-superpowers:pr -->`:
- Extract `## Retro Notes` section.
- Extract size: what did the card say (`## Size`), what was the actual
  diff size?
- Extract card number.

**From closed cards in window:**

```bash
gh issue list --state closed --search "closed:>$(date -d '7 days ago' +%Y-%m-%d)" \
  --json number,title,body,closedAt,labels
```

For each with `<!-- board-superpowers:card -->`:
- Time from Ready→Done (approximate via first transition timestamp).
- Whether it was decomposed mid-flight (look for child cards referenced
  by `Closes #<parent>` or by `parent: #<N>` language in comments).

**From currently Blocked cards:**
- Anything that's been Blocked for > 3 days is a signal.

### Step 3 — Cluster findings

Run three passes:

**Pass A — Decomposition quality:**
- How many cards were re-split mid-flight? (Target: < 20%.)
- How many Retro Notes say "should have been split"?
- How many PRs came in smaller than their card's Size label suggested?
  (Over-sizing is almost as bad as under-sizing — it means the card
  could have been split earlier.)
- Any recurring themes in what got under-scoped? (E.g., "every auth card
  turned out bigger than expected.")

**Pass B — Verification load:**
- How many PRs had `Human Verification TODO` sections with > 3 items?
  (High human-TODO count = test coverage gap.)
- Any areas of the product where the same E2E step gets verified on
  every PR? (Candidate for automation.)

**Pass C — Flow health:**
- How long did cards sit in In Review? (Long = architect is the
  bottleneck; short = good.)
- How long did cards sit in Ready? (Long = over-decomposed; short = good.)
- Stale claims this week? (Any = a process problem.)

### Step 4 — Render

```
═══════════════════════════════════════════════════════════════
 RETROSPECTIVE — <window> — <N> PRs merged, <M> cards closed
═══════════════════════════════════════════════════════════════

📊 FLOW
──────────
 Cards to Done:         <N>
 Avg time Ready→Done:   <X days>   (last period: <Y>)
 Avg time In Review:    <X hours>  (last period: <Y>)
 Stale claims:          <count>

🧩 DECOMPOSITION
──────────────────
 Cards re-split mid-flight: <N> / <total>  (<pct>%)
 Cards under-sized:         <N>  (PR was bigger than card Size)
 Cards over-sized:          <N>  (PR was smaller — card could split)

 Patterns:
   • <e.g., "All 3 auth cards under-sized — consider splitting auth work
      by 'happy path' vs 'error surfaces' next time.">
   • ...

🔬 VERIFICATION
─────────────────
 PRs with 0 human-TODOs:    <N>  (fast-lane healthy)
 PRs with > 3 human-TODOs:  <N>  (test-coverage gap candidates)

 Frequently re-verified areas (candidate for automation):
   • <path>  — <count> PRs all needed similar manual step

🚧 STUCK
──────────
 Blocked > 3 days:
   • #<N>  <title>   reason: <summary>

═══════════════════════════════════════════════════════════════
```

### Step 5 — Offer follow-up actions

After the report, offer concrete actions the architect can take:

1. If decomposition patterns emerged:
   > "Want me to add a project-local note to `CLAUDE.md` capturing the
   > 'auth cards split by path vs errors' rule? Future Manager sessions
   > will consult it during decomposition."

2. If verification patterns emerged:
   > "The <area> PRs all needed the same manual step. Want me to create
   > a card for automating it?"
   (Creating the card goes through Intake Routine — don't skip.)

3. If stale claims happened:
   > "<N> stale claims this week. Want me to audit why they stalled?
   > Usually it's either 'kick-off prompt didn't have enough context'
   > or 'Consumer hit a blocker it couldn't self-rescue from'."

### Step 6 — Log the retro

Append the report to `.board-superpowers/retros/<YYYY-MM-DD>.md` so
future retros have a baseline. Commit it.

## Anti-patterns

- ❌ Don't run retro without signal. If <5 PRs merged in the window,
  say: "Window too short for a useful retro — wait another week or
  widen the window."
- ❌ Don't turn retro into post-mortem for a single incident. If the
  architect wants to dig into one bad card, that's triage, not retro.
- ❌ Don't moralize ("you should have split that card"). Report the
  pattern; let the architect decide what to do.
- ❌ Don't auto-update heuristics without architect consent. Every
  CLAUDE.md edit gets explicit approval.
