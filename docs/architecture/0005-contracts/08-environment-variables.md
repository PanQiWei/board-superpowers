# 08 — Environment variables

> Pin every environment variable board-superpowers reads — name,
> format, default, which scripts / hooks read it, and the originating
> ADR / feature spec / `AGENTS.md` section. Plus the
> plugin-contract integration variables (CC + Codex CLI) the runtime
> sets for us.
>
> Rationale lives in the cited ADR / feature spec / `PLUGIN_DEVELOPMENT.md`
> section. Shape lives here.

---

## Cross-variable conventions

These rules apply to every env var in this section:

- **Read-only from the plugin's perspective.** No script in
  `scripts/` or hook in `hooks/` exports a `BOARD_SP_*` value
  itself. The architect (or their shell init) sets these; the
  plugin reads them. Per ADR-0007 C-PLUGIN-2 (no daemon — no
  long-lived process state to maintain).
- **Defaults are documented inline.** Every variable has a
  documented default (often "unset = use built-in fallback"). A
  missing variable is never a hard error unless the table below
  marks it required.
- **Validation is fail-loud.** Where a variable's value is
  syntactically constrained (e.g., `BOARD_SP_WORKTREE_DIR` MUST
  be absolute), the script rejects bad input with exit `30`
  (`claim-card.sh` only) or `2` per
  [`01-script-contracts.md`](./01-script-contracts.md) exit-code
  table. Silent fallback to the default on bad input is forbidden.
- **Reserved namespace: `BOARD_SP_*`.** All plugin-specific env
  vars live in this namespace. Adding a new one requires updating
  this file and any caller in the same PR (per
  `docs/architecture/AGENTS.md` change-impact matrix; new env
  vars are a contract surface).

### `--machine` keys are NOT env vars

A common confusion to head off: `MISSING`, `ROUTING_INJECTED`, and
`PROJECT` are NOT environment variables. They are **stdout
key-value lines** emitted by `check-deps.sh --machine` and parsed
by `hooks/session-start.sh`. See
[`01-script-contracts.md`](./01-script-contracts.md) "`scripts/check-deps.sh`
→ Stdout / stderr" for the canonical contract. The output channel
happens to use `KEY=value` syntax that resembles env-var assignment;
that's where the resemblance ends.

---

## `BOARD_SP_*` — plugin-defined env vars

Enumerated from a `grep -rn "BOARD_SP_"` of `scripts/` and `hooks/`
on 2026-04-26. Three variables are read by the v1 codebase. A
fourth namespace (`BOARD_SP_AUDIT_*`) is reserved for ADR-0006 §5
follow-up; no current consumer.

### `BOARD_SP_WORKTREE_DIR`

| Property | Value |
|----------|-------|
| Format | Absolute filesystem path. Relative paths are rejected. |
| Default | unset → falls through to project-local `.worktrees/` (priority 2) → `$HOME/.config/superpowers/worktrees/<project>/` (priority 3) |
| Read by | `scripts/lib/common.sh` (`bsp_pick_worktree_dir`) |
| Validation | If set, MUST start with `/`. Relative input → `bsp_die "BOARD_SP_WORKTREE_DIR must be absolute, got: ..." 30` (exit `30`). |

When set, this is the **highest-priority** worktree-parent
directory — see
[`07-path-conventions.md`](./07-path-conventions.md) "Worktree
path resolution" for the full priority list. Intended for advanced
setups: single-machine multi-checkout, storage-tiering, CI runners
where `$HOME` is ephemeral.

#### Cited rationale

- ADR-0003 — "Path resolution priority" (priority-1 entry).
- `scripts/lib/common.sh` `bsp_pick_worktree_dir` — implementation.
- [`07-path-conventions.md`](./07-path-conventions.md) "Worktree
  path resolution" — canonical contract pin.
- `AGENTS.md` "Override via `$BOARD_SP_WORKTREE_DIR`" — protocol
  invariant surfaced.

---

### `BOARD_SP_SESSION_SLUG`

| Property | Value |
|----------|-------|
| Format | Free-form string. Used inline in commit message + claim-marker `session:` field. |
| Default | unset → `s-$(date +%s)-$$` (auto-generated; epoch seconds + PID) |
| Read by | `scripts/claim-card.sh` (claim-commit message + marker `session:` field) |
| Validation | None — string is used as-is. |

Identifies the Consumer session that produced a given claim — used
by the architect during triage to disambiguate multiple claim
attempts on the same card (e.g., when a Mode-2 Consumer's parent
respawns it after termination). The auto-generated default
(`s-<epoch>-<pid>`) is sufficient for v1; an architect-provided
slug overrides for cases where a meaningful identifier
(e.g., `s-overnight-batch-2026-05-01`) aids post-hoc analysis.

The `session:` field on the ClaimMarker is per-card, per-claim —
see [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md)
"ClaimMarker" for the marker schema.

#### Cited rationale

- `scripts/claim-card.sh` line 217 — implementation.
- [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md)
  "ClaimMarker" — `session:` field consumer.
- ADR-0002 (atomic claim — the marker is the lock-payload; the
  session slug is its provenance).

---

### `BOARD_SP_DEBUG`

| Property | Value |
|----------|-------|
| Format | `1` to enable; any other value (or unset) to disable |
| Default | unset → disabled |
| Read by | `scripts/lib/common.sh` (every script that sources it) |
| Effect | Sets `set -x` (xtrace) + `PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '` for the rest of the sourcing script |

Diagnostic-only. Enables verbose shell tracing across every
`scripts/*.sh` that sources `common.sh` — that is, every script
**except** `check-deps.sh` (deliberately self-contained per
[`01-script-contracts.md`](./01-script-contracts.md) "Cross-script
conventions"). Note: enabling this on `claim-card.sh` will dump
the worktree absolute path + claim-branch name to stderr — fine
for local debugging, but DO NOT capture this output into any
remote artifact (PR body, audit log, GitHub comment) or the
`worktree:` info-leak guard from
[`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md)
is defeated.

#### Cited rationale

- `scripts/lib/common.sh` lines 21, 31–34 — implementation.
- [`01-script-contracts.md`](./01-script-contracts.md) "Debug
  toggle" — caller-facing reference.
- ADR-0003 — `worktree:` info-leak guard rationale (the reason the
  `BOARD_SP_DEBUG` output should not be captured into remote
  artifacts).

---

### `BOARD_SP_AUDIT_*` (reserved namespace; no v1 consumer)

| Property | Value |
|----------|-------|
| Format | Reserved — no member of this namespace is read by v1 code. |
| Default | n/a (no consumer at v1) |
| Read by | none at v1 |
| Status | **TBD** — namespace reserved per ADR-0006 §5 BYO-RDBMS. The first concrete member, `BOARD_SP_AUDIT_DB_URL`, is finalized in [`03-config-schemas.md`](./03-config-schemas.md) "`~/.board-superpowers/credentials.yml` → Resolution priority". |

Per ADR-0006 §5, audit-DB credentials resolve via two mechanisms:

1. `BOARD_SP_AUDIT_DB_URL` env var (highest precedence, when consumed)
2. `~/.board-superpowers/credentials.yml:audit_db_url`

Neither is read by current scripts because the audit-write code path
itself is not implemented at v1 — the schema is pinned in
[`06-audit-log-schema.md`](./06-audit-log-schema.md) and the
credential resolution is pinned in
[`03-config-schemas.md`](./03-config-schemas.md), but the writer
component is a future card. When that card lands, it MUST
read `BOARD_SP_AUDIT_DB_URL` first per the resolution priority
contract; this entry is then promoted from "reserved" to "active"
in the same PR.

#### Cited rationale

- ADR-0006 §5 (BYO RDBMS — credential mechanism).
- [`03-config-schemas.md`](./03-config-schemas.md) "Resolution
  priority (env var vs file)" — canonical resolution-order contract.
- [`06-audit-log-schema.md`](./06-audit-log-schema.md) "Connection
  setup" — the consumer when the writer lands.

---

## Plugin-contract integration vars

Set by the platform runtime (Claude Code or Codex CLI) during
plugin / hook execution. board-superpowers reads them; the
plugin contract owns them. Renaming or removing any is upstream-
driven (a CC or Codex release-note event), not board-superpowers-
driven.

### `CLAUDE_PLUGIN_ROOT`

| Property | Value |
|----------|-------|
| Format | Absolute filesystem path |
| Default | Set by Claude Code at hook + skill execution time (e.g., `~/.claude/plugins/cache/<marketplace>/board-superpowers/<version>/`) |
| Read by | `hooks/session-start.sh`, every skill body that invokes `${CLAUDE_PLUGIN_ROOT}/scripts/...`, the `command` field in `hooks/hooks.json` |
| Validation | None at the plugin layer (CC owns the contract); `hooks/session-start.sh` defensively checks `[ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/scripts/check-deps.sh" ]` and silently no-ops if either fails |

The **only** reliable way to reference plugin-internal files
(scripts, references, agent definitions) from a hook or skill.
Hard-coding `~/.claude/plugins/board-superpowers/...` is forbidden
per `scripts/AGENTS.md` + `PLUGIN_DEVELOPMENT.md`
"Claude Code → `${CLAUDE_PLUGIN_ROOT}`".

**Codex CLI equivalent: none.** Codex scripts must derive their own
paths via `BASH_SOURCE` / relative-to-self. board-superpowers
keeps this abstraction in `scripts/lib/common.sh` so callers
don't need to know which platform they're on, but the variable
itself is Claude-Code-only. Per `PLUGIN_DEVELOPMENT.md` "TL;DR
surface mapping → Plugin install env var".

#### Cited rationale

- `PLUGIN_DEVELOPMENT.md` "Claude Code → `${CLAUDE_PLUGIN_ROOT}`"
  — canonical home for the upstream contract.
- `hooks/session-start.sh` line 21 + `hooks/hooks.json` line 8 —
  v1 consumers.
- `scripts/AGENTS.md` — `${CLAUDE_PLUGIN_ROOT}` is the only
  reliable way for scripts to reference the plugin's own files,
  surfaced as a protocol invariant.

---

### `CLAUDE_PROJECT_DIR`

| Property | Value |
|----------|-------|
| Format | Absolute filesystem path to the project root the session is running in |
| Default | Set by Claude Code; `check-deps.sh` falls back to `$PWD` if unset |
| Read by | `scripts/check-deps.sh` (line 31: `PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"`) |
| Validation | None — used directly to locate `<project>/CLAUDE.md` for routing-marker check + project-local skill candidates |

Used by `check-deps.sh` for two purposes:

1. Locate `<project>/CLAUDE.md` to check for the
   `board-superpowers:routing` marker pair.
2. Add `$PROJECT_DIR/.claude/skills/gstack` to the gstack-detection
   candidate list (per-project gstack install).

The `${CLAUDE_PROJECT_DIR:-$PWD}` fallback exists because the var
is unset under some test harnesses and direct shell invocations.
`hooks/session-start.sh` does NOT propagate this var — `check-deps.sh`
reads it directly from its own environment, which inherits from the
hook's environment, which inherits from CC.

**Codex CLI equivalent: none documented as such.** Codex's project
root concept is implicit (the cwd of the `codex` invocation). Per
`PLUGIN_DEVELOPMENT.md` (cwd is the only stable contract on the
Codex side at v1).

#### Cited rationale

- `scripts/check-deps.sh` line 31 — implementation.
- `hooks/session-start.sh` line 22 — explicit non-propagation note.
- `PLUGIN_DEVELOPMENT.md` "Claude Code → Hooks" — `CLAUDE_PROJECT_DIR`
  is part of the standard hook stdin payload + hook env.

---

### `CLAUDE_SESSION_ID`

| Property | Value |
|----------|-------|
| Format | Opaque string (Claude Code-assigned per session) |
| Default | Set by Claude Code at session start. Unset under non-CC shells. |
| Read by | `scripts/lib/common.sh` (`bsp_resolve_platform`, `bsp_resolve_session_id`, `bsp_render_creator_trace_block` — landed earlier in this PR); `scripts/audit-log-write.sh` line 117 (via `BSP_SESSION_ID` export); intake card-creation paths invoke the render helper at `gh issue create` time. |
| Validation | None — used as-is. |

The canonical "session id" surface for Claude Code consumers.
Provided to subprocesses via the shell environment (terminal env
inheritance), so any script sourced from a CC-spawned shell sees
it. Codex CLI's equivalent is `CODEX_THREAD_ID` — see entry below
for the term-bridge rationale.

#### Cited rationale

- `scripts/lib/common.sh` (`bsp_resolve_platform`, `bsp_resolve_session_id`) — implementation.
- `scripts/audit-log-write.sh` line 117 — primary caller (audit row writer).
- `skills/board-canon/references/card-body-schema.md` § creator-trace — marker block consumer (lands in same PR).
- Card #44 design — initial wiring.

---

### `CODEX_THREAD_ID`

| Property | Value |
|----------|-------|
| Format | Opaque string (Codex CLI-assigned per session; Codex's terminology is "thread id") |
| Default | Set by Codex CLI from `rust-v0.125.0` onward (PR [openai/codex#10096](https://github.com/openai/codex/pull/10096)). Unset on older Codex installs. |
| Read by | `scripts/lib/common.sh` (`bsp_resolve_platform`, `bsp_resolve_session_id` — fallback chain when `CLAUDE_SESSION_ID` is unset); downstream consumers same as `CLAUDE_SESSION_ID`. |
| Validation | None — used as-is. |

Term-bridge: Codex CLI calls this concept a "thread id"; the
project's `audit_log.session_id` column and the `BSP_SESSION_ID`
export use "session id". The helper `bsp_resolve_session_id()`
collapses the two terms into one canonical value, so consumers
see "session id" everywhere.

When the architect's Codex install is older than `rust-v0.125.0`
the var is unset; `bsp_resolve_session_id` then falls through to
the PWD-derived fallback. `Created-by` will be `unknown` in this
case — documented as expected fallback behavior, not an error.

#### Cited rationale

- [openai/codex#8923](https://github.com/openai/codex/issues/8923) — feature request that motivated the Codex-side env var.
- [openai/codex#10096](https://github.com/openai/codex/pull/10096) — PR introducing `CODEX_THREAD_ID` injection.
- `scripts/lib/common.sh` `bsp_resolve_platform` / `bsp_resolve_session_id` — fallback chain consumer.

---

## Variables board-superpowers does NOT read (anti-cargo-cult)

For the avoidance of doubt — these adjacent CC / Codex env vars
exist but are NOT read by board-superpowers v1. Listed so a
maintainer doesn't add a phantom entry while implementing a new
feature without checking the actual call sites.

| Variable | Owner | Why board-superpowers doesn't read it |
|----------|-------|---------------------------------------|
| `CLAUDE_SKILL_DIR` | CC | Skills self-locate via their own `SKILL.md` lookup; no script needs the dir. |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | CC | Mode-2 Consumer must NOT depend on `SendMessage` for correctness — see `MULTI_AGENT_DEVELOPMENT.md` "What this means for board-superpowers → 1. Mode-2 must close under C-PLUGIN-1". v1 codepath is gated by board state, not this flag. |
| `CLAUDE_CODE_FORK_SUBAGENT` | CC | Forked subagents are interactive-only and Claude-only; out of v1 Mode-2 scope. |
| `CODEX_*` (except `CODEX_THREAD_ID`, see entry above) | Codex | No other Codex-specific path is wired in v1; portability is via `BASH_SOURCE` self-derivation, not env vars. |

Adding any of these to a `Read by` table above requires also
updating the consumer code in the same PR. Per `AGENTS.md`
change-impact matrix.

---

## Cross-references

- [`01-script-contracts.md`](./01-script-contracts.md) — every
  script that reads one of these env vars enumerates them in its
  own "Inputs" section.
- [`02-hook-contracts.md`](./02-hook-contracts.md) —
  `hooks/session-start.sh` reads `CLAUDE_PLUGIN_ROOT` (and
  inherits `CLAUDE_PROJECT_DIR` to `check-deps.sh`).
- [`03-config-schemas.md`](./03-config-schemas.md) — env-var-vs-file
  resolution priority for `BOARD_SP_AUDIT_DB_URL`.
- [`06-audit-log-schema.md`](./06-audit-log-schema.md) — the audit
  writer that will consume `BOARD_SP_AUDIT_DB_URL` when implemented.
- [`07-path-conventions.md`](./07-path-conventions.md) —
  `BOARD_SP_WORKTREE_DIR`'s effect on the worktree resolution
  priority list.
- ADR-0003 (worktree path priority — `BOARD_SP_WORKTREE_DIR` is
  priority 1).
- ADR-0006 §5 (BYO RDBMS — `BOARD_SP_AUDIT_*` namespace
  reservation).
- ADR-0007 C-PLUGIN-2 (no daemon — no plugin-set env vars).
- `PLUGIN_DEVELOPMENT.md` "Claude Code → `${CLAUDE_PLUGIN_ROOT}`",
  "Codex CLI" sections — upstream-contract canonical home for the
  CC + Codex integration vars.
- `MULTI_AGENT_DEVELOPMENT.md` "What this means for
  board-superpowers" — context for the experimental-flag entries
  in the "does NOT read" table.
- `AGENTS.md` § "Working tree discipline" → "Default worktree
  path" + `scripts/AGENTS.md` — protocol invariants surfaced
  here.
