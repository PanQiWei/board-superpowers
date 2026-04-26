## 3.4 Domain events

The state-changing moments that *cross aggregate boundaries* or
that another aggregate explicitly observes. Not "every state
mutation" — only the ones whose occurrence drives behavior in a
context other than the emitter's. Examples of mutations that
DON'T appear here: edits to a Card's body during refinement
(stays inside the Card aggregate; Audit context records via
`AuditEntry.Written`, not via a separate event), in-memory
adjustments to a PreflightSnapshot (transient, no observer).

Each entry: **emitter aggregate** / **trigger condition** /
**payload sketch** / **observers** / **physical signal channel**.
The signal channels are intentionally explicit because under
C-PLUGIN-1 (no in-memory cross-session IPC), every cross-context
event flows through one of: GitHub artifacts (workaround a) or
on-disk transcripts (workaround b). Domain events here are the
**logical** notion; the channels say how an observer actually
notices.

| # | Event | Emitter | Channel |
|---|-------|---------|---------|
| 3.4.1 | `Card.Created` | Card aggregate | GitHub Issue create + Project v2 add |
| 3.4.2 | `Card.Ready` | Card aggregate | Status field transition |
| 3.4.3 | `Card.Status.Transitioned` | Card aggregate | Status field transition |
| 3.4.4 | `Card.Claimed` | Card aggregate (write site: ConsumerLogical) | ClaimBranch creation on origin |
| 3.4.5 | `Consumer.Spawned` | ConsumerLogical | Card-thread comment (first comment) |
| 3.4.6 | `Consumer.Suspended` | ConsumerLogical | Card-thread comment (surface message) |
| 3.4.7 | `Consumer.WokeUp` | ConsumerLogical | New ConsumerProcess starts; card comment optional |
| 3.4.8 | `Consumer.Terminated` | ConsumerLogical | Branch / PR / card-status state change |
| 3.4.9 | `PR.Submitted` | PR aggregate | GitHub PR creation |
| 3.4.10 | `PR.ReviewCycle.CommentLanded` | PR aggregate (observer-emitted) | GitHub PR thread comment |
| 3.4.11 | `PR.Merged` | PR aggregate | GitHub merge event + auto-close |
| 3.4.12 | `AuditEntry.Written` | AuditTrail | RDBMS INSERT |
| 3.4.13 | `RoutingBlock.HashMismatch` | RepoBootstrap | F-B4 SHA256 compare |
| 3.4.14 | `Plugin.HostVersionTransition` | HostBootstrap | manifest.yml `last_seen_version` mismatch |
| 3.4.15 | `Plugin.RepoVersionTransition` | RepoBootstrap | state.yml `last_seen_version_in_repo` mismatch |

---

### 3.4.1 `Card.Created`

- **Emitter.** Card aggregate.
- **Trigger.** Producer F-09 calls
  `BoardAdapter.create_card(...)` after passing INVEST gate
  (§1.6.1) and vertical-slicing gate (§1.6.2). ADR-0006 row
  1 (Create cards = A).
- **Payload (sketch).** `{project_ref, card_number,
  initial_status: "Backlog", title, body, labels, milestone?,
  threads?}`.
- **Observers.** AuditTrail (writes `AuditEntry` with
  `action_id=1`). Manager's next preflight piggyback (F-04)
  may surface the new card's effect on dispatch
  recommendation.
- **Channel.** GitHub Issue create event + Project v2 item
  add. Observable via `gh issue list` /
  `BoardAdapter.list_cards(status_filter=["Backlog"])`.

### 3.4.2 `Card.Ready`

- **Emitter.** Card aggregate.
- **Trigger.** Producer transitions a Card from Backlog to
  Ready after confirming input completeness (the "spec
  pointer resolves; INVEST passed at human-review depth"
  gate). ADR-0006 row 5 (Backlog → Ready = A precondition:
  required fields present).
- **Payload (sketch).** `{project_ref, card_number,
  prior_status: "Backlog", new_status: "Ready",
  spec_resolved: true}`.
- **Observers.** ConsumerLogical's F-C0 (manual-pull
  candidate query) and F-04 (today's dispatch
  recommendation) only consider Ready cards.
  AuditTrail writes an entry with `action_id=5`.
- **Channel.** Project v2 Status field write via
  `BoardAdapter.set_card_status`.

### 3.4.3 `Card.Status.Transitioned`

- **Emitter.** Card aggregate.
- **Trigger.** Any Status field write (every transition in the
  `board-protocol` state machine — Ready → In Progress, In
  Progress → In Review, In Progress → Blocked, etc.).
- **Payload (sketch).** `{project_ref, card_number,
  prior_status, new_status, who_role}` where `who_role` is
  Producer or Consumer per ADR-0006 §3 + §1.4 cross-cutting.
- **Observers.** Same as `Card.Ready` plus Manager's F-02
  (PR queue ordering uses In Review status as the trigger to
  surface a PR for verification).
- **Channel.** `BoardAdapter.set_card_status`. Generalized
  case of `Card.Ready` (3.4.2 is one specific transition;
  this is the catch-all).

### 3.4.4 `Card.Claimed`

- **Emitter.** Card aggregate (logical), but the **write site**
  is the ConsumerLogical aggregate creating the ClaimBranch.
- **Trigger.** `claim-card.sh` succeeds with exit 0 — the
  atomic `git push --force-with-lease=<ref>:` won the race.
  §1.4.1 F-C1.
- **Payload (sketch).** `{project_ref, card_number, branch,
  worktree_path (consumer-side only — never persisted to
  origin), session_slug, mode, base_branch}`.
- **Observers.** Card aggregate updates StatusBinding (next
  step in F-C3 transitions to In Progress, emitting 3.4.3).
  AuditTrail writes an entry with `actor_role=consumer` and
  the symmetric Consumer-side `action_id` for "atomic claim"
  (TBD-3 in `03-aggregates-and-entities.md`). Manager's
  preflight piggyback notices via `git ls-remote | grep
  claim/` and via the Status transition.
- **Channel.** ClaimBranch creation visible on origin
  (`refs/heads/claim/<N>-<slug>`) + ClaimMarker file
  visible at `.board-superpowers/claims/<N>.claim` on that
  branch + (next step) Status field write.

### 3.4.5 `Consumer.Spawned`

- **Emitter.** ConsumerLogical aggregate.
- **Trigger.** A new ConsumerProcess starts (Mode-1 architect-
  spawned, OR Mode-2 Producer-spawned via CC `Agent` tool).
  §1.4 Mode topology.
- **Payload (sketch).** `{project_ref, card_number, mode (1
  or 2), session_id, parent_session_id (if Mode-2), spawn_at}`.
- **Observers.** AuditTrail (writes
  `AuditEntry` with `actor_role=consumer`,
  `action_id=<Consumer-spawn>` — TBD-3). Manager's preflight
  piggyback infers via session-log mtime increase
  (C-PLUGIN-1 workaround b).
- **Channel.** No GitHub artifact directly for spawn itself;
  the **first card-thread comment** the Consumer posts at
  F-C3 is the board-observable proxy (the "first comment
  posted with session slug, branch name, and worktree path"
  in F-C3 outputs). For Mode-2, the parent ProducerSession
  has the session_id from the `Agent` tool return value.

### 3.4.6 `Consumer.Suspended`

- **Emitter.** ConsumerLogical aggregate.
- **Trigger.** F-C8 surface fires — card spec insufficient,
  design decision-point ambiguity, debug-stuck-N-times,
  cross-card touch detected (F-C6), acceptance criteria
  contradiction.
- **Payload (sketch).** `{project_ref, card_number,
  trigger_reason, surface_message, mode, session_id,
  surface_at}`.
- **Observers.** Architect (Mode-1 — sees terminal output and
  card-thread comment); ProducerSession's preflight piggyback
  (Mode-1 + Mode-2 — sees the new card-thread comment on
  next prompt). AuditTrail writes an entry with
  `actor_role=consumer`, the Consumer-side surface
  `action_id` (TBD-3), and `outcome=escalated`.
- **Channel.** **Primary: card-thread comment** (board-
  mediated; C-PLUGIN-1 workaround a; same channel under both
  Modes). Mode-1 also writes to terminal stdout. Mode-2 MAY
  use CC `SendMessage` as a latency optimization signal to
  Producer, but is **never load-bearing** — the card-thread
  comment is the contract (`MULTI_AGENT_DEVELOPMENT.md` §1).

### 3.4.7 `Consumer.WokeUp`

- **Emitter.** ConsumerLogical aggregate.
- **Trigger.** A new ConsumerProcess starts to resume a
  suspended ConsumerLogical. Mode-1: architect responds
  interactively in the same terminal — no new process unless
  the architect spawned a fresh session. Mode-2: Producer's
  preflight piggyback decides to wake (per ADR-0006 row 13
  Dispatch Consumer = A, with optional override to R via
  `autonomy_overrides:`); spawns a new ConsumerProcess via
  the CC `Agent` tool with the SuspendState's resolution as
  context.
- **Payload (sketch).** `{project_ref, card_number,
  prior_session_id, new_session_id, mode,
  resolution_context, woke_at}`.
- **Observers.** AuditTrail (writes
  `AuditEntry` with `action_id=13` for the dispatch and a
  Consumer-side wake `action_id` — TBD-3). The Card
  aggregate's StatusBinding stays at In Progress through the
  whole suspend → wake cycle (suspend does NOT move to
  Blocked unless F-C14 failure path triggers).
- **Channel.** New session-transcript file appears on disk
  (CC `~/.claude/projects/...`); a new card-thread comment
  posted by the new ConsumerProcess to confirm it picked up
  the work (optional but customary).

### 3.4.8 `Consumer.Terminated`

- **Emitter.** ConsumerLogical aggregate.
- **Trigger.** One of three F-C14 paths fires:
  - **Success path:** PR merged → write retro note → self-
    delete worktree → process exits.
  - **Failure path:** Blocked-class condition (F-C6 cross-
    card touch, F-C8 unresolvable surface, F-C4
    NEEDS_CONTEXT or BLOCKED) → mark card Blocked + write
    failure note + release claim + KEEP worktree.
  - **Crash path:** ConsumerProcess died without clean exit
    — observable via session-log mtime stagnation + GitHub
    timestamp signals.
- **Payload (sketch).** `{project_ref, card_number, path
  (success | failure | crash), session_id, terminated_at,
  worktree_disposition (deleted | preserved | unknown)}`.
- **Observers.** AuditTrail writes one entry per path.
  Manager's preflight piggyback infers (success: PR merged
  signal; failure: Blocked status + comment; crash: stale-
  detection in F-11). The Card aggregate's StatusBinding
  reaches Done (success) or Blocked (failure) or remains In
  Progress with the marker still on origin (crash — handled
  by Triage F-10).
- **Channel.** Path-dependent:
  - Success: PR merge event (auto-close) + branch deletion
    + retro note merged into PR body.
  - Failure: Status field write to Blocked + card-thread
    failure-context comment + ClaimBranch may stay (forensic)
    or be cleaned by architect; worktree preserved.
  - Crash: nothing written by Consumer; Producer's preflight
    piggyback observes session-log mtime stagnation
    + GitHub timestamps not advancing (ADR-0007 derived).

### 3.4.9 `PR.Submitted`

- **Emitter.** PR aggregate.
- **Trigger.** Consumer F-C12 opens the PR via
  `superpowers:finishing-a-development-branch` or
  `gstack:/ship`, then appends the protocol-required
  sections (§1.8).
- **Payload (sketch).** `{project_ref, card_number, pr_number,
  branch, opened_by_session_id, body_sections_present:
  [Summary, Test Plan, Automated Verification,
  Human Verification TODO?, Retro Notes?]}`.
- **Observers.** Card aggregate transitions In Progress → In
  Review (emits 3.4.3). Manager's F-02 PR queue surfaces
  the PR on next preflight. AuditTrail writes an entry with
  `actor_role=consumer`, Consumer-side PR-submit
  `action_id` (TBD-3).
- **Channel.** GitHub PR creation event + the trailing
  `<!-- board-superpowers:pr -->` marker that distinguishes
  board-superpowers PRs from generic ones.

### 3.4.10 `PR.ReviewCycle.CommentLanded`

- **Emitter.** PR aggregate (observer-emitted — actually
  written by an external GitHub user / bot, but the PR
  aggregate is what board-superpowers cares about).
- **Trigger.** Any new comment lands on the open PR thread
  — architect comment, non-architect maintainer (I-3),
  automated reviewer bot, etc. F-C13 treats them comment-
  source-agnostic.
- **Payload (sketch).** `{project_ref, card_number, pr_number,
  comment_id, comment_author, scope_signal (in-card |
  cross-card-suggestion | stakeholder-note),
  landed_at}`.
- **Observers.** ConsumerLogical (the same instance that
  opened the PR — F-C13 stays alive through merge). On
  Mode-2, Producer's preflight piggyback may
  detect-and-wake (ADR-0006 row 13). AuditTrail writes
  an entry with Consumer-side review-cycle response
  `action_id` (TBD-3) when the Consumer responds.
- **Channel.** GitHub PR comment thread. Consumer detects on
  next prompt via `gh pr view --comments` (no realtime
  push under C-PLUGIN-2; the architect's prompt or the
  Mode-2 wake-up is the trigger).

### 3.4.11 `PR.Merged`

- **Emitter.** PR aggregate.
- **Trigger.** A human (the architect, per I-2 — Consumer
  cannot self-merge, matrix row 12 = R-class hard floor)
  merges the PR via GitHub UI / `gh pr merge`.
- **Payload (sketch).** `{project_ref, card_number, pr_number,
  merged_at, merged_by (GitHub user), merge_commit_sha}`.
- **Observers.** Card aggregate StatusBinding auto-transitions
  to Done via GitHub's `Closes #<N>` mechanism (emits
  3.4.3). ConsumerLogical's F-C14 success path triggers
  (post-merge retro-note supplement, self-delete worktree,
  process exits). AuditTrail does NOT typically write here
  (the merge is performed outside the plugin's session
  context); the ConsumerLogical's success-path termination
  event (3.4.8) is what lands the audit entry.
- **Channel.** GitHub merge event + auto-close + branch
  deletion.

### 3.4.12 `AuditEntry.Written`

- **Emitter.** AuditTrail aggregate.
- **Trigger.** Every D-AUTONOMY-1 A-class action executes (one
  entry); every R-class action proposes (one entry, outcome
  `escalated`) and resolves (one entry, outcome `approved`
  or `rejected`). Per ADR-0006 §1.
- **Payload (sketch).** Full AuditEntry value object — see
  ADR-0006 §5 / `03-aggregates-and-entities.md` § 3.3.8 for
  the column schema.
- **Observers.** Producer's F-12 retro routine + F-13 weekly
  report routine read the AuditTrail at trigger time
  (Milestone close, N-cards-completed threshold, weekly
  cadence). No live-decision-loop reader.
- **Channel.** RDBMS INSERT into the audit table (Postgres
  or MySQL; never local file, never card comment).

### 3.4.13 `RoutingBlock.HashMismatch`

- **Emitter.** RepoBootstrap aggregate.
- **Trigger.** F-B4 detects that the on-disk SHA256 of the
  routing block in `CLAUDE.md` (or `AGENTS.md`) differs from
  the stored `BlockHash` in `state.yml:routing_blocks`.
  Means the architect modified the plugin-owned region
  (I-11) since last bootstrap or last F-B4 re-injection.
- **Payload (sketch).** `{filename: ("CLAUDE.md" |
  "AGENTS.md"), expected_hash, actual_hash, detected_at,
  upgrade_context: {old_version, new_version}}`.
- **Observers.** The architect — F-B4 surfaces a 3-way
  prompt: replace your version (lossy), merge by appending
  new sections only, leave alone. AuditTrail writes an
  entry once the architect chooses; the chosen path is
  the `outcome` (R-class action; matrix row 4 / 10
  semantic).
- **Channel.** Surface to the architect via the next prompt
  response (preflight piggyback, ADR-0007).

### 3.4.14 `Plugin.HostVersionTransition`

- **Emitter.** HostBootstrap aggregate.
- **Trigger.** F-B3 fires —
  `~/.board-superpowers/manifest.yml:last_seen_version`
  is older than current
  `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json:version`.
- **Payload (sketch).** `{old_version, new_version,
  schema_version_migrated_from?,
  schema_version_migrated_to?, transitioned_at}`.
- **Observers.** Architect — F-B3 surfaces the highlights
  from `references/changelog/v<NEW>.md`. AuditTrail
  writes an entry (autonomy A; matrix row 14 cadence-driven
  notification analog applies).
- **Channel.** Surface to architect via session-start banner
  + manifest.yml `last_seen_version` updated.

### 3.4.15 `Plugin.RepoVersionTransition`

- **Emitter.** RepoBootstrap aggregate.
- **Trigger.** F-B4 fires —
  `~/.board-superpowers/repos/<normalized-repo-path>/state.yml:last_seen_version_in_repo`
  is older than current plugin version (often after
  3.4.14 has already fired host-side, but per the §1.5 (D)
  / (E) scenarios it can fire alone if architect upgraded
  long ago and is now visiting an outdated repo).
- **Payload (sketch).** `{project_ref, old_version,
  new_version, schema_version_migrated?,
  features_auto_enabled: [feature_id, ...],
  features_opted_out: [feature_id, ...],
  routing_blocks_reinjected: [{filename, hash_match,
  outcome (auto-replaced | architect-chose-replace |
  architect-chose-merge | architect-chose-leave)}]}`.
- **Observers.** Architect — F-B4 surfaces the per-repo
  changes (auto-enabled features list, opt-out prompt,
  per-file routing-block status). AuditTrail writes
  multiple entries: one for the version transition, one
  per routing-block re-injection, one per feature
  auto-enable / opt-out. (R-class for opt-outs and for
  user-modified routing-block 3-way choices; A-class for
  auto-re-inject of unmodified blocks.)
- **Channel.** Surface to architect via preflight or
  `using-board-superpowers` Step 3; state.yml updates.

---

### 3.4.16 Events deliberately NOT in the registry

Avoid the temptation to elevate every state change to a
domain event. The following are state mutations whose effects
stay inside one aggregate and are recorded only in the
AuditTrail (via 3.4.12 generic `AuditEntry.Written`):

- **Card body refinement** while in Backlog/Ready (Producer
  F-09 / F-10 refine actions; ADR-0006 row 2 = A, single
  AuditEntry, no other observer).
- **Label adjustments** (Producer F-15 hygiene; matrix row
  11 = A, single AuditEntry, no observer).
- **WIP limit adjustment** in `RepoConfig` (matrix row 9 =
  A; the change does affect Manager's F-04 dispatch
  recommendation calculations, but those re-read RepoConfig
  on each prompt — no event flow needed).
- **PreflightSnapshot creation** — transient, intra-aggregate;
  not persisted, not observed by anything outside Producer's
  current prompt response.
- **PlanBrief writes / updates** — Consumer-internal scratch;
  no observer outside ConsumerLogical's own implementation
  delegation chain.

If one of these turns out to need a cross-aggregate observer
in a future feature, promote it to a named event here in the
same PR that adds the observer.

---

### 3.4.17 Event-channel summary

The full set of physical channels through which events flow.
Recap because every cross-aggregate observation has to use one
of these (no in-memory IPC under C-PLUGIN-1).

| Channel | Used by events |
|---------|----------------|
| GitHub Issue (body, thread comments) | 3.4.1, 3.4.2, 3.4.3, 3.4.5, 3.4.6, 3.4.7, 3.4.8 (failure path), 3.4.13 (target file update) |
| GitHub PR (body, thread comments, merge event) | 3.4.9, 3.4.10, 3.4.11 |
| GitHub Project v2 Status field | 3.4.2, 3.4.3 (everything routing through `set_card_status`) |
| ClaimBranch on origin (creation, deletion) | 3.4.4, 3.4.8 (success path branch deletion) |
| ClaimMarker file on the ClaimBranch | 3.4.4 (existence proves claim) |
| Local filesystem (worktrees, plan briefs) | 3.4.8 (success path worktree self-delete; failure path worktree preserved) |
| Platform session-transcript files | 3.4.5, 3.4.7, 3.4.8 (crash detection via mtime stagnation per ADR-0007) |
| BYO RDBMS | 3.4.12 (every audit-log write) |
| `~/.board-superpowers/manifest.yml` | 3.4.14 |
| `~/.board-superpowers/repos/<normalized-repo-path>/state.yml` | 3.4.13, 3.4.15 |
| Architect's prompt response surface (preflight piggyback) | 3.4.13, 3.4.14, 3.4.15 (and any event whose observer is the architect) |

Mode-2-specific optional optimization (latency only, not
load-bearing): CC `SendMessage` between Producer ↔ Consumer
under `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Per
`MULTI_AGENT_DEVELOPMENT.md` §1, the contract channel for every
event a Mode-2 Consumer surfaces is still the card-thread
comment (workaround a); `SendMessage` may carry the same
information faster but the system MUST close correctly when it
is unavailable.
