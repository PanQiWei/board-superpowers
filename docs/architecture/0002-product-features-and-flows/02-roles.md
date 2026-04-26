### 1.2 Roles

This section defines one thing: **the role of the session's master
agent with respect to the kanban**. It does NOT define what kind
of agent the master is in general — a Claude Code or Codex CLI
session's master agent can carry other specific roles
(orchestration, specialist work, review, ...) on top of its
kanban-relative role; those other roles are out of scope here.

With respect to the kanban, every session's master agent is in
exactly one of two roles. **The distinction is purpose, not
literal I/O direction** — both roles read and write; what differs
is what the session ultimately delivers.

- **Producer** — purpose is **to result in new items being added
  to the kanban, and to keep the kanban in a state where it can
  keep receiving items cleanly.** Originating new items is the
  obvious case; reshaping existing items (e.g., splitting one L
  card into four S cards) and management operations (lint,
  stale-claim cleanup, orphan removal) also belong here, because
  the net effect of all of them is "the kanban as a writable
  artifact stays healthy and ready to keep accepting new work."
- **Consumer** — purpose is **to complete or resolve exactly one
  item on the kanban.** The session's defining outcome is "this
  one item is now Done — or it is rejected with the reason
  captured back onto the kanban." Reading other items for context
  is fine; mutating one's own item's status is required; touching
  anyone else's item belongs to a different session.

The two roles never blend within one session — one session = one
master agent = one kanban-relative role for the lifetime of the
session. The same human architect can drive sessions of either
role (and typically does, daily); they just don't multiplex
within a single session.

**Sources and original framings (which parts are encoded canon
vs proposed by board-superpowers).**

- **Pull-system framing** for the Producer / Consumer split: the
  upstream-feeder vs downstream-puller distinction sits inside
  Anderson, *Kanban* (2010), ch. 1 & 8 — every kanban system has
  both. We name them by *purpose* (writes-to-kanban vs
  completes-one-item) rather than by *station* (upstream vs
  downstream) because in AI orchestration the station metaphor
  maps misleadingly to model types rather than session intent.
- **Producer's maintenance scope** (lint, stale-claim cleanup,
  orphan removal) is the operational analog of TPS *kaizen*
  (continuous worker-driven process improvement) and *jidoka*
  (stop-the-line on detected defect). See Ohno, *Toyota
  Production System* (1988), ch. 2.
- **Consumer's "this one item is now Done"** is the per-Card
  layer of Definition of Done per *Scrum Guide* 2020; the
  per-Card contract is encoded in §1.8 (PR contract).
- **Original framings** (board-superpowers, in the Part C
  "no peer-reviewed methodology for AI-orchestration" gap of
  `docs/research/agile-best-practices.md`):
  - **"Producer" / "Consumer" as role labels** — canonical
    Kanban names workers by station; we name by purpose
  - **One session = one master agent = one kanban-relative role
    for the lifetime of the session** — canonical Kanban does
    not enforce role lock per worker over time; the lifetime
    invariant is new
  - **Layered roles** — kanban-relative role (this section)
    plus other specific roles (orchestration, specialist work,
    review) layered on top — canonical methodology does not
    separate these two layers explicitly

