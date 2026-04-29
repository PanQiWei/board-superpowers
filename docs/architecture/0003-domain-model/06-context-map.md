## 3.6 Context map

How the five bounded contexts (`02-bounded-contexts.md`)
communicate. Honest scope: most context-to-context
communication in board-superpowers is **Customer-Supplier
through GitHub artifacts** — the board is the medium of every
inter-context signal that isn't pure file-on-disk read. Strategic
DDD's richer relationship vocabulary
(Conformist, Shared Kernel, Anti-Corruption Layer, Open Host
Service, Published Language) is used **only where it genuinely
clarifies a seam**, not as decoration.

The map below is intentionally lean — six edges total, four of
them Customer-Supplier through GitHub. The two non-trivial seams
are: (a) the Kanban Protocol projection (Anti-Corruption Layer)
between Board context's logical layer and the backend substrate
(GitHub Project v2 today; Linear / Jira / future via their own
projections per ADR-0025), and (b) the routing-block-marker pair
between Bootstrap context and the host platform's CLAUDE.md /
AGENTS.md surface.

---

### 3.6.1 Edge inventory

| # | From → To | Pattern | Channel | Notes |
|---|-----------|---------|---------|-------|
| 1 | Bootstrap → Board | Customer (one-shot at F-B2) | Kanban Protocol `read_board` (status-options validation) — v1 GitHubProjectAdapter projection realizes via `BoardAdapter.get_status_options` | Bootstrap calls Board once to confirm the backend has all six canonical Status options (or a fold-table mapping to them per the custom-state folding rule). |
| 2 | Session → Board | Customer (continuous) | Kanban Protocol actions (`read_board` / `read_card` / `transition_card` / `create_card` / `claim_card` / `release_claim` / `link_pr_to_card` / `comment_on_card`) — v1 GitHubProjectAdapter projection realizes via `gh` CLI + `git push` (claim branch) | The dominant edge in v1. Every Producer + Consumer feature reads or writes Board context this way. |
| 3 | Session → Bootstrap | Customer (read-only) | Filesystem read of `state.yml` / `config.yml` at session start | `using-board-superpowers` Step 1; `consuming-card` Step 0. |
| 4 | (any) → Audit | Customer (write-only) | RDBMS INSERT into the BYO database | Every D-AUTONOMY-1 action writes an `AuditEntry`. Audit context is sink-only — never feeds back into other contexts' live decision loop. |
| 5 | Session → Spec | Customer (read-only) | Filesystem read of repo-relative path / third-party storage GET | Consumer F-C2 fetches; Producer F-08/F-09 references. |
| 6 | Board ↔ backend substrate (GitHub Project v2 today; Linear / Jira / future) | **Anti-Corruption Layer** = Kanban Protocol projection | v1 GitHubProjectAdapter (Form A: bash + `gh project` / `gh issue` / `gh pr`); future Form B (plugin-shipped MCP server) / Form C (REST/GraphQL) projections per ADR-0025 | The translation layer between board-superpowers' canonical Kanban Protocol vocabulary and the backend's native taxonomy. Protocol contract: `0005-contracts/00-kanban-protocol.md`. v1 projection contract: ADR-0005 (rescoped). |

Two more relationships exist conceptually but don't warrant
their own row in the table:

- **Bootstrap ↔ host platform** (Claude Code / Codex CLI). The
  routing block in `CLAUDE.md` and `AGENTS.md` is a **Published
  Language** of sorts — both platforms agree on the marker
  format `<!-- board-superpowers:routing -->` /
  `<!-- /board-superpowers:routing -->` and the verbatim block
  body inside it (I-10 mirror rule). The plugin's contract with
  the host is "the host auto-loads the file, finds the block,
  and treats the prose as model-facing instructions." The
  `BlockHash` mechanism (`03-aggregates-and-entities.md` §
  3.3.6) enforces the boundary at upgrade time.
- **Mode-2 Producer ↔ Consumer** within the Session context.
  This is intra-context communication, not cross-context — both
  ProducerSession and ConsumerLogical live in Session. The
  primary channel under Mode-2 is the same Board-mediated
  card-thread comment that Mode-1 uses (per
  `MULTI_AGENT_DEVELOPMENT.md` § 1); the optional `SendMessage`
  channel is a CC-only latency optimization. No new context
  edge needed.

---

### 3.6.2 Why Customer-Supplier dominates

Five of the six edges are Customer-Supplier (one context calls
the other; the supplier exposes a stable surface; failures
return well-typed errors). The pattern dominates because
board-superpowers' substrate commitments make every cross-
context interaction a one-way request:

- **Board context exposes the Kanban Protocol** to Bootstrap
  and Session through whatever projection the backend ships.
  Consumers of Board never assume Board's internal shape;
  they reason in protocol terms and dispatch to the active
  projection (the v1 GitHubProjectAdapter for github-project-v2).
- **Audit context is a write-only sink** — write-only Customer-
  Supplier with the additional discipline that nobody reads back
  into the live loop.
- **Spec context exposes static files**. Consumers request a
  path; Spec returns content. No mutation from board-superpowers
  side.
- **Bootstrap context's state files** are read by Session at
  session start. One-shot at-startup contract; no realtime
  channel.

The pattern's symmetry is what makes the plugin
backend-portable in principle — swap in a different Kanban
Protocol projection (a new Form A / B / C realization for a
new backend), and the Customer-Supplier shape across edges
1, 2, and 6 stays the same; only the supplier's internals
change.

---

### 3.6.3 The Anti-Corruption Layer — Kanban Protocol projection

The single edge in board-superpowers that genuinely warrants
the **Anti-Corruption Layer** (ACL) name. Strategic-DDD ACL
shape: a translation layer that prevents one context's
vocabulary from leaking into another.

Per ADR-0025 the ACL is reframed: it is **the per-backend
projection of the Kanban Protocol**
(`0005-contracts/00-kanban-protocol.md`). The protocol is the
canonical mental model — eight actions, six canonical states,
the Board / Card / Status / Claim / PR Link / Label / Comment
ontology, the `Card.key` opaque identifier, the
`claim/<key-slug>-<title-slug>` branch-naming convention.
**The projection IS the ACL**: each backend (GitHub Project v2
today; Linear / Jira / future) ships a projection — Form A
bash CLI, Form B plugin-shipped MCP server, Form C REST/GraphQL
— that translates between the protocol's canonical vocabulary
and the backend's native API. ADR-0005's five-method
`BoardAdapter` surface remains valid AS the v1
GitHubProjectAdapter implementation projection (Form A,
bash + `gh` CLI), not as a universal contract every adapter
must implement.

**What the projection translates:**

- Canonical `Status` enum
  (`Backlog | Ready | In Progress | In Review | Done | Blocked`)
  ↔ backend-native status names (GitHub Project v2 single-
  select option names; future Linear / Jira native columns,
  with the custom-state folding rule from
  `0005-contracts/00-kanban-protocol.md` § State machine).
- Canonical `Card` value object ↔ backend-native issue+project
  item shape; canonical `Card.key` opaque identifier ↔
  backend-native key (GitHub issue number `42`; Linear
  `eng-42`; Jira `proj-42`).
- Canonical action contracts (`read_board`, `read_card`,
  `create_card`, `transition_card`, `claim_card`,
  `release_claim`, `link_pr_to_card`, `comment_on_card`) ↔
  backend-native operations. The v1 GitHubProjectAdapter
  realizes these via the five ADR-0005 methods + claim push +
  PR link conventions; future projections realize them via
  whatever transport fits their backend.
- Canonical `Result[T]` + `ErrorKind` enum
  (`not_found | permission | rate_limit | conflict |
  schema_mismatch | transport`) ↔ backend-native error
  payloads (`gh` exit codes, REST error JSON, etc.). Per
  ADR-0025 the `Result[T]` shape belongs to ADR-0005's
  Form A projection; alternative projections are NOT bound
  to it.
- Canonical `ProjectRef` ↔ backend-native project handle
  (`OWNER/NUMBER` for GitHub Project v2 per ADR-0005; per-
  projection parser for others).

**What the projection deliberately does NOT translate** (per
the protocol's "out of scope at v1" list and ADR-0005 § Out
of scope at v1):

- Backend-specific affordances (Linear's cycles, Jira's
  custom workflows, GitHub's draft items, native richer
  label semantics like Linear team-vs-workspace). These
  either fold to canonical at the projection layer or stay
  backend-internal — they MUST NOT leak into agent-visible
  vocabulary.
- Backend-specific identifiers like `gh_pr_number` field on
  `Card`. The projection keeps backend-internal identifiers
  internal.

**Why this seam matters:** the projection-as-ACL is what makes
ADR-0001's pluggable-backend commitment + ADR-0025's
multi-projection commitment falsifiable. Without it, every
new feature would tunnel a `gh`-shaped assumption into Board
context, and the second-projection cost would balloon. With
it, the second projection is a self-contained translation
problem — the agent always reasons in protocol terms.

At v1 the projection is the only place in the codebase where
backend-specific code lives; the GitHubProjectAdapter wrapper
port (ADR-0005 § Consequences, re-anchored by ADR-0010)
consolidates the existing `gh`-bound scripts behind it.
Future Form B (MCP-server) projections — Linear via the
official Linear MCP server, Jira via Atlassian Remote MCP —
are recognized as valid projection shapes by ADR-0025; they
do NOT inherit ADR-0005's bash-CLI shape.

---

### 3.6.4 Map summary diagram

A single picture of the inter-context wiring.

```mermaid
flowchart LR
    subgraph Bootstrap[Bootstrap Context]
        HM[HostManifest]
        RS[RepoState]
        RC[RepoConfig]
    end

    subgraph Session[Session Context]
        PS[ProducerSession]
        CL[ConsumerLogical]
    end

    subgraph Board[Board Context]
        Card[Card]
        PR[PullRequest]
    end

    subgraph Spec[Spec Context]
        SP[SpecPointer collection]
    end

    subgraph Audit[Audit Context]
        AT[AuditTrail]
    end

    Adapter[Kanban Protocol projection\n(Anti-Corruption Layer)\nv1: GitHubProjectAdapter]:::acl

    Bootstrap -->|edge 1\nstatus-options validation once at F-B2| Adapter
    Session -->|edge 2\nprotocol actions\ncontinuous| Adapter
    Adapter -.->|translates to| Board

    Session -->|edge 3\nread state.yml + config.yml\nat session start| Bootstrap

    Bootstrap -->|edge 4| AT
    Session -->|edge 4| AT
    Board  -->|edge 4| AT

    Session -->|edge 5\nread thin-pointer| Spec
    Card -.->|references| Spec

    classDef acl fill:#fef3c7,stroke:#92400e,stroke-width:2px
```

Reading the picture:

- **Edge 4 fans in to AuditTrail** from every context. That is
  the "audit-log uniformity" invariant I-8 visualized — same
  schema, every actor.
- **The Kanban Protocol projection box is the only
  `flowchart` node not contained in any context's
  subgraph.** That placement reflects its role: it doesn't
  *belong* to either side of the seam; it IS the seam.
  (Strategic-DDD ACLs are conceptually "owned by the
  downstream side" — the consumers depending on the canonical
  vocabulary — so in a stricter rendering this would live
  inside Board context. Drawing it as a free-standing box
  highlights the translation function. The protocol document
  is the canonical vocabulary; each projection — v1
  GitHubProjectAdapter via Form A; future Linear / Jira via
  Form B / C per ADR-0025 — implements that vocabulary on
  one backend.)
- **Spec is a thin participant.** Card.body references; Session
  reads. Nothing else interacts with Spec. That thinness is
  by design — board-superpowers refuses to grow opinions
  about spec format / location / quality (P7).

---

### 3.6.5 Forces of change

What would force the map to grow:

- **Adding a second Kanban Protocol projection** (Linear,
  Jira; per ADR-0025 also free to choose Form B MCP-server
  shape over Form A bash CLI). No new edge; the projection-
  as-ACL accepts a new implementation behind the protocol.
  The map shape stays identical. (This is the architectural
  payoff of the ACL.)
- **Adding multi-kanban support** (one repo with multiple
  boards — flagged in ADR-0025 as a v1.x roadmap item).
  Today the Project aggregate is 1:1 with a board; under
  multi-kanban it becomes 1:N. No new context edge — every
  Session-side action gains a board-selection step internal
  to the projection, and the canonical edges 1 / 2 / 6
  stay shape-identical.
- **Adding a second Audit-context backend** (e.g., a shipped
  SQLite adapter for solo architects who refuse Postgres).
  Currently rejected (ADR-0006 § Alternatives considered);
  if accepted via ADR supersession, the edge-4 contract
  surface would need a stable-cross-backend audit-write API.
- **Webhooks / push-shaped change detection from Board.** Today
  Board is poll-shaped (Producer reads on preflight). If a
  future ADR adds webhooks (ADR-0005 § Out of scope at v1
  flags this), a new edge from Board → Session would appear,
  and the C-PLUGIN-2 (no daemon) constraint would need
  re-examination — webhook receivers are daemon-shaped, which
  is exactly what board-superpowers structurally refuses
  today.
- **Splitting Card and PR into separate contexts.** Tempting if
  Linear / Jira PR semantics diverge enough from GitHub's;
  not a v1 concern. Would add a Customer-Supplier edge
  between the new PR context and the existing Card context.

Each scenario above is a known stretch; none breaks the
current map's logic.

---

### 3.6.6 What this map is NOT

- **Not a deployment diagram.** The map describes logical
  dependencies between bounded contexts; it does not
  prescribe processes, machines, or network topology. The
  plugin runs as a single user-side process tree per
  session; the only "remote" components are GitHub (Board
  substrate) and the BYO RDBMS (Audit substrate).
- **Not a sequence of operations.** Each edge says "context A
  may call context B"; the *order* in which calls happen
  varies by feature (e.g., Manager's daily routine reads
  Board many times per prompt; Consumer's lifecycle reads
  Board once at claim, twice at PR submit, etc.). The
  per-feature sequencing lives in 0002 Part 2 user flows.
- **Not a public surface inventory.** The map shows
  *internal* context-to-context wiring. The public surfaces
  (`scripts/*.sh` exit codes, `check-deps.sh --machine` keys,
  routing-block marker strings, `${CLAUDE_PLUGIN_ROOT}` env
  var, etc.) live in `0005-contracts.md` (when filled) and
  the `docs/architecture/AGENTS.md` change-impact matrix.

The map's job is to make context boundaries argumentatively
visible — to give a future maintainer a one-page check on
"is this new feature crossing a context boundary I should be
careful about?" Anything finer-grained belongs in the
per-aggregate sections of `03-aggregates-and-entities.md`,
the per-event sections of `04-domain-events.md`, or the
per-feature spec in 0002.
