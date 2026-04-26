# 06 — Audit log schema

> Pin the BYO-RDBMS audit-log shape: the core 8 columns, per-
> `action_id` payload sub-schemas, the orthogonal `outcome` /
> `approval_stage` enums, AuditTrail scope (per-Project), DDL
> ownership (one-shot init script), and the migration model.
>
> Promotes ADR-0006 §5 draft to canonical and resolves TBD-3, TBD-4,
> TBD-5 from 0003 § 3.3.8.

---

## Core schema — 8 columns

The AuditEntry value object. Append-only; immutable once written;
no UPDATE / DELETE supported in the contract.

| Column | Type (Postgres) | Type (MySQL equiv) | Required? | Notes |
|--------|-----------------|--------------------|-----------|-------|
| `timestamp` | `TIMESTAMPTZ` | `DATETIME(3)` | yes | Wall-clock time the entry was written. Always UTC. |
| `project` | `TEXT` | `VARCHAR(255)` | yes | `OWNER/NUMBER` string identifying the GitHub Project (round-trip stable per ADR-0005). |
| `session_id` | `TEXT` | `VARCHAR(64)` | yes | The originating CC or Codex session id (UUID-shaped at v1). |
| `actor_role` | `TEXT` (CHECK in `('producer','consumer')`) | `ENUM('producer','consumer')` | yes | Lowercase per §1.4 cross-cutting note + 0003 § 3.3.8. |
| `action_id` | `SMALLINT` | `SMALLINT` | yes | Matrix row id; see "action_id catalog" below. |
| `payload` | `JSONB` | `JSON` | yes | Per-`action_id` shape; see "Per-`action_id` payload sub-schemas" below. |
| `outcome` | `TEXT` (CHECK in `('success','failure')`) | `ENUM('success','failure')` | yes | **Execution-layer** terminal state — did the action's effect land cleanly. See "outcome enum" below. |
| `approval_stage` | `TEXT` (CHECK in `('auto','propose','approved','rejected')`) | `ENUM('auto','propose','approved','rejected')` | yes | **Process-layer** position in the approval lifecycle — orthogonal to `outcome`. See "approval_stage enum" below. |

### Indices (recommended)

The plugin DOES NOT manage indices on the architect's database
(per P7 — mechanism, not configuration). The DDL init script
creates a primary surrogate key + the CHECK constraints; index
choices are the architect's. Suggested starter:

```sql
CREATE INDEX audit_project_timestamp_idx ON audit_log(project, timestamp DESC);
CREATE INDEX audit_session_idx           ON audit_log(session_id);
CREATE INDEX audit_action_id_idx         ON audit_log(action_id);
CREATE INDEX audit_approval_stage_idx    ON audit_log(approval_stage);
```

### Cited rationale

- ADR-0006 §5 (audit-entry schema draft, finalized here).
- 0003 § 3.3.8 AuditTrail aggregate (canonical entity home).
- I-8 (audit-log uniformity — Producer + Consumer entries share
  one schema).

---

## `outcome` enum (execution layer)

`outcome` records what happened when the action's effect was
applied. It is the answer to "did the side effect land".

| Value | When to write |
|-------|---------------|
| `success` | The action's side effect (state mutation, GitHub call, file write) executed cleanly |
| `failure` | The action attempted but failed (transport / permission / schema_mismatch / hard-floor block) |

`outcome` is required on every entry. R-class proposal entries
(`approval_stage = 'propose'`) carry `outcome = success` if the
proposal was successfully drafted and presented to the architect,
or `outcome = failure` if proposal drafting itself failed.

## `approval_stage` enum (process layer)

`approval_stage` records where the action sits in the approval
lifecycle. It is the answer to "what was the governance path".

| Value | When to write |
|-------|---------------|
| `auto` | A-class action — executed without architect approval (per ADR-0006 D-AUTONOMY-1) |
| `propose` | R-class action's first entry — Producer drafted the proposal and is awaiting architect response |
| `approved` | R-class action's second entry — architect approved AND the action then executed (with `outcome` reporting the execution result) |
| `rejected` | R-class action's second entry — architect declined the proposal (`outcome = success` since "successfully recorded the rejection") |

### Two-entry rule for R-class actions

Per ADR-0006 §1: every R-class action writes **two** AuditEntry
rows.

- **Entry 1 (propose):** `approval_stage = 'propose'`,
  `outcome = success` (proposal drafted and presented).
  `payload` carries the proposal text + the action's would-be
  parameters.
- **Entry 2 (resolve):** `approval_stage ∈ {'approved', 'rejected'}`
  depending on architect response. If `approved`, `outcome ∈
  {success, failure}` reflects whether the post-approval execution
  succeeded. If `rejected`, `outcome = success`.

The two entries share `session_id` + `action_id` + `project`;
they're linked via timestamp ordering (entry 2 always has a later
timestamp than entry 1).

### A-class single-entry rule

A-class actions write **one** AuditEntry row with
`approval_stage = 'auto'` and `outcome ∈ {success, failure}`.

### Why two enums instead of one

Earlier draft (pre-2026-04-26) had a single `outcome` column
with values `{success, failure, escalated, rejected}`, which
conflated the execution-layer question ("did it work") with the
process-layer question ("what stage of approval"). The split
makes the dominant queries crisp:

- "Last week's failed actions": `WHERE outcome = 'failure'`
- "Last week's rejected proposals": `WHERE approval_stage = 'rejected'`
- "All A-class executions on Project X this month":
  `WHERE approval_stage = 'auto' AND project = 'X' AND timestamp > '...'`

---

## `action_id` catalog

`action_id` is a stable integer reference into a documented
matrix. The matrix has two halves:

- **Producer rows: 1–14** — from ADR-0006 §3 (canonical).
- **Consumer rows: 100–111** — finalized here per TBD-3 (canonical
  numbering proposal in this file). Rows 105–111 split the prior
  single "review-cycle response" row into seven sub-action rows so
  retro queries can filter by sub-action at the column level
  rather than via JSONB path extraction.

Producer-vantage rows that apply symmetrically to Consumer-side
actions (per §1.4 cross-cutting note — rows 8 / 12 / 13) keep their
Producer numbers and are written with `actor_role = consumer`. A
sibling Consumer row in the 100-range exists ONLY where the action
has no Producer counterpart (claim, surface, terminate, etc.).

### Producer rows — 1–14 (per ADR-0006 §3)

| `action_id` | Action | Default class |
|-------------|--------|---------------|
| 1 | Create cards (decomposition output) | A |
| 2 | Edit card body (refine description, add acceptance criteria) | A |
| 3 | Split card | R |
| 4 | Update `CLAUDE.md` / `AGENTS.md` | R |
| 5 | Backlog → Ready transition | A |
| 6 | In Progress → Blocked transition | R |
| 7 | Close stale card | R |
| 8 | Cancel claim | R |
| 9 | Adjust WIP limit | A |
| 10 | Modify `.board-superpowers/config.yml` | R |
| 11 | Extend GitHub Project fields (add label / add status option) | A |
| 12 | Auto-merge PR | R (and N for Consumer per I-2) |
| 13 | Dispatch Consumer session | A |
| 14 | Auto-trigger retro / weekly report (cadence-driven) | A |

### Consumer rows — 100–111 (canonical, finalized per TBD-3)

| `action_id` | Action | Default class | Symmetric Producer row? |
|-------------|--------|---------------|------------------------|
| 100 | Claim card (atomic git-push) | A | none (claim is a Consumer-only primitive; § 1.4.1 F-C1) |
| 101 | Surface (F-C8 — propose-and-suspend) | R | partial mirror of row 4 / 8 in spirit; gets its own number because the action shape is Consumer-specific |
| 102 | Terminate — success path | A | none (success is a Consumer terminal action) |
| 103 | Terminate — failure path (Blocked + release claim + keep worktree) | R | partial mirror of row 6 (In Progress → Blocked); kept as a Consumer row because the side effects (claim release, worktree preservation) are Consumer-specific |
| 104 | Retro Notes write (initial at PR-submit + post-merge supplement) | A | none |
| 105 | Review-cycle response — direct one-line fix (apply architect's literal suggestion) | A | none (Consumer-only; § 1.4.1 F-C13) |
| 106 | Review-cycle response — re-delegation (hand back to `superpowers:subagent-driven-development` for substantive change) | A | none |
| 107 | Review-cycle response — verification chain (`superpowers:verification-before-completion` + `superpowers:requesting-code-review`) | A | none |
| 108 | Review-cycle response — cross-platform review (`gstack:/codex` adversarial pass) | A | none |
| 109 | Review-cycle response — QA pass (`gstack:/qa` browser-real verification) | A | none |
| 110 | Review-cycle response — security audit (`gstack:/cso` OWASP / STRIDE pass) | A | none |
| 111 | Review-cycle response — cycle completion (final commit + reply summarizing what landed across rows 105–110 in this cycle) | A | none |

#### Numbering rationale

- 100-range chosen to avoid collision with future Producer rows
  (matrix-numbering reserves 1–99 for Producer expansion).
- Six rows is the minimum to cover the lifecycle moments listed
  in §1.4 (claim, surface, success-terminate, failure-terminate,
  retro write, review-cycle). Smaller sub-actions (F-C2 fetch,
  F-C3 worktree-entry, F-C7 hard-floor block) are folded into
  the surrounding row's payload (e.g., F-C3 transition emits
  a Producer row 13 entry with `actor_role = consumer` because
  it's a status transition, not a Consumer-specific action).
- F-C9 / F-C10 / F-C11 verification-chain invocations do NOT each
  get their own `action_id` — they emit one AuditEntry per
  invocation under `action_id = 105` with a `subaction` field in
  the payload distinguishing them. Rationale: the verification
  chain is one logical Consumer action ("run pre-submit checks");
  the per-skill outcomes are payload detail.

#### Consumer rows that REUSE Producer row numbers

- `actor_role = consumer` + `action_id = 5` — Consumer transitions
  Ready → In Progress at F-C3 (re-uses row 5 because the action
  semantics are identical to Producer's Backlog → Ready
  transition). Per §1.4.1 F-C3 + 0003 § 3.3.3.
- `actor_role = consumer` + `action_id = 13` — Mode-2 wake-up of a
  suspended Consumer (re-uses row 13 because dispatch is
  dispatch). Per §1.4 cross-cutting note "rows 8/12/13 apply
  symmetrically".

---

## Per-`action_id` payload sub-schemas

Each payload is a JSON object. v1 spec finalizes the shape per
TBD-3. Future fields can be added (additive only); removing or
renaming requires a payload-schema migration (analogous to I-12).

The `payload` column is JSONB / JSON — the database doesn't
enforce shape. Shape is enforced at write-time by the script /
SKILL emitting the entry.

### Producer — `action_id = 1` (Create card)

```json
{
  "card_number": 42,
  "title": "Sign in with Google — happy path",
  "labels": ["type:feature", "size:S"],
  "milestone": "v1.0",
  "threads": ["auth"],
  "size": "S",
  "depends_on": [44]
}
```

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `card_number` | integer | yes | Issue number assigned by GitHub |
| `title` | string | yes | The created Issue title |
| `labels` | string list | yes | Applied at creation (may be empty `[]`) |
| `milestone` | string \| null | optional | GitHub Milestone name if any |
| `threads` | string list | optional | Per 0003 § 3.3.1 ThreadRef value object |
| `size` | string `XS\|S\|M\|L` | yes | Mirror of card body Size; for filtering |
| `depends_on` | int list | optional | Card numbers this Card depends on (parsed from Context) |

### Producer — `action_id = 2` (Edit card body)

```json
{
  "card_number": 42,
  "before_sha256": "sha256:<64-hex>",
  "after_sha256": "sha256:<64-hex>",
  "sections_changed": ["Acceptance Criteria", "Out of Scope"]
}
```

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `card_number` | integer | yes | |
| `before_sha256` | string | yes | SHA256 of full Card body before edit |
| `after_sha256` | string | yes | SHA256 of full Card body after edit |
| `sections_changed` | string list | yes | Section header names (without leading `## `) the edit touched |

### Producer — `action_id = 3` (Split card)

```json
{
  "source_card": 42,
  "split_into": [50, 51, 52],
  "rationale": "OAuth callback grew to 320 LOC; split into happy/error/sign-out."
}
```

R-class — emits the propose entry (`outcome = escalated`,
`payload.proposal: <text>`) AND the resolve entry (`outcome ∈
{success, failure, rejected}`, `payload.split_into: [...]` populated
on `success`).

### Producer — `action_id = 4` (Update CLAUDE.md / AGENTS.md)

R-class. Two entries: propose + resolve.

```json
{
  "files": ["CLAUDE.md", "AGENTS.md"],
  "diff_excerpt": "<short prose summary of the change>",
  "before_block_hashes": {
    "CLAUDE.md": "sha256:<hex>",
    "AGENTS.md": "sha256:<hex>"
  },
  "after_block_hashes": {
    "CLAUDE.md": "sha256:<hex>",
    "AGENTS.md": "sha256:<hex>"
  }
}
```

`before_*` / `after_*` populated only on the resolve entry's
`success` outcome.

### Producer — `action_id = 5` (Backlog → Ready transition)

```json
{
  "card_number": 42,
  "from_status": "Backlog",
  "to_status": "Ready",
  "input_completeness_check": "passed"
}
```

`input_completeness_check` is `"passed"` (per ADR-0006 row 5 spec
gate — Producer's input-completeness validation; see I-9).

### Producer — `action_id = 6` (In Progress → Blocked)

R-class. Two entries.

```json
{
  "card_number": 42,
  "from_status": "In Progress",
  "to_status": "Blocked",
  "reason": "<blocker text>",
  "claim_branch": "claim/42-oauth-callback"
}
```

### Producer — `action_id = 7` (Close stale card)

R-class. Two entries.

```json
{
  "card_number": 42,
  "rationale": "<why closing without merge>",
  "last_activity": "2026-04-20T13:00:00Z"
}
```

### Producer — `action_id = 8` (Cancel claim)

R-class. Two entries. Symmetric on Consumer side too (when
Consumer initiates abandonment).

```json
{
  "card_number": 42,
  "branch": "claim/42-oauth-callback",
  "session_slug": "s-a7b3",
  "rationale": "<why canceling>",
  "delete_branch": true,
  "delete_worktree": false
}
```

`delete_worktree: false` is the F-C14 failure-path default
(worktree preserved for human takeover, per ADR-0003).

### Producer — `action_id = 9` (Adjust WIP limit)

```json
{
  "before": 5,
  "after": 7,
  "rationale": "<why changing>"
}
```

### Producer — `action_id = 10` (Modify config.yml)

R-class. Two entries.

```json
{
  "before_sha256": "sha256:<hex>",
  "after_sha256": "sha256:<hex>",
  "fields_changed": ["wip_limit", "autonomy_overrides"]
}
```

`autonomy_overrides:` writes pass through this row.

### Producer — `action_id = 11` (Extend Project fields)

```json
{
  "field_kind": "label",
  "name": "type:experimental",
  "color": "ff5722"
}
```

`field_kind ∈ {label, status_option}` at v1.

### Producer — `action_id = 12` (Auto-merge PR)

R-class for Producer; **N for Consumer** (per I-2 — Consumer
cannot self-merge). On Consumer side: a Consumer attempting this
action is a Hard-floor block (per F-C7) and emits an `action_id =
12` entry with `outcome = failure`, `actor_role = consumer`, plus
`payload.blocked_at_layer = "hard_floor"`.

```json
{
  "pr_number": 123,
  "card_number": 42,
  "merge_method": "squash",
  "blocked_at_layer": null
}
```

### Producer — `action_id = 13` (Dispatch Consumer)

```json
{
  "card_number": 42,
  "mode": "Mode-1",
  "consumer_session_id": "<UUID-shape>",
  "dispatch_concurrency": 1,
  "wake_up": false
}
```

| Field | Notes |
|-------|-------|
| `mode` | `"Mode-1"` (architect-spawned) or `"Mode-2"` (Producer-spawned subagent) |
| `consumer_session_id` | The new ConsumerProcess's session id, if observable at dispatch time |
| `dispatch_concurrency` | The current concurrency cap (per C-PLUGIN-3) |
| `wake_up` | `true` when this is a Mode-2 wake-up of a previously-suspended Consumer; `false` for fresh dispatch |

### Producer — `action_id = 14` (Auto-trigger retro / weekly report)

```json
{
  "trigger_kind": "retro",
  "trigger_reason": "milestone_close",
  "lookback_window_days": 7,
  "report_destination": "card_thread"
}
```

`trigger_kind ∈ {retro, weekly_report}`. `trigger_reason ∈
{milestone_close, n_cards_completed, decomposition_drift,
cadence_due}`.

### Consumer — `action_id = 100` (Claim card)

```json
{
  "card_number": 42,
  "branch": "claim/42-oauth-callback",
  "worktree": "/home/.../worktrees/proj/claim/42-oauth-callback",
  "session_slug": "s-a7b3",
  "base_branch": "main"
}
```

> Note: `worktree:` IS present here (this is the audit log, not the
> on-origin ClaimMarker). The audit DB is private to the architect
> (per ADR-0006 §5 "not public"); the info-leak guard applies only
> to artifacts on origin (see [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md)).

### Consumer — `action_id = 101` (Surface — F-C8)

R-class. Two entries (propose + resolve).

```json
{
  "card_number": 42,
  "trigger": "design_decision_point",
  "summary": "<one-line description of what needs architect input>",
  "channel": "card_thread_comment"
}
```

`trigger` enum (open-ended): `spec_insufficient`,
`design_decision_point`, `debug_stuck`, `cross_card_touch`,
`acceptance_criteria_unreachable`, `other`.

`channel` is always `"card_thread_comment"` at v1 (the primary
channel under both Modes per C-PLUGIN-1 workaround a). Mode-2
optional `SendMessage` is not load-bearing and not audited
separately.

### Consumer — `action_id = 102` (Terminate — success path)

```json
{
  "card_number": 42,
  "branch": "claim/42-oauth-callback",
  "pr_number": 123,
  "worktree_removed": true,
  "retro_supplemented": true
}
```

### Consumer — `action_id = 103` (Terminate — failure path)

R-class. Two entries.

```json
{
  "card_number": 42,
  "branch": "claim/42-oauth-callback",
  "blocked_reason": "<failure context>",
  "claim_released": true,
  "worktree_kept": true,
  "worktree_path": "/home/.../worktrees/proj/claim/42-oauth-callback"
}
```

### Consumer — `action_id = 104` (Retro Notes write)

```json
{
  "card_number": 42,
  "pr_number": 123,
  "phase": "initial",
  "lesson_summary": "<one-line summary of what landed in Retro Notes>"
}
```

`phase ∈ {initial, post_merge_supplement}` — the two-pass
authorship rule (§1.8.3).

### Consumer — `action_id = 105` (Review-cycle response — direct one-line fix)

```json
{
  "card_number": 42,
  "pr_number": 123,
  "cycle_index": 2,
  "comment_id_replied": 1234567890,
  "diff_lines_changed": 1,
  "commit_sha": "abc1234"
}
```

The architect's review comment was actionable as a literal
one-line edit; no skill orchestration involved.

### Consumer — `action_id = 106` (Review-cycle response — re-delegation)

```json
{
  "card_number": 42,
  "pr_number": 123,
  "cycle_index": 2,
  "delegated_to_skill": "superpowers:subagent-driven-development",
  "delegation_brief": "<one-line summary of what was handed off>",
  "commits_pushed": 3
}
```

The change was substantive enough to hand back to a TDD-driven
sub-agent rather than fix in line.

### Consumer — `action_id = 107` (Review-cycle response — verification chain)

```json
{
  "card_number": 42,
  "pr_number": 123,
  "cycle_index": 2,
  "skills_invoked": [
    "superpowers:verification-before-completion",
    "superpowers:requesting-code-review"
  ],
  "verification_outcome": "passed"
}
```

Standard pre-resubmit verification chain (F-C9 / F-C10).
`verification_outcome ∈ {passed, regressed, blocked}`.

### Consumer — `action_id = 108` (Review-cycle response — cross-platform review)

```json
{
  "card_number": 42,
  "pr_number": 123,
  "cycle_index": 2,
  "skill_invoked": "gstack:/codex",
  "findings_count": 2,
  "findings_addressed": 2
}
```

Per F-C11 cross-platform adversarial review.

### Consumer — `action_id = 109` (Review-cycle response — QA pass)

```json
{
  "card_number": 42,
  "pr_number": 123,
  "cycle_index": 2,
  "skill_invoked": "gstack:/qa",
  "qa_url": "https://staging.example.com/feature/...",
  "qa_outcome": "passed"
}
```

Mandatory for any UI-touching card per AGENTS.md routing block.
`qa_outcome ∈ {passed, failed, blocked}`.

### Consumer — `action_id = 110` (Review-cycle response — security audit)

```json
{
  "card_number": 42,
  "pr_number": 123,
  "cycle_index": 2,
  "skill_invoked": "gstack:/cso",
  "owasp_findings": 0,
  "stride_findings": 1,
  "findings_addressed": 1
}
```

OWASP / STRIDE audit. Triggered when the diff touches auth,
input handling, dependency lists, or secrets.

### Consumer — `action_id = 111` (Review-cycle response — cycle completion)

```json
{
  "card_number": 42,
  "pr_number": 123,
  "cycle_index": 2,
  "sub_actions_in_cycle": [105, 107, 109],
  "comments_replied": 3,
  "commits_pushed": 1,
  "ready_for_re_review": true
}
```

Final cycle entry — Consumer summarizes what changed across
`sub_actions_in_cycle` and signals the architect that the PR is
ready for the next review pass.

### Numbering rationale for the 105–111 split

The earlier draft bundled all seven sub-actions under a single
`action_id = 105` with a `subaction` JSONB field. The split
into per-sub-action `action_id`s was made to make horizontal
retro queries cheap:

- "Last week's QA passes": `WHERE action_id = 109`
- "Re-delegations this month per Consumer":
  `SELECT session_id, COUNT(*) FROM audit_log WHERE action_id = 106 GROUP BY session_id`
- "Cycles per card": `SELECT card_number, COUNT(*) FROM audit_log WHERE action_id = 111 GROUP BY card_number`

These would have required `payload->'subaction' = '...'` JSON
path queries (one-order-of-magnitude slower) under the bundled
shape. Vertical queries (cycle history per Card) are unaffected
by the split — both shapes filter on `card_number` first.

---

## AuditTrail scope — per-Project (TBD-5 finalized)

**Decision:** AuditTrail is **per-Project**. The `project` column
is the partitioning axis; one row → one Project.

**DB-physical cardinality is orthogonal.** One BYO RDBMS connection
MAY serve multiple Projects (architect shares an `audit_db_url`
across several `<repo>/.board-superpowers/config.yml` files), or
each Project MAY get its own DB. Both work because every query
carries `WHERE project = ?` regardless. The architect's
`audit_db_url` choice does not affect the logical scope decision.

### Why per-Project (not global, per-architect, per-Card, or per-host)

1. **Multi-architect symmetry on a single Project (I-3).** Two
   architects on the same Project converge to one logical
   AuditTrail; cross-architect timeline reconstruction is one query.
2. **Practical query scoping.** Daily / retro / F-13 weekly routines
   all use `WHERE project = ? AND timestamp > ?` as the dominant
   index path.

Rejected alternatives: per-architect (violates I-3); per-Card
(over-fragmentation, N joins for cross-card timeline); per-host
(splits one architect's two-machine workflow).

### Cited rationale

- 0003 § 3.3.10 TBD-5 — finalization here.
- I-3 (multi-architect symmetry).
- ADR-0006 §5 (BYO RDBMS — schema applies regardless of scope
  decision).

---

## DDL ownership — one-shot init script (TBD-4 finalized)

**Decision:** board-superpowers ships a one-shot
`scripts/audit-init.sh` that runs idempotent DDL the first time
`BOARD_SP_AUDIT_DB_URL` (or `~/.board-superpowers/credentials.yml`)
resolves successfully. Architect controls the DB; plugin owns the
schema.

### Script contract (forward-looking — not in v1 ship; lands per
TBD-4)

`scripts/audit-init.sh` will:

| Step | Behavior |
|------|----------|
| 1 | Read credentials from `BOARD_SP_AUDIT_DB_URL` env var or `~/.board-superpowers/credentials.yml:audit_db_url` (env-var precedence per [`03-config-schemas.md`](./03-config-schemas.md)) |
| 2 | Connect; refuse if the DSN is not Postgres or MySQL |
| 3 | Run idempotent DDL — `CREATE TABLE IF NOT EXISTS audit_log (…)` with the 7-column shape pinned above |
| 4 | Run idempotent DDL for the recommended starter indices (see "Indices" above) |
| 5 | Insert a sentinel `schema_version` row (or use a sibling `audit_schema_meta` table tracking `version: 1`) |
| 6 | Exit 0 on success; exit 1 on any DDL failure (architect fixes DB / scope) |

### Idempotency

DDL uses `IF NOT EXISTS` clauses so re-runs are safe. Indices
similarly. The schema-version sentinel is upserted (architect's
DB; we do not own the table — merely the schema definition).

### Exit codes (forward-looking)

| Code | Meaning |
|------|---------|
| `0` | DDL applied (or schema already at current version — no-op) |
| `1` | DB unreachable, DDL failed, credentials malformed |
| `2` | Bad arguments |
| `3` | Postgres / MySQL client (`psql` / `mysql`) unavailable on PATH |

### Why one-shot, not embedded

- Per P7 (D-META-1): we ship mechanism, not configuration. The
  architect explicitly opts in to schema creation by running the
  script.
- Per ADR-0006 §5 trade-off acknowledgment: BYO RDBMS adds
  onboarding friction; making it explicit (run a script) is the
  feature, not a bug.
- Embedding DDL into `bootstrap-project.sh` would couple per-repo
  setup to host-level audit configuration — orthogonal concerns.

### Cited rationale

- 0003 § 3.3.8 TBD-4 — finalization here.
- P7 / D-META-1 (mechanism, not configuration).
- ADR-0006 §5 (BYO RDBMS).

---

## Migration model — schema_version + lazy-on-read

When the audit-log schema needs to evolve (e.g., adding a column,
splitting `payload` further), reuse the I-12 pattern from
[`03-config-schemas.md`](./03-config-schemas.md):

| Mechanism | Behavior |
|-----------|----------|
| `audit_schema_meta` row tracking | `version: <int>` sentinel; updated by migration scripts |
| Migration scripts | `scripts/migrations/audit-v<N>-to-v<N+1>.sh` — one per source version; runs DDL + (if needed) data backfill; idempotent |
| Trigger | Lazy-on-read — when a session opens the audit DB and detects `audit_schema_meta.version < <plugin-known-max>`, the migration runs before any write |
| Older plugin reading newer schema | **Fail loudly.** Plugin refuses to write entries; surfaces "this audit DB is on schema v<X>; you're on plugin v<Y>; please upgrade" |
| Migration shape | Versioned-and-additive. Add columns. Never drop / rename. |

### Cited rationale

- I-12 (canonical pattern).
- §1.5.5 TBD-Notes (migration runner timing).
- 0003 § 3.3.8 TBD-4.

---

## DB-unavailable degradation

Per ADR-0006 §5 "Trade-off explicitly registered" + 0003 § 3.3.8
"DB-unavailable degradation rule":

If the audit DB is unreachable (network, credentials, DDL not
applied), **every A-class action degrades to R-class** (architect
prompted for everything Producer would otherwise auto-do). This
is the fallback that keeps the plugin usable when the DB is down;
the autonomy gain that A buys is lost while degraded.

The degradation is per-action, in-flight, surfaced via the
preflight piggyback: "audit DB unreachable; auto-actions paused
until restored. Approve dispatch of Card #42?"

### Cited rationale

- ADR-0006 §5.
- 0003 § 3.3.8.

---

## Cross-references

- [`03-config-schemas.md`](./03-config-schemas.md) —
  `~/.board-superpowers/credentials.yml` schema; env-vs-file
  resolution priority for `audit_db_url`.
- [`08-environment-variables.md`](./08-environment-variables.md) —
  `BOARD_SP_AUDIT_DB_URL` definition.
- [`07-path-conventions.md`](./07-path-conventions.md) —
  `~/.board-superpowers/credentials.yml` path + permissions.
- ADR-0006 (canonical autonomy boundary + audit-log persistence;
  this file finalizes the §5 schema draft and TBD-3 / TBD-4 /
  TBD-5).
- ADR-0007 (preflight piggyback — degradation surface).
- I-2, I-3, I-8 — invariants this file operationalizes.
- 0003 § 3.3.8 AuditTrail aggregate (entity-level home; TBDs
  finalized here).
