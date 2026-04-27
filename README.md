# board-superpowers

> **An enforcement layer that makes parallel AI execution behave like a real team instead of chaos.**
>
> Built as a plugin for **Claude Code** and **OpenAI Codex CLI**.
> Composes [`superpowers`](https://github.com/anthropics/claude-plugins-official) (TDD, code review, debugging) and [`gstack`](https://github.com/garrytan/gstack) (design, QA, security) — does not replace them.

**English** · [简体中文](./README.zh-CN.md)

---

## Why this exists

The AI-era architect's primary value is **no longer writing code**. It is sequencing problems, designing architecture, judging tradeoffs, and verifying that what the AI built actually works. Coding itself is becoming AI's job.

board-superpowers operationalizes that role-shift. Concretely:

- You run **N parallel Consumer sessions** against **one Manager session**.
- You walk away.
- You come back to a **merge-ready queue of PRs**, each carrying an explicit `## Human Verification TODO` checklist.
- **Verifying that checklist is your remaining job** — and the plugin's whole shape is designed to maximize how far that scarce attention can go.

If you have personally decided to focus on judgment and architecture rather than line-by-line authorship, and you are willing to dispatch implementation to AI without babysitting it — this plugin is for you.

## What changes for you

| Without board-superpowers | With board-superpowers |
|---|---|
| One terminal, babysit one session, rebase constantly | N terminals, each a dedicated Consumer you mostly do not read |
| "What should I work on?" lives in your head | A Manager session reads the board and tells you |
| Sprint planning is a lossy conversation | Decomposition is a skill that enforces INVEST and vertical slicing |
| Scope creep caught mid-PR | Scope is frozen into the card body before any Consumer claims it |
| Merges are surprises | Every PR ships with a structured `## Human Verification TODO` |
| Your coordination state is in your head | Your coordination state is your **own** GitHub Project — we never own it |

## The three pillars

board-superpowers sits at the intersection of three commitments. Most adjacent tools cover one or two; covering all three is the differentiation.

### 1. Substrate commitment — your board, never ours

Truth lives on **your existing board** (GitHub Project today; Linear, Jira, others via the `BoardAdapter` contract tomorrow). We never own a hosted control plane, never run a backend, never ask you to log into our service.

If a feature ever requires durable state that lives anywhere except your board + your git remote, we have broken the commitment. This is structural, not aspirational — it is what makes us the open-source choice next to Devin / Factory / similar hosted products that *must* own their state for business reasons.

### 2. Methodology embedded as code

The agile discipline is **enforced by the plugin**, not configured by you:

- **INVEST** every card. Independent, Negotiable, Valuable, Estimable, Small, Testable.
- **Vertical slices** over layer-splits. Always.
- **Pull-based work**: Consumers claim atomically; Managers do not assign.
- **One PR per session**. No multi-card sessions.
- **Lightweight retro** — aggregated from PR notes, not a separate ceremony.
- **Soft WIP limit** (default 5) — warn, do not block.
- **Cards are XS / S / M / L** — never story points, never velocity, never per-architect KPIs.

Anything that smells like sprint-cadence-cosplay (story-point estimation, velocity tracking, retro-as-meeting) is deliberately absent. AI orchestration inverts which resources are scarce, and most ceremonies that human teams need are noise here.

### 3. Composition is permanent

board-superpowers **never reimplements TDD, QA, code review, brainstorming, or security audit**. Those belong to `superpowers` and `gstack`. board-superpowers is the **scheduling layer** that composes them into routines:

- Manager's intake routine routes through `gstack:/office-hours` and `superpowers:brainstorming`.
- Consumer's implementation routine delegates to `superpowers:subagent-driven-development`.
- Consumer's pre-PR verification chain calls `superpowers:verification-before-completion` → `superpowers:requesting-code-review` → `gstack:/review` → `gstack:/codex` (cross-platform adversarial review) → `gstack:/qa` (UI cards) → `gstack:/cso` (security-flagged cards).

If a similar discipline already exists in those upstream plugins, we use it. If we ever ship a duplicate, that is a bug.

## The two roles

Every session plays exactly one role with respect to the kanban. Routing happens automatically based on your first message.

### Producer — keep-the-board-healthy session

> Today's only Producer-class role: **Manager**.

A Manager session is **long-lived, aggregate-view, never writes code**. It exposes 15 capabilities across five clusters:

- **Read primitives** — atomic kanban query, pending-PR queue with priority ordering, blocked-session inspection, today's dispatch recommendation, board-health snapshot, context briefing on switch-back.
- **Action features** — overnight batch dispatch ("the human rests; the agents do not"), interactive intake & design routing, decomposition into INVEST-compliant cards, triage with a 5-step remediation ladder.
- **Cadence features** — lazy stale-session detection, event-driven retro routine (no sprint cadence), weekly aggregated report.
- **Project-level conversations** — quality-harness setup conversation (your project's golden principles encoded as lint + structural tests + auto-PR), kanban hygiene & maintenance.

### Consumer — one-card-to-done session

> Today's only Consumer-class role: **Implementer**.

A Consumer session **claims one Ready card atomically**, fetches its spec, delegates implementation through skills, runs adversarial self-review, opens a PR, handles the review cycle, terminates cleanly.

Two operational modes:

- **Mode-1** (architect-spawned): you paste a kick-off prompt into a fresh terminal — works on Claude Code AND Codex CLI.
- **Mode-2** (Producer-spawned): the Manager spawns a Consumer as a subagent — Claude Code only at v1.

Each Consumer runs in its own git worktree. N parallel Consumers therefore never share HEAD.

## Quick start

### Prerequisites

board-superpowers refuses to run if these are missing — by design:

```bash
# superpowers — TDD, subagent-driven development, code review
/plugin install superpowers@claude-plugins-official

# gstack — design, QA, visual review, security
cd ~/.claude/skills && git clone https://github.com/garrytan/gstack && cd gstack && ./setup
```

You will also need: `gh` CLI (logged in, with `project` scope), `git`, `python3`.

### Install board-superpowers

```bash
git clone https://github.com/PanQiWei/board-superpowers ~/.claude/plugins/board-superpowers
```

#### Claude Code

```
/plugin add local ~/.claude/plugins/board-superpowers
```

CC auto-discovers the plugin's `hooks/hooks.json` at install time — no extra step needed.

#### Codex CLI

Codex CLI doesn't auto-discover plugin-bundled hooks (the plugin manifest spec has no `hooks` field). Register the SessionStart hook once after install:

```bash
# Inspect the registration snippet first (recommended):
bash ~/.claude/plugins/board-superpowers/scripts/register-codex-hooks.sh

# Then auto-merge into your user-scope ~/.codex/hooks.json:
bash ~/.claude/plugins/board-superpowers/scripts/register-codex-hooks.sh --install-user

# OR per-repo (writes ./.codex/hooks.json; requires repo trust):
bash ~/.claude/plugins/board-superpowers/scripts/register-codex-hooks.sh --install-repo
```

The script is idempotent — re-running replaces the existing entry rather than duplicating. It backs up your `hooks.json` before overwriting. Uninstall via `--uninstall-user`.

### One-time per-repo bootstrap

For each repo where you want board-superpowers active. Currently manual — an auto-bootstrap skill is planned for a future version.

1. **In GitHub UI**, create a Project v2 with a `Status` single-select field whose options are exactly, in this order: `Backlog → Ready → In Progress → Blocked → In Review → Done`.
2. **Add the standard labels** by running:
   ```bash
   bash ~/.claude/plugins/board-superpowers/scripts/setup-labels.sh
   ```
   This creates `wip-override`, `suspended`, `security`, `pr-contract-override` (idempotent — skips already-existing labels).
3. **Create `.board-superpowers/config.yml`** in the repo root and commit it:
   ```yaml
   project: <owner>/<number>      # e.g., PanQiWei/4
   ```
   Then create `.board-superpowers/config.local.yml` (gitignored, per-user):
   ```yaml
   wip_limit: 5                   # personal capacity; soft cap, default 5
   ```
4. **Verify** by running:
   ```bash
   bash ~/.claude/plugins/board-superpowers/scripts/check-deps.sh
   bash ~/.claude/plugins/board-superpowers/scripts/read-board.sh \
     --owner <owner> --project <number> --status Ready
   ```
   Both should exit 0; the second prints the JSON list of Ready cards (empty `[]` is fine).
5. **Optional — add a routing block** to your `CLAUDE.md` and `AGENTS.md` so the agent knows to invoke this plugin's skills explicitly. The entry skill (`using-board-superpowers`) will trigger on common phrases without it, but the explicit routing improves reliability. See `~/.claude/plugins/board-superpowers/AGENTS.md` § "board-superpowers session routing" for a copy-pasteable block.

That is it. After step 5 (or step 4 if you skip the routing block), open a fresh CC session in your repo and type "what should I work on" to confirm the entry skill triggers.

## A typical day

```
┌─────────────────────────────────────────────────────────────┐
│  MORNING                                                    │
│  Open a Manager session: "what should I work on?"           │
│                                                             │
│  Manager preflights and reports:                            │
│    - 2 PRs need your verification                           │
│    - 3 cards in flight                                      │
│    - 5 cards Ready to dispatch                              │
│                                                             │
│  You verify the 2 PRs and merge.                            │
│  You ask Manager for today's dispatch recommendation.       │
│  You open 3 fresh Consumer terminals, paste the kick-offs,  │
│  walk away.                                                 │
├─────────────────────────────────────────────────────────────┤
│  MIDDAY                                                     │
│  Consumers finish, open PRs.                                │
│                                                             │
│  Manager: "what needs me?"                                  │
│    -> 3 PRs grouped by verification surface, sorted         │
│                                                             │
│  You verify, merge, dispatch the next wave.                 │
├─────────────────────────────────────────────────────────────┤
│  END OF DAY                                                 │
│  Manager: "I'm leaving — kick off X, Y, Z overnight"        │
│    -> Producer dispatches Consumer sessions one by one,     │
│       under controlled concurrency, while you sleep.        │
│       The human rests; the agents do not.                   │
├─────────────────────────────────────────────────────────────┤
│  WEEKLY                                                     │
│  Manager: "weekly retro"                                    │
│    -> Aggregates last 7 days of PR retro notes into         │
│       flow signals, decomposition drift, and proposed       │
│       CLAUDE.md amendments (you approve before they land).  │
└─────────────────────────────────────────────────────────────┘
```

### Three phrases the Manager understands out of the box

| You say | Manager does |
|---|---|
| `what should I work on?` / `morning briefing` | Daily routine — board snapshot + dispatch recommendation |
| `I have a new requirement: <X>` | Intake — routes you through design skills, then decomposition |
| `weekly retro` | Retro — aggregates last 7 days of PR notes into a structured report |

Plus eight more documented in the spec — see `docs/architecture/0002-product-features-and-flows/03-producer-surface.md`.

### Dispatching a Consumer

When the Manager hands you a kick-off prompt like:

```
[board-card:#42] Work on card #42 in project acme/3.

Start by invoking `consuming-card` skill. It will handle the full
lifecycle: claim (atomic) -> implement -> PR -> update board.

Context the architect added on top of the card body:
None — card body is complete.
```

Open a fresh terminal in the project directory, paste it, and walk away. The Consumer reports back only when its PR is open (or when it hits a real blocker that needs you).

## The PR contract

Every Consumer PR ships with three structured sections:

- **`## Automated Verification`** (required) — what tests / lints / cross-platform reviews / security passes ran, and what passed. The audit trail of the verification chain.
- **`## Human Verification TODO`** (optional for low-risk cards; required when end-to-end human checks are needed) — the steps the AI could not automate. **This is your remaining job.** Source: Producer's plan + Consumer's implementation-time additions.
- **`## Retro Notes`** (required when reusable lessons exist) — knowledge harvesting for future cards. **Not** estimate-vs-actual, **not** velocity, **not** KPI metrics.

If a PR is missing one of these (when required), Manager's Review Queue routine flags the violation inline. The structure is protocol; the *content* is project-specific and never preset.

## What we explicitly do NOT do

These are commitments to *not* do things. Future feature requests of the shape "should we add X?" should test against this list.

- **No backend, database, or web UI.** Truth lives on your board.
- **No reimplementation of upstream disciplines.** TDD belongs to `superpowers`; QA / review / brainstorming / security belong to `gstack`.
- **No CI replacement.** Tests run wherever your CI runs.
- **No story points / velocity / per-architect performance metrics.** Cards are XS / S / M / L. Retro surfaces flow signals, not KPIs.
- **No agent self-merging PRs.** Humans merge. Agents propose.
- **No hosted install service / account creation / install wizard.** Distribution is `git clone` + `/plugin add local` today, marketplace one-liner tomorrow. Never a hosted layer.
- **No methodology-extension marketplace.** Third-party "discipline plugins" extending routines are permanently out — versioning debt and chicken-and-egg costs do not fit the project framing.
- **No cross-team / fleet view at v1.** That is the explicit 10x (see Vision below), not v1.

## Two design principles you should know about

### Meta-methodology, not opinionated configuration

board-superpowers ships **mechanisms**: the conversational scaffolds and maintenance routines you use to *establish and evolve* your own practice. It deliberately ships **no project-specific defaults**:

- No default lint rules. Manager helps you bootstrap your own.
- No default PR-section content. The 3-section *structure* is protocol; the *content* is yours.
- No fixed WIP number. A starting default exists; Manager assists you tuning it from observed flow metrics.
- No default retro template. Retro aggregates *your* signals, not ours.

If we ever shipped a default whose content prejudges what your project should look like, that principle is broken.

### Default + override + accountability

Every governance dimension follows one shape: a sane **default** executes automatically; **overrides** are allowed but cost explicit friction (a config edit, a written justification, an architect prompt); every override leaves an **accountable trace** (audit-log row, PR description, card thread comment).

The Producer's autonomy matrix has 14 rows mapping every action to one of: **A** (auto, audit-logged), **R** (propose-then-await-approval), or **N** (permanently rejected). You can always see what the AI did, why, and whether you approved.

## Vision

Two amplifiers of the v1 thesis. Both are explicitly post-v1; both are first-class on the roadmap.

### Self-improving methodology (per project)

Retro signals auto-tune your project's CLAUDE.md decomposition rules. Year 2 of using board-superpowers on a project, the agent knows your repo's idioms — which subsystems get under-sized, which areas need a11y verification on every PR, which dependencies always surprise — better than a new hire would in 6 months. The methodology stays the same; the parameters tune themselves.

### Cross-team standard

Multi-architect, multi-board, fleet view. The methodology becomes the lingua franca for AI-era engineering teams the way Scrum was for the prior era — but enforced by code, not by ceremony. The `BoardAdapter` contract is what makes this reachable for non-GitHub teams.

### Explicitly rejected

Open methodology marketplace (third-party "discipline plugins"). The versioning debt of a stable plugin contract is heavy; chicken-and-egg ecosystem risk is real; it does not fit the project framing.

## Status

v1 design is being finalized. Implementation is dogfooded against the plugin's own GitHub Project — every non-trivial change passes through a Manager-Consumer flow.

- Architecture spec: `docs/architecture/` (read `0001-positioning.md` first)
- Product features and flows: `docs/architecture/0002-product-features-and-flows/`
- Domain model: `docs/architecture/0003-domain-model/`
- Component architecture: `docs/architecture/0004-component-architecture.md`
- Cross-component contracts: `docs/architecture/0005-contracts/`
- Decision records: `docs/architecture/adr/`

## Updating

```bash
cd ~/.claude/plugins/board-superpowers && git pull
```

Then restart Claude Code so the plugin reloads.

## License

MIT.
