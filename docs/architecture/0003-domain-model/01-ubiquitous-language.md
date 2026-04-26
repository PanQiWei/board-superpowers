## 3.1 Ubiquitous language

Alphabetical glossary. Every term used in board-superpowers
docs and skills with a precise meaning has one entry here.
Each entry: a one-paragraph definition + the doc that owns
the canonical detail + the 0003 sub-file that expands it
(when applicable).

This file is the **navigation hub for entity-level
questions**. Other docs link in; the canonical contract for
a term lives at the link this entry points out to.

When two docs use the same word for different things, they
get separate entries here (e.g., **Status** the canonical
enum vs. **Status field** the GitHub Project v2 column).

---

### A

**ActionId.** Integer 1–14 keying ADR-0006 §3 permission
matrix rows. Rides on every `AuditEntry` so post-hoc analysis
can join entries to the matrix row that authorized the action.
Source: ADR-0006 §5 audit-entry schema. Expanded in:
`03-aggregates-and-entities.md` § AuditTrail.

**Aggregate.** A consistency boundary — the entity (root) plus
the lifecycle-bound entities and value objects that change
together. board-superpowers uses aggregates as a *navigation
device*, not a code-pattern: each aggregate names a thing and
points at the artifact that physically stores it. Source:
this directory. Expanded in: `03-aggregates-and-entities.md`.

**Architect.** The human user who runs both Producer and
Consumer sessions, verifies PRs, and merges. Single-person
or 2–3-person tight team at v1 (P3, P1). Multi-architect
symmetry is invariant I-3: any GitHub maintainer is treated
as "an architect"; no per-architect plugin-layer roles.
Source: `0001-positioning.md` (Audience), §1.2 (roles),
I-3. Expanded in: `02-bounded-contexts.md` (cross-cutting).

**AuditEntry.** One immutable row in the BYO-RDBMS audit log
recording one Producer or Consumer action (A-class executed,
or R-class proposed/resolved). Schema (draft): `timestamp`,
`project`, `session_id`, `actor_role`, `action_id`, `payload`
(JSONB), `outcome`. Source: ADR-0006 §5. Expanded in:
`03-aggregates-and-entities.md` § AuditTrail and
`04-domain-events.md` § AuditEntry.Written.

**AuditTrail.** The aggregate that owns the append-only
sequence of `AuditEntry` rows for one project (or globally,
implementation TBD). The plugin ships the schema and write
mechanism; the architect provides the database (P7 applied —
mechanism, not infrastructure). Source: ADR-0006 §5. Expanded
in: `03-aggregates-and-entities.md`.

**AutonomyClass.** A / R / N — Auto / Reserved / No-go. The
classification ADR-0006 §1 assigns each Producer (and
symmetrically each Consumer) action. v1: A=7, R=7, N=0.
Source: ADR-0006 §1, §3. Expanded in:
`03-aggregates-and-entities.md` § AuditTrail (action_id
column) and `04-domain-events.md`.

**AutonomyOverride.** Architect-supplied promotion of an R-class
action to A-class (or future demotion of an A to R), exposed at
two layers: user-level `~/.board-superpowers/overrides.yml` and
project-level `.board-superpowers/config.yml`. Project-layer
overrides are themselves R-class writes (matrix row 10).
Source: ADR-0006 §4. Schema TBD in `0005-contracts.md`.

### B

**BlockHash.** SHA256 (lowercase hex, 64 chars) of the bytes
between the routing-block marker pair in `CLAUDE.md` /
`AGENTS.md`, stored at
`state.yml:routing_blocks[].block_hash` keyed by the matching
`target_file` element. F-B4 compares it on upgrade to detect
architect modification of an otherwise plugin-owned region
(I-11). Source: §1.5.2 (F-B2), §1.5.4 (F-B4), I-10, I-11.
Expanded in: `03-aggregates-and-entities.md` § RepoBootstrap.

**Blocked.** Status enum value. Terminal-ish state — does NOT
count toward the WIP limit (I-6). Owner of the transition into
Blocked: Consumer (F-C13/F-C14 failure path) or Manager (R via
ADR-0006 row 6). Source: ADR-0005 (Status type), `board-protocol`
(state machine), §1.7 I-6. Expanded in:
`03-aggregates-and-entities.md` § Card and
`05-relationships.md`.

**BoardAdapter.** The contract every backend (GitHub Project
v2, Linear, Jira, etc.) implements. Five methods: `list_cards`,
`get_card`, `get_status_options`, `create_card`,
`set_card_status` + `parse` / `serialize` for `ProjectRef`.
Source: ADR-0005. Expanded in: `02-bounded-contexts.md`
(Board context boundary) and `06-context-map.md` (the
Anti-Corruption Layer seam).

**Board context.** The bounded context owning Card / Status /
Project / Label / ClaimMarker (logical layer). Talks to every
other context via the BoardAdapter or via GitHub artifacts
directly. Source: this directory. Expanded in:
`02-bounded-contexts.md`.

**Board Manager.** The specific Producer role at v1
(§1.3.1 — long-lived, aggregate-view, architect-initiated).
Synonym: **Manager**. Source: §1.3.1. Expanded in:
`03-aggregates-and-entities.md` § ProducerSession.

**Board Consumer.** A Consumer-role session running the
**Implementer** specific role (§1.4.1). Synonym: **Consumer**
when context is unambiguous. Source: §1.4.1. Expanded in:
`03-aggregates-and-entities.md` § ConsumerLogical.

**Bootstrap context.** The bounded context owning HostManifest /
RepoState / RepoConfig / RoutingBlock / FeatureActivation. Talks
to Board context only via `BoardAdapter.get_status_options`
during F-B2 validation; otherwise self-contained. Source: this
directory. Expanded in: `02-bounded-contexts.md`.

### C

**Card.** A leaf work item. One GitHub Issue + one Project v2
item linked to it; the Issue body follows the §1.6.3 schema and
ends with `<!-- board-superpowers:card -->`. The unit Consumers
claim, Producers create, the architect verifies. Source:
`board-protocol/SKILL.md`,
`decomposing-into-milestones/references/card-schema.md`,
ADR-0005 § Card. Expanded in: `03-aggregates-and-entities.md`
§ Card aggregate.

**CardNumber.** The integer identifier `N` GitHub assigns to
the Issue at creation. Used in claim branch name (`claim/<N>-<slug>`),
marker file path (`.board-superpowers/claims/<N>.claim`), kick-off
prompt (`[board-card:#N]`). VO of the Card aggregate. Source:
`board-protocol/SKILL.md`, `claim-card.sh` arg validation.

**Cardinality.** Manager: at most one active per project (informal,
no software lock — §1.3.1). Implementer: at most one per card,
enforced atomically by ClaimBranch creation (§1.4.1, I-1).
Source: §1.3.1, §1.4.1, I-1. Expanded in:
`03-aggregates-and-entities.md`.

**ClaimBranch.** The remote git ref `claim/<N>-<slug>` whose
existence on origin IS the distributed lock (ADR-0002). Created
atomically by `git push --force-with-lease=<ref>:` — first
push wins; race losers see exit 10. The branch is also the
feature branch the eventual PR targets. Source: ADR-0002,
`scripts/claim-card.sh` header, §1.4.1 F-C1. Expanded in:
`03-aggregates-and-entities.md` § ConsumerLogical.

**ClaimMarker.** The file `.board-superpowers/claims/<N>.claim`
(YAML; fields `card`, `session`, `claimed_at`, `base`, `branch`).
Force-committed (`git add -f`) onto the ClaimBranch even though
its parent directory is gitignored locally. Side effect: visible
on origin as on-public proof that a Consumer holds the claim.
**Never** carries an absolute local path (regression-tested in
`tests/test-claim-card-worktree.sh`). Source: `claim-card.sh`
(write site), I-13 (gitignore rule). Expanded in:
`03-aggregates-and-entities.md` § ConsumerLogical.

**Codex CLI.** OpenAI's CLI plugin host. Mode-1 supported on
both CC and Codex; Mode-2 is **Claude Code only at v1** (§1.4
cross-cutting principles). Source: `PLUGIN_DEVELOPMENT.md`,
`MULTI_AGENT_DEVELOPMENT.md`.

**Composition.** P4b operationalization — board-superpowers
delegates real work to `superpowers:*` and `gstack:/*`,
never reimplements TDD / brainstorming / QA / review /
security audit. Source: `0001-positioning.md` P4b, ADR-0004.

**ConsumerLogical.** A *logical* Consumer role binding to one
Card. Persists across Mode-2 terminate-and-resume cycles
(its Worktree + ClaimBranch + ClaimMarker survive process
death). One per claimed Card. Source: §1.4.1 cardinality,
§1.4 Mode topology. Expanded in:
`03-aggregates-and-entities.md` § ConsumerLogical.

**ConsumerProcess.** A *physical* CC or Codex CLI process
incarnation that runs one ConsumerLogical for one stretch.
Multiple ConsumerProcesses may incarnate the same
ConsumerLogical sequentially (Mode-2 wake-up after suspend;
crash + restart). Source: §1.4 Mode topology, F-C14
(crash path). Expanded in: `03-aggregates-and-entities.md`
§ ConsumerLogical.

### D

**D-AUTONOMY-1.** Producer autonomy boundary decision (ADR-0006).
Operationalized via the §3 14-row matrix and the §2 triage rule.
Source: ADR-0006. Expanded in:
`03-aggregates-and-entities.md` § AuditTrail.

**D-META-1.** P7 operationalization — the plugin ships
mechanism (conversational scaffolds, capture machinery), not
project-specific configuration (lint rules, PR template
content, fixed WIP). Source: `0001-positioning.md` P7, §1.3
cross-cutting principles. Bears on `RepoConfig`'s minimal
shape and on the `state.yml:features_enabled` lazy default-on
pattern.

**Domain event.** A state-changing moment that crosses an
aggregate boundary or that another aggregate observes. Not
"every state mutation" — only the ones that matter to other
aggregates. Source: this directory. Expanded in:
`04-domain-events.md`.

**Done.** Status enum value. Reached when the PR merges
(GitHub auto-close on `Closes #<N>`). Source: ADR-0005,
`board-protocol`, §1.4 F-C14 success path.

### E

**Epic.** A work-grouping concept in canonical agile (Scrum/Jira).
board-superpowers uses **Thread** instead — see Thread.
Source: §1.1.

**Event-driven cadence.** Replaces calendar-driven cadence —
Retro / Daily inspection / Refinement / Flow-metrics aggregation
all trigger on events (Milestone close, N-cards-completed,
session start), not on Sprint boundaries (§1.1). Source: §1.1.

### F

**FeatureActivation.** Entry in `state.yml:features_enabled`
naming a per-feature toggle for one repo. v1 list-shape (on/off
only); future map-shape per-feature config through schema
migration (§1.5 Notes). Source: §1.5 (state.yml shape), F-B4
(default-on with opt-out). Expanded in:
`03-aggregates-and-entities.md` § RepoBootstrap.

### G

**gstack.** External plugin providing design / QA / security /
review skills (`/office-hours`, `/plan-eng-review`, `/qa`,
`/cso`, `/review`, `/codex`, `/browse`, ...). Hard runtime
dependency (P4b, ADR-0004). Source: `0001-positioning.md` P4b,
ADR-0004, `README.md` install. Detected by `check-deps.sh`
(§1.5.0).

### H

**HostBootstrap.** The aggregate owning the host-layer state
(`~/.board-superpowers/manifest.yml`) and the host version-
transition lifecycle (F-B1, F-B3). Source: §1.5. Expanded in:
`03-aggregates-and-entities.md` § HostBootstrap.

**HostManifest.** The file
`~/.board-superpowers/manifest.yml` (mode 0700 dir; YAML;
fields at v1: `schema_version: 1`, `host_bootstrapped_at`,
`last_seen_version`). Per-machine, never tracked in git
(I-13). Source: §1.5 state-file table, I-13.

### I

**Implementer.** The single Consumer specific role at v1
(§1.4.1). Owns end-to-end card delivery: claim → fetch spec →
implement → self-check → PR → review-cycle → terminate.
Synonym (when context unambiguous): **Consumer**. Source:
§1.4.1.

**Invariant.** A fact that must hold across all code paths.
The 13 cross-cutting invariants (I-1..I-13) live in
`0002-product-features-and-flows/07-cross-cutting-invariants.md`
and are referenced from each aggregate they apply to in
`03-aggregates-and-entities.md`.

**INVEST.** Wake-2003 checklist (Independent / Negotiable /
Valuable / Estimable / Small / Testable). Refusal-condition
gate at decomposition time (§1.6.1) — failing any letter
blocks a Card from landing in Backlog. Source: §1.6.1,
`decomposing-into-milestones/SKILL.md`. Card aggregate
invariant (referenced from `03-aggregates-and-entities.md`).

### K

**Kanban.** The board model board-superpowers inherits
(Anderson 2010): pull system, WIP limits, classes of service.
Specifically NOT inheriting Sprint or velocity tracking
(§1.1). Source: §1.1.

### L

**Label.** GitHub repository label. Two namespaces created by
`bootstrap-project.sh`: `type:*` (`feature`, `bug`, `chore`,
`refactor`, `epic`) and `size:*` (`XS`, `S`, `M`, `L`).
BoardAdapter contract: adapters do NOT auto-create labels;
unknown label → `schema_mismatch` error (ADR-0005). Source:
`bootstrap-project.sh` header, ADR-0005.

### M

**Manager.** See **Board Manager**.

**Marker comment.** The trailing HTML comments
`<!-- board-superpowers:card -->` (Card body),
`<!-- board-superpowers:pr -->` (PR body),
`<!-- board-superpowers:routing -->` /
`<!-- /board-superpowers:routing -->` (CLAUDE.md / AGENTS.md
routing block). Each is a machine-readable identifier that
distinguishes board-superpowers artifacts from generic
content. Source: `card-schema.md`, `pr-template.md`,
`agentsmd-routing.md`, I-10. Expanded across multiple
aggregates in `03-aggregates-and-entities.md`.

**Milestone.** Outcome bucket on the **outcome axis** of work
(§1.1). Maps to GitHub Project's native Milestone field at
v1. Card.milestone is 0-or-1; required to be set before a
Card transitions Backlog → Ready (§1.1). Source: §1.1.

**Mode-1.** Architect-spawned interactive Consumer session —
the architect pastes a `[board-card:#N]` kick-off into a
fresh CC or Codex CLI session. Both platforms supported.
Mode-1 is the superset; every Consumer feature works here.
Source: §1.4 Mode topology.

**Mode-2.** Producer-spawned subagent Consumer session — a
Producer session calls CC's `Agent` tool with the Consumer
agent definition. **Claude Code only at v1.** Source: §1.4
Mode topology, `MULTI_AGENT_DEVELOPMENT.md`.

### N

**Negative invariant.** A fact about what must NEVER hold.
Examples: "ClaimMarker MUST NOT carry an absolute local
path" (regression-tested), "audit-log MUST NOT persist to
SQLite or local file" (ADR-0006). Source: invariant list +
ADR consequences sections.

### O

**Override.** See **AutonomyOverride**.

### P

**PR (PullRequest).** A GitHub Pull Request opened by Consumer
(F-C12) targeting the ClaimBranch. Body follows §1.8 schema
(Summary / Test Plan from delegated skill + Automated
Verification + optional Human Verification TODO + Retro
Notes + trailing `<!-- board-superpowers:pr -->` marker).
One PR per Card per Consumer session (I-1). Source: §1.8,
`board-protocol/SKILL.md`. Expanded in:
`03-aggregates-and-entities.md` § PR.

**Plan brief.** Consumer-side scratch artifact at
`docs/board-superpowers/plans/card-<N>.md` — gitignored,
written by F-C2 to feed
`superpowers:subagent-driven-development`. The Card body on
GitHub remains source of truth; the plan brief is workspace
only. Source: §1.4.1 F-C2,
`AGENTS.md` (protocol invariants).

**Plugin.** The CC + Codex CLI installable artifact this
repo IS. Distributed via `/plugin add local` today;
marketplace one-liner future (P5). Source:
`PLUGIN_DEVELOPMENT.md`, `0001-positioning.md` P5.

**PreflightSnapshot.** Transient per-prompt object held by
ProducerSession — the result of one preflight piggyback
check (stale sessions, cadence, health, completed-since-last).
Lives only between prompt-arrival and prompt-response;
disposable. Source: ADR-0007 derived idiom. Expanded in:
`03-aggregates-and-entities.md` § ProducerSession.

**Preflight piggyback.** ADR-0007 derived idiom — Producer
runs lightweight situation-awareness checks before
processing each architect prompt's content; results prepend
the response. The board-superpowers core technical idiom
under plugin form. Source: ADR-0007.

**Producer.** One of two kanban-relative roles for a
session's master agent (§1.2). Purpose: keep the kanban
populated and well-shaped. Originating new Cards, reshaping
existing ones, running maintenance ops. v1 specific role:
Manager. Source: §1.2.

**ProducerSession.** The aggregate owning one Producer-role
session's identity (`session_id`), lifecycle, and the
PreflightSnapshot it computes per architect prompt. One
active per project at v1 (informal cardinality). Source:
§1.3.1, ADR-0007. Expanded in:
`03-aggregates-and-entities.md`.

**Project.** A single repo / single board scope (§1.1). One-to-one
with a GitHub Project v2 instance (per ADR-0001). Identified
by `OWNER/NUMBER`. Source: §1.1, ADR-0001, ADR-0005.

**ProjectRef.** Adapter-internal handle parsed from a
user-facing identifier — `OWNER/NUMBER` for
GitHubProjectAdapter; `WORKSPACE/TEAM` for the hypothetical
LinearAdapter. Round-trip stable
(`serialize(parse(s).value) == s`). Source: ADR-0005 type
definitions.

### R

**Ready.** Status enum value. Reached when Manager confirms
INVEST compliance (Backlog → Ready transition; ADR-0006 row
5). Precondition for atomic claim (`Ready → In Progress`;
F-C1). Source: `board-protocol`, ADR-0005, §1.6.1.

**RepoBootstrap.** The aggregate owning per-`(host, repo)` state
(`~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
+ the RoutingBlockTracker entries inside it) and the per-`(host,
repo)` bootstrap + version-transition lifecycle (F-B2, F-B4).
Host-local: each architect's host independently bootstraps and
maintains its own RepoState. Source: §1.5. Expanded in:
`03-aggregates-and-entities.md` § RepoBootstrap.

**RepoConfig.** The user-editable file
`<repo>/.board-superpowers/config.yml` carrying `project`,
`wip_limit`, future commented-out placeholders, and
optional `autonomy_overrides:`. Tracked in git (I-13);
**not** schema-versioned (uses commented placeholders
instead — I-11 / §1.5 YAGNI rationale). Source: §1.5,
`bootstrap-project.sh`, ADR-0006 §4.

**RepoState.** The plugin-managed file
`~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
(YAML, schema-versioned). v1 fields: `schema_version`,
`repo_bootstrapped_at`, `last_seen_version_in_repo`,
`features_enabled`,
`routing_blocks: [{target_file, block_hash, injected_at}, ...]`.
**Host-local**, never tracked in git (I-13). User edits silently
overwritten on next state-update cycle (I-11). Source: §1.5
state-file table, I-11, I-13.

**Reserved.** AutonomyClass value `R` — Producer (or
Consumer) drafts a proposal and awaits architect approval
on the next prompt. Source: ADR-0006 §1.

**Retro Notes.** PR body section §1.8.3 — knowledge
harvesting only (NOT estimate-vs-actual / KPI / throughput).
Two-pass authorship: implementation insights at PR-submit;
review-cycle insights supplemented post-merge. Feeds
Producer's F-12 retro routine. Source: §1.8.3.

**RoutingBlock.** The fenced block between
`<!-- board-superpowers:routing -->` /
`<!-- /board-superpowers:routing -->` in `CLAUDE.md` and
`AGENTS.md`. Plugin-owned within the marker pair
(I-11); user-owned outside. Source-of-truth content lives
at
`skills/using-board-superpowers/references/agentsmd-routing.md`
(I-10 mirror rule). Source: §1.5.2 (F-B2), §1.5.4 (F-B4),
I-10, I-11. Expanded in:
`03-aggregates-and-entities.md` § RepoBootstrap.

**RoutingBlockTracker.** Per-file (one for `CLAUDE.md`, one for
`AGENTS.md`) entry under `state.yml:routing_blocks` carrying
`block_hash` (SHA256 of the on-disk block bytes) and
`injected_at`. Used by F-B4 to detect architect modification.
Source: §1.5 state.yml shape.

### S

**Schema versioning.** Both `manifest.yml` and `state.yml`
carry an integer `schema_version` field. Migrations live at
`${CLAUDE_PLUGIN_ROOT}/scripts/migrations/<file>-v<N>-to-v<N+1>.sh`
and run lazy-on-read (I-12). Versioned-and-additive only.
Source: I-12, §1.5 cross-cutting principles. Expanded in:
`03-aggregates-and-entities.md` § HostBootstrap +
§ RepoBootstrap.

**Session.** The CC or Codex CLI process plus its identity.
Two flavors at the kanban-relative layer: **ProducerSession**
and **ConsumerProcess** (the physical incarnation backing a
**ConsumerLogical**). Source: §1.2, `03-aggregates-and-entities.md`.

**SessionId.** UUID-shaped identifier for one CC session
(`~/.claude/projects/<dir>/<session-id>.jsonl`) or one Codex
session (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`,
UUID v7 embedded in the JSONL). VO of ProducerSession and
ConsumerProcess. Used by Producer's preflight piggyback for
session-id reachback (C-PLUGIN-1 workaround b). Source:
`MULTI_AGENT_DEVELOPMENT.md`, ADR-0007.

**Session slug.** Short tag (`s-a7b3`) that distinguishes
which of N parallel Consumer sessions owns a given Card.
Appears in claim commit message, ClaimMarker `session:`
field, and the first Consumer-posted card comment. **Not** a
GitHub identity — every session authenticates as the same
user. Source: `board-protocol/SKILL.md`, `claim-card.sh`.

**Size.** VO of the Card aggregate — `XS`, `S`, `M`, or `L`.
Bounds in `card-schema.md`. No `XL` allowed; cards
exceeding L must be re-split (§1.6.1 Small letter). Source:
`card-schema.md`, §1.6.1.

**Slug.** Lowercase-hyphenated short identifier (≤ 40 chars,
40 chosen because GitHub truncates branch-name UI at
roughly that width) derived from Card title; appears in
`claim/<N>-<slug>` branch name. VO of the ConsumerLogical
aggregate. Source: `board-protocol/SKILL.md`,
`claim-card.sh`.

**Spec context.** The bounded context owning the spec / plan
/ design artifacts referenced from a Card body via
thin-pointer (I-9). v1 owns very little of its own — most
spec docs live in the user's `docs/` tree or in third-party
storage. Source: this directory. Expanded in:
`02-bounded-contexts.md`.

**Status.** Typed enum (canonical) — `Backlog`, `Ready`, `In
Progress`, `In Review`, `Done`, `Blocked`. ADR-0005 type.
Distinct from **Status field**. VO of the Card aggregate.
Source: ADR-0005, `board-protocol`.

**Status field.** The GitHub Project v2 single-select column
that physically stores Status values (six options, in fixed
order). Adapter-internal id needed by `set_card_status`.
Source: ADR-0005, `bootstrap-project.sh` validation. (Sister
backends — Linear, Jira — have their own per-backend status
column with a per-adapter mapping table.)

**Substrate commitment.** P2a — the plugin uses the team's
existing board as truth source and refuses to own state
itself. Architectural form is the BoardAdapter contract
(ADR-0005). Source: `0001-positioning.md` P2a.

**superpowers.** External plugin providing TDD /
subagent-driven-development / executing-plans / writing-skills /
verification-before-completion / requesting-code-review /
brainstorming / writing-plans / systematic-debugging skills.
Hard runtime dependency (P4b, ADR-0004). Source:
`0001-positioning.md` P4b, ADR-0004, `README.md` install.

**SuspendState.** Transient ConsumerLogical state when F-C8
surface fired and the Consumer is awaiting architect (Mode-1)
or Producer-mediated (Mode-2) input. Resolved by F-C14
wake-up. Source: §1.4 F-C8, F-C14. Expanded in:
`03-aggregates-and-entities.md` § ConsumerLogical.

### T

**Thread.** Named work mainline (工作主线) that groups
related Cards across Milestones by thematic continuity.
Closest agile-canonical equivalents: Epic (Scrum / Jira),
Initiative (Linear / SAFe). Card.threads is 0..N. Source:
§1.1.

**Thin-pointer card.** I-9 / §1.4 cross-cutting principle —
the Card body links to spec docs by repo-relative path; it
does NOT inline the full spec. Consumer self-fetches via
F-C2; Producer's Backlog → Ready gate guarantees the pointer
resolves. Source: I-9, §1.4 cross-cutting principles,
§1.6.3.

### U

**Ubiquitous language.** This file. Strategic-DDD term: the
shared vocabulary that maintainers, skills, scripts, ADRs,
and feature specs all use the same way. Source: this
directory.

### V

**Verification chain.** Consumer pre-submit sequence (F-C9)
— `superpowers:verification-before-completion` →
`superpowers:requesting-code-review` → `gstack:/review`.
Output seeds the PR's `## Automated Verification` section.
Source: §1.4.1 F-C9.

**Vertical slice.** Decomposition rule — every Card is
end-to-end user-visible (or developer-visible) behavior
through whatever layers it crosses. Layer-split cards are
re-sliced before landing on the board. Card aggregate
invariant. Source: §1.6.2.

### W

**WIP limit.** The soft cap on `In Progress + suspended +
In Review` cards (Blocked does NOT count — I-6). Default 5;
override via `RepoConfig.wip_limit`. Manager warns when
reached but does not block dispatch. Source: I-6,
`board-protocol/SKILL.md`, `bootstrap-project.sh`.

**Worktree.** Filesystem checkout paired with one
ClaimBranch — created by `claim-card.sh` via `git worktree
add`. Default location:
`$HOME/.config/superpowers/worktrees/<project>/<branch>`;
overridable via `$BOARD_SP_WORKTREE_DIR` or project-local
`.worktrees/` (must exist AND be gitignored). Persists
across Mode-2 terminate-and-resume cycles; self-deletes on
F-C14 success path; preserved on F-C14 failure path for
human takeover. One per ConsumerLogical (I-7). Source:
ADR-0003, I-7, `claim-card.sh` header.

### Z (placeholder, no entries today)

— intentionally left empty so future maintainers know the
file is alphabetized end-to-end (Z entries belong here when
they arise).
