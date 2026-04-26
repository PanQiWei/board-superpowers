## Part 2 — User flows

The flows below are **time-ordered narratives** that compose
features from Part 1. Each flow is what the architect actually
walks through; each step names which features it activates so
reviewers can trace from flow back to feature spec.

Flows are not implementations — they describe what the user sees,
in order. The `Implementing surface` and `Constraining ADR(s)`
columns in Part 3 connect each step to the artifacts that realize
it.

### 2.1 First-time install flow

The architect has neither board-superpowers, superpowers, nor
gstack installed. End state: the architect can open Claude Code
in any repo, say "set up board-superpowers", and F-B1 fires
correctly — followed by F-B2 the moment they touch a real repo.

This flow is a **user-journey narrative**, not a procedural
checklist. It tells you what the architect is thinking at each
step, what they see on screen, what to do when something fails,
and where Claude Code and Codex CLI behavior diverges. Step
numbers are anchors; the prose between them is the contract.

**0. Mental state at the start.** The architect has heard about
board-superpowers (likely via a coworker, a thread on Hacker
News, or this README). What they expect: "let me install three
plugins, point them at a GitHub Project, and start dispatching
work." What they don't yet know: that the plugin layers an
opinionated kanban methodology on top of `superpowers` and
`gstack`, and the first-time intro is what closes that gap. The
intro flow exists to compress "spend 30 min reading docs" into
"see the two-role model in 90 seconds and let me start working".

**1. Install superpowers.** From any Claude Code session:
`/plugin install superpowers@claude-plugins-official`. The
plugin lands in `~/.claude/plugins/cache/.../superpowers/`.
Confirm via `/plugin list` — a row labeled `superpowers` should
appear with its version.
- **Failure recovery — plugin not visible after install.** Most
  often a stale `/plugin list` cache; restart Claude Code (close
  the window, reopen). If still missing, `ls
  ~/.claude/plugins/cache/` to check whether the install actually
  wrote to disk; absence usually means the marketplace name is
  wrong (typo in `claude-plugins-official`).
- **Failure recovery — install errored.** Check authenticated
  state: `/plugin marketplace list` should show
  `claude-plugins-official`; if absent, `/plugin marketplace add
  claude-plugins-official` first.

**2. Install gstack.** `cd ~/.claude/skills && git clone
https://github.com/garrytan/gstack && cd gstack && ./setup`.
Confirm via `/browse --help` in a Claude Code session — gstack's
`/browse` skill should respond with its usage.
- **Failure recovery — `./setup` fails on dependency build.**
  gstack ships a Playwright binary; on first install it may need
  to download the browser. `pnpm` or `npm` errors during this
  step usually mean the runtime version is too old; check the
  setup script's prereqs.
- **Failure recovery — `/browse --help` doesn't respond.** The
  skill loads from `~/.claude/skills/gstack/`; verify with `ls`.
  If present, restart Claude Code.

**3. Install board-superpowers.** `git clone
https://github.com/PanQiWei/board-superpowers
~/.claude/plugins/board-superpowers`, then in a Claude Code
session: `/plugin add local ~/.claude/plugins/board-superpowers`.
(Once the plugin is published to a marketplace per ADR-0007's
distribution contract, this collapses to a `/plugin install`
one-liner — v1 is the clone path.)
- **What the architect sees.** A confirmation that the plugin
  was registered locally; `/plugin list` now shows
  `board-superpowers` alongside `superpowers`. No file under
  `~/.board-superpowers/` exists yet — that's F-B1's job, not
  install's.
- **Failure recovery — clone destination already exists.** If
  the architect tried installing once before and aborted: `rm
  -rf ~/.claude/plugins/board-superpowers` then re-clone.

**4. First trigger — open Claude Code in any repo, say "set up
board-superpowers".** The `using-board-superpowers` skill fires.
What happens, in order:

  - **Layer 2 dependency check (§1.5.0)** runs first. If
    superpowers or gstack is missing, the skill stops with a
    verbatim banner naming the missing dep and what to do
    (re-run step 1 or 2). This is the reliable gate; the
    SessionStart hook (Layer 1) may have already shown a banner
    on session start, but Layer 2 is the one that actually
    blocks progress.
  - **Manifest check.** The skill stats
    `~/.board-superpowers/manifest.yml`. Absent → **F-B1
    fires**. (F-B1 narrative inline below; F-B3 / F-B4
    upgrade-time variants are §2.3.)
  - **F-B1 runs.** Creates `~/.board-superpowers/` (mode 0700),
    writes `manifest.yml` with `schema_version: 1`,
    `host_bootstrapped_at: <iso8601>`, `last_seen_version:
    <plugin version>`. Then loads
    `references/intro.md` and walks the architect through the
    two-role model + the morning-of-day-1 happy path. **The
    architect can ask questions** during this walk-through —
    intro.md is intentionally paused at section breaks, not
    monologued. Expected duration: 90 seconds to 5 minutes
    depending on how chatty the architect is.

**5. Hand-off to F-B2.** F-B1 ends by checking whether
`~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
exists for the current repo on this host. Absent (the common
case for a brand-new install) → **F-B2 fires**. Flow continues
into §2.2.

**6. Verification.** After F-B2 completes (next section), the
architect can prompt their next session ("what should I work
on?" / "morning briefing") and the `managing-board` skill
takes over, routing per the injected `CLAUDE.md` / `AGENTS.md`
block. If the architect instead opens a NEW Claude Code session
(closing the first one), F-B1 does NOT re-fire (manifest exists),
F-B2 does NOT re-fire (state.yml exists), and the routing block
in `CLAUDE.md` / `AGENTS.md` directly carries the session into
Manager or Consumer mode based on the first prompt.

**Codex CLI parity.** Steps 1–3 differ on Codex CLI:

  - **Step 1 (superpowers on Codex)** — install via Codex's
    plugin marketplace; consult Codex's plugin docs (per
    `PLUGIN_DEVELOPMENT.md`). The board-superpowers v1 ship
    target is Claude Code; Codex parity is on the dual-platform
    commitment but the install commands above are CC-specific.
  - **Step 2 (gstack on Codex)** — gstack supports Codex via its
    own setup path; check gstack's README.
  - **Step 3 (board-superpowers on Codex)** — `git clone` to a
    Codex-discoverable plugin path, then register via `codex
    plugin marketplace add` (per `PLUGIN_DEVELOPMENT.md`'s
    Codex section). The local-marketplace approach (a
    `marketplace.json` listing the plugin via `"source":
    {"source": "local", "path": "./..."}`) is the canonical
    Codex local-install path.
  - **Step 4 (the "set up board-superpowers" trigger)** —
    identical on Codex once the plugin is registered. The skill
    description matches against the user prompt the same way
    on both platforms; F-B1 fires identically; F-B2 reads the
    same host-local
    `~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
    (the per-host directory works on both platforms).

**Why this flow exists in this shape.** The 4-step install is
the minimum viable surface. Two reasons it cannot collapse to
a single command:
1. Two upstream plugins (`superpowers` and `gstack`) are
   independently maintained and live in separate marketplaces;
   their install paths are not under board-superpowers' control.
2. Local-clone install for board-superpowers itself reflects
   v1's pre-marketplace status — once published, step 3
   collapses to one line, and this entire flow becomes a
   2-step experience.

- **Features activated**: §1.5.0 (dependency check Layer 1 +
  Layer 2 on step 4), F-B1 (host bootstrap, on first prompt
  in step 4), then F-B2 (per-repo bootstrap, on the same
  session if the repo has no state.yml — flows into §2.2).
- **Constraining ADRs**: ADR-0007 (plugin-form constraints —
  no daemon, no network call after install, per P5);
  `PLUGIN_DEVELOPMENT.md` Codex / Claude Code parity rules.

### 2.2 Per-project bootstrap flow

The architect has the plugins installed (F-B1 has run; the host
manifest exists) but no
`~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
exists for this repo on this host. End state: the repo is fully
configured — labels, validated Status field, `config.yml`
written and tracked in git, gitignore entry in place,
host-local `state.yml` written outside the repo, routing block
injected into both `CLAUDE.md` and `AGENTS.md` with their
SHA256s recorded in the host-local `state.yml` — and the
architect can dispatch Manager / Consumer sessions in the next
Claude Code or Codex CLI session in this repo.

This is a **user-journey narrative**, not a script wrapper. F-B2
is the longest single interaction in board-superpowers' lifecycle
(typical 5–15 minutes for a first-time architect). The narrative
below covers what the architect is thinking at each step, the
five micro-decisions about BYO-RDBMS, what they see when things
go wrong, and what the `block_hash` mechanism is doing under the
hood.

**0. Mental state at the start.** The architect just finished
the §2.1 install flow OR has done F-B1 in the past on a different
repo and is now using board-superpowers in a new project for the
first time. They have an existing repo on disk and they're
opening Claude Code at the project root. They expect: "set this
project up so I can start dispatching Consumers". They don't
yet expect: a Project v2 creation step that they have to do in
the GitHub UI. The flow's first job is to set that expectation
clearly.

**1. The Project v2 creation gate (manual UI step, not
scriptable).** When the architect says "set up board-superpowers"
and F-B2 fires, the very first thing the skill does after
preflight is **stop and ask**: "Do you have a GitHub Project v2
already created for this repo, with a `Status` single-select
field containing exactly these six options in this order:
`Backlog → Ready → In Progress → In Review → Done → Blocked`?"
- **Why it can't be scripted.** Per ADR-0001 substrate-commitment
  pragmatics, Project v2 single-select option creation via the
  GraphQL API is unreliable with standard PATs (the API
  succeeds intermittently and the UI does not always reflect
  the state for several minutes). The substrate is GitHub
  Project v2; the substrate is partly UI-only at this layer.
  This is one of two manual steps in the entire plugin (the
  other is F-B1 install in §2.1).
- **What the architect sees if they say "no, I haven't created
  it"**. The skill walks them through the UI:
  1. Open `https://github.com/orgs/<OWNER>/projects/new`
     (or the user variant for personal repos).
  2. Choose "Board" template.
  3. Add the repo to the project.
  4. Add a single-select field named `Status` (or rename the
     default field — but the name `Status` is the contract).
  5. Add the six options in the canonical order. **Order
     matters.** The bootstrap script validates the order, not
     just presence (per §1.5.2 F-B2 sub-capability 2).
  6. Note the project's URL — the architect will need
     `OWNER/NUMBER` (e.g. `acme/3`) at step 2 below.
- **What the architect sees if they say "yes"**. Skill asks
  them to paste `OWNER/NUMBER` and continues.

**2. Architect supplies `OWNER/NUMBER`.** Skill confirms by
running `gh project view <OWNER/NUMBER>` to validate that the
project actually exists and is reachable from the architect's
authenticated `gh` session. If the project is private and the
token lacks scope, surface a remediation hint immediately — do
not wait for `bootstrap-project.sh` to fail with a less
actionable message.

**3. `bootstrap-project.sh` runs the five sub-capabilities** (per
§1.5.2 F-B2 step 2). The architect sees one progress line per
sub-step. Common failure modes worth narrating in detail:

  - **Status field validation failures.** Three flavors:
    - **Option misnamed.** The architect created options like
      `Backlog`, `Ready`, `In progress` (lowercase 'p') — the
      validator reports the diff: "Found `In progress`, expected
      `In Progress`". Architect fixes in UI, re-runs.
    - **Wrong order.** Architect created the six options but in
      a different sequence (e.g., `Done` before `In Review`).
      The validator reports the actual sequence and the
      expected sequence. Order matters because the project's
      board view shows columns in option-creation order, and
      downstream skills (Daily routine, Triage) assume the
      canonical left-to-right reading.
    - **Missing options.** Architect forgot `Blocked` (common —
      it's the rightmost). Validator names the missing
      option(s).

  - **Label conflicts.** Pre-existing labels named
    `type:feature` etc. with different colors are skipped, not
    overwritten — board-superpowers does not assert color
    ownership. Real failures (token-scope problems) abort.

  - **Sub-capability 5: the BYO-RDBMS conversation.** The most
    interesting decision point in F-B2. The architect makes
    five micro-decisions; the skill walks them through each:

    1. **Do I have a Postgres or MySQL instance available?**
       If no → choose "skip for now" and continue with degraded
       Producer autonomy (every A-class action becomes R-class
       — see ADR-0006 §5). Bootstrap completes; the BYO-RDBMS
       step can be re-run later via `using-board-superpowers`
       once the architect provisions a DB.
    2. **Does my company allow audit logs to land in our
       production DB?** Many enterprise environments forbid
       coupling app tooling to prod. If "no", the architect
       provisions a separate small DB instance (e.g., a Fly.io
       Postgres single-instance, a local Docker postgres, an
       AWS RDS small tier).
    3. **Per-project schema or one shared schema across
       projects?** v1 ships with one `audit_log` table per
       schema; per-project schemas are the simpler default.
       Shared schema requires the architect to namespace
       project IDs themselves (the `audit_log` table has a
       `project` column; collisions are the architect's
       responsibility).
    4. **Run degraded for now and come back?** Acceptable.
       Bootstrap proceeds; F-B2 marks `audit.degraded: true`
       in `state.yml`'s upcoming `features_enabled` list.
       Later, the architect can come back, provision the DB,
       and re-run — the skill detects `audit.degraded` and
       offers to re-attempt the credential check.
    5. **What if the DB later goes down mid-session?** Producer
       degrades to R-class for the duration of the outage
       (per ADR-0006 §5's "trade-off explicitly registered"
       note). Audit-log writes buffer in memory until the DB
       is back; on persistent failure, Producer surfaces and
       suspends. There is no on-disk audit-log fallback —
       SQLite / local files are explicitly forbidden per
       ADR-0006 §5 because the BYO-RDBMS contract is the
       enforcement mechanism.

**4. Initial `state.yml` write** (per §1.5.2 F-B2 step 3). Skill
writes to
`~/.board-superpowers/repos/<normalized-repo-path>/state.yml`
(`mkdir -p` the parent if absent — the file is host-local, never
in git):
```yaml
schema_version: 1
repo_bootstrapped_at: "2026-04-26T11:00:00Z"
last_seen_version_in_repo: "0.1.0"
features_enabled:
  - bootstrap.host
  - bootstrap.per_repo
routing_blocks: []    # filled in step 5
```

**5. Dual-file routing block injection** (per §1.5.2 F-B2
step 4). Skill reads
`skills/using-board-superpowers/references/agentsmd-routing.md`,
extracts the fenced block, and appends it to both `CLAUDE.md`
AND `AGENTS.md`. If a file does not exist, it is created with
just the routing block. After injection, the skill computes
`SHA256(<everything between the marker pair, excluding markers
themselves>)` and appends one element per file to
`state.yml:routing_blocks`:

```yaml
routing_blocks:
  - target_file: "CLAUDE.md"
    block_hash: "sha256:a3f8...64hex..."
    injected_at: "2026-04-26T11:00:01Z"
  - target_file: "AGENTS.md"
    block_hash: "sha256:a3f8...64hex..."
    injected_at: "2026-04-26T11:00:01Z"
```

- **Why `block_hash` exists.** Plugin upgrades may want to
  re-inject an updated routing block when the source-of-truth
  in `agentsmd-routing.md` evolves (F-B4). The plugin has to
  decide: "did the architect modify the on-disk block since I
  last wrote it?" The `block_hash` is the answer — at F-B4
  time, recompute SHA256 of the on-disk block and compare. If
  hashes match → user has not modified; safe to auto-update.
  If hashes differ → user has modified; surface the conflict
  for a 3-way decision (replace / merge / leave alone) instead
  of silently overwriting.
- **What the architect sees**. Nothing visible about the hash
  itself at F-B2 — it lands in `state.yml` and is invisible
  until F-B4 surfaces a conflict. The architect just sees
  "routing block injected into CLAUDE.md and AGENTS.md".

**6. Two scaffolding commits.** Per `README.md`. Skill suggests
the two-commit split so the architect can review each cleanly:
```
chore: bootstrap board-superpowers
chore: add board-superpowers routing to CLAUDE.md
```
`config.yml` and `.gitignore` updates land in the first commit;
`CLAUDE.md` and `AGENTS.md` routing blocks land in the second.
`state.yml` is host-local (`~/.board-superpowers/repos/<normalized>/`)
and is **not** part of either commit. Skill leaves the actual
`git commit` to the architect — bootstrap does not commit on the
architect's behalf, in keeping with the I-2 / I-11 plugin-vs-user
split.

**7. First-card pointer.** Per §1.5.2 F-B2 step 5. Skill loads
`skills/using-board-superpowers/references/first-time-user-guide.md`
and walks the architect through what to do next:
- **Option A**: Open a Manager session and say "what should I
  work on?" — Manager will report an empty board and walk
  the architect through creating their first card via the
  intake flow (§2.5).
- **Option B**: Use the GitHub UI to create one or two cards
  by hand (filling in the schema per
  `decomposing-into-milestones/references/card-schema.md`),
  then dispatch a Consumer.
- **Option C**: Bring an existing requirement to Manager
  ("I want to refactor X") and let the intake → decomposition
  flow create the first cards.

The first-time-user-guide is paused at section breaks — the
architect reads, asks questions, and gets a clear picture of
the two-role model before any actual board work begins. This
is the second half of intro.md's job (the first half ran
during F-B1).

**Codex CLI parity.** Step 5's dual-file injection is the
centerpiece of cross-platform support. On a host where the
architect uses both Claude Code and Codex CLI, both files
get the block; both platforms therefore route correctly. The
`<!-- board-superpowers:routing -->` marker pair is
identical in both files; `check-deps.sh` matches in either.

- **Features activated**: §1.5.0 (dep check), F-B2 (per-repo
  bootstrap, end-to-end).
- **Constraining ADRs**: ADR-0001 (Project v2 manual creation
  — substrate commitment), ADR-0006 §5 (BYO RDBMS audit log
  setup at this step).

### 2.3 Plugin upgrade flow (host + per-repo)

The architect upgraded the board-superpowers plugin since their
last session. End state: the host manifest reflects the new
version (F-B3 fired once), every previously-bootstrapped repo
gets the new repo-side features default-enabled with an
"auto-enabled" notice and an opt-out prompt (F-B4 fires once
per repo on first re-visit), and any routing-block content
changes get auto-re-injected (where the architect did not
modify the on-disk block) or surfaced for manual decision
(where they did).

This is a **user-journey narrative** for scenarios D and E from
the §1.5 matrix. F-B3 fires on the upgraded host; F-B4 fires
later, lazily, the next time the architect visits each
previously-bootstrapped repo.

**0. Mental state at the start.** The architect runs `cd
~/.claude/plugins/board-superpowers && git pull` (or, post-
marketplace publication, `/plugin upgrade board-superpowers`)
because they saw a release notification or because they want a
new feature mentioned in the changelog. They restart Claude
Code so the plugin reloads. They do NOT yet expect anything
new to surface — they're about to open Claude Code in some
arbitrary repo to do their morning work. The flow's first job
is to make the version transition visible without being
obtrusive.

**1. First Claude Code session post-upgrade.** Architect opens
a session in any repo. They prompt as usual ("what should I
work on?" or whatever their morning trigger is). The
`using-board-superpowers` skill's Layer 2 preflight runs first:

  - Dependency check (§1.5.0) — passes (deps unchanged).
  - **Manifest version check.** Reads
    `~/.board-superpowers/manifest.yml:last_seen_version`,
    compares to current `plugin.json:version`. If older →
    **F-B3 fires** before any other behavior.

**2. F-B3 surfaces the changelog highlights** (per §1.5.3 F-B3
step 2). What the architect sees, in this shape:

```
board-superpowers v0.1.0 → v0.2.0
─────────────────────────────────────

What's new for the host (this machine):
  • <highlight 1>
  • <highlight 2>

What's new for every repo:
  • F-B4 will fire on the first session in each
    previously-bootstrapped repo to surface these:
    - <repo-side feature 1>
    - <repo-side feature 2>

What to expect when you next visit your existing repos:
  • <count> repos on your machine were bootstrapped on v0.1.0;
    each will get an F-B4 prompt the next time you open it.
  • Routing blocks were updated in this version; F-B4 will
    auto-re-inject in any repo where you have not modified the
    on-disk block since bootstrap. Where you have modified
    your block, F-B4 will surface a 3-way diff.

Breaking changes:
  • (none in this release)

Full release notes: https://github.com/PanQiWei/board-superpowers/releases/tag/v0.2.0
```

The content is loaded from
`skills/using-board-superpowers/references/changelog/v0.2.0.md`
— a hand-curated highlights file that the maintainer authors
in the same PR as the release tag. Highlights, not full
release notes (see TBD-Notes for the rationale).

**3. Architect reads, asks questions, then continues.** They
might ask "what does <highlight 1> mean for me?" — the skill
answers from the changelog file's prose, not from generated
text. They might ask "do I have to do anything now?" — the
answer is no; F-B4 happens lazily when they next visit each
repo.

**4. Manifest update.** F-B3 ends by writing `last_seen_version:
0.2.0` to `~/.board-superpowers/manifest.yml` and an audit-log
entry `host_version_transition` (assuming BYO-RDBMS is
configured in any repo on the host — F-B3 enqueues the entry
to the next-flushed audit-log). On subsequent sessions, the
manifest version matches the plugin version → F-B3 does not
re-fire.

**5. Architect's normal session continues.** Manager / Consumer
behavior is whatever the new plugin version provides. F-B3 was
a one-time speed bump; the rest of the session looks normal.

---

**Hours / days later: architect opens an existing repo
(scenario E variant).** Architect `cd`s into a previously-
bootstrapped repo, opens Claude Code, prompts as usual.

**6. F-B4 fires on first session in this repo on this host
post-upgrade.** Layer 2 preflight reads
`~/.board-superpowers/repos/<normalized-repo-path>/state.yml`'s
`last_seen_version_in_repo`, compares to current plugin
version. Older → **F-B4 fires**.

**7. F-B4 sub-flow A: schema migration (if needed).** Per §1.5.4
F-B4 step 2. If `state.yml:schema_version` is older than the
plugin's understanding, run migrations from
`${CLAUDE_PLUGIN_ROOT}/scripts/migrations/state-v<N>-to-v<N+1>.sh`
in sequence, lazily-on-read. The architect sees a brief note:
"Migrating state.yml from schema v<N> to v<M>" with each step.
Migrations are versioned-and-additive (per I-12) — they only
add fields, never destroy. Architect doesn't have to do
anything; the migration is automatic.

**8. F-B4 sub-flow B: new-features list.** Per §1.5.4 F-B4
step 3. Skill loads the changelog file's "new for repo"
section, default-enables each new feature by appending its
feature_id to `state.yml:features_enabled`, and surfaces:

```
This repo was bootstrapped on v0.1.0; you upgraded to v0.2.0.
The following repo-side features are auto-enabled:

  ✓ <feature_id 1>: <one-line description>
  ✓ <feature_id 2>: <one-line description>
  ✓ <feature_id 3>: <one-line description>

Reply 'opt out: <feature_id>' for any you don't want, or
just continue if you're happy with all of them.
```

The architect reads, may opt out of one or more, then
continues. Default-enable rationale per P1 (architect attention
is scarce — opt-out is friction-minimizing) and per VS Code
marketplace convention (auto-update on by default, opt-out
per-extension).

**9. F-B4 sub-flow C: routing-block re-injection.** Per §1.5.4
F-B4 step 4. For each of `CLAUDE.md` and `AGENTS.md`:

  - Read on-disk block between the marker pair.
  - Compute SHA256.
  - Find the matching `target_file` element in
    `state.yml:routing_blocks` and compare its `block_hash`.

**Case 1: hashes match (block is plugin-pristine).** Skill
auto-re-injects the new source-of-truth block content from
`references/agentsmd-routing.md`, updates `block_hash` in
`state.yml`, writes an audit-log entry. Architect sees:

```
✓ CLAUDE.md routing block auto-updated (was unmodified).
✓ AGENTS.md routing block auto-updated (was unmodified).
```

**Case 2: hashes differ (architect modified the block).**
Skill does NOT auto-update. Surfaces:

```
⚠ Your CLAUDE.md routing block was modified since v0.1.0
  bootstrap. The new v0.2.0 block adds the following sections:

    + ## board-superpowers cross-platform routing
    + - When unsure, invoke `using-board-superpowers` first
    [diff snippet showing what's new in source-of-truth]

  How would you like to handle this?

  (a) Replace your version with the new block. Your edits
      will be lost — I can show you a full diff first if you
      want to copy them out.
  (b) Merge by appending the new sections only. Your existing
      block stays, the new content gets appended above the
      </routing> closing marker.
  (c) Leave alone. I'll just record the new source-of-truth
      hash so you don't see this prompt again until the next
      version bump. You'll re-inject by hand later.
```

This is the chezmoi `apply` 3-way prompt UX, adapted to
markdown blocks. Pattern is mainstream (chezmoi + Debian dpkg
conffile + apt-get conffile flags all use a variant of
"replace / merge / leave"); board-superpowers inherits it.

**10. F-B4 sub-flow D: state.yml update.** Skill writes
`last_seen_version_in_repo: 0.2.0` to `state.yml`,
`features_enabled` reflecting opt-out responses,
each matching `routing_blocks[]` element updated for files that
auto-re-injected (case 1) or that the architect chose option
(a) or (b) on (case 2). For files where the architect chose
option (c), the `block_hash` is updated to the new
source-of-truth hash so the prompt does not re-fire on the
next session — but the on-disk block stays as the architect
modified it.

**11. The "decline everything" suppression.** What if the
architect declines every new feature AND chooses option (c) on
both routing blocks? `last_seen_version_in_repo` is still
updated to current. This is intentional — the architect
explicitly engaged with the upgrade prompt; re-prompting on
every subsequent session for the same version would be
hostile. The audit-log entry records "F-B4 declined all
features and routing changes for v0.2.0", and the next
upgrade event (when the architect goes from v0.2.0 to v0.3.0)
will surface its own F-B4.

**12. Architect's session continues.** Like F-B3, F-B4 is a
one-time speed bump per repo per upgrade. The next session in
this repo does not re-fire F-B4 (state.yml version matches
plugin version).

**Codex CLI parity.** Identical on Codex once the manifest +
state files exist. Both files (`CLAUDE.md` and `AGENTS.md`)
get the same hash-and-re-inject treatment regardless of which
platform the architect is running.

**Cross-cut: when the architect declines a routing-block
update.** They retain full ownership of their on-disk block.
The plugin's compatibility contract is: the routing block
SHOULD direct the model to invoke `using-board-superpowers`
and route Manager / Consumer. If the architect's customized
block stops doing that (e.g., they removed the routing
language entirely while keeping the markers), the next
session's `using-board-superpowers` Step 1 will still fire
correctly (Layer 2 reads `check-deps.sh` and the marker pair,
not the block content). But routing of Manager / Consumer via
the first-message check happens via the routing block's
prose — if the architect deleted that prose, they have
deleted that routing. F-B4 surfaces this trade-off when it
detects user modification (the (a)/(b)/(c) prompt makes the
divergence explicit).

- **Features activated**: F-B3 (host transition, fires once
  per host upgrade), F-B4 (per-repo transition, fires once
  per repo per upgrade), §1.5.0 (dep check throughout).
- **Constraining ADRs**: ADR-0006 (row 4 — modifies SoT;
  routing-block re-injection in case-2 path); ADR-0007
  (preflight piggyback for the version mismatch detection).

### 2.4 Daily Manager flow

A typical architect day. The architect opens a Manager session
in the morning, dispatches work, monitors the Review Queue
through the day, and dispatches more in the evening. The
Manager session is long-lived (one per project per day);
Consumer sessions are spawned as needed.

1. **Morning trigger.** Architect opens Manager session: "what
   should I work on?" or "morning briefing". The
   `managing-board` skill fires.
2. **Preflight piggyback runs (per ADR-0007).** Manager runs
   `check-deps.sh` (just-in-time re-check, Layer 3 of the
   alert strategy), then the lightweight situation-awareness
   check: stale session detection (F-11), cadence check (is
   retro / weekly report due?), health degradation, completed
   Consumers since last prompt. Results land at the top of
   Manager's response (e.g. "Preflight: 2 PRs ready for
   verification, 1 stale claim from overnight").
3. **Daily routine fires (`managing-board/references/daily-routine.md`).**
   Manager renders the fixed-template board snapshot: NEEDS
   YOU FIRST (open PRs awaiting verification — F-02), IN
   FLIGHT (cards a Consumer is working on — F-03), BLOCKED
   (F-03 + F-10), READY TO DISPATCH (F-04), with WIP budget
   reported. Recommends one thing per the priority order in
   the routine (PRs first → stale claims → WIP at limit →
   dispatch).
4. **Architect verifies open PRs and merges.** Per I-2,
   architect (not Consumer) does the merge. Each merged PR
   triggers GitHub auto-close on its `Closes #<N>` line; the
   project automation moves the card to Done.
5. **Architect dispatches new Consumers.** Manager generates
   kick-off prompts (F-04 → F-07 area; the "one artifact
   Manager uniquely produces" per `managing-board/SKILL.md`).
   Architect opens N fresh terminals (one per dispatch),
   pastes the kick-off, walks away. Each terminal is a
   Mode-1 Consumer session (per §1.4 mode topology); the
   architect could alternatively let Manager spawn Mode-2
   Consumers via the CC `Agent` tool — see §2.6 for the
   Mode-1/Mode-2 channel divergence.
6. **Midday: PRs return, architect re-prompts Manager.**
   "what needs me?" — Manager re-runs preflight, surfaces
   newly opened PRs, ordered (F-02). Architect verifies,
   merges, dispatches the next wave.
7. **Evening: end-of-day overnight batch.** "I'm leaving,
   dispatch overnight" → Manager runs F-07 (overnight batch
   dispatch). Architect approves the queue (Consumer
   dispatches are A per matrix row 13 but the *batch* itself
   is a deliberate architect-initiated decision); Manager
   queues N cards under controlled concurrency (per
   C-PLUGIN-3, default = 1 serial). Audit-log entries
   accumulate to the BYO RDBMS overnight; the morning
   preflight (back to step 2) surfaces the results.
- **Features activated**: F-01, F-02, F-03, F-04, F-05, F-06,
  F-07, F-11; preflight piggyback idiom throughout.
- **Constraining ADRs**: ADR-0006 (matrix rows 13, 14),
  ADR-0007 (preflight piggyback).

### 2.5 New requirement intake flow

Architect has an idea or a stakeholder request that doesn't
yet exist on the board. End state: the requirement is
decomposed into INVEST-compliant cards in Backlog, ready for
the architect to promote individually to Ready.

1. **Architect tells Manager.** "I have a new requirement:
   <one-paragraph description>" or "I want to refactor X".
   The `managing-board` skill routes to the Intake routine
   (`references/intake-routine.md`).
2. **F-08 — Interactive intake & design routing.** Manager
   does **not** jump to decomposition. It evaluates the
   shape of the requirement (greenfield idea vs.
   architectural refactor vs. small feature add) and routes
   to a design skill:
   - `gstack:/office-hours` for "is this worth building"
     framing.
   - `gstack:/plan-eng-review` for architecture-locking
     decisions.
   - `superpowers:brainstorming` for a Socratic requirement-
     and-design refinement.
   - `superpowers:writing-plans` to convert the design output
     into an executable plan once the design conversation
     settles.
   Per AGENTS.md / CLAUDE.md routing rules, the choice
   depends on the requirement's shape; `managing-board/SKILL.md`
   tells the architect "this sounds like a design
   conversation, not a board-management one — pick one".
3. **Architect runs the chosen design skill.** This usually
   takes a separate session (the Manager is for board
   orchestration, not for the design conversation itself —
   per `managing-board/SKILL.md`'s "Design-level thinking —
   delegate, don't do it"). Output: a design doc / plan at a
   well-known path (e.g.
   `docs/superpowers/specs/<date>-<topic>-design.md`).
4. **Architect returns to Manager: "decompose this".**
   Manager hands off to the
   `decomposing-into-milestones` skill (F-09).
5. **F-09 — Decomposition into cards.** Per
   `decomposing-into-milestones/SKILL.md`, runs the 7-step
   procedure: identify capabilities (confirmed with
   architect), order by dependency (confirmed), slice each
   capability vertically (confirmed per slice), draft each
   card body (per §1.6.3 schema), review the set with the
   architect, push to the board via
   `scripts/create-card.sh`. All cards land in **Backlog**,
   never `Ready` — the Backlog → Ready promotion is the
   architect's separate confirmation that the card is
   actionable now.
6. **Manager reports back.** "N cards created in Backlog:
   #X–#Y. Promote to Ready when you want, and I can
   generate kick-off prompts." Architect promotes
   selectively; promoted cards now appear in tomorrow's
   Daily routine under READY TO DISPATCH.
- **Features activated**: F-08 → F-09; §1.6 (all four
  decomposition rules at draft time).
- **Constraining ADRs**: ADR-0006 row 1 (create cards = A) +
  row 5 (Backlog → Ready transition = A; precondition is
  schema completeness — see §1.6.3).

### 2.6 Card consumption flow (Manager-dispatched)

The canonical implementation flow. Architect has dispatched a
Consumer on a specific card; Consumer runs through the F-C0–
F-C14 lifecycle and delivers a PR. Two channel variants —
Mode-1 (architect-spawned interactive terminal) and Mode-2
(Producer-spawned CC subagent) — diverge at surface points
(F-C8) and at termination (F-C14 wake-up).

**Common path (Mode-1 and Mode-2 identical):**

1. **Kick-off.** Either the architect pastes Manager's
   kick-off prompt into a fresh terminal (Mode-1), or
   Manager spawns Consumer via the CC `Agent` tool (Mode-2).
   First message contains `[board-card:#N]`. The
   `consuming-card` skill fires.
2. **Preflight (F-C2 area + Layer 3 dep re-check).** Consumer
   runs `check-deps.sh`, invokes `board-protocol`, fetches
   the card (`gh issue view <N>`), validates schema (marker +
   required sections), checks dependencies (each `Depends on
   #D` is closed and merged).
3. **F-C1 — Atomic claim.** Consumer derives the slug from
   the card title (≤40 chars per `board-protocol`), runs
   `claim-card.sh`. On success, parses two stdout lines
   (`branch=` and `worktree=`). On exit `10` (race lost),
   stops cleanly and reports who won. On exit `20` / `30`,
   surfaces the error and stops.
4. **F-C3 — Worktree entry + In Progress transition.**
   `cd "$WORKTREE"`. Runs `transition-card.sh --to "In
   Progress"`. Posts the first card-thread comment with
   session slug, branch, worktree path.
5. **F-C2 — Spec / plan / acceptance-criteria fetch.**
   Builds the plan brief at
   `docs/board-superpowers/plans/card-<N>.md` (gitignored;
   Consumer scratch). Follows the thin-pointer convention
   (per §1.6.3) to load any linked spec doc.
6. **F-C4 — TDD-driven implementation delegation.** Per the
   handoff matrix, picks the execution skill: default
   `superpowers:subagent-driven-development`; fallback
   `superpowers:executing-plans` (Mode-2 caveat: subagent
   spawning may violate `max_depth=1` — fallback applies);
   UI / visual cards take the
   `gstack:/review` + `gstack:/qa` path. Execution skill
   owns RED-GREEN-REFACTOR; Consumer strictly executes.
   F-C5 (TDD-skip) governs whether RED-GREEN runs at all.
7. **F-C7 — Permission boundary** runs continuously
   throughout step 6: soft default for engineer-norm
   actions, ambiguity fallback surfaces (F-C8) when
   uncertain, hard floor blocks forbidden ops (no force-push
   to main, no commit of secrets, no `rm -rf` outside
   worktree).
8. **F-C6 — Cross-card touch hard refuse** fires if the
   execution skill tries to write a file owned by another
   card. Surface (F-C8), transition to Blocked (F-C13).
9. **F-C9 + F-C10 + F-C11 — Pre-submit verification chain.**
   `superpowers:verification-before-completion` →
   `superpowers:requesting-code-review` → `gstack:/review`
   (F-C9). `gstack:/codex` for cross-platform adversarial
   review (F-C10, attribution recorded in PR body).
   Conditional UI / security passes (F-C11).
10. **F-C12 — PR submission with mandatory sections.** Opens
    PR via `superpowers:finishing-a-development-branch` (or
    `gstack:/ship`). Appends the protocol-required sections
    (per §1.8): Automated Verification (required), Human
    Verification TODO (optional — omit cleanly if
    low-risk), Retro Notes (knowledge-harvesting). Card
    transitions to In Review.
11. **F-C13 — Review-cycle response.** Same Consumer
    instance stays alive through merge. Each review comment
    triggers a response cycle: re-delegate to F-C4 for
    non-trivial fixes, re-run F-C9/F-C10/F-C11 for
    verification, post reply comments. Stakeholder
    comments (PM / designer / customer) default
    integrate-as-context; surface (F-C8) when scope expansion
    is implied.
12. **F-C14 — Termination.** Success path: PR merges, GH
    auto-closes the issue, project automation moves card to
    Done; Consumer writes the post-merge supplement to
    Retro Notes; self-deletes worktree (`git worktree remove
    --force`); process exits. Failure path: card → Blocked,
    failure-context comment, claim released, **worktree
    KEPT** for human takeover; process exits.

**Mode-1 vs Mode-2 channel divergence:**

- **F-C8 (surface protocol)**: Mode-1 surfaces via terminal
  stdout (architect responds in the same terminal). Mode-2
  surfaces via card-thread comment (board-mediated, the
  primary contract); CC `SendMessage` MAY be used as an
  optional latency-optimization signal to the Producer but
  is never load-bearing.
- **F-C14 wake-up sub-flow** (Mode-2 only): Consumer
  suspended via F-C8 → Producer's preflight piggyback
  detects the surface (next architect prompt to Manager) →
  Producer reports "Consumer #N is waiting on decision X"
  → architect responds → Producer wakes the Mode-2 Consumer
  via `SendMessage` (per ADR-0006 row 13 with Mode-2 caveat).
  Architect can override to require manual approval before
  every wake-up via `autonomy_overrides:`.

**Suspended / wake-up sub-flow (Mode-2):** Consumer hits an
F-C8 trigger (e.g., spec contradiction). Posts card-thread
comment, exits the active reasoning loop, becomes "logically
suspended" — the CC subagent process is technically still
alive but waiting for `SendMessage`. Architect prompts
Manager hours later. Manager's preflight piggyback finds the
new card-thread comment, surfaces it as "Consumer #N is
waiting on decision X — last surfaced 4h ago". Architect
responds to Manager. Manager (per matrix row 13) wakes the
Consumer via `SendMessage` with the architect's decision.
Consumer resumes inside its persisted worktree (per I-7,
worktree persists across suspend cycles), continues lifecycle.

- **Features activated**: F-C0 (manual-pull only — see §2.7),
  F-C1, F-C2, F-C3, F-C4, F-C5, F-C6, F-C7, F-C8, F-C9,
  F-C10, F-C11, F-C12, F-C13, F-C14.
- **Constraining ADRs**: ADR-0002 (claim via push), ADR-0003
  (worktree per Consumer), ADR-0004 (composition over
  reimpl — every delegated skill), ADR-0006 (rows 6, 8, 12,
  13), ADR-0007 (Mode-2 wake-up via preflight piggyback).

### 2.7 Card consumption flow (manual pull, no Manager)

The bypass path. Architect skips the Manager session entirely
for a single-card pull — appropriate when the architect knows
they want one card from Ready, the dispatch ceremony is
overhead, and the Manager's daily-briefing context-load is
unnecessary.

1. **Architect opens a fresh Claude Code session in the
   project directory.** Says "pull a card from the board" or
   "start on the board card" (no `#N` named). The
   `consuming-card` skill fires.
2. **F-C0 — Self-selection from Ready.** Per the
   `consuming-card/SKILL.md` Step 0 contract: query Ready
   cards (never Backlog), filter by deps satisfied + size
   hint (if any) + oldest-first among ties, surface top 3
   candidates, **wait for one-shot architect confirmation**.
   Hard rule: do not silently pick. On `none`, session ends
   cleanly with no side effects.
3. **Architect picks a number.** Card number now bound to
   `N`; flow continues into F-C1 (atomic claim) and the
   common path documented in §2.6 from step 3 onward.
4. **No Manager session is involved.** The Daily routine
   does not run; the kick-off prompt artifact is not
   generated; the audit-log entry from the dispatch (F-07
   row 13) is not written (because there is no Producer
   dispatch — the action is Consumer's own claim, audit-
   logged with `actor_role: consumer`).

When this is appropriate:
- Single-card sessions where Manager dispatch is overhead.
- Quick "pick a small card to warm up" moments.
- Architect already has the board state in their head and
  doesn't need a snapshot.

When Manager is preferred over manual pull:
- Multiple cards to dispatch in one session.
- Need the WIP-budget / health-snapshot context before
  picking.
- Need the kick-off-prompt artifact for parallel terminals.

- **Features activated**: F-C0 → F-C1 → F-C14 (full
  lifecycle as in §2.6).
- **Constraining ADRs**: same as §2.6 minus ADR-0006 row 13
  (no dispatch action — Consumer self-pulled).

### 2.8 Weekly retro flow

Architect has been running the board for ~7 days; wants the
"what should I carry forward" report.

1. **Architect prompts Manager: "weekly retro".** The
   `managing-board` skill routes to the Retro routine
   (`references/retro-routine.md`).
2. **F-12 — Retro routine fires.** Per ADR-0006 matrix row
   14, the cadence-driven trigger is A-class (auto-trigger
   = A); when the architect explicitly asks instead, the
   action is the same auto-trigger short-circuit. Manager
   walks the trigger window: last 7 days by default, or the
   full milestone if a Milestone close just fired, or the
   N-cards-completed window if that threshold tripped.
3. **F-12 aggregates Retro Notes from the trigger window's
   PRs.** Per §1.8.3, every PR in the window has a
   `## Retro Notes` section (when reusable lessons exist).
   Manager walks the merged PRs, extracts the notes, groups
   by theme.
4. **F-13 (when applicable) merges the quality-trend half.**
   Weekly report combines (a) Retro Notes synthesis
   (knowledge harvesting) with (b) F-14 quality-harness
   data (lint violation counts, structural-test failure
   trend, etc., once F-14 is configured for the project).
5. **Manager produces the structured retro report.** Format
   per Derby & Larsen 2006 5-stage: Set the stage / Gather
   data / Generate insights / Decide what to do / Close.
   Output is markdown, copy-paste-ready for status-report
   reuse.
6. **Optional: proposed CLAUDE.md / AGENTS.md amendments.**
   If Retro Notes surface a recurring decomposition pattern
   that should be encoded as a project-local rule (e.g.
   "always carve the schema migration as its own card"),
   Manager proposes the amendment as an R-class action
   (matrix row 4 — modifies SoT). Architect approves; the
   amendment lands in the next commit.
- **Knowledge-harvesting framing reminder (per §1.8.3 and
  §1.1)**: this report has zero KPI / velocity / per-
  architect performance content. The output is "lessons to
  carry forward", not "how productive were we last week".
- **Features activated**: F-12, F-13 (when configured),
  preflight piggyback for the cadence trigger.
- **Constraining ADRs**: ADR-0006 (rows 4, 14), ADR-0007
  (preflight piggyback for cadence detection).

### 2.9 Triage flow (stuck / oversized / stale cards)

Architect notices something is off — or Manager's morning
preflight surfaces it. End state: each anomalous card has a
chosen disposition (resume, split, reassign, kill, refine)
and the disposition has executed.

1. **Trigger.** Three sources:
   - Architect explicit: "what's stuck?" / "triage card #N" /
     "the board feels stuck".
   - Manager preflight surfaces it (F-11 stale detection
     fires during the next prompt; F-05 health snapshot
     reports degradation).
   - F-10's own remediation ladder is invoked from another
     routine (e.g., Daily routine surfaces a stale claim and
     hands off to triage).
2. **F-10 — Triage with remediation ladder.** Manager
   queries:
   - Blocked cards (F-01 with status filter) — what's
     blocking each?
   - In Progress with stale heartbeat (F-11 — last commit /
     last comment / last claim push timestamps via GitHub-
     observable signals; never heartbeat-style protocols, per
     I-5 and ADR-0007).
   - Oversized cards (size:L approaching the split threshold;
     in-flight cards whose actual diff is creeping toward
     the L ceiling).
3. **Per-card diagnosis loop** (per
   `managing-board/SKILL.md`'s inline triage routine).
   Manager loads the card, classifies the symptom in
   conversation with the architect, applies the remediation
   ladder:
   - **Unblock** (External dep / decision now satisfied) —
     A via matrix row 5 (Backlog → Ready), or transition
     Blocked → Ready directly.
   - **Split** (Violates INVEST — too big, not vertical, not
     testable) — R via matrix row 3 (re-split = R; defer to
     F-09 for the actual decomposition).
   - **Reassign** (Stale claim — Consumer session died; new
     Consumer should pick it up after worktree cleanup) — R
     via matrix row 8 (cancel claim = R; cleanup recipe in
     `managing-board/SKILL.md`).
   - **Kill** (Card no longer warranted) — R via matrix
     row 7 (close stale card = R; irreversible).
   - **Refine** (Acceptance Criteria no longer match intent)
     — A via matrix row 2 (edit card body = A).
4. **Apply only after architect confirms the diagnosis.**
   Per `managing-board/SKILL.md`: don't edit the card before
   the diagnosis is confirmed. R-class actions surface as
   proposals awaiting approval; A-class actions execute with
   audit log.
5. **Stale-claim reassign sub-recipe** (most common): per
   `managing-board/SKILL.md` triage table, offer three
   choices — **resume** (new kick-off prompt for the same
   Consumer to pick up partial work), **reassign**
   (`git worktree remove --force` paired worktree, delete
   stale branch on remote, release card to Ready), **cancel**
   (close or back to Backlog).
- **Features activated**: F-10 (driver), F-01, F-05, F-11,
  F-09 (when split path picked).
- **Constraining ADRs**: ADR-0006 rows 2, 3, 5, 7, 8 (each
  ladder branch maps to a row), ADR-0007 (F-11 stale
  detection via preflight piggyback).

### 2.10 Mid-session dependency loss flow (failure mode)

A long-running Manager or Consumer session is in flight.
While the session is alive, the architect uninstalls
superpowers (rare but legitimate — a botched upgrade, a
manual `rm -rf`, a reorganization of `~/.claude/skills/`).
End state: the session catches the loss before it makes a
silent broken handoff, the architect re-installs, the session
recovers without losing in-flight work.

1. **Pre-loss state.** Manager (or Consumer) is running
   normally. Worktree is intact, branch is intact, card is
   `In Progress` (or Manager has unflushed audit-log entries
   in flight).
2. **Dependency removed.** Architect uninstalls superpowers
   in another terminal — `~/.claude/plugins/cache/.../
   superpowers/` no longer resolves.
3. **Just-in-time re-check fires (per §1.5.0 Layer 3).** The
   next Manager / Consumer action that needs to invoke a
   `superpowers:*` skill (e.g., Consumer about to invoke
   `superpowers:subagent-driven-development` at F-C4, or
   Manager about to invoke `superpowers:writing-plans`
   during F-08) re-runs `bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"`. Exit `2`
   surfaces.
4. **Session surfaces the missing-dependency banner
   verbatim.** Per `using-board-superpowers/SKILL.md`'s
   appendix, the banner content is identical regardless of
   which session caught it. Session enters logical suspend
   (Consumer F-C8-style, Manager equivalent) — does not
   continue the pending action; does not silently
   re-implement the missing skill (P4b violation refusal).
5. **Architect re-installs.** Per §2.1 step 1, runs
   `/plugin install superpowers@claude-plugins-official`.
   Architect restarts the session OR (if the plugin install
   surfaces in `~/.claude/plugins/` without restart) the
   next prompt's Layer 3 re-check passes.
6. **Session resumes.** Manager picks up where it was —
   the in-flight Routine continues, audit-log entries
   flush. Consumer picks up at F-C4 — worktree intact (per
   I-7), card still `In Progress`, branch still claimed.
   No data lost; the only cost is the prompt cycle the
   missing-dep banner consumed.

**Why the just-in-time re-check is load-bearing**: per the
three-layer alert strategy in §1.5.0, the SessionStart hook
fires once per session (cannot catch mid-session loss); the
SKILL Step 1 fires only on the entry skill (cannot catch
later cross-plugin calls). The Layer 3 re-check is the only
defense against this specific failure mode.

- **Features activated**: §1.5.0 Layer 3 (just-in-time
  re-check); F-C8 / F-08 area (the suspend-and-surface
  pattern).
- **Constraining ADRs**: ADR-0004 (composition over reimpl
  — Consumer cannot re-implement the missing skill);
  ADR-0007 (no daemon — the re-check has to be in-band).

---

