# ADR 0006: Producer autonomy boundary — autonomous-with-transparency, with explicit permission matrix

**Status:** proposed
**Date:** 2026-04-26
**Deciders:** PanQiWei (maintainer)

## Context

Producer (the Board Manager session) orchestrates the board and
runs many board-modifying actions: creating cards, moving status,
dispatching Consumer sessions, modifying config, splitting work,
and more. Two failure modes bound the design space:

- **Approval-for-everything** violates `0001-positioning.md` P1 —
  architect attention is the scarce resource. If Producer pauses
  at every action for confirmation, the plugin recreates the
  bottleneck it exists to remove.
- **All-auto** loses architect control over structural changes
  and the architect's reserved powers (most notably merge). It
  also makes "is this Producer doing the right thing" un-auditable
  after the fact — there's no surface to inspect what the agent
  actually did between two morning prompts.

A boundary is required: which actions Producer takes on its own,
which actions it must propose-and-await, what gets recorded so
the architect can audit later, and what evolves over time as
trust grows. That boundary is **D-AUTONOMY-1**, defined here.

This ADR also sets the persistence target for the audit log.
That choice is load-bearing because the wrong target (local file
in repo, dedicated audit issue, card comments) creates either a
public audit trail leaking project-internal decisions, or a
file-based store that re-introduces the "plugin owns durable
state" anti-pattern (`0001-positioning.md` P4a). The decision
applies P7 (`0001-positioning.md`): we ship the schema and the
write mechanism; the architect provides the database.

## Decision

### 1. Behavior contract — autonomous-with-transparency

Producer follows three rules, in this order:

1. **Auto when safe.** If the action passes the triage rule
   below (Decision §2) as Auto-class, Producer executes it
   without pausing.
2. **Always log.** Every action — Auto or Reserved — writes an
   audit-log entry. Auto-class writes one entry per execution;
   Reserved-class writes one entry on propose and one on resolve
   (approved / rejected).
3. **Escalate when uncertain.** If the action is Reserved-class,
   OR if Producer's preconditions for an Auto-class action don't
   hold (e.g., card body missing required fields), Producer drafts
   a proposal and awaits the next architect prompt for approval.

We name the three classes **A** (Auto), **R** (Reserved), and
**N** (No-go, permanent). At v1 the matrix has 7 A, 7 R, and 0 N.
The N=0 result is itself a decision — see §4 below.

### 2. Triage rule (short-circuit, top-to-bottom)

Apply each test in order; the first match wins. If none match,
default to A.

1. Touches an **architect's reserved power** (merge, architectural
   decisions) → **R**
2. Modifies a **source of truth** (`CLAUDE.md`, `AGENTS.md`,
   `.board-superpowers/config.yml`) → **R**
3. **Interrupts or risks losing** in-flight work (transitions a
   card to `Blocked`, closes a card, cancels an active claim) →
   **R**
4. **Cross-card structural change** (splits a card, mutates a
   schema invariant) → **R**
5. Otherwise → **A**

### 3. Initial permission matrix (v1)

14 rows. A=7, R=7, N=0.

| # | Producer action | Default | Category |
|---|-----------------|---------|----------|
| 1 | Create cards (decomposition output) | A | forward incremental |
| 2 | Edit card body (refine description, add acceptance criteria) | A | forward incremental |
| 3 | Split card | R | cross-card structural |
| 4 | Update `CLAUDE.md` / `AGENTS.md` | R | source of truth |
| 5 | Backlog → Ready transition | A | forward state advance |
| 6 | In Progress → Blocked transition | R | interrupts in-flight work |
| 7 | Close stale card | R | irreversible + interrupts |
| 8 | Cancel claim | R | interrupts + risks lost work |
| 9 | Adjust WIP limit | A | reversible parameter |
| 10 | Modify `.board-superpowers/config.yml` | R | source of truth |
| 11 | Extend GitHub Project fields (add label / add status option) | A | forward incremental, schema-additive |
| 12 | Auto-merge PR | R | architect's reserved power |
| 13 | Dispatch Consumer session | A | unlocks F-5 overnight batch |
| 14 | Auto-trigger retro / weekly report (cadence-driven) | A | preflight piggyback (see ADR-0007) |

### 4. Trust evolution clause

All R defaults are **current-trust-level settings, NOT permanent
invariants.** N=0 is the intentional declaration that no
permanent untouchable red lines exist at the plugin level — every
R can be promoted to A after stable usage demonstrates that the
risk model has changed for that architect on that project.

The promotion path uses an `autonomy_overrides:` field exposed at
two layers:

- **User layer:** `~/.board-superpowers/overrides.yml` — applies
  to every project the architect uses board-superpowers on.
- **Project layer:** `.board-superpowers/config.yml` — overrides
  the user layer for one specific project.

Project-layer overrides are themselves R-class writes (matrix row
10) — promoting an R to A still requires the architect to make
that change explicitly. Exact override schema and merge semantics
are deferred to `0005-contracts.md`.

### 5. Audit log persistence — BYO RDBMS

Audit log entries persist to a **relational database the
architect provides**. This is a direct application of P7
(`0001-positioning.md`): the plugin ships the schema and the
write mechanism (the **mechanism**); the architect provides the
database (the **infrastructure**).

**Persistence rules:**

- Every A-class action writes one entry on execution.
- Every R-class action writes one entry on propose and one on
  resolve (`approved` / `rejected`).
- The audit log MUST NOT persist to local files inside the
  project root.
- The audit log MUST NOT live in any git-tracked file.
- The audit log MUST NOT be public (no card comments, no
  dedicated audit issue, no GitHub Discussions).

**Backend constraint:** Postgres or MySQL. SQLite is **not
acceptable** because it's file-based and would re-introduce the
"local persistence" anti-pattern under a different name.

**Credentials.** Connection details live in user-level config.
Two candidate mechanisms (final choice deferred to
`0005-contracts.md`):

- `~/.board-superpowers/credentials.yml` (chmod 600)
- `BOARD_SP_AUDIT_DB_URL` env var

**Audit-entry schema (draft).** Final shape is finalized in
`0005-contracts.md`; the entity-level home of the schema is
[`0003-domain-model/03-aggregates-and-entities.md` § 3.3.8
AuditTrail aggregate](../0003-domain-model/03-aggregates-and-entities.md);
the v1 minimum is:

| Column | Type | Notes |
|--------|------|-------|
| `timestamp` | TIMESTAMPTZ | when the entry was written |
| `project` | TEXT | e.g. `owner/repo#projectNumber` |
| `session_id` | TEXT | the CC / Codex session originating the action |
| `actor_role` | ENUM(`producer`, `consumer`) | which role acted (lowercase per 0002 / 0003 / 0005 — see C1) |
| `action_id` | SMALLINT | matrix row 1–14 from §3 above |
| `payload` | JSONB | action-specific data (card id, before/after status, proposal text, etc.) |
| `outcome` | ENUM(`success`, `failure`, `escalated`, `rejected`) | terminal state of this action |

## Consequences

**What this enables:**

- **F-3 (today's dispatch recommendation) is reachable.** Matrix
  row 13 (Dispatch Consumer = A) is the precondition; without it
  Producer would have to interrupt the architect for every
  dispatch and the routine collapses into approval theater.
- **F-5 (overnight batch dispatch) is reachable.** Same row 13
  precondition, plus the audit log makes overnight runs auditable
  the next morning without trusting Producer's narrative.
- **F-7 cadence-driven retro / weekly report triggering is
  reachable.** Matrix row 14 (Auto-trigger = A) is the
  precondition. Combined with ADR-0007's preflight-piggyback
  idiom, the architect gets retros on cadence without scheduling
  ceremony.
- **Trust growth has a ratchet.** R → A promotion via
  `autonomy_overrides:` lets architects loosen the boundary as
  their confidence in Producer rises, without re-litigating the
  framework.

**What this constrains:**

- **Every Producer feature spec MUST explicitly map its
  sub-actions to matrix rows.** A spec that describes
  "Producer does X" without naming the row(s) X corresponds to is
  incomplete and must not ship.
- **All A-class actions require an audit-log write.** If the
  audit DB is unavailable, A actions degrade to R (escalate to
  the architect) as the fallback. The system stays usable when
  the DB is down; it loses the autonomy gain that A buys.
- **All R-class actions require a "propose draft + await
  approval" UX.** In CC / Codex plugin form this means Producer
  must carry approval state across the architect's next prompt.
  The tech-stack layer (`0004-component-architecture.md`,
  `0005-contracts.md`) MUST verify that CC and Codex sessions
  support this carry-over before any R-class action ships.

**What this rules out:**

- Default audit-log persistence to local files, card comments, a
  dedicated audit issue, or any other public/in-repo target.
- A fixed N (no-go) class at v1 — the architect is the final
  authority, not the plugin.
- Silent contract drift in the matrix. New action → new row,
  with explicit A/R classification routed through the triage
  rule, in this ADR or a supersession.

**Trade-off explicitly registered.**

BYO RDBMS adds onboarding friction. Architects must provision
Postgres or MySQL before A-class autonomy unlocks. The fallback
(no DB → all A degrade to R) keeps the plugin usable but chattier
during pre-DB use. This trade-off is deliberate. The alternatives
— default local SQLite, default `.log` file, default audit issue
— each violate either P4a (local persistent state owned by the
plugin), P7 (we ship taste-defaults instead of mechanism), or the
"not public" rule (audit trail bleeds project-internal decisions
to anyone with repo read access). The friction is a feature: it
forces the architect to make an explicit decision about where
their audit trail lives.

## Alternatives considered

**All-A (Producer auto-executes everything).** Rejected: violates
"architect retains merge" (matrix row 12) and "source of truth
must be human-edited" (rows 4 and 10). Also makes the plugin
indistinguishable from a Devin-shaped hosted-control-plane bet,
contradicting `0001-positioning.md` P2a.

**All-R (Producer proposes, architect approves everything).**
Rejected: violates P1; F-5 (overnight batch) becomes structurally
impossible because every dispatch needs a synchronous prompt; the
plugin reduces to a fancier `gh` wrapper.

**Hardcoded matrix without an evolution clause.** Rejected:
blocks the realistic trust-growth path. After 3 months on a
project, an architect may rationally want WIP-tuning (already A)
plus, say, automatic "Backlog → Ready" promotion to be promoted
in scope. With no override path, every architect lives at
month-1 trust forever.

**Audit log to local file (`.board-superpowers/audit.log`).**
Rejected: violates "not local, not in repo." A `.gitignore` entry
hides it from commit but doesn't change that durable plugin-owned
state lives next to the project — exactly the anti-pattern P4a
forbids.

**Audit log to GitHub card comments.** Rejected: violates "not
public." Anyone with repo read access reads Producer's internal
decision log, including escalation drafts that may name
unresolved disagreements.

**Audit log to a dedicated audit issue.** Rejected: same "not
public" violation, plus the issue grows unboundedly and turns
the issue tracker into an event store it isn't designed for.

**Allow SQLite as a BYO option.** Rejected: SQLite is file-based
and re-introduces the local-persistence anti-pattern under a new
name. The whole point of BYO RDBMS is to push durable state out
of the project tree onto infrastructure the architect owns
explicitly.

## Notes

- The 14-row matrix is the v1 contract surface for autonomy. It
  is **not** an exhaustive list of everything Producer ever does
  — some actions (reading the board, summarizing, drafting prose
  output) don't mutate state and don't need a row. The matrix
  lists every action that mutates GitHub state, plugin config,
  or session lifecycle.
- N=0 at v1 should be re-examined at the 6-month mark together
  with the P2a / P4a falsification check (ADR-0005). If experience
  surfaces a class of actions the architect *never* wants Producer
  to be able to perform under any override (e.g., force-pushing
  to `main`), N=1+ becomes a real category and this ADR gets
  superseded.
- The audit-log schema's `payload` JSONB column is intentionally
  loose at v1. As Producer features stabilize, the per-`action_id`
  payload shapes will be hardened so post-hoc analysis doesn't
  require parsing freeform JSON. Entity-level placeholder lives at
  [`0003-domain-model/03-aggregates-and-entities.md` § 3.3.8
  TBD-3](../0003-domain-model/03-aggregates-and-entities.md);
  the contract finalizes in `0005-contracts.md`.

## Related

- ADR-0005 — v1 BoardAdapter contract surface (the audit-log DB
  config integration point lands in `0005-contracts.md`, alongside
  the BoardAdapter contract)
- ADR-0007 — Plugin-runtime-derived constraints (the preflight
  piggyback idiom that makes matrix row 14 implementable)
- `MULTI_AGENT_DEVELOPMENT.md` — operationalizes matrix row 13
  (Dispatch Consumer = A) for the Mode-2 path; documents which
  CC / Codex subagent primitives exist, which are experimental,
  and which Mode-2 must NOT depend on for correctness
- `0001-positioning.md` P1 (architect attention is scarce), P4a
  (truth-source belongs to the user), P7 (meta-methodology, not
  opinionated configuration) — the three premises this ADR
  operationalizes
- `0002-product-features-and-flows/03-producer-surface.md` F-3,
  F-5, F-7 — the features whose spec MUST cite this ADR's matrix
  rows
- [`0003-domain-model/`](../0003-domain-model/README.md) —
  AuditTrail aggregate (§ 3.3.8) carries the audit-entry schema
  at entity granularity; `AuditEntry.Written` domain event is
  catalogued in § 3.4.12.
- `0005-contracts.md` (stub) — `autonomy_overrides:` schema and
  `BOARD_SP_AUDIT_DB_URL` mechanism finalize here
