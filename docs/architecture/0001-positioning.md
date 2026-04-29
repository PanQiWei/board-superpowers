# Positioning, scope, and non-goals

> **Status:** accepted (2026-04-25).

board-superpowers is **an enforcement layer that makes parallel AI
execution behave like a real team instead of chaos.**

## Why this exists

AI-era architects spend most of their value not on writing code, but
on **defining real problems, sequencing direction & ideas,
designing architecture, and giving product-experience feedback.** The
implementation work that used to consume their day is becoming AI's
job. board-superpowers operationalizes that role-shift.

Concretely: the architect runs N parallel Claude Code Consumer
sessions against one Board Manager session, walks away, and comes
back to a queue of reviewable PRs. Each PR carries an explicit
`## Human Verification TODO` checklist — verifying that checklist is
the architect's remaining job, and the plugin's whole shape is
designed to maximize how far that scarce attention can go.

## Audience and scale

**Who.** A solo architect or a tight team of 2–3 sharing one board.
Heavy users are people who have made the personal decision to focus
on judgment and architecture rather than line-by-line authorship —
and who are willing to dispatch implementation to AI without
babysitting it.

**Scale at v1.** One GitHub Project per repo, single-architect
ownership of the Manager session, up to ~10 parallel Consumer
sessions on commodity hardware. Cross-team / fleet / multi-org /
multi-architect-on-one-board is the explicit 10x (see Vision below),
not the v1 contract.

## Premises

Six load-bearing premises. Each is stated affirmatively and paired
with a falsification criterion — the observation that would prove
the premise wrong.

### P1 — Role-shift thesis

AI-era architect's primary value is sequencing, judgment, and
architecture; coding is becoming AI's job. board-superpowers exists
to operationalize this shift.

*Falsification:* if architects using board-superpowers consistently
report spending more time *writing* code than *verifying* code
(e.g., > 60% of session time on `git commit` rather than on
Manager / Review Queue routines), P1 is wrong and the plugin's
reason to exist collapses.

### P2a — Substrate commitment

The plugin's structural commitment is to
"use the team's existing board (GitHub Project, Linear, Jira,
etc.) as truth source, never own the state ourselves."

Refusing the hosted control plane is a stance only an open-source
plugin will credibly take.

This commitment has two reinforcing layers:
1. **Architectural:** the **Kanban Protocol**
   ([`0005-contracts/00-kanban-protocol.md`](./0005-contracts/00-kanban-protocol.md))
   is the universal mental model agents reason in; per-backend
   projections (Form A bash CLI, Form B plugin-shipped MCP server,
   Form C REST/GraphQL — see protocol § Implementation surface)
   realize the protocol on each backend. Backend-replacement is
   thus a projection-shaped concern, not a contract-shaped one;
   the protocol's transport-agnostic stance makes that explicit.
2. **Strategic:** competitor business models structurally disfavor
   matching us. They could in principle ship a free OSS adapter
   the way LangChain does, but the bet is they won't prioritize
   it.

*Honest scope of "present commitment" (2026-04-28 reframe):* the
**Kanban Protocol** is committed in writing today
([`0005-contracts/00-kanban-protocol.md`](./0005-contracts/00-kanban-protocol.md),
ADR-0025 accepted) at agent-readable + second-projection-
implementable detail. v1.0 ships **one projection** —
GitHubProjectAdapter (Form A: bash + `gh` CLI) — whose shape is
documented in ADR-0005 (rescoped by ADR-0025 to "the v1
GitHubProjectAdapter implementation projection," not "the
universal contract"). The current `gh`-bound scripts
(`claim-card.sh`, `create-card.sh`, `transition-card.sh`) ARE
that projection's reference shape; the optional wrapper port
that consolidates them behind a single bash adapter file (card
#36) is a refactoring concern of the projection, not a gate on
the protocol. v1.x adds Linear / Jira projections (Form B
expected, wrapping each platform's official MCP server). So P2a
is **"protocol committed, one projection in production, more
projections expected in v1.x."**

*Falsification:* if v1 GA + 1 week (AI cadence) passes and no
second adapter has been seriously attempted (by us or a
contributor), P2a was aspiration dressed as commitment. (Anchor
re-shaped from a 6-month calendar offset by ADR-0010.)

### P2b — Methodology embedded as code

The agile methodology embedded in the routines (INVEST, vertical
slicing, one-card-one-session-one-PR, humans merge, Retro is
signal aggregation not ceremony, soft WIP limit) is harder to
copy than it looks but easier than P2a. It's the daily-UX layer
sitting on top of the structural commitment in P2a.

*Falsification:* if a similar tool ships every routine we have
inside their hosted product within one release cycle and
adoption-of-board-superpowers stalls in response, P2b carried no
weight and the differentiation rests purely on P2a.

### P3 — Solo / small-team scale at v1

v1 is for ONE architect or a tight team of 2–3 sharing one board.
Cross-team / fleet / multi-org / multi-architect-on-one-board is
the explicit 10x (Vision option 2), not v1.

*Falsification:* if a single architect cannot run 5+ parallel
Consumer sessions against one Manager session without
filesystem / git / coordination hazards in v1, P3's "small-team
OK" half is unsupported (because team-of-3 = at least 3 sessions
in parallel against the same board on the same repo).

### P4a — Truth-source belongs to the user, never us

board-superpowers never owns board state. The user's existing
board is the truth. Period. v1 ships GitHub Project v2 as the
reference backend; future adapters (Linear, Jira, others) are
first-class targets, not afterthoughts.

*Falsification:* if we ever ship a feature whose primary state
lives in `.board-superpowers/` (or any plugin-owned location) and
is not reconstructible from the user's board + git remote, P4a
broke. Allowed: per-session scratch (claim markers, plan briefs).
Forbidden: durable state that the user's board doesn't see.

### P4b — Composition is permanent

board-superpowers never reimplements TDD, QA, code review,
brainstorming, security audit, or any discipline already provided
by superpowers or gstack. Hard runtime dependency on those
plugins is a feature, not a bug. (See ADR-0004.)

*Falsification:* if we ever ship a skill that duplicates an
existing `superpowers:*` or `gstack:/*` skill (overlapping
description, overlapping triggers), P4b is broken. PRs that touch
SKILL frontmatter are the gate.

### P5 — Distribution stays minimal

Today: git clone + `/plugin add local`. Future: marketplace
one-liner. Never a hosted install service, account creation, or
wizard. "Marketplace" here is a distribution channel, not a
control plane — install delivers static files to
`~/.claude/plugins/`, no runtime dependency on the marketplace
after install.

*Falsification:* if installing or upgrading board-superpowers
ever requires a network call to a service we host, P5 is broken.

### P6 — Human verification is a first-class output

Every Consumer PR ships a `## Human Verification TODO` section.
The human verifying that section is the *point* of the
architect's remaining role; the plugin's value falls apart if
Consumers stop producing actionable human-verification checklists.

*Falsification:* if architects start auto-merging
board-superpowers PRs without reading the Human Verification
TODO, either the contract is no longer honored OR P1's
"verification is the architect's job" thesis is being violated.
Either way, the architectural premise weakens.

### P7 — Meta-methodology, not opinionated configuration

board-superpowers ships **meta-methodology**: conversational
scaffolds and maintenance mechanisms that help an architect
*establish and evolve* their own software-engineering practice
(kanban management, quality harness, retro / report cadence,
autonomy boundary). It deliberately does NOT ship project-specific
concrete configuration — no default lint rules, no default PR
template content, no fixed WIP number, no default report format.

Where P1 names *for whom* we optimize (architect attention is the
bottleneck) and P2a + P2b name *what form* the optimization takes
(substrate + methodology embedded as code), P7 names *where the
boundary of that optimization lies*: the plugin is the
capture-machinery, not the capture-output. The architect's taste
is the project-specific layer; we never ship taste presets that
prejudge it.

OpenAI's "Harness Engineering"
(<https://openai.com/index/harness-engineering/>) is the closest
external precedent — "capture taste once, enforce continuously."
That work captures OpenAI's own taste in OpenAI's own harness.
P7 sits one layer above: we provide the capture machinery itself,
so any architect can capture their own taste in their own
project. Shipping our taste as defaults would collapse the layer
above into the layer below and reproduce the very thing P7
refuses.

Anti-patterns this premise refuses to ship (each is a recurring
"can we just add a default for X?" temptation):

- **Default lint config.** Producer helps the architect bootstrap
  their own; we don't pick `ruff` over `flake8`, `eslint` over
  `biome`, or strict over loose.
- **Default PR template content.** The 3-section structure
  (`Automated Verification` / `Human Verification TODO` / `Retro
  Notes`) is hardcoded because it's protocol; the *content* of
  each section is project-customized, never preset.
- **A fixed WIP=N.** A starting default exists for first-run
  ergonomics, but D-AUTONOMY-1 (ADR-0006) gives Producer authority
  to assist the architect tuning it from observed flow metrics.
  WIP is a project parameter, not a plugin opinion.
- **Default retro template content.** Retro is signal aggregation
  from PR notes; the aggregation rubric is project-tunable, not
  a one-size-fits-all template.

*Falsification:* if board-superpowers ever ships a default whose
content prejudges what the architect's project should look like
(a recommended lint ruleset, a canned PR-section body, a retro
template with prescribed questions), P7 is broken — either we
revert the default or we amend P7 to admit the line moved.

### P8 — Default + override + accountability

board-superpowers' governance pattern across every dimension —
Producer autonomy, TDD enforcement, permission boundary,
cross-card touch, stakeholder routing, board mutation,
adversarial review — follows one shape: a sane **default**
executes automatically; **overrides** are allowed but cost
explicit friction (a config edit, a written justification, an
architect prompt); every override leaves an **accountable**
trace (audit-log row, PR description body, card-thread comment).

This is the inverse of two more obvious approaches we explicitly
refuse:

- **All-default-no-override** would force the architect to fork
  board-superpowers to deviate from a built-in choice; collapses
  P7's meta-methodology stance into prescriptive configuration.
- **All-prompt-no-default** would re-introduce the very
  attention-tax bottleneck P1 names; every action becomes a
  question, the plugin no longer reduces architect load.

P8 sits between: the default does the right thing for the
typical case, the architect can deviate when judgment differs,
and either way the trail is preserved for retrospective review.
This is a design generalization of D-AUTONOMY-1's Auto / Reserved
/ Never matrix (ADR-0006), but it applies to every governance
dimension in the project, not just Producer autonomy.

Concrete instances of the pattern (each documented in its own
spec):

- **D-AUTONOMY-1** (ADR-0006) — Producer's 14-row matrix is the
  canonical instance: A executes auto, R proposes-and-awaits,
  every action writes audit log.
- **TDD-skip rule** (`0002-product-features-and-flows/04-consumer-surface.md`
  F-C5) — `type:docs` / `type:chore` default-exempt, others
  default-required, Consumer can override with PR-section
  justification.
- **Permission boundary three layers** (F-C7) — engineer-norm
  default, ambiguity-fallback surface, hard-floor refuse.
- **Cross-card touch** (F-C6) — default refuse, surface for
  arbitration.
- **Stakeholder routing** (F-C13) — default integrate-as-context,
  surface when scope expansion implied.
- **Board-mutation gradient** (`0002-product-features-and-flows/07-cross-cutting-invariants.md`
  I-13 area) — own-card status auto, labels / body / title
  case-by-case, other cards refuse.
- **Plugin-upgrade new features** (F-B4) — default-enable with
  auto-enabled list and per-feature opt-out.

Where P7 names *the boundary of opinionation* (we ship
mechanisms, not project-specific configuration), P8 names *the
shape governance takes inside that boundary* (default executes,
override allowed with friction, audit captures).

*Falsification (concrete observable):* if a PR adds a new
governance dimension AND the diff lacks **all three** of (a) an
`autonomy_overrides:` schema entry or equivalent declarative
override surface, (b) the corresponding override mechanism wired
in code (env var, config field, or interactive prompt), and
(c) an AuditEntry `action_id` row defining what the audit trail
records when the override fires — then P8 is broken for that
dimension. Either we land the missing legs in a follow-up PR or
we amend P8 in an ADR to admit the boundary moved. The PR-diff
test is the load-bearing observable; "the typical architect
would approve" subjective phrasings are not.

## Non-goals (explicit refusals)

These are commitments to *not* do things; refusing them is part of
what makes board-superpowers what it is. Future questions of the
shape "should we add X?" should test against this list before
being entertained.

- **No own backend / DB / web UI.** Truth lives on the user's board
  (GitHub Project today, Linear / Jira / others via adapter
  tomorrow). See ADR-0001.
- **No reimplementation of upstream disciplines.** TDD belongs to
  superpowers; QA / review / brainstorming / security belong to
  gstack. Composition is permanent; we do not absorb their scope.
  See ADR-0004.
- **No CI replacement.** Tests run wherever the user's CI runs.
- **No story points / velocity / per-architect performance metrics.**
  Cards are XS / S / M / L only. Retro surfaces flow signals, not
  KPIs.
- **No cross-team / fleet view at v1.** That's the explicit 10x
  (Vision option 2), not v1.
- **No agent self-merging PRs.** Humans merge. Agents propose.
- **No hosted install service / account creation / install wizard.**
  Distribution stays git clone + `/plugin add local` today,
  marketplace one-liner future. No hosted layer ever.
- **No methodology-extension marketplace.** Third-party "discipline
  plugins" extending routines is permanently out — versioning debt
  + chicken-and-egg costs do not fit the side-project framing.

## AI-native concept hygiene

Most agile process artifacts assume a fixed implementation
throughput — roughly: human-developer-days. When that assumption
holds, time-boxing (sprint), per-day decomposition (sub-task /
sub-issue), and scale-aware estimation (story points) all earn
their keep. In AI-orchestrated software R&D, implementation
throughput moves 10×–100× (per ADR-0010's AI-cadence convention)
while architect attention does not (per P1 + P3). The agile
process surface that humans built around the implementation
bottleneck loses its load-bearing purpose, and quietly becomes
ceremony.

board-superpowers walked through this surface concept by concept.
Each removed or transformed artifact was tested against one
question: *what does this do that something else doesn't already
do better in an AI-cadence world?*

| Removed concept | Human-cadence purpose | AI-native replacement |
|-----------------|----------------------|----------------------|
| **Sprint** | Time-boxed batch + retro + demo unit | Continuous flow + per-PR demo (Human Verification TODO) + Retro from PR Notes (signal aggregation, not ceremony) |
| **Sub-issue / sub-task** | Decompose Story into person-day chunks for sprint; multi-human coordination point; stakeholder visibility; estimation aggregation; sprint-internal sequencing; mental chunking | INVEST sibling slicing + `depends-on` (decomposition); atomic claim primitive at git-push layer (coordination); Thread / Milestone (visibility, chunking); XS/S/M/L sizing (estimation); continuous flow (sequencing) |
| **Story points** | Scale-aware sprint estimation | XS/S/M/L only — coarse enough to be quick, granular enough to flag *too big, slice further* |
| **Burndown chart** | Visualize sprint progress | WIP + Done count read directly by Daily routine |
| **Stand-up meeting** | Sync across humans | Agents don't need sync; architect already reads PRs |
| **Epic** | Multi-sprint feature container | Replaced by Thread (theme grouping) or Milestone (deliverable bucket); same role, no multi-sprint container assumption |

The pattern in one sentence:

> If a software-development concept assumes implementation
> throughput is the bottleneck, AI-native R&D probably makes it
> degenerate. **Architect attention is the new bottleneck**;
> everything board-superpowers kept and everything it built
> optimizes for that.

These are not oversights. Each was evaluated and rejected
because its load-bearing purpose evaporates when implementation
throughput scales 100× while architect attention does not.

**Falsification test for new concept additions.** When a future
contributor proposes adding feature X (e.g., "let's add story
points back," "let's add sub-tasks under cards," "let's add a
sprint-like cycle"), the test is: *can X carry load that
existing AI-native mechanisms (continuous flow + INVEST siblings
+ Thread / Milestone + atomic claim + XS/S/M/L) cannot? If not,
X is degenerate by the same reasoning that removed sprint.*
Adding such a feature requires an ADR documenting which AI-
native mechanism is insufficient and why.

**Companion artifacts:**

- [`../README.md`](../../README.md) § "Why there's no sprint, no
  sub-issue, no story points" — community-facing version of this
  argument. Same content, less spec jargon.
- [`adr/0026-multi-kanban-lifecycle-and-flat-card-hierarchy.md`](./adr/0026-multi-kanban-lifecycle-and-flat-card-hierarchy.md)
  § "3. Card hierarchy" — the protocol-level decision (Card
  stays flat) that this concept-hygiene argument anchors.
- [`0005-contracts/00-kanban-protocol.md`](./0005-contracts/00-kanban-protocol.md)
  § "Card hierarchy" — protocol semantic-level encoding of the
  flat-Card decision and display-only metadata fields.

## Glossary

Terms used throughout this doc and downstream architecture docs.
Maintainers reading six months from now should be able to reach
back here when a phrase confuses them.

- **Substrate commitment (P2a).** A strategic-architectural
  commitment: we use the team's existing board as truth source and
  refuse to own state ourselves. Has two reinforcing layers
  (architectural + strategic) — see P2a above.
- **Kanban Protocol.** The semantic mental model agents reason in
  when interacting with any kanban board (GitHub Project v2,
  Linear, Jira, future). Establishes ontology (Board / Card /
  Status / Claim / PR Link / Label / Comment), six-state machine,
  identity rules (`Card.key` opacity, branch naming
  `claim/<key-slug>-<title-slug>`), eight action contracts,
  compliance levels, and three implementation projection forms
  (bash CLI, plugin-shipped MCP server, REST). Lives in
  `0005-contracts/00-kanban-protocol.md`. ADR-0025 promotes this
  protocol to spec authority.
- **Backend projection.** A concrete realization of the Kanban
  Protocol on one backend through one transport. v1 ships one
  projection: **GitHubProjectAdapter** (Form A — bash + `gh` CLI),
  whose implementation shape is documented in ADR-0005 (rescoped
  to projection-only by ADR-0025, not the universal contract).
  v1.x roadmap: Linear / Jira projections, expected to be Form B
  (plugin-shipped MCP server wrapping the official Linear /
  Atlassian Remote MCP server).
- **Backend-shape-agnostic.** A property of skills: they reason in
  Kanban Protocol terms (not backend-specific APIs) and dispatch
  to the active projection through `operating-kanban` (lands
  v0.5.0). Today's `gh`-bound scripts ARE the GitHub projection's
  reference shape; the optional wrapper port that consolidates
  them behind a single bash adapter file (card #36) is a
  refactoring concern of the projection.
- **Claim primitive.** The atomic operation that gives a Consumer
  Session exclusive ownership of a Card. Today: `git push
  --force-with-lease=<ref>:` of a `claim/<key-slug>-<title-slug>`
  branch (per ADR-0025's branch-naming abstraction; for GitHub
  `<key-slug>` slugifies to the issue number, so existing
  `claim/<N>-<slug>` branches remain valid). This is **git-layer**,
  not board-layer — git platform (GitHub/GitLab/Bitbucket)
  decides atomicity; the board only observes the resulting status
  transition. See ADR-0002.

## Position vs the obvious alternatives

board-superpowers sits at the intersection of three categories.
Each category has a real, well-funded alternative; the differentiation
isn't "we invented something new" — it's that none of the alternatives
covers all three positions simultaneously.

| Closest existing thing | Where it covers us | Where we differ |
|------------------------|--------------------|-----------------|
| **Linear / Jira / GitHub Projects + raw Claude Code** | Process tooling + AI in different windows | Process tools don't enforce; AI sessions don't coordinate. We give one tool that does both, with the agile methodology embedded as code rather than configurable as preference. |
| **gstack + superpowers used by hand** | Per-task disciplines (TDD, brainstorm, review, QA, /cso) | Those disciplines work on one task at a time. We add the multi-task agile orchestration that composes them into routines (Daily / Intake / Review Queue / Triage / Retro). |
| **One Claude Code session with subagents** | Parallelism via the built-in dispatching primitive | Subagents share a session and a context window. We give true parallel sessions with GitHub as the coordination backbone, so 10 Consumers don't blow each other's context. |
| **Devin** (with Linear/Jira), **Factory** | End-to-end ticket → worktree → PR via AI | The flows are functionally near-identical; differentiation is **control-plane location** — they own a hosted control plane (their business model requires it); we never own one (P2a + P4a). |

The interesting position is the fourth row. board-superpowers and
Devin do almost the same thing — but where Devin holds state in its
hosted backend and renders coordination through its UI, we hold
state in your existing board and render coordination through git.
That choice is structural, not feature-level — and it's the load-
bearing architectural commitment behind P2a.

## Vision

Two amplifiers of the v1 thesis. Both are explicitly post-v1; both
are first-class on the roadmap.

### Self-improving methodology (per project)

Retro signals auto-tune CLAUDE.md decomposition rules per project.
Year 2 of using board-superpowers on a project, the agent knows
your repo's idioms (which subsystems get under-sized, which areas
need a11y verification on every PR, which dependencies always
surprise) better than a new hire would in 6 months. The
methodology stays the same; the parameters tune themselves.

### Cross-team standard

Multi-architect, multi-board fleet. The methodology becomes the
lingua franca for AI-era engineering teams the way Scrum was for
the prior era — but enforced by code, not by ceremony. 100
architects across an org speak the same agile dialect; retros
aggregate cross-team patterns; hiring conversation includes "we
work in board-superpowers." The Kanban Protocol
(`0005-contracts/00-kanban-protocol.md`, ADR-0025) is what makes
this reachable for non-GitHub teams — agents speak protocol;
per-backend projections (the GitHubProjectAdapter projection
ships at v1.0; Linear / Jira projections in v1.x) realize it on
each team's substrate.

### Explicitly rejected

**Open methodology marketplace.** Third-party "discipline plugins"
extending routines (chaos-engineering, fintech-money-flow-audit,
etc.) is permanently out. Reasons: the versioning debt of a stable
plugin contract is heavy; chicken-and-egg ecosystem risk is real;
it's not a 10x of the role-shift thesis (it's a 10x of
"extensibility for its own sake"); it doesn't fit the side-project
framing the maintainer signed up for. If domain-specific judgment
needs to live in a board-superpowers project, encode it as
project-local CLAUDE.md rules, not as a plugin-extension surface.

## Related

- ADR-0001 — pluggable board backend (GitHub Project v2 as v1
  reference adapter)
- ADR-0004 — composition over reimplementation
- ADR-0005 — v1 BoardAdapter contract surface
- `CLAUDE.md` — developer guide (operational; this file is
  foundational)
- `README.md` — end-user overview
