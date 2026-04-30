# Observability

> **Status:** v1-grade. Promoted from stub to canonical via card #33.

## Purpose

Define how a maintainer (or the architect using the plugin) knows
board-superpowers is healthy at runtime, where to look for what, and
what the plugin deliberately does **not** observe in v1. The previous
stub version of this doc only listed candidate signals; this version
pins the four observability surfaces that v1 contracts to expose, the
schema each surface uses, and the boundary between "observable in v1"
and "deferred / never."

The doc consumes the same contract surfaces that `0006-failure-modes.md`
consumes for detection signals, and is the reverse-direction reference:
failure-mode entries cite this doc for "where do I look", and this doc
cites the failure-mode entries for "what does that signal indicate."

## Surfaces (four, layered shallow → deep)

The v1 observability stack is intentionally shallow. There are exactly
four surfaces, ordered from "any architect can look here in 5 seconds"
to "audit replay across sessions":

1. **In-session surface.** What the architect sees in the live CC /
   Codex session — skill prose output, `[bsp ...]` log lines from
   `scripts/lib/common.sh`, hook intent-injection markers in the
   conversation context.
2. **State-probe surface.** What `using-board-superpowers` reads on
   every session start — host manifest, per-repo state.yml, plugin
   version, INVOKE markers from the SessionStart hook.
3. **Audit-log surface (BYO RDBMS, deferred).** The 8-column AuditEntry
   table written by the deferred `auditing-actions` atomic skill.
   v1-minimum substitutes the local jsonl trace; v1-complete swaps in
   the BYO RDBMS without changing the surface above it.
4. **Local jsonl trace (v1-minimum surface).** The append-only
   `audit-local.jsonl` file written by `bsp_audit_local_write`. A
   degraded substitute for the BYO RDBMS surface; same forensic intent,
   smaller schema, host-local scope.

Each surface has a section below documenting its schema, query patterns,
retention rules, and explicit non-coverage.

## In-session surface

This is the surface every architect interacts with whether they realize
it or not. It is the cheapest to read and the easiest to act on.

### Signals

- **`[bsp ...]` log lines.** Every script under `scripts/` and helper in
  `scripts/lib/common.sh` writes prefixed lines to stderr at notable
  moments. Examples observed in v1: `[bsp] claim transaction: card #N →
  branch claim/N-<slug>`, `[bsp] step 2/4: creating worktree at ...`,
  `[bsp] audit-local: R-class action <id> (<skill>) → <path>`, `[bsp
  ERROR] missing dependency: <cmd>`. The convention is documented in
  `scripts/lib/common.sh` § "Conventions" line comment block.
- **Skill prose output.** Each molecular skill writes structured prose
  during its routine — for example, `consuming-card` Step 1-12
  narration, `managing-board` Daily routine's 4-section briefing,
  `bootstrapping-repo` first-time-user welcome. The prose IS the
  observability surface for "what is the skill currently doing."
- **Hook intent-injection markers.** When `SessionStart` fires
  successfully, the conversation context contains a marker line like
  `INVOKE: bootstrapping-repo` followed by `REASON: <one-line>`.
  Architects can confirm a hook fired by looking for these markers in
  the session transcript.
- **Cross-skill handoff lines.** When `consuming-card` invokes
  `superpowers:test-driven-development` (or any other cross-plugin
  skill) procedurally, the call site emits a one-line "invoking
  <plugin>:<skill> for <reason>" preamble before reading the sibling
  SKILL.md. The preamble is what an architect reads to confirm the right
  composition is happening.

### Query patterns

In-session surface is read in real time during the session. There is no
after-the-fact query — once the session ends, the prose lives only in
whatever transcript export the platform offers (CC: session export;
Codex: terminal scrollback).

### Retention

None inside the plugin. Architects who need durable in-session signal
are expected to use the platform's transcript export. The plugin does
not write a sidecar transcript file because doing so would duplicate
platform functionality and re-introduce the transcript-leak risk
class — transcripts naturally include absolute local paths, OS
usernames, and occasionally retro-style content the architect would
not want public.

### Explicit non-coverage

- **No structured event stream.** `[bsp ...]` lines are prose, not JSON.
  Tooling that wants to ingest them needs to grep / sed; the plugin will
  not commit to a parser-stable shape until a v1.x consumer demands it
  (per ADR-0011 deferred-routine pattern).
- **No latency timing.** The plugin does not currently emit timing for
  skill operations. The cadence-scrutiny rule (per ADR-0010 § 3 in
  spirit, applied to observability rather than the literal scope-shaped
  quantities the section names) makes timing observability a low-value
  surface in v1: the architect already sees skill operations complete
  in human-perceptible time, so a separate metric adds noise without
  decision value.

## State-probe surface

The state-probe surface is what `using-board-superpowers` (entry skill)
reads on every session start as its reliable dep gate. It complements
the hook intent-injection markers, which can be silently dropped on
some session-restoration paths (per `AGENTS.md` § "Hook intent
injection — the v1 dispatch optimization": "CC `SessionStart`
delivery is unreliable so the marker is an optimization, not a
correctness requirement"; see `0006-failure-modes.md` Scenario (e)
for the documented failure mode).

### Signals

- **Host manifest** at `~/.board-superpowers/manifest.yml`. Presence
  indicates the host is bootstrapped (per F-B1). Absence triggers
  `INVOKE: bootstrapping-repo` from the entry skill.
- **Per-repo state file** at
  `~/.board-superpowers/repos/<normalized>/state.yml`. Schema documented
  in `0005-contracts/03-config-schemas.md` § "`~/.board-superpowers/repos/<normalized-repo-path>/state.yml` — RepoState".
  Required keys: `schema_version`, `repo_bootstrapped_at`,
  `last_seen_version_in_repo`, `features_enabled`, `routing_blocks`.
  Absence triggers per-repo bootstrap (F-B2).
- **Plugin version** read from
  `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` (CC) or, on Codex
  CLI which does not export a plugin-root env var, derived from this
  file's own location two levels up (i.e., `<plugin-root>/.codex-plugin/plugin.json`).
  Both paths resolve through `bsp_plugin_root()` in
  `scripts/lib/common.sh`. The unified setup-stages check (per
  ADR-0012) compares each stage's recorded `generation` /
  `target_state_hash` against the registry's current target; any
  `never-run` or `stale` stage triggers `INVOKE: bootstrapping-repo`
  (one marker covers both first-time bootstrap AND plugin-upgrade
  drift; there is no separate version-transition marker).
- **Routing block hashes** in `state.yml.routing_blocks[]`. Each entry
  pins a `target_file` (e.g., `AGENTS.md`) and a `block_hash` (sha256 of
  the canonical routing block text). Probe re-hashes the live block in
  the target file; mismatch indicates user modification (handled by
  the M7 routing-block stage's three-way prompt inside the unified
  setup-stages flow per ADR-0012 + ADR-0018, executed by
  `bootstrapping-repo`).
- **Per-repo `.board-superpowers/config.yml`** (committed to git,
  opposite of `state.yml`). Schema in
  `0005-contracts/03-config-schemas.md` § "`<repo>/.board-superpowers/config.yml` — RepoConfig".
  Required: `project: <owner>/<number>`. Optional:
  `wip_cap_per_consumer`, `autonomy_overrides`. The probe reads this for
  project coordinates whenever the consuming-card / managing-board
  skills need them.

### Query patterns

- **`yq '.schema_version' state.yml`** — version drift detection.
- **`yq '.routing_blocks[].block_hash' state.yml`** — recompute-and-diff
  to detect routing block tampering.
- **`yq '.project' .board-superpowers/config.yml`** — project
  coordinates resolution before any `gh project ...` call.
- **`bash hooks/session-start.sh`** can be invoked manually as a
  self-check (it prints any `INVOKE: ...` marker it would have emitted
  on a real session start, plus `REASON: ...`).

### Retention

State files are durable until manually deleted; they outlive any
session. The host manifest persists across all repos on the host; the
per-repo state files persist per-`(host, repo)` pair. No automatic
rotation; size is bounded (each file ≤ a few KB).

### Explicit non-coverage

- **No history of state changes.** `state.yml` is the current state, not
  a journal. Audit-log surface (next section) is where state-changing
  operations are recorded.
- **No cross-repo aggregation.** Each repo's state file is independent;
  no "fleet view" exists in v1. If a contributor wants to know "which of
  my N repos are on plugin v0.1 vs v0.2", they need to grep manually.
  Per ADR-0011 deferral pattern, this is on the v1.x candidates list
  pending demand.

## Audit-log surface (BYO RDBMS — deferred via `auditing-actions`)

The full audit-log surface is the contract that the deferred atomic
skill `auditing-actions` will own. Until that skill ships, the local
jsonl trace (next section) is the v1-minimum substitute. This section
documents the v1-target shape so future implementations (and current
architect understanding) align on what the deferred surface looks like.

### Schema — 8 columns

The single source of truth for the column-level schema is
`0005-contracts/06-audit-log-schema.md` § "Core schema — 8 columns".
Reproduced here for ease of lookup; if the two diverge, the contracts
file is canonical.

| Column | Postgres type | Notes |
|--------|---------------|-------|
| `timestamp` | `TIMESTAMPTZ` | UTC; wall-clock of write |
| `project` | `TEXT` | `OWNER/NUMBER` (round-trip stable per ADR-0005) |
| `session_id` | `TEXT` | CC / Codex session id (UUID-shaped at v1) |
| `actor_role` | `TEXT` (CHECK in `('producer','consumer')`) | lowercase per `0005-contracts/06-audit-log-schema.md` table note ("§1.4 cross-cutting note + 0003 § 3.3.8"); same row schema is enforced for both Producer and Consumer entries by I-8 (audit-log uniformity) |
| `action_id` | `SMALLINT` | matrix row id from `classifying-actions` (deferred) |
| `payload` | `JSONB` | per-`action_id` schema; canonical sub-schemas in `0005-contracts/06-audit-log-schema.md` |
| `outcome` | `TEXT` (CHECK in `('success','failure')`) | execution-layer terminal state |
| `approval_stage` | `TEXT` (CHECK in `('auto','propose','approved','rejected')`) | process-layer position; orthogonal to outcome |

The `outcome` × `approval_stage` orthogonality is load-bearing: an
A-class action lands as `(success, auto)` or `(failure, auto)`; an
R-class action lands as one row `(success, propose)` followed by one row
`(success, approved)` or `(failure, rejected)`; the
rejected-then-resolved chain produces three rows. This shape is what
`0006-failure-modes.md` Scenarios (a)–(g) reference in the "Audit-log
entry shape" field of each entry.

### Query patterns

The schema is designed for these architect-facing queries:

- **"Show me everything #33 touched."** `SELECT * FROM audit_log WHERE
  payload->>'card_number' = '33' ORDER BY timestamp;`
- **"Which actions are awaiting my approval?"** `SELECT * FROM audit_log
  WHERE approval_stage = 'propose' AND session_id = '<current>' ORDER BY
  timestamp DESC;`
- **"What did session X do?"** `SELECT timestamp, action_id, outcome,
  approval_stage FROM audit_log WHERE session_id = 'X' ORDER BY
  timestamp;`
- **"R-class rejection rate over the last week."** `SELECT count(*)
  FILTER (WHERE approval_stage='rejected') * 1.0 / count(*) FILTER
  (WHERE approval_stage IN ('approved','rejected')) FROM audit_log WHERE
  timestamp > now() - interval '7 days';` (informs autonomy_overrides
  tuning per ADR-0006 § 4 trust evolution clause)
- **"Find the gap entries (Scenario b recovery markers)."** `SELECT *
  FROM audit_log WHERE action_id = (SELECT id FROM action_catalog WHERE
  name = 'audit.recovery.gap-noted');`

The query surface is intentionally SQL — one of the points of choosing
BYO RDBMS over a custom file format (per ADR-0006 § 5) is that
architects already know SQL and can ad-hoc whatever they need without
plugin-side tooling.

### Retention

The plugin does not enforce retention. Architects choose their own
retention policy at the database level (`DELETE FROM audit_log WHERE
timestamp < ...`). Per P7 (mechanism not infrastructure), retention is
the architect's decision; the plugin only writes.

Recommended starter policies for common scenarios:

- **Single-architect dogfood.** Keep forever. The volume per session is
  dozens of rows; even at 10 sessions a day for a year that is < 50k
  rows, well within "trivial" for any RDBMS.
- **Multi-contributor team.** Retain ≥ 90 days for forensic / on-call
  needs; archive older rows to cold storage if compliance requires.
- **Compliance-heavy environment (regulated industry).** Retain per the
  regulation; plugin imposes no upper bound.

### Explicit non-coverage

- **No PII redaction.** Architects choose what goes into `payload`; if
  PII makes it in, it stays in. The plugin does not scrub.
- **No write-side encryption.** TLS to the database is the architect's
  responsibility (set in DSN); at-rest encryption is the database's
  responsibility. Plugin treats the audit-log write call as a simple SQL
  INSERT.
- **No real-time alerting.** Querying for failures is on-demand; the
  plugin does not push notifications. If alerting is needed, architects
  build it on top of the SQL surface.

## Local jsonl trace surface (v1-minimum)

Until `auditing-actions` lands, every mutating action writes one line to
`~/.board-superpowers/repos/<normalized>/audit-local.jsonl` via
`bsp_audit_local_write` (defined in `scripts/lib/common.sh`).

### Schema — 7 fields

Each line is a single JSON object. Fields:

| Field | Type | Notes |
|-------|------|-------|
| `ts` | string (ISO 8601 UTC) | wall-clock at write time |
| `repo_root` | string (absolute path) | the primary working tree resolved by `bsp_primary_repo_root` |
| `action_id` | string (dotted) | e.g., `consumer.card.claim`, `producer.card.promote-to-ready` |
| `decision_class` | string | `A` / `R` / `N` (matches the BYO RDBMS `approval_stage` semantics with a different label) |
| `skill` | string | originating skill (`consuming-card`, `managing-board`, etc.) |
| `summary` | string | one-line human-readable description |
| `mode` | string | always `v1-minimum-degraded` while the BYO RDBMS surface is deferred |

The shape diverges from the BYO RDBMS schema because the local trace is
a degraded substitute, not the canonical surface. Mapping when the BYO
RDBMS lands:

- `ts` → `timestamp`
- `action_id` (string) → catalog lookup → `action_id` (SMALLINT)
- `decision_class` `A` → `approval_stage='auto'`; `R` → `approval_stage
  in ('propose','approved','rejected')` (need to split into two rows
  during reconcile); `N` → no audit row required (or
  `approval_stage='auto'` with explicit "no-op" payload)
- `skill` → folded into `payload.skill`
- `summary` → folded into `payload.summary`
- `repo_root` + project info → `project` (requires
  `.board-superpowers/config.yml` lookup at reconcile time)
- `mode` → not migrated (it is the v1-minimum marker itself)

The reconciler that performs this migration when BYO RDBMS comes online
is TBD scope for `auditing-actions` skill landing.

### Query patterns

- **"Everything #33 touched."** `grep -n '#33\|"summary":".*P1=#33'
  ~/.board-superpowers/repos/<normalized>/audit-local.jsonl | jq .`
- **"Most recent action."** `tail -1
  ~/.board-superpowers/repos/<normalized>/audit-local.jsonl | jq .`
- **"All R-class actions in this repo."** `jq -c 'select(.decision_class
  == "R")' ~/.board-superpowers/repos/<normalized>/audit-local.jsonl`
- **"Action count by skill."** `jq -r '.skill'
  ~/.board-superpowers/repos/<normalized>/audit-local.jsonl | sort |
  uniq -c | sort -rn`

### Retention

Append-only; no rotation. The file is small (each entry < 1 KB; a heavy
day produces < 50 entries) and lives outside any git repo, so growth is
bounded by host disk and is not a concern in practice. If an architect
chooses to archive / rotate, plain `mv` works — the plugin re-creates
the file on the next write.

### Explicit non-coverage

- **No cross-repo aggregation.** Each repo has its own jsonl file. Same
  constraint as state.yml.
- **No write-side validation.** `bsp_audit_local_write` does not verify
  that `action_id` strings follow a catalog; the BYO RDBMS will, via its
  `SMALLINT` enum-constrained column.
- **No two-row R-class shape.** v1-minimum writes one entry per R-class
  action with `decision_class=R` (after the architect ack is recorded as
  the act of running the script). The two-row "propose then resolve"
  shape is deferred until `auditing-actions` lands, because v1-minimum's
  degraded R-class default treats every mutation interactively (the
  architect is in the loop synchronously, so the propose-resolve gap is
  always zero seconds).

## Cross-surface interactions

The four surfaces compose, they do not duplicate. The interactions worth
knowing:

- **State-probe writes touch both the in-session surface AND the state
  file.** When `using-board-superpowers` updates
  `state.yml.routing_blocks` after re-injecting a routing block, the
  in-session surface emits `[bsp] routing-block updated in
  <target_file>` and the state file gains a fresh `block_hash`. The
  audit-log surface does NOT record this — touching `state.yml` is
  plugin-internal hygiene, not a board mutation (per
  `0006-failure-modes.md` § "Scenario (g)" repair entry note).
- **In-session surface MUST surface audit-log surface failures.** When
  `bsp_audit_local_write` fails (Scenario b), the calling skill prints
  the error to the in-session surface — silent failure is forbidden per
  the audit gap = contract violation rule.
- **Hook intent-injection markers are advisory, state probe is
  authoritative.** If the hook fires and the marker says `INVOKE:
  bootstrapping-repo` but the state probe finds bootstrap already
  complete, the probe wins and the entry skill ignores the marker. The
  in-session surface emits `[bsp] hook marker stale (state-probe
  authoritative); ignoring INVOKE: bootstrapping-repo` so the
  discrepancy is visible.

## What you do NOT observe in v1

By design, the following are NOT exposed by any v1 surface:

- **Per-Consumer performance.** Sessions are anonymous to the board. The
  audit log carries `session_id` for forensics, but there is no
  "Consumer X completed N cards this week" surface. Per
  `0001-positioning.md` P2b and ADR-0006 § 4, performance metrics are an
  explicit non-feature — they invite optimization for the metric over
  the work.
- **Story points / velocity.** Cards carry an Estimate field with values
  XS / S / M / L; that is the only sizing surface. No point sum, no
  burndown, no velocity. Per
  `feedback_question_human_team_ceremonies_in_ai_context`, all of these
  are human-team ceremony shapes rejected under cadence scrutiny.
- **SLA / SLO targets.** There are no numeric thresholds for any
  operation. Architects calibrate from in-session signals and audit-log
  queries on actual behavior, not from pre-set numeric goals. ADR-0010
  § 3 establishes the AI cadence 100x convention for time + scope-shaped
  quantities; this section extends the spirit of that convention to
  observability thresholds — calendar / numeric thresholds carry the
  same human-team-cadence assumption that ADR-0010 § 3 banned for time
  / scope, so setting them here would re-introduce vestigial ceremony
  shapes by analogy.
- **Real-time dashboards.** No web UI, no tray icon, no notification
  surface. Observability in v1 is "the architect runs `cat
  audit-local.jsonl | jq` when curious" — pull, not push. Pushing a
  dashboard is an F-05-shaped surface and is deferred per ADR-0011.
- **Cross-machine telemetry.** The plugin is host-local; nothing leaves
  the architect's machine except the GitHub API calls explicitly named
  by the work. No phone-home, no usage metrics.
- **Test-coverage metrics.** `0008-test-architecture.md` documents the
  test surface; metric thresholds for coverage (% of scripts, % of
  skills) are deferred until the v1.x CI toolchain decision per
  ADR-0011's "Group A" deferral logic.

## Open questions (out of scope for v1; tracked for v1.x)

- Should the audit log include a column for the originating user-prompt
  text? Useful for "what did the architect actually ask for"; risky
  because user prompts may include PII. Deferred until a concrete demand
  pull surfaces (per ADR-0011 re-open trigger).
- Is there value in emitting OpenTelemetry spans from `[bsp ...]` log
  lines? Would let architects feed observability into existing
  infrastructure. Currently no demand; defer.
- Should the plugin offer an opt-in metrics sink (e.g., StatsD line per
  mutating action)? Same answer — defer until demand pull.

## Related

- ADR-0006 § 5 — Audit log persistence + R-class degradation (the
  canonical decision behind the audit-log surface).
- ADR-0009 — Allow SQLite as a BYO audit DB scheme (widens the "DB"
  definition for the audit-log surface; does not change shape).
- ADR-0010 — AI cadence 100x convention (informs the "what you do NOT
  observe" section: timing / velocity / SLA targets are vestigial under
  AI cadence).
- ADR-0011 — Defer Producer routines F-03..F-07 + F-10..F-15 to v1.x
  pending demand pull (covers F-05 board health snapshot, F-13 weekly
  report; observability for those surfaces is consequently deferred).
- `0005-contracts/06-audit-log-schema.md` — canonical 8-column schema
  (this doc summarizes and cross-references; that doc is source of
  truth).
- `0005-contracts/03-config-schemas.md` — per-repo state.yml +
  config.yml schemas referenced from the state-probe surface section.
- `0006-failure-modes.md` — every failure-mode entry's "Detection
  signal" field cross-references this doc; this doc is the
  reverse-direction reference.
- `0008-test-architecture.md` — test surfaces are themselves observed
  (test results land in CI logs, not in the audit log); this doc
  deliberately does not duplicate that.
- `bootstrapping-repo/SKILL.md` — F-B1 / F-B2 set up the state-probe
  surface for a fresh repo.
- `using-board-superpowers/SKILL.md` § "Step 1 — re-run dep + state
  check (Layer 2 reliable gate)" — the entry skill is the primary
  consumer of the state-probe surface.
- `feedback_question_human_team_ceremonies_in_ai_context` (auto-memory)
  — drives "what you do NOT observe" deferrals.
