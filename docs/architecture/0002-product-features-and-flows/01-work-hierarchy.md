### 1.1 Work hierarchy

Before discussing roles or surfaces, name the structural taxonomy
of work the kanban organizes. board-superpowers organizes Cards
along **two orthogonal axes**. There is **no time-window axis**
(no Sprint, no Iteration) — see the deviation rationale below
for why.

**The two axes:**

```
Project
│
├── outcome axis:   Milestone 1, Milestone 2, ...   (deliverable
│                                                    buckets, optional
│                                                    target dates)
└── thematic axis:  Thread A, Thread B, ...         (continuous work
                                                     mainlines)
```

- **Project** — a single repo / single board scope. One-to-one
  with a GitHub Project v2 (per ADR-0001).
- **Milestone** — a deliverable outcome bucket. Has a goal
  description and an optional target date. Maps to GitHub
  Project's native Milestone field at v1.
- **Thread** — a named work mainline (工作主线) that groups
  related Cards across Milestones by thematic continuity.
  Closest agile-canonical equivalents: **Epic** (Scrum / Jira)
  and **Initiative** (Linear / SAFe). We use "Thread" because
  the user mental model is "a continuous work mainline" —
  Thread is the *dynamic* continuation cousin of the *static*
  Epic grouping.
- **Card** — the leaf work item; the unit Consumers claim and
  Producers add. A Card lives at coordinates on the two axes:

  ```
  Card.milestone : 0 or 1     — which outcome bucket it serves
  Card.threads   : 0..N       — which mainlines it's part of
  ```

  **Untagged Cards** (`milestone=null`) are permitted in
  **Backlog** state — they are raw intake awaiting refinement.
  `milestone` MUST be set before a Card transitions to **Ready**
  state. Threads remain optional even at Ready.

**The orthogonal model in pictures:**

A Thread cuts across Milestones; a Milestone may contain Cards
that belong to multiple Threads or to no Thread at all. Neither
axis nests inside the other:

```
                    Thread A   Thread B   Thread C   (no thread)
                    ────────   ────────   ────────   ──────────

  Milestone X       Card 17               Card 20    Card 18
                    Card 22

  Milestone Y                  Card 21               Card 23

  (untagged)                                          Card 19
                                                      └─ awaiting refinement,
                                                         still in Backlog
```

**Deviations from canonical agile / Kanban (and rationale):**

- **Sprint deliberately dropped** — Scrum and most modern PM
  tools that import its vocabulary (Linear, Jira, SAFe) treat
  Sprint as a fundamental unit. We drop it because at AI-
  orchestration throughput rates (continuous production,
  10–100× human cycle time), **time-boxed cadence becomes
  incoherent**: a 1-week sprint at AI speed contains 50+
  completed cards, which makes sprint-retro data archaeology
  rather than a learning loop. The traditional purposes of
  Sprint (commitment batch, burnout protection, stakeholder
  predictability, ceremony cadence) all collapse: AI has no
  burnout, predictability is per-Card not per-batch, and
  ceremonies need event triggers rather than calendar
  triggers. See `docs/research/agile-best-practices.md`
  Implication #1 for the full reasoning. **This is a
  board-superpowers-original framing** — falls in the Part C
  "no peer-reviewed methodology for AI-orchestration" gap.

- **Pure Kanban (Anderson 2010) also drops Sprint, but for a
  different reason** — Kanban removes Sprint to prevent
  team-burnout and sprint-commitment pressure (anti-patterns
  in human teams). We arrive at the same "no Sprint" answer
  via a different argument (AI throughput inverts the cadence
  rationale). board-superpowers therefore inherits Kanban's
  pull system + WIP limits + classes of service, but for
  AI-throughput reasons rather than human-burnout reasons.

- **Thread axis added on top of Kanban** — pure Kanban does
  not have a thematic-grouping primitive (Anderson treats
  classes of service as the only categorical dimension).
  Threads are a Linear / Jira-style addition (Epic /
  Initiative cousin) that lets the architect track continuous
  work mainlines across Milestones.

- **Thread** is our term for Epic / Initiative — naming choice
  open for future alignment with canon if there's reason. See
  §1.6 (Decomposition surface) for how Threads are produced
  and maintained.

**Cadence is event-driven, not calendar-driven.**

Because Sprint is gone, every routine that traditional agile
ties to a sprint boundary is re-anchored on events or sessions.
Concrete trigger types (the §1.3 Producer surface routines
codify these in detail):

- **Retro** — triggered by Milestone close, by an N-cards-
  completed threshold, or by a detected decomposition-drift
  signal
- **Daily inspection** — triggered at each architect session
  start (a session = one architect engagement window)
- **Refinement** — triggered when Backlog grows past N untagged
  cards, or when architect explicitly requests
- **Flow metrics aggregation** — internal rolling-7-day window
  for averaging (lead time, throughput, CFD); not a user-facing
  concept and not tied to any ceremony

**Position of this section in the spec:** every subsequent
Part 1 section references this hierarchy. Roles (§1.2) operate
on Cards. Producer surface (§1.3) includes routines that
operate at Milestone level (decomposition) and Card level
(Intake, Triage), with cadence triggered by events / sessions
(Retro, Daily inspection, Refinement). Consumer surface (§1.4)
is per-Card. PR contract (§1.8) is per-Card.

