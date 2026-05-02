## 3.3 Aggregates and entities

Each aggregate is named once, with: **root**, **member entities**
(lifecycle-bound to root), **value objects** (immutable, no
identity of their own), **invariants enforced at root**, and
**physical location** (where this thing actually lives — a
GitHub Issue + Project v2 item, a filesystem path, an RDBMS
row, a git ref). Cross-references back to 0002 features and
ADR contracts are aggressive on purpose: 0003 is the *navigation
hub*; 0002 / ADRs are the canonical detail.

The aggregate list (read order optimizes for the common
question "what is this thing":

| # | Aggregate | Root | Context |
|---|-----------|------|---------|
| 3.3.1 | Card | Card | Board |
| 3.3.2 | PR | PullRequest | Board |
| 3.3.3 | ConsumerLogical | ConsumerLogical | Session |
| 3.3.4 | ProducerSession | ProducerSession | Session |
| 3.3.5 | HostBootstrap | HostManifest | Bootstrap |
| 3.3.6 | RepoBootstrap | RepoState | Bootstrap |
| 3.3.7 | RepoConfig | RepoConfig | Bootstrap |
| 3.3.8 | AuditTrail | AuditTrail | Audit |
| 3.3.9 | SpecPointer | (collection-shaped — see entry) | Spec |

---

### 3.3.1 Card aggregate

The leaf work item. The entity Producers create, Consumers
claim, the architect verifies. Spans Board context.

**Root.** `Card` — identified by `(ProjectRef, Card.key)` where
`Card.key` is the Kanban Protocol's opaque, display-stable,
unparseable identifier (`0005-contracts/00-kanban-protocol.md`
§ Identity). For the v1 GitHubProjectAdapter projection the
`Card.key` value happens to equal the GitHub Issue number's
string form (`42`, `137`); on future projections it takes the
backend-native form (Linear `eng-42`; Jira `proj-42`). The
glossary entry `CardNumber` (§3.1) remains valid as the GitHub-
shape value backing v1's `Card.key`.

**Member entities.**

- **CardBody** — the markdown body following the §1.6.3 schema
  (thin-pointer block + Goal / Acceptance criteria / Out of scope
  / Dependencies / optional Execution Hints / Notes + trailing
  `<!-- board-superpowers:card -->` marker). Mutable while the
  card is in Backlog/Ready (Producer refines per ADR-0006 row
  2 = A); locked once In Progress (Consumer reads only,
  surfaces F-C8 if updates needed).
- **StatusBinding** — the live association between this Card
  and a `Status` value on the Project v2 board. Has its own
  state-machine semantics (allowed transitions are the
  `board-protocol` table). Each transition emits the
  `Card.Status.Transitioned` domain event
  (`04-domain-events.md`).
- **LabelSet** — the `type:*` and `size:*` labels currently
  applied. Created by `bootstrap-project.sh`; assignment is
  per-Card.
- **ClaimMarker (transient when alive).** When the Card is in
  `In Progress` / `In Review`, exactly one ClaimMarker file
  exists on origin under
  `.board-superpowers/claims/<key>.claim` on the ClaimBranch
  (where `<key>` is `Card.key`; under the v1 GitHubProjectAdapter
  projection this resolves to the GitHub issue number, e.g.,
  `.board-superpowers/claims/42.claim`).
  Logically a member entity of Card, but **physically owned
  by the ConsumerLogical aggregate** (3.3.3) — its existence
  on origin is the proof Card is claimed; its lifecycle is
  pinned to the ConsumerLogical's lifecycle (deleted when the
  branch is deleted).

**Value objects.**

- **CardNumber** — integer `N` GitHub assigns at issue
  creation. Backs `Card.key` under the v1 GitHubProjectAdapter
  projection. Future projections (Linear / Jira) carry their
  own backend-native key shape (`eng-42`, `proj-42`); the
  protocol-layer abstraction is `Card.key` per
  `0005-contracts/00-kanban-protocol.md` § Identity.
- **KeySlug** — `slugify(Card.key)` — lowercase, alphanumeric
  + hyphens. Per the Kanban Protocol branch-naming convention
  `claim/<key-slug>-<title-slug>`. Under v1's GitHub projection,
  `slugify("42")` is `"42"`, so existing `claim/<N>-<slug>`
  branches remain valid.
- **Slug (= TitleSlug)** — derived once from Card title
  (lowercase-hyphenated, ≤ 40 chars). Stable for the Card's
  lifetime; locked into the ClaimBranch name as the
  `<title-slug>` half of `claim/<key-slug>-<title-slug>`.
- **Status** — typed enum from ADR-0005:
  `Backlog | Ready | In Progress | In Review | Done | Blocked`.
- **Estimate** — `XS | S | M | L`. `XL` is invalid by design
  (§1.6.1 Small letter — exceeding L forces re-split before the
  card lands). Realized in card body as the `**Estimate**:`
  thin-pointer field (per §1.6.3 schema); persisted on the
  GitHub-side via the `size:*` label set defined in
  0005-contracts/05-github-artifact-schemas.md (the value-object
  name `Estimate` and the label key `size:*` differ for label-
  rename-cost reasons; both refer to the same concept).
- **CardType** — derived from the `type:*` label
  (`feature | bug | chore | refactor | epic`).
- **MilestoneRef** — 0-or-1 GitHub Milestone reference (§1.1
  outcome axis).
- **ThreadRef** — 0..N user-defined thread tag (§1.1 thematic
  axis; precise representation TBD — see TBD-N1 below).

**Invariants enforced at root.**

- **I-1** — one Card binds to at most one ConsumerLogical at a
  time. Enforced by the ClaimBranch atomicity (ADR-0002).
- **I-6** — counts toward WIP iff Status ∈
  `{In Progress, In Review}` ∪ `{In Progress with SuspendState}`;
  `Blocked` does NOT count.
- **I-9** — CardBody.Context section MUST resolve to a valid
  spec (in-repo path or third-party storage URL) before
  Backlog → Ready transition (Producer's input-completeness
  gate, ADR-0006 row 5 precondition).
- **State machine** (canonical in `board-protocol/SKILL.md`):
  `Backlog → Ready → In Progress → In Review → Done`,
  with `Blocked` reachable from `In Progress` and a few
  reverse transitions. **`Backlog → anywhere except Ready` is
  forbidden** — the Ready gate is non-bypassable. Diagram in
  `05-relationships.md`.
- **§1.6.1 INVEST** is a Card-aggregate invariant at decomposition
  time — every Card landing on the board passes Independent /
  Negotiable / Valuable / Estimable / Small / Testable.
- **§1.6.2 Vertical slicing** is a Card-aggregate invariant at
  decomposition time — no layer-only Cards.
- **Trailing marker required.** CardBody MUST end with the
  exact bytes `<!-- board-superpowers:card -->` so
  `managing-board` and other tooling can distinguish
  board-superpowers Cards from plain Issues on the same
  project (§1.6.3, `card-schema.md`).

**Physical location.**

- **Card identity + Status field** — under v1 the
  GitHubProjectAdapter projection stores this as one row in
  the GitHub Project v2 items table, indexed by
  `(ProjectRef, Card.key)` (the GitHub Issue number backs
  `Card.key`). Other projections (Linear / Jira / future)
  carry the same logical identity in their own backend's
  storage.
- **CardBody + LabelSet + thread** — under v1 stored as one
  GitHub Issue; the body markdown obeys the protocol-level
  body schema (`0005-contracts/00-kanban-protocol.md` §
  Body schema). Backends without native markdown convert at
  the projection layer; agents always read and write
  markdown.
- **ClaimMarker (when alive)** — one file at
  `.board-superpowers/claims/<key>.claim` on the
  `claim/<key-slug>-<title-slug>` ref on origin. Under v1's
  GitHub projection, `<key>` is the GitHub issue number and
  the path resolves to `.board-superpowers/claims/42.claim`
  on `claim/42-fix-bug`. Lifecycle owned by ConsumerLogical
  (3.3.3).

---

### 3.3.2 PR aggregate

The Pull Request resolving exactly one Card. Spans Board
context. Separate aggregate (not part of Card) because its
lifecycle (review-cycle iteration, mandatory section structure,
auto-close-on-merge, three different protocol-required
sections) operates independently of Card.status transitions.

**Root.** `PullRequest` — identified by `(ProjectRef, PRNumber)`.

**Member entities.**

- **PRBody** — the markdown body following the §1.8 schema:
  - `## Summary` (from delegated PR-creation skill)
  - `## Test Plan` (from delegated skill)
  - `## Automated Verification` (Consumer writes; **required**)
  - `## Human Verification TODO` (Consumer writes; **OPTIONAL**)
  - `## Retro Notes` (Consumer writes; **required when
    reusable lessons exist**)
  - `Closes #<card>` linker line + trailing
    `<!-- board-superpowers:pr -->` marker.
- **AutomatedVerificationRecord** — list of (skill ran,
  outcome, evidence). Seeded by F-C9 / F-C10 / F-C11.
- **HumanVerificationTODO** — optional checklist of
  human-only end-to-end checks. Source: Producer's plan +
  Consumer's implementation-time additions. Filler items
  forbidden (§1.8.2).
- **RetroNotesEntry** — knowledge-harvesting prose; two-pass
  authorship (initial at PR-submit, supplemented post-merge
  with review-cycle insights). Feeds Producer's F-12 retro
  routine via card-thread aggregation.
- **ReviewCycleIteration** — each round of (review comments
  arrive → Consumer responds → new commits pushed) is one
  iteration. The same Consumer instance handles every
  iteration (§1.4.1 F-C13).

**Value objects.**

- **PRNumber** — GitHub-assigned integer.
- **CardLink** — back-reference to the Card. Under v1's GitHub
  projection this is the `Closes #<CardNumber>` syntax that
  GitHub auto-resolves on merge; the protocol-level requirement
  (per `0005-contracts/00-kanban-protocol.md` § PR Link) is
  bidirectional discoverability — from `Card.url` an agent can
  navigate to the PR; from the PR an agent can navigate back
  to `Card.key`. Future projections may realize the link via
  Linear's git-integration or Jira's smart-commit syntax.
- **TitleShape** — recommended `[card:#<key>] <verb> <area>`
  (strong recommend per F-C12; not enforced by the contract).
  Under v1's GitHub projection `<key>` is the issue number `N`.

**Invariants enforced at root.**

- **I-1** — exactly one Card resolved per PR; no multi-card
  PRs.
- **I-2** — Consumer cannot self-merge (matrix row 12 = R; the
  Architect, or a different human, performs the merge).
- **§1.8 marker** required — trailing
  `<!-- board-superpowers:pr -->` so Manager's Review Queue
  routine (F-02) can find board-superpowers PRs.
- **`## Automated Verification` is mandatory** when the PR is
  opened; missing → §1.8 contract violation flagged by F-02.
- **`## Human Verification TODO` filler is forbidden** — items
  like "verify it works" / "make sure tests pass" are
  contract violations even if the section is otherwise
  present (§1.8.2).
- **Same-Consumer review-cycle rule** — review feedback is
  responded to by the same ConsumerLogical that opened the
  PR; never a fresh re-spawned session (§1.4.1 F-C13).
- **PR.Merged → Card.Done** auto-close via GitHub's
  `Closes #<N>` mechanism. Reverse coupling: Card cannot
  reach Done except via PR merge (or rare manual GitHub
  intervention; not a board-superpowers code path).

**Physical location.** One GitHub Pull Request, plus PR thread
comments (review feedback), plus the Card thread comments
that reference the PR. The branch the PR targets is the same
ClaimBranch that holds the ClaimMarker.

---

### 3.3.3 ConsumerLogical aggregate

The kanban-relative Consumer role binding to one Card. The
**logical / physical split** is the most subtle entity in
0003 — required by §1.4 Mode topology and the F-C14
Mode-2-resume path. Spans Session context.

**Root.** `ConsumerLogical` — identified by
`(ProjectRef, Card.key)`. Persists across ConsumerProcess
incarnations.

**Member entities.**

- **ClaimBranch** — the `claim/<key-slug>-<title-slug>` ref on
  origin (per the Kanban Protocol branch-naming convention,
  `0005-contracts/00-kanban-protocol.md` § Identity). Under
  v1's GitHub projection `slugify(Card.key)` of `42` is `42`,
  so the form reduces to `claim/42-fix-auth-bug` and existing
  branches remain valid. Created atomically by
  `git push --force-with-lease=<ref>:` (ADR-0002). Acts as:
  distributed lock + feature branch + debugging aid (§1.4.1
  F-C1). Lifecycle bound to ConsumerLogical: created at F-C1,
  deleted at F-C14 success path (after merge GitHub auto-
  deletes; after failure path the branch may be cleaned by
  architect).
- **ClaimMarker** — the file
  `.board-superpowers/claims/<key>.claim` (YAML; see §3.1
  glossary entry for fields). Under v1's GitHub projection
  `<key>` is the issue number, e.g.,
  `.board-superpowers/claims/42.claim`. Force-committed onto
  the ClaimBranch even though gitignored locally. Visible on
  origin as proof of claim.
- **Worktree** — filesystem checkout paired with the
  ClaimBranch. Default location:
  `$HOME/.config/superpowers/worktrees/<project>/<branch>`.
  Persists across Mode-2 terminate-and-resume cycles
  (I-7); self-deletes on F-C14 success path; preserved on
  F-C14 failure path for human takeover.
- **PlanBrief** — `docs/board-superpowers/plans/card-<N>.md`,
  gitignored, written by F-C2. Per-session scratch the
  Consumer hands to `superpowers:subagent-driven-development`.
- **ConsumerProcess (zero-or-more, sequential — at most one
  alive at a time).** A *physical* CC or Codex CLI process
  running this ConsumerLogical for a stretch. Has its own
  identity (`SessionId`) and its own lifetime (process
  start to clean exit / suspend / crash). Multiple
  ConsumerProcesses backing one ConsumerLogical occur on
  Mode-2 wake-up (subagent re-spawn), on user-driven resume
  after suspend, and on crash + manual restart.
- **SuspendState (zero-or-one).** When F-C8 surface fires
  the Consumer enters a logical-suspend state pending
  architect (Mode-1) or Producer-mediated (Mode-2)
  resolution. Encoded by: a card-thread comment recording
  the surface trigger (the **primary** channel under both
  Modes; C-PLUGIN-1 workaround a) + Card.status remains
  `In Progress` (the suspended Consumer holds the card; it
  is NOT moved to Blocked unless F-C14 failure path
  triggers).

**Value objects.**

- **SessionId** — UUID-shaped; one per ConsumerProcess
  incarnation. Distinct from ConsumerLogical's identity.
- **SessionSlug** — short tag (`s-a7b3`) the Consumer
  generates at claim time; appears in claim commit
  message, ClaimMarker `session:` field, and the first
  card comment. Stable across the entire ConsumerLogical
  lifetime (one slug per logical Consumer, not per process
  incarnation).
- **Mode** — `Mode-1` (architect-spawned interactive) or
  `Mode-2` (Producer-spawned subagent). Bound at F-C1 spawn
  time; immutable for the ConsumerLogical's lifetime.
- **WorktreePath** — absolute filesystem path. Lives only
  on the ConsumerProcess's stdout / in the `worktree=`
  contract line (§1.4.1 F-C1 stdout shape). **MUST NOT** be
  written to ClaimMarker (regression-tested in
  `tests/test-claim-card-worktree.sh` — info-leak guard).

**Invariants enforced at root.**

- **I-1** — exactly one ConsumerLogical per Card.
- **I-7** — exactly one Worktree per ConsumerLogical;
  parallel Consumers therefore never share HEAD.
- **ClaimBranch existence ≡ ConsumerLogical alive** —
  deleting the branch is the only way to release the
  claim. The marker file alone is not enough; the *branch
  ref on origin* is the lock.
- **WorktreePath info-leak guard** — never appears on a
  public branch (the ClaimMarker's deliberate omission of
  a `worktree:` field; documented in `claim-card.sh`).
- **One ConsumerProcess alive at a time per ConsumerLogical.**
  Mode-2 wake-up after suspend creates a new process
  incarnation only after the prior one has exited.
- **Cross-card touch hard refuse (§1.4 F-C6).** Consumer
  detects writes to files owned by another Card and
  surfaces (F-C8) instead of silently editing across the
  scope boundary.
- **Cardinality (Mode-2-specific):** at v1, the ConsumerLogical
  must be reachable from a Producer that spawned it via the
  CC `Agent` tool. Codex Mode-2 is out-of-scope at v1
  (`MULTI_AGENT_DEVELOPMENT.md`).

**Physical location.**

- **ClaimBranch + ClaimMarker** — git ref + tracked file on
  origin.
- **Worktree** — filesystem directory (paths above).
- **PlanBrief** — gitignored file in user's repo.
- **ConsumerProcess transcript** — the platform's session
  transcript file (CC or Codex; paths in §3.1 SessionId
  entry).
- **SuspendState** — represented by a card-thread comment
  on GitHub (the only durable representation;
  C-PLUGIN-1 workaround a).

**TBD-1.** **`Worktree` lifecycle on Mode-2 wake-up after
process death on a different machine.** Today's claim-card.sh
creates worktrees at machine-local paths. If a Mode-2
ConsumerLogical's prior ConsumerProcess died on machine M1
and the Producer wakes a new ConsumerProcess on machine M2,
the original worktree is unreachable. Open question routed to
`0006-failure-modes.md` F-08 (cross-machine Consumer death).
The current spec assumes single-machine Mode-2 (P3 — solo /
small-team scale at v1).

---

### 3.3.4 ProducerSession aggregate

The long-lived Manager session. Spans Session context.
Considerably simpler than ConsumerLogical because Producer
holds no claim, owns no worktree, and is bound only by
informal "at most one per project at any time" cardinality
(§1.3.1 — no software lock).

**Root.** `ProducerSession` — identified by `SessionId`.

**Member entities.**

- **PreflightSnapshot (transient, one per architect prompt).**
  The result of one preflight piggyback check (ADR-0007
  derived idiom): which Consumers are stale, whether retro is
  due, board health degraded, which dispatched Consumers
  completed since last prompt. Lives only between
  prompt-arrival and prompt-response; disposable. Inserted
  at the top of Producer's response prose.

**Value objects.**

- **SessionId** — same shape as ConsumerProcess.SessionId.
- **PromptCount** — informal monotonically-increasing counter
  (purely for preflight-piggyback observability — every
  PreflightSnapshot is keyed by it).

**Invariants enforced at root.**

- **No daemon, ever (C-PLUGIN-2).** ProducerSession only
  acts in response to architect prompts; cannot push
  notifications. Wording like "Producer notifies you when
  X" is forbidden in feature specs without a `via preflight
  on next prompt` qualifier.
- **Cardinality** — at most one active per project at v1
  (informal; no software lock). Multiple architects sharing
  one board is out of scope at v1 (P3).
- **No code authorship.** I-2 — Producer reads PRs but does
  not author commits, run tests, or push to claim branches.
- **Every state mutation routed through ADR-0006 §3
  matrix.** Producer specs that describe an action without
  naming the matrix row it maps to are incomplete (§1.3
  cross-cutting principles).

**Physical location.** A CC or Codex CLI process plus its
session-transcript file (paths in §3.1 SessionId glossary
entry). The PreflightSnapshot is in-memory only and never
persisted.

---

### 3.3.5 HostBootstrap aggregate

Cross-repo, per-machine plugin install state. Spans Bootstrap
context.

**Root.** `HostManifest` — the file
`~/.board-superpowers/settings.yml` (host-shared locality per
ADR-0024; replaces `manifest.yml` from v0.4.0). Also
registers host-level automated stages (e.g.,
`m9.host.register-codex-hooks`) that replace the
README's manual instruction.

**Member entities.** None at v1 — all state is on the root.
(Future: a `VersionHistoryEntry` collection if architects
ask for visible upgrade history; flagged TBD-2 below.)

**Value objects.**

- **SchemaVersion** — integer; file-level `schema_version`
  field, per ADR-0021 two-section layout.
- **HostBootstrappedAt** — ISO 8601 timestamp.
- **LastSeenVersion** — semver string of the
  most-recently-launched plugin install (recorded as
  `last_seen_plugin_version` in host-shared settings.yml).
- **StagesCompleted** — `stages_completed[]` array of per-stage
  lifecycle entries, each carrying the three-layer fingerprint
  (`generation`, `target_state_hash`, `target_state`) per
  ADR-0013. Machine-managed; authoritative lifecycle source of
  truth for the unified check-script (ADR-0012).
- **ModulesProjection** — `modules.<id>` section (per ADR-0021)
  holding the architect-facing config-item projection derived
  from `stages_completed[]`. Regenerated by SKILL on stage
  completion; architects do not edit directly.

**Invariants enforced at root.**

- **I-12 schema versioning** — `schema_version` field on the
  `settings.yml` file; per-module `schema_version` under
  each `modules.<id>` section evolves independently (per
  ADR-0021). Versioned-and-additive only; lazy-on-read
  migration per ADR-0013 lifecycle.
- **I-13 — never tracked in git** (host-level fact; lives at
  `~/.board-superpowers/`).
- **Plugin-managed (I-11)** — `stages_completed[]` section
  silently overwritten by the plugin on each stage completion;
  no `block_hash` mechanism applies (no user-owned regions
  inside `stages_completed[]`). `modules.<id>` projection is
  also plugin-managed but hand-edits are detected on the next
  SKILL pass (per ADR-0021 authority-direction rule).
- **Single-host scope.** A HostManifest does NOT span multiple
  machines; each machine has its own. (Cross-machine sync is
  not a v1 concern.)

**Physical location.** `~/.board-superpowers/settings.yml`
(directory mode 0700).

**TBD-2.** Whether to record a per-version history list (e.g.,
`version_history: [{version, transitioned_at}]`) instead of
the v1 single `last_seen_plugin_version` scalar. Forensically
useful if an upgrade goes wrong months later. Deferred — at
v1 the changelog file
(`references/changelog/v<X>.md`) is the version-history
artifact per the bootstrapping-repo SKILL.

---

### 3.3.6 RepoBootstrap aggregate

Per-`(host, repo)` plugin install state. Spans Bootstrap context.
**Host-local** — never enters git. Each architect on each host
independently maintains a `RepoState` for each repo bootstrapped
on that host.

**Root.** `RepoState` — the file
`~/.board-superpowers/repos/<repo-identity>/settings.yml`
(repo-shared locality per ADR-0024), where `<repo-identity>` is
derived from the repo's GitHub `origin` URL as `<owner>-<repo>`
(per ADR-0017; e.g., `git@github.com:PanQiWei/board-superpowers.git`
→ `PanQiWei-board-superpowers`). Fallback for local-only repos
(no `origin`): `_path-<normalized-path>` prefix, where
`<normalized-path>` is the absolute path with leading `/` stripped
and remaining `/` replaced by `-`.

A sibling `state.yml` (TTL cache) co-exists at the same parent
directory for `external_validated_at` + `external_ttl_seconds`
fields that are excluded from the fingerprint hash per ADR-0013
(non-deterministic fields must not influence the lifecycle diff).

**Member entities.**

- **RoutingBlockTracker (per file: `CLAUDE.md`,
  `AGENTS.md`).** Each carries `block_hash` (SHA256 of the
  on-disk routing block bytes) + `injected_at` timestamp.
  Stored under `modules.m7_routing` in the `settings.yml`
  projection. Used by the routing-block injection stage to
  detect architect modification of the plugin-owned region
  (I-11).
- **StagesCompleted** — `stages_completed[]` array (per ADR-0013).
  The authoritative machine-readable status surface:
  one entry per setup stage, each carrying
  `{stage_id, status, completed_at, plugin_version, generation,
  target_state_hash, target_state, target_state_schema_version}`.
  The unified check-script (ADR-0012) diffs this array against
  the stage registry (ADR-0014) to compute the per-stage
  lifecycle state on each `SessionStart`.
- **ModulesProjection** — `modules.<id>` section (per ADR-0021)
  holding the architect-facing config-item projection derived
  from `stages_completed[]`'s `target_state` entries. Includes
  `modules.m4_audit` (audit DSN config, written by M4 stages),
  `modules.m7_routing` (routing block hashes), and any other
  modules whose stages bind to `repo-shared` locality.

**Value objects.**

- **SchemaVersion** — integer; file-level `schema_version`
  field; per-module `schema_version` under each `modules.<id>`
  section per ADR-0021.
- **RepoBootstrappedAt** — ISO 8601 timestamp (recorded in
  `stages_completed[]` as the first stage's `completed_at`).
- **LastSeenPluginVersion** — semver string of the
  most-recently-launched plugin install for this specific repo
  (recorded as `last_seen_plugin_version` in settings.yml).
- **BlockHash** — SHA256 hex (lowercase, 64 chars). One per
  RoutingBlockTracker entry, stored under
  `modules.m7_routing`.

**Invariants enforced at root.**

- **I-10 routing-block mirror rule** — the block content
  injected into `CLAUDE.md` / `AGENTS.md` is byte-identical
  to the source-of-truth block at
  `skills/using-board-superpowers/references/agentsmd-routing.md`.
- **I-11 plugin-owned vs user-owned region split** — the
  routing block within marker pair is plugin-owned;
  everything outside is user-owned. `BlockHash` is the
  enforcement mechanism (routing-block stage detects
  modification and surfaces a 3-way prompt instead of
  silently overwriting).
- **I-12 schema versioning** — `schema_version` field on the
  `settings.yml` file; per-module `schema_version` evolves
  independently (ADR-0021). Lifecycle diff and stage re-run
  replace the legacy lazy-on-read migration scripts.
- **I-13 host-local, never in git** — `settings.yml` lives outside
  any repo so multi-host / multi-architect collaboration on the
  same git remote does not silently overwrite each other's
  bootstrap state. Each architect's host bootstraps once per
  repo and keeps its own `RepoState`.
- **GitHub-based identity (ADR-0017)** — two clones of the same
  `(host, GitHub repo)` on the same machine share the same
  `<repo-identity>` directory and therefore the same
  `settings.yml`, `credentials.yml`, and `audit.db`. Per-clone
  isolation is preserved only for `repo-clone` locality files
  (`settings.local.yml`, `.venv/`).
- **Plugin-managed** — `stages_completed[]` section silently
  overwritten by the plugin on each stage completion; safe
  because the file is host-local. `modules.<id>` projection
  is also plugin-managed; hand-edits are detected on the next
  SKILL pass (ADR-0021). The `BlockHash` mechanism applies
  only to the routing block in `CLAUDE.md` / `AGENTS.md` it
  tracks, not to `stages_completed[]` fields.

**Physical location.** `~/.board-superpowers/repos/<repo-identity>/settings.yml`
(plus sibling `state.yml` TTL cache and `credentials.yml`) plus the
routing blocks it references in `<repo>/CLAUDE.md` and
`<repo>/AGENTS.md`.

---

### 3.3.7 RepoConfig aggregate

User-editable per-repo configuration. Spans Bootstrap context.
Distinct from RepoBootstrap because the **user owns the
content** (versus plugin-managed), and because hand-editing is
the supported mutation path (versus plugin-rewrite).

**Root.** `RepoConfig` — the file
`<repo>/.board-superpowers/settings.yml` (repo-git locality per
ADR-0024; replaces `config.yml` from v0.4.0). Per-user overrides
live in the sibling `<repo>/.board-superpowers/settings.local.yml`
(repo-clone locality; gitignored via `*.local.*` pattern).

**Member entities.** None.

**Value objects.**

- **ProjectRef** — opaque identifier for the active board,
  parsed by the active Kanban Protocol projection
  (`0005-contracts/00-kanban-protocol.md` § Implementation
  surface). Under the v1 GitHubProjectAdapter projection
  this is the `OWNER/NUMBER` string identifying the GitHub
  Project v2; future Linear / Jira projections carry their
  own `parse` / `serialize` rules. Roundtrip-stable per
  ADR-0005's type definitions (now rescoped to "the v1
  GitHubProjectAdapter implementation projection" by
  ADR-0025). Stored under the
  `<repo>/.board-superpowers/config.yml § kanban:` block per
  `0005-contracts/03-config-schemas.md`.
- **WipLimit** — positive integer; default `5`. Bound to the
  WIP soft-limit invariant (I-6). Stored in `settings.local.yml`
  at `modules.m5_repo_configuration.wip_limit` (repo-clone
  locality — per-user, not team-shared) per ADR-0024.
- **KanbanBackend** — enum `github-project-v2` (v1 only).
  Stored in `settings.yml` (repo-git) at
  `modules.m10_kanban.backend` per ADR-0024. ADR-0022 governs
  capability dispatch on the chosen backend.
- **WorktreeDirOverride (optional).** Two override paths:
  `BOARD_SP_WORKTREE_DIR` env var or `<repo>/.worktrees/`
  directory (must exist AND be gitignored); precedence
  documented in `claim-card.sh`.
- **AutonomyOverride (optional, list).** Per-action-id
  promotion of R → A (or future demotion of A → R). Project-
  layer overrides stored under `modules.m8_autonomy.autonomy_overrides`
  in `settings.local.yml`; user-layer overrides in
  `~/.board-superpowers/settings.yml:modules.m8_autonomy`
  (folded from legacy `overrides.yml` per ADR-0024). Project-
  layer overrides are themselves R-class writes (matrix row
  10 — modifying SoT).

**Invariants enforced at root.**

- **User-editable (repo-git layer)** — the plugin reads the
  `settings.yml` (repo-git) but does not overwrite
  architect-edited values; SKILL detects hand-edits to the
  `modules.<id>` projection and resolves per ADR-0021. The
  bootstrap stage writes the initial `settings.yml`; thereafter
  the architect owns the `modules.<id>` section.
- **I-13 tracked in git** — `settings.yml` (repo-git) is
  team-shared by definition; `settings.local.yml` (repo-clone)
  is gitignored via `*.local.*` pattern.
- **`ProjectRef` parse roundtrip-stable** — changing the
  string by hand requires the active Kanban Protocol
  projection's `parse()` to accept the new value (ADR-0005
  type contract under v1's GitHubProjectAdapter; future
  projections carry their own `parse` rule per
  `0005-contracts/00-kanban-protocol.md`).

**Physical location.** `<repo>/.board-superpowers/settings.yml`
(repo-git) + `<repo>/.board-superpowers/settings.local.yml`
(repo-clone, gitignored).

---

### 3.3.8 AuditTrail aggregate

The append-only forensic log. Spans Audit context.

**Root.** `AuditTrail` — logical handle (one per project; or
globally; precise scoping TBD in `0005-contracts.md`).

**Member entities.** None — the AuditTrail IS a stream of
immutable AuditEntry value objects.

**Value objects.**

- **AuditEntry** — one row in the BYO RDBMS. Schema (draft
  v1, from ADR-0006 §5):

  | Column | Type | Notes |
  |--------|------|-------|
  | `timestamp` | TIMESTAMPTZ | When the entry was written |
  | `project` | TEXT | `OWNER/NUMBER` string |
  | `session_id` | TEXT | The CC / Codex session originating the action |
  | `actor_role` | ENUM(`producer`, `consumer`) | Which role acted (lowercase to match §1.4 cross-cutting note) |
  | `action_id` | SMALLINT | Matrix row 1–14 from ADR-0006 §3 (Producer-side); symmetric Consumer rows TBD-3 below |
  | `payload` | JSONB | Action-specific data — see TBD-3 for per-`action_id` shape hardening |
  | `outcome` | ENUM(`success`, `failure`, `escalated`, `rejected`) | Terminal state of this action |

  Immutable once written; no UPDATE / DELETE supported in
  the contract.

**Invariants enforced at root.**

- **I-8 audit-log uniformity** — same schema for Producer
  and Consumer entries; cross-role timeline reconstruction
  walks one log, not two.
- **Append-only** — no UPDATE / DELETE in the contract.
- **R-class writes two entries** (one on propose, one on
  resolve `approved | rejected`); A-class writes one
  (on execution). Per ADR-0006 §1.
- **DB-unavailable degradation rule** — if the RDBMS is
  unreachable, every A-class action degrades to R-class
  (architect prompted). The AuditTrail aggregate is what
  the degradation guards: no write → no autonomy.
- **Persistence target constraints (ADR-0006 §5 + ADR-0009):**
  6-scheme allowlist — `postgresql://`, `postgres://`,
  `mysql://`, `mysql+pymysql://`, `sqlite://`, `sqlite3://`.
  SQLite is acceptable when host-local under
  `~/.board-superpowers/repos/<normalized>/audit.db`; SQLite
  inside the project tree, bare file paths, and public
  destinations (card comments, audit issues, GitHub
  Discussions) remain forbidden.
- **Credentials sourced from per-repo file, never host-shared
  (ADR-0015).** Either
  `~/.board-superpowers/repos/<repo-identity>/credentials.yml`
  (chmod 600; `audit_db_url:` field) or `BOARD_SP_AUDIT_DB_URL`
  env var. Env var takes precedence. Finalized in
  `0005-contracts.md`.

**Physical location.** A user-provided Postgres, MySQL, or
SQLite database (per ADR-0009). The plugin owns the schema
definition (lives in TBD-4) but does NOT own the database
itself.

**TBD-3.** Per-`action_id` payload shape hardening. ADR-0006 §5
notes payload is loose JSONB at v1; once Producer features
stabilize, each `action_id` should pin a payload schema (e.g.,
`action_id=1` Create Card → `{card_number, title, milestone,
threads, size, labels}`; `action_id=13` Dispatch Consumer →
`{card_number, mode, consumer_session_id, dispatch_concurrency}`).
Symmetric Consumer-side rows (claim, surface, terminate,
review-cycle response) need their own action_id assignments —
the matrix as written in ADR-0006 §3 is Producer-vantage; §1.4
cross-cutting note says rows 8 / 12 / 13 apply symmetrically
plus Consumer-only rows are needed (claim is referenced as a
Consumer A action without a row number in §1.4.1 F-C1). This is
the most concrete 0005-contracts.md handoff from 0003.

**TBD-4.** Migration tool / schema-DDL ownership. The plugin
ships the schema *definition*; whether it ships migrations
(Alembic-style) for evolving the schema across plugin versions
is open. Initial expectation: ship a single canonical DDL file
+ a migrations directory keyed by plugin version; no automated
runner (architect runs migrations explicitly). Lands in
`0005-contracts.md`.

---

### 3.3.9 SpecPointer (collection-shaped)

Lightweight — calling it a "full aggregate" overstates what
v1 needs. Spans Spec context. Listed here so the navigation
chain from Card → Spec is explicit.

**Conceptual root.** The set of `(CardNumber → list of spec
references)` derived from each Card body's Context section.

**Member "entities."** Each spec reference is a string the
Consumer's F-C2 step resolves — typically a repo-relative
path like `docs/superpowers/specs/2026-04-22-oauth-design.md`,
optionally a third-party storage URL (TBD whether v1 ships
that resolver — see Notes in §1.5 / §1.4 cross-cutting).

**Value objects.**

- **SpecRef** — repo-relative path or URL string.

**Invariants.**

- **I-9 thin-pointer card** — the pointer must resolve at
  Backlog → Ready transition (Producer's gate per ADR-0006
  row 5 precondition). Consumer never re-derives a missing
  spec (would either silent-under-deliver or burn architect
  attention via over-surfacing).
- **No plugin-side mutation.** board-superpowers does not
  edit user spec docs; only reads them.

**Physical location.** User-owned `docs/` tree (most v1
cases) or third-party storage (configured at bootstrap if
that path lands).

**Why this is "collection-shaped" instead of an aggregate-
proper.** No identity beyond "the spec(s) for Card #N." No
internal lifecycle. No invariants beyond "the link in the
Card body resolves." Calling it an aggregate would invite
the plugin to grow opinions about spec format, location, and
quality — which P7 + I-9 explicitly refuse.

---

### 3.3.10 Cross-aggregate cardinality summary

A quick lookup for the "how many of X relate to Y" question.
Detailed diagrams in `05-relationships.md`.

| Aggregate | Cardinality with neighbors |
|-----------|----------------------------|
| **Card** ↔ **PR** | 1 Card ↔ 0..1 PR (a Card may be Done without a PR only via rare manual GitHub intervention; the typical path is one PR per Card; I-1) |
| **Card** ↔ **ConsumerLogical** | 1 Card ↔ 0..1 alive ConsumerLogical (atomic claim enforces; I-1) |
| **ConsumerLogical** ↔ **ConsumerProcess** | 1 ConsumerLogical ↔ 0..N sequential ConsumerProcess incarnations (Mode-2 wake-up, crash + restart) |
| **ConsumerLogical** ↔ **Worktree** | 1 ↔ 1 (I-7) |
| **ConsumerLogical** ↔ **ClaimBranch** | 1 ↔ 1 (existence ≡ alive) |
| **ConsumerLogical** ↔ **ClaimMarker** | 1 ↔ 1 (lifecycle bound to ClaimBranch) |
| **ConsumerLogical** ↔ **PR** | 1 ↔ 0..1 (the same Consumer that claimed opens the PR; F-C12) |
| **ProducerSession** ↔ **Project** | At most 1 active ProducerSession per Project (informal; §1.3.1) |
| **ProducerSession** ↔ **PreflightSnapshot** | 1 ↔ 0..N over time, exactly 1 alive at any given prompt boundary |
| **HostManifest** ↔ machine | 1 ↔ 1 |
| **RepoState** ↔ Project | 1 ↔ 1 (multi-kanban — 1 repo : N boards — is a v1.x roadmap item per ADR-0025; if it lands, RepoState gains a per-board sub-key but the aggregate boundary stays). |
| **RepoConfig** ↔ Project | 1 ↔ 1 (same multi-kanban caveat). |
| **AuditTrail** ↔ AuditEntry | 1 ↔ 0..N (append-only) |
| **AuditTrail** ↔ Project | 1 ↔ 1 (or 1 ↔ N globally — precise scoping TBD-5) |
| **Card** ↔ **AuditEntry** | 1 ↔ 0..N (every Card-mutating action emits an entry; reads do not) |

**TBD-5.** Whether AuditTrail is per-Project or globally scoped
(one DB serves multiple projects). Decision driver: whether
architects with multiple projects want one DB or N. Lands in
`0005-contracts.md`.

---

### Notes on TBD entries collected here

- **TBD-N1** (Card aggregate). Concrete representation of
  Card.threads (label namespace? GitHub Project v2 custom
  field? Something else). Currently ad-hoc per project. §1.1
  flags Thread as a board-superpowers-original concept whose
  physical encoding has not yet landed; promoting it to a
  hard schema is a follow-up.
- **TBD-1** (ConsumerLogical aggregate). Cross-machine
  Worktree lifecycle on Mode-2 wake-up. Routed to
  `0006-failure-modes.md` F-08.
- **TBD-2** (HostBootstrap aggregate). Per-version history
  list inside HostManifest. Deferred.
- **TBD-3** (AuditTrail aggregate). Per-`action_id` payload
  shape hardening + symmetric Consumer-side `action_id`
  assignments. Lands in `0005-contracts.md` (the most
  concrete handoff from 0003).
- **TBD-4** (AuditTrail aggregate). Migration tool / schema-
  DDL ownership convention. Lands in `0005-contracts.md`.
- **TBD-5** (cross-aggregate cardinality). Per-project vs
  global AuditTrail scope. Lands in `0005-contracts.md`.

These are recorded honestly: each has a one-line rationale for
why it isn't pinned at v1 and a destination doc that will
finalize it. None blocks the v1 0003 spec.
