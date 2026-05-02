# Release Notes — v0.5.0 (setup-stages substrate + 22-module bootstrap redesign)

> **Codename**: bootstrap redesign. This release completes the
> setup-stages substrate (ADR-0012 through ADR-0027) that replaces the
> ad-hoc bootstrap scripts shipped in v0.4.x. Every new repo now walks
> through 22 declarative stages driven by a 6-state lifecycle engine;
> the hook fires on every session start and routes the architect
> automatically.

---

## Pre-v1 breaking changes

These changes affect any architect with an existing v0.4.x installation.
The migration is a **delete-and-re-bootstrap** — no data migration script.

### 1. settings.yml family rename (ADR-0024 Part A)

All v0.4.x per-file names retire. The new names:

| v0.4.x path | v0.5.0 path | Locality |
|-------------|-------------|----------|
| `~/.board-superpowers/manifest.yml` | `~/.board-superpowers/settings.yml` | host-shared |
| `~/.board-superpowers/repos/<norm>/state.yml` | `~/.board-superpowers/repos/<identity>/settings.yml` | repo-shared |
| `<repo>/.board-superpowers/config.yml` | `<repo>/.board-superpowers/settings.yml` | repo-git |
| `<repo>/.board-superpowers/config.local.yml` | `<repo>/.board-superpowers/settings.local.yml` | repo-clone |
| `~/.board-superpowers/overrides.yml` | folded into `~/.board-superpowers/settings.yml` § `modules.m8_autonomy` | host-shared |

**Action**: delete the legacy files and re-bootstrap each repo:

```bash
# Remove host-level legacy files
rm -f ~/.board-superpowers/manifest.yml
rm -f ~/.board-superpowers/overrides.yml
rm -rf ~/.board-superpowers/repos/   # legacy per-repo state.yml tree

# For each repo using board-superpowers:
cd <your-repo>
rm -f .board-superpowers/config.yml
rm -f .board-superpowers/config.local.yml
```

### 2. M4 audit credentials.yml relocates to per-repo (ADR-0015)

v0.4.x kept audit credentials at `~/.board-superpowers/credentials.yml`
(host-shared). v0.5.0 moves them to
`~/.board-superpowers/repos/<identity>/credentials.yml` (repo-shared,
gitignored). This keeps audit backends per-repo-isolated.

**Action**: delete the legacy host-shared credentials file and re-enter
the DSN per-repo (or accept the SQLite zero-config default per ADR-0019):

```bash
rm -f ~/.board-superpowers/credentials.yml
```

### 3. `migrating-repo-version` SKILL absorbed into `bootstrapping-repo` (ADR-0012)

The deferred `migrating-repo-version` SKILL is retired from the roadmap.
Its function (detecting version transitions and running the lifecycle
engine) is absorbed into `bootstrapping-repo` as the single executor for
the setup-stages flow. Architects are not affected — the SKILL was never
shipped. The hook emits one marker grammar: `INVOKE: bootstrapping-repo`.

### 4. `stages_completed[]` storage path change

v0.4.x wrote stage completion records at the top-level `stages_completed:`
list. v0.5.0 writes lifecycle state at
`modules.lifecycle.<stage_id>` inside repo-shared `settings.yml`.
The old key is ignored; re-bootstrap initializes the new path.

---

## New capabilities

### Unified setup-stages mechanism (22 stages, 6-state lifecycle)

Every repo now bootstraps through a 22-stage declarative registry
(`scripts/stages-registry.yml`). Stages span 10 modules (M1–M10). The
hook computes a lifecycle diff on every session start and emits
`INVOKE: bootstrapping-repo` with the first non-applied stage as REASON.
The `bootstrapping-repo` SKILL drives the sequential per-stage flow.

**Lifecycle states** (ADR-0013): `pending` | `applied` | `not-applicable` |
`drifted` | `failed` | `blocked`. Stages whose dependency is pending or
failed cascade to `not-applicable` (no spurious prompts).

**3-layer fingerprint diff** (ADR-0013): Layer 1 = O(1) generation int;
Layer 2 = sha256 target-state hash (detects semantic drift without a
generation bump); Layer 3 = structured field diff (human-readable
migration diagnostics in the SKILL).

### Zero-config SQLite default audit backend (ADR-0009 + ADR-0019)

M4 now defaults to SQLite when the architect skips DSN entry. The
`acquire-dsn` agentic stage presents `[sqlite]` as the pre-selected
default. SQLite DB lives at `<repo>/.board-superpowers/audit.sqlite3`
(gitignored). No Postgres/MySQL credentials required for a first install.

### Agentic config-item protocol (ADR-0023)

Four stages require architect input: `m4.repo.acquire-dsn`,
`m5.repo.set-wip-limit`, `m8.host.bootstrap-overrides-yml`,
`m10.repo.choose-kanban-projection`. Each uses the 5-element ADR-0023
protocol: `executor()` returns `{requires_input, prompt, default}`;
the SKILL surfaces the prompt; the architect responds; `apply_choice()`
persists the validated value. Empty selection is a valid `completed` state
for multi-choice stages (M8 autonomy overrides).

### Cross-platform M9 stage automates Codex hook registration

The new `m9.host.register-codex-hooks` stage (`codex-only`) runs
`scripts/register-codex-hooks.sh --install-user` automatically during
bootstrap on Codex CLI. The README's manual registration instruction
retires; architects run a single bootstrap session and M9 wires the hook.
On Claude Code, M9 is `not-applicable` (CC auto-discovers `hooks.json`).

### BoardAdapter capability dispatch for M3 stages (ADR-0027)

M3's two stages (`m3.repo.ensure-labels`, `m3.repo.validate-status-field`)
are now gated by the `applicable_when.kanban_projection_capability`
predicate (ADR-0020 Form B). The predicate shells out to
`bsp_resolve_active_projection` and checks the projection's reference file
`skills/operating-kanban/references/<projection-id>.md` §"Setup
capabilities". v0.5.0 ships `github-project-v2.md` declaring both
capabilities. Future projections that don't support label management skip
`ensure-labels` cleanly.

### M7 multi-stage routing-block injection (ADR-0018)

Three M7 stages detect the repo's routing-target form
(`cc-only` / `codex-only` / `dual` / `neither`) and inject the two required
routing blocks (`routing-rule` + `skill-routing`) into the appropriate
files. Each block is capped at 4 KiB; the total Codex AGENTS.md budget
is enforced at 32 KiB. The SKILL surfaces a human-readable size warning
when the budget nears the cap.

### Graceful degradation path (no venv)

On a truly fresh repo before M2 venv creation, the hook falls back to the
v0.4.x file-presence heuristic (host-shared settings.yml + repo-shared
settings.yml absent → emit `INVOKE: bootstrapping-repo`). Once M2
completes and the venv exists, subsequent hook runs use the full lifecycle
diff via `python3 -m stages_lib lifecycle-probe`.

---

## Migration steps for architects

1. **Delete legacy state files** (see Breaking Changes §1 + §2 above).

2. **Pull main, ensure `uv sync` succeeds**:
   ```bash
   cd <your-plugin-dir>   # where board-superpowers plugin is installed
   git pull --ff-only
   cd <your-repo>
   uv sync --project .board-superpowers   # if venv already exists
   ```

3. **Open a fresh CC or Codex session in any repo running board-superpowers**.
   The hook fires; the SKILL routes automatically; the sequential per-stage
   flow walks you through any agentic stages:
   - `m10.repo.choose-kanban-projection` — confirm `github-project-v2`
     (only option at v0.5.0)
   - `m5.repo.set-wip-limit` — enter WIP limit (default 5)
   - `m8.host.bootstrap-overrides-yml` — select autonomy presets (empty = OK)
   - `m4.repo.acquire-dsn` — accept SQLite default or enter Postgres/MySQL DSN
   - Automated stages (M1, M2, M3, M6, M7, M9) run without prompts

4. **Verify the final state**:
   ```bash
   # Host-shared settings written
   cat ~/.board-superpowers/settings.yml

   # Repo-shared lifecycle recorded
   cat ~/.board-superpowers/repos/<identity>/settings.yml

   # Repo-git config present
   cat <repo>/.board-superpowers/settings.yml

   # SQLite audit DB created (if SQLite default chosen)
   ls -la <repo>/.board-superpowers/audit.sqlite3

   # Routing blocks injected
   grep -n "board-superpowers" <repo>/AGENTS.md
   grep -n "board-superpowers" <repo>/CLAUDE.md   # if dual form

   # .gitignore protective entries
   grep "board-superpowers managed" <repo>/.gitignore
   ```

5. **Subsequent sessions are silent**. The hook runs the lifecycle diff and
   emits no `INVOKE` marker when all 22 stages are `applied` or
   `not-applicable`.

6. **Existing cards are untouched**. `bash scripts/read-board.sh` (and
   all other board-touching scripts) continues to work; the setup-stages
   substrate is additive.

---

## Architect-attention items

- **`migrating-repo-version` SKILL deferred-and-retired** — the hook now
  handles version transitions via the lifecycle engine; no separate
  migration SKILL is needed for v0.4.x → v0.5.0.
- **Multi-kanban support deferred to v0.6.x** — `m10.repo.choose-kanban-projection`
  persists the shorthand flat form (`modules.m10_kanban.projection: github-project-v2`).
  The multi-kanban kanbans-list nesting form is reserved for v0.6.x; do not
  hand-edit it into settings.yml at v0.5.0.
- **Linear / Jira projections land in v1.x** — `m10` enum has one option
  at v0.5.0. New options carry `introduced_in_version` per ADR-0023 so
  existing repos that already chose `github-project-v2` are not re-prompted
  when a new projection option ships.
- **`deprecated` lifecycle state deferred to v0.6.0** — ADR-0013 defines
  the state but no v0.5.0 stage carries `deprecated_in_version`; the
  auto-prune sweep is a no-op until the first stage removal.
