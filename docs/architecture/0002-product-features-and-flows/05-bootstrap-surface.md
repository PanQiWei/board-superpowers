### 1.5 Bootstrap surface

The capabilities the setup and lifecycle-transition flows expose.
Bootstrap is no longer a single one-shot ceremony — it is a
**two-layer state machine** spanning host (cross-repo, per
machine) and repo (per project), with two upgrade-time variants
that fire when a previously-bootstrapped install moves to a new
plugin version. The four features below are organized along
**(layer × event)**:

|                | First-time event              | Version-transition event       |
|----------------|-------------------------------|--------------------------------|
| **Host layer** | F-B1 Host bootstrap           | F-B3 Host version transition   |
| **Repo layer** | F-B2 Per-repo bootstrap       | F-B4 Per-repo version transition |

The four user scenarios this matrix covers (see §2.1 / §2.2 /
§2.3 for the user-journey narratives):

- **A. Brand-new everything** — F-B1 fires (host bootstrap +
  intro + quick-start) → then F-B2 (per-repo bootstrap) on the
  first repo touched.
- **B. Old host, new repo** — F-B2 only ("this is your N-th
  repo, here's per-repo bootstrap"). F-B1 was satisfied long ago.
- **C. Steady state** — none of F-B1..F-B4 fire; the dep check
  inside Layer 2 of the alert strategy is the only bootstrap-
  surface code that runs.
- **D. Plugin upgraded since last session** — F-B3 fires once
  (changelog highlights for the new version) → if any repo lags
  behind the new version on its next visit, F-B4 fires there too.
- **E. Host current but specific repo lagged** — F-B4 only ("this
  repo is on vX, plugin is vY, here's what's new for repo-side").

**Cross-cutting principles applied throughout this section**
(every subsection MUST honor):

- **Self-contained scripts at the dep-check layer.** Per `CLAUDE.md`
  ("Two files are deliberately self-contained"),
  `scripts/check-deps.sh` and `hooks/session-start.sh` MUST NOT
  source `scripts/lib/common.sh`. A broken lib must never break
  dependency detection or session startup.
- **Three-layer alert + intent-injection strategy.** Layer 1
  (SessionStart hook) does **two** things: (a) the dep alert
  banner (best-effort, advisory; emit when a sibling plugin is
  missing); (b) **intent injection** — when on-disk state implies
  the architect needs `bootstrapping-repo` or
  `migrating-repo-version`, the hook emits an `INVOKE: <skill>`
  marker into `additionalContext` so the entry skill fast-paths
  the routing decision (per
  [`0004-component-architecture.md`](../0004-component-architecture.md)
  § "Hook intent injection pattern" and
  [`0005-contracts/02-hook-contracts.md`](../0005-contracts/02-hook-contracts.md)
  § "Intent-injection markers"). Layer 2
  (`using-board-superpowers` SKILL Step 1) is the reliable gate
  — it re-runs the same dep + state check itself so the routing
  works even when the hook silently drops (CC `SessionStart`
  delivery is unreliable). Layer 3 (just-in-time re-checks
  inside `managing-board` and `consuming-card`) catches
  mid-session uninstalls before any cross-plugin call.
- **D-META-1** (`0001-positioning.md` P7): bootstrap captures
  project parameters (`OWNER/NUMBER`, `wip_limit`) but ships zero
  taste presets — no canned lint config, no canned PR section
  bodies, no canned retro template.
- **Dual-platform parity.** Per `PLUGIN_DEVELOPMENT.md`, the
  routing block lands in **both** `CLAUDE.md` (Claude Code
  auto-loads) AND `AGENTS.md` (Codex CLI auto-loads). The marker
  pair `<!-- board-superpowers:routing -->` /
  `<!-- /board-superpowers:routing -->` is identical in both;
  `check-deps.sh` matches in either.
- **Plugin-owned vs user-owned region split** (see I-11). State
  files written by these features (`manifest.yml`, `state.yml`)
  are plugin-managed; `config.yml` is user-editable; routing
  blocks are plugin-owned within the marker pair, user-owned
  outside. The `block_hash` mechanism (F-B4) enforces the
  boundary.
- **Schema versioning** (see I-12). Both `manifest.yml` (host)
  and `state.yml` (per-repo, host-local) carry `schema_version: <int>`.
  On read, the plugin runs migration if the on-disk value is older
  than the version this build understands. Lazy-on-read (Confluent /
  FlatBuffers schema-evolution pattern) over eager-on-startup —
  the migration only fires when the data is actually accessed,
  avoiding a startup-time cost for cold sessions.
- **Team-shared declarations in git, host-local state out** (see
  I-13). `config.yml` is committed (user decisions about WIP
  limit, project ref, etc. — team-shared by definition). The
  routing block injected into `CLAUDE.md` / `AGENTS.md` is
  committed too (the team uses it). `state.yml` is **host-local**
  at `~/.board-superpowers/repos/<normalized-repo-path>/state.yml`,
  never tracked — each architect's host independently bootstraps
  and maintains its own; collaborators on the same git remote do
  not silently overwrite each other's state. `manifest.yml` is
  also host-local at `~/.board-superpowers/`.
  `.board-superpowers/claims/` is gitignored (per-session
  forensic state, force-committed only to claim branches).

**State files (the data plane this surface owns):**

| File | Layer | Tracked in git? | Editable by user? | Schema-versioned |
|------|-------|-----------------|-------------------|------------------|
| `~/.board-superpowers/manifest.yml` | Host | No (per-machine) | No (plugin-managed) | Yes |
| `~/.board-superpowers/repos/<normalized>/state.yml` | Repo (host-local) | No (per-machine, per-repo) | No (plugin-managed) | Yes |
| `<repo>/.board-superpowers/config.yml` | Repo | Yes | **Yes** (hand-editable) | No (`wip_limit` etc.) |
| `<repo>/.board-superpowers/claims/` | Repo | No (gitignored) | No (per-session) | N/A |

The `<normalized>` directory name is the repo's absolute path
with leading `/` stripped and remaining `/` replaced by `-` (e.g.,
`/Users/panqiwei/my-project-repo` → `Users-panqiwei-my-project-repo`).
Canonical home for the rule:
[`0005-contracts/07-path-conventions.md`](../0005-contracts/07-path-conventions.md)
"Per-host layout".

YAML format chosen for `manifest.yml` and `state.yml` to match
the existing `config.yml` (see TBD-Notes below for the YAML-vs-
TOML rationale).

**Initial v1 manifest / state shape** (deliberately minimal per
YAGNI / Stripe-style API-evolution discipline — fields not
needed today are added via migration when needed; users seeing
a placeholder field will ask "what's this for?" and that drag
is worse than a future single-line migration):

```yaml
# ~/.board-superpowers/manifest.yml
schema_version: 1
host_bootstrapped_at: "2026-04-26T10:30:00Z"
last_seen_version: "0.1.0"
```

```yaml
# ~/.board-superpowers/repos/<normalized-repo-path>/state.yml
schema_version: 1
repo_bootstrapped_at: "2026-04-26T11:00:00Z"
last_seen_version_in_repo: "0.1.0"
features_enabled:
  - bootstrap.host
  - bootstrap.per_repo
routing_blocks:
  - target_file: "CLAUDE.md"
    block_hash: "sha256:<64-hex>"
    injected_at: "2026-04-26T11:00:01Z"
  - target_file: "AGENTS.md"
    block_hash: "sha256:<64-hex>"
    injected_at: "2026-04-26T11:00:01Z"
```

`features_enabled` is a list (not a map) at v1 — features are
either on or off, no per-feature config yet. When per-feature
config arrives, the migration converts list → map of feature_id
→ config; the on-read migration runs the first time any feature
needs its config.

#### 1.5.0 Dependency check (shared primitive)

> Used as a sub-capability by F-B1, F-B2, F-B3, F-B4, and by
> Layers 2 and 3 of the alert strategy. Documented here once;
> referenced everywhere else.

- **Capability**: detect that `superpowers` and `gstack` are
  installed and reachable from the current session, and that the
  current project's `CLAUDE.md` carries the routing-block marker.
  Implemented by `scripts/check-deps.sh`.
- **Inputs**: `$CLAUDE_PROJECT_DIR` (defaults to `$PWD`) and
  `$HOME` for plugin / skill path resolution. No CLI args in
  default mode; `--machine` flag toggles output shape.
- **Outputs**: human-readable banner on stderr + exit code (default
  mode); structured key=value lines on stdout (`--machine` mode).
- **Exit codes**: `0` = all dependencies present + routing
  injected (or no `CLAUDE.md` exists, in which case routing check
  is skipped); `2` = missing dependency OR `CLAUDE.md` exists but
  no routing marker; `3` = a runtime command (`gh`, `python3`)
  itself unavailable. The asymmetric "no `CLAUDE.md` is fine but
  `CLAUDE.md` without the marker is not" rule keeps the dep check
  silent in repos that don't use `CLAUDE.md` at all.
- **`--machine` mode keys**: emit nothing when everything is fine
  (callers test on `-z` of stdout); when something is wrong, emit
  exactly three lines:
  ```
  MISSING=<comma-separated-deps-or-empty>
  ROUTING_INJECTED=<yes|no>
  PROJECT=<absolute path>
  ```
  Renaming any of these three keys breaks the SessionStart hook
  parser (`hooks/session-start.sh`); see `CLAUDE.md` change-impact
  matrix.
- **Three-layer delivery** (in increasing reliability):
  - **Layer 1 — SessionStart hook**: `hooks/session-start.sh`
    runs `check-deps.sh --machine`, sanitizes the result, and
    emits a banner via `hookSpecificOutput.additionalContext`.
    **Two roles** at this layer: (a) **dep alert** when a
    sibling plugin is missing (current behavior); (b) **intent
    injection** — when host or per-repo state implies a
    bootstrap or migration is needed, the hook emits an
    `INVOKE: <skill-name>` + `REASON: <line>` marker into
    `additionalContext` so the model fast-paths to the right
    skill on the next prompt. Marker grammar pinned in
    [`../0005-contracts/02-hook-contracts.md`](../0005-contracts/02-hook-contracts.md)
    § "Intent-injection markers"; pattern rationale in
    [`../0004-component-architecture.md`](../0004-component-architecture.md)
    § "Hook intent injection pattern". Best-effort; per CC docs
    `SessionStart` delivery is unreliable, so Layer 2 always
    repeats the check.
  - **Layer 2 — `using-board-superpowers` SKILL Step 1**: the
    reliable gate **and the fallback**. Always re-runs the same
    dep + state check Layer 1 ran; if Layer 1 fired the marker
    the entry skill walks the marker, if Layer 1 silently
    dropped the entry skill detects the same condition itself
    and routes the same way. On exit `2` the skill stops and
    surfaces the verbatim banner.
  - **Layer 3 — Just-in-time re-checks**: `managing-board` and
    `consuming-card` both re-run `check-deps.sh` immediately
    before any cross-plugin call (e.g., before invoking
    `gstack:/qa` or `superpowers:subagent-driven-development`).
    Catches mid-session uninstalls — see §2.10.
- **Maps to (canonical)**: TPS *poka-yoke* — fail-safe design at
  the boundary.
- **Autonomy**: N/A (read-only; no state mutation).

#### 1.5.1 F-B1. Host bootstrap

- **Capability**: when `~/.board-superpowers/manifest.yml` is
  absent on the host, run the cross-repo, per-machine
  initialization: verify dependencies, create
  `~/.board-superpowers/`, write the initial host manifest, and
  deliver the first-time intro + quick-start narrative. F-B1
  fires once per host (machine), not once per repo. After F-B1
  completes, the architect's next interaction with a specific
  repo triggers F-B2.
- **Trigger**: `using-board-superpowers` Step 1 reads
  `~/.board-superpowers/manifest.yml`; absence triggers F-B1
  before any other behavior.
- **Inputs**: nothing from the architect at trigger time. The
  intro narrative may collect the architect's working-style
  preferences (typical parallel-Consumer count, primary kanban
  substrate) but defaults are safe — the architect can answer
  "use defaults" and proceed.
- **Outputs** (in order):
  1. Dependency check via §1.5.0 — abort with banner on exit `2`.
  2. Create `~/.board-superpowers/` (mode 0700; the directory
     never holds secrets but the conservative permission is
     defense-in-depth).
  3. Write `~/.board-superpowers/manifest.yml` with v1 minimal
     shape (`schema_version: 1`, `host_bootstrapped_at`,
     `last_seen_version`).
  4. Deliver intro + quick-start by loading
     `skills/using-board-superpowers/references/intro.md` (the
     two-role mental model + the morning-of-day-1 happy path).
- **Composes**: §1.5.0 dependency check + filesystem ops
  (`mkdir`, write YAML) + skill content delivery via
  `references/intro.md`. No `gh`, no network.
- **Maps to (canonical)**: XDG Base Directory Specification — the
  state file lives under `$XDG_STATE_HOME` semantics
  (`~/.local/state/board-superpowers/manifest.yml` is the
  XDG-strict path; v1 ships at `~/.board-superpowers/` for
  brevity and convention with sibling tools like `gh` whose state
  also lives at `~/.config/gh/`. See TBD-Notes for the strict-XDG
  migration option). The intro-on-first-run pattern is from
  `rustup` initial install + `bun upgrade` post-install message
  conventions.
- **Original framing**: the **two-layer (host + repo) state
  separation** itself. Most CLI tools (`gh`, `rustup`, `bun`)
  carry only host state. board-superpowers needs both because the
  product is per-repo (a kanban scoped to a project) but the
  install is per-host (a plugin reachable from any session). The
  matrix matters because version-transition events fire
  asymmetrically across the two layers — F-B3 fires once per host
  upgrade; F-B4 fires once per repo per (repo × upgrade) pair.
- **Mode compatibility**: both. The path
  `~/.board-superpowers/manifest.yml` is identical on Claude Code
  and Codex CLI hosts; the intro content is platform-portable
  prose.
- **Autonomy**: A — F-B1 is the trivial first-run setup; no
  architect approval needed for an empty-state initialization.
  Audit-log entry not yet meaningful (audit-log persistence is
  configured during F-B2's BYO-RDBMS sub-step, which has not yet
  run when F-B1 fires — F-B1 audit goes to a deferred queue
  flushed when F-B2 establishes the DB connection, OR is dropped
  silently if F-B2 declines BYO-RDBMS, since pre-config events
  are low-value forensically).

#### 1.5.2 F-B2. Per-repo bootstrap

- **Capability**: when
  `~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
  is absent for the current repo on the current host, run the
  per-`(host, repo)` initialization: Project v2 confirmation
  (manual UI step, see ADR-0001), `bootstrap-project.sh`
  (4 sub-capabilities — gitignore step now narrower; see below),
  initial `state.yml` write at the host-local path, dual-file
  routing injection (CLAUDE.md + AGENTS.md), and first-card
  pointer delivery. F-B2 fires once per `(host, repo)` pair, on
  the first session in that repo on that host after F-B1 has
  completed.
- **Trigger**: `using-board-superpowers` Step 3 reads
  `~/.board-superpowers/repos/<normalized-repo-path>/state.yml`;
  absence triggers F-B2. Precondition: F-B1 has already run
  (manifest.yml exists). If F-B1 has not run,
  `using-board-superpowers` fires F-B1 first and chains into
  F-B2.
- **Inputs**: `OWNER/NUMBER` of an existing GitHub Project v2
  (collected from the architect during the per-repo
  conversation); optional `--wip N` (default 5); BYO-RDBMS
  credentials (env var or `~/.board-superpowers/credentials.yml`,
  collected during sub-capability 5).
- **Outputs** (in order):
  1. **Project v2 confirmation gate.** The architect confirms
     they have created (or will create now) a Project v2 with
     the required Status field and six options
     (`Backlog → Ready → In Progress → In Review → Done →
     Blocked`). Per ADR-0001's substrate-commitment posture,
     the script does NOT create the project — Project v2
     single-select option creation via API is unreliable with
     standard tokens. The skill walks the architect through the
     UI steps if needed, then waits for the architect to paste
     `OWNER/NUMBER`.
  2. **`bootstrap-project.sh` runs the five sub-capabilities**,
     in execution order:
     1. **Standard labels** (`type:feature`, `type:bug`,
        `type:chore`, `type:refactor`, `type:epic`,
        `size:XS`, `size:S`, `size:M`, `size:L`). Idempotent
        — pre-existing labels with the same name are skipped,
        not overwritten. Real failures (token-scope problems)
        abort the bootstrap; "already exists" does not.
     2. **Status field validation** — confirms the project's
        `Status` single-select field exists and has all six
        required options in the exact order. The script
        reports missing options and aborts (architect adds
        them in UI and re-runs).
     3. **`.board-superpowers/config.yml`** — written with
        `project: "OWNER/NUMBER"` and `wip_limit: N`. Hand-
        editable by design; future fields are commented-out
        placeholders so editing the file communicates extension
        shape without ambiguity. Schema-versioning does NOT
        apply to `config.yml` — it is user-editable and uses
        commented-out placeholders rather than schema versions
        (the YAGNI half of I-12).
     4. **`.gitignore` entry** — appended idempotently in one
        block (per [`07-cross-cutting-invariants.md`](./07-cross-cutting-invariants.md)
        I-13). With `state.yml` now host-local, only the per-session
        `claims/` directory needs ignoring inside the repo:
        ```
        # board-superpowers local state (claim markers are per-session)
        .board-superpowers/claims/
        ```
        `config.yml` is intentionally not negated — it is tracked
        by default since the parent directory is tracked. The prior
        `!state.yml` and `!config.yml` belt-and-suspenders lines are
        no longer needed: `state.yml` does not live in the repo at
        all.
     5. **BYO RDBMS audit-log credential setup** (per ADR-0006
        §5) — checks for `BOARD_SP_AUDIT_DB_URL` env var OR
        `~/.board-superpowers/credentials.yml` (chmod 600) with
        an `audit_db_url:` field. **Postgres or MySQL only**;
        SQLite, local file paths, and any public destination
        (card comments, audit issue) are explicitly forbidden.
        If no DB is configured, surface the trade-off: every
        D-AUTONOMY-1 A-class action degrades to R-class
        (architect prompt required for everything Producer
        would otherwise auto-do) until the architect provisions
        a DB. The bootstrap completes either way; the friction
        is a feature per ADR-0006's "trade-off explicitly
        registered" note.
  3. **Initial `state.yml` write** — at
     `~/.board-superpowers/repos/<normalized-repo-path>/state.yml`,
     mode inherits the `0700` parent. Fields: `schema_version: 1`,
     `repo_bootstrapped_at: <iso8601>`,
     `last_seen_version_in_repo: <current plugin version>`,
     `features_enabled: [bootstrap.host, bootstrap.per_repo]`,
     `routing_blocks: []` (filled by step 4). The directory
     `~/.board-superpowers/repos/<normalized-repo-path>/` is
     `mkdir -p`'d if absent.
  4. **Dual-file routing injection** — append the canonical
     routing block to **both** `CLAUDE.md` AND `AGENTS.md`. The
     block content is mirrored verbatim from
     `skills/using-board-superpowers/references/claudemd-routing.md`
     between the marker pair `<!-- board-superpowers:routing -->`
     / `<!-- /board-superpowers:routing -->`. If either file
     exists already with content, the block is appended (with one
     blank line of separation); if a file does not exist, it is
     created with just the routing block. After injection, append
     one element to `state.yml:routing_blocks` per file, of shape
     `{ target_file: "<file>", block_hash: "sha256:<hex>",
     injected_at: "<iso8601>" }`. The `block_hash` is SHA256 of
     the injected block (everything between the marker pair,
     excluding the markers themselves) — what F-B4 later uses to
     detect user modifications before auto-updating.
  5. **First-card pointer delivery** — show the architect the
     "what now" surface: how to create their first card via the
     Manager session (or by pasting a card via the GitHub UI and
     bootstrapping the body schema). Loads from
     `references/first-time-user-guide.md`.
- **Composes**: `gh label create`, `gh project view`,
  `gh project field-list`, `python3` for JSON parsing,
  filesystem ops, SHA256 (via `sha256sum` / `shasum -a 256`).
- **Maps to (canonical)**: ADR-0001 substrate commitment;
  XDG-style per-project state under repo root; the dual-file
  injection pattern is dictated by `PLUGIN_DEVELOPMENT.md`
  (Claude Code auto-loads `CLAUDE.md`, Codex CLI auto-loads
  `AGENTS.md`).
- **Original framing**: the **`block_hash` tamper-detection
  field**. Pattern adapted from chezmoi's `run_onchange_` script
  hashing (which uses SHA256 of script content to decide
  re-execution) and from Debian's `dpkg conffile` prompt (which
  detects user-modified config files via stored MD5 to avoid
  silent overwrite on package upgrade). Plain
  diff-and-surface-to-user is the right pattern; we use SHA256
  (vs MD5) because there is no compatibility cost and SHA256 is
  what the rest of the ecosystem uses.
- **Mode compatibility**: both. The dual-file injection means
  the next session lands cleanly regardless of platform; the
  `state.yml` schema is platform-portable.
- **Autonomy**: A for the bootstrap action itself (architect
  invoked it explicitly via the trigger phrase). The R-class
  edits to the routing block content during F-B4 (when an
  upgrade introduces new routing) are governed by §1.5.4.

#### 1.5.3 F-B3. Host version transition

- **Capability**: when `~/.board-superpowers/manifest.yml`
  exists but its `last_seen_version` is older than the current
  plugin version (the version embedded in
  `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`), surface
  the changelog highlights for the new version once and update
  the manifest. F-B3 fires at most once per host per
  (old → new) transition; it does NOT fire for repos (that's
  F-B4).
- **Trigger**: `using-board-superpowers` Step 1 compares the
  manifest's `last_seen_version` to the current
  `plugin.json:version`. Mismatch (older) triggers F-B3.
- **Inputs**: `last_seen_version` from the manifest;
  `plugin.json:version` from the install.
- **Outputs** (in order):
  1. Dependency check via §1.5.0.
  2. Load
     `skills/using-board-superpowers/references/changelog/v<NEW>.md`
     — a hand-curated highlights file (NOT the full GitHub
     release notes; see TBD-Notes for the full-vs-highlights
     rationale). The file is one per version and contains:
     "what's new for the host", "what's new that affects every
     repo", "what to expect when you next visit your existing
     repos" (which transitions to F-B4), "any breaking changes".
  3. Write `last_seen_version: <NEW>` to manifest.yml. Schema
     version migration runs first if `schema_version` is older
     than the current plugin's understanding (lazy-on-read; see
     I-12 and TBD-Notes for the migration-runner placement).
- **Composes**: §1.5.0 dependency check + `plugin.json` parse +
  changelog file lookup + `manifest.yml` rewrite. No `gh`, no
  network.
- **Maps to (canonical)**: `gh extension upgrade` notice (gh
  shows an upgrade banner once per 24h when extensions have new
  versions); `bun upgrade` post-install message; `rustup update`
  channel-version display. The pattern across these tools: brief
  highlights + pointer to full release notes is preferred over
  dumping the full changelog.
- **Original framing**: the **per-version external `references/
  changelog/v<X>.md` file** instead of inlining changelog prose
  into a script. Two reasons: (a) keeps script logic tiny
  (parse manifest, look up file, present); (b) makes the
  changelog reviewable independently in its own PR before
  release tagging. Pattern from `rust-lang/rust/RELEASES.md` —
  release notes are a content artifact, not application logic.
- **Mode compatibility**: both. Same manifest path on both
  platforms; same changelog file consumed.
- **Autonomy**: A for the transition (it's a notification, not
  a state mutation that requires architect approval). Audit-log
  entry written: `host_version_transition`, with old / new
  version + `schema_version` migration result if any.

#### 1.5.4 F-B4. Per-repo version transition

- **Capability**: when
  `~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
  exists but its `last_seen_version_in_repo` is older than the
  current plugin version on this host, surface the
  new-features-this-version list, **default-enable** the new
  repo-side features with an "auto-enabled" notice (architect can
  opt out per-feature), re-inject the routing block if its
  source-of-truth content has changed AND the user did not modify
  the on-disk block (detected via `block_hash` comparison), and
  update `state.yml`. F-B4 fires once per `(host, repo, upgrade)`
  triple, on the first session in that repo on that host after the
  host upgrade.
- **Trigger**: `using-board-superpowers` Step 3 (or the
  preflight piggyback in `managing-board` / `consuming-card`)
  compares `state.yml:last_seen_version_in_repo` to the current
  plugin version. Mismatch triggers F-B4.
- **Inputs**: `state.yml` current contents; `plugin.json:version`;
  the changelog highlights file
  `references/changelog/v<NEW>.md` (re-used from F-B3 — the
  "new for repo" half of that file is what F-B4 surfaces).
- **Outputs** (in order):
  1. Dependency check via §1.5.0.
  2. **`schema_version` migration** if the on-disk
     `state.yml:schema_version` is older than the plugin's
     understanding. Lazy-on-read: the migration runs the first
     time `state.yml` is opened for a write that needs the
     newer fields. Migration steps live at
     `${CLAUDE_PLUGIN_ROOT}/scripts/migrations/state-v<N>-to-v<N+1>.sh`
     and are versioned-and-additive — never destructive.
  3. **New-features list** — read the changelog file's "new for
     repo" section, default-enable each new feature by adding
     its feature_id to `state.yml:features_enabled`. Show the
     architect: "vNEW auto-enabled the following features for
     this repo: [list]. Reply 'opt out: feature_id' for any
     you don't want." Default-enable rationale per P1 (architect
     attention is scarce — opt-out friction-minimizing) and per
     VS Code marketplace-extension pattern (auto-update on by
     default, opt-out per-extension).
  4. **Routing-block re-injection** — for each of `CLAUDE.md`
     and `AGENTS.md`:
     - Read the current on-disk block (between the marker pair).
     - Compute its SHA256.
     - Find the matching `target_file` element in
       `state.yml:routing_blocks` and compare to its `block_hash`.
     - **If hashes match** (block is plugin-pristine): re-inject
       the new source-of-truth block content from
       `references/claudemd-routing.md`, update `block_hash` in
       `state.yml`, log an audit entry. Auto-update; no architect
       prompt.
     - **If hashes differ** (architect modified the block since
       last injection): do NOT auto-update. Surface to the
       architect: "Your <filename> routing block was modified
       since vOLD bootstrap. The new vNEW block adds the
       following: [diff of new-vs-old source-of-truth]. Want me
       to: (a) replace your version (your edits will be lost —
       I can show you a diff first), (b) merge by appending the
       new sections only, (c) leave alone (you'll re-inject by
       hand later)?" Per chezmoi's "file changed since
       chezmoi last wrote it" prompt and Debian's `dpkg conffile`
       3-way prompt — the standard tamper-detection UX.
  5. **Update `state.yml`** — `last_seen_version_in_repo: <NEW>`,
     `features_enabled` reflecting opt-out responses,
     each matching `routing_blocks[]` element updated for files that auto-
     re-injected. If the architect declined every new feature
     and made no other changes, `last_seen_version_in_repo` is
     still updated to current — to suppress the F-B4 prompt on
     every subsequent session for this version.
- **Composes**: §1.5.0 dep check + `state.yml` parse + SHA256
  + diff (line-based diff for the user-modified surface
  prompt) + `references/claudemd-routing.md` source-of-truth
  read + migration-script execution.
- **Maps to (canonical)**: chezmoi `apply` 3-way prompt for
  modified targets; Debian `dpkg --force-confdef` /
  `--force-confold` family of conffile-handling options; VS
  Code marketplace auto-update default-on with opt-out.
- **Original framing**: the **two-axis upgrade dispatch** —
  most tools have either a single per-host changelog (`gh`,
  `rustup`) OR a per-repo migration (database tools like
  Alembic). board-superpowers has both because some changes
  affect every session immediately (F-B3 host-side), and other
  changes need per-repo opt-in or routing-block adjustment
  (F-B4 repo-side). The matrix is original to this
  product-shape.
- **Mode compatibility**: both. Both files (`CLAUDE.md` and
  `AGENTS.md`) get the same hash-and-re-inject treatment.
- **Autonomy**: A for the auto-re-injection path (block
  unmodified — re-applying source-of-truth is the trivial
  default; architect can revert via git). R for the
  user-modified path (architect must choose between replace /
  merge / leave alone — modifying SoT). R for new-feature
  opt-outs (architect explicitly declines per-feature). Audit
  log mandatory for every routing-re-inject and every
  feature-enable / opt-out.

#### 1.5.5 Notes — TBD / open design choices

The bootstrap surface contains five honest-gaps choices that
were resolved during this spec round. Each is recorded here so
the rationale is reviewable when the implementation lands.

- **`block_hash` algorithm: SHA256 raw hex.** Pattern:
  `sha256:<64 lowercase hex chars>`. Rejected alternatives:
  base64 (less greppable in YAML; no compactness benefit at
  this scale), git-blob-style hash (would require running git
  on the file content; SHA256-via-`sha256sum` is one fewer
  dependency). SHA256 is what chezmoi uses for its
  `run_onchange_` script tracking and what Homebrew uses for
  formula download verification — the ecosystem default.
- **Migration runner timing: lazy-on-read.** Migrations fire
  the first time `manifest.yml` or `state.yml` is opened for
  a write that needs the newer fields, NOT eager-on-startup.
  Rationale: Confluent Schema Registry and most NoSQL
  schema-evolution patterns favor lazy migration to avoid a
  startup-time tax on cold sessions. Eager-on-startup would
  block every Claude Code session start by N migration steps;
  lazy-on-read pays the cost only in sessions that actually
  mutate state. Trade-off acknowledged: a long-uninstalled
  state file may take several migrations on first re-touch
  (acceptable — the user invoked the plugin, they are present
  for the migration).
- **F-B3 changelog content: highlights only, link to full
  release notes.** Rationale: `gh extension upgrade`,
  `bun upgrade`, and `rustup update` all surface highlights
  + a link rather than dumping full release notes. Full notes
  are link-fetchable from GitHub at
  `https://github.com/PanQiWei/board-superpowers/releases/tag/v<X>`.
  Inlining the full notes would (a) make the changelog file
  large enough to be skim-bait rather than read material, and
  (b) duplicate content the architect might already have read
  on GitHub.
- **YAML for `manifest.yml` and `state.yml`** to match the
  existing `config.yml` (which is already YAML — see
  `.board-superpowers/config.yml` in this repo). YAML over
  TOML rationale at this scale: `config.yml` is the existing
  precedent and gratuitous format diversity costs more than
  TOML's modest type-safety wins. If a future BSP-side
  decision wants to migrate the lot to TOML for editor
  type-checking benefits, that's a separate decision and
  should be its own ADR.
- **Precise `.gitignore` pattern** for `<repo>/.board-superpowers/`:
  ```
  # board-superpowers local state (claim markers are per-session)
  .board-superpowers/claims/
  ```
  Just the per-session forensic `claims/` subdir is ignored.
  `config.yml` is tracked by default (the parent directory is
  tracked). `state.yml` does **not** live in the repo — it is
  host-local at `~/.board-superpowers/repos/<normalized>/state.yml`
  per I-13, so it does not need a negation line here. Earlier
  belt-and-suspenders `!state.yml` / `!config.yml` lines from
  the v0 spec are removed.

The five resolutions above are not yet ADRs. If implementation
discovers any of them is wrong, the fix is straightforward
(change the algorithm in F-B2 + F-B4 + add a one-time
migration; change the format with a one-time migration; etc.)
— each is local to the bootstrap surface and not load-bearing
for any other surface in this spec.

**Open TBDs that landed in this spec round but did not get
resolved:**

- **F-B1 audit-log handling pre-F-B2.** F-B1 fires before
  F-B2 has configured BYO-RDBMS, so audit-log entries from
  F-B1 (`host_bootstrapped`, `host_intro_delivered`) have no
  destination. Current spec: enqueue to memory, flush when
  F-B2 establishes DB; drop silently if F-B2 declines BYO-
  RDBMS. Open: should the F-B1 entries persist to a temp
  file and be replayed on the first BYO-RDBMS flush in any
  subsequent F-B2 across any repo on this host? The
  forensic-completeness benefit is small at v1; flagged for
  ADR consideration if F-B1 audit becomes load-bearing.
- **`~/.board-superpowers/` vs strict-XDG path
  `~/.local/state/board-superpowers/manifest.yml`.** v1 ships
  at `~/.board-superpowers/` for brevity and convention with
  sibling tools (`gh` lives at `~/.config/gh/`, not strict-
  XDG). If a future user demands strict XDG compliance, the
  migration path is: detect old path, move to new path on
  first F-B3 of the version that flips the default. Flagged
  for v0.x → v1.0 consideration.

