# ADR 0012: Kanban Protocol as top-level contract; ADR-0005 rescoped to v1 GitHubProjectAdapter projection

**Status:** accepted
**Date:** 2026-04-28
**Deciders:** PanQiWei (maintainer)

## Context

ADR-0005 shipped a BoardAdapter contract surface — five read+write
methods, a `Result[T]` type, six `ErrorKind` values, status mapping
policy — at second-adapter-implementable detail. That contract
made ADR-0001 / P2a (substrate commitment) falsifiable: a
second-adapter author has a complete spec to implement against.

The contract took an **SDK shape**: function signatures, parameter
lists, error enums. SDK shape is the natural form when:

- The caller is a deterministic program reading method signatures.
- The contract owner controls the function-table the caller
  dispatches through.

Both assumptions weaken in board-superpowers' actual runtime:

1. **The caller is an agent.** Skills (managing-board,
   consuming-card, decomposing-into-milestones, bootstrapping-
   repo) are read by agents; instructions for "how to read the
   board on this backend" are absorbed via SKILL bodies and MCP
   tool descriptions, not method calls into a function table.
   Agents are polymorphic at the prompt-text layer, not at the
   function-signature layer — they re-shape behavior based on
   what the per-backend reference says, without compiled
   dispatch.

2. **The contract owner does NOT control the function table.**
   Each backend (GitHub, Linear, Jira, future) has its own API
   shape — `gh project item-edit`, Linear's GraphQL, Jira's
   REST `transitions` endpoint, MCP tool calls each platform's
   official MCP server exposes. Forcing every backend wrapper to
   implement a uniform `set_card_status(card_id, status) ->
   Result[None]` adds an impedance layer at every backend
   without buying anything beyond what naming convention already
   buys.

3. **MCP transport is a first-class plugin platform affordance.**
   Both Claude Code (`.mcp.json` at plugin root) and Codex CLI
   (`mcpServers` field in `.codex-plugin/plugin.json` →
   `.mcp.json`) ship MCP server registration as a built-in
   plugin component (per
   [`PLUGIN_DEVELOPMENT.md`](../../../PLUGIN_DEVELOPMENT.md) § "MCP
   server registration" / § "MCP integration"). Sensitive
   credential storage is handled by `userConfig.sensitive`
   (Claude Code keychain) or `codex mcp login` (Codex OAuth).
   Plugins shipping a `.mcp.json` get auth, lifecycle, and tool
   visibility for free. Defining a BoardAdapter SDK at v1.0 that
   doesn't acknowledge the MCP transport path means v1.x
   adapters either bend the SDK or skip it.

4. **"Awareness without implementation" is the v1.0 commitment.**
   In design conversation (2026-04-28), the maintainer scoped
   v1.0 commitment as: GitHub Project v2 implements; Linear
   and Jira are NOT shipped — but the contract surface, schemas,
   and operations MUST already have been audited for cross-
   substrate compatibility. v1.x adapters land later without
   contract churn. ADR-0005's SDK-shape contract does not pass
   this audit cleanly: branch-naming hard-codes GitHub issue
   number `<N>`; PR-link mechanism hard-codes `Closes #N`;
   transition mechanism hard-codes "field option set" (not
   Jira's transition-by-id model).

The right shape for board-superpowers' contract is therefore
**protocol** (semantic mental model agents adapt to backend-
specific projections), not **SDK** (function table the agent
must dispatch through).

## Decision

The **Kanban Protocol** ([`docs/architecture/0005-contracts/00-
kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md)) is
established as the **top-level contract** of board-superpowers'
board layer.

The protocol fixes:

- The **ontology** — Board / Card / Status / Claim / PR Link /
  Label / Comment.
- The **state machine** — six canonical states + legal
  transitions; full SPOT in
  [`board-canon`](../../../skills/board-canon/SKILL.md).
- The **identity rules** — `Card.key` is display-stable opaque
  string; branch naming is `claim/<key-slug>-<title-slug>`.
- The **eight action contracts** — `read_board`, `read_card`,
  `create_card`, `transition_card`, `claim_card`, `release_claim`,
  `link_pr_to_card`, `comment_on_card` (OPTIONAL).
- The **compliance levels** — L0 (read-only) through L3 (full
  v1).
- The **implementation surface** — three projection forms
  (Form A bash CLI; Form B plugin-shipped MCP server; Form C
  REST/GraphQL).

The protocol is **transport-agnostic**. Backends realize the
protocol via projections; the projection's transport (CLI, MCP,
REST) is internal to the projection. Agentic loops adapt at
runtime to whatever the projection's reference file documents.

**Custom-state folding rule.** Backends with richer native
taxonomies fold to the six canonical states at projection time;
unfoldable native states fold to `Backlog` with stderr warning.
Per-card overrides forbidden — folding is a global property of
the backend's taxonomy on a given repo.

**`add_card_comment` re-evaluated.** Now an OPTIONAL protocol
action (was: out of scope per ADR-0005). v1 callers do not
require it; backends advertise support per their L1 declaration.

### Rescoping ADR-0005

ADR-0005's contract surface — `list_cards` / `get_card` /
`get_status_options` / `create_card` / `set_card_status`,
`Result[T]`, the six `ErrorKind` values, `StatusOption`, the
contract semantics — is **rescoped** from "the contract every
adapter must implement" to **"the v1 GitHubProjectAdapter
implementation projection"** (Form A). It remains valid, in force,
and immutable-modulo-superseding-ADR for the GitHubProjectAdapter
projection. New backend projections do NOT inherit ADR-0005's
shape verbatim; they implement the Kanban Protocol in whatever
shape fits their transport.

ADR-0005's Status field is amended to: `accepted; § Consequences
amended by ADR-0010; § Decision and § Type definitions amended by
ADR-0025`. The Decision and Type-definitions sections themselves
remain (they document the GitHubProjectAdapter projection's shape);
the supersession is one of **scope re-interpretation**, not text
deletion.

### Branch-naming abstraction

Branch naming `claim/<N>-<slug>` (where `N` is GitHub issue
number) is **generalized** to `claim/<key-slug>-<title-slug>`
(where `<key-slug>` = `slugify(Card.key)`). Existing
GitHubProjectAdapter claim branches remain valid because GitHub
`<key-slug>` of `42` slugifies to `42`. ADR-0001 and ADR-0002 are
amended to reference the abstracted form. The slugifier
contract itself remains in
[`board-canon`](../../../skills/board-canon/SKILL.md) § Branch
naming.

## Consequences

**What this enables:**

- The contract is **agent-readable** — natural-language semantic
  contracts let agents form a backend-agnostic mental model and
  dispatch through SKILL / MCP-tool projections.
- Cross-backend audit is **falsifiable**: if a future projection
  lands and existing skills require source edits to work against
  it (beyond pointing at a different backend reference file),
  the protocol is leaking projection details. Falsification
  triggers documented in the protocol document.
- v1.x MCP adapters slot in naturally — ship a `.mcp.json` entry
  shipping the official Linear / Atlassian Remote MCP server,
  add a `references/<backend>.md` documenting per-action tool
  invocation, no contract churn.
- ADR-0005's contract surface is preserved as documentation of
  the GitHubProjectAdapter projection — its `Result[T]` and
  `ErrorKind` types remain useful for that projection's bash
  callers.

**What this constrains:**

- **Branch naming abstraction lands in v0.5.0** — board-canon's
  current `claim/<N>-<slug>` text MUST be patched to the
  abstracted form. Existing GitHub claim branches (e.g.,
  `claim/42-fix-bug`) remain valid; the patch generalizes the
  rule, does not retroactively rename anything.
- **`<repo>/.board-superpowers/config.yml` schema gains a
  `kanban:` block** at v0.5.0. Schema change documented in
  [`0005-contracts/03-config-schemas.md`](../0005-contracts/03-config-schemas.md).
  Existing v0.4.x repos require migration on next bootstrap
  re-run; the `migrating-repo-version` skill (deferred to
  v1-complete per [`SKILLS.md`](../../../SKILLS.md)) will absorb
  this when it ships.
- **A new atomic skill `operating-kanban` lands in v0.5.0** as the
  backend-projection dispatch SPOT. Catalog row + SKILL.md ship
  in a follow-up PR after this protocol document lands.
- **Card #36 (GitHubProjectAdapter wrapper port) is repurposed.**
  Its original AC asks for "a single
  `scripts/lib/adapters/github.sh` implementing the BoardAdapter
  contract" — that AC is reframed as "the v1
  GitHubProjectAdapter Form A projection's reference shape." The
  wrapper port stays useful (consolidates `gh` calls) but is no
  longer the universal-contract gate.

**What this rules out:**

- **SDK-shape escape hatches in the protocol surface.** Protocol
  document MUST NOT name `Result[T]`, function-signature
  parameter lists, or any artifact whose existence presumes a
  function-table caller. Such concepts belong to projections;
  the projection's reference file may use them when the
  transport demands.
- **Per-card folding overrides.** Custom-state folding is a
  global property of the backend's taxonomy on a given repo; per-
  card folding instructions are forbidden.
- **Silent contract drift.** Any change to the eight action
  names or semantic contracts, the six canonical states, the
  ontology object set, identity rules, or compliance levels
  requires a new ADR superseding the protocol document.

## Alternatives considered

**Keep ADR-0005 as the universal contract; add cross-substrate
compatibility patches inline.** Considered: amend ADR-0005's
type definitions to abstract `Card.id` to `Card.key`, generalize
status mapping policy, document custom-state folding. Rejected
because the SDK shape itself is the problem — abstracting fields
without abstracting shape leaves the contract still presuming a
function-table caller. The agentic-loop adaptation premise
requires protocol-shape, not patched-SDK-shape.

**Ship a thin protocol layer ON TOP of ADR-0005's SDK; keep both
as live contracts.** Two-layer "protocol over SDK" was considered.
Rejected because it doubles the maintenance surface (every
addition requires both layers updated) and creates ambiguity
about which layer is canonical when they drift. Single-layer
protocol with SDK demoted to one projection's shape is cleaner.

**Defer protocol formalization to v1.x; ship v1.0 with ADR-0005
unchanged.** Rejected because the cross-substrate compatibility
audit (the v1.0 reframe maintainer committed to in the design
conversation) is not credibly performed without a protocol-level
contract to audit against. v1.0 GA without protocol = v1.0 GA
without "Linear / Jira awareness" credibility.

**Define the protocol in code (a Python ABC, a YAML schema, etc.)
and skip the spec doc.** Rejected because the protocol is a
**decision** about what the plugin commits to, not just an
implementation detail. Spec-level protocol documents are where
agentic mental models live; code is for projections (and v1
ships only one projection).

## Notes

- This ADR ships AS the protocol document lands ([`0005-contracts/
  00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md)).
  Their PRs are the same PR — the protocol is the Decision's
  artifact, this ADR is the Decision's record.
- ADR-0005's amended Status field reads: `accepted; § Consequences
  amended by ADR-0010; § Decision and § Type definitions amended
  by ADR-0025`. The original Decision text is preserved (rescoped
  in interpretation, not redacted) so historical readers see what
  ADR-0005 originally committed to and how that interpretation
  shifted.
- ADR-0001 and ADR-0002 are amended in place for the branch-
  naming abstraction — `claim/<N>-<slug>` → `claim/<key-slug>-
  <title-slug>`. This is the rare case where in-place ADR text
  edit is acceptable: the abstraction is strictly additive over
  the previous form (GitHub `<key-slug>` of `42` slugifies to
  `42`), so old behavior remains valid; the spec just becomes
  more general.
- `0001-positioning.md` P2a's "honest scope of present
  commitment" is updated to reflect the protocol rescoping
  rather than the SDK-style "contract committed; implementation
  port queued" phrasing.

## Related

- ADR-0001 — Pluggable board backend (P2a anchor; this ADR
  shifts how P2a's commitment is encoded)
- ADR-0002 — Atomic claim via remote branch push (branch naming
  abstraction touch-point)
- ADR-0005 — v1 BoardAdapter contract surface (rescoped by this
  ADR to GitHubProjectAdapter projection; Status field amended)
- ADR-0010 — AI-cadence convention; influences the timing of the
  protocol-vs-SDK choice via the v1 GA + 1w falsification
  re-anchor
- [`0005-contracts/00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md)
  — the protocol document itself, this ADR's artifact
- [`0001-positioning.md`](../0001-positioning.md) P2a, P4a,
  P4b — substrate + composition commitments this protocol
  operationalizes
- [`PLUGIN_DEVELOPMENT.md`](../../../PLUGIN_DEVELOPMENT.md) § "MCP
  server registration" / § "MCP integration" — Form B projection
  platform basis
- [`SKILLS.md`](../../../SKILLS.md) — atomic-skill boundary
  declaration (board-canon vs operating-kanban) lands in the
  same PR as this ADR
