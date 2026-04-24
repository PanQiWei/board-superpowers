# board-superpowers

> A scheduling layer for Claude Code. Turns your GitHub Project into
> the dispatcher. Turns one Claude Code session into one deliverable
> milestone — one PR, end-to-end. Built on top of `superpowers` and
> `gstack`.

## Why this exists

Claude Opus 4.7 is good enough that you can stop babysitting individual
Claude Code sessions. The bottleneck has moved up a layer: **your
attention is now the scarce resource**, not the model's coding
competence.

board-superpowers is built around that inversion. It splits the
architect's attention into two clean streams:

- **Design attention** — into one Board Manager session and into
  external design skills (`superpowers:brainstorming`,
  `gstack:/office-hours`, `gstack:/plan-eng-review`).
- **Verification attention** — into a review queue of PRs, each with
  an explicit "Human Verification TODO" the author couldn't automate.

Everything else — implementation, TDD, code review, PR creation — runs
in parallel Board Consumer sessions. Each one follows a single
contract: **one session = one card = one PR**.

### What changes for you

| Before | After |
|--------|-------|
| One terminal, babysit one session, rebase constantly | N terminals, each a dedicated Consumer you mostly don't read |
| "What should I work on" is in your head | A Manager session reads the board and tells you |
| Sprint planning is a lossy conversation | Decomposition is a skill that enforces INVEST and vertical slicing |
| Scope creep caught mid-PR | Scope frozen into the card before a Consumer claims it |
| Merges are surprises | Every PR has a `## Human Verification TODO` section tailored for you |

## The two roles

Every Claude Code session using this plugin plays one of two roles.
Routing happens automatically via the first user message.

### 🧭 Board Manager

One session runs alongside you, never writes code. Five routines:

- **Daily** — what PRs need you, what's in flight, what's ready to
  dispatch.
- **Intake** — route new requirements through design skills, then
  decomposition.
- **Review Queue** — batch PRs by verification surface, flag protocol
  violations.
- **Triage** — stuck cards, oversized cards, stale claims.
- **Retro** — weekly signal aggregation from PR retro notes; feeds
  decomposition heuristics.

### 🔧 Board Consumer

Spawned per card. Claims atomically via git branch push. Delegates
actual implementation to `superpowers:subagent-driven-development` or
`gstack:/review+/qa`. Delivers a PR with three protocol-required
sections:

- `## Automated Verification` — what ran, what passed.
- `## Human Verification TODO` — end-to-end steps you can't automate.
- `## Retro Notes` — estimate vs actual, surprises, suggested
  re-decomposition.

## Installation

**Note:** board-superpowers is a scheduling layer that **composes**
`superpowers` and `gstack`. Install both first — the plugin will refuse
to run if either is missing, and this is intentional.

Platform: **Claude Code only.** Skills use `${CLAUDE_PLUGIN_ROOT}` and
invoke `superpowers:*` / `gstack:/*` skills directly; other harnesses
are not currently supported.

### 1. Install the prerequisites

**superpowers** — TDD, subagent-driven development, code review:

```bash
/plugin install superpowers@claude-plugins-official
```

**gstack** — design, QA, visual review:

```bash
cd ~/.claude/skills \
  && git clone https://github.com/garrytan/gstack \
  && cd gstack && ./setup
```

Confirm both load:

```bash
/plugin list        # superpowers should appear
/browse --help      # gstack should respond
```

### 2. Install board-superpowers

Clone into your Claude Code plugins directory:

```bash
git clone https://github.com/PanQiWei/board-superpowers \
  ~/.claude/plugins/board-superpowers
```

Then register it as a local plugin in a Claude Code session:

```
/plugin add local ~/.claude/plugins/board-superpowers
```

> board-superpowers is not yet published to a plugin marketplace. Once
> it is, `/plugin install board-superpowers@<marketplace>` will become
> the one-liner path. Until then, the clone above is canonical.

### 3. Verify

Open a Claude Code session in any repo and say:

> set up board-superpowers

The `using-board-superpowers` skill should fire, run the preflight
dependency check, and either walk you through first-time project
bootstrap (next section) or tell you the repo is already routed.

If you see the **missing dependency** banner instead, revisit step 1.
The banner is the plugin's loudest contract — treat it as blocking.

### Updating

```bash
cd ~/.claude/plugins/board-superpowers && git pull
```

Then restart Claude Code so the plugin reloads.

## First-time project setup

Per repo where you want to use board-superpowers:

1. **Create a GitHub Project v2.** Add a `Status` single-select field
   with these options, in this order:
   `Backlog → Ready → In Progress → In Review → Done → Blocked`.
   (Project v2 single-select option creation via API is unreliable
   with standard tokens — you do this in the UI once.)
2. **Open Claude Code in the repo and say** "set up board-superpowers".
3. The `using-board-superpowers` skill will:
   - Verify `superpowers` and `gstack` are installed.
   - Ask for the `OWNER/NUMBER` of the project you just created.
   - Run `scripts/bootstrap-project.sh`:
     - Creates standard labels (`type:*`, `size:*`).
     - Validates the project has all 6 required Status options.
     - Writes `.board-superpowers/config.yml` (project + WIP limit).
     - Adds `.board-superpowers/claims/` to `.gitignore`.
   - Inject a routing block into `CLAUDE.md` so future sessions
     auto-route to Manager or Consumer based on context.
4. **Commit the scaffolding** as two commits:
   ```
   chore: bootstrap board-superpowers
   chore: add board-superpowers routing to CLAUDE.md
   ```

You're done. Any future session in this repo routes itself.

## Quick start — a typical day

```
┌─────────────────────────────────┐
│  Morning                        │
│  ───────                        │
│  Open Manager session:          │
│    "what should I work on?"     │
│                                 │
│  Manager shows you the board:   │
│    2 PRs need your verification │
│    3 cards in flight            │
│    5 Ready to dispatch          │
│                                 │
│  You verify 2 PRs and merge.    │
│  Dispatch 3 new cards.          │
│                                 │
│  Open 3 Consumer terminals.     │
│  Paste the 3 kick-off prompts.  │
│  Walk away.                     │
├─────────────────────────────────┤
│  Midday                         │
│  ──────                         │
│  Consumers finish, open PRs.    │
│                                 │
│  Manager: "what needs me?"      │
│    → 3 PRs, grouped and sorted. │
│                                 │
│  You verify, merge, dispatch    │
│  the next wave.                 │
├─────────────────────────────────┤
│  Friday                         │
│  ──────                         │
│  Manager: "weekly retro."       │
│    → Flow metrics, size         │
│      calibration, patterns.     │
│                                 │
│  You adjust CLAUDE.md rules     │
│  based on the patterns.         │
└─────────────────────────────────┘
```

### Three phrases the Manager understands

| You say | Manager does |
|---------|-------------|
| "what should I work on?" | Daily routine — board snapshot + recommendation |
| "I have a new requirement: `<desc>`" | Intake — routes you to design, then decomposition |
| "weekly retro" | Retro — aggregates last 7 days of PR notes into a report |

### Dispatching a Consumer

When Manager hands you a kick-off prompt like:

```
[board-card:#42] Work on card #42 in project acme/3.

Start by invoking `consuming-card` skill. It will handle the full
lifecycle: claim (atomic) → implement → PR → update board.

Context the architect added on top of the card body:
None — card body is complete.
```

Open a fresh terminal in the project directory, paste it, walk away.
The Consumer reports back only when the PR is up (or when it hit a
real blocker).

Each Consumer session isolates itself in a dedicated git worktree
that `claim-card.sh` creates — by default at
`~/.config/superpowers/worktrees/<project>/claim/<N>-<slug>`. That
is why N Consumer terminals in parallel do not trample each other's
HEAD. You open the terminal at the primary repo; the Consumer
`cd`s into its worktree during Step 2 and never comes back.

### Pulling a card yourself (without the Manager)

If you don't want to bounce through the Manager for a single card
pull, open a fresh session in the project and say:

> pull a card from the board

The `consuming-card` skill's Step 0 will query Ready cards, show
you 3 candidates, and wait for you to pick one before claiming.

## Opinions this plugin has

- **INVEST** for every card (Independent, Negotiable, Valuable,
  Estimable, Small, Testable).
- **Vertical slices** over layer splits. Always.
- **Pull-based work** — Consumers claim; Managers don't assign.
- **One PR per session** — no multi-card sessions.
- **Lightweight retro** — aggregated from PR notes, not a separate
  ceremony.
- **Soft WIP limit** (default 5) — warn but don't block.
- **Human verification is a first-class output** of every PR, not an
  afterthought.

## What this plugin does NOT do

- Run your CI. Your CI stays your CI.
- Estimate in story points. Cards are XS/S/M/L — no numbers. If a card
  doesn't fit one PR, split it.
- Track velocity as a KPI. Retro surfaces flow signals, not
  performance metrics.
- Manage releases, branch protection, or merge policies. Your project
  setup continues unchanged.
- Replace `superpowers` or `gstack`. It composes them; it does not
  shadow them.

## Structure

```
board-superpowers/
├── .claude-plugin/plugin.json
├── hooks/
│   ├── hooks.json
│   └── session-start.sh            # Dep-alert layer 1
├── scripts/
│   ├── check-deps.sh               # Shared by hook + skills
│   ├── bootstrap-project.sh        # One-time per-repo setup
│   ├── claim-card.sh               # Atomic git-push claim
│   ├── create-card.sh              # Standardized card creation
│   └── transition-card.sh          # Project v2 status transition
└── skills/
    ├── using-board-superpowers/    # Meta: routing + preflight (layer 2)
    ├── board-protocol/             # Shared contract: schema + state machine
    ├── managing-board/             # Manager main skill + routine references
    ├── decomposing-into-milestones/# Manager's INVEST + slicing engine
    └── consuming-card/             # Consumer main skill + PR template
```

## License

MIT.
