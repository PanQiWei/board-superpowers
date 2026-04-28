# ADR 0005: v1 BoardAdapter contract surface

**Status:** accepted; § Consequences amended by ADR-0010; § Decision and § Type definitions amended by ADR-0012 (rescoped to v1 GitHubProjectAdapter projection)
**Date:** 2026-04-25
**Deciders:** PanQiWei (maintainer)

> **Reading note (2026-04-28).** After ADR-0012, this ADR is no
> longer "the contract every adapter must implement" — it is **the
> v1 GitHubProjectAdapter implementation projection** (one specific
> shape Form A takes when the transport is bash + `gh` CLI). The
> universal contract now lives in
> [`../0005-contracts/00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md)
> as the Kanban Protocol. Read this ADR's `Decision` and `Type
> definitions` sections as describing how the GitHubProjectAdapter
> projection realizes the protocol; do NOT read them as constraining
> future Linear / Jira / other projections.

## Context

ADR-0001 commits board-superpowers to a pluggable board backend
(GitHub Project v2 as v1 reference adapter; Linear / Jira / others
as first-class future targets). For that commitment to be more
than aspiration, the **interface every adapter must implement** has
to be specified at second-adapter-implementable detail today —
otherwise ADR-0001 is "we'll figure out the contract later," and
the substrate commitment in `0001-positioning.md` P2a collapses to
unfalsifiable.

> **2026-04-28 update.** The premise that "the contract every
> adapter must implement" is the right shape for board-
> superpowers' contract surface was reversed by ADR-0012. SDK
> shape (function table caller dispatches through) does not
> match an agentic runtime where callers are agents reading SKILL
> bodies. The contract surface defined here remains valid AS the
> v1 GitHubProjectAdapter projection's shape; it is no longer
> universal. See ADR-0012 § Context for the full rationale.

The contract has to be small enough that one author can implement
a second adapter (Linear, Jira, etc.) in a weekend, and complete
enough that the maintainer doesn't end up making up missing pieces
six months from now. It also has to be honest about what it does
NOT cover — every omission is a deliberate scope decision, not an
oversight.

## Decision

The v1 BoardAdapter contract surface is defined below.
**Immutable-modulo-superseding-ADR** once this ADR is accepted —
any signature change, type definition change, error-semantics
change, or status-mapping policy change requires a new ADR.

### Type definitions

**`ProjectRef`** — adapter-internal handle for a board. Each
adapter parses its own user-facing identifier into a `ProjectRef`.
Opaque to callers.

```
ProjectRef:
  GitHubProjectAdapter:    parsed from "OWNER/NUMBER"
                           (matches bootstrap-project.sh CLI)
  LinearAdapter (future):  parsed from "WORKSPACE/TEAM" or similar
  JiraAdapter (future):    parsed from "DOMAIN/PROJECT_KEY"
```

Every adapter MUST expose:

- `parse(user_string: str) -> Result[ProjectRef]`
- `serialize(ref: ProjectRef) -> str`

…and the round-trip MUST be stable
(`serialize(parse(s).value) == s`). Required because
`.board-superpowers/config.yml` stores the user-facing identifier
and bootstrap reconstructs `ProjectRef` per session from the
stored string.

**`Status`** — typed enum of canonical board-superpowers status
names. Adapters translate to/from native names via per-adapter
mapping table.

```
Status = Literal[
  "Backlog", "Ready", "In Progress", "In Review", "Done", "Blocked"
]
```

**`StatusOption`** — what `get_status_options` returns. Carries
the backend-native id needed for downstream mutation.

```
StatusOption:
  name        : Status            # canonical name
  order       : int               # backend-defined position (0-based);
                                  # callers MUST NOT key semantic logic
                                  # on order — it's render-only
  backend_id  : str               # adapter-internal id needed by
                                  # set_card_status's lookup
```

**`Card`** — what `list_cards` and `get_card` return.

```
Card:
  id          : str               # backend-native string id
  title       : str
  body        : str               # markdown
  status      : Status            # typed enum, never raw string
  labels      : list[str]         # label *names* only at v1; color
                                  # / description out of scope
  url         : str               # link back to backend's UI
  created_at  : str               # ISO 8601
  updated_at  : str               # ISO 8601
```

**`Result[T]`** — return shape for any method that can fail.
Callers branch on `error_kind`, never on `message`.

```
Result[T]:
  ok          : bool
  value       : T | None          # populated iff ok=True
  error_kind  : ErrorKind | None  # populated iff ok=False
  message     : str | None        # human-readable; never matched on

ErrorKind = Literal[
  "not_found",        # entity does not exist
  "permission",       # auth lacks scope or role
  "rate_limit",       # backend asks us to slow down
  "conflict",         # write rejected due to concurrent change
  "schema_mismatch",  # status / field / label does not exist
  "transport"         # network / 5xx / unknown
]
```

### Read methods

```
list_cards(
  project_ref     : ProjectRef,
  status_filter   : list[Status] | None = None,
) -> Result[list[Card]]
```

Returns all cards on the board, optionally filtered by canonical
status name list. Order is backend-native — no contract on
ordering at v1. Callers (Daily routine, Review Queue, Triage)
sort client-side.

```
get_card(
  project_ref     : ProjectRef,
  card_id         : str,
) -> Result[Card]
```

Returns one card with full body + labels. Errors with `not_found`
if `card_id` doesn't exist on this project. Used by
`consuming-card` (claim flow), `decomposing-into-milestones`
(cross-references).

```
get_status_options(
  project_ref     : ProjectRef,
) -> Result[list[StatusOption]]
```

Returns ordered list of canonical status options as the backend
has them configured. Bootstrap calls this to validate the board
has all 6 required statuses; `set_card_status` callers (or the
adapter internally) call it for `backend_id` lookup.

### Write methods

```
create_card(
  project_ref     : ProjectRef,
  title           : str,
  body            : str,
  labels          : list[str],
  initial_status  : Status = "Backlog",
) -> Result[str]
```

Creates a new card; returns its backend-assigned `card_id` on
success. `initial_status` defaults to `"Backlog"` —
`decomposing-into-milestones` never lands cards directly in
`Ready` (that's a separate user action, not the adapter's
concern). Errors with `schema_mismatch` if a label doesn't exist
on the backend (label lifecycle is owned by `bootstrap-project.sh`
or the user, NOT the adapter — see Contract semantics below).

```
set_card_status(
  project_ref     : ProjectRef,
  card_id         : str,
  status          : Status,
) -> Result[None]
```

Transitions a card to a new canonical status. The adapter MUST
internally resolve `Status` → `backend_id` without requiring the
caller to do it (typically by caching a recent
`get_status_options()` result for the lifetime of the
`ProjectRef`). If the backend's status options change between
cache-refresh and call, the adapter returns `schema_mismatch` and
the caller is expected to retry after re-fetching.

### Contract semantics

These are the fine-print rules every adapter MUST honor. Each
closes one ambiguity a second-adapter author would otherwise have
to make up.

- **Idempotency.** `set_card_status` to the current status is a
  successful no-op (`ok=True`, `value=None`); not an error.
  `create_card` has no idempotency key at v1 — callers that retry
  after a transport blip risk duplicate cards. Adding a
  `dedupe_key` parameter is a future ADR-0005 supersession; for
  now, callers guard at their layer (typically by checking
  `list_cards` before retrying).

- **Partial failure on list operations.** `list_cards` /
  `get_status_options` return `ok=True` with the well-formed
  subset and silently OMIT malformed entries (adapter logs a
  warning to stderr); they do NOT return `ok=False/transport`.
  Rationale: a board with 3 weird cards is still 97% useful;
  making the whole list call fail blocks Daily routine over edge
  cases. `get_card` for a specific malformed card returns
  `ok=False/schema_mismatch`.

- **Label lifecycle.** Adapters do NOT auto-create labels;
  `create_card` with an unknown label returns
  `ok=False/schema_mismatch`. Label provisioning belongs to
  `bootstrap-project.sh` (or the user via the backend's UI). Same
  policy across adapters even if the backend allows lazy creation
  (Linear) — keeps caller behavior consistent.

- **`StatusOption.order`.** Backend-defined, not canonical. Two
  reasons: (a) some backends genuinely re-order columns (Linear
  workspace customization); (b) callers that depend on order
  should derive from canonical name, not numeric position.
  `order` is provided so callers that DO need to render the
  board in workflow order have it; semantic logic must NOT key
  on it.

- **`ProjectRef` parse / serialize.** Every adapter exposes
  `parse(str) -> Result[ProjectRef]` and
  `serialize(ProjectRef) -> str`, round-trip stable. (See Type
  definitions above.)

- **Adapter constructor failure.** Constructor returns
  `Result[Adapter]`. Common failure modes map as: missing
  credentials → `permission`; project not found →
  `not_found`; backend unreachable → `transport`. This lets
  callers distinguish "user hasn't run `gh auth login`" from
  "project number doesn't exist" without parsing error messages.

### Per-adapter status mapping

Each backend has its own status taxonomy; the adapter is
responsible for translating between native and canonical names.

**v1 GitHubProjectAdapter** (1-to-1; we created the project's
Status field to match):

```
canonical      → GitHub Project v2 Status field option
"Backlog"      → "Backlog"
"Ready"        → "Ready"
"In Progress"  → "In Progress"
"In Review"    → "In Review"
"Done"         → "Done"
"Blocked"      → "Blocked"
```

**Future LinearAdapter** (illustrative; not committed):

```
canonical      → Linear status
"Backlog"      → "Backlog"
"Ready"        → "Todo"
"In Progress"  → "In Progress"
"In Review"    → "In Review"
"Done"         → "Done"
"Blocked"      → "Cancelled"  (or custom workflow state)
```

The mapping table per adapter is what makes the contract
genuinely backend-agnostic. Mismatches at this layer become
explicit `schema_mismatch` errors rather than silent corruption.

### Out of scope at v1

These are deliberate omissions, not oversights. Each has a
reason. Adding any of them later requires an ADR-0005
supersession, not a silent contract amendment.

- **`claim_card()`** — git layer, not board layer (see ADR-0002
  stub). Atomicity is provided by `git push --force-with-lease`;
  the board only observes the resulting `set_card_status` call
  after claim succeeds.
- **`add_card_comment()`** — no caller in v1. Today's scripts
  (`claim-card.sh`, `create-card.sh`, `transition-card.sh`,
  Manager's kick-off prompt, Consumer's Step 5 report) all
  communicate via the PR body or the marker file. If a future
  observability feature genuinely needs board comments, add via
  ADR supersession.
- **Webhooks / push-shaped change detection** — adapter is
  poll-shaped at v1. Callers that want change notifications poll
  on their own cadence. Webhook receivers are a future ADR.
- **Bulk operations** — each operation is one card. Aggregation
  happens in the calling skill, not the adapter.
- **Authentication / connection lifecycle** — handled by the
  adapter constructor and ambient credentials (e.g., `gh auth
  login` for GitHubProjectAdapter, `LINEAR_API_KEY` env for the
  hypothetical LinearAdapter). Not part of the contract surface.
- **Pagination** — v1 callers iterate and the adapter returns
  full lists. Pagination is a future addition when scale demands
  it.

## Consequences

**What this enables:**

- ADR-0001's pluggable-backend commitment is now falsifiable — a
  second-adapter author has a complete spec to implement against.
- 0001-positioning.md P2a (substrate commitment) gets an
  architectural anchor at "contract committed" detail rather than
  "we plan to" hand-waving.
- Error semantics are uniform across adapters; calling skills can
  be written backend-agnostic from day one.

**What this constrains (and what's queued):**

- **GitHubProjectAdapter wrapper port.** Today's `claim-card.sh`,
  `create-card.sh`, `transition-card.sh` call `gh` directly. They
  are the v1 GitHubProjectAdapter implementation in spirit but
  not in shape. Refactoring to a single
  `lib/adapters/github.sh` (or equivalent) implementing this
  contract is a separate PR. Sized M-L.
  - **Hard deadline:** wrapper port lands **before v1 GA**, or
    P2a is downgraded from "present commitment" to
    "aspirational" via a 0001-positioning.md amendment.
    *Anchor re-shaped from a 60-day calendar offset to a
    v1-GA-relative event by ADR-0010.*
  - Bootstrap-CLI side note: when the wrapper port lands, also
    resolve whether `bootstrap-project.sh`'s `OWNER/NUMBER` arg
    becomes `--adapter github --project-ref OWNER/NUMBER`
    (generic) or stays adapter-specific (each adapter ships its
    own bootstrap script).
- **Falsification check (v1 GA + 1 week, AI cadence).** If no
  second adapter has been seriously attempted by **v1 GA +
  1 week**, file a retro card reconsidering whether P2a + P4a
  are honest commitments or aspiration. Mechanism: a `chore`
  Backlog card titled `P2a/P4a falsification check (v1 GA +
  1w)` is filed in the same Backlog the day this ADR's PR
  merges; the title is **edited to** `P2a/P4a falsification
  check (YYYY-MM-DD)` once v1 GA is declared and the absolute
  date becomes computable. *Anchor re-shaped from a 6-month
  calendar offset to a v1-GA-relative event by ADR-0010.*

**What this rules out:**

- Backend-specific escape hatches in the public contract surface.
  No `gh_pr_number` field on `Card`. No "adapter-specific
  options" parameter. Backend-specific behavior is internal to
  the adapter.
- Silent contract drift. Any change requires a new ADR; the
  immutability gate is enforced at PR review.

## Alternatives considered

**Defer the contract surface to a future ADR; ship ADR-0005 as
"proposed" with `Decision: TBD`.** Rejected during
office-hours session round 2 because P2a (substrate commitment)
becomes unfalsifiable if the contract is "we'll figure it
out later" — `0001-positioning.md` P2a would be aspiration, not
commitment.

**Ship a richer contract surface (10+ methods including
`add_card_comment`, `link_pr_to_card`, `add_label`, etc.).**
Rejected because every method we ship is a method every adapter
must implement; over-shipping the surface guarantees nobody
writes the second adapter. Strict YAGNI: 5 methods cover all
current callers.

**Define the contract in code (a Python ABC or shell function
table) and skip the ADR.** Rejected because the contract is a
*decision* about what the plugin commits to, not just an
implementation detail. ADRs are where decisions live; code is
where they get implemented. (The wrapper port PR ships the code
form.)

**Accept the contract but mark `Result[T]` and error semantics
as "to be designed."** Rejected because missing error semantics
is the load-bearing gap that would block second-adapter
implementation. Closing it now is the whole point of this ADR.

## Notes

- This ADR is shipping the contract as **design intent**. The
  reference implementation (today's `gh`-bound shell scripts) is
  not yet refactored to call through a `BoardAdapter` interface
  — that's the GitHubProjectAdapter wrapper port (Consequences
  above). The honesty gap between "contract Accepted" and "no
  call sites use it yet" is the price of doing this in the
  right order: spec → port → second-adapter, instead of
  spec-and-port-and-second-adapter-all-at-once.
- The wrapper-port deadline ("before v1 GA") and the
  P2a/P4a-falsification check ("v1 GA + 1 week (AI cadence)")
  are both real commitments. If they slip,
  0001-positioning.md P2a should be amended honestly rather
  than quietly carried. *Original anchor sizes (60-day /
  6-month calendar offsets) re-shaped by ADR-0010.*
- Future ADR supersessions of this contract should record the
  `before` and `after` contract surface so decision history
  stays traceable.

## Related

- ADR-0001 — Pluggable board backend (the architectural
  commitment this ADR makes implementable)
- ADR-0002 — Atomic claim via remote branch push (stub; the
  reason `claim_card()` is not in this contract surface)
- ADR-0004 — Composition over reimplementation (sibling
  scope-discipline commitment; both define what board-superpowers
  refuses to own)
- `0001-positioning.md` P2a, P4a — substrate-commitment framing this
  ADR makes falsifiable
- `0005-contracts.md` (stub) — when filled, this ADR becomes the
  canonical source for the BoardAdapter category of contracts
- `0006-failure-modes.md` (stub) — F-04 (missing CI), F-08
  (cross-machine Consumer death) interact with the adapter's
  error semantics
- [`0003-domain-model/`](../0003-domain-model/README.md) — Project,
  Card, Status entities become abstract over backend after this ADR
  (Card aggregate § 3.3.1; BoardAdapter Anti-Corruption Layer
  § 3.6.3).
