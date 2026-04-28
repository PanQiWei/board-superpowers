# Domain model

> Entity-level vocabulary for board-superpowers — what the
> things ARE that every Producer feature, Consumer feature, hook,
> script, and skill manipulates. This is the contract a
> maintainer can read to know what cannot be true at the same
> time, and where every entity physically lives (GitHub Issue,
> filesystem path, RDBMS row, in-memory session, claim branch).
>
> **Audience.** Future maintainers asking "what is a Card / Claim /
> ConsumerLogical / RoutingBlock / AuditEntry" and "which other
> documents are the source of truth for the contract that names
> this thing." Clarity for navigation > academic completeness.

---

## Status

**Spec.** Tracks 0002 features and the accepted ADRs. Where 0002
or an ADR has the canonical contract, this directory **points**
to it; we do not duplicate. Where 0003 is the source of truth
(ubiquitous-language alphabetization, aggregate boundaries,
domain-event registry), the relevant sub-file says so explicitly.

When `skills/board-protocol/SKILL.md` and this directory disagree,
**this directory wins**. `board-protocol` is a SKILL (model-facing
runtime instructions); 0003 is design. SKILL changes that imply a
model change land here first.

---

## What 0003 is — and is NOT

**0003 IS:**

- An **alphabetized term registry** other docs link back to
  ([`01-ubiquitous-language.md`](./01-ubiquitous-language.md)).
- A small set of **bounded contexts** mapping entities → owners →
  protocol layers ([`02-bounded-contexts.md`](./02-bounded-contexts.md)).
- A list of **aggregates** (root + member entities + value objects),
  each pinned to its **physical artifact** — a GitHub Issue, a
  Project v2 item, a filesystem path, an RDBMS row, or a git ref
  ([`03-aggregates-and-entities.md`](./03-aggregates-and-entities.md)).
- A **domain-event** registry — the state-changing moments that
  cross aggregate boundaries
  ([`04-domain-events.md`](./04-domain-events.md)).
- Lightweight **mermaid** ER + state + sequence diagrams
  ([`05-relationships.md`](./05-relationships.md)).
- A **context map** — how the bounded contexts communicate, in plain
  prose ([`06-context-map.md`](./06-context-map.md)).

**0003 is NOT:**

- ❌ A tactical-DDD code blueprint. There is **no Repository,
  Factory, Service, Specification, AntiCorruptionLayer, Domain
  Service, Application Service, Adapter pattern** in 0003. The
  plugin is bash + skill-markdown + GitHub artifacts; OO-code
  patterns do not map.
- ❌ UML class diagrams (boxes-with-attributes-and-methods). Mermaid
  ER + state diagrams cover everything we need; class diagrams
  would invite the OO-code patterns 0003 explicitly refuses.
- ❌ Field-level types (string vs varchar vs text). The actual
  shapes are in `state.yml` examples (§1.5), in
  `card-schema.md`, and in ADR-0006 §5 audit-entry table; 0003
  links to them.
- ❌ A speculative "future enterprise extension" surface. YAGNI per
  §1.5 cross-cutting principles. Anything not in v1 spec is either
  marked TBD with a one-line rationale or omitted.
- ❌ A duplicate of 0002. Where 0002 names a feature's behavior,
  0003 names the entity that feature operates on. The two are
  reference partners, not redundant.

---

## Reading order

Navigator. Each file is single-topic; read top-down on first pass,
then jump back via term-registry links.

| File | Coverage |
|------|----------|
| [`01-ubiquitous-language.md`](./01-ubiquitous-language.md) | Alphabetical glossary — single source of truth for terms used across docs and skills. Every term cites where the canonical detail lives. |
| [`02-bounded-contexts.md`](./02-bounded-contexts.md) | Five bounded contexts: Board / Session / Bootstrap / Audit / Spec. Each context names its scope, owned entities, and which other contexts it talks to. |
| [`03-aggregates-and-entities.md`](./03-aggregates-and-entities.md) | Aggregates with root + members + value objects + invariants + physical-storage location. The meat. |
| [`04-domain-events.md`](./04-domain-events.md) | State-changing events that cross aggregate boundaries — emitter, trigger, payload shape, observers. |
| [`05-relationships.md`](./05-relationships.md) | Mermaid ER diagram + state diagrams for Card / ConsumerLogical / PR + a Mode-2 suspend-and-wake-up sequence diagram. |
| [`06-context-map.md`](./06-context-map.md) | How the bounded contexts communicate. Mostly Customer-Supplier through GitHub artifacts; a small Anti-Corruption Layer at the Kanban Protocol projection seam (per ADR-0012; the v1 GitHubProjectAdapter is the first projection). |

---

## Cross-cutting conventions

Three reading conventions to keep 0003 consistent with 0002:

- **Term casing.** **Card**, **Producer**, **Consumer**, **Architect**,
  **Manager**, **Implementer**, **AuditEntry**, **HostManifest**,
  **RepoState**, **RoutingBlock**, **BlockHash**, **ClaimMarker** are
  capitalized when used as proper-noun entities. Lowercased forms
  ("a card", "the consumer") refer to the everyday concept.
- **Linking direction.** When a term has a deeper home (an ADR, a
  §1.x section, a script header), 0003 links **out**. The glossary
  is the navigation hub, not the canonical detail.
- **Invariants stay where they were declared.** I-1..I-13 live in
  `0002-product-features-and-flows/07-cross-cutting-invariants.md`;
  0003 references them by ID at the right aggregate, and 0002's
  invariant entries pick up an inline `Aggregate: <name>` annotation
  pointing back here.

---

## Related

- `0001-positioning.md` — premises (especially P5 distribution stays
  minimal, P7 meta-methodology). Every aggregate's "physical
  location" choice respects these.
- `0002-product-features-and-flows/` — the catalog of behaviors that
  operate on the entities here.
- `0004-component-architecture.md` (stub) — runtime topology that
  realizes these entities.
- `0005-contracts/` — finalizes the Kanban Protocol top-level
  contract (`00-kanban-protocol.md`, anchored by ADR-0012;
  rescopes ADR-0005's BoardAdapter to the v1 projection),
  the `autonomy_overrides:` schema, and the
  `BOARD_SP_AUDIT_DB_URL` mechanism (all touched here at
  entity granularity).
- `0006-failure-modes.md` (stub) — failure modes named in entity
  terms (e.g., "ghost claim" = ClaimMarker without ConsumerProcess).
- `adr/` — architectural decisions; 0003 entities track them
  one-for-one (ADR-0001/0005 → BoardAdapter, now rescoped per
  ADR-0012 to v1 GitHubProjectAdapter projection; ADR-0012 →
  Kanban Protocol top-level contract + Card.key + branch
  naming; ADR-0002 → ClaimBranch + ClaimMarker; ADR-0003 →
  Worktree; ADR-0006 → AuditEntry + AutonomyOverride;
  ADR-0007 → PreflightSnapshot; ADR-0009 → Audit substrate
  SQLite allowance).
- `PLUGIN_DEVELOPMENT.md` — which entities are platform-given vs
  plugin-owned (e.g., session transcripts are platform-owned;
  routing blocks are plugin-owned-within-marker-pair).
- `MULTI_AGENT_DEVELOPMENT.md` — Mode-1 vs Mode-2 contracts; the
  ConsumerLogical-vs-ConsumerProcess split in
  `03-aggregates-and-entities.md` is shaped by that doc.
- `skills/board-protocol/SKILL.md` — the runtime-model contract for
  Card schema + state machine + branching + WIP. When 0003 and
  board-protocol disagree, **0003 wins**; board-protocol is a
  SKILL (instructions), not a design spec.
- `skills/decomposing-into-milestones/references/card-schema.md` —
  canonical Card body schema; 0003's Card aggregate references it
  rather than duplicating.
