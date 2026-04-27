# 07 — Path conventions

> Pin every filesystem path board-superpowers reads or writes:
> worktree resolution priority, per-host (`~/.board-superpowers/`)
> layout, per-repo (`<repo>/.board-superpowers/`) layout, PlanBrief
> location, the session-log paths Producer consumes for heartbeat,
> and the exact `.gitignore` block `bootstrap-project.sh` writes.
>
> Rationale lives in the cited ADR / feature spec / `AGENTS.md`
> section. Shape lives here.

---

## Cross-path conventions

These rules apply to every path in this section:

- **Absolute paths only on stdout / config.** Scripts that emit a
  path on stdout (`claim-card.sh`'s `worktree=<absolute path>` line)
  emit it absolute. Tests assert on absolute. The one exception is
  the `.gitignore` entry, which is repo-relative by file format.
- **`$HOME` resolution.** macOS / Linux only at v1. Resolved via the
  caller's `HOME` env var with the standard shell fallback
  (`HOME="${HOME:-$(cd ~ && pwd)}"`). Windows is **out of v1 scope**
  per §1.5 cross-cutting principles + P3 (solo / small-team scale).
  WSL is treated as Linux.
- **No absolute local paths in remote artifacts.** Anything that
  pushes to a remote (claim branch markers, PR bodies, audit-log
  entries written from Consumer context) MUST NOT serialize a local
  filesystem path. The `worktree:` field omission on the
  ClaimMarker is the load-bearing example — see
  [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md)
  "Forbidden field — `worktree:`" for the contract and
  `tests/test-claim-card-worktree.sh` for the regression guard.
- **Plugin-internal paths via `${CLAUDE_PLUGIN_ROOT}`.** Scripts and
  hooks reference plugin-shipped files only via
  `${CLAUDE_PLUGIN_ROOT}/...`. Never hard-coded
  `~/.claude/plugins/...`. Per
  [`08-environment-variables.md`](./08-environment-variables.md) +
  `PLUGIN_DEVELOPMENT.md` "Claude Code → `${CLAUDE_PLUGIN_ROOT}`".
- **Permissions.** `~/.board-superpowers/` is mode `0700`;
  `~/.board-superpowers/credentials.yml` is mode `0600`. Per
  [`03-config-schemas.md`](./03-config-schemas.md) "Cross-config
  conventions". `<repo>/.board-superpowers/` inherits the repo's
  umask.

---

## Worktree path resolution

Three-priority list for `<WORKTREE_DIR>` (the **parent** directory
under which a per-claim worktree lives). Pinned by ADR-0003 and
implemented in `scripts/lib/common.sh` (`bsp_pick_worktree_dir`).

| Priority | Source | Condition | Path |
|----------|--------|-----------|------|
| 1 | `$BOARD_SP_WORKTREE_DIR` env var | set; MUST be absolute (rejected with exit `30` if relative) | `$BOARD_SP_WORKTREE_DIR` |
| 2 | Project-local `.worktrees/` | `<primary>/.worktrees/` exists AND `git check-ignore -q .worktrees` returns 0 | `<primary>/.worktrees` |
| 3 | Global default | always — fall-through | `$HOME/.config/superpowers/worktrees/<project-name>` |

Where:

- `<primary>` is the primary working tree's root (`git rev-parse
  --git-common-dir`'s parent — works regardless of which worktree
  the caller is invoked from).
- `<project-name>` is `basename "$<primary>"`.

### The resolved worktree path

Once `<WORKTREE_DIR>` is picked, the per-claim worktree itself
resolves to:

```
<WORKTREE_DIR>/<BRANCH>
```

Where `<BRANCH>` is the claim branch name `claim/<N>-<slug>` (per
[`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md)
"Claim branch naming"). Example, using priority 3:

```
$HOME/.config/superpowers/worktrees/board-superpowers/claim/15-fix-claim-card-force-add
```

This combined path is what `claim-card.sh` emits as the
`worktree=<absolute path>` stdout line — part of the script's
two-line public contract per
[`01-script-contracts.md`](./01-script-contracts.md) "`scripts/claim-card.sh`".

### Priority-2 gitignore-or-fallthrough rationale

Priority 2 deliberately gates on `.worktrees/` being **both
present AND gitignored**. The "AND gitignored" half exists because
an un-ignored `.worktrees/` would silently pollute `git status`
inside the primary working tree the moment a claim is created —
defeating the isolation property ADR-0003 buys. When `.worktrees/`
exists but is **not** gitignored, `claim-card.sh` logs a warning
to stderr and falls through to priority 3 rather than risk the
footgun. Per ADR-0003 "Path resolution priority" + the inline
comment in `bsp_pick_worktree_dir`.

### Override discipline

`$BOARD_SP_WORKTREE_DIR` (priority 1) is documented in
[`08-environment-variables.md`](./08-environment-variables.md) and
intended for advanced setups (single-machine multi-checkout,
storage-tiering, CI runners). Setting it relative is a hard
error — rejected with exit `30` per
[`01-script-contracts.md`](./01-script-contracts.md) exit-code
table.

### Cited rationale

- ADR-0003 — "Path resolution priority" (the canonical 3-priority
  list landing here as a contract).
- `scripts/lib/common.sh` — `bsp_pick_worktree_dir` is the
  canonical implementation of the 3-priority resolution.
- `AGENTS.md` "Worktree default path" — the same priority list
  surfaced in the developer guide; it points here.
- I-7 (one-card-one-worktree).
- `tests/test-claim-card-worktree.sh` — happy path + concurrent +
  already-claimed + worktree info-leak guard.
- [`08-environment-variables.md`](./08-environment-variables.md) —
  `BOARD_SP_WORKTREE_DIR` formal definition.

---

## Per-host layout — `~/.board-superpowers/`

Owned by the **HostBootstrap aggregate** (0003 § 3.3.5), the
**RepoBootstrap aggregate** (0003 § 3.3.6) at the per-repo state
sub-directory, plus the **AuditTrail aggregate** at the credential
layer (0003 § 3.3.8). Mode `0700`. Lives outside any repo by
design — none of these files are tracked in git (per I-13).

| Path | Tracked in git? | Mode | Owner | Purpose |
|------|-----------------|------|-------|---------|
| `~/.board-superpowers/` | n/a | `0700` | HostBootstrap | Per-host plugin state root |
| `~/.board-superpowers/manifest.yml` | no | inherits umask (typically `0644`) | HostBootstrap | Plugin-managed `HostManifest` (per [`03-config-schemas.md`](./03-config-schemas.md)) |
| `~/.board-superpowers/overrides.yml` | no | inherits umask | RepoConfig (user-layer) | User-level autonomy overrides (per [`03-config-schemas.md`](./03-config-schemas.md)) |
| `~/.board-superpowers/credentials.yml` | no | **`0600` strict** | AuditTrail | Audit-DB connection string (per [`03-config-schemas.md`](./03-config-schemas.md) + ADR-0006 §5) |
| `~/.board-superpowers/repos/` | n/a | inherits `0700` | RepoBootstrap | Container for every per-`(host, repo)` directory this host has bootstrapped |
| `~/.board-superpowers/repos/<normalized-repo-path>/` | n/a | inherits | RepoBootstrap | One sub-directory per repo bootstrapped on this host; name is the repo's absolute path with leading `/` stripped and remaining `/` replaced by `-`. Houses the three per-`(host, repo)` siblings below |
| `~/.board-superpowers/repos/<normalized-repo-path>/state.yml` | no | inherits | RepoBootstrap | Plugin-managed `RepoState` for this (host, repo) pair (per [`03-config-schemas.md`](./03-config-schemas.md)) |
| `~/.board-superpowers/repos/<normalized-repo-path>/audit-local.jsonl` | no | inherits | AuditTrail (degraded mode) | Per-`(host, repo)` jsonl trace written when audit DB is unavailable. **Legacy v0.1.0-minimum** wrote this at `~/.board-superpowers/<host>/<repo>/audit-local.jsonl`; Card 1's plumbing migrates the legacy path into the canonical normalized location |
| `~/.board-superpowers/repos/<normalized-repo-path>/audit.db` | no | inherits | AuditTrail (SQLite scheme) | **Optional.** Default SQLite database path suggested by `bootstrap-project.sh` step 2e when the architect picks `sqlite://` / `sqlite3://` (per ADR-0009). Absent when BYO scheme is Postgres / MySQL or audit DB is not configured |

### Path-normalization rule for the per-repo sub-directory

Given a repo's absolute path on the host, the canonical
sub-directory name is computed as:

1. Strip the leading `/`.
2. Replace every remaining `/` with `-`.

Examples:

| Repo absolute path | Sub-directory name |
|--------------------|---------------------|
| `/Users/panqiwei/my-project-repo` | `Users-panqiwei-my-project-repo` |
| `/Users/panqiwei/Dev/repos/nemori-ai/board-superpowers` | `Users-panqiwei-Dev-repos-nemori-ai-board-superpowers` |
| `/home/alice/work/api-server` | `home-alice-work-api-server` |

This is the canonical name `bootstrap-project.sh` writes and every
session's preflight reads. The mapping is one-way (we never decode
back to the original path); collisions across distinct paths sharing
the same normalized form are not addressed at v1 — out of scope per
P3 (solo / small-team scale). Note this scheme deliberately differs
from Claude Code's leading-`-` form (`-Users-panqiwei-...`); the
absence of the leading dash makes the directory listing read more
naturally with no semantic loss.

### Per-`(host, repo)` directory contents — three siblings

Each `~/.board-superpowers/repos/<normalized-repo-path>/` directory
houses up to three sibling files, one per concern, all owned by
distinct aggregates but co-located so a single `(host, repo)` pair
has exactly one canonical filesystem footprint:

| Sibling | Always present? | Owner | Lifecycle |
|---------|-----------------|-------|-----------|
| `state.yml` | Yes (after F-B2) | RepoBootstrap | Created at F-B2 first run; updated by F-B4 on version transitions; schema-versioned per I-12 |
| `audit-local.jsonl` | Yes during R-class degradation; absent once a BYO audit DB is configured AND reachable | AuditTrail (degraded mode) | Append-only jsonl trace written when `audit_db_url` is unset OR the configured DB is unreachable. **Legacy v0.1.0-minimum location** was `~/.board-superpowers/<host>/<repo>/audit-local.jsonl`; Card 1's plumbing migrates that path forward into the canonical normalized location |
| `audit.db` | Only when BYO scheme is `sqlite://` / `sqlite3://` AND the architect accepted the default path suggestion | AuditTrail (SQLite scheme) | Created on the first audit write after F-B2 step 2e selects SQLite; lives for the project's lifetime (no rollover); WAL mode enabled on first connection |

**One normalized dir per `(host, repo)` pair.** The directory name
is fully determined by the host's view of the repo's absolute path
(per the normalization rule above); no two distinct
`(host, repo)` pairs share a directory under any architect's `$HOME`.
The three siblings stay in lockstep — when the architect runs the
deferred `bootstrap-rollback.sh`, every sibling under this directory
gets cleaned up symmetrically.

The `audit.db` sibling is **forbidden inside the project tree**
(e.g., `<repo>/.board-superpowers/audit.db`). Per ADR-0009 the
default suggestion deliberately steers the architect to this
host-local location; if they override to a different host-local
path under `~/.board-superpowers/` that is acceptable, but a
project-tree location is rejected.

### Why `~/.board-superpowers/` and not `~/.config/board-superpowers/`

ADR-0003 already places the global-default worktree dir under
`~/.config/superpowers/worktrees/...`. Plugin state (manifest +
overrides + credentials) lives under `~/.board-superpowers/` to
keep config files deliberately distinct from the working-tree
storage that may be `rm -rf`'d to reclaim disk. The two are owned
by different aggregates and have different lifecycles; co-locating
them would confuse the cleanup story.

### Forward-extension placeholder

Future plugin-managed per-host files (e.g., a session-cache index
for Producer's preflight piggyback) land under
`~/.board-superpowers/` alongside the v1 set. Mode `0700` on the
parent dir guards anything new by default.

### Cited rationale

- 0003 § 3.3.5 HostBootstrap aggregate — entity-level home for
  `manifest.yml`.
- 0003 § 3.3.7 RepoConfig aggregate — `overrides.yml` user layer.
- 0003 § 3.3.8 AuditTrail aggregate — `credentials.yml` location +
  permission rules.
- ADR-0006 §5 (BYO RDBMS — credential-file location finalization).
- ADR-0009 — `audit.db` sibling location finalization for the
  SQLite scheme; default path suggestion under
  `~/.board-superpowers/repos/<normalized-repo-path>/audit.db`.
- I-13 (state files in git, machine-state files not).
- [`03-config-schemas.md`](./03-config-schemas.md) — schemas for
  every file in this table.

---

## Per-repo layout — `<repo>/.board-superpowers/`

Owned by the **RepoConfig aggregate** (0003 § 3.3.7) plus the
**ConsumerLogical aggregate** at the claim-marker layer (0003
§ 3.3.3). Lives inside the repo; mode inherits the repo's umask.
The split between tracked and untracked is load-bearing:
`config.yml` holds the **team-shared** subset of project config
and is tracked; `config.local.yml` holds the **per-user**
subset (host-/architect-specific overrides like `wip_limit`)
and is gitignored via the project-wide `*.local.*` pattern; the
per-session `claims/` subdirectory is gitignored locally — but
individual claim markers are force-added onto their own claim
branch (per ADR-0002 + I-13).

Note: per-repo plugin state (`state.yml`) does **not** live here.
It lives at `~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
(per "Per-host layout" above) so collaborators on the same git
remote do not silently overwrite each other's host-local bootstrap
state.

| Path | Tracked in git? | Owner | Purpose |
|------|-----------------|-------|---------|
| `<repo>/.board-superpowers/` | yes (directory) | RepoConfig | Per-repo plugin config root |
| `<repo>/.board-superpowers/config.yml` | **yes** | RepoConfig | User-editable team-shared project config (per [`03-config-schemas.md`](./03-config-schemas.md) § "config.yml") |
| `<repo>/.board-superpowers/config.local.yml` | **no** (gitignored via `*.local.*` pattern) | RepoConfig (per-user layer) | Per-user override of team-shared config — `wip_limit`, `autonomy_overrides`, etc. (per [`03-config-schemas.md`](./03-config-schemas.md) § "config.local.yml") |
| `<repo>/.board-superpowers/claims/` | **no** (gitignored locally) | ConsumerLogical | Per-session claim markers; force-committed to claim branch only |
| `<repo>/.board-superpowers/claims/<N>.claim` | gitignored locally; **force-added on the claim branch** | ConsumerLogical | One marker per claimed card; YAML payload per [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md) |

### Claim marker — locally gitignored, branch-committed

The contract is deliberately split:

- On `main` (and any branch other than `claim/<N>-<slug>`), the
  marker file MUST NOT appear — `.gitignore` blocks it.
- On the claim branch `claim/<N>-<slug>`, the marker MUST appear
  as a committed file. `claim-card.sh` does the `git add -f` to
  bypass the local `.gitignore`, then commits; that commit + push
  IS the atomic lock per ADR-0002.

The marker's existence on `origin/claim/<N>-<slug>` is the
proof-of-claim observable to other Consumer sessions (and to
Manager during triage). Per
[`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md)
"ClaimMarker" + the inline comment in `claim-card.sh` step 5.

### Tracked-vs-untracked rationale

`config.yml` is tracked because a collaborator joining the repo
MUST see it in their clone — without `config.yml` the routing
block has no project to point at. It carries only the
**team-shared** subset of project config (today: `project`;
future: `base_branch`, `default_execution_skill`). Per I-13 +
0003 § 3.3.7.

`config.local.yml` is **not** tracked because it carries the
**per-user** subset (today: `wip_limit`; future:
`autonomy_overrides`). These fields are personal-capacity or
personal-risk-tolerance choices, not team-coordination decisions
— Alice's parallel-session capacity has no contractual claim on
Bob's. Tracking `wip_limit` would silently force one architect's
preference onto every collaborator's clone. The `*.local.*`
gitignore pattern is project-wide, generalizing the convention
beyond just `config.local.yml`: any future per-user file in any
directory that follows `<name>.local.<ext>` naming is automatically
gitignored. Per I-13 + 0003 § 3.3.7 (per-user layer).

`state.yml` is **not** here at all — it lives at
`~/.board-superpowers/repos/<normalized>/state.yml`, host-local.
Each architect's host independently runs F-B2 once per repo and
maintains its own `state.yml`; nothing crosses git. This eliminates
the "plugin silently overwrites a collaborator's hand-edit on the
next push" round-trip. Per I-13 (current form) + 0003 § 3.3.6.

`claims/` is gitignored locally because the claim markers are
per-session ephemera that must NEVER appear on `main` — they are
proof-of-claim only on the claim branch. Per
[`03-config-schemas.md`](./03-config-schemas.md) + I-13.

### Cited rationale

- 0003 § 3.3.6 RepoBootstrap aggregate — `state.yml` home (now
  host-local at `~/.board-superpowers/repos/<normalized>/`).
- 0003 § 3.3.7 RepoConfig aggregate — `config.yml` home.
- I-13 (state.yml host-local, machine-state files not in git).
- ADR-0002 (atomic claim via remote branch push — the marker file
  is the lock-payload).
- `AGENTS.md` "`.board-superpowers/claims/` is gitignored" —
  protocol invariant absorbed here.
- `tests/test-claim-card.sh` — `.gitignore` invariant +
  force-add regression guard.

---

## PlanBrief location

```
<repo>/docs/board-superpowers/plans/card-<N>.md
```

| Property | Value |
|----------|-------|
| Tracked in git? | **No** (gitignored) |
| Owner | ConsumerLogical (1:1 with the claimed card) |
| Lifecycle | Created by Consumer Step 3 (per `consuming-card/SKILL.md`); deleted on success path; preserved on failure path (parallels worktree per ADR-0003) |
| Source of truth? | **No** — the card body on GitHub is the source of truth; the PlanBrief is scratch for `superpowers:subagent-driven-development` |

The PlanBrief is **not** a contract surface in the cross-component
sense — its body shape is opaque to anyone outside the Consumer
session that owns it. The path is pinned here because Producer's
triage routine grep'd-for it as a "is this card actually in
progress" signal at one point; that signal is now subsumed by the
ClaimMarker on the claim branch, but the path stays deterministic
so a human takeover can `cd` into the worktree and immediately see
what scratch the Consumer was working from.

### Cited rationale

- `AGENTS.md` "Plan briefs live at `docs/board-superpowers/plans/card-<N>.md`
  and are gitignored" — the canonical pin.
- 0003 § 3.3.3 ConsumerLogical aggregate — PlanBrief is a member
  entity (relationship `ConsumerLogical ||--|| PlanBrief : "1:1
  scratch"` per 0003 § 5).
- 0002 §1.4.3 F-C3 — Consumer Step 3 writes the PlanBrief.
- 0002 §1.4.14 F-C14 — success vs failure path treatment (parallels
  worktree per ADR-0003).

---

## Session log paths Producer consumes

Producer's **preflight piggyback** (per ADR-0007 + ADR-0006 row 14)
reads on-disk session transcripts so it can answer "what did the
Consumer actually do since I last looked" without trusting Consumer
self-report. Both Claude Code and Codex CLI persist transcripts to
deterministic paths; Producer's lookup uses platform detection to
pick the right one.

### Claude Code

```
~/.claude/projects/<project-dir>/<sessionId>/subagents/agent-<agentId>.jsonl
```

| Component | Source |
|-----------|--------|
| `<project-dir>` | URL-encoded form of the absolute project path the session ran in |
| `<sessionId>` | The CC session id (UUID) — captured from `system/init` event in the transcript stream |
| `<agentId>` | Subagent id; only present when the parent spawned the Consumer via the `Agent` tool (Mode-2 Consumer) |

For a Mode-1 Consumer (no parent — architect dispatched directly),
the transcript is the **top-level session file** at
`~/.claude/projects/<project-dir>/<sessionId>.jsonl` (no
`subagents/agent-<agentId>.jsonl` suffix).

Retention follows the `cleanupPeriodDays` setting (default 30 days
per `MULTI_AGENT_DEVELOPMENT.md`). Producer's preflight MUST
tolerate a missing transcript file — older Consumer runs may have
been pruned.

### Codex CLI

```
~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
```

| Component | Source |
|-----------|--------|
| `YYYY/MM/DD` | UTC date of the session start, by file system convention |
| `rollout-*.jsonl` | Glob; Codex assigns a UUID v7 session id embedded inside the JSONL — renaming the file does not change the id |

Per `MULTI_AGENT_DEVELOPMENT.md` "Codex CLI → Sessions and `codex
exec`": Codex does not separate parent vs child transcripts the way
CC does; every session — including subagent spawns via
`spawn_agents_on_csv` — produces its own `rollout-*.jsonl`.

### Cross-platform note

Producer detects which platform it's running on via the presence of
`${CLAUDE_PLUGIN_ROOT}` (CC) vs reachability of `~/.codex/`
(Codex). The transcript path lookup is gated by that detection;
Producer never assumes both formats are simultaneously present.

This pair of paths is **not** a contract surface board-superpowers
owns — both are upstream platform contracts documented in
`MULTI_AGENT_DEVELOPMENT.md` and surface here only because Producer
reads them. Format breaks land in `MULTI_AGENT_DEVELOPMENT.md`'s
"Honest gaps" section first; Producer code follows.

### Cited rationale

- `MULTI_AGENT_DEVELOPMENT.md` "Session-id reachback" + "Sessions
  and `codex exec`" — canonical home for the upstream-contract
  shape; this section mirrors and links.
- ADR-0007 C-PLUGIN-2 (no daemon — preflight piggyback is the
  no-daemon-friendly alternative to a state-tracking service).
- ADR-0006 §3 row 14 (Auto-trigger retro / weekly report; the
  preflight-piggyback consumer of these paths).

---

## The `.gitignore` block

`scripts/bootstrap-project.sh` writes (or appends to) `<repo>/.gitignore`
during F-B2 setup. The exact form, verbatim from the script:

```gitignore
# Per-user local override files — convention: <name>.local.<ext>
# Any file matching this pattern is gitignored. Use for per-user
# config / state that shadows team-shared tracked files (e.g.,
# config.local.yml shadows config.yml's per-user fields).
*.local.*

# board-superpowers local state (claim markers are per-session)
.board-superpowers/claims/
```

Two distinct entries land:

1. The project-wide `*.local.*` pattern — any file whose name
   matches `<name>.local.<ext>` is gitignored regardless of
   directory. This is the canonical per-user override
   convention (see § "Per-repo layout" Tracked-vs-untracked
   rationale).
2. The board-superpowers-specific `.board-superpowers/claims/`
   rule — claim markers are per-session and must never appear
   on `main`.

### Write semantics

| Scenario | Behavior |
|----------|----------|
| `.gitignore` does not exist | Created with both entries above as its initial content |
| `.gitignore` exists, both entries already present (exact line match for each) | Idempotent no-op; logs `✓ already present` |
| `.gitignore` exists, one or both entries missing | Ensures trailing newline on the existing file, prepends one blank line for visual separation, then appends only the missing entries with their respective comment headers |

The "exact match" check uses `grep -Fxq` — a fixed-string,
whole-line, quiet match. Trailing-slash differences
(`.board-superpowers/claims` without trailing `/`) are NOT
considered duplicates and would result in a second appended
entry. Same logic for `*.local.*` — any whitespace or trailing
characters break the dedup. Per the inline implementation in
`bootstrap-project.sh`.

### Future-extension placeholder

If F-B2 grows additional gitignore needs (e.g., the PlanBrief tree
at `docs/board-superpowers/plans/`), they appear under the same
comment header in the same block. Single-block-per-tool keeps the
diff readable and the merge story trivial. The PlanBrief gitignore
entry is currently **TBD** in the script — as of v1, PlanBrief
gitignoring is documented in `AGENTS.md` and presumed to be the
architect's responsibility (or rolled into a follow-up F-B2 card).
Forward-pointer: when implemented, the additional line lives
inside the same `# board-superpowers local state ...` block.

### Cited rationale

- `scripts/bootstrap-project.sh` lines 211–237 — canonical
  implementation.
- `AGENTS.md` "`.board-superpowers/claims/` is gitignored but
  individual claim markers are force-committed to their claim
  branch (never to main)" — protocol invariant.
- I-13 (state files in git, machine-state files not).
- §1.5.2 F-B2 (per-repo bootstrap — the script's spec).

---

## Cross-platform notes

| Concern | macOS / Linux | Windows |
|---------|---------------|---------|
| `$HOME` | Native | **Out of v1 scope.** WSL is treated as Linux. |
| Path separator | `/` | n/a (out of scope) |
| Permission bits (`0700`, `0600`) | Native via `chmod`; `umask 022` set by `lib/common.sh` | n/a (out of scope) |
| Symlinks (in worktree paths) | Resolved via `cd` at script time | n/a (out of scope) |
| Case sensitivity | Linux: case-sensitive; macOS APFS: case-insensitive by default | n/a |

The case-insensitive macOS-default surface matters in exactly one
place: a project named `Foo` and a project named `foo` would share
a worktree dir at priority 3 (`$HOME/.config/superpowers/worktrees/foo/`
vs `$HOME/.config/superpowers/worktrees/Foo/`). v1 does not address
this — the workaround is to set `$BOARD_SP_WORKTREE_DIR` per
project. Out-of-scope per P3.

---

## Cross-references

- [`01-script-contracts.md`](./01-script-contracts.md) — every
  script that writes one of these paths (`bootstrap-project.sh`
  for `.gitignore` + `<repo>/.board-superpowers/`; `claim-card.sh`
  for the worktree + claim marker).
- [`02-hook-contracts.md`](./02-hook-contracts.md) — `hooks/session-start.sh`
  reads `${CLAUDE_PLUGIN_ROOT}` to find `check-deps.sh`; that env
  var is the only path-resolution contract the hook depends on.
- [`03-config-schemas.md`](./03-config-schemas.md) — schemas for
  every file in the per-host and per-repo layouts above.
- [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md) —
  ClaimMarker field schema + `worktree:` field-omission contract;
  claim-branch naming convention.
- [`06-audit-log-schema.md`](./06-audit-log-schema.md) — the audit
  log is the **one** place where a `worktree:` absolute path IS
  recorded (write context only; never pushed to a remote).
- [`08-environment-variables.md`](./08-environment-variables.md) —
  `BOARD_SP_WORKTREE_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PROJECT_DIR`
  formal definitions.
- ADR-0002 (atomic claim — claim marker is the lock payload).
- ADR-0003 (worktree path priority — canonical home).
- ADR-0006 §5 (BYO RDBMS — `credentials.yml` location).
- ADR-0009 (allow SQLite as a BYO audit DB scheme — `audit.db`
  sibling default path).
- ADR-0007 C-PLUGIN-2 (no daemon — session-log paths are read,
  never written).
- `MULTI_AGENT_DEVELOPMENT.md` — session-log path canonical home
  (CC + Codex variants).
- `AGENTS.md` "Worktree default path", "`.board-superpowers/`",
  "Plan briefs live at...", "Never commit absolute local paths to
  a public branch" — protocol invariants surfaced here.
