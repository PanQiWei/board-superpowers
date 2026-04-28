# ADR 0001: Pluggable board backend (GitHub Project v2 as v1 reference adapter)

**Status:** accepted; branch-naming convention generalized by ADR-0012
**Date:** 2026-04-25
**Deciders:** PanQiWei (maintainer)

> **Reading note (2026-04-28).** ADR-0012 elevates the universal
> contract from "the BoardAdapter SDK ADR-0005 defines" to "the
> Kanban Protocol document at
> [`../0005-contracts/00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md)".
> ADR-0001's substrate-pluggability commitment is unchanged; what
> changed is the SHAPE of the contract that anchors it. Branch
> naming `claim/<N>-<slug>` (where `N` is GitHub issue number) is
> generalized by ADR-0012 to `claim/<key-slug>-<title-slug>` (where
> `<key-slug>` = `slugify(Card.key)`). For GitHub Project v2,
> `<key-slug>` of `42` slugifies to `42`, so existing
> `claim/<N>-<slug>` branches remain valid. The board-canon
> skill is the SPOT for the slugifier rule.

## Context

board-superpowers needs a single durable place to hold board state:
which cards exist, what status each one is in, who claimed what,
when the board was last updated. The deeper question is whether the
plugin should *own* that state or *defer* to whatever the user's team
already uses.

Three observations forced the decision:

1. **Distributed claim coordination already happens at the git
   layer.** Atomic claim is `git push --force-with-lease=<ref>:` on a
   namespaced branch (see ADR-0002 stub). That primitive is free,
   already-trusted, and works against any git host (GitHub, GitLab,
   Bitbucket). The board layer doesn't need to provide an atomic
   primitive of its own.

2. **The architect already lives inside their existing board.**
   GitHub Project v2 is one common case; Linear and Jira are real
   alternatives that engineering teams have already standardized on.
   Forcing a team to migrate boards before they can use
   board-superpowers is a non-starter for any team that has been
   running for more than a few months.

3. **Owning state is the business model of similar tools we are
   choosing *not* to mirror.** Devin, Factory, Cursor all sell
   hosted control planes. Their value capture depends on owning the
   state. An open-source plugin whose central commitment is to
   *defer to the user's existing board* makes a different
   architectural bet — see Positioning P2a (substrate commitment).

The original v0.1.0 release shipped GitHub-CLI-bound shell scripts
that hard-coded `gh project` and `gh issue` calls. That was correct
for getting v0.1 out the door, but it implicitly committed the
project to GitHub-only — exactly the wrong shape for the
substrate commitment described above.

## Decision

The board layer is **pluggable behind a stable contract**.

- **Contract:** the **Kanban Protocol** ([`../0005-contracts/00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md))
  is the universal contract — a semantic mental model agents reason
  in, with eight action contracts, six canonical states, identity
  rules, and three implementation projection forms (bash CLI / plugin-
  shipped MCP server / REST). ADR-0005 defines the **v1
  GitHubProjectAdapter implementation projection** (Form A: bash +
  `gh` CLI), not the universal contract — see ADR-0012 for the
  rescoping. *(2026-04-28 update: original Decision text used
  ADR-0005 as the universal contract; ADR-0012 reframed that.)*
- **v1 reference projection:** **GitHubProjectAdapter** (Form A)
  ships with the plugin. It is the only projection at v1.
- **Future projections:** LinearAdapter, JiraAdapter, and any other
  backend a contributor wants to write are **first-class targets**,
  not afterthoughts. They realize the Kanban Protocol on their
  backend through whatever projection form fits — Form B (plugin-
  shipped MCP server, expected for Linear/Jira) is a first-class
  option per ADR-0012.
- **The board IS the truth source.** board-superpowers does not
  maintain a parallel state store. Per-session scratch
  (`.board-superpowers/claims/<key>.claim`, `docs/board-superpowers/
  plans/`) is the only state we own, and both are
  reconstructible-or-disposable. *(2026-04-28: the path token `<N>`
  is generalized to `<key>` per ADR-0012's branch-naming
  abstraction; for GitHub `<key>` slugifies to the issue number.)*

## Consequences

**What this enables:**

- Teams already on Linear or Jira can adopt board-superpowers
  without migrating boards — once the second adapter ships.
- The plugin's positioning (P2a) gets a falsifiable architectural
  anchor: if no second adapter is attempted by v1 GA + 1 week (AI
  cadence; see ADR-0005 Consequences as amended by ADR-0010),
  P2a's "present commitment" framing is downgraded.
- ADR-0002 (claim primitive) decouples cleanly from the board: git
  pushes are atomic on any git host; the board adapter only
  observes the resulting status transition.
- Bootstrap UX stays simple at v1 (`bootstrap-project.sh
  --project OWNER/NUMBER` is GitHub-shaped); the second-adapter
  PR will sort out whether `--adapter <name>` becomes an explicit
  flag or each adapter ships its own bootstrap.

**What this constrains:**

- Every new feature that touches board state must route through the
  BoardAdapter contract — not through `gh` directly. The existing
  scripts pre-date this commitment and will be ported behind the
  contract via the **GitHubProjectAdapter wrapper port** (lands
  before v1 GA; see ADR-0005 Consequences as amended by ADR-0010).
  Until then, the contract ships as design intent and the
  implementation gap is documented honestly.
- The contract surface itself (ADR-0005) is now immutable-modulo-
  superseding-ADR. Any change to method signatures, type
  definitions, or error semantics requires a new ADR.
- Backend-specific affordances (Linear's auto-creating labels,
  Jira's custom workflows, GitHub Project v2's draft items) MUST
  be either covered by the contract OR explicitly out-of-scope.
  We do not expose backend-specific escape hatches at v1.

**What this rules out:**

- A bespoke board UI hosted by us. Permanently. (Non-goal.)
- A custom DB or state store of our own. Permanently. (Non-goal.)
- "GitHub-only" as a positioning claim. The whole point of P2a is
  the opposite.

## Alternatives considered

**Bespoke SQLite/JSON store under `.board-superpowers/`.** Would
have given full control over data model and zero external
dependencies. Rejected because (a) it duplicates state the user's
existing board already holds, (b) it forces architects onto a UI
we'd have to build to make the data useful, (c) it violates P4a's
"truth-source belongs to the user" before we even ship.

**GitHub Issues-only with labels in place of Status.** Simpler
than Project v2 (no second-class single-select fields, no
admin-time field configuration). Rejected because labels don't
have ordering, can't be filtered usefully in queries, and don't
match how engineers think about board flow. Project v2's Status
field is the smallest concept that actually models a workflow.

**Linear or Jira as the single backend instead of GitHub
Project.** Tempting because both have richer data models. Rejected
because v1's user is the maintainer (PanQiWei), who lives in
GitHub. Picking the maintainer's actual backend as v1 reference
keeps dogfooding tight. Future adapters are first-class.

**Hosted backend of our own.** Would have made coordination
trivial (atomic operations, push notifications, multi-tenant
permissions all built-in). Rejected on positioning grounds, not
technical: hosted = SaaS = a business model that doesn't match a
side-project open-source plugin. See P5 (Distribution stays
minimal).

## Notes

This ADR uses number 0001 even though a file with that number
existed earlier (`0001-github-project-as-source-of-truth.md`).
That earlier file was a **never-accepted skeleton stub** created
during the architecture-skeleton scaffolding step on the same
date — it had no Decision and no acceptance signature. Reusing
its number is therefore not a violation of "ADRs are immutable
once accepted" — the immutability rule applies to *accepted*
ADRs, not to placeholder stubs.

A future maintainer reading this should NOT cite this renumbering
as license to rewrite an *accepted* ADR in place. Superseding an
accepted ADR creates a NEW ADR with a fresh number that links
back via the `Status: superseded by ADR-N` field.

## Related

- ADR-0002 — Atomic claim via remote branch push (stub; the claim
  primitive lives at the git layer, decoupled from the board
  adapter)
- ADR-0004 — Composition over reimplementation of TDD/QA
  (sibling architectural commitment)
- ADR-0005 — v1 BoardAdapter contract surface (the contract this
  ADR establishes the need for)
- `0001-positioning.md` P2a, P4a — substrate-commitment framing this
  ADR anchors
- [`0003-domain-model/`](../0003-domain-model/README.md) — Project,
  Card, Status entities become abstract over backend after this ADR
  (Card aggregate § 3.3.1; BoardAdapter ACL is the seam in
  § 3.6.3).
