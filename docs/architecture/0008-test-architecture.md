# Test architecture

> **Status:** v1-grade. Promoted from stub to canonical via card #33.

## Purpose

Define what gets tested at which layer, why each layer earns its tests,
where the in-tree CI gates live, and what the v1 test surface
deliberately does **not** cover. Replaces the v0.x stub which claimed
"only `claim-card.sh` is covered" — that statement was already obsolete
by v0.2.0 (14 `.sh` files under `tests/`: 13 tests + 1 sourced helper
`common-helpers.sh`), and this doc captures the real
shape so future Consumers can extend it without re-discovering it from
the file tree.

The doc is paired with `0006-failure-modes.md` (each documented failure
mode names the test that would have caught it) and with
`0007-observability.md` (test outputs land in CI logs and stderr, not in
the runtime audit-log surface). Together the three docs make up the v1
quality contract: failures we know about, signals that surface them, and
tests that prevent regressions.

## Layer matrix

The v1 test surface has three layers, ordered from cheapest to deepest:

| Layer | Scope | Tools | Coverage in v1-minimum (v0.2.0) | Hermetic? |
|-------|-------|-------|----------------------------------|-----------|
| **Unit / contract** | Single script's stdout shape, exit codes, side-effect shape (file written, branch created, line appended) | bash + bare-repo-as-origin pattern in `tests/common-helpers.sh` | claim-card, check-deps (×2), setup-labels, audit-local migration, entry-skill marker consumption, hook INVOKE marker, all four bootstrap scripts | yes (HOME / XDG / GIT_CONFIG isolated) |
| **Integration** | Multi-script flows where one script's output feeds another | bash + same hermetic primitives | bootstrap end-to-end, bootstrap rollback, bootstrapping-repo skill, F-B1 host bootstrap, F-B2 per-repo (×3 variants) | yes |
| **Skill smoke / CI gate** | Whole-tree invariants that need to hold across every skill, not just one | bash wrappers around python3 validators | `verify-skill-metadata.sh`, `verify-skill-frontmatter.sh`, `shellcheck -x` | yes (read-only on the source tree; no temp dirs needed) |

Two layers are **explicitly out of scope** for v1 and not in the matrix:

- **State-machine end-to-end** (every transition in `board-canon`
  triggers a test that asserts the post-condition). Tested ad-hoc in the
  bootstrap / claim integration tests; not extracted as its own layer
  until the matrix outgrows the integration layer (deferred per ADR-0011
  demand-pull pattern).
- **Manager / Consumer end-to-end** (drive a real CC / Codex session
  against a scratch repo + Project, assert the user-visible prose).
  Likely permanent manual smoke test category — automating CC / Codex
  session orchestration is platform-coupled and brittle. Documented as a
  manual smoke checklist in
  `bootstrapping-repo/references/first-time-user-guide.md`.

### Why three layers, not five

The classic test pyramid (unit / integration / contract / e2e /
acceptance) presupposes a deployed-service architecture;
board-superpowers is a script + skill bundle with no long-running
process. The integration layer carries what would have been "contract"
tests in a service-shape codebase (because there is no inter-service
contract — only inter-script CLI contracts), and the skill smoke layer
carries what would have been "linting / static analysis" in a compiled
codebase (because skills are markdown + yaml, not source code that
compiles). Folding to three layers eliminates the redundancy without
losing coverage.

## Layer 1 — Unit / contract tests

### What they test

For each script under `scripts/`, one or more
`tests/test-<script>-<aspect>.sh` files assert:

- **Exit code shape.** Every documented exit code is reachable; no test
  path returns a code outside the documented set.
- **Stdout shape.** When the script prints structured output (JSON for
  downstream consumption, e.g., `claim-card.sh`'s final JSON line), the
  test parses it with `python3 -c 'json.load(sys.stdin)'` and asserts
  key presence.
- **Stderr shape.** `[bsp ...]` log lines and `[bsp ERROR]` failure
  lines are asserted via grep against expected substrings — but not
  against full text, to avoid coupling tests to copy-edits.
- **Side effects.** File created / appended at expected path, git branch
  created locally / pushed to bare origin, GitHub Project field flipped
  (mocked via `gh` shim where necessary).
- **Idempotency.** Where the script's docstring claims idempotent re-run
  is a no-op (e.g., `setup-labels.sh`), the test runs the script twice
  and asserts the second run is a no-op (no extra rows / branches /
  commits / file appends).

### Hermetic pattern

Promoted here from `tests/common-helpers.sh` (and from the obsolete
devguide note in CLAUDE.md). Every contract test source-helpers and then
runs in a temp dir that:

- `HOME=$TMP/home` — isolates user config (no leakage of real
  `~/.gitconfig` / `~/.board-superpowers/`).
- `XDG_CONFIG_HOME=$TMP/xdg` — isolates worktree default path
  (`$HOME/.config/superpowers/worktrees/`).
- `GIT_CONFIG_GLOBAL=$TMP/.gitconfig-global` +
  `GIT_CONFIG_SYSTEM=/dev/null` — isolates git author / committer +
  ignores host-global git settings.
- Bare local repo at `$TMP/origin.git` serves as `origin`; **no test
  reaches GitHub**. The bare repo is the substitute for the real remote.
- `core.hooksPath=/dev/null` + `core.excludesFile=/dev/null` — disables
  git hooks and global excludes that could bias side-effect assertions.
- Process-level: `set -euo pipefail` + `trap` cleanup that `rm -rf` the
  temp dir on exit.

The hermetic primitives live in `tests/common-helpers.sh` and are
sourced by every contract test (and by every integration test below).
When the primitives need to evolve (e.g., a new env var that must be
isolated), the change lands once in helpers and every test inherits it.

### Coverage in v0.2.0

The current `tests/` tree (counted from the worktree at v0.2.0):

```
tests/
├── audit-local-migration.sh
├── check-deps-exit-codes.sh
├── check-deps-machine-mode.sh
├── common-helpers.sh
├── fixtures/
│   ├── session-start-v0.2.0-post-bootstrap.txt
│   └── session-start-v0.2.0-pre-bootstrap.txt
├── integration/
│   └── README.md
├── setup-labels-idempotent.sh
├── test-bootstrap-end-to-end.sh
├── test-bootstrap-rollback.sh
├── test-bootstrapping-repo-skill.sh
├── test-entry-skill-marker-consumption.sh
├── test-fb1-host-bootstrap.sh
├── test-fb2-byo-rdbms.sh
├── test-fb2-per-repo.sh
├── test-fb2-routing-injection.sh
└── test-hook-invoke-marker.sh
```

Layer-1 (contract) coverage in v0.2.0: `audit-local-migration`,
`check-deps-exit-codes`, `check-deps-machine-mode`,
`setup-labels-idempotent`, `test-entry-skill-marker-consumption`,
`test-hook-invoke-marker`. Six of the v1-minimum scripts have at least
one contract test; the older `claim-card.sh` lives at the same layer but
its tests historically used a different filename pattern
(`test-claim-card*.sh`) — when those tests are re-added or refactored,
prefer the new `<scope>-<aspect>.sh` naming that the rest of the v0.2.0
tree adopts.

### Coverage gaps (intentional)

- **`submit-pr.sh`** — exercised end-to-end via the `consuming-card`
  Step 10 path during dogfood; no isolated contract test. Reason: the
  script is heavily PR-API-coupled and mocking the `gh pr create`
  surface produces tests that test the mock, not the script.
  Surface-level integration test would be more useful and is on the v1.x
  candidates list pending demand.
- **`bootstrap-rollback.sh`** — covered by `test-bootstrap-rollback.sh`
  but only at the integration level (running the rollback after a real
  bootstrap), not as a unit contract test. Same reason — the rollback's
  contract is "undo what bootstrap did" and is best asserted against a
  real bootstrap state.

## Layer 2 — Integration tests

### What they test

Multi-script flows where one script's output feeds another, or where a
sequence of operations must produce a coherent end state:

- **Bootstrap end-to-end** (`test-bootstrap-end-to-end.sh`): F-B1 host
  bootstrap → F-B2 per-repo bootstrap → state.yml + manifest.yml +
  routing block injection all land coherently.
- **Bootstrap rollback** (`test-bootstrap-rollback.sh`): bootstrap then
  rollback returns the host + repo to pre-bootstrap state (no state.yml,
  no manifest entry, no routing block in AGENTS.md).
- **Bootstrapping-repo skill behavior**
  (`test-bootstrapping-repo-skill.sh`): the molecular skill's
  prose-output contract on first-time-on-this-repo state — checks that
  the right `INVOKE: bootstrapping-repo` marker is emitted, the skill
  body is consumed, the state probe re-runs after bootstrap completes.
- **F-B1 host bootstrap** (`test-fb1-host-bootstrap.sh`): isolated F-B1
  path (without F-B2) — used to test the host-only bootstrap that runs
  once per host across all repos.
- **F-B2 variants**
  (`test-fb2-{byo-rdbms,per-repo,routing-injection}.sh`): the three F-B2
  sub-capabilities — BYO RDBMS credential setup, per-repo state file
  write, routing block injection into `AGENTS.md` + `CLAUDE.md`. Split
  because each has its own prerequisites and failure modes.

Integration tests use the same hermetic primitives as Layer 1 — the test
boundary is tightly scoped (no real GitHub, no real DB), but the script
composition is real (one script's output is the next's input).

### `tests/integration/README.md`

The integration sub-directory is the future home of opt-in
**real-network** tests — tests that hit a real GitHub Project (requires
`gh` auth + the maintainer's `project` scope) or a real BYO RDBMS (per
ADR-0009's 6-scheme allowlist). v0.2.0 ships zero such tests; the
README pins the contract for any test that lands here in the future.
The opt-in mechanism is environmental: a test under
`tests/integration/` MUST gate its actual side-effecting work on
`BSP_INTEGRATION=1` and print a friendly skip-message-then-exit-0
otherwise. CI runners do not carry the secrets needed for the
integration suite, so default test runs do not exercise it.

## Layer 3 — Skill smoke / CI gates

### `verify-skill-metadata.sh`

Validates the `<skill-dir>/.skill-meta.yaml` ↔ `SKILLS.md` catalog
correspondence per `SKILL_DEVELOPMENT.md` § "board-superpowers metadata
convention". Specifically:

1. Every `skills/<name>/` has both `SKILL.md` AND `.skill-meta.yaml`.
2. Every `.skill-meta.yaml` has the 5 required fields: `version`
   (semver) + the four dimensions `layer` / `type` / `mode` /
   `bounded-context`.
3. All four dimension values are in their legal enum sets (e.g., `layer
   ∈ {entry, molecular, atomic}`, `type ∈ {technique, pattern,
   reference, discipline}`, `mode ∈ {claude-code-only, codex-only,
   both}`, `bounded-context ∈ {board, session, bootstrap, audit,
   spec}`).
4. The yaml's four-dimension values match the SKILLS.md catalog
   statement for that skill.

Implementation: bash wrapper that delegates yaml parsing to a python3
heredoc (yaml parsing in pure bash is painful; python3 is already a hard
dependency). Exit code 0 = all skills pass; 1 = at least one problem on
stderr.

### `verify-skill-frontmatter.sh`

Validates the `<skill-dir>/SKILL.md` YAML frontmatter per
`SKILL_DEVELOPMENT.md` § "Three-tier frontmatter discipline":

1. **Tier 1**: `name` + `description` are present (mandatory;
   cross-platform portable).
2. **Tier 2**: any field used must be in the CC official spec set
   (`when_to_use`, `argument-hint`, `arguments`,
   `disable-model-invocation`, `user-invocable`, `allowed-tools`,
   `model`, `effort`, `context`, `agent`, `hooks`, `paths`, `shell`).
3. **Tier 3**: NO custom non-spec fields (anti-pattern A4 — fields like
   `version: 1.0` belong in `.skill-meta.yaml`, not in the SKILL
   frontmatter).
4. **Defensive cross-platform safety**:
   - `description` ≤ 1024 characters (cross-platform safe ceiling).
   - `description` + `when_to_use` combined ≤ 1536 characters (CC
     absolute ceiling).
   - `argument-hint` values containing YAML special characters
     (`:,*&!|>'"[]{}#%@\``) MUST be double-quoted.

Implementation: same bash + python3 heredoc pattern as
`verify-skill-metadata.sh`.

### `shellcheck -x`

Static analysis for every `.sh` file under `scripts/` and `hooks/`. The
`-x` flag follows source paths so the checker sees variables defined in
`scripts/lib/common.sh` when it is sourced. Convention: every script
under `scripts/` MUST `set -euo pipefail` BEFORE sourcing common.sh;
shellcheck enforces this and several other strict-mode rules.

Local invocation:

```bash
shellcheck -x scripts/**/*.sh hooks/*.sh
```

Exit code 0 = clean; non-zero = warnings or errors. v0.2.0 standing
rule: every script in this tree must be shellcheck-clean before merge;
an open shellcheck warning is a contract violation flagged in PR review.

### Why these three at the smoke layer

Each catches an entire class of regression that no single contract /
integration test would:

- `verify-skill-metadata`: catches drift between the yaml side-files and
  the SKILLS.md catalog. Without this gate, the catalog can claim
  "atomic" while the yaml says "molecular" indefinitely; the next
  architect inherits broken topology.
- `verify-skill-frontmatter`: catches Tier 3 violations (non-spec fields
  like `version: ...` accidentally added to SKILL.md frontmatter).
  Without this gate, individual SKILL.md files drift into private
  conventions.
- `shellcheck -x`: catches shellisms that work in bash 5 / GNU but break
  on macOS bash 3.2 (the project's stated minimum per AGENTS.md tech
  stack), plus the usual quoting / unset-variable / glob hazards.

## Hook smoke check (cross-platform parity)

`hooks/session-start.sh` is identical on both platforms (uses
`bsp_plugin_root()` from `scripts/lib/common.sh` to resolve paths
cross-platform). However, **registration differs** between Claude Code
and Codex CLI per `PLUGIN_DEVELOPMENT.md` § "What this means for
board-superpowers" #3:

- **Claude Code** auto-discovers `<plugin-root>/hooks/hooks.json` on
  plugin load. No user action required.
- **Codex CLI** does NOT auto-discover. The user runs
  `scripts/register-codex-hooks.sh --install-user` (writes to
  `~/.codex/hooks.json`) or `--install-repo` (writes to
  `<repo>/.codex/hooks.json`) once per Codex install. Idempotent; backs
  up the target file before merging.

The hook smoke check verifies:

- **Hook script behavior is platform-independent.**
  `test-hook-invoke-marker.sh` invokes `hooks/session-start.sh` directly
  with a controlled state and asserts the `INVOKE: <skill> / REASON:
  <line>` marker shape. Same test, same assertion, on both platforms.
- **Registration script is idempotent.** Running
  `scripts/register-codex-hooks.sh --install-user` twice in a row
  produces no diff in `~/.codex/hooks.json` (the second run detects the
  existing entry and exits 0 with `[bsp] codex hook already registered,
  skipping`).
- **Marker consumption is platform-independent.**
  `test-entry-skill-marker-consumption.sh` simulates a session where the
  hook injected `INVOKE: bootstrapping-repo` and asserts
  `using-board-superpowers` routes correctly to `bootstrapping-repo`
  regardless of which platform the marker came from.

The smoke checks run as part of the unit / contract layer (above) but
are called out separately here because the cross-platform parity
property is what makes board-superpowers dual-platform without divergent
test surfaces.

## Audit-log integrity check

The v1-minimum-degraded local jsonl trace at
`~/.board-superpowers/repos/<normalized>/audit-local.jsonl` has
integrity properties that need to survive code changes:

- **Append-only.** No script in the tree opens the file in a mode other
  than append (`>>` or python's `open(..., 'a')`). Test surface: a grep
  over `scripts/` for any `open(...,"w")` / `>` redirection targeting
  `audit-local.jsonl` MUST return zero matches. Currently informal;
  promotion to an automated lint candidate for v1.x.
- **One JSON object per line, no trailing comma.** Each appended line is
  a complete JSON object, parseable in isolation by `python3 -c
  'json.loads(sys.stdin.read())'`. Test surface:
  `audit-local-migration.sh` exercises this property for the legacy →
  v0.2.0 layout migration; same parser would catch a malformed append in
  any future migration.
- **Required fields always present.** Every entry has the 7 v1-minimum
  fields (`ts`, `repo_root`, `action_id`, `decision_class`, `skill`,
  `summary`, `mode`). Test surface: `bsp_audit_local_write` (the only
  writer) is tested transitively whenever an end-to-end test exercises a
  mutating action; the helper's own contract test is on the v1.x
  candidates list pending demand.
- **Migration backward compatibility.** When a future plugin version
  reshapes the local jsonl format (e.g., to mirror the BYO RDBMS schema
  for cleaner reconcile), the migration script MUST preserve every
  existing entry. Test surface: `audit-local-migration.sh` is the
  template — it asserts an old-layout file is correctly read
  post-migration with no entries lost.

## Deferred `auditing-actions` test surface

When the deferred `auditing-actions` atomic skill ships (per SKILLS.md
catalog), it brings a new test surface for the BYO RDBMS path:

- **DSN parser tests.** Validate that the 6-scheme allowlist
  (`postgres://`, `postgresql://`, `mysql://`, `mysql+pymysql://`,
  `sqlite://`, `sqlite3://` per ADR-0009) parses correctly and rejects
  unknown schemes.
- **Schema migration tests.** The DDL init script per
  `0005-contracts/06-audit-log-schema.md` § "DDL ownership" must produce
  a schema that the writer can use — tested by running the init script
  against an ephemeral DB and writing one row of each `(action_id,
  outcome, approval_stage)` combination.
- **R-class two-row write tests.** Per ADR-0006 § 5, R-class actions
  write one row at propose time + one at resolve time. Test surface:
  drive a propose, drive an ack, assert two rows landed with linked
  `payload.proposal_id`.
- **Degradation tests.** When the configured DB is unreachable, the
  writer falls back to the v1-minimum-degraded jsonl path AND prints the
  WARN line to stderr. Test surface: configure an invalid DSN, drive a
  mutating action, assert the WARN line + the jsonl entry both land.
- **Reconciler tests.** Once the BYO RDBMS lands, the one-shot
  reconciler that ingests the v1-minimum-degraded jsonl trace into the
  DB MUST be tested for completeness (every jsonl entry produces one
  row) and idempotency (re-running the reconciler is a no-op).

These tests are scoped to the `auditing-actions` skill landing PR; they
are not v1-minimum work and not part of card #33's deliverable. Listed
here so the v1.x ship plan inherits the surface without re-deriving it.

## CI invocation

v0.2.0 has no automated CI runner; the CI gates run locally. The
standing rule per AGENTS.md:

```bash
# Full local CI suite (run before opening a PR):
bash scripts/verify-skill-metadata.sh
bash scripts/verify-skill-frontmatter.sh
shellcheck -x scripts/**/*.sh hooks/*.sh

# Hermetic test suite — runs every time:
for t in tests/*.sh; do
  case "$(basename "$t")" in
    common-helpers.sh) continue ;;  # sourced helper, not a test
  esac
  [ -f "$t" ] && bash "$t" || true
done

# Opt-in real-network integration suite — only with BSP_INTEGRATION=1:
if [ "${BSP_INTEGRATION:-0}" = "1" ]; then
  for t in tests/integration/*.sh; do
    [ -f "$t" ] && bash "$t" || true
  done
fi
```

The aggregating runner (`tests/run-all.sh` or similar) is on the v1.x
candidates list per ADR-0011 demand-pull pattern — currently the
architect's manual `for` loop is fast enough that automating it has not
earned its complexity. When CI is added (likely GitHub Actions matrix on
macOS + Linux per the existing `0006-failure-modes.md` Scenario (a)
workaround for BSD vs GNU `date`), the same `for` loop is the contract
surface that gets wrapped.

### macOS + Linux parity

Per `AGENTS.md` "Tech stack" § "bash 3.2+", macOS BSD bash 3.2 is the
stated floor. Several Linux-only patterns have already bitten dogfood
and are now banned by convention:

- `date -d` (GNU) — use `date -j -f` (BSD) or pure bash `printf
  '%(...)T'`.
- Process substitution `<(...)` — supported on bash 3.2 but parses
  differently in `sh` mode; tests MUST run under `bash` explicitly.
- `mapfile` — bash 4+, NOT in 3.2; use `read -r` loops or `(
  )`-substituted arrays.
- `[[ ... =~ ... ]]` regex behavior differs between bash 3.2 and 4+;
  prefer `case ... esac` or `expr` for portability-critical paths.

`shellcheck -x` catches most of these (SC2317, SC2046, SC2039, etc.);
the residual ones are documented as PR-review checklist items in
`enforcing-pr-contract`.

## What v1 deliberately does NOT test

Per the cadence-scrutiny rule
(`feedback_question_human_team_ceremonies_in_ai_context`) and ADR-0011's
deferred-routine pattern:

- **Test-coverage percentage targets.** No "% of scripts covered" / "%
  of skills covered" thresholds. Coverage is informal and
  architect-judged; numeric thresholds are deferred until concrete CI
  toolchain decision per ADR-0010 § 3.
- **Performance regression tests.** No timing assertions. Per ADR-0010 §
  3, AI-cadence operation makes timing observability unactionable in v1;
  performance tests would tell the architect nothing the in-session
  surface does not already make obvious.
- **Mutation testing.** No automated mutation testing (e.g., via `mull`
  for compiled languages, equivalent for bash). The plugin's surface is
  small enough that diff-driven review catches what mutation testing
  would, at far lower complexity.
- **Stress / load tests.** No script is on a hot path (the slowest is
  `claim-card.sh`'s 4-step transaction at < 5 seconds). Stress is
  meaningless at this scale.
- **End-to-end CC / Codex session tests.** Manual smoke checklist only;
  automating session orchestration is platform-coupled and brittle.
  Documented intentional gap, re-evaluated when v1.x demand surfaces.

## Test ownership

- **Authoring a new test.** The Consumer working on the script / hook /
  skill that the test covers writes the test in the same PR.
  PR-review-time check (per `enforcing-pr-contract`): every script
  change of > 20 LOC under `scripts/` SHOULD have at least one new
  contract test row in the PR's diff; absence MAY be flagged.
- **Maintaining `tests/common-helpers.sh`.** Owned by the architect —
  the helper is shared infrastructure and its edits land in their own
  focused PR.
- **CI gate evolution.** The three CI gates (`verify-skill-metadata`,
  `verify-skill-frontmatter`, `shellcheck -x`) evolve when the
  underlying contracts evolve; their changes land in the same PR as the
  contract change per the AGENTS.md "Same-PR contract update" rule.

## Related

- ADR-0006 § 5 — Audit log persistence (drives the audit-log integrity
  check + deferred `auditing-actions` test surface).
- ADR-0007 — Plugin-runtime-derived constraints (drives the hook smoke
  check's cross-platform parity property).
- ADR-0008 — Plugin-to-plugin SKILL invocation (drives
  `verify-skill-frontmatter`'s namespace-prefix check for cross-skill
  references).
- ADR-0009 — Allow SQLite as a BYO audit DB scheme (drives the deferred
  DSN parser tests' 6-scheme allowlist).
- ADR-0010 — AI cadence 100x convention (drives the "what v1 does NOT
  test" deferrals: timing, coverage %, performance regressions).
- ADR-0011 — Defer Producer routines F-03..F-07 + F-10..F-15 to v1.x
  pending demand pull (the deferred-routine pattern this doc applies to
  deferred test surfaces).
- `0005-contracts/06-audit-log-schema.md` — referenced from the deferred
  `auditing-actions` test surface section.
- `0006-failure-modes.md` — every scenario's "Detection signal" is a
  candidate test surface; many already exist as Layer 1 / 2 tests.
- `0007-observability.md` — test outputs land outside the runtime
  observability surfaces (CI logs, not audit log).
- `PLUGIN_DEVELOPMENT.md` § "What this means for board-superpowers" #3 —
  canonical source for the cross-platform hook registration contract
  this doc's smoke check protects.
- `SKILL_DEVELOPMENT.md` § "Three-tier frontmatter discipline" —
  canonical source for what `verify-skill-frontmatter` enforces.
- `SKILL_DEVELOPMENT.md` § "board-superpowers metadata convention" —
  canonical source for what `verify-skill-metadata` enforces.
- `tests/common-helpers.sh` — the hermetic-pattern primitives; this doc
  references them but does not duplicate their implementation.
