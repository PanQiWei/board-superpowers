# Failure modes

> **Status:** v1-grade. Promoted from stub to canonical via card #33.

## Purpose

Catalog every known way board-superpowers can fail at runtime, with a
uniform shape per scenario so that anyone debugging a real outage can
find the failure mode here, learn what to do about it, and update this
file if the mode is new.

A "failure mode" in this document is an unintended state transition or
operation outcome — the system tried to do the right thing and could
not. The intentional absence of a routine (e.g., F-12 Retro routine
deferred per ADR-0011) is **not** a failure mode; it is an intentional
deferral with a documented re-open trigger. Likewise, the deferred
audit-log persistence backend — when the architect has not configured
the BYO RDBMS yet — degrades the system per ADR-0006 §5 + the
v1-minimum-degraded local jsonl trace; that degradation path itself IS
in scope here, but the absence of the BYO infrastructure is not.

## Per-scenario format

Each failure mode below carries four mandatory fields:

- **Detection signal.** What the operator sees (or what an automated
  probe sees) that distinguishes this failure from healthy operation.
  Where automated detection is implemented or planned, the
  cross-reference points to `0007-observability.md`.
- **User-visible behavior.** What the architect / Consumer / Producer
  experiences in the session. Distinguishes "you see an error" from "you
  see nothing and the work silently halts."
- **Audit-log entry shape.** Which `action_id` rows the BYO RDBMS sees
  during the failure, what `outcome` value lands (`success` /
  `failure`), and what `approval_stage` value the entry carries (`auto`
  / `propose` / `approved` / `rejected`). Schema reference:
  `0005-contracts/06-audit-log-schema.md` § "Core schema — 8 columns".
  When the audit log itself is unavailable (Scenario B), the shape
  describes the v1-minimum-degraded local jsonl entry instead.
- **Recovery path.** The concrete steps that restore healthy operation,
  separated by who acts (architect / Consumer / plugin code) and whether
  the recovery is automatic, opt-in, or manual.

## Scenario (a) — GitHub API rate-limit / 5xx

The plugin makes GitHub API calls through `gh` for board reads (F-01),
Status flips (claim, In Review, Done transitions), branch pushes, PR
creates / comments. GitHub returns 429 (rate-limit, primary or
secondary) or a 5xx (server error, intermittent or sustained) and the
call fails.

- **Detection signal.** `gh` exits non-zero with a stderr line matching
  `HTTP 429`, `HTTP 5\d\d`, or `secondary rate limit`. The rate-limit
  budget is observable via `gh api rate_limit` and is the canonical
  pre-flight probe; a sustained 5xx from `api.github.com` is observable
  via the same endpoint returning non-200. Per `0007-observability.md`
  § "In-session surface", the `[bsp ERROR]` line on the calling
  script's stderr is the in-session signal an architect actually sees.
- **User-visible behavior.** The script that wraps the failing `gh` call
  returns a `[bsp ERROR] gh exited 1: <stderr summary>` message on
  stderr (per `bsp_die` in `scripts/lib/common.sh`) and the calling
  skill receives a non-zero exit. Mid-claim (during `claim-card.sh`'s
  4-step transaction) the script aborts at the failing step; which
  steps had already landed depends on where in the 4-step sequence the
  failure hit (Scenario (d) below documents the canonical 4-step
  partial-state shape).
- **Audit-log entry shape.** For an A-class action that hit the
  rate-limit at execution time, one entry is written with
  `outcome=failure` and `approval_stage=auto`; `payload` includes
  `{error_class: "github_rate_limit" | "github_5xx",
  retry_after_seconds: <N>}` so retry tooling can be built later. For an
  R-class action, the propose entry was already written with
  `approval_stage=propose, outcome=success`; a second resolve entry
  lands with `approval_stage=approved` (the architect already acked) but
  `outcome=failure` and the same error_class payload.
- **Recovery path.** (1) Architect waits the `retry_after_seconds`
  window the API hint named (typical: 60-3600 s for primary rate-limit,
  instant for secondary), then re-runs the failed action. The script is
  idempotent — re-running `claim-card.sh` for an already-claimed card is
  a no-op per the script's docstring. (2) For sustained 5xx longer than
  30 minutes, the architect treats it as a soft outage of the GitHub
  adapter and either waits or postpones the day's board work; no
  plugin-side workaround exists because GitHub is the source of truth.

## Scenario (b) — Audit-log filesystem write failure

The v1-minimum-degraded audit trace writes to
`~/.board-superpowers/repos/<normalized>/audit-local.jsonl` via
`bsp_audit_local_write`. The directory is missing-and-uncreatable
(permissions, read-only `$HOME`, full disk), the file is locked, or the
append fails mid-line.

- **Detection signal.** `bsp_audit_local_write` exits non-zero. Specific
  signals: `mkdir: cannot create directory` (no write permission on
  `$HOME`), `No space left on device` (disk full), or a partial-line
  append visible to the next `tail` reader. The function itself emits
  `[bsp] audit-local: <decision>-class action <id> (<skill>) → <path>`
  on success and `[bsp WARN]` on the legacy-migration mv-failure path;
  on hard failure the calling script's strict-mode (`set -euo pipefail`)
  propagates the non-zero exit to the caller, which surfaces a `[bsp
  ERROR]` via `bsp_die` (per `scripts/lib/common.sh` `bsp_audit_local_write`
  function and the `bsp_die` helper at line 190).
- **User-visible behavior.** The mutating action that triggered the
  audit write **completes its primary effect** (the GitHub Status flip
  already landed), but the local trace is missing the entry. The user
  sees a `[bsp ERROR] audit-log write failed: <reason>` on stderr; the
  calling skill MUST surface this to the architect rather than silently
  continue, because the audit gap is itself a contract violation.
- **Audit-log entry shape.** The intended entry has `outcome=success`
  for the primary action plus `approval_stage=auto` (A-class) or
  `approval_stage=approved` (R-class). When the write itself fails the
  entry is **not present** in `audit-local.jsonl` — the failure is
  detected by the gap, not by a sentinel row. When the BYO RDBMS lands,
  the corresponding entry shape is `outcome=success,
  approval_stage=approved, payload={...primary action...}` plus an
  out-of-band operator alert that the local trace was unreachable.
- **Recovery path.** (1) Architect fixes the underlying filesystem
  condition: `chmod` the directory, free disk space, unlock the file.
  (2) Architect manually appends a synthetic recovery entry to
  `audit-local.jsonl` documenting the gap window:
  `{"ts":"<now>","action_id":"audit.recovery.gap-noted","decision_class":"N","skill":"<originating>","summary":"audit-local
  write failed at <approx-window>; primary action <X> landed per
  board-side check"}`. (3) When BYO RDBMS lands, the same gap-noted
  convention applies to the central log; the gap-recovery row is
  required so future querying can distinguish "no action happened" from
  "action happened, audit failed."

## Scenario (c) — BYO RDBMS unreachable (A → R degradation per ADR-0006 §5)

When the BYO RDBMS audit backend lands (deferred to v1-complete via the
`auditing-actions` atomic skill), the plugin will attempt to write each
A-class and R-class entry to it. The DB is unreachable: TCP connection
refused, authentication failure, schema migration not applied, or the
configured `BOARD_SP_AUDIT_DB_URL` is empty / malformed.

- **Detection signal.** The audit-write helper (TBD:
  `scripts/audit-log-write.sh`) exits non-zero. Specific signals: `psql:
  connection to server ... failed`, `MySQL ERROR 2002`, `relation
  "audit_log" does not exist` (schema not initialized), or the DSN
  parser rejected the URL with `[bsp ERROR] BOARD_SP_AUDIT_DB_URL:
  invalid scheme`. Per ADR-0006 §5 the architect provides the database
  (P7); plugin emits a single diagnostic line, not a stack trace.
- **User-visible behavior.** Per ADR-0006 §5 (Audit log persistence —
  BYO RDBMS), the R-class degradation when the DB is unavailable is
  the canonical fallback (paraphrased from §5's persistence rules;
  preserved through ADR-0009 per its "Partially superseded" admonition
  in §5): the entire
  autonomy posture degrades from A-class default to R-class default —
  every mutating action that would have run autonomously now requires
  explicit architect ack. The architect sees `[bsp WARN] audit DB
  unavailable; degrading to R-class default for this session` on the
  first mutating action attempt of the session, and the action then
  enters propose-and-ack flow. The session continues to function, just
  slower and with explicit checkpoints.
- **Audit-log entry shape.** Once the DB is restored the architect runs
  a one-shot reconciler (TBD; out of scope for v1-minimum) that ingests
  the local jsonl trace from the degradation window and inserts
  equivalent BYO RDBMS rows with `payload.degraded_at_write=true` so the
  gap is forensically distinguishable from native R-class operation.
  During the gap, every entry lands in `audit-local.jsonl` with
  `mode=v1-minimum-degraded` (already the v1-minimum default) — the
  existing local trace IS the degradation path.
- **Recovery path.** (1) Architect fixes the DB-side issue (start
  Postgres, fix credentials, run the DDL init script per
  `0005-contracts/06-audit-log-schema.md` § "DDL ownership"). (2)
  Architect runs the reconciler (TBD) to backfill the gap entries from
  `audit-local.jsonl`. (3) Plugin auto-detects DB availability on the
  next mutating action and lifts the R-class degradation; no session
  restart required. The degradation is **never** silent — every degraded
  action lands with the WARN line on stderr, so an architect cannot
  accidentally operate degraded for a long window without noticing.

## Scenario (d) — Claim race

Two Consumer sessions attempt to claim the same Ready card
simultaneously: both run `claim-card.sh --card N` within milliseconds,
both see Status=Ready, both attempt the four-step transaction. The
branch push step is the natural arbiter (per ADR-0002 § "Atomic claim
via remote branch push"), but the rest of the transaction is exposed to
a partial-state window.

- **Detection signal.** The losing Consumer's `git push origin
  claim/N-<slug>` returns a non-fast-forward rejection with `!
  [rejected] claim/N-<slug> -> claim/N-<slug> (non-fast-forward)`. The
  winning Consumer's push succeeds with the standard `* [new branch]`
  line. Per `0007-observability.md` § "State-probe surface", the
  loser's partial-state shape (Status=In Progress on a card with no
  live `claim/N-<slug>` branch on origin) is observable to the next
  state probe that runs against this repo, and to any architect that
  cross-checks `gh project item-list` against `git ls-remote`.
- **User-visible behavior.** The losing Consumer sees the `git push`
  error and the script exits non-zero with `[bsp ERROR] step 4/4 failed:
  claim race detected (branch already exists on origin)`. Critically,
  **steps 1-3 have already executed** for the loser: Status was flipped
  to In Progress (twice — once by the winner, once by the loser; the
  second flip is a no-op on a same-value field), worktree was created
  locally, branch was created locally. Only step 4 (the public claim
  signal) failed. The loser sees a partial-state message naming exactly
  which steps need rollback.
- **Audit-log entry shape.** The loser's session writes one A-class
  entry per local-step success (steps 1-3) with `outcome=success,
  approval_stage=auto` (when classifying-actions is online; v1-minimum
  degrades to R-class so each step requires propose-ack), then one entry
  for step 4 with `outcome=failure, approval_stage=auto,
  payload={error_class: "claim_race", winner_branch_sha: "<sha>"}`. The
  winner's session writes the same shape but with all four entries
  `outcome=success`. Both sessions' entries carry distinct `session_id`
  so the race is forensically reconstructable.
- **Recovery path.** (1) The loser's `claim-card.sh` does NOT
  auto-rollback — per `board-canon/SKILL.md` § "Claim protocol": "If
  step 4 fails, steps 1-3 are NOT rolled back automatically — the
  Consumer must explicitly surface the partial state to the architect
  rather than silently retry." (Note: `claim-card.sh`'s own docstring
  reads "rolls back what it can" — the script-level claim is more
  optimistic than the SKILL contract; the SKILL is canonical when the
  two diverge, per the AGENTS.md "Same-PR contract update" rule.) (2)
  Architect inspects the partial state (Status was
  already correctly flipped by the winner; the loser's local worktree +
  branch are the cleanup target) and instructs the loser session to
  remove the worktree and delete the local branch: `git worktree remove
  <path>; git branch -D claim/N-<slug>`. (3) The loser then either picks
  a different Ready card or releases its WIP slot. No rollback is needed
  on the board side — the winner already owns the claim.

## Scenario (e) — Hook delivery silent drop (Claude Code SessionStart)

`SessionStart` hook delivery in Claude Code is unreliable in some
session-restoration paths (documented in `AGENTS.md` § "Hook intent
injection — the v1 dispatch optimization": "CC `SessionStart`
delivery is unreliable so the marker is an optimization, not a
correctness requirement"; see also `0004-component-architecture.md`
§ "Hook intent injection pattern" for the contracted fallback shape). The hook's `INVOKE: <skill>` marker (e.g.,
`INVOKE: bootstrapping-repo` for first-time repos) is never injected;
the entry skill `using-board-superpowers` does not see the marker.

- **Detection signal.** The entry skill performs a redundant state probe
  (per `using-board-superpowers/SKILL.md` § "Step 1 — re-run dep + state check (Layer 2 reliable gate)") that
  does not depend on the hook marker. If the probe finds
  first-time-on-this-repo state (manifest absent, per-repo state.yml
  absent) it routes to `bootstrapping-repo` regardless of marker
  presence. The "failure" is therefore detectable only as a
  **performance** signal — the entry skill spent ~50ms doing a probe
  that the hook would have short-circuited. There is no user-visible
  misroute.
- **User-visible behavior.** None. The state-probe fallback fires
  correctly; the architect sees the same downstream skill response they
  would have seen with marker delivery. The "silent drop" is the
  design's worst-case envelope — the system is designed to operate as if
  the hook never fires, and the marker is a fast-path optimization, not
  a correctness requirement (per
  `docs/architecture/0004-component-architecture.md` § "Hook intent
  injection pattern").
- **Audit-log entry shape.** No dedicated entry. The downstream skill's
  normal entries land per its bounded context. If diagnostic visibility
  into hook-drop frequency becomes valuable, a future telemetry surface
  (out of scope for v1) could write `action_id=plugin.hook.dropped` rows
  from the entry skill when its probe fires without a marker — but
  emitting one row per session start would dwarf the actual
  mutating-action signal in the log, so the deliberate v1 choice is to
  NOT log this.
- **Recovery path.** None required. The fallback IS the recovery. The
  intent-injection markers are an optimization; the entry skill's
  reliable dep gate is the contract. If the architect notices excessive
  entry-skill probe latency they can re-register the hook
  (`scripts/register-codex-hooks.sh --install-user` for Codex; CC
  re-registers automatically on plugin reload) but this is hygiene, not
  failure recovery.

## Scenario (f) — Worktree-base path unavailable

`claim-card.sh` step 2 creates a worktree at
`$BOARD_SP_WORKTREE_DIR/<repo>/claim/<N>-<slug>` (default base:
`$HOME/.config/superpowers/worktrees/`). The base path is
missing-and-uncreatable (permissions, missing parent, read-only mount),
the target subdirectory already exists with conflicting content (stale
orphan from a prior failed claim, or a different repo collision), or the
disk is full mid-`git worktree add`.

- **Detection signal.** `git worktree add` exits non-zero. Specific
  signals: `fatal: '<path>' already exists` (orphan dir), `fatal: not a
  directory` (path component mid-prefix is a regular file), `Permission
  denied`, or `No space left on device`. Steps 1 (Status flip) has
  already succeeded; steps 2-4 are blocked.
- **User-visible behavior.** `claim-card.sh` exits non-zero with `[bsp
  ERROR] step 2/4 failed: <git worktree stderr>`. The board Status field
  is now incorrectly showing In Progress for a card that has no Consumer
  — a partial-state condition the script flags but does not auto-fix
  (per `board-canon/SKILL.md` § "Claim protocol", the SKILL-level claim
  protocol contract: "If step 4 fails, steps 1-3 are NOT rolled back
  automatically" — same partial-state shape applies to step 2 / 3
  failures as well).
- **Audit-log entry shape.** Step 1's entry landed with
  `outcome=success`. Step 2's entry lands with `outcome=failure,
  approval_stage=auto, payload={error_class: "worktree_create_failed",
  reason: "<git_stderr_first_line>", target_path: "<path>"}`. The
  Status-In-Progress on the board with no claim branch on origin is the
  cross-checkable inconsistency that an audit-time reviewer can detect.
- **Recovery path.** (1) Architect inspects the worktree-base path and
  resolves the underlying issue: remove the orphan directory (verifying
  it is not someone else's in-flight worktree first via `git worktree
  list`), free disk space, fix permissions, or override
  `BOARD_SP_WORKTREE_DIR` to a different location for this session. (2)
  Architect manually flips the card's Status back to Ready via `gh
  project item-edit` (the rollback step `claim-card.sh` did not
  perform), with a corresponding audit entry:
  `action_id=consumer.claim.rollback, payload={card: N, reason:
  "worktree_create_failed", original_status: "In Progress"}`. (3)
  Architect re-runs `claim-card.sh` for the same card; with the
  worktree-base now writable, the four steps complete cleanly.

## Scenario (g) — State-file corruption

The per-repo state file at
`~/.board-superpowers/repos/<normalized>/state.yml` is corrupted:
malformed YAML (trailing junk after editor crash), missing required keys
(`schema_version`, `last_seen_version_in_repo`), or the file was deleted
while a session was mid-operation.

- **Detection signal.** YAML parse failure on the next read by
  `using-board-superpowers` or `bootstrapping-repo`: `yq` exits
  non-zero, or the `schema_version` key is absent / unrecognized. The
  entry skill's reliable dep gate catches missing-or-corrupt state on
  every session start (per `using-board-superpowers/SKILL.md` § "State
  probe"). Per `0007-observability.md` § "State-probe surface", the probe is the
  only routine guaranteed to read state.yml on every session —
  corruption between sessions is detected at the next session start.
- **User-visible behavior.** Entry skill fails closed: it blocks routing
  to any Producer / Consumer skill and surfaces a `[bsp ERROR] state.yml
  at <path> is corrupted: <yq error>; cannot determine version state`
  message. The architect cannot proceed with any board action until the
  state is repaired. This is a deliberate fail-closed posture —
  operating with corrupt state risks duplicate bootstrap,
  version-migration loops, or audit gaps in the host-state surface.
- **Audit-log entry shape.** No mutating action lands during the
  corruption window (the entry skill blocked routing). Once recovered,
  the architect's repair action MAY be logged:
  `action_id=plugin.state.repair, decision_class=R, payload={path:
  "<state.yml>", reason: "<corruption type>", recovered_from: "backup" |
  "manual" | "regenerated"}`. The repair entry is optional in v1-minimum
  (the architect's repair is an out-of-band operation; the audit log's
  role is to capture mutating actions on the board, not on the plugin's
  own host-state files).
- **Recovery path.** (1) Architect inspects `state.yml` (it is small, <
  20 lines typically) and either fixes the corruption manually or
  restores from a recent backup. The schema is documented at
  `0005-contracts/03-config-schemas.md` § "Per-repo state.yml". (2) If
  no backup exists and the corruption is unrecoverable, the architect
  deletes `state.yml` entirely; the next session start triggers
  `bootstrapping-repo`'s F-B2 routine which re-derives the file from the
  in-tree `.board-superpowers/config.yml` plus current plugin version.
  The cost of regeneration is approximately one minute of architect
  interaction — `state.yml` is intentionally minimal so this fallback is
  cheap. (3) The `routing_blocks[].block_hash` field will re-derive on
  regenerate; this is benign (the routing block in `AGENTS.md` /
  `CLAUDE.md` is unchanged; only the recorded hash gets updated to match
  it).

## Recovery primitives

Common building blocks called from multiple scenarios above:

- **`git push origin --delete <branch>`** — release a stuck claim branch
  when the Consumer that pushed it cannot be reached. Used in Scenarios
  (d) and (f) recovery paths.
- **`git worktree remove --force <path>`** — clean a stale or orphaned
  worktree directory. Used when Scenario (f) involves a leftover from a
  prior failed claim, and as the natural cleanup at the end of any
  successful PR merge (per `consuming-card/SKILL.md` § Step 12).
- **Manual Status flip via `gh project item-edit`** — used for
  partial-state recovery in Scenarios (d) and (f) when `claim-card.sh`
  left the Status field inconsistent with the world. Architect computes
  the field-id and option-id once per repo (cached implicitly by
  `bsp_gh_field_id` / `bsp_gh_field_option_id`), then issues the
  targeted edit.
- **Forced project-status reset** — when GitHub's webhook
  auto-transition (`In Review → Done` on PR merge) drops or lags beyond
  ~30s, architect manually flips the card to Done via the same `gh
  project item-edit` path. The post-merge accounting lag is documented
  in `board-canon/references/wip-counting.md` and is normal up to ~30s;
  sustained absence indicates a webhook configuration drift on the
  GitHub Project side, not a failure mode the plugin can autonomously
  fix.
- **Synthetic audit-recovery entry** — used in Scenario (b) and (c)
  recovery paths to mark the audit gap window. Standardized
  `action_id=audit.recovery.gap-noted`; payload names the approximate
  gap window and the originating action that was missed.

## How to add a failure mode

When a Consumer or Producer encounters a real failure not catalogued
here:

1. While debugging, capture the four mandatory fields (detection signal
   / user-visible behavior / audit-log entry shape / recovery path) so
   the catalogue entry can be drafted at fix time.
2. Open a card targeting the spec — the same intake / decomposition flow
   as any other spec change. The card's deliverable is one new top-level
   scenario section in this file plus any cross-references to
   `0007-observability.md` (if a new detection signal is added) or
   `0005-contracts/06-audit-log-schema.md` (if a new `action_id` is
   needed).
3. The PR adding the scenario MUST include a Retro Notes entry on the
   bug fix that surfaced it, so the failure-mode catalogue entry is
   paired with the production incident that motivated it. Per
   `enforcing-pr-contract` § "Retro Notes", this is the canonical
   channel for "why this entry exists."

## What is NOT a failure mode

Several conditions look failure-shaped on first glance but are
intentional surface choices:

- **Deferred Producer routines (F-03..F-07 + F-10..F-15) returning "not
  implemented in v1".** Per ADR-0011, those routines are deferred
  pending demand pull; their absence is the design.
- **`migrating-repo-version` skill not triggering at v0.2.0 → v0.2.x
  transitions.** Per `AGENTS.md` § "v1-minimum degraded behaviors", the
  migration runner does not exist until the v0.2.x → v0.3.x transition;
  the hook explicitly does not inject `INVOKE: migrating-repo-version`
  in v0.2.0.
- **R-class default for every mutating action in v1-minimum.** Per
  `AGENTS.md` § "v1-minimum degraded behaviors", until
  `classifying-actions` ships, every mutation requires architect ack.
  This is a per-design degradation, not a fault.
- **Audit log lives in local jsonl, not BYO RDBMS, in v1-minimum.** Same
  source — the BYO RDBMS lands with `auditing-actions` in v1-complete.
  The local jsonl trace is the documented v1-minimum substitute, not a
  degraded mode the architect needs to recover from.

## Related

- ADR-0002 — Atomic claim via remote branch push (Scenario (d) is the
  design's branch-push race).
- ADR-0006 § 5 — Audit log persistence + R-class degradation when DB
  unavailable (Scenario (c) is this clause's runtime expression).
- ADR-0007 — Plugin-runtime-derived constraints (Scenario (e) is
  adjacent to C-PLUGIN-1's "no in-memory cross-session IPC" — the hook
  unreliability is a separate concern documented in `AGENTS.md` §
  "Hook intent injection — the v1 dispatch optimization", but both
  motivate the same fail-closed posture for cross-session signal).
- ADR-0008 — Plugin-to-plugin SKILL invocation (referenced for Scenario
  (e) routing fallback shape).
- ADR-0009 — Allow SQLite as a BYO audit DB scheme (does not change
  Scenario (c) recovery shape; only widens the "DB" definition).
- ADR-0010 — AI cadence 100x convention (informs why some scenarios —
  like Scenario (a) sustained 5xx — are recovered by "wait or postpone
  the day's work" rather than implementing complex retry: at AI cadence
  the cost of postponing is hours, not days, so retry tooling does not
  earn its complexity).
- ADR-0011 — Defer Producer routines F-03..F-07 + F-10..F-15 to v1.x
  pending demand pull (the canonical "not a failure mode" entry above).
- `0005-contracts/06-audit-log-schema.md` — 8-column schema referenced
  by every scenario's audit-log entry shape field.
- `0007-observability.md` — detection-signal surfaces; every scenario
  above cross-references the observability doc for the canonical
  detection mechanism.
- `0008-test-architecture.md` — every scenario above is a candidate test
  surface; several already exist as Layer 1 / Layer 2 tests under
  `tests/`, and `0008` § "Layer 1" + § "Layer 2" enumerate which
  scenarios have which test coverage.
- `0004-component-architecture.md` § "Hook intent injection pattern" —
  explains why Scenario (e) is a non-failure under the design.
- `consuming-card/SKILL.md` § "Step 4" / "Step 12" — claim worktree
  creation + post-merge cleanup, the consumer-side surfaces touched by
  Scenarios (d) (f).
