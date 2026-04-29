# BOARD_DEVELOPMENT.md — plugin-wide development guide for the board / card / Kanban Protocol layer

> **Required reading** before any work that touches the board layer:
> - Editing the **Kanban Protocol document**
>   ([`docs/architecture/0005-contracts/00-kanban-protocol.md`](./docs/architecture/0005-contracts/00-kanban-protocol.md)).
> - Authoring or modifying the **`board-canon`** atomic SKILL or
>   the **`operating-kanban`** atomic SKILL (shipped v0.5.0).
> - Adding a new **backend projection** (Linear, Jira, others)
>   for the Kanban Protocol.
> - Touching multi-kanban schema, kanban lifecycle states, the
>   eight protocol actions, the six canonical statuses, the Card
>   ontology / hierarchy decision, branch-naming convention, or
>   the claim primitive.
> - Updating any of the spec docs that anchor the protocol
>   (ADR-0001 / 0002 / 0005 / 0025 / 0026 / 0027 / 0001-positioning.md
>   "AI-native concept hygiene" section).

This is the **board-layer-development companion** to
[`SETUP_STAGES_DEVELOPMENT.md`](./SETUP_STAGES_DEVELOPMENT.md).
That guide covers main's setup-stages system (registry +
5-callable contract + agentic config-item protocol). This guide
covers the **runtime side**: how the plugin reads / mutates the
kanban board through a backend-agnostic Kanban Protocol +
per-backend projection. The two systems meet at one bridge —
main's M10 config-item stage writes the kanban backend selection
into `settings.yml`; the `operating-kanban` runtime SKILL
(shipped v0.5.0) reads it. § 7 "Setup-stages bridge" below
documents the seam in detail.

**URL freshness:** all citations verified 2026-04-29.

---

## Table of contents

1. [What "board layer" means and what this guide covers](#1-what-board-layer-means-and-what-this-guide-covers)
2. [Where the source-of-truth lives](#2-where-the-source-of-truth-lives)
3. [Mental model in one page](#3-mental-model-in-one-page)
4. [Anti-patterns — review-rejection list](#4-anti-patterns--review-rejection-list)
5. [Authoring rules](#5-authoring-rules)
6. [Adding a new backend projection](#6-adding-a-new-backend-projection)
7. [Setup-stages bridge](#7-setup-stages-bridge)
8. [AI-native concept hygiene reminder](#8-ai-native-concept-hygiene-reminder)
9. [Common pitfalls](#9-common-pitfalls)

---

## 1. What "board layer" means and what this guide covers

board-superpowers' board layer is the runtime substrate that
reads and mutates the kanban board (today GitHub Project v2;
v1.x roadmap Linear, Jira, others). It is **not** the same thing
as the setup-stages system. Setup-stages is "configure the
plugin"; board layer is "operate the kanban during use."

The board layer's contract surface is the **Kanban Protocol**
(per ADR-0025). The protocol is a *semantic mental model* agents
reason in — eight named actions, six canonical statuses, a small
ontology (Board / Card / Status / Claim / PR Link / Label /
Comment), and identity rules. **It is NOT an SDK** — there are
no function signatures, no parameter lists, no return types. The
protocol is realized on each backend through a *projection*
(per ADR-0025 § Implementation surface):

- **Form A** — bash CLI projection (today's GitHubProjectAdapter).
- **Form B** — plugin-shipped MCP server projection (v1.x roadmap).
- **Form C** — REST/GraphQL projection (also v1.x).

Multi-kanban support, lifecycle states, and the flat-Card
hierarchy stance are layered on top of the protocol per ADR-0026.

This guide applies whenever your work touches:

- The Kanban Protocol document or its semantic contracts
  (8 actions, 6 statuses, ontology, identity, body schema,
  custom-state folding rule).
- A backend projection — adding a new one or revising an existing
  one.
- The `board-canon` atomic SKILL (state machine SPOT) or the
  `operating-kanban` atomic SKILL (backend-projection dispatch
  SPOT, shipped v0.5.0).
- The four molecular SKILLs that consume protocol actions:
  `managing-board`, `consuming-card`, `decomposing-into-milestones`,
  `bootstrapping-repo`.
- The atomic `claim` primitive (`scripts/claim-card.sh`) or its
  branch-naming convention.
- `settings.yml § modules.m10_kanban` schema.
- AI-native concept hygiene anchors (sub-issue, sprint, story
  points, etc. — see § 8 below).

This guide does NOT cover: setup-stages registry / 5-callable
contract / agentic config-item flow — those are in
[`SETUP_STAGES_DEVELOPMENT.md`](./SETUP_STAGES_DEVELOPMENT.md);
plugin manifest / hooks / scripts platform contracts — those are
in [`PLUGIN_DEVELOPMENT.md`](./PLUGIN_DEVELOPMENT.md);
SKILL-authoring discipline (frontmatter, skeleton selection,
testing) — those are in
[`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md).

---

## 2. Where the source-of-truth lives

The board-layer spec is distributed across multiple files. **The
canonical reading order on first pass:**

| Order | File | What it carries |
|-------|------|-----------------|
| 1 | [`docs/architecture/0001-positioning.md`](./docs/architecture/0001-positioning.md) — premises P2a + P2b + § "AI-native concept hygiene" | Why we have a kanban layer at all; what we deliberately refuse (sprint, sub-issue, story points, etc.) |
| 2 | [`docs/architecture/adr/0025-kanban-protocol-as-top-contract.md`](./docs/architecture/adr/0025-kanban-protocol-as-top-contract.md) | Why the contract is protocol-shape, not SDK-shape; ADR-0005 rescoping |
| 3 | [`docs/architecture/0005-contracts/00-kanban-protocol.md`](./docs/architecture/0005-contracts/00-kanban-protocol.md) | The protocol itself — ontology, identity, 8 action contracts, 6 statuses, body schema, custom-state folding, multi-kanban semantics, card hierarchy stance, compliance levels, projection forms |
| 4 | [`docs/architecture/adr/0026-multi-kanban-lifecycle-and-flat-card-hierarchy.md`](./docs/architecture/adr/0026-multi-kanban-lifecycle-and-flat-card-hierarchy.md) | Three coupled v0.5.0+ decisions: lifecycle (5 states); multi-kanban schema (`modules.m10_kanban.kanbans`); flat-Card hierarchy + display-only metadata |
| 4b | [`docs/architecture/adr/0027-m3-dispatch-via-kanban-protocol-projection.md`](./docs/architecture/adr/0027-m3-dispatch-via-kanban-protocol-projection.md) | Supersedes ADR-0022 § M3 capability dispatch; routes capability dispatch through Kanban Protocol projections rather than ADR-0005's SDK-shaped adapter handles |
| 5 | [`docs/architecture/adr/0001-pluggable-board-backend-with-github-project-v1.md`](./docs/architecture/adr/0001-pluggable-board-backend-with-github-project-v1.md) | Substrate-pluggability commitment (ADR rescoped reading note included) |
| 6 | [`docs/architecture/adr/0002-claim-via-branch-push.md`](./docs/architecture/adr/0002-claim-via-branch-push.md) | Atomic claim primitive at git-push layer |
| 7 | [`docs/architecture/adr/0005-board-adapter-contract.md`](./docs/architecture/adr/0005-board-adapter-contract.md) | The v1 GitHubProjectAdapter projection's bash-implementation shape (rescoped per ADR-0025) |
| 8 | [`skills/board-canon/SKILL.md`](./skills/board-canon/SKILL.md) + `references/` | State machine, Card body schema, branch-naming slugifier, WIP counting — the read-only schema authority |
| 9 | [`docs/architecture/0003-domain-model/`](./docs/architecture/0003-domain-model/) — Card / ClaimBranch / ClaimMarker entries; § 3.6.3 ACL | Domain-model anchor; § 3.6.3 reframes the ACL as the per-backend protocol projection |
| 10 | [`docs/architecture/0005-contracts/03-config-schemas.md`](./docs/architecture/0005-contracts/03-config-schemas.md) § "`modules.m10_kanban` block — v0.5.0 planned schema" | Schema for the M10-module kanban registry in `settings.yml` |
| 11 | [`docs/architecture/0005-contracts/05-github-artifact-schemas.md`](./docs/architecture/0005-contracts/05-github-artifact-schemas.md) | The GitHubProjectAdapter projection's artifact contract (Status enum, ClaimMarker shape, PR template marker pair) |
| 12 | [`README.md`](./README.md) + [`README.zh-CN.md`](./README.zh-CN.md) § "Why there's no sprint, no sub-issue, no story points" | Community-facing version of the AI-native concept hygiene argument |

When you change any of these, the
[`docs/architecture/AGENTS.md`](./docs/architecture/AGENTS.md)
spec change-impact matrix tells you which others must be patched
in the same PR.

---

## 3. Mental model in one page

### Protocol vs SDK — the load-bearing distinction

| Aspect | SDK shape | Protocol shape (what board-superpowers uses) |
|--------|-----------|---------------------------------------------|
| **Caller** | Deterministic program reading function signatures | Agent reading SKILL bodies + MCP tool descriptions |
| **Surface** | Function table; types; error enums | Eight named actions; semantic contracts (pre/post/error/idempotency); ontology |
| **Polymorphism** | Compile-time dispatch through types | Runtime adaptation via prompt-text instructions |
| **Cross-backend** | Forces every wrapper into uniform impedance | Each backend ships its own *projection* (Form A/B/C) of the same protocol |
| **Versioning** | Breaking changes via type signatures | Breaking changes via superseding ADR |

ADR-0005 was originally an SDK-shape contract (5 methods +
`Result[T]` + 6 ErrorKinds). ADR-0025 reframes board-superpowers'
top-level contract as a protocol; ADR-0005 is now scoped to "the
v1 GitHubProjectAdapter implementation projection" only.

### The eight actions

`read_board`, `read_card`, `create_card`, `transition_card`,
`claim_card`, `release_claim`, `link_pr_to_card`,
`comment_on_card` (OPTIONAL).

Each is a **semantic contract** with pre/post/error/idempotency.
NOT a function signature. The protocol document is the SoT.

### The six statuses

`Backlog | Ready | In Progress | In Review | Done | Blocked`

Closed enum at protocol level. Backends with richer native
taxonomies fold to canonical via the projection's reference file.
Folding is per-backend (schema) + per-repo (values) — never
per-card.

### Identity & branch naming

- `Card.key`: opaque, display-stable string (GitHub `42`, Linear
  `eng-42`, Jira `proj-42`). NOT parseable.
- Internal Card identity: composite key `(kanban_id, Card.key)`.
- Branch shape v0.5.0+: `claim/<kanban-id>-<key-slug>-<title-slug>`.
- v0.4.x legacy `claim/<key-slug>-<title-slug>` accepted by parser.

### Multi-kanban (per ADR-0026)

A single repo MAY bind multiple kanbans. The kanban registry
lives at `settings.yml § modules.m10_kanban` (per main's M10
config-item stage). v1.0 runtime hard-fails on `kanbans:` list
length > 1 (carve-out); schema reserves the list shape for v1.x.
Cross-kanban Card moves are **forbidden**.

### Card hierarchy — flat at protocol

There is no `Card.parent` field at protocol level. Card relates
to Card only through `depends-on` / `depended-on-by`
(sequencing, not containment). Backend-native sub-issue / sub-
task surfaces as **display-only metadata**:
`display_parent` / `display_children_count` /
`display_hierarchy_path`.

This is grounded in **AI-native concept hygiene** (per
0001-positioning.md § "AI-native concept hygiene"; see § 8
below): sub-issue / sub-task is sibling to sprint / story-points /
burndown — a degenerate human-cadence artifact whose load-
bearing purpose evaporates when implementation throughput goes
100×.

### Claim is git-layer atomic

Per ADR-0002: `git push --force-with-lease=<ref>:` of a
`claim/...` branch IS the distributed lock. The board's status
flip is downstream — the board never needs to provide an atomic
primitive of its own.

(Open spec/impl drift: `scripts/claim-card.sh` currently uses
plain `git push -u`, NOT `--force-with-lease`. Tracked as a
follow-up; race semantics are coincidentally close in the
ref-doesn't-exist case but the explicit-empty-value semantics
is missing.)

---

## 4. Anti-patterns — review-rejection list

If a PR proposes any of the following, it must be rejected
unless it ships with a superseding ADR. These were each
considered, debated, and explicitly rejected in the design
conversation captured in ADR-0025 / 0026 + 0001-positioning.md
"AI-native concept hygiene."

| # | Anti-pattern | Why rejected | Spec anchor |
|---|--------------|--------------|-------------|
| **A1** | Adding `Card.parent` at protocol level (1-level parent-child) | Parent Card is non-claimable → violates I-1 (one Card = one Consumer session = one PR); makes Card two ontologically distinct things at once | ADR-0026 § 3.4 / § Alternatives considered |
| **A2** | Auto-deriving parent status from children | Cross-backend semantics disagree — GitHub parent can close while children open; Linear configurable; Jira workflow-dependent. Protocol cannot normalize | ADR-0026 § 3.4; cross-impact agent finding 7 |
| **A3** | Shipping a "halo Card" or non-claimable Card type | Same as A1 — bifurcates Card concept; halo's purpose (stakeholder visibility) is already served by Thread / Milestone | ADR-0026 § 3.4; codex critique #3 finding 4 |
| **A4** | Introducing or re-introducing sprint, story points, burndown chart, stand-up, sub-task hierarchy | These assume implementation throughput is the bottleneck (human-developer-days). AI cadence inverts that. Each was evaluated against the falsification test in § 8 below | 0001-positioning.md § "AI-native concept hygiene" |
| **A5** | Breaking I-1 invariant (one Card = one Consumer session = one PR) | Multi-card-per-session forces context smearing across cards; parallel Consumers lose isolation | 0002-product-features-and-flows/07-cross-cutting-invariants.md I-1 |
| **A6** | Cross-kanban Card moves at protocol level | A Card belongs to one kanban for its lifetime. "Moving" is retire-on-source + create-on-destination, both R-class audited | ADR-0026 § 2 |
| **A7** | Asymmetric branch naming (single-kanban vs multi-kanban shapes) | Forces every branch consumer (claim-card.sh, ls-remote sweeps, post-merge cleanup) to parse two shapes; migration churn when single→multi happens | ADR-0026 § 2; codex critique #1 D3 |
| **A8** | Auto-creating `depends-on` edges from native sub-issue/sub-task | Sequencing ≠ containment. Auto-edges block child until parent Done — wrong direction; reverse direction (parent waits for all subs) is also wrong since parent isn't claimable | ADR-0026 § 3.2; codex critique #3 D2 |
| **A9** | `hierarchy_mode: flat | one-level | recursive` config knob | Every SKILL would need to branch on hierarchy semantics, defeating the protocol's purpose as a single agent mental model | ADR-0026 § Alternatives considered |
| **A10** | `Card.kind: feature | story | task` enum at protocol level | Imports a methodology taxonomy; overlaps with existing `type:*` labels | ADR-0026 § 3.4 |
| **A11** | Markdown-body `## Parent` section convention as protocol mechanism | Body is user-editable → drift risk; projection metadata fields (`display_parent`) are the canonical mechanism | ADR-0026 § 3.3; codex critique #3 finding 11b |
| **A12** | `parent:#42` labels as protocol-level mechanism | Label churn; duplicates native hierarchy; stale-link risk | codex critique #3 finding 11c |
| **A13** | Promoting display-only metadata fields to protocol-significant | `display_parent` / `display_children_count` / `display_hierarchy_path` are agent-readable for context but MUST NOT participate in transitions, claims, WIP counting, or any state computation. If a future change makes them load-bearing, that's an ADR (and probably the wrong design) | 00-kanban-protocol.md § Card hierarchy |
| **A14** | Direct `gh` calls in skill bodies bypassing the projection layer | Form A projection is bash + `gh` consolidated in `scripts/`; molecular SKILLs (managing-board / consuming-card / decomposing-into-milestones / bootstrapping-repo) should not inline `gh` calls — they MUST go through the projection (today via the existing scripts; v0.5.0+ via `operating-kanban`) | ADR-0025 § Decision; ADR-0026 § Notes |
| **A15** | Treating ADR-0005 as still universal (post ADR-0025) | ADR-0005's contract surface remains valid AS the v1 GitHubProjectAdapter projection's bash-implementation shape. New backend projections do NOT inherit ADR-0005 verbatim — they realize the protocol in whatever shape fits their transport | ADR-0025 § Rescoping ADR-0005 |
| **A16** | Adding a `Card.id` field that exposes backend-native id structure | Protocol identity is `Card.key` (opaque, display-stable, unparseable). Exposing internal backend ids (e.g., GitHub project item id) would force every projection to materialize a uniform shape and would leak GitHub-shape | 00-kanban-protocol.md § Identity |

---

## 5. Authoring rules

### Spec change-impact matrix is the gate

Before merging any board-layer spec change, walk the
[`docs/architecture/AGENTS.md`](./docs/architecture/AGENTS.md)
"Spec change-impact matrix" rows that match. If a row applies,
its right-hand-side files MUST be patched in the same PR. The
relevant rows for board work:

- ADR-0005 BoardAdapter (rescoped projection).
- `0005-contracts/00-kanban-protocol.md` (top-level contract).
- Branch-naming convention `claim/<key-slug>-<title-slug>`.
- `0005-contracts/03-config-schemas.md § modules.m10_kanban`.

### Where to put a new field

| Field's role | Goes in | Examples |
|--------------|---------|----------|
| Protocol-significant (transitions / claims / WIP / state computation read it) | Protocol document § Ontology or § Identity; same-PR add to `board-canon` if it's a schema rule; same-PR add to relevant action contracts | `Card.key`, `Card.status`, `Card.labels` |
| Projection-internal (backend's native field; never agent-visible) | Backend's reference file under `operating-kanban/references/<backend>.md`; NOT in protocol document | GitHub Project item id; Linear cycle id |
| Display-only metadata (agent-readable, never load-bearing) | Protocol document § Card hierarchy (display_*) field block | `display_parent`, `display_children_count` |
| Configuration (architect-set at bootstrap or runtime) | `settings.yml § modules.m10_kanban` schema; same-PR update `0005-contracts/03-config-schemas.md` | `compliance: L0..L3`, `wip_limit_local` |

### Adding a new protocol action

This is rare. To add a 9th action:

1. Demonstrate it cannot be expressed via composition of the
   existing 8.
2. Author a new ADR superseding ADR-0025 § Action contracts (or
   amending it additively if it doesn't break existing
   behavior).
3. Update protocol document § Action contracts with full
   semantic contract (intent / pre / post / failure / idempotency).
4. Update each backend's `operating-kanban/references/<backend>.md`
   with the projection-specific invocation.
5. Add to compliance levels (L0/L1/L2/L3) — which level requires
   the new action?

### Modifying a lifecycle state machine (kanban or card)

Two state machines exist at the board layer; do not confuse:

- **Kanban entity lifecycle** (5 states per ADR-0026): Bound /
  Active / Suspended / Archived / Retired. State transitions
  are R-class.
- **Card status enum** (6 values per the protocol's State
  machine section): Backlog / Ready / In Progress / In Review /
  Done / Blocked.

Adding / renaming / removing a state in either requires a
superseding ADR. Renames cascade to: protocol document; ADR-0026
(if kanban lifecycle); board-canon (state machine SPOT); every
backend's reference file's mapping table.

### Adding a kanban backend

See § 6 below.

---

## 6. Adding a new backend projection

To add Linear / Jira / a custom backend, ship the following in
one PR:

1. **A reference file** at
   `skills/operating-kanban/references/<backend>.md` documenting:
   - Per-action invocation pattern (what shell command, what
     MCP tool, what REST call realizes each of the 8 protocol
     actions on this backend).
   - The **custom-state folding mapping** — backend-native
     statuses to the 6 canonical, with a note for any unfoldable
     native states (which fold to `Backlog` with stderr warning
     per the protocol § Custom-state folding rule).
   - The **markdown ↔ native body conversion** — Linear: native
     markdown ✓; Jira: ADF, document the conversion lossiness.
   - Capability deltas: which optional protocol action
     (`comment_on_card`) is supported?
   - Auth provisioning (`provision_credentials()` sub-contract).

2. **Backend declared in the projection enum** in
   `0005-contracts/03-config-schemas.md § modules.m10_kanban
   field types`. Currently: `github-project-v2`. Adding `linear`
   / `jira` / etc. requires a same-PR reference file (see step 1)
   per the protocol's "second-projection authors" contract.

3. **Bootstrap support** — main's M10 config-item stage
   (`m10.repo.choose-kanban-backend` per ADR-0024) already has
   a `set` callable that persists the backend choice. Adding a
   new backend may need:
   - Schema validation step ensuring the backend has all 6
     required canonical statuses (or a fold mapping).
   - Mandatory-label provisioning step (e.g., `type:*`,
     `size:*`).
   - `provision_credentials()` invocation per backend's auth
     model (token, OAuth, MCP login, etc.).

4. **A capability declaration** in
   `docs/architecture/0005-contracts/adapter-capabilities.md`
   (lands with the first non-GitHub projection — see
   `0005-contracts/00-kanban-protocol.md § What every projection
   MUST provide`'s v1.0 carve-out).

5. **Tests** — at minimum, unit tests for the slugifier on the
   new backend's `Card.key` shape (e.g., Linear `ENG-42` →
   `eng-42`). End-to-end tests against a real backend are
   conditional on whether the backend has a public sandbox.

If the backend has an official MCP server (Linear, Atlassian
Remote MCP for Jira), Form B (plugin-shipped MCP server) is the
expected projection form per ADR-0025. Plugin-platform support
(Claude Code `userConfig.sensitive` for tokens / `Elicitation`
hooks; Codex CLI `codex mcp login` for OAuth) handles auth and
lifecycle without bespoke transport code.

---

## 7. Setup-stages bridge

The board layer is **not** a setup-stages stage. It is a runtime
substrate. But there is a clean seam where setup-stages and the
board layer meet, and getting that seam right matters.

### The seam: M10 writes, operating-kanban reads

```
Setup time (per SETUP_STAGES_DEVELOPMENT.md):
  m10.repo.choose-kanban-backend (ADR-0024 config-item stage)
    → executor: agentic prompt for backend + project_ref
    → persists `modules.m10_kanban.{backend, project_ref}` in
      <repo>/.board-superpowers/settings.yml

Runtime (per ADR-0025 + ADR-0026):
  operating-kanban (atomic SKILL, shipped v0.5.0)
    → reads `modules.m10_kanban.{backend, project_ref, kanbans, ...}`
    → dispatches the 8 protocol actions through the named
      backend's projection
```

Single direction: setup-stages PROVISION; runtime CONSUME. No
back-edges. The runtime SKILL never writes to settings.yml; the
M10 stage never invokes runtime protocol actions.

### What `operating-kanban` is NOT

- **Not a setup-stage.** Setup-stages have lifecycle (`completed`
  / `stale` / etc. per ADR-0013); they are not invoked during
  normal Manager / Consumer operation. `operating-kanban` is
  invoked on every protocol action — that's runtime SKILL
  behavior, not stage behavior. See SETUP_STAGES_DEVELOPMENT.md
  § 4 "Things that look like a stage but are NOT one."
- **Not a replacement for M10.** M10's job is to capture the
  architect's backend choice through the agentic config-item
  protocol (ADR-0023). `operating-kanban`'s job is to dispatch
  protocol actions to whatever backend M10 stored.
- **Not the M10 module's owner.** The
  `modules.m10_kanban.<field>` schema is jointly governed: M10
  stage is responsible for `backend` / `project_ref` /
  `compliance` / writing the initial state. ADR-0026 layers
  `kanbans` (list) + `legacy_claims` on top; `operating-kanban`
  reads all of them at runtime but only the M10 stage / `bind`
  / `migrating-repo-version` write.

### What still needs to be sorted (v0.5.0+ work)

- ADR-0022 § M3 ("BoardAdapter capability dispatch") was authored
  before ADR-0025 elevated the Kanban Protocol. **ADR-0027
  supersedes ADR-0022 § M3** — capability dispatch now flows
  through Kanban Protocol projections rather than ADR-0005's
  SDK-shaped adapter handles. Treat M10's persisted backend
  selection as protocol-projection metadata; routes through
  `operating-kanban`'s backend-selection logic (per ADR-0027 +
  ADR-0026 § Schema), not as ADR-0005-shaped adapter handles.
- The exact shape of the v0.5.0 `migrating-repo-version` skill's
  legacy_claims write (`modules.m10_kanban.legacy_claims`) needs
  alignment with ADR-0017 cross-clone state sharing. ADR-0026
  Branch naming Migration § documents the path; the skill's
  implementation lands in v0.5.0.

---

## 8. AI-native concept hygiene reminder

If a future PR proposes adding a concept to the board layer, run
the **falsification test** from
[`0001-positioning.md`](./docs/architecture/0001-positioning.md)
§ "AI-native concept hygiene":

> Can X carry load that existing AI-native mechanisms
> (continuous flow + INVEST siblings + Thread / Milestone +
> atomic claim + XS/S/M/L) cannot? If not, X is degenerate by
> the same reasoning that removed sprint.

Concepts already removed/refused on this test:

- **Sprint** — replaced by continuous flow + per-PR demo + retro
  from PR Notes.
- **Sub-issue / sub-task** — sibling-degenerate; six historical
  purposes either die outright (decomposition / coordination /
  estimation aggregation / sprint-internal sequencing) or shift
  one level up (visibility / chunking → Thread / Milestone).
- **Story points** — coarse XS/S/M/L only; absolute scale is
  hours.
- **Burndown chart** — WIP + Done counts read directly.
- **Stand-up meeting** — agents don't sync; architect reads PRs.
- **Epic** — replaced by Thread (theme grouping) or Milestone
  (deliverable bucket).

Any PR proposing to add or re-introduce one of these MUST
include an ADR documenting which AI-native mechanism is
insufficient and why. README's "Why there's no sprint, no sub-
issue, no story points" section is the community-facing version
of this argument; the ADR-0026 § 3 + 0001-positioning.md
"AI-native concept hygiene" pair is the spec-level version.

---

## 9. Common pitfalls

### Pitfall 1: confusing protocol semantics with projection mechanics

Protocol says *"`transition_card` moves a card from current
canonical status to another canonical status"*. The mechanism by
which the move happens is projection-internal. GitHub: edit a
field option. Linear: set a workflow state. Jira: fire a
transition by ID. **All three are "transition_card" at protocol
level.** Don't bake projection mechanics into protocol
semantics; don't bake protocol semantics into projection
references (e.g., do not write `gh project item-edit ...` in the
protocol document).

### Pitfall 2: writing in the protocol document

The protocol document is for stable semantic contracts. Anything
mutable (current GitHub field IDs, recently-added Linear
features, evolving MCP tool names) belongs in the projection
reference file. If you find yourself writing implementation
details into the protocol document, you're probably in the wrong
file.

### Pitfall 3: thinking ADR-0005 is dead

ADR-0005 is alive AS the v1 GitHubProjectAdapter projection's
shape. Its 5 methods + `Result[T]` + 6 ErrorKinds are still
authoritative for the bash-side projection. What ADR-0025
changed is interpretation: ADR-0005 is *one* projection's shape,
not *the* universal contract.

### Pitfall 4: trying to make the bridge bidirectional

`operating-kanban` reads M10 state, never writes it. If you find
yourself wanting `operating-kanban` to mutate
`modules.m10_kanban.*`, you are crossing the seam in the wrong
direction. Mutations to that block belong in setup-stages SKILLs
(M10 config-item stage's `set` callable, or
`migrating-repo-version` for v0.4.x → v0.5.0 transitions).

### Pitfall 5: re-litigating the flat-Card hierarchy decision

The flat-Card decision is not "we couldn't agree on hierarchy."
It is grounded in AI-native concept hygiene. Any PR re-opening
this decision must engage the falsification test in § 8 before
proposing changes. Showing that "GitHub has sub-issues GA, so we
should too" is NOT engaging the test — it's a different framing.

### Pitfall 6: forgetting to update the change-impact matrix

The change-impact matrix in
[`docs/architecture/AGENTS.md`](./docs/architecture/AGENTS.md)
captures the cross-document coupling. When you add a new
coupling (e.g., a new field that affects both protocol document
and a SKILL spec), add a row to the matrix in the same PR.

---

## Maintenance discipline for this doc

- All cross-references to spec docs verified **2026-04-29**.
- When ADR-0025 / 0026 / 0027 are amended or superseded, this
  doc must be updated in the same PR.
- When a new backend projection ships, § 6 acquires the new
  backend in its examples; the projection's reference file
  should be linked from § 2.
- This doc is referenced **by name** from the root
  [`AGENTS.md`](./AGENTS.md) "Cross-cutting reference docs"
  table — not loaded with `@`-prefix — so it does not ride into
  every session's context. The
  [`skills/AGENTS.md`](./skills/AGENTS.md) "Board-touching SKILLs
   — additional read" section sends agents here on demand when
  any board-related SKILL is touched.

---

## See also

- [`AGENTS.md`](./AGENTS.md) (root) — board-superpowers developer
  guide; routes board work here.
- [`docs/architecture/AGENTS.md`](./docs/architecture/AGENTS.md)
  — spec governance + change-impact matrix.
- [`SETUP_STAGES_DEVELOPMENT.md`](./SETUP_STAGES_DEVELOPMENT.md)
  — sibling guide for the setup-stages system; § 7 above
  describes the bridge between the two.
- [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) — SKILL-
  authoring discipline; required reading when authoring any
  board SKILL.
- [`SKILLS.md`](./SKILLS.md) — SKILL catalog including
  `board-canon` and `operating-kanban` (shipped v0.5.0).
- [`PLUGIN_DEVELOPMENT.md`](./PLUGIN_DEVELOPMENT.md) — plugin
  manifest / hook / script platform contracts.
- [`MULTI_AGENT_DEVELOPMENT.md`](./MULTI_AGENT_DEVELOPMENT.md) —
  subagent / agent-team / orchestration contracts.
- [`README.md`](./README.md) + [`README.zh-CN.md`](./README.zh-CN.md)
  — end-user overview, especially the "Why there's no sprint, no
  sub-issue, no story points" section.
