## 3.2 Bounded contexts

board-superpowers' entities split into **five bounded
contexts**. Each context owns a clearly-named slice of the
ubiquitous language, with sharp boundaries on what belongs
inside and what does not. Contexts talk to each other through
**well-defined seams** — usually GitHub artifacts or the
Kanban Protocol projection (the v1 GitHubProjectAdapter at
ADR-0005, anchored by ADR-0012) — never through shared
in-memory state (C-PLUGIN-1).

Why five and not three or seven: each context corresponds to a
*different physical substrate* — git+GitHub artifacts, OS
processes + filesystem, plugin-managed YAML files, BYO RDBMS,
user-owned `docs/` tree. Sharing a context across substrates
would obscure which storage layer owns the data.

| # | Context | Physical substrate | Owned aggregates |
|---|---------|--------------------|-----------------|
| 1 | Board | Kanban Protocol over a backend substrate (v1: GitHub Project v2 + Issues + git refs; future: Linear / Jira via their own projections per ADR-0012) | Card · PR |
| 2 | Session | OS processes + filesystem worktrees | ProducerSession · ConsumerLogical |
| 3 | Bootstrap | Plugin-managed YAML files (`manifest.yml`, `state.yml`) + user-owned `config.yml` | HostBootstrap · RepoBootstrap · RepoConfig |
| 4 | Audit | BYO RDBMS (Postgres / MySQL / SQLite per ADR-0009) | AuditTrail |
| 5 | Spec | User-owned `docs/` tree + third-party storage | SpecPointer (TBD-light) |

The boundaries are drawn so that each context can in principle
be **replaced by a different substrate** without touching the
others — Board context already has a contract (the **Kanban
Protocol** at `0005-contracts/00-kanban-protocol.md`, anchored
by ADR-0012; v1 GitHubProjectAdapter at ADR-0005 is the first
projection of that protocol) that makes this concrete; Audit
context's BYO-RDBMS choice has the same shape (Postgres OR
MySQL OR SQLite per ADR-0009 OR future contributor target).
The other three contexts are glued to their substrates by
ADRs (ADR-0002 / ADR-0003 for Session; §1.5 for Bootstrap;
I-9 + thin-pointer for Spec) but the boundary still lets each
evolve independently.

---

### 3.2.1 Board context

**Scope.** Everything about *what work exists, what state it's
in, who claims it, and what PR resolves it.* The board IS the
state (P4a) — this context owns that state's logical shape.

**Owned aggregates.**

- **Card** — the leaf work item; root of the Card aggregate
  (`03-aggregates-and-entities.md` § Card).
- **PR** — the Pull Request a Consumer opens to resolve a Card;
  its own aggregate because its lifecycle (review-cycle
  iteration, mandatory section structure, auto-close-on-merge)
  is independent of the Card's status transitions.

**Physical substrate.** Accessed through the **Kanban
Protocol** (`0005-contracts/00-kanban-protocol.md`, anchored
by ADR-0012); the active backend projection translates
protocol actions to the backend's native shape. Under v1's
GitHubProjectAdapter projection (Form A: bash + `gh` CLI;
ADR-0005 — now rescoped per ADR-0012 to "the v1
GitHubProjectAdapter implementation projection") that
resolves to GitHub Project v2 (the Status field + the
project-item linkage), GitHub Issues (Card body + thread),
GitHub Pull Requests (PR body + review threads), and git
refs (`claim/<key-slug>-<title-slug>` branches that host
ClaimMarker commits; `slugify(Card.key) == Card.key` for
GitHub-shape integers, so historical `claim/<N>-<slug>`
branches stay valid). Future Linear / Jira projections
realize the same protocol via Form B (plugin-shipped MCP
server) or Form C (REST/GraphQL).

**Talks to:**

- **Bootstrap context** — receives `ProjectRef` from
  `RepoConfig.kanban.project_ref`; performs Status-options
  validation via the active projection (under v1's GitHub
  projection that is `BoardAdapter.get_status_options` per
  ADR-0005) during F-B2.
- **Session context** — provides Card.status, Card.body
  (thin-pointer to Spec), Card.labels for ConsumerLogical's
  F-C0 / F-C1 / F-C2; receives status transitions via
  `transition-card.sh`.
- **Audit context** — every status transition / Card mutation
  emits a `Card.Status.Transitioned` or sibling domain event
  that lands as an `AuditEntry`.
- **Spec context** — Card.body links into Spec context via
  thin-pointer (I-9); Board context never owns spec content.

**Invariants applying here:** I-1 (one card = one Consumer
session = one PR), I-2 (Producer never touches code; Consumer
never owns merge), I-3 (multi-architect symmetry — no
per-user filtering at the plugin layer), I-6 (soft WIP limit
on `In Progress + suspended + In Review`), I-9 (thin-pointer
card), I-10 (routing-block mirror — only weakly: Card body
schema and PR body schema both rely on marker comments that
have to match downstream tooling expectations).

---

### 3.2.2 Session context

**Scope.** Everything about *the live processes running the
plugin* — Producer or Consumer, Mode-1 or Mode-2, their
worktrees, their preflight snapshots, their suspension and
resumption.

**Owned aggregates.**

- **ProducerSession** — the long-lived Manager session.
  Owns transient PreflightSnapshots; does NOT persist anything
  itself (P4a — no plugin-owned durable state).
- **ConsumerLogical** — the kanban-relative role binding to
  one Card. Owns the persistent ClaimBranch + ClaimMarker +
  Worktree, plus zero-or-more ConsumerProcess incarnations
  (one currently alive at most; multiple sequential during
  Mode-2 wake-ups or crash restarts) and an optional
  SuspendState.

**Physical substrate.** OS processes (CC or Codex CLI),
git worktrees on local disk
(`$HOME/.config/superpowers/worktrees/...` by default),
the platform's session-transcript files
(`~/.claude/projects/...jsonl`,
`~/.codex/sessions/.../rollout-*.jsonl`),
and the per-Card `docs/board-superpowers/plans/card-<N>.md`
plan brief (gitignored, Consumer-owned).

**Talks to:**

- **Board context** — every meaningful Session lifecycle event
  (claim, in-progress transition, suspend, surface, PR submit,
  termination) writes to a Board-context artifact (claim
  branch push, status transition, card comment, PR creation).
  The board IS the inter-Session signal channel
  (C-PLUGIN-1 workaround a).
- **Bootstrap context** — reads `RepoConfig.project`,
  `RepoConfig.wip_limit`, `RepoState.features_enabled` at
  session start; never writes.
- **Audit context** — emits `AuditEntry.Written` for every
  qualifying action (matrix row 1–14 from ADR-0006 §3 + the
  symmetric Consumer rows from §1.4 cross-cutting principles).
- **Spec context** — F-C2 fetches spec docs via the
  thin-pointer link in Card.body; never mutates them.

**Invariants applying here:** I-1, I-7 (one-card-one-worktree),
I-8 (audit-log uniformity — Producer and Consumer write the
same schema), I-11 (no plugin-owned durable state in repo —
plan brief is the only Consumer-side scratch and is
gitignored), I-13 (claim markers force-committed only to
claim branches, never main).

---

### 3.2.3 Bootstrap context

**Scope.** Everything about *plugin install, per-repo setup,
and version transitions* — the (layer × event) matrix from
§1.5.

**Owned aggregates.**

- **HostBootstrap** — `~/.board-superpowers/manifest.yml` plus
  the host-version-transition lifecycle (F-B1, F-B3).
- **RepoBootstrap** — `~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
  (host-local per I-13) plus the per-`(host, repo)` version-
  transition lifecycle (F-B2, F-B4) plus the RoutingBlockTracker
  + FeatureActivation entities inside.
- **RepoConfig** — `<repo>/.board-superpowers/config.yml`,
  user-editable, hand-tuned. `wip_limit`, `project`, optional
  `autonomy_overrides:` (ADR-0006 §4 project layer).

**Physical substrate.** Plugin-managed YAML files in fixed
locations (per-machine `~/.board-superpowers/`, per-repo
`<repo>/.board-superpowers/`), routing-block-bearing files
in the project root (`CLAUDE.md`, `AGENTS.md`), the plugin's
own `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`
(version source of truth), and the per-version changelog
files at
`skills/using-board-superpowers/references/changelog/v<X>.md`.

**Talks to:**

- **Board context** — performs Kanban Protocol Status-options
  validation exactly once during F-B2 to confirm the backend
  has all six canonical Status options (or a fold-table per
  the protocol's custom-state folding rule). Under v1's GitHub
  projection this is `BoardAdapter.get_status_options` per
  ADR-0005.
- **Session context** — every Session reads `RepoConfig` and
  `RepoState.features_enabled` at session start through
  `using-board-superpowers` Step 1.
- **Audit context** — F-B3 / F-B4 writes
  `host_version_transition` / `routing_block_reinjected` /
  `feature_activated` audit entries.
- **Spec context** — none directly. (Bootstrap does not touch
  user spec docs.)

**Invariants applying here:** I-10 (routing-block mirror rule
between source-of-truth `agentsmd-routing.md` and downstream
files), I-11 (plugin-owned vs user-owned region split, with
`block_hash` as the boundary enforcer), I-12 (schema
versioning + lazy migration), I-13 (state files in git,
machine-state files not).

---

### 3.2.4 Audit context

**Scope.** Everything about *who did what, when, and what
happened* — the append-only forensic record of every Producer
and Consumer action.

**Owned aggregates.**

- **AuditTrail** — the append-only stream of immutable
  AuditEntry rows for one project (or globally; precise
  scoping TBD in `0005-contracts.md`).

**Physical substrate.** A relational database the architect
provides — the 6-scheme allowlist is `postgresql://`,
`postgres://`, `mysql://`, `mysql+pymysql://`, `sqlite://`,
`sqlite3://` (ADR-0006 §5 + ADR-0009). SQLite is acceptable
when host-local under
`~/.board-superpowers/repos/<normalized>/audit.db`; SQLite
inside the project tree, bare file paths, card comments, and
dedicated audit issues remain forbidden. Connection details
via `~/.board-superpowers/credentials.yml` (chmod 600) or
`BOARD_SP_AUDIT_DB_URL` env var.

**Talks to:**

- **All other contexts** as a write-only sink. AuditEntry is
  the *recording* shape of every domain event; Audit context
  itself never reads back into the live decision loop. Retro
  / weekly-report routines (F-12, F-13) are the only readers,
  and they read from Audit context to produce architect-facing
  prose, not to drive other context's behavior.

**Degradation mode.** If the Audit DB is unavailable, every
A-class action degrades to R-class (ADR-0006 § Consequences).
This is a context-level invariant: no AuditEntry write → no
A-class autonomy. The system stays usable; it loses the
no-prompt autonomy gain.

**Invariants applying here:** I-8 (audit-log uniformity —
Producer and Consumer entries share the schema). The
ADR-0006 §5 schema (`timestamp`, `project`, `session_id`,
`actor_role`, `action_id`, `payload`, `outcome`) is the
canonical contract.

---

### 3.2.5 Spec context

**Scope.** Everything about *spec / plan / design content the
Card body links into* — what F-C2 fetches before delegating
implementation.

**Owned aggregates.**

- **SpecPointer** (lightweight; arguably an entity-collection
  rather than a full aggregate). The set of in-repo or
  third-party-storage paths a Card body's Context section
  links to via the thin-pointer rule. board-superpowers does
  not own the spec content itself; only the *contract that
  the pointer must resolve at claim time* (Producer's Backlog
  → Ready gate, ADR-0006 row 5 precondition).

**Physical substrate.** The user's own `docs/` tree (most
common case at v1) or a third-party storage backend
configured at bootstrap (TBD design — see
`05-bootstrap-surface.md` Notes if it lands). board-superpowers
does NOT prescribe a spec format, location convention, or
storage backend beyond "the link in the Card body must
resolve when the Consumer arrives."

**Talks to:**

- **Board context** — Card.body's Context section links here.
- **Session context** — F-C2 fetches; never writes.

**Invariants applying here:** I-9 (thin-pointer card —
Consumer self-fetches; never re-derives a missing spec).

**Why this is its own context** (despite being thin): keeping
spec ownership outside the Board / Session contexts
preserves P7 — board-superpowers does not ship a spec format
opinion. Conflating Spec into Board would invite the plugin
to start prescribing `docs/specs/` structure, lint rules,
template content; the separation buys the same discipline
the Kanban Protocol + per-backend projection buys for the
Board substrate.

---

### 3.2.6 Why this carving (and not other splits)

Three alternative splits considered and rejected:

- **Splitting Card and PR into separate contexts.** Tempting
  because PR has its own state machine and lifecycle. Rejected
  because both reach the same backend via one Kanban Protocol
  projection (under v1 the GitHubProjectAdapter via the same
  `gh` surface), and PR Link is itself a protocol-level
  concept (`0005-contracts/00-kanban-protocol.md` § Ontology
  / § `link_pr_to_card`). At v1 PR is a Board-context
  aggregate; it remains a candidate for promotion if
  Linear / Jira PR semantics diverge enough later.
- **Folding Audit into Bootstrap** because both are "config-
  shaped" plugin-managed state. Rejected because Audit's BYO
  RDBMS substrate is structurally different from
  Bootstrap's local YAML files, and the failure modes
  (DB-unavailable degradation) belong with Audit's behavior,
  not Bootstrap's. Keeping them separate also makes the
  ADR-0006 §5 contract land in one obvious place.
- **Promoting Decomposition to its own context.** Tempting
  because decomposition (§1.6) has rich rules (INVEST, vertical
  slicing). Rejected because every decomposition output is a
  Card — decomposition is a *behavior* of the Producer role
  (F-09) operating on Board-context entities, not a separate
  ownership domain. The rules that constrain it
  (§1.6.1 INVEST, §1.6.2 vertical slicing) become Card
  aggregate invariants in `03-aggregates-and-entities.md`.

Each rejected split is a path open to a future maintainer if a
real shape change forces it. The current carving is the
smallest set that makes every entity placement obvious.
