# 01 — Script contracts

> Every script under `scripts/` is a public contract surface. Hooks,
> SKILLs (via `${CLAUDE_PLUGIN_ROOT}`), tests, and user automations
> all call them. This file pins each script's input vector, output
> shape, exit-code map, and side effects.
>
> Rationale lives in the cited ADR / feature spec. Shape lives here.
>
> **Kanban Protocol layering (per ADR-0012).** The board-mutating
> scripts here (`bootstrap-project.sh`, `claim-card.sh`,
> `transition-card.sh`, `create-card.sh`) are the v1
> **GitHubProjectAdapter projection's** Form A (bash CLI)
> implementation — they call the GitHub-specific `gh` CLI directly.
> Their contracts (stdin / stdout / exit codes / `gh` side effects)
> are authoritative for v1.0 and any future repo configured with
> `kanban.backend: github-project-v2`. Future backend projections
> (Linear, Jira) ship their own Form A scripts (or skip Form A in
> favor of Form B / Form C); the protocol-level semantics live in
> [`00-kanban-protocol.md`](./00-kanban-protocol.md).

---

## Cross-script conventions

These rules apply to every script under `scripts/`:

- **Strict mode.** Each script begins with `set -euo pipefail` and
  sources `scripts/lib/common.sh` immediately after — except
  `check-deps.sh`, which is **deliberately self-contained** (no
  source) so a broken lib cannot derail dep detection. Per
  `scripts/AGENTS.md` "Self-contained scripts".
- **Header comment is the help text.** `bsp_show_help` (from
  `lib/common.sh`) prints the leading `# ...` block as `--help`
  output. Every script supports `-h` / `--help`.
- **Universal exit codes** (every script honors these):

  | Code | Meaning |
  |------|---------|
  | `0`  | Success |
  | `1`  | Operational failure (caller surfaces; do not blindly retry) |
  | `2`  | Bad arguments |
  | `3`  | A runtime command (`gh` / `python3`) is unavailable, or `gh` is unauthenticated |

  **Per-script extensions** — additions to the universal map for a
  single script:

  - `check-deps.sh` reuses `2` as the *missing-dep* signal (its only
    "bad input" semantically is "deps missing"). No new code.
  - `claim-card.sh` adds three codes pinned by ADR-0002:
    `10` race-loss (caller MUST stop, never retry),
    `20` git / network error,
    `30` bad args or missing `git` dependency. Note: `30` overlaps
    semantically with the universal `2` + `3`; the split is kept for
    caller-API stability (existing tests + `consuming-card` Step 2
    branch on `30` distinctly). See ADR-0002 for the rationale; do
    not consolidate without an ADR-0002 supersession.

  New exit codes require updating every caller plus every branching
  skill. See `docs/architecture/AGENTS.md` change-impact matrix.

- **Strict input parsing.** Owner / number / repo arguments go
  through `bsp_parse_owner_number` or `bsp_parse_owner_repo` in
  `lib/common.sh` — exactly one slash, no leading or trailing
  slash, NUMBER must be a positive integer.
- **JSON parsing is `python3`.** Where a script reads `gh` JSON
  output it pipes to `python3`. Identifiers (issue numbers, repo
  full names, status names) are passed through environment
  variables, never string-interpolated into Python code (per
  `transition-card.sh` injection-hardening note H1/L3).
- **Plugin-root reference.** Scripts reference plugin-internal
  paths via `${CLAUDE_PLUGIN_ROOT}` only — never hard-code
  `~/.claude/plugins/...`. Per ADR-0007 / `PLUGIN_DEVELOPMENT.md`.
- **Debug toggle.** `BOARD_SP_DEBUG=1` enables `xtrace` (see
  `lib/common.sh`). Per `08-environment-variables.md`.

---

## `scripts/check-deps.sh`

Layer 1 of the three-layer alert strategy (per §1.5.0). Self-
contained: does NOT source `lib/common.sh`.

### Purpose

Detect that `superpowers` and `gstack` are reachable from the
current session, and that the current project's `CLAUDE.md` carries
the routing-block marker.

### Inputs

| Source | Variable | Default | Effect |
|--------|----------|---------|--------|
| Env | `CLAUDE_PROJECT_DIR` | `$PWD` | Project root for routing-marker check |
| Env | `HOME` | `$(cd ~ && pwd)` | Home dir for plugin / skill path resolution |
| Arg | `$1` | `human` | `--machine` toggles output shape |

No flag arg vector beyond optional `--machine` mode toggle.

### Stdout / stderr

| Mode | Output destination | Shape |
|------|--------------------|-------|
| `human` (default) | stdout (success line) or stderr (banner) | Human-readable banner if anything missing; one-line success ("✅ board-superpowers: …") if all OK |
| `--machine` | stdout, only when something is wrong | Three lines, exact key names: `MISSING=<csv>` `\n` `ROUTING_INJECTED=<yes\|no>` `\n` `PROJECT=<absolute path>` `\n`. Empty when all OK (callers test `-z`). |

**`--machine` keys are protocol** — `MISSING`, `ROUTING_INJECTED`,
`PROJECT`. Renaming any of them breaks `hooks/session-start.sh`'s
parser (per `docs/architecture/AGENTS.md` change-impact matrix).

### Exit codes

| Mode | Code | Meaning |
|------|------|---------|
| `human` | `0` | All deps present + routing OK (or no `CLAUDE.md`) |
| `human` | `2` | Missing dependency OR `CLAUDE.md` exists but no routing marker |
| `human` | `3` | Runtime command unavailable (e.g., `python3` not on PATH) |
| `--machine` | always `0` | Output channel signals state instead of exit code |

### Side effects

None. Read-only across `~/.claude/plugins/...`,
`~/.claude/skills/...`, `~/.codex/superpowers/...`, and the project
root's `CLAUDE.md` (if present).

### Cited rationale

- `0002-product-features-and-flows/05-bootstrap-surface.md` §1.5.0
  (the dep-check shared primitive).
- `scripts/AGENTS.md` "Self-contained scripts" +
  `docs/architecture/AGENTS.md` change-impact matrix entry for
  the `--machine` keys.
- ADR-0007 C-PLUGIN-2 (no daemon — preflight check is the
  no-daemon-friendly readiness probe).

### Forward-looking — experimental-flag preflight (Mode-2)

If a future Mode-2 path lands a `SendMessage`-dependent or agent-
teams-dependent optimization (per `MULTI_AGENT_DEVELOPMENT.md`
§ "Experimental flags are a runtime concern"), `check-deps.sh`
MUST add an `EXPERIMENTAL=<csv-of-required-env-flags-not-set>` key
to its `--machine` output (e.g.,
`EXPERIMENTAL=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`). Until Mode-2
ships such a path, no experimental-flag check fires and the key is
absent from `--machine` output. Forward-shape only; no v1 caller
depends on it.

---

## `scripts/bootstrap-project.sh`

Per-repo F-B2 driver (per §1.5.2). Sources `lib/common.sh`.

### Purpose

One-time per-repo setup: standard labels, Status-field validation,
`config.yml`, `.gitignore`. Per ADR-0001 substrate-commitment posture
the script does NOT create the GitHub Project — the architect creates
it via UI.

### Inputs

| Flag | Type | Required? | Default | Effect |
|------|------|-----------|---------|--------|
| `--project` | `OWNER/NUMBER` | required | — | Identifies the GitHub Project v2 |
| `--wip` | positive int | optional | `5` | Initial `wip_limit` written to `config.yml` |
| `-h` / `--help` | flag | optional | — | Print header comment |

Env: `gh` CLI must be authenticated (`gh auth status`) and have
`project` scope. `python3` must be on PATH.

### Stdout

Human-readable progress lines (each step prints `→` then a status):
1. Label creation summary (`created: N already existed: M failed: K`)
2. Status-field validation tick (`✓ Status field has all 6 required options`)
3. `config.yml` written tick
4. `.gitignore` updated tick
5. Multi-line "next steps" footer

Not parsed by any other script; safe to evolve.

### Exit codes

| Code | Meaning |
|------|---------|
| `0`  | All four steps succeeded |
| `1`  | Operational failure: a real label-creation failure (not "already exists"), `Status` field missing required options, project not accessible, file-write failure |
| `2`  | Bad arguments — missing `--project`, malformed `OWNER/NUMBER`, non-positive `--wip` |
| `3`  | `gh` / `python3` unavailable, or `gh` not authenticated |

### Side effects

| Surface | What |
|---------|------|
| GitHub | Creates 9 standard labels via `gh label create` (idempotent — "already exists" silently OK). See [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md) for the label set. |
| GitHub | Reads `gh project view` + `gh project field-list` to validate Status options. **Does not write to the project.** |
| Filesystem | `mkdir -p .board-superpowers/` then writes `.board-superpowers/config.yml` |
| Filesystem | Appends `.board-superpowers/claims/` to `.gitignore` (idempotent; with comment header) |

### Known implementation gaps vs §1.5.2 spec

The **contract** for `bootstrap-project.sh` IS the 5-sub-capability
spec in §1.5.2: labels, Status validation, `config.yml`, routing-
block injection (`CLAUDE.md` + `AGENTS.md`), `state.yml`, and BYO-
RDBMS audit-DB init. v1 ships only the first three from the script
directly; the last two currently happen via the
`using-board-superpowers` skill body during interactive bootstrap.

This is **implementation backlog, not a contract weakening** — the
canonical surface remains the §1.5.2 5-sub-capability spec. Test
gap and migration plan track in `0008-test-architecture.md` (stub)
and the F-B2 follow-up cards.

### Cited rationale

- §1.5.2 F-B2 (per-repo bootstrap).
- ADR-0001 (substrate commitment — Project v2 created by architect).
- ADR-0006 §5 (BYO-RDBMS sub-capability).

---

## `scripts/claim-card.sh`

Atomic Consumer claim primitive (per F-C1, ADR-0002, ADR-0003).
Sources `lib/common.sh`.

### Purpose

(a) Distributed lock via `git push --force-with-lease=<ref>:` on a
namespaced claim branch. (b) Filesystem isolation via a dedicated
git worktree. Both succeed atomically or both clean up on failure.

### Inputs

Positional, in order:

| Position | Name | Required? | Effect |
|----------|------|-----------|--------|
| `$1` | `<card-number>` | required | Positive integer GitHub Issue number |
| `$2` | `<short-slug>` | required | Free-form; sanitized via `bsp_sanitize_slug` (lowercased, `[^a-z0-9-]+` → `-`, collapsed, ≤ 40 chars) |
| `$3` | `[base-branch]` | optional | If absent, resolved from `origin/HEAD` then `main` then `master` |

Env (read; per [`08-environment-variables.md`](./08-environment-variables.md)):

| Var | Effect |
|-----|--------|
| `BOARD_SP_WORKTREE_DIR` | Highest-priority worktree-parent path; MUST be absolute |
| `BOARD_SP_SESSION_SLUG` | Optional Consumer session slug tag (claim commit + marker file). Defaults to `s-$(date +%s)-$$` |
| `HOME` | Used for the global-default worktree path |

### Stdout (success path — exactly two lines, in order)

```
branch=<claim branch name>
worktree=<absolute path to worktree>
```

Both lines are **structured contract**. `consuming-card/SKILL.md`
Step 2 parses both. Changing the shape (renaming a key, swapping
order, adding a third line, dropping a trailing newline) is a
breaking change requiring callers + tests + README to land in the
same PR.

### Stderr (failure paths)

| Exit | Stderr shape |
|------|--------------|
| `10` | Multi-line: `card #N already claimed` + `branch:` + `last author:` + `last commit:` |
| `10` (race-loss after push) | `card #N was just claimed by another session (race)` |
| `20` (git-push failure) | `<script>: error: git push failed; check auth / network` + indented `git output:` block |
| Any error via `bsp_die` | `<script>: error: <message>` |

### Exit codes

| Code | Meaning | Caller behavior |
|------|---------|-----------------|
| `0`  | Claim successful; stdout has `branch=` and `worktree=` lines | Proceed to Consumer Step 3 (`cd` into worktree, transition card) |
| `10` | Race lost — branch already exists on remote | **MUST stop**, never retry. Surface who won (last author / last commit) to the architect |
| `20` | Git or network error (including worktree setup) | Surface error; do not retry automatically |
| `30` | Bad arguments or missing dependency (`git`) | Fix invocation and re-run |

Exit codes are pinned by ADR-0002. Adding a new code requires an
ADR-0002 supersession + caller updates.

### Side effects (success path)

| Order | Effect |
|-------|--------|
| 1 | `git fetch origin` |
| 2 | (Idempotent reuse) Detect existing matching worktree + push if marker already in place |
| 3 | `mkdir -p` worktree-parent dir |
| 4 | `git worktree add <path> -b claim/<N>-<slug> origin/<base>` |
| 5 | Write `.board-superpowers/claims/<N>.claim` (YAML; see [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md)) |
| 6 | `git add -f` the marker (forces add despite `.gitignore`) |
| 7 | `git commit` with message `claim: card #<N> [<session-slug>]` + body |
| 8 | `git push --force-with-lease=refs/heads/<branch>: --set-upstream origin <branch>` — **the atomic lock step** |

On failure between steps 4 and 8, `bsp_cleanup_partial_claim` removes
the worktree and local branch; cleanup never masks the original error.

### Worktree path resolution

Three-priority list (per ADR-0003 + [`07-path-conventions.md`](./07-path-conventions.md)):

1. `$BOARD_SP_WORKTREE_DIR` if set (MUST be absolute; rejected with
   exit `30` if relative).
2. `<primary>/.worktrees/` if it exists AND is gitignored
   (`git check-ignore -q .worktrees`). If it exists but is NOT
   gitignored, log a warning and fall through.
3. `$HOME/.config/superpowers/worktrees/<project-name>/` (default).

Combined with branch name yields `<dir>/<BRANCH>` for the worktree
path on stdout.

### Cited rationale

- ADR-0002 (atomic claim via remote branch push) — exit-code pin.
- ADR-0003 (one worktree per Consumer) — path-priority pin + info-
  leak guard.
- §1.4.1 F-C1 (atomic claim primitive).
- I-7 (one-card-one-worktree).
- `tests/test-claim-card.sh` + `tests/test-claim-card-worktree.sh`
  (regression guards).

---

## `scripts/create-card.sh`

Standardized card creation (per F-09 / decomposing-into-milestones
Step 6). Sources `lib/common.sh`.

### Purpose

Create a GitHub Issue with the board-superpowers standard body and
add it to the configured GitHub Project, in one shot.

### Inputs

| Flag | Type | Required? | Effect |
|------|------|-----------|--------|
| `--title` | string | required | Issue title |
| `--body-file` | path | required | File with the card body (per [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md)) |
| `--project` | `OWNER/NUMBER` | required | Project to add the new item to |
| `--repo` | `OWNER/REPO` | optional | Repo to create the issue in (defaults to the current repo) |
| `--label L` | string, repeatable | optional | Label to apply (e.g. `--label type:feature --label size:S`) |

Env: `gh` CLI must be authenticated with `project` scope.

### Stdout

On success, exactly one line:

```
<issue-number>
```

A bare positive integer. Used by the calling skill to compose
follow-up commands (e.g., `transition-card.sh --issue $N …`).

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Issue created AND added to the project |
| `1` | Issue created but failed to add to project (manual `gh project item-add` instruction printed to stderr) |
| `2` | Bad arguments |
| `3` | `gh` unavailable |

The exit-1 partial-failure path is surfaced precisely because the
two operations cannot be atomic — fail loudly so the caller can
fix-forward via the printed `gh project item-add` command.

### Side effects

- `gh issue create` (writes one new GitHub Issue).
- `gh project item-add` (links it into the project).

### Cited rationale

- §1.6 decomposition surface.
- Per §1.5.2 the script intentionally does NOT pass `--project` to
  `gh issue create` (that flag expects project TITLE, not
  OWNER/NUMBER). Two-step is canonical.

---

## `scripts/transition-card.sh`

Move a card to a new Status column on a GitHub Project v2. Used by
both Manager and Consumer. Sources `lib/common.sh`.

### Purpose

Resolve the project + issue + Status-field option to backend IDs,
then issue `gh project item-edit --single-select-option-id` to
mutate the column.

### Inputs

| Flag | Type | Required? | Effect |
|------|------|-----------|--------|
| `--issue` | positive int | required | GitHub Issue number |
| `--project` | `OWNER/NUMBER` | required | Project hosting the card |
| `--to` | string | required | One of the six canonical Status names (case-insensitive, whitespace-trimmed) |
| `--repo` | `OWNER/REPO` | optional | Disambiguate when one project hosts items from multiple repos |

Status string MUST resolve to one of the six options pinned in
[`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md).
Mismatch → exit 1 with the available options listed on stderr.

### Stdout

On success, exactly one line:

```
moved issue #<N> to <Status>
```

Human-readable confirmation; not parsed structurally.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Status updated |
| `1` | Operational failure (project not found, issue not on project, Status option missing, GraphQL error) |
| `2` | Bad arguments |
| `3` | `gh` / `python3` unavailable |

### Side effects

GitHub Project v2 mutation: `gh project item-edit
--single-select-option-id <option-id>` on the resolved item.

### Security note

Identifiers (`ISSUE_NUM`, `REPO_FULL`, `TO_STATUS`) are passed to
the embedded `python3` filter via environment variables, never
string-interpolated into the script body. Original CVE-grade
injection vector (H1/L3) is closed.

### Cited rationale

- `board-canon/SKILL.md` state machine (the allowed transitions
  surfaced as the in-session SPOT; protocol-level semantics live in
  [`00-kanban-protocol.md`](./00-kanban-protocol.md)).
- ADR-0006 (every transition is an audit-logged action; rows 5/6/7
  governance).
- ADR-0012 — this script is part of the v1 GitHubProjectAdapter
  projection (Form A bash CLI).

---

## `scripts/lib/common.sh`

Shared library; not directly executable. Caller MUST `set -euo
pipefail` before sourcing. Per `scripts/AGENTS.md`.

### Exported functions

| Function | Signature | Purpose |
|----------|-----------|---------|
| `bsp_log` | `<msg>` | Stderr log with `<script-name>: <msg>` prefix |
| `bsp_die` | `<msg> [exit_code]` | Log + exit (default exit `1`) |
| `bsp_require_cmd` | `<cmd> [exit_code]` | Fail fast if a command is missing (default exit `3`) |
| `bsp_require_arg` | `<flag_name> <argc>` | Assert `$#` has a value after `<flag>` (used inside arg loops) |
| `bsp_parse_owner_number` | `<v> <flag>` | Strict OWNER/NUMBER parser; sets `BSP_OWNER`, `BSP_NUMBER` (exit `2` on malformed input) |
| `bsp_parse_owner_repo` | `<v> <flag>` | Strict OWNER/REPO parser; sets `BSP_REPO_OWNER`, `BSP_REPO_NAME` |
| `bsp_show_help` | — | Print the leading `# ...` block of `$0` as `--help` |
| `bsp_sanitize_slug` | `<s>` | Lowercase, replace `[^a-z0-9-]+` with `-`, collapse, strip ends, cap at 40 chars |

### Exported variables

| Variable | Source | Use |
|----------|--------|-----|
| `BSP_SCRIPT_NAME` | `basename "${BASH_SOURCE[<topmost>]}"` | Caller-visible script name (used in log / die prefixes) |
| `BSP_OWNER`, `BSP_NUMBER` | Set by `bsp_parse_owner_number` | OWNER/NUMBER components |
| `BSP_REPO_OWNER`, `BSP_REPO_NAME` | Set by `bsp_parse_owner_repo` | OWNER/REPO components |

### Side effects on source

- `umask 022` for any file the caller subsequently creates.
- If `BOARD_SP_DEBUG=1`, enables `set -x` and sets a verbose
  `PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '`.

### Contract

Function signatures are part of the public contract for any script
under `scripts/` that sources `common.sh`. Renaming a function or
changing its arg order requires updating every caller in the same
PR (per `docs/architecture/AGENTS.md` change-impact matrix row 3).

---

## Shell-style discipline

Per `scripts/AGENTS.md`:

- `shellcheck -x ./*.sh` from the `scripts/` directory before
  committing. SC1091 typically means wrong cwd, not a real bug.
- `shellcheck -x ./*.sh` in `tests/` too — tests are scripts.
- Second opinion on non-trivial shell logic: `gstack:/codex`.

---

## Cross-references

- [`00-kanban-protocol.md`](./00-kanban-protocol.md) — top-level
  Kanban Protocol; the board-mutating scripts above are the v1
  GitHubProjectAdapter projection's Form A bash CLI implementation.
- [`02-hook-contracts.md`](./02-hook-contracts.md) — `hooks/session-start.sh`
  consumes `check-deps.sh --machine` output; the key names in this
  doc must match.
- [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md) —
  pin for ClaimMarker fields written by `claim-card.sh`, label set
  written by `bootstrap-project.sh`, Status enum read by
  `transition-card.sh`.
- [`06-audit-log-schema.md`](./06-audit-log-schema.md) — every
  state-mutating script's behavior maps to one or more `action_id`
  rows; the AuditEntry payload sub-schema names which fields the
  script's invocation must record.
- [`07-path-conventions.md`](./07-path-conventions.md) — worktree
  path priority is the canonical pin; `claim-card.sh` is the
  implementation.
- [`08-environment-variables.md`](./08-environment-variables.md) —
  every `BOARD_SP_*` variable read by these scripts is enumerated
  there.
- ADR-0002 / ADR-0003 / ADR-0007 / ADR-0008 — rationale homes.
- `AGENTS.md` "Protocol invariants" → "Script contracts" — the
  source matrix this section absorbs.
