# Decision matrix — Producer rows 1-14 + Consumer rows 100-113

This is the canonical decision table for the skill. Every mutating action
maps to one row; the row's `default class` is the starting point for
classification (see `triage-rule.md` for the short-circuit rule that may
escalate Auto to Reserved, and `override-parsing.md` for the layered
overrides that may promote Reserved to Auto).

## Producer rows (1-14)

| `action_id` | Action | Default class | Category |
|-------------|--------|---------------|----------|
| 1 | Create cards (decomposition output) | A | forward incremental |
| 2 | Edit card body (refine description, add acceptance criteria) | A | forward incremental |
| 3 | Split card | R | cross-card structural |
| 4 | Update CLAUDE.md / AGENTS.md | R | source of truth |
| 5 | Backlog → Ready transition | A | forward state advance |
| 6 | In Progress → Blocked transition | R | interrupts in-flight work |
| 7 | Close stale card | R | irreversible + interrupts |
| 8 | Cancel claim | R | interrupts + risks lost work |
| 9 | Adjust WIP limit | A | reversible parameter |
| 10 | Modify .board-superpowers/config.yml or config.local.yml | R | source of truth |
| 11 | Extend GitHub Project fields (add label / add status option) | A | forward incremental, schema-additive |
| 12 | Auto-merge PR | R | architect's reserved power |
| 13 | Dispatch Consumer session | A | unlocks overnight batch |
| 14 | Auto-trigger retro / weekly report (cadence-driven) | A | preflight piggyback |

## Consumer rows (100-113)

| `action_id` | Action | Default class |
|-------------|--------|---------------|
| 100 | Claim card (atomic git-push transaction) | A |
| 101 | Surface (propose-and-suspend) | R |
| 102 | Terminate — success path | A |
| 103 | Terminate — failure path (Blocked + release claim + keep worktree) | R |
| 104 | Retro Notes write (initial at PR-submit + post-merge supplement) | A |
| 105 | Review-cycle response — direct one-line fix | A |
| 106 | Review-cycle response — re-delegation | A |
| 107 | Review-cycle response — verification chain | A |
| 108 | Review-cycle response — cross-platform review | A |
| 109 | Review-cycle response — QA pass | A |
| 110 | Review-cycle response — security audit | A |
| 111 | Review-cycle response — cycle completion | A |
| 112 | PR-submit pre-flight — card body sync (toggle ACs to `[x]`, write implementation summary) | A |
| 113 | Post-merge cleanup — remove worktree + delete local claim branch + write close audit row | A |

## Reused Producer rows on the Consumer side

When a Consumer-side action has identical semantics to a Producer-side row,
it reuses the Producer `action_id` and writes `actor_role = consumer` in
the audit entry:

- Consumer Ready → In Progress at claim → Producer row 5 (status advance).
- Consumer cancel claim → Producer row 8 (matches semantics).
- Consumer attempts Auto-merge → Producer row 12 (which is class N for
  Consumer; hard-floor block).

## Unknown action_id rule

If the caller passes an `action_id` not listed above, the algorithm
returns A (default fall-through). This is deliberate — new mutating
actions that haven't yet been classified default to safe-on-execution
rather than block-on-unknown.
