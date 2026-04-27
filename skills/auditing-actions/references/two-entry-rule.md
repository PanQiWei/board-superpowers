# Two-entry rule for R-class actions

A-class actions write **one** audit row. R-class actions write **two**
— a propose entry when the action is drafted, and a resolve entry when
the architect responds.

## A-class: one row

| Column | Value |
|--------|-------|
| `approval_stage` | `auto` |
| `outcome` | `success` if the action's side effect landed; `failure` if it errored |
| `payload` | the per-action_id JSON shape with full action details |

The single row records: this happened automatically, here's what it did,
here's whether it succeeded.

## R-class: two rows, ordered by timestamp

### Entry 1: propose

Written immediately after `classifying-actions` returns R, BEFORE the
architect sees the proposal text.

| Column | Value |
|--------|-------|
| `approval_stage` | `propose` |
| `outcome` | `success` (the proposal was successfully drafted and presented), or `failure` (drafting itself failed) |
| `payload` | `{"proposal": "<text shown to architect>", "would_be_params": {...}}` |

### Entry 2: resolve

Written after the architect responds (approves OR declines) AND, if
approved, after the action's side effect runs.

| Column | Value (approved) | Value (rejected) |
|--------|------------------|------------------|
| `approval_stage` | `approved` | `rejected` |
| `outcome` | `success` if action ran cleanly; `failure` if action errored | `success` (decline successfully recorded) |
| `payload` | full action details, with `before_*` / `after_*` populated as appropriate | `{"decline_reason": "<text>"}` |

### Both entries linked

The two entries share `session_id`, `action_id`, `project`, and
`actor_role`. They're linked by timestamp ordering — entry 2 always has
a later timestamp than entry 1.

## Why two entries

Cleanly answers two distinct queries:

- "What's currently waiting for architect approval?" — `WHERE
  approval_stage = 'propose' AND no matching resolve entry exists`
- "What did the architect approve last week, and how did it go?" —
  `WHERE approval_stage IN ('approved','rejected') AND timestamp > ...`

A single-entry shape would conflate "this proposal exists" with
"this action happened" — useful for some queries, lossy for others.
