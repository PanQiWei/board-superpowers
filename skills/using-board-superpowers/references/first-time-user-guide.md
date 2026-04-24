# First-time user guide (post-bootstrap)

When Step 3 of `using-board-superpowers` injects the routing block,
it is by definition the architect's first time with the plugin in
this repo (`check-deps.sh` sets `ROUTING_INJECTED=no` only in that
case). Deliver this onboarding immediately after the two bootstrap
commits land.

Substitutions while delivering:

- `{PROJECT}` — the `OWNER/NUMBER` the architect supplied to
  `bootstrap-project.sh`.
- `{WIP}` — the WIP limit written to `.board-superpowers/config.yml`
  (default 5).

## Delivery shape

This is a conversation, not a wall of text. Open with one sentence,
then walk through the six sections below. Pause between sections to
let the architect ask or object. Do not paste the README; do not
inline the individual routine references (`daily-routine.md` etc.) —
those are for Manager / Consumer use, not architect onboarding.

Opening line:

> "Bootstrapping done for {PROJECT}. Before you close this session,
> here's the shape of how you'll work in this repo from now on —
> six short sections, ask at any point."

### Section 1 — What just happened

- GitHub Project `{PROJECT}` is now bound to this repo.
- Standard labels created: `type:{feature,bug,chore,refactor,epic}`
  and `size:{XS,S,M,L}`.
- `.board-superpowers/config.yml` written (committed).
  `.board-superpowers/claims/` gitignored (per-session scratch, but
  individual claim markers *are* force-committed onto their claim
  branches — that's how the claim is proven on origin).
- Routing block injected into `CLAUDE.md` — every future Claude Code
  session in this repo auto-picks Manager or Consumer based on the
  first user message.

### Section 2 — The mental model

**One session = one card = one PR.** Two roles, only ever one per
session:

| Role | What it does | How to invoke |
|------|--------------|---------------|
| 🧭 Board Manager | Reads the board, plans, dispatches. Never writes code, never merges. | "what should I work on?", "review the board", "I have a new requirement: …", "weekly retro" |
| 🔧 Board Consumer | Claims one card atomically, implements it in an isolated git worktree, opens one PR. | "work on card #N" or "pull a card from the board" |

A Manager session typically stays open alongside you for a full day.
Consumer sessions are per-card and disposable — open a fresh
terminal, paste the kick-off prompt, walk away.

### Section 3 — A day in this loop

Describe this rhythm, do not table it:

- **Morning.** Open Manager → "what should I work on?" → Manager
  shows PRs that need your verification, cards in flight, cards
  Ready to dispatch. Verify and merge pending PRs first (a waiting
  PR = a Consumer's idle work). Then dispatch up to WIP-budget cards.
- **Midday.** Consumer sessions finish and open PRs. Ask Manager
  "what PRs need me?" — it groups them by verification surface (UI
  batch, same-area batch, zero-TODO fast lane) so you verify in
  batches, not context-switching per PR.
- **Friday.** "weekly retro" → flow metrics + a decomposition-signal
  digest from PR Retro Notes.

### Section 4 — Three Manager phrases to memorize

| You say | Manager runs | What it produces |
|---------|--------------|------------------|
| "what should I work on?" | Daily routine | Fixed-template board snapshot + one recommendation |
| "I have a new requirement: `<desc>`" | Intake routine | Routes you to design (`superpowers:brainstorming` or `gstack:/office-hours`), then to decomposition → Backlog cards |
| "what PRs need me?" | Review Queue | PRs grouped for batching, protocol violations flagged |

Also useful: "card #N is blocked / too big" (triage), "promote card
#N to Ready" (move from Backlog).

### Section 5 — The PR contract

Every Consumer PR is required to have three sections. Knowing them
up front means you know what to expect when you open one:

- `## Automated Verification` — what ran, what passed.
- `## Human Verification TODO` — checkboxes the Consumer could not
  automate. This is **your job** before merge.
- `## Retro Notes` — estimate vs actual, surprises, suggested
  re-decomposition. This feeds the weekly retro.

If a PR is missing one of those, Manager flags it as a protocol
violation during Review Queue — you reply to the Consumer ("please
add Retro Notes per board-protocol, then re-request review").

### Section 6 — Rules of the road

- **WIP soft limit: {WIP}.** Manager warns at or over; never blocks.
  Raise deliberately.
- **Card flow:** Backlog → Ready → In Progress → In Review → Done.
  `Blocked` is a side state. Manager does NOT promote Backlog → Ready
  on its own; you do ("promote card #N to Ready").
- **Humans merge PRs.** Agents do not self-merge, even their own.
- **Pull-based.** Consumers claim cards; Manager never assigns. Even
  the kick-off prompts Manager hands you are suggestions — you pick
  which to paste into a terminal.
- **Parallel Consumers are isolated.** Each claim creates its own
  git worktree (default under
  `~/.config/superpowers/worktrees/<project>/<branch>`). N Consumer
  terminals do not trample each other's HEAD.
- **Design comes before cards.** Requirements go through Intake →
  design → decomposition. Cards never land on the board as "figure
  it out in impl".

## After delivery — offer two next steps

Pick one based on whether the architect already has something to
build:

1. **Real intake.** If they have a feature in mind:
   > "Want to try this end-to-end? Open a fresh terminal in this
   > repo and say 'I have a new requirement: <your feature>'. The
   > Manager will walk you through design → decomposition and land
   > the cards in Backlog."

2. **Dry-run Manager.** If nothing specific yet:
   > "Or say 'what should I work on today?' in this same session.
   > With an empty board you'll see the empty-state output — worth
   > seeing once so the real one isn't a surprise."

Then stop. Do not auto-create a card. Do not auto-open a Consumer
session.

## Hard do-nots during delivery

- Do not paste `README.md` into chat — it's docs for someone reading
  the plugin cold; the architect just finished bootstrap and is
  already oriented.
- Do not embed the routine references (`daily-routine.md`,
  `intake-routine.md`, etc.) — those are procedure for Manager to
  execute, not material for the architect to memorize.
- Do not inline `board-protocol` — Manager and Consumer skills load
  it themselves at preflight.
- Do not auto-create an example card to "demo" the flow. The first
  real card is the architect's call.
