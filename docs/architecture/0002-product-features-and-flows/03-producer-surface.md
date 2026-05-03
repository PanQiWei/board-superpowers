### 1.3 Producer surface

The capabilities a Producer-role session exposes. Producer is
the kanban-relative role from §1.2 — its purpose is to keep
the kanban populated and well-shaped. Concrete Producer
sessions take on **specific roles** that bundle related
capabilities. v1 ships one such specific role — **Manager** —
whose 15 features are documented in §1.3.1. Future Producer
specific roles (e.g., a dedicated Triager split out of Manager,
a dedicated Lint runner) become sibling subsections under §1.3.

This section is a **catalog of Manager's capabilities
(features)** — the time-ordered combinations of these features
that an architect actually walks through are documented as
**flows in Part 2**, not here. Capability vs flow separation:
capability = "what Producer can do, time-independent"; flow =
"how the architect uses these capabilities in order, over
time." See §2.4 (Daily Manager flow) for the canonical morning-
ritual flow that composes F-01–F-06 into a single architect-
facing briefing.

**Cross-cutting principles applied throughout this section**
(every feature spec MUST honor):

- **D-AUTONOMY-1** (`adr/0006-producer-autonomy-boundary.md`):
  every feature's `Autonomy` field maps its sub-actions to
  matrix rows 1–14. A = auto with audit log; R = propose-then-
  await-approval; N = permanently rejected (none at v1).
- **C-PLUGIN-1 / -2 / -3**
  (`adr/0007-plugin-runtime-derived-constraints.md`): no
  in-memory cross-session IPC; no daemon thread; controlled
  Consumer-dispatch concurrency.
- **Preflight piggyback** (idiom defined in
  `adr/0007-plugin-runtime-derived-constraints.md`): all
  "automatic" / "monitor" / "detect" features piggyback their
  checks on the architect's next prompt — there is no realtime
  push.
- **D-META-1** (`0001-positioning.md` P7): capabilities
  provide mechanism, not project-specific configuration.
  Where a feature could ship a default rule (lint config,
  retro template, WIP number), it instead ships the
  conversational scaffold for the architect to capture their
  own.

#### 1.3.1 Manager (specific role)

A **Manager** session is a Producer-role session whose specific
role is **board orchestration** — making sense of the board's
state, dispatching work to Consumer sessions, intaking new
requirements, triaging trouble, and aggregating learnings.

**Cardinality**: v1 has at most one active Manager session per
project at any time. Cardinality is enforced informally —
there is no software lock; the architect simply does not open
two Manager sessions simultaneously. Multiple architects
sharing one board is out of scope at v1 (per
`0001-positioning.md` P3).

**Session shape**: long-lived, aggregate view (one Manager
session covers all Threads + Milestones in the project),
architect-initiated commands (the architect prompts; Manager
preflights then responds). Per C-PLUGIN-2 there is no daemon
— Manager only acts in response to architect prompts.

**Trigger phrases** (route via the 4 Producer routine SKILL
descriptions matching — `briefing-daily` / `intaking-requirement`
/ `reviewing-pr-queue` / `triaging-board` — per
`PLUGIN_DEVELOPMENT.md`):

| Architect says | Manager activates (features) | Flow it composes (Part 2) |
|----------------|------------------------------|---------------------------|
| "what should I work on?" / "morning briefing" | F-01, F-02, F-03, F-04, F-05 | §2.4 Daily Manager flow |
| "I have a new requirement: <X>" / "I want to refactor <Y>" | F-08 → F-09 | §2.5 New requirement intake flow |
| "what needs me?" / "what PRs need me?" | F-02, F-03 | §2.4 sub-flow |
| "stuck cards" / "triage" | F-10 | §2.9 Triage flow |
| "retro" | F-12 | §2.8 Retro flow |
| "weekly report" | F-13 | §2.8 sub-flow |
| "I'm leaving, dispatch overnight" | F-04 → F-07 | §2.6 (overnight batch variant) |
| "what was I working on?" / "context for #N" | F-06 | §2.6 sub-flow |
| "let's set up our quality harness" | F-14 | (TBD harness setup flow) |
| "audit the board" / "kanban hygiene" | F-15 | §2.9 sub-flow |
| (other / generic board questions) | F-01 (default) | — |

The 15 features below are Manager's complete capability surface
at v1, grouped into 5 thematic clusters for readability.

##### Group A — Query primitive

###### F-01. Atomic kanban query primitive

> The lowest-level read primitive. Every other read-side feature
> composes this one; nothing in §1.3.1 calls `gh` directly.

- **Capability**: expose atomic kanban read — given a query
  (project + filters: status / label / milestone / thread /
  author / age range), return a structured snapshot. Wrapping
  GitHub's native query layer behind this primitive ensures a
  single point of board-API contact across all features.
- **Inputs**: project ref (`owner/repo#projectNumber`) +
  optional filters (status, label, milestone, thread, author,
  age range).
- **Outputs**: structured data — list of cards, each with
  status, labels, assignees, PR refs, timestamps.
- **Composes**: the Kanban Protocol's `read_board` action
  ([`0005-contracts/00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md)).
  v1 realizes this via the GitHub Project v2 projection —
  `gh project item-list` / `gh issue list` / `gh pr list`
  (direct GitHub API), wrapped per the v1
  GitHubProjectAdapter projection shape (ADR-0005, rescoped
  by ADR-0025 from "universal adapter contract" to "v1 GitHub
  projection's bash implementation shape").
- **Maps to (canonical)**: Anderson 2010 *Kanban*, ch. 4 — the
  minimal "visualize work" read surface.
- **Original framing**: wrapping GitHub's native query layer
  into a board-superpowers-internal atomic primitive (so
  feature specs don't proliferate ad-hoc query implementations)
  is an architectural-hygiene decision, not a user-facing
  capability per se.
- **Autonomy**: N/A (read-only; no state mutation).

##### Group B — Read-only dashboards

These features compose F-01 to produce architect-facing
dashboards. Each answers a specific awareness question; the
morning-ritual flow (§2.4) composes B-group features 02–05
(plus F-06 as needed) into a single briefing output.

###### F-02. Pending PR queue with ordering

- **Capability**: list every open Consumer PR awaiting
  architect review/merge, **ordered by priority** — not just
  grouped. Ordering signals: CI/harness status, claim age,
  Consumer-marked ready-vs-blocked, owning Thread priority.
  Contract violations (PR missing one of the §1.8 mandatory
  sections) are flagged inline.
- **Inputs**: project ref + optional filter (single Thread /
  single Milestone).
- **Outputs**: sorted list — `[(PR #, title, age, harness
  status, Human Verification TODO summary, recommended
  action)]`.
- **Composes**: F-01 + parsing of PR body's mandatory sections
  (§1.8: `## Automated Verification`, `## Human Verification
  TODO`, `## Retro Notes`).
- **Maps to (canonical)**: Reinertsen 2009 *Principles of
  Product Development Flow* — Cost-of-Delay-driven
  prioritization combined with Anderson's "limit work in
  progress" read surface.
- **Original framing**: the **ordering dimension** —
  traditional board tools group PRs (by assignee / status) but
  do not order them. board-superpowers makes ordering a first-
  class output because architect attention is the bottleneck
  (P1) and unordered queues force re-prioritization on every
  glance.
- **Autonomy**: N/A (read-only).

###### F-03. Blocked sessions inspection

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: identify all Consumer sessions in the
  `blocked-on-architect` state — distinguishing `running` (CC
  worker active, architect not needed) from
  `blocked-on-architect` (waiting for architect input or
  decision). The judgment combines card status, the latest
  comment (Consumer writing "needs decision X"), and the claim
  branch's last-commit timestamp.
- **Inputs**: project ref.
- **Outputs**: list — `[(card #, session-id, blocked since,
  what-decision-needed summary)]`.
- **Composes**: F-01 + (per C-PLUGIN-1 workaround b) reading
  the Consumer session via session-id from CC's
  `~/.claude/projects/<dir>/<session-id>.jsonl` or Codex's
  `codex exec resume [SESSION_ID]` to validate session state.
- **Maps to (canonical)**: Reinertsen 2009 — queue-management
  observability surface. No direct canonical-agile equivalent
  for the running-vs-blocked-on-architect distinction.
- **Original framing**: **two-state session classification
  (running vs blocked-on-architect)** is board-superpowers
  original — a concept arising from AI-orchestration where
  architect-attention contention is the dominant resource
  cost. Requires Consumer-side state externalization (§1.4)
  so Producer can read the state.
- **Autonomy**: N/A (read-only).

###### F-04. Today's dispatch recommendation

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: given current board state, WIP utilization,
  blocking situation, and Thread priority, **recommend** which
  Ready cards should be dispatched to Consumers today.
  Recommendation only — actual dispatch is F-07's job.
- **Inputs**: project ref + optional architect hints ("I have
  3 hours" / "focus on Thread X").
- **Outputs**: `[(card #, why-recommended, estimated effort,
  recommended Consumer concurrency)]` + a short narrative
  summary.
- **Composes**: F-01 + F-02 + F-05 (health check, to avoid
  over-dispatch) + (per C-PLUGIN-3) respect for current
  in-flight Consumer count and the WIP limit.
- **Maps to (canonical)**: Reinertsen 2009 (WIP control) +
  Cohn 2005 *Agile Estimating and Planning* (capacity-
  estimation surface). The "cohort to dispatch today" framing
  borrows planning's capacity vocabulary without importing
  sprint cadence.
- **Original framing**: the **recommend-vs-execute split** —
  decoupling "what should I dispatch" from "actually dispatch"
  is original. It lets the architect course-correct the
  recommendation before F-07 commits to spawning Consumer
  sessions.
- **Autonomy**: N/A for the recommendation itself; the
  downstream dispatch action lives in F-07 and is governed by
  ADR-0006 matrix row 13 (Dispatch Consumer = A).

###### F-05. Board health snapshot

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: emit kanban-flow health metrics — WIP
  utilization, blocked ratio, stale-card count, cycle-time
  trend, recent ship rate. **Distinct from DORA** (which
  targets deployment) — F-05's scope is board liquidity.
- **Inputs**: project ref + optional lookback window (default
  7 days).
- **Outputs**: `{wip_used: 4/5, blocked_ratio: 0.2,
  stale_count: 2, avg_cycle_time: 18h, ship_rate_7d: 12
  cards/week, health_grade: "yellow"}`.
- **Composes**: F-01 + an internal health-grade computation
  function. Initial threshold values (what makes the grade red
  vs yellow vs green) are intentionally TBD at v1 spec — see
  Notes.
- **Maps to (canonical)**: Anderson 2010, Cumulative Flow
  Diagram core metrics (subset); Forsgren / Humble / Kim 2018
  *Accelerate* — throughput / lead-time framing (but board-
  scoped, not deployment-scoped).
- **Original framing**: **the board-health-grade concept** —
  traditional PM tools surface metrics; they do not grade.
  board-superpowers internalizes the metrics → grade mapping
  so an architect glances once to decide whether to intervene.
- **Autonomy**: N/A (read-only). Initial grade thresholds left
  TBD; they get pinned via D-META-1 (architect captures their
  own thresholds) once a project has lived data.

###### F-06. Context briefing on switch-back

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: when the architect switches focus back to a
  specific card / Thread, Producer surfaces a **fast context
  reload** — what's happened recently, the current blocker (if
  any), the last decision the architect left here, the related
  cards' current state.
- **Inputs**: card # or Thread ref + (optional) last-architect-
  touch timestamp; defaults to inferring from session history.
- **Outputs**: `{since_last_touch: "...", recent_events: [...],
  current_blocker: "...", last_decision: "...", related_cards:
  [...]}`.
- **Composes**: F-01 + (per C-PLUGIN-1 workaround b) reading
  Consumer-session jsonl to extract events since last
  architect touch + PR comments + card body revision history.
- **Maps to (canonical)**: no direct canonical-agile
  equivalent. Closest precedent: Cockburn's "information
  radiator" (passive display) — but F-06 is active reload on
  demand. Engineering handoff documentation has the same
  spirit.
- **Original framing**: **multi-thread architect context-loss**
  is amplified in AI orchestration — traditional PM tools
  assume the architect tracks 1–2 threads at a time; board-
  superpowers must assume 5 parallel (per P3 + the user's own
  working profile). Context reload becomes a first-class
  feature, not a margin convenience.
- **Autonomy**: N/A (read-only).

##### Group C — Action features (write-side)

These features mutate state. Each maps explicitly to
D-AUTONOMY-1 matrix rows; the audit-log requirement (ADR-0006
§5) applies to every action below.

###### F-07. End-of-day overnight batch dispatch

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: end-of-day, the architect tells Producer "I'm
  leaving — kick off X, Y, Z to run overnight." Producer queues
  the cards and dispatches Consumer sessions one by one (under
  controlled concurrency, per C-PLUGIN-3) so most cards finish
  or land in PR state by morning. The economic point: convert
  architect's idle time into productive coding-agent runtime —
  "the human rests; the agents do not."
- **Inputs**: card list (explicit, or "everything F-04 just
  recommended") + concurrency parameter (default 1 serial) +
  optional time window ("stop by 8 a.m.").
- **Outputs**: (synchronous) queue confirmation + estimated
  completion-time prediction. (asynchronous) one audit-log
  entry per card completion; results aggregated into the next
  morning's preflight (§2.4).
- **Composes**: F-04 (input source) + Consumer F-C1 atomic
  claim (§1.4.1) + (per C-PLUGIN-3) controlled concurrency +
  (per ADR-0006 row 13) Dispatch Consumer = A.
- **Maps to (canonical)**: no direct canonical-agile
  equivalent (traditional PM tools do not schedule execution).
  Closest precedent: CI/CD pipeline batch-job runners — but
  card-scoped, not build-scoped.
- **Original framing**: **economic feature** — turning
  architect sleep time into productive runtime is board-
  superpowers' real differentiator from traditional PM tools.
  P1 says architect attention is the bottleneck; F-07 makes it
  asymmetric — when the architect is asleep, attention is
  zero, but board throughput stays positive.
- **Autonomy**: A (matrix row 13). Audit-log entries persist to
  the BYO RDBMS per ADR-0006 §5.

###### F-08. Interactive intake & design routing

- **Capability**: when the architect introduces a new
  requirement or refactor idea ("I want to refactor X" / "new
  idea Y"), Producer does not jump to decomposition. Instead
  it **routes through design skills** (`gstack:/office-hours`,
  `gstack:/plan-eng-review`, `superpowers:brainstorming`) for
  the conversation, then sinks the design output to F-09 for
  decomposition only when the design is settled.
- **Inputs**: raw requirement / refactor proposal / idea
  (architect's natural language).
- **Outputs**: (intermediate) design-skill conversation output.
  (final) design artifact (markdown / spec sketch) → triggers
  F-09.
- **Composes**: `gstack:/office-hours` /
  `gstack:/plan-eng-review` / `superpowers:brainstorming`
  (chosen dynamically by requirement type, per AGENTS.md
  routing rules) + F-09 downstream.
- **Maps to (canonical)**: Cohn 2009 — story-discovery half of
  Backlog Refinement (without importing sprint refinement
  cadence); *Scrum Guide* 2020 "Product Backlog Refinement"
  intake half.
- **Original framing**: the **design-skills routing layer** —
  Producer does not reinvent design conversation; it routes to
  existing gstack / superpowers skills. Direct application of
  P4b (composition is permanent) and P7 (D-META-1, mechanism
  not configuration).
- **Autonomy**: A for the routing decision (Producer chooses
  which skill to invoke). The downstream sink (F-09) carries
  its own autonomy mapping.

###### F-09. Decomposition into cards

- **Capability**: take an F-08 design artifact and decompose it
  into INVEST-compliant, vertically sliced Cards, written to
  the GitHub Project. Initial decomposition (creating new
  cards) is autonomous; later splitting of existing cards is
  escalated.
- **Inputs**: design artifact (markdown spec) + optional
  milestone ref + optional thread ref.
- **Outputs**: cards written to GitHub. Each card body
  satisfies the schema in
  `decomposing-into-milestones/references/card-schema.md`
  (acceptance criteria, decomposition rationale, size estimate
  XS / S / M / L).
- **Composes**: `superpowers:writing-plans` (turn spec sketch
  into executable plan) + `scripts/create-card.sh` (write to
  GitHub) + (per ADR-0006 rows 1 and 3) initial create=A,
  re-split of existing card=R.
- **Maps to (canonical)**: Cohn 2004 *User Stories Applied*
  (story splitting); Wake 2003 INVEST checklist
  (*<https://xp123.com/articles/invest-in-good-stories-and-smart-tasks/>*);
  Cohn SPIDR (*<https://www.mountaingoatsoftware.com/blog/five-simple-but-powerful-ways-to-split-user-stories>*).
- **Community supplement**: Lawrence's nine patterns and the
  hamburger-method pattern (Adzic) are widely cited but are
  NOT Mountain-Goat-Software canonical — treat as supplementary
  patterns, not primary; SPIDR is the canonical 5-set.
- **Original framing**: the **A-on-create / R-on-resplit
  asymmetry** — creating new cards is forward-incremental and
  safe; re-splitting existing cards is structural and warrants
  escalation. The asymmetry is captured in ADR-0006 matrix
  rows 1 and 3.
- **Autonomy**: A (matrix row 1) for first decomposition; R
  (matrix row 3) for re-splitting. Audit log mandatory for
  both.

###### F-10. Triage with remediation ladder

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: detect anomalous cards (stale / oversized /
  blocked too long / orphan claim) and apply a **fixed
  remediation ladder**: unblock (autonomous), split (escalate
  to F-09), reassign (cancel claim, escalate), kill (close,
  escalate), refine (adjust card body, autonomous).
- **Inputs**: anomaly source — F-11 (stale detection), F-05
  (health degradation), or architect manual ("triage").
- **Outputs**: per anomalous card, a chosen ladder action.
  A-class actions execute with audit log; R-class actions
  surface as proposals awaiting approval.
- **Composes**: F-01 + F-11 + F-05 + F-09 (for split) + (per
  ADR-0006) each ladder action references a different matrix
  row — unblock = A via row 5; split = R via row 3; reassign
  = R via row 8; kill = R via row 7; refine = A via row 2.
- **Maps to (canonical)**: Anderson 2010, ch. 9 — "swarm to
  unblock" pattern (closest); Cohn 2009 — refinement subset.
- **Original framing**: the **explicit 5-step ladder + per-step
  D-AUTONOMY-1 mapping** — traditional triage is ad-hoc
  judgment; board-superpowers structures it so each anomaly
  type has a known response.
- **Autonomy**: per-action — see Composes line above. Audit log
  mandatory.

##### Group D — Cadence / preflight features

These features are time-aware (cadence-driven) but, per
C-PLUGIN-2, are **never implemented as daemon polling**. All
run via the preflight piggyback idiom (ADR-0007).

###### F-11. Stale session detection (lazy)

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: in the preflight piggyback, detect stale
  Consumer sessions. The judgment uses GitHub-observable
  timestamps (last commit, last comment, last claim push) —
  **never** "I haven't heard a heartbeat." Heartbeat-style
  protocols are off the table per ADR-0007.
- **Inputs**: project ref + size-keyed thresholds (XS = 4h,
  S = 24h, M = 72h, L = 168h — initial values TBD; default
  starting point only, see Notes).
- **Outputs**: stale-card list → fed to F-10 triage.
- **Composes**: F-01 + the preflight piggyback idiom
  (ADR-0007) + size-label lookup for thresholds.
- **Maps to (canonical)**: Anderson 2010 (manage flow);
  Reinertsen 2009 (queue-aging awareness).
- **Original framing**: **lazy detection via preflight
  piggyback** — C-PLUGIN-2 forbids daemon polling, so board-
  superpowers' staleness is "the architect learns about it on
  the next prompt." This differs sharply from traditional PM
  tools that push notifications.
- **Autonomy**: N/A (detection is read-only; remediation
  handled by F-10).

###### F-12. Retro routine

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: periodic structured reflection — what
  worked, what didn't, what to change. **Event-driven
  trigger** (Milestone close, OR N-cards-completed threshold,
  OR detected decomposition drift), not calendar-driven.
  Output may include proposed CLAUDE.md / AGENTS.md amendments
  (escalated, per matrix row 4).
- **Inputs**: trigger event + lookback scope (a Milestone,
  last N cards, or a window).
- **Outputs**: retro report (markdown) + (optional) proposed
  changes to CLAUDE.md / AGENTS.md awaiting approval (R per
  matrix row 4).
- **Composes**: F-01 + the preflight piggyback idiom (cadence
  check) + per-card Retro Notes from PRs (§1.8.3) + Derby &
  Larsen 5-stage format.
- **Maps to (canonical)**: Derby & Larsen 2006 *Agile
  Retrospectives* — Set the stage / Gather data / Generate
  insights / Decide what to do / Close. Format borrowed
  verbatim; **trigger** is the deviation (event-driven, not
  sprint-end). Edmondson 1999 *Admin Sci Quarterly* —
  psychological-safety prerequisite.
- **Original framing**: **event-driven trigger** is original
  (consistent with §1.1's "calendar cadence is incoherent at
  AI throughput"). The Derby & Larsen 5-stage format itself
  is canonical.
- **Autonomy**: A for the cadence-driven auto-trigger (matrix
  row 14); R for any proposed SoT changes (matrix row 4).
  Audit log for both.

###### F-13. Weekly aggregated report

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: weekly aggregate report combining two
  audiences in one document: (a) **quality trend** — data from
  F-14's continuous enforcement and any golden-principles
  violation counts; (b) **professional status report** —
  completed cards, shipped PRs, outstanding items, focus areas
  for next week. The two audiences are merged into one output
  because the architect is the same person reading both (P1).
- **Inputs**: project ref + window (default last 7 days).
- **Outputs**: weekly report (markdown), copy-paste-ready for
  status-report use.
- **Composes**: F-01 + F-05 + (F-14 data, when configured) +
  the preflight piggyback cadence trigger.
- **Maps to (canonical)**: OpenAI Codex Automations
  (<https://developers.openai.com/codex/app/automations>) —
  productized weekly summary patterns (weekly code review
  summary, repo maintenance summary). OpenAI's "Harness
  Engineering"
  (<https://openai.com/index/harness-engineering/>) provides
  the principle source for the quality-trend half.
- **Original framing**: **merging quality-trend and
  professional-status into one report** — traditional PM
  workflows separate these (engineering health vs management
  report); board-superpowers merges them because the
  architect is both audiences.
- **Autonomy**: A (matrix row 14, cadence-driven auto-trigger).
  Audit log mandatory.

##### Group E — Project-level conversational features

These features run extended conversations with the architect
to set up or maintain project-level infrastructure. They are
the most explicit application of P7 (D-META-1) — Producer
ships the conversation scaffold; the architect's project-
specific configuration emerges from the conversation.

###### F-14. Harness setup & evolution conversation

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: through conversation, **help the architect
  establish and evolve** continuous-quality-enforcement
  infrastructure for their own project — golden principles
  encoded as lint rules + structural tests + Codex auto-PR +
  automerge harness. Producer **does not** ship a generic
  harness configuration. Instead it elicits the project's
  taste through conversation, then assists in maintaining the
  resulting infrastructure.
- **Inputs**: architect ad-hoc trigger ("set up our harness" /
  "our lint rules need work") + the project's current state
  (existing lint config, test coverage, etc.).
- **Outputs**: (process) a series of conversational exchanges
  and proposed lint rules / test scaffolds / auto-PR
  templates. (artifact) those configurations land in the
  project (R per matrix row 4 / row 10, since they modify SoT).
- **Composes**: `gstack:/plan-eng-review` (design conversation)
  + `superpowers:writing-plans` + project-specific lint /
  test infrastructure.
- **Maps to (canonical)**: OpenAI's "Harness Engineering"
  (<https://openai.com/index/harness-engineering/>) —
  "capture taste once, enforce continuously"; Building an
  AI-Native Engineering Team
  (<https://developers.openai.com/codex/guides/build-ai-native-engineering-team>).
- **Original framing**: **meta-methodology applied to harness**
  — OpenAI's published practice captures OpenAI's own taste;
  F-14 provides the conversational scaffold for any architect
  to capture their own project's taste. Direct concrete
  embodiment of P7 / D-META-1.
- **Autonomy**: R (matrix rows 4 and 10 — artifact landing
  modifies SoT, so each landing requires architect approval).

###### F-15. Kanban hygiene & maintenance ops

**Status:** deferred-to-v1.x — see ADR-0011

- **Capability**: maintenance of the kanban board itself —
  stale-card cleanup, orphan claim branches, outdated labels,
  config drift detection, GitHub Project field consistency.
  **The object is the board, not the project's source code**
  (this distinction from F-14 is important and intentional).
- **Inputs**: project ref + optional scope (full audit / quick
  check).
- **Outputs**: hygiene-issues list + proposed remediations
  (most flow through F-10).
- **Composes**: F-01 + F-11 + F-10 + the preflight piggyback
  (for quick checks).
- **Maps to (canonical)**: Anderson 2010 — board maintenance
  is implicit in "manage flow"; no canonical-agile method
  enumerates these housekeeping operations.
- **Original framing**: **strict separation of "code hygiene"
  (F-14) vs "kanban hygiene" (F-15)** — traditional PM tools
  conflate these because they are not adjacent to AI-
  orchestration scale; at board-superpowers' scale (15
  features, multiple parallel sessions) they are operationally
  distinct.
- **Autonomy**: per-action — label cleanup = A via matrix row
  11; orphan-claim cancel = R via matrix row 8; etc. Audit log
  mandatory.

#### 1.3.2 (reserved for additional Producer specific roles)

Future Producer specific roles (e.g., a Triager split out of
Manager, a dedicated Lint runner, a dedicated Refiner) become
subsections here. v1 ships only Manager.

**Notes on TBD values** (deferred to first lived-data
calibration):

- F-05 board-health grade thresholds (red / yellow / green
  boundaries)
- F-11 size-keyed staleness thresholds (XS = 4h, S = 24h,
  M = 72h, L = 168h are starting defaults, not v1 commitments)
- F-12 cadence threshold (`N cards completed since last Retro`
  default = 30 starting point)
- F-13 weekly report cadence (default = every 7 days;
  configurable)

These are deliberately left TBD per D-META-1 (P7) — defaults
are starting points; the architect captures the project-
specific values during real use.

