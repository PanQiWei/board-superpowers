### 1.7 Cross-cutting invariants

Project-wide invariants that span Producer + Consumer +
Bootstrap + Decomposition. Each invariant is a contract that
multiple features simultaneously presuppose; breaking any one
breaks every feature in the "Cited by" line.

These are the contracts a PR reviewer checks when a feature
modification looks innocent — most of the load-bearing
invariants in board-superpowers are not local to one feature.

**I-1. One card = one Consumer session = one PR.** Each
Consumer session binds to one card at claim time (F-C1) and
exits at PR merge or terminal Blocked (F-C14). No multi-card
sessions, no PR that resolves multiple cards, no card resolved
across multiple PRs. Cited by: F-C0, F-C1, F-C12, F-C13, F-C14;
Producer F-04 (recommendation respects one-card-per-session
when sizing the dispatch wave).
**Aggregate:** Card / ConsumerLogical / PR (one-to-one chain;
see `0003-domain-model/03-aggregates-and-entities.md`).
What breaks: parallelism
guarantees collapse (two cards in one session re-introduces the
HEAD-trample problem worktree isolation solves); audit-log
attribution becomes per-session-not-per-card.

**I-2. Producer never touches code; Consumer never owns merge
(Producer-Consumer hard-floor symmetry).** Producer reads
PRs (F-02, F-03) but does not author commits, run tests, or
push to claim branches. Consumer authors commits (F-C4) but
cannot merge its own PR (matrix row 12 — auto-merge = N for
Consumer, hard floor). Both sides have the *other side's
defining action* as a hard floor. Cited by: §1.3 cross-cutting
principles, F-C7 (permission boundary hard-floor),
ADR-0006 row 12.
**Aggregate:** ProducerSession (cannot author commits) +
PR (Consumer cannot self-merge) — see
`0003-domain-model/03-aggregates-and-entities.md`.
What breaks: the human-merge premise (P6 —
human verification is a first-class output) collapses if
Consumer can self-merge; the role separation in §1.2 collapses
if Producer ships code.

**I-3. Multi-architect symmetry.** Any GitHub user with
maintainer rights on the project is treated as "an architect"
by the plugin. board-superpowers does not model role / team /
permission concepts at the plugin layer — those live in
GitHub. The Producer / Consumer split is per-session (per §1.2)
and orthogonal to who the human user is. Cited by: F-C13
(stakeholder routing — comments treated comment-source-
agnostic), Producer F-03 (no per-architect filtering on
blocked-on-architect), §1.4 cross-cutting principles.
**Aggregate:** cross-cutting; bears on Card aggregate
(no per-architect routing on Card.assignees) and PR aggregate
(F-C13 stakeholder-routing rule).
What breaks: any feature that filters by GitHub user identity
silently hardcodes a single-architect assumption; multi-
maintainer projects then mis-route or under-surface work. This
folds in the §1.4 F-C13 follow-up flag.

**I-4. Default + override + accountability.** A recurring
governance pattern: a sane default executes automatically;
exceptions are allowed with friction (an explicit override or
written justification); exceptions leave an audit trail (PR
description, audit-log row, card-thread comment). Cited by:
ADR-0006 D-AUTONOMY-1 (every R row is "default + propose +
audit"), F-C5 (TDD-skip — default by `type:*`, override with
written justification in PR), F-C7 (permission boundary —
soft default + ambiguity-fallback surface + hard floor with
audit), F-C6 (cross-card touch — default refuse, surface for
arbitration), F-C13 (stakeholder routing — default integrate-
as-context, surface when scope expansion implied). The pattern
recurs often enough that it is now codified as **P8 in
`0001-positioning.md`** (Default + override + accountability)
— this invariant is the cross-cutting trace P8 generalizes
from.
**Aggregate:** cross-cutting governance pattern; surfaces in
AuditTrail's R-class two-entry rule (propose + resolve), in
ConsumerLogical's permission-boundary three-layer model, and
in PR aggregate's TDD-skip-with-justification line.
What breaks: governance becomes
ad-hoc-per-feature, accountability becomes lossy, override
proliferation goes undetected.

**I-5. Plugin form derived constraints.** Every feature with
verbs like *monitor*, *detect*, *trigger automatically* MUST
close under C-PLUGIN-1 (no in-memory cross-session IPC),
C-PLUGIN-2 (no daemon thread), and C-PLUGIN-3 (controlled
Consumer-dispatch concurrency). Cited by: §1.3 cross-cutting
principles, every Producer feature in Group D, F-07, F-11,
F-12, F-13, ADR-0007 (canonical).
**Aggregate:** ProducerSession (PreflightSnapshot is the
in-memory artifact through which "automatic" behavior closes
under no-daemon).
What breaks: feature
descriptions that promise "real-time" or "continuous
monitoring" land specs that physically cannot run as plugins;
implementation either gold-plates a daemon (violating P5) or
fakes the contract (violating user trust).

**I-6. Soft WIP limit.** `In Progress + suspended + In Review`
counts toward the limit; `Blocked` does NOT. Default `5`,
configurable in `.board-superpowers/config.yml:wip_limit`. Soft
means: Manager warns when the limit is reached but does not
block dispatch — the architect can override deliberately. Cited
by: Producer F-04 (dispatch recommendation), F-07 (overnight
batch concurrency), `board-protocol/SKILL.md` "WIP limit",
ADR-0006 row 9 (adjust WIP limit = A).
**Aggregate:** Card (StatusBinding decides WIP membership) +
RepoConfig (WipLimit value object).
What breaks: dispatch
recommendations stop reflecting actual architect attention
budget; flow degrades; "swarm to unblock" patterns become
silently impossible because Blocked counts twice.

**I-7. One-card-one-worktree.** Every Consumer session binds
to one card and runs all post-claim work inside one worktree
created by `claim-card.sh`. Default location:
`$HOME/.config/superpowers/worktrees/<project>/<branch>`.
Worktree persists across Mode-2 terminate-and-resume cycles;
self-deletes on success path; preserved on failure path for
human takeover. Cited by: F-C1 stdout shape (`worktree=`
contract), F-C3 (`cd` into worktree), F-C13 (review-cycle work
in same worktree), F-C14 (success vs failure path treatment),
ADR-0003.
**Aggregate:** ConsumerLogical (Worktree is a member entity
1:1 with the root).
What breaks: parallel Consumer sessions trample each
other's HEAD; review-cycle responses target the wrong branch;
cleanup races destroy in-flight work.

**I-8. Audit-log uniformity.** Same audit-entry schema (per
ADR-0006 §5) for both `actor_role: producer` and
`actor_role: consumer` actions. Cross-role timeline
reconstruction at retro time (F-12, F-13) walks one log, not
two. Cited by: ADR-0006 §5, every Producer feature with audit-
log entries, every Consumer feature with audit-log entries
(F-C1, F-C3, F-C4, F-C6, F-C7, F-C8, F-C9, F-C10, F-C11,
F-C12, F-C13).
**Aggregate:** AuditTrail (the AuditEntry value object is the
single shared schema; see
`0003-domain-model/03-aggregates-and-entities.md` § 3.3.8).
What breaks: retro routines become per-role
joined queries (operationally complex); cross-session
attribution becomes lossy where Producer dispatched a Consumer
and the timeline crosses both sides.

**I-9. Thin-pointer card.** The Card body is the Producer's
contract surface. For cards needing spec / plan / design depth
beyond what fits inline, the body links to spec docs (in-repo
under `docs/` or in third-party storage configured at
bootstrap) by repo-relative path. Consumer (F-C2) self-fetches;
Consumer never re-derives a missing spec. Producer's Backlog →
Ready gate (ADR-0006 row 5 precondition) guarantees the
pointer resolves. Cited by: F-C2, §1.4 cross-cutting
principles, §1.6.3 (card body schema), `card-schema.md`.
**Aggregate:** Card (CardBody member entity) +
SpecPointer (collection-shaped, Spec context).
What breaks: Consumer's input completeness assumption collapses;
Consumer either guesses the spec (silent under-delivery) or
surfaces F-C8 on every card (over-surfacing burns architect
attention).

**I-10. Routing-block mirror rule.** The routing block
injected into downstream `CLAUDE.md` and `AGENTS.md` is
byte-identical to the fenced block in
`skills/using-board-superpowers/references/claudemd-routing.md`
between the marker pair. Edits to one MUST land in the other
in the same commit. Cited by: F-B2, F-B4, `CLAUDE.md`
change-impact matrix, the `<!-- board-superpowers:routing -->`
marker pair detected by `check-deps.sh`.
**Aggregate:** RepoBootstrap (RoutingBlockTracker member
entity carries the BlockHash that enforces the mirror).
What breaks: routing
diverges between source-of-truth and downstream installs;
bootstrap re-runs after a plugin update produce inconsistent
routing across freshly-bootstrapped vs. previously-bootstrapped
projects.

**I-11. Plugin-owned vs user-owned region split.** Some files
under board-superpowers' control are plugin-managed (the plugin
writes them, the user does not edit them); others are
user-editable (the plugin reads them, the user owns the
content); some files are mixed (the plugin owns a marked
region, the user owns the rest). The rules:
- `~/.board-superpowers/manifest.yml` and
  `~/.board-superpowers/repos/<normalized-repo-path>/state.yml` are **plugin-managed**.
  User edits there are silently overwritten on the next
  state-update cycle and the `block_hash` mechanism does NOT
  apply (these files have no user-owned regions).
- `<repo>/.board-superpowers/config.yml` is **user-editable**.
  The plugin reads `wip_limit`, `project`, etc.; future fields
  appear as commented-out placeholders rather than schema-
  versioned migrations, deliberately matching the existing
  hand-editable convention.
- Routing blocks in `CLAUDE.md` and `AGENTS.md` are **mixed**:
  plugin-owned within the marker pair `<!-- board-superpowers:routing -->`
  / `<!-- /board-superpowers:routing -->`, user-owned outside
  the markers. The `block_hash` field in `state.yml`
  (computed by F-B2 and re-checked by F-B4) enforces the
  boundary at upgrade time — user modification of the in-marker
  region is detected via SHA256 mismatch and surfaced for a
  3-way decision (replace / merge / leave alone), never
  silently overwritten. Cited by: F-B2 (initial hash write),
  F-B4 (hash compare + 3-way prompt), I-10 (mirror rule
  source-of-truth side).
**Aggregate:** HostBootstrap + RepoBootstrap (plugin-managed)
vs RepoConfig (user-editable) vs the routing block (mixed
ownership; BlockHash is the boundary enforcer).
What breaks: silent overwrite of user
  customizations on plugin upgrade; user-edited plugin state
  files get reverted between sessions with no audit trail.

**I-12. Schema versioning + automatic migration.** Both
`~/.board-superpowers/manifest.yml` and
`~/.board-superpowers/repos/<normalized-repo-path>/state.yml` carry an integer
`schema_version` field. On read, if the on-disk value is older
than the version this plugin build understands, the plugin
runs migration scripts at
`${CLAUDE_PLUGIN_ROOT}/scripts/migrations/<file>-v<N>-to-v<N+1>.sh`
in sequence to bring the file up to current. Migration timing
is **lazy-on-read** (run when the file is first opened in a
session) rather than eager-on-startup, matching Confluent
Schema Registry's lazy-migration pattern and avoiding a
session-startup tax on every cold session that doesn't
actually need state mutation. Migrations are
versioned-and-additive — they add fields, they do not remove or
rename. Older plugin builds reading newer schema files MUST
fail loudly (refuse to operate, surface "this state file was
written by plugin v<X>; you're on v<Y>; please upgrade") rather
than silently dropping unrecognized fields. Cited by: F-B1,
F-B2, F-B3, F-B4.
**Aggregate:** HostBootstrap (HostManifest.SchemaVersion) +
RepoBootstrap (RepoState.SchemaVersion). RepoConfig is
deliberately NOT versioned (uses commented placeholders
instead — I-11).
What breaks: schema evolution requires user
manual editing; old installs become broken on upgrade because
the in-place file no longer parses; the YAGNI initial v1 shape
becomes a permanent ceiling instead of a starting point.

**I-13. Team-shared declarations in git, host-local state out.**
The placement strategy across `<repo>/.board-superpowers/` and
`~/.board-superpowers/repos/<normalized>/` enforces four rules:
- `<repo>/.board-superpowers/config.yml` — committed (user
  decisions about WIP limit, project ref, etc. — team-shared by
  definition).
- `<repo>/.board-superpowers/claims/` — gitignored locally
  (per-session forensic state); individual marker files get
  force-committed only to claim branches by `claim-card.sh`,
  never to `main`.
- `~/.board-superpowers/repos/<normalized>/state.yml` — host-local,
  never tracked. Each architect on each host independently runs
  F-B2 and maintains its own bootstrap state. The normalized
  sub-directory name is the repo's absolute path with leading `/`
  stripped and remaining `/` replaced by `-` (per
  [`0005-contracts/07-path-conventions.md`](../0005-contracts/07-path-conventions.md)).
- `~/.board-superpowers/manifest.yml` — host-level plugin install
  state (per-machine, never tracked). Same enclosing directory as
  the per-repo state, owned by HostBootstrap.

Cited by: F-B2 (writes both `<repo>/.board-superpowers/config.yml`
and `~/.board-superpowers/repos/<normalized>/state.yml`); F-B4
(reads / re-writes `state.yml` per host); ADR-0002 (claim marker
force-commit-to-claim-branch contract).
**Aggregate:** RepoConfig (config.yml in git), ConsumerLogical
(ClaimMarker in git only on its own branch), RepoBootstrap
(RepoState host-local), HostBootstrap (HostManifest host-local).
What breaks if violated:
  putting `state.yml` back inside the repo and tracking it
  re-introduces the silent cross-collaborator overwrite race
  (architect A pushes state.yml → architect B's next session
  silently rewrites it on the next state-update → A pushes again
  → no audit, ping-pong); putting team-shared declarations like
  `config.yml` outside the repo loses cross-architect symmetry.

