# Agile best practices — research reference

> **Why this doc exists.** board-superpowers' core thesis (positioning
> P2b: "methodology embedded as code") only holds if the methodology
> we encode is **industry-validated**, not invented. This document is
> the canonical reference of established practice from the agile /
> kanban / DORA / SDLC literature, distilled from primary sources, so
> that when we draft `docs/architecture/0002-product-features-and-
> flows.md` and the related architecture docs, we can **cite, adopt,
> or deliberately deviate** rather than ad-hoc invent.
>
> **Three parts.** A: Kanban methodology + flow theory (Anderson,
> Reinertsen, TPS lineage). B: Story decomposition + work splitting
> (Wake, Cohn, SPIDR, INVEST). C: Agile ceremonies + DORA + AI-SDLC
> (Scrum Guide 2020, *Accelerate*, Derby & Larsen, plus an honest
> survey of the much shakier AI-orchestration literature).
>
> **Closing section.** "Implications for board-superpowers spec" —
> 9 concrete revisions to the spec docs surfaced by this research.
> That section is the bridge from research → architecture work.

---

## How to use this doc

- **Before drafting** any spec section that touches kanban
  primitives, ceremonies, decomposition, DoR/DoD, retrospectives,
  PR culture, or DORA metrics: search this doc first; cite the
  canonical source in the spec section; only invent vocabulary
  when no established term covers the case.
- **For AI-orchestration specifics** (multi-agent kanban, role of
  master agent, agent-driven decomposition): Part C is honest
  about the gap — there is **no peer-reviewed methodology**. The
  plugin is itself contributing here. Spec sections that fall in
  this gap should label themselves as **"proposed"** rather than
  **"encoded"**.
- **When in doubt**, primary sources (named books and papers)
  beat blog posts and vendor marketing. URLs are intentionally
  sparse — the load-bearing material is in print.

---

## Part A — Kanban methodology + flow theory

### Pull system
- **Canonical definition (1-2 sentences):** A system in which
  downstream capacity signals upstream to release the next unit
  of work; nothing enters a stage until that stage has free
  capacity. Contrasts with push, where work is released on a
  schedule or on demand from the input side regardless of
  downstream load.
- **Source / authority:** Anderson, *Kanban* (2010), ch. 1
  "Solving the Agile Manager's Dilemma" and ch. 8 "The Recipe
  for Success"; lineage from Ohno, *Toyota Production System*
  (1988), ch. 2.
- **Why it matters / what it constrains:** Caps inventory between
  stages, exposes bottlenecks instead of hiding them in queues,
  and removes scheduling as a planning artifact.
- **Plugin relevance:** A board where Consumers claim cards
  (vs a Manager assigning) is a pull system; the plugin's
  atomic-claim branch push *is* the kanban signal.

### WIP limits
- **Canonical definition:** An explicit upper bound on the number
  of work items allowed in a column, swimlane, or system at any
  moment. The bound is the mechanism that turns a visualized
  board into a pull system — without it the board is just a
  tracker.
- **Source / authority:** Anderson, *Kanban* (2010), ch. 6
  "Mapping the Value Stream" and ch. 9 "From Worst to Best in
  Five Quarters"; theoretical basis in Little's Law (Little,
  1961) and Reinertsen, *Principles of Product Development Flow*
  (2009), ch. 6 "The Principles of Batch Size" and ch. 7 "The
  Principles of WIP Constraint".
- **Why it matters:** By Little's Law, lead time scales linearly
  with WIP at constant throughput; capping WIP is the only direct
  lever on lead time that doesn't require adding capacity.
- **Setting them — competing conventions:** Anderson recommends
  per-column limits (e.g., 1.5× developers for "in progress").
  Leopold (*Practical Kanban*, 2017) prefers whole-board /
  CONWIP-style limits because per-column limits create local
  optima. Per-person WIP limits exist in practice (one item per
  pair) but are community folklore, not anchored to a primary
  text.
- **Soft vs hard:** Anderson's original formulation treats limits
  as hard. Many modern teams run "soft" limits that warn but
  don't block; this is a pragmatic deviation, named by Leopold
  and others.
- **Plugin relevance:** A soft per-board WIP limit (default 5 in
  this plugin) protects the architect's verification attention,
  which is the human bottleneck. Worth a one-line ADR.

### Classes of service
- **Canonical definition:** A categorization of work items by
  urgency profile — i.e., the shape of their cost-of-delay curve
  — that determines pull priority and policy. Anderson defines
  four canonical classes: Standard, Expedite, Fixed-Date,
  Intangible.
- **Source / authority:** Anderson, *Kanban* (2010), ch. 11
  "Establishing a Delivery Cadence" and especially ch. 13
  "Classes of Service".
- **The four classes:**
  - **Standard** — linear or roughly-linear cost of delay; FIFO
    within the class.
  - **Expedite** — steep, immediate cost of delay (production
    outage, regulatory). Gets a dedicated swimlane and may
    violate WIP limits by policy.
  - **Fixed-Date** — cost of delay near-zero until a deadline,
    then steps up sharply (compliance, marketing launches).
    Pulled when remaining time approaches the estimated lead
    time.
  - **Intangible** — cost of delay currently low or unknown but
    may rise (tech debt, refactors). Pulled to fill slack
    capacity.
- **Why it matters:** Different urgency profiles need different
  pull rules; treating everything as Standard wastes capacity on
  low-CoD work and starves Expedite items.
- **Plugin relevance:** Maps cleanly onto label conventions for
  AI-claimed cards; Expedite-class cards justify bypassing the
  WIP soft limit. **Currently absent from card schema — adding
  is cheap.**

### Cumulative Flow Diagram (CFD)
- **Canonical definition:** A stacked area chart over time where
  each band is the count of items in a given workflow state.
  Horizontal distance between top and bottom band edges = WIP;
  horizontal distance between two band edges at a y-value
  approximates average time-in-state for items at that point.
- **Source / authority:** Anderson, *Kanban* (2010), ch. 14
  "Metrics and Management Reporting"; precursor in Anderson,
  *Agile Management for Software Engineering* (2003).
- **Bottleneck patterns:**
  - **Widening band** in one state = arrivals exceed departures
    = bottleneck at the *next* stage.
  - **Flat band** = no work entering or leaving the state
    (starvation upstream or block downstream).
  - **Diverging top and bottom curves** = WIP growing
    system-wide; lead time rising.
  - **Parallel curves** = system in flow equilibrium.
- **Why it matters:** It's the only diagnostic that shows lead
  time, throughput, and WIP simultaneously over time;
  retrospectives use it to locate bottlenecks empirically rather
  than by intuition.
- **Plugin relevance:** Retro routine should generate a CFD from
  GitHub Project status-change events; widening "In Review" band
  is the classic AI-team signal of human-verification bottleneck.

### Little's Law
- **Canonical definition:** For a stable queueing system in
  steady state: **L = λW**, or in software-kanban form,
  **Average Lead Time = Average WIP / Average Throughput**. It
  is an identity, not a model — it holds independent of arrival
  distribution, service distribution, or scheduling discipline,
  *provided* the assumptions are met.
- **Source / authority:** Little, *A Proof for the Queuing
  Formula L = λW* (Operations Research 9.3, 1961); software
  framing in Reinertsen, *Principles of Product Development Flow*
  (2009), ch. 3 "Economics of Queues" and Vacanti, *Actionable
  Agile Metrics for Predictability* (2015).
- **Assumptions that break in software:** stable system
  (violated by sprint boundaries / end-of-quarter pushes); no
  items leave by means other than completion (violated by
  cancellation); average WIP age ≈ average lead time of
  completed items (violated when a long-running stuck item
  skews WIP).
- **Why it still matters as a heuristic:** Even when the strict
  identity fails, the *direction* is reliable: cutting WIP at
  constant throughput lowers lead time. It justifies WIP limits
  without requiring a full queueing model.
- **Plugin relevance:** Quantifies why uncapped Consumer
  parallelism degrades end-to-end card lead time even when the
  model has spare capacity.

### Cost of Delay (CoD)
- **Canonical definition:** The economic loss per unit time from
  not having a feature delivered — the slope (or full curve) of
  value-loss against schedule slip. Reinertsen frames it as the
  single most important variable in product economics and the
  one most teams refuse to quantify.
- **Source / authority:** Reinertsen, *Principles of Product
  Development Flow* (2009), ch. 2 "The Economic View" (esp.
  principle E5: "If you only quantify one thing, quantify the
  cost of delay"); Reinertsen, *Managing the Design Factory*
  (1997), earlier formulation.
- **CD3 — Cost of Delay Divided by Duration:** Prioritization
  heuristic: rank work by CoD ÷ expected duration (sometimes
  called WSJF, "weighted shortest job first", in SAFe's
  adaptation). Maximizes value delivered per unit of capacity
  consumed. Note: WSJF in SAFe uses a normalized proxy for CoD;
  this is a pragmatic deviation, not Reinertsen's original.
- **Qualitative urgency profiles:** When teams cannot quantify
  CoD in dollars, Reinertsen and Anderson endorse classifying by
  curve shape — which is exactly what classes of service
  formalize.
- **Plugin relevance:** When the bottleneck is human verification
  time, CD3 says **prefer many small low-duration cards over one
  large high-CoD card** — directly justifies the "split if it
  doesn't fit one PR" rule.

### Pull vs assignment
- **Canonical definition:** In a pull system, the worker (or
  team) selects the next work item from a Ready queue when they
  have capacity; in an assignment system, a planner pre-allocates
  items to workers. Kanban is definitionally pull-based; this is
  its core methodological commitment.
- **Source / authority:** Anderson, *Kanban* (2010), ch. 1 and
  ch. 8; contrasted with Scrum's sprint-commitment model in
  Anderson ch. 4 and in Kniberg & Skarin, *Kanban and Scrum —
  Making the Most of Both* (2010).
- **Why it's load-bearing:** Pull preserves WIP cap automatically
  (you can't pull if the column is full), surfaces the bottleneck
  (Ready queue grows when downstream is blocked), and keeps the
  worker's local context in charge of selection.
- **Difference from Scrum:** Scrum commits a batch (sprint
  backlog) at sprint start; work is typically self-assigned
  within the batch but the batch boundary is push. Kanban has no
  batch — pull is continuous. SAFe and "Scrumban" hybrids
  compromise here; purists (Anderson, Leopold) consider the
  compromise a regression.
- **Plugin relevance:** AI Consumers claiming cards via atomic
  branch push *is* the kanban pull signal; assigning cards to
  specific Consumer sessions would break the model.

### Lead time / Cycle time / Throughput
- **Canonical definitions:**
  - **Lead time:** Wall-clock time from when an item is
    *committed to* (enters Ready / commitment point) until it is
    delivered (enters Done). Customer-facing metric.
  - **Cycle time:** Wall-clock time an item spends in active
    work — typically from "In Progress" to "Done".
    Internal-process metric. **Competing definition:** Vacanti
    (*Actionable Agile Metrics*, 2015) uses "cycle time" as a
    synonym for lead time and reserves "process cycle time" for
    the in-progress subset; Anderson uses the narrower
    definition. Always state the start and end states when
    quoting a number.
  - **Throughput:** Number of items completed per unit time
    (items/week is the common unit). Capacity metric.
- **Source / authority:** Anderson, *Kanban* (2010), ch. 14;
  Vacanti, *Actionable Agile Metrics* (2015), ch. 2-4;
  Reinertsen (2009), ch. 3.
- **Why each matters:** Lead time predicts customer experience;
  cycle time isolates the team's process from queueing delays;
  throughput sizes the system. Little's Law ties all three.
- **Plugin relevance — load-bearing:** With AI Consumers, cycle
  time *collapses* (model is fast); lead time is dominated by
  Ready-queue wait + human verification wait. **Optimizing for
  cycle time is the wrong target for our tool — the bottleneck
  is human attention.** This refines positioning P1's thesis.

### Toyota Production System lineage
- **Canonical definition:** TPS is the manufacturing system from
  which lean and kanban descend; its core ideas were articulated
  by Taiichi Ohno (Toyota) and translated to software via the
  Poppendiecks. Three TPS concepts survive as load-bearing in
  modern software kanban; many others (heijunka, takt time,
  single-piece flow as literal practice) are referenced but
  rarely operationalized.
- **Source / authority:** Ohno, *Toyota Production System: Beyond
  Large-Scale Production* (1988); Poppendieck & Poppendieck,
  *Lean Software Development* (2003), ch. 1-3; Liker, *The Toyota
  Way* (2004), ch. 11.
- **Three concepts that survive:**
  - **Jidoka** — "automation with a human touch": stop the line
    when a defect appears rather than letting it propagate.
    Software analog: failing CI blocks merge; broken-build = team
    drops everything.
  - **Andon** — visual signal that something is blocked or
    broken; anyone can pull it. Software analog: "Blocked"
    status, @-mention in PR, or the kanban wall itself.
  - **Kaizen** — continuous, incremental, worker-driven
    improvement of the process. Software analog: retrospectives
    that feed back into the workflow definition (column
    structure, WIP limits, policies).
- **Plugin relevance:** Andon = "Blocked" status + explicit
  unblock workflow; jidoka = a failing PR check halts the
  Consumer rather than auto-retrying; kaizen = the retro routine
  that revises decomposition heuristics from past PR retro notes.

---

## Part B — Story decomposition + work splitting

### INVEST criteria
- **Canonical definition:** A six-letter checklist for evaluating
  whether a user story is ready to be worked on:
  **I**ndependent, **N**egotiable, **V**aluable, **E**stimable,
  **S**mall, **T**estable. Each letter is a property of a *good*
  story, not a hard gate.
- **Source / authority:** Bill Wake, "INVEST in Good Stories,
  and SMART Tasks," XP123, August 2003.
- **Letter-by-letter:**
  - **Independent** — the story can be built and shipped without
    waiting on a sibling. *Pitfall:* hidden coupling via shared
    schema/migration that only surfaces at integration.
  - **Negotiable** — the story is a placeholder for a
    conversation, not a fixed spec. *Pitfall:* over-specified
    acceptance criteria that lock implementation choices the
    implementer should own.
  - **Valuable** — delivers value to a user or stakeholder, not
    just to the next layer of code. *Pitfall:* "build the auth
    middleware" — valuable to engineers, invisible to users.
  - **Estimable** — the team can size it; if not, knowledge is
    missing (spike). *Pitfall:* unestimable stories silently
    absorb a sprint because no one names the unknown.
  - **Small** — fits in a single iteration; rule of thumb a few
    days at most. *Pitfall:* "small" judged by lines of code
    rather than verification surface.
  - **Testable** — has explicit, checkable acceptance criteria.
    *Pitfall:* criteria phrased as "works correctly" / "is
    performant" with no observable.
- **Plugin relevance:** INVEST is the natural validator gate
  before a Manager hands a card to a Consumer — a card failing
  *I* or *T* cannot be safely autonomously implemented.

### Vertical slicing vs horizontal layering
- **Canonical definition:** A *vertical slice* delivers a thin
  end-to-end increment touching every layer (UI → API → DB) for
  one narrow scenario. *Horizontal layering* groups work by
  architectural layer (build all DB first, then all API).
  Vertical is the agile default because each slice is
  independently demonstrable and shippable.
- **Source / authority:** The "vertical slice" framing predates
  a single attribution; commonly traced to early XP practice and
  to Jeff Patton's *User Story Mapping* (O'Reilly, 2014) which
  formalized the **walking skeleton** + **release slices** view.
  The **"hamburger method"** is Gojko Adzic's variant (Adzic,
  "Splitting user stories — the hamburger method," gojko.net,
  ~2012) — list the steps of a workflow, then for each step
  list quality/effort options, and pick a thin horizontal stripe
  across all steps.
- **Plugin relevance:** The Manager's decomposition skill should
  refuse "build the data layer" cards by construction — every
  card should map to a user-observable change.

### Story-splitting pattern catalogs
- **Canonical state:** Multiple overlapping pattern catalogs
  exist; the most-cited primary catalog is Richard Lawrence's
  nine. "Wake's twenty" is widely circulated but lacks a single
  verified canonical URL — community-aggregated.
- **Source / authority:** Richard Lawrence, "Patterns for
  Splitting User Stories" (richardlawrence.info, 2009 — nine
  patterns); Mike Cohn, *Agile Estimating and Planning* (2005)
  ch. 12 ("Splitting User Stories") for an overlapping set.
- **Lawrence's nine (well-attested):** Workflow Steps · Business
  Rule Variations · Major Effort · Simple/Complex · Variations
  in Data · Data Entry Methods · Defer Performance · Operations
  (CRUD) · Break Out a Spike.
- **Commonly added in extended lists:** by user role, by
  acceptance criterion, by interface (browser/mobile/CLI), by
  happy path vs error path, by optional vs required fields.
- **Plugin relevance:** Encode the patterns as named splitting
  strategies the Manager can suggest; "this card looks like a
  *Workflow Steps* split" is more actionable than "make it
  smaller."

### SPIDR pattern
- **Canonical definition:** A five-letter splitting heuristic —
  **S**pike, **P**ath, **I**nterface, **D**ata, **R**ules. Try
  them in order; the first one that yields a sensible split
  wins.
- **Source / authority:** Mike Cohn, "Five Simple but Powerful
  Ways to Split User Stories," Mountain Goat Software blog
  (mountaingoatsoftware.com), ~2017. SPIDR is Cohn's modern
  consolidation of the Lawrence/Wake patterns into a memorable
  five.
- **The five:**
  - **Spike** — split off a time-boxed investigation when the
    story can't be estimated.
  - **Path** — split by the different paths through the story
    (happy / error / edge).
  - **Interface** — split by which interface or platform
    (browser vs mobile, API vs UI).
  - **Data** — split by data variation (handle USD first, other
    currencies later).
  - **Rules** — split by which business rules are enforced now
    vs later.
- **Plugin relevance — load-bearing:** SPIDR is the right default
  decomposition algorithm to bake in — short, ordered, covers
  ~80% of real splits. **Adopt directly into the
  `decomposing-into-milestones` skill.**

### Definition of Ready (DoR)
- **Canonical definition:** A team-agreed checklist a story must
  satisfy before it is pulled into a sprint / claimed for work.
  Typical contents: clear acceptance criteria, dependencies
  identified, sized, INVEST-clean.
- **Source / authority:** No single canonical author. The term is
  widely attributed to Scrum community practice circa 2010;
  popularized in writing by Jeff Sutherland and others. *Honest
  gap:* DoR is **not** in the Scrum Guide and is sometimes
  explicitly criticized (notably by Ron Jeffries) as anti-agile
  bureaucracy.
- **Common pitfalls:** Treating DoR as a hard bureaucratic gate
  (anti-pattern — turns the backlog into a waterfall queue) vs
  treating it as a shared-understanding checklist (the
  agile-aligned reading).
- **Plugin relevance:** DoR is the natural place to encode "card
  body schema complete" as a machine-checkable precondition
  before a Consumer can claim. **The contested status means we
  should either embrace it explicitly with INVEST + machine
  checks as the criteria + rationale (and address Jeffries'
  critique), OR skip it and explain why.**

### Definition of Done (DoD)
- **Canonical definition:** A team-agreed checklist a story must
  satisfy to be considered complete. Typical contents: code
  merged, tests passing, code-reviewed, deployed to staging (or
  production), documentation updated, accepted by Product Owner.
- **Source / authority:** Defined in the **Scrum Guide**
  (Schwaber & Sutherland, current edition) as a required
  artifact. The layered view — per-story DoD, per-sprint DoD,
  per-release DoD — is well-established practice but not in the
  Guide itself; common in Cohn and in Henrik Kniberg's *Scrum
  and XP from the Trenches* (2007).
- **Common pitfalls:** DoD that stops at "merged to main" —
  omitting "in production" or "user-verified" — produces
  inventory, not value. The cure is to extend DoD with a Human
  Verification step.
- **Plugin relevance:** Maps directly to a PR template's
  `## Automated Verification` + `## Human Verification TODO`
  sections — DoD is what those sections enforce.

### Story estimation — survey
- **Canonical definitions:**
  - **Story points** — relative sizing in unitless points,
    usually Fibonacci-ish (1, 2, 3, 5, 8, 13). Source: Cohn,
    *Agile Estimating and Planning* (2005), credits Ron Jeffries
    with the original "points" framing in early XP.
  - **T-shirt sizing** — XS / S / M / L / XL — coarse buckets
    for early-stage estimation. No single canonical author;
    widespread industry practice.
  - **#NoEstimates** — the position that detailed estimation is
    waste; instead, slice every story to roughly the same size
    and count throughput. Source: Vasco Duarte, *#NoEstimates:
    How To Measure Project Progress Without Estimating*
    (Oikosofy, 2015); Woody Zuill is the other primary advocate.
- **Plugin relevance — load-bearing:** T-shirt sizing without
  numbers + a "split if it doesn't fit one PR" rule is the
  cheapest #NoEstimates-aligned policy — **directly validates
  the spec's existing XS/S/M/L decision.**

### Walking skeleton / "thin vertical slices"
- **Canonical definition:** Deliver a thin slice of a system
  that goes through every layer end-to-end as early as possible
  — the "walking skeleton" that you then thicken. The cake
  metaphor: serve a thin slice of the whole cake (sponge +
  icing + filling), not all the sponge first.
- **Source / authority:** The principle is core XP. Kent Beck,
  *Extreme Programming Explained: Embrace Change*, 2nd ed.
  (Addison-Wesley, 2004) articulates it through Incremental
  Design and Weekly Cycle. The "walking skeleton" naming is
  Alistair Cockburn, *Crystal Clear* (Addison-Wesley, 2004).
- **Plugin relevance:** The very first card on a new project
  should always be a walking-skeleton card — **bake this into
  the bootstrap routine** rather than leave it to taste.

---

## Part C — Agile ceremonies + DORA + AI-SDLC

### Daily Standup (Daily Scrum)
- **Canonical definition:** A 15-minute time-boxed event for the
  Developers to inspect progress toward the Sprint Goal and
  adapt the Sprint Backlog. The 2020 Scrum Guide *removed* the
  prescribed three questions ("did / will / blockers"); they are
  now optional structure, not doctrine.
- **Source / authority:** *Scrum Guide* 2020 (scrumguides.org),
  section "Daily Scrum." Kanban "walk the board" variant:
  Anderson, *Kanban* (2010), ch. on cadences.
- **Why it matters:** It is an *inspection* event for the team,
  not a status report to a manager. Anti-patterns: round-robin
  reporting upward, exceeding the timebox, deferring impediment
  surfacing.
- **Plugin relevance:** A board-walk Manager routine should
  re-create the *inspection* property — surface blockers and
  WIP risk, not produce a per-agent status report.

### Backlog Refinement
- **Canonical definition:** The ongoing activity of adding
  detail, estimates, and order to Product Backlog items so they
  become "Ready" for a future Sprint. It is not a Scrum *event*,
  just an ongoing activity.
- **Source / authority:** *Scrum Guide* 2020, "Product Backlog
  Refinement."
- **Plugin relevance:** Card decomposition (INVEST, vertical
  slicing, SPIDR) belongs in refinement; a Manager skill that
  decomposes mid-sprint is doing refinement, not planning.
  **Our "Intake" routine ≈ Refinement.**

### Sprint Review vs Continuous Demo
- **Canonical definition:** Sprint Review is a working-session
  inspection of the Increment with stakeholders, max 4 hours for
  a one-month Sprint. The "continuous demo" /
  "production-as-demo" framing replaces the cadence-bound review
  with always-shippable trunk + feature-flag exposure.
- **Source / authority:** *Scrum Guide* 2020 ("Sprint Review");
  Humble & Farley, *Continuous Delivery* (2010), ch. 1 & 15;
  Forsgren/Humble/Kim, *Accelerate* (2018), ch. 4.
- **Plugin relevance:** Per-PR "Human Verification TODO" is the
  unit-of-demo equivalent; no batched sprint-review event needed.

### Retrospective
- **Canonical definition:** A timeboxed inspection of the team's
  process, tools, and interactions, producing actionable
  improvements (max 3 hours for a one-month Sprint).
- **Source / authority:** *Scrum Guide* 2020 ("Sprint
  Retrospective"); **Derby & Larsen, *Agile Retrospectives:
  Making Good Teams Great* (Pragmatic, 2006)** — defines the
  canonical 5-phase structure: (1) Set the Stage, (2) Gather
  Data, (3) Generate Insights, (4) Decide What to Do, (5) Close.
  Common formats: Start-Stop-Continue, 4Ls
  (Liked / Learned / Lacked / Longed-For), Mad-Sad-Glad,
  Sailboat (anchors / wind / rocks / island).
- **Effectiveness predicates:** psychological safety (Edmondson,
  1999, *Admin Sci Quarterly*), action items with named owners,
  and a *follow-through gate* at the next retro. Without all
  three the ceremony degrades to theater.
- **Plugin relevance:** A weekly retro skill must aggregate
  signal *and* track action-item closure across weeks, otherwise
  it is decorative.

### Sprint Planning & the Sprint Goal
- **Canonical definition:** Initiates the Sprint by answering
  Why (Sprint Goal), What (selected backlog items), How (initial
  plan). The 2020 Scrum Guide elevated the **Sprint Goal** to
  the single coherent commitment for the Sprint.
- **Source / authority:** *Scrum Guide* 2020, "Sprint Planning"
  + "Commitments."
- **Plugin relevance:** A board-level "weekly theme" or
  epic-coherence field gives Consumer sessions a tiebreaker when
  scope wobbles. Currently absent from card schema.

### What XP / Kanban dropped
- **XP** (Beck, *Extreme Programming Explained*, 2nd ed. 2004):
  keeps planning and retrospective, drops formal review in favor
  of on-site customer + continuous integration; planning poker
  is XP-derived (Grenning, 2002), not Scrum-canonical.
- **Kanban** (Anderson 2010; Reinertsen 2009): drops Sprints
  entirely. Cadence is decoupled from commitment; the system is
  governed by **WIP limits + explicit policies + flow metrics**
  (lead time, throughput, CFD).
- **Plugin relevance — load-bearing:** A pull-based, WIP-limited
  board with no fixed cadence is **Kanban**, not Scrum — name it
  correctly so users don't import sprint-shaped expectations.

### DORA Four Key Metrics
- **Canonical definition:** Deployment Frequency, Lead Time for
  Changes, Change Failure Rate, and Time to Restore Service
  (originally "MTTR"). Recent State of DevOps reports added a
  fifth, Reliability/Operational Performance.
- **Source / authority:** Forsgren, Humble, Kim, *Accelerate*
  (IT Revolution, 2018), ch. 2 & Appendix A; annual *State of
  DevOps Report* (DORA / Google Cloud, 2014–present, dora.dev).
- **Why it matters:** *Accelerate*'s core empirical claim is
  that throughput (Frequency, Lead Time) and stability (CFR,
  MTTR) are *positively* correlated, not a tradeoff. The
  Elite/High/Medium/Low cluster analysis is the benchmark
  scaffolding.
- **Plugin relevance:** A board's flow signals should map cleanly
  to Lead Time and Deployment Frequency at minimum; CFR requires
  post-merge incident linkage.

### Trunk-Based Development
- **Canonical definition:** All developers integrate to a single
  shared trunk at least daily; branches, if any, live <24h.
- **Source / authority:** Paul Hammant,
  trunkbaseddevelopment.com; Humble & Farley, *Continuous
  Delivery* (2010), ch. 14; *Accelerate* (2018), ch. 4
  (identifies TBD as a top predictor of Elite performance).
- **Plugin relevance:** "One session = one card = one
  short-lived `claim/<N>-<slug>` branch" is TBD-shaped; enforce
  branch lifetime as a flow metric.

### GitHub Flow / GitLab Flow
- **Canonical definition:** GitHub Flow (Scott Chacon, 2011):
  single `main`, short-lived feature branches, PR + review +
  deploy. GitLab Flow adds environment branches
  (staging/production) for teams that can't deploy `main`
  directly.
- **Source / authority:** GitHub Docs ("GitHub flow"); GitLab
  Docs ("GitLab Flow").
- **Plugin relevance:** Default to GitHub Flow shape; avoid
  baking in GitFlow's release/develop branches.

### Continuous Delivery vs Continuous Deployment
- **Canonical definition:** *Continuous Delivery* — every commit
  produces a release-candidate that *could* deploy via a manual
  gate. *Continuous Deployment* — every passing commit *does*
  deploy automatically.
- **Source / authority:** Humble & Farley, *Continuous Delivery*
  (Addison-Wesley, 2010), ch. 1.
- **Plugin relevance:** Human Verification TODO is the manual
  gate; the plugin sits at the **Continuous Delivery** boundary,
  not Continuous Deployment.

### Pull-Request Culture / Small-PR Norm
- **Canonical definition:** Pre-merge peer review on a branch
  via a PR / MR, with mergeability predicated on CI green +
  reviewer approval. Empirically, review effectiveness drops
  sharply past ~200–400 LOC per PR.
- **Source / authority:** SmartBear *Best Kept Secrets of Peer
  Code Review* (Cohen, 2006) — Cisco study; Google's *Software
  Engineering at Google* (Winters, Manshreck, Wright, O'Reilly
  2020), ch. 9 ("Code Review"); Microsoft Research: Bird,
  Bacchelli, et al., "Expectations, Outcomes, and Challenges of
  Modern Code Review" (ICSE 2013).
- **Plugin relevance:** Card decomposition heuristics should
  target PR-size, not story-points; **"won't fit in one PR →
  split"** is the operational rule.

### AI-orchestrated SDLC — honest survey

> **Disclaimer up front.** As of late 2025 / early 2026, there
> is **no consolidated peer-reviewed methodology** for
> orchestrating AI agents across the SDLC comparable to
> *Accelerate* for DevOps or the *Scrum Guide* for Scrum. What
> exists is (a) a fast-growing arXiv literature on LLM-based
> code generation and multi-agent systems, (b) industrial blog
> posts and white papers from GitHub Next / Microsoft Research /
> Google DeepMind / Anthropic, (c) early Gartner/Forrester
> analyst framings, and (d) emerging O'Reilly/Manning books that
> are largely *practitioner reports*, not methodology with
> empirical validation. **The lack of established practice is
> itself load-bearing**: the plugin is encoding *agile/DevOps*
> methodology, and treating the *AI-orchestration layer* as the
> part still to be discovered.

#### Peer-reviewed signal (individual productivity)
- Ziegler et al., "Productivity Assessment of Neural Code
  Completion" (MSR / GitHub, *MAPS* workshop 2022) — the
  original Copilot productivity study.
- Peng et al., "The Impact of AI on Developer Productivity:
  Evidence from GitHub Copilot" (arXiv:2302.06590, 2023) — RCT,
  ~55% task speedup on a constrained task.
- Fan et al., "Large Language Models for Software Engineering:
  Survey and Open Problems," ICSE-FoSE 2023 (arXiv:2310.03533)
  — survey of the field.

#### Multi-agent SE (active research, no settled methodology)
- **MetaGPT** (Hong et al., ICLR 2024, arXiv:2308.00352) —
  assigns SDLC roles (PM/architect/engineer/QA) to LLM agents
  with structured artifact handoffs.
- **ChatDev** (Qian et al., arXiv:2307.07924, 2023) —
  waterfall-shaped multi-agent collaboration.
- **AutoGen** (Wu et al., Microsoft Research, arXiv:2308.08155,
  2023) — framework for multi-agent conversations.
- **SWE-bench / SWE-agent** (Princeton NLP, 2023–2024,
  swebench.com) — the benchmark + scaffolded agent that
  legitimized "agent solves a real GitHub issue end-to-end" as a
  research task.
- **CMU SEI:** has published *blog posts and technical notes* on
  AI-augmented software acquisition (sei.cmu.edu/blog) but no
  flagship methodology equivalent to its CMMI or TSP work.

#### AI-assisted code review (mostly product, not methodology)
- Vendors: GitHub Copilot code review (GA 2024), CodeRabbit,
  Graphite Reviewer, Cursor Bugbot, Greptile, Sourcery.
- Closest peer-reviewed: Tufano et al., "Using Pre-Trained
  Models to Boost Code Review Automation" (ICSE 2022); Li et
  al., "Automating Code Review Activities by Large-Scale
  Pre-training" (FSE 2022).
- **Plugin relevance:** Use AI review as a *first-pass filter*
  with a named human gate — exactly what
  `superpowers:requesting-code-review` + `gstack:/review` + a
  Human Verification TODO encode. **Do not claim AI review
  *replaces* human review; the literature does not yet support
  that.**

#### Plugin's own contribution to Part C
Multi-agent SE research validates *role decomposition* (Manager
/ Consumer is a coarse instance) but **not** any specific
coordination protocol. board-superpowers chooses
**GitHub-as-coordinator** deliberately, against the in-process
orchestration default of MetaGPT/AutoGen — that's a novel choice
the spec should own as ours, not pretend to inherit.

---

## Implications for board-superpowers spec

Nine concrete revisions to `docs/architecture/0002-product-features-
and-flows.md` (and a couple of upstream docs) surfaced by this
research. Numbered for cross-reference; **L** = load-bearing,
**M** = medium, **S** = small / cosmetic.

### 1. **[L]** Drop Sprint entirely; cadence is event-driven, not calendar-driven

**Resolved 2026-04-25** — see `docs/architecture/0002-product-features-and-flows/01-work-hierarchy.md` (§1.1).

board-superpowers is **pull-based + WIP-limited at the
execution layer** (Kanban-shape, per Anderson 2010), and
organizes Cards along **two orthogonal axes — Milestone
(outcome) and Thread (≈ Epic / Initiative, thematic)**. There
is **no Sprint, no Iteration, no time-window axis at all**.

**Why drop Sprint:** the traditional purposes of Sprint
(commitment batch, burnout protection, stakeholder
predictability, ceremony cadence) all collapse at AI-
orchestration throughput rates. A 1-week sprint at 10–100×
human cycle time contains 50+ completed cards — sprint-retro
becomes data archaeology rather than a learning loop. AI has
no burnout. Predictability is per-Card not per-batch. And the
real cadence-driving signals (a Milestone closes, N cards
complete, a decomposition heuristic drifts, an architect logs
in for a session) are **events**, not weekdays.

**An earlier draft kept Sprint** as a "cadence anchor for the
human architect" — that argument turned out to be a
post-hoc rationalization. The architect's real cadence is
session-based (sporadic engagement windows) plus event-driven
(retro when Milestone closes, refine when Backlog backs up).
Calendar cadence forces ceremony on a schedule that doesn't
match either the AI's continuous production or the human's
attention-bounded consumption.

**Pure Kanban (Anderson 2010) also drops Sprint** but for a
different reason — Kanban removes Sprint to prevent
team-burnout and sprint-commitment pressure (anti-patterns in
human teams). board-superpowers arrives at the same "no
Sprint" answer via a different argument (AI throughput
inverts the cadence rationale). We inherit Kanban's pull
system + WIP limits + classes of service, but for AI-
throughput reasons rather than human-burnout reasons.

**This is a board-superpowers-original framing** — falls
squarely in the Part C "no peer-reviewed methodology for
AI-orchestration" gap. Specifically the discovery that
**event-driven cadence subsumes calendar-driven cadence
when production speed inverts the human/AI bottleneck
direction**.

**What replaces Sprint as a unit of measurement:** for flow
metrics (throughput, lead time, CFD), we use a **rolling
7-day window** internally — system-internal naming, never
surfaced as a user concept ("the last 7 days" is just the
denominator for averaging, not a ceremony anchor).

**Untagged cards permitted in Backlog:** raw intake doesn't
need a Milestone tag yet. Refinement is the gate that attaches
Milestone before Ready transition. Threads remain optional
even at Ready.

**Affects:** spec already updated (§1.1 Work hierarchy).
Downstream effects still pending: `0001-positioning.md` (P1
thesis sharpens — bottleneck shifts to **session-bounded
human attention**, not sprint-bounded); §1.3 Producer surface
routine designs (Daily / Retro / Refinement triggers must all
be event/session-based); ADR-0005 BoardAdapter contract
(no Iteration type needed); plugin descriptions in
`.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`.

### 2. **[L]** AI Consumers shift the bottleneck — refine P1

With AI Consumers, **cycle time collapses (model is fast); lead
time is dominated by Ready-queue wait + human verification wait**.
Optimizing cycle time is the wrong target. The bottleneck is
human attention. This refines `0001-positioning.md` P1
("role-shift thesis") with a queueing-theory backing rather than
a pure assertion — and gives us a Little's-Law-grounded reason
for the soft WIP limit.

**Affects:** `0001-positioning.md` P1 amendment; spec sections
that talk about "speed" should distinguish cycle time from lead
time.

### 3. **[L]** Distinguish "encoded" vs "proposed" sections

Parts A + B (Kanban + decomposition) and the DORA / TBD parts of
Part C are settled — encode faithfully and cite. The
**multi-agent AI-orchestration coordination protocol** is
unsettled — board-superpowers is itself a contribution. The spec
should label sections accordingly so the reader knows when we're
restating canon vs proposing new.

**Affects:** all of `0002-product-features-and-flows/` (every
sub-file under that directory) — add a visual marker per section
(e.g., `[encoded: Anderson 2010 ch. 13]` vs
`[proposed by board-superpowers]`).

### 4. **[L]** Adopt SPIDR as the default decomposition algorithm

Cohn's SPIDR (Spike / Path / Interface / Data / Rules) is short,
ordered, covers ~80% of real splits. More accessible than
Lawrence's nine or "Wake's twenty." Bake into the
`decomposing-into-milestones` skill as the default split
algorithm; cite Lawrence's nine as supplementary patterns.

**Affects:** §1.5 Decomposition surface; the
`decomposing-into-milestones` SKILL body when we get there.

### 5. **[M]** Add classes of service to card schema

Anderson's four classes (Standard / Expedite / Fixed-Date /
Intangible) map cleanly onto label conventions. Currently absent
from card schema. Adding them is cheap, unlocks Expedite-bypass-
WIP-limit, and gives Manager Triage routine a richer signal.

**Affects:** §1.5.3 Card body schema; future ADR if we adopt
formally.

### 6. **[M]** Decide DoR explicitly (it's contested)

DoR is widely-practiced but not in the Scrum Guide and is
criticized by Jeffries as anti-agile bureaucracy. We should
**either** embrace it explicitly with INVEST + machine checks as
the criteria + rationale (and address Jeffries' critique
inline), **or** skip DoR and explain why our pull-time validation
is a better fit. Don't leave it implicit.

**Affects:** §1.5 Decomposition surface or new §1.x; PR contract
in §1.7.

### 7. **[M]** DORA metrics in retro routine

Lead Time + Deployment Frequency are computable directly from
GitHub Project status-change events + merge-to-main events.
CFR + MTTR need post-merge incident linkage (out of scope at v1
unless we add an "Incident" status). Retro routine should produce
at minimum the two computable metrics; CFD generation is the
high-value visualization.

**Affects:** §1.2 Retro routine sub-section; possibly an ADR for
"what flow metrics retro produces at v1."

### 8. **[M]** Walking skeleton in bootstrap

Per Cockburn 2004, the very first card on a new project should
be a walking-skeleton card — validates the whole pipeline from
claim to deploy on day 1. Currently bootstrap doesn't do this.
Adding "create walking-skeleton card" as a final bootstrap step
gives every new project a shippable proof-of-pipeline.

**Affects:** §1.4 Bootstrap surface (Routing injection
sub-section); `bootstrap-project.sh` script when we get there.

### 9. **[S]** Map Manager 5 routines to ceremonies + use established names where they fit

| Our routine | Maps to | Action |
|-------------|---------|--------|
| Daily | Daily Standup (inspection event, not status report) | Cite *Scrum Guide* 2020; warn against status-report anti-pattern |
| Intake | Backlog Refinement | Consider renaming "Intake" → "Refinement" for vocab alignment |
| Review Queue | (no direct ceremony) | Label as **proposed** |
| Triage | (no direct ceremony) | Label as **proposed** |
| Retro | Sprint Retrospective + Derby & Larsen 5-phase | Cite Derby & Larsen 2006; require psychological safety + action-item closure-tracking |

**Affects:** §1.2 Manager surface — sub-section content for each
routine.

---

## Honest gaps + open questions

Compiled from the three research agents:

- **Per-person WIP limits** are widespread in practice but cannot
  be anchored to a primary text — community folklore.
- **"Soft" WIP limits** are a pragmatic deviation from Anderson's
  hard-limit formulation; named as such by Leopold but not by
  Anderson.
- **WSJF** as used in SAFe is a normalized proxy for Reinertsen's
  CD3, not Reinertsen's original.
- **Cycle time vs lead time** has two competing conventions
  (Anderson narrow vs Vacanti broad). Always state start/end
  states when quoting a number.
- **"Twenty Ways to Split Stories"** — Lawrence's original nine
  are well-sourced; the expanded list of twenty is
  community-aggregated and authorship varies.
- **DoR** has no single canonical source; contested as a
  practice.
- **"Slicing the cake"** — the metaphor is folkloric within the
  agile community; the underlying principle (vertical slicing /
  walking skeleton) is well-sourced (Beck 2004, Cockburn 2004).
- **AI-orchestration methodology** — no peer-reviewed canon
  exists. board-superpowers' coordination shape is itself a
  contribution.

---

## Sources (combined bibliography)

### Books (primary)
- Anderson, David J. *Kanban: Successful Evolutionary Change for
  Your Technology Business.* Blue Hole Press, 2010.
- Beck, Kent. *Extreme Programming Explained: Embrace Change.*
  2nd ed. Addison-Wesley, 2004.
- Cockburn, Alistair. *Crystal Clear.* Addison-Wesley, 2004.
- Cohn, Mike. *User Stories Applied.* Addison-Wesley, 2004.
- Cohn, Mike. *Agile Estimating and Planning.* Prentice Hall,
  2005.
- Derby, Esther & Larsen, Diana. *Agile Retrospectives: Making
  Good Teams Great.* Pragmatic Bookshelf, 2006.
- Duarte, Vasco. *#NoEstimates.* Oikosofy, 2015.
- Forsgren, Nicole; Humble, Jez; Kim, Gene. *Accelerate.* IT
  Revolution, 2018.
- Humble, Jez & Farley, David. *Continuous Delivery.*
  Addison-Wesley, 2010.
- Kniberg, Henrik. *Scrum and XP from the Trenches.* InfoQ,
  2007.
- Kniberg, Henrik & Skarin, Mattias. *Kanban and Scrum — Making
  the Most of Both.* InfoQ / C4Media, 2010.
- Leopold, Klaus. *Practical Kanban.* LEANability Press, 2017.
- Liker, Jeffrey. *The Toyota Way.* McGraw-Hill, 2004.
- Ohno, Taiichi. *Toyota Production System.* Productivity
  Press, 1988.
- Patton, Jeff. *User Story Mapping.* O'Reilly, 2014.
- Poppendieck, Mary & Tom. *Lean Software Development.*
  Addison-Wesley, 2003.
- Reinertsen, Donald G. *The Principles of Product Development
  Flow.* Celeritas, 2009.
- Vacanti, Daniel S. *Actionable Agile Metrics for
  Predictability.* ActionableAgile Press, 2015.
- Winters, Titus; Manshreck, Tom; Wright, Hyrum. *Software
  Engineering at Google.* O'Reilly, 2020.

### Papers (peer-reviewed)
- Bird, Bacchelli, et al. "Expectations, Outcomes, and
  Challenges of Modern Code Review." ICSE 2013.
- Edmondson, Amy. "Psychological Safety and Learning Behavior in
  Work Teams." *Administrative Science Quarterly*, 1999.
- Fan et al. "Large Language Models for Software Engineering:
  Survey and Open Problems." arXiv:2310.03533, 2023.
- Hong et al. "MetaGPT: Meta Programming for Multi-Agent
  Collaborative Framework." arXiv:2308.00352, ICLR 2024.
- Li et al. "Automating Code Review Activities by Large-Scale
  Pre-training." FSE 2022.
- Little, John D. C. "A Proof for the Queuing Formula L = λW."
  *Operations Research* 9, no. 3 (1961).
- Peng et al. "The Impact of AI on Developer Productivity:
  Evidence from GitHub Copilot." arXiv:2302.06590, 2023.
- Qian et al. "ChatDev." arXiv:2307.07924, 2023.
- Tufano et al. "Using Pre-Trained Models to Boost Code Review
  Automation." ICSE 2022.
- Wu et al. "AutoGen." Microsoft Research, arXiv:2308.08155,
  2023.

### Online (canonical, stable)
- Adzic, Gojko. "Splitting user stories — the hamburger method."
  gojko.net, ~2012.
- Cohn, Mike. "Five Simple but Powerful Ways to Split User
  Stories" (SPIDR). Mountain Goat Software,
  mountaingoatsoftware.com, ~2017.
- DORA. *State of DevOps Report* (annual). dora.dev.
- Hammant, Paul. *Trunk-Based Development.*
  trunkbaseddevelopment.com.
- Lawrence, Richard. "Patterns for Splitting User Stories."
  richardlawrence.info, 2009.
- Schwaber, Ken & Sutherland, Jeff. *The Scrum Guide.*
  scrumguides.org, 2020 ed.
- Wake, Bill. "INVEST in Good Stories, and SMART Tasks." XP123,
  2003.
