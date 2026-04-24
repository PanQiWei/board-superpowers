# board-superpowers — project instructions

This repo **is** the plugin. Sessions here are plugin-maintainer
sessions, not product-user sessions. See @README.md for the
user-facing overview.

This file is the developer guide for the plugin itself. Read it
before editing anything under `skills/`, `scripts/`, `hooks/`, or
`.claude-plugin/`. The routing block at the bottom is the same block
the plugin injects into every downstream repo during bootstrap — it
is mirrored verbatim from
`skills/using-board-superpowers/references/claudemd-routing.md` and
does not describe plugin-maintainer behavior.

## Architecture at a glance

board-superpowers is a scheduling layer on top of `superpowers` and
`gstack`. At runtime it does four things:

1. **Alerts** the architect if either dependency is missing. Three
   layers, in increasing reliability:
   1. `hooks/session-start.sh` — best-effort banner via
      `additionalContext` (Claude Code's SessionStart delivery is
      buggy — treat this layer as advisory).
   2. `skills/using-board-superpowers/SKILL.md` Step 1 — the
      reliable gate; every skill invocation routes through it.
   3. Just-in-time re-checks inside `managing-board` and
      `consuming-card` before any cross-plugin call, in case deps
      got uninstalled mid-session.
2. **Routes** each session into `managing-board` or `consuming-card`
   based on the first user message (the routing block at the bottom
   of this file tells the model how).
3. **Coordinates** work through GitHub. No server-side state. The
   board IS the state: Project v2 status column + Issue body
   schema + `claim/<N>-<slug>` remote branches.
4. **Delegates** real work — brainstorming, TDD, debugging, QA,
   review, security audit — to `superpowers:*` and `gstack:/*`. We
   compose; we don't reimplement.

### Data plane

- **GitHub Project v2** — the board. Its `Status` field drives the
  state machine defined in `skills/board-protocol/SKILL.md`.
- **GitHub Issues** — the cards. Body schema lives in
  `skills/decomposing-into-milestones/references/card-schema.md`.
- **Claim branches** — `claim/<N>-<slug>` on origin. Creating one
  via `git push --force-with-lease=<ref>:` is the distributed lock
  (first push wins, second one exits 10).
- **Worktrees** — default at
  `$HOME/.config/superpowers/worktrees/<project>/<branch>`, owned
  by `claim-card.sh`. One per Consumer session, so N parallel
  Consumers never share HEAD.
- **`.board-superpowers/config.yml`** — committed per-repo config
  (project coordinate + WIP limit).
- **`.board-superpowers/claims/<N>.claim`** — marker file on the
  claim branch. Gitignored locally but force-committed to the claim
  branch, so the marker is visible on origin as proof of claim.

### Control plane (plugin surfaces)

| Surface | Called by | Promises |
|---------|-----------|----------|
| `hooks/session-start.sh` | Claude Code on session start | Best-effort dep alert via `additionalContext` |
| `scripts/check-deps.sh` | The hook + every skill's preflight | Exit `0` deps OK, `2` missing. `--machine` mode emits `MISSING=` / `ROUTING_INJECTED=` key=value lines. |
| `scripts/bootstrap-project.sh` | `using-board-superpowers` Step 3 | Labels + Status validation + `config.yml` + `.gitignore` entry |
| `scripts/claim-card.sh` | `consuming-card` Step 2 | Atomic claim + isolated worktree; two-line stdout (`branch=` / `worktree=`) |
| `scripts/create-card.sh` | `decomposing-into-milestones` Step 6 | Issue + Project-item in one shot |
| `scripts/transition-card.sh` | Manager + Consumer | Move a card between Status options |
| `skills/*/SKILL.md` | Claude Code model matching on `description` frontmatter | That description is behavior, not documentation |

## Tech stack

- **bash 3.2+** with strict mode. Callers `set -euo pipefail` before
  sourcing `scripts/lib/common.sh`.
- **gh CLI** with `project` scope (plus `issue` / `pr` implicitly).
- **python3** for JSON parsing (gh output → field / option IDs).
- **shellcheck** — the style + correctness gate for every script
  and test.
- **Claude Code plugin protocol** — `${CLAUDE_PLUGIN_ROOT}` env,
  `hooks/hooks.json` schema, SKILL.md YAML frontmatter,
  `hookSpecificOutput.additionalContext` payload shape.
- No runtime dependencies beyond the above. No node, no go, no
  compiled artifacts.

## Directory layout and ownership

```
board-superpowers/
├── .claude-plugin/
│   ├── plugin.json                 # version source of truth
│   └── marketplace.json            # local-marketplace manifest (dogfood)
├── hooks/
│   ├── hooks.json                  # Claude Code hook registration
│   └── session-start.sh            # Layer 1 dep alert; self-contained
├── scripts/
│   ├── lib/common.sh               # shared bash utils; caller sets
│   │                               # strict mode BEFORE sourcing
│   ├── check-deps.sh               # exit 0/2; self-contained
│   ├── bootstrap-project.sh
│   ├── claim-card.sh
│   ├── create-card.sh
│   └── transition-card.sh
├── skills/
│   ├── using-board-superpowers/    # entry skill: preflight + routing
│   │   └── references/             # + first-time bootstrap
│   │       ├── claudemd-routing.md         # injected into downstream
│   │       │                               # CLAUDE.md — mirror of the
│   │       │                               # block at the bottom here
│   │       └── first-time-user-guide.md    # delivered post-bootstrap
│   ├── board-protocol/             # shared state machine + schema
│   ├── managing-board/             # Manager main skill
│   │   └── references/
│   │       ├── daily-routine.md
│   │       ├── intake-routine.md
│   │       ├── review-queue.md
│   │       └── retro-routine.md
│   ├── decomposing-into-milestones/
│   │   └── references/
│   │       ├── card-schema.md
│   │       └── decomposition-patterns.md
│   └── consuming-card/
│       └── references/
│           ├── pr-template.md
│           └── handoff-to-superpowers.md
├── tests/
│   ├── test-claim-card.sh              # force-add + .gitignore invariant
│   └── test-claim-card-worktree.sh     # worktree isolation
├── CLAUDE.md                       # this file — developer guide
├── README.md                       # end-user overview
└── LICENSE
```

Two files are **deliberately self-contained** — they must NOT source
`scripts/lib/common.sh`, because a broken or missing lib must never
break either dep detection or Claude Code startup:

- `hooks/session-start.sh`
- `scripts/check-deps.sh`

Everything else under `scripts/` sources the lib.

## Self-hosting

The plugin dogfoods itself: this repo has its own
`.claude-plugin/marketplace.json`, its own
`.board-superpowers/config.yml`, and routes sessions through its own
Manager / Consumer skills.

Two load-bearing consequences:

- **The routing block at the bottom of this file is a mirror.** It
  is the same text injected into downstream repos during bootstrap,
  and it must match
  `skills/using-board-superpowers/references/claudemd-routing.md`
  verbatim between the marker pair. Edits to one land in the other
  in the same commit.
- **The `<!-- board-superpowers:routing -->` /
  `<!-- /board-superpowers:routing -->` marker pair is matched by
  `check-deps.sh`.** Do not rename, indent, or merge them into
  surrounding prose.

Non-trivial changes should go through the plugin's own Manager →
Consumer flow — create a card, claim it, open a PR. Direct-edit on
main is fine for typos and single-reference docs fixes; not for
protocol changes.

## Protocol invariants

These are load-bearing because downstream installs depend on them.
Breaking any of them → migration note in the PR body, consider a
version bump.

### Script contracts

- **`scripts/*.sh` are a public contract.** Hooks, skills (via
  `${CLAUDE_PLUGIN_ROOT}`), and user automations call them.
- **Exit-code discipline.** Each script documents its exit codes in
  its header comment. Current conventions:
  - `0` — success
  - `1` — operational failure
  - `2` — bad arguments OR (for `check-deps.sh` only) missing deps
  - `3` — missing runtime command (gh / python3)
  - `10` — `claim-card.sh`: already claimed (caller must stop, not retry)
  - `20` — `claim-card.sh`: git / network error
  - `30` — `claim-card.sh`: bad args / missing dep
- **New exit codes require updating every caller plus every
  branching skill.**
- **`claim-card.sh` stdout is structured.** On success it prints
  exactly two lines, in order:
  ```
  branch=<claim branch name>
  worktree=<absolute path to worktree>
  ```
  `consuming-card/SKILL.md` Step 2 parses both. Changing the shape
  is a breaking change.
- **`check-deps.sh` `--machine` keys are `MISSING`,
  `ROUTING_INJECTED`, `PROJECT`.** Renaming any of them breaks
  `hooks/session-start.sh`'s parser.

### File / path contracts

- **`.board-superpowers/claims/` is gitignored** but individual
  claim markers are force-committed to their claim branch (never to
  main). `claim-card.sh` does the `git add -f`.
- **`.board-superpowers/config.yml` is tracked** and hand-editable.
- **Worktree default path** is
  `$HOME/.config/superpowers/worktrees/<project>/<branch>`.
  Override via `$BOARD_SP_WORKTREE_DIR`, or via project-local
  `.worktrees/` (must both exist AND be gitignored).
- **CLAUDE.md routing markers** `<!-- board-superpowers:routing -->`
  / `<!-- /board-superpowers:routing -->` are matched by
  `check-deps.sh`.
- **Never commit absolute local paths to a public branch.** Claim
  markers ride on claim branches that push to origin; a local path
  leaks OS username / directory layout. See
  `tests/test-claim-card-worktree.sh` for the regression guard.
- **Plan briefs live at `docs/board-superpowers/plans/card-<N>.md`
  and are gitignored.** The card body on GitHub is the source of
  truth; the plan brief is scratch for
  `superpowers:subagent-driven-development`.

### Skill contracts

- **Skill `description` frontmatter is behavior.** Downstream
  models match on it — editing it changes which sessions the skill
  fires in. Treat edits with the same care as code.
- **Skill filenames are stable.** `SKILL.md` + `references/<name>.md`
  — the Claude Code runtime enumerates these.
- **Every skill that calls an external plugin must just-in-time
  re-check deps** via `check-deps.sh` before the call, in case
  deps got uninstalled mid-session.

## Change-impact matrix

Before editing, check what else has to land in the same PR. If you
change what's on the left, update everything on the right.

| If you change… | You must also update… |
|----------------|----------------------|
| `scripts/claim-card.sh` stdout shape | `skills/consuming-card/SKILL.md` Step 2 parser + `tests/test-claim-card*.sh` + `README.md` "Dispatching a Consumer" |
| Any `scripts/*.sh` exit code | Every caller (grep `scripts/` + `skills/`) + the invariants section above |
| `scripts/lib/common.sh` function signature | Every script that sources it |
| `check-deps.sh` output keys (`MISSING`, `ROUTING_INJECTED`, `PROJECT`) | `hooks/session-start.sh` parser |
| Marker string `board-superpowers:routing` | `check-deps.sh` marker detection + every skill that mentions it |
| `skills/board-protocol` state machine | Every skill referencing transitions + `scripts/transition-card.sh` Status option names |
| `skills/decomposing-into-milestones` card schema | `scripts/create-card.sh` body template + PR review gate in `managing-board/references/review-queue.md` |
| Worktree default path | `scripts/claim-card.sh` + `README.md` + `skills/consuming-card/SKILL.md` + `skills/board-protocol/SKILL.md` + triage reassign recipe in `managing-board/SKILL.md` |
| `skills/using-board-superpowers/references/claudemd-routing.md` | This file's routing block (mirror rule — verbatim between the markers) |
| `skills/using-board-superpowers/references/first-time-user-guide.md` | If the guide's structure changes, `skills/using-board-superpowers/SKILL.md` Step 3 reference to it |
| `.claude-plugin/plugin.json:version` | `.claude-plugin/marketplace.json:plugins[0].version` + git tag |
| Any skill `description` frontmatter | `README.md` if the trigger phrases appear there |
| `hooks/hooks.json` schema | `hooks/session-start.sh` if new hook entry points get added |

## Maintaining skills

1. Invoke `superpowers:writing-skills` first. It enforces frontmatter
   rules, description discipline, and reference-splitting heuristics.
2. If the edit changes the `description` field, re-read adjacent
   skills' descriptions — overlaps cause mis-routing.
3. If the edit changes a procedure step, check the change-impact
   matrix for callers (the `scripts/*.sh` one is the usual bite).
4. Skill bodies stay in English for shareability. Chinese discussion
   belongs in commit messages or PR bodies.
5. Reference files follow the pattern `skills/<name>/references/<topic>.md`.
   Keep each file single-topic; SKILL.md is the dispatcher.

## Maintaining scripts

1. Header comment is mandatory: purpose, usage, exit codes, stdout
   shape (if any), side effects, required deps. `bsp_show_help`
   prints the header as `--help`.
2. `set -euo pipefail` + source `scripts/lib/common.sh` at the top,
   unless self-contained (`check-deps.sh`) — document the exception
   inline.
3. Run `shellcheck -x <script>` from the scripts directory before
   committing. If you hit SC1091, it usually means you ran
   shellcheck from the wrong cwd, not that the source line is wrong.
4. Second opinion on non-trivial shell logic: `gstack:/codex`.
5. If a script gains a new exit code or stdout line, update the
   change-impact matrix in the same PR.
6. `${CLAUDE_PLUGIN_ROOT}` is the only reliable way for scripts to
   reference the plugin's own files. Never hard-code `~/.claude/plugins/...`.

## Maintaining hooks

1. `hooks/session-start.sh` must stay self-contained — no sourcing
   `lib/common.sh`, no dependency on repo layout beyond reading its
   own path via `${CLAUDE_PLUGIN_ROOT}`.
2. Anything emitted to `additionalContext` is untrusted model
   input. Sanitize every value derived from `check-deps.sh` before
   interpolation — see `sanitize_dep_name` in `session-start.sh`
   for the pattern.
3. Hook failures must NEVER block Claude Code startup. Silent
   no-op on error is the correct failure mode at this layer; the
   SKILL preflight is the real safety net.
4. `hooks.json` declares a 10s timeout. Keep new work well under it.

## Testing

Tests live in `tests/*.sh` — plain bash, no framework. They must be
**hermetic**. See `tests/test-claim-card-worktree.sh` for the
canonical pattern:

- `export HOME=$TMP/home` — isolate user config.
- `export XDG_CONFIG_HOME=$TMP/xdg` — isolate worktree default path.
- `export GIT_CONFIG_GLOBAL=$TMP/.gitconfig-global` +
  `GIT_CONFIG_SYSTEM=/dev/null` — neutralize the runner's git
  config; write a minimal `user.name` / `user.email` to the test
  global config.
- Use a local bare repo as `origin`; never reach GitHub from a test.
- Kill hooks and custom excludes: `core.hooksPath=/dev/null`,
  `core.excludesFile=/dev/null`.

Run everything:

```bash
for t in tests/*.sh; do bash "$t" || exit 1; done
```

Adding a test: name it `tests/test-<area>.sh`, make it executable,
and assert on invariants — not only happy paths. The
`worktree:` field info-leak fix landed a regression assertion
precisely because the existing happy-path test had not caught it.

## Releasing

No deploy target. A release is bookkeeping:

1. Decide the semver bump. Script / hook / skill contract breaks
   are major. Additive behavior is minor. Docs-only is patch.
2. Bump `.claude-plugin/plugin.json:version` AND
   `.claude-plugin/marketplace.json:plugins[0].version` in the
   same commit.
3. If the release touches `scripts/` or `hooks/`, run `gstack:/cso`
   before tagging.
4. Tag: `git tag v<version> && git push origin v<version>`.
5. Draft a GitHub release pointing at the tag, with migration notes
   whenever a contract changed.

**Not applicable here:** `gstack:/ship`, `/land-and-deploy`,
`/canary`, `/document-release`. This plugin has no deploy target.

## Project-specific skill routing

The global `~/.claude/CLAUDE.md` already routes gstack ↔ superpowers
for day-to-day work. The injected routing block at the bottom of
this file captures the project-agnostic version of that for
downstream repos. In addition, for this repo:

- Editing any `skills/*/SKILL.md` → invoke
  `superpowers:writing-skills` first.
- Second opinion on shell logic → `gstack:/codex`.
- Before tagging a release that touches `scripts/` or `hooks/` →
  `gstack:/cso`.
- Dogfood the board for non-trivial changes: create a card, claim
  it via the plugin's own Consumer flow, open the PR. Direct edits
  are fine only for typos and single-reference docs fixes.
- **Not applicable here:** `gstack:/ship`, `/land-and-deploy`,
  `/canary`, `/document-release`. See Releasing above.

## Commands

```bash
# Public contract surfaces
bash scripts/check-deps.sh                      # preflight; exits 0 or 2
bash scripts/bootstrap-project.sh --help        # one-time per-repo setup
bash scripts/create-card.sh --help              # Manager: create card
bash scripts/claim-card.sh --help               # Consumer: atomic claim
bash scripts/transition-card.sh --help          # move card status

# Developer workflows
for t in tests/*.sh; do bash "$t" || exit 1; done    # run all tests
(cd scripts && shellcheck -x ./*.sh)                 # lint scripts
(cd tests   && shellcheck -x ./*.sh)                 # lint tests
```

<!-- board-superpowers:routing -->
## board-superpowers session routing

This project uses the `board-superpowers` plugin. Any Claude Code
session in this project plays one of two roles:

- **Board Consumer** — if the first message contains `[board-card:#N]`,
  or the user asks to work on / claim / implement card N, invoke the
  `consuming-card` skill immediately. That skill owns the full
  lifecycle: claim → implement → PR → update board.
- **Board Manager** — if the user asks about planning today's work,
  reviewing the board, decomposing a requirement, triaging blocked
  cards, or running a retro, invoke the `managing-board` skill.
- When unsure, invoke `using-board-superpowers` first.

board-superpowers depends on the `superpowers` and `gstack` plugins
and will delegate design and execution work to them. Do not
reimplement what they already do.

### How to compose gstack and superpowers

Both plugins are runtime dependencies of board-superpowers. They are
complementary, not alternatives — route by phase of work, not by
preference.

**Division of labor**

- **gstack owns the bookends.** Direction-setting before a card is
  claimed (is this worth building, what's the right shape) and
  delivery-side verification (code review, QA, security). CEO /
  design / QA / security-officer viewpoints.
- **superpowers owns the middle.** The coding-discipline loop:
  `brainstorming` → `writing-plans` → `test-driven-development` →
  `systematic-debugging` → `verification-before-completion` →
  `requesting-code-review`. TDD is mandatory inside this loop.
- **Conflict arbitration** follows `superpowers:using-superpowers`:
  **user instructions > skill > default behavior.** A gstack skill's
  "plan is ready, start coding" advice does not override superpowers'
  TDD discipline unless the user explicitly says so in the current
  conversation.

**Typical flow — menu, not checklist**

Pick skills that fit the card; do not run them all.

Pre-card intake (Manager's Intake routine routes here before a card
is created):

1. `gstack:/office-hours` or `/plan-ceo-review` — is this worth
   building.
2. `gstack:/plan-eng-review` — lock the architecture.
3. `superpowers:brainstorming` — sharpen requirements and design.
4. `superpowers:writing-plans` — turn the output into an executable
   plan.

Implementation (inside a Consumer session):

5. `superpowers:test-driven-development` drives Red → Green →
   Refactor.
6. Stuck? `superpowers:systematic-debugging`, or
   `gstack:/investigate` for a second angle.
7. Parallelizable subtasks:
   `superpowers:dispatching-parallel-agents` or
   `superpowers:subagent-driven-development`.

Self-check and delivery (still inside the Consumer session, before
opening the PR):

8. `superpowers:verification-before-completion` — evidence-first; do
   not claim "done" without it.
9. `gstack:/review` — production-bug viewpoint.
10. `superpowers:requesting-code-review` — independent
    second-pair-of-eyes.
11. `gstack:/qa <url>` — real-browser QA. Mandatory for any
    UI-touching card.
12. `gstack:/cso` — security / OWASP / STRIDE audit. superpowers has
    no equivalent.

Release, deploy, canary, and document-release skills
(`gstack:/ship`, `/canary`, `/land-and-deploy`,
`/document-release`) are project-specific. Enable them only if they
match this repo's deployment shape; otherwise use whatever release
flow the project already has. board-superpowers does not prescribe
a release process.

**Pitfalls**

- **Skill-name collisions.** Two large libraries have overlapping
  descriptions. Route by this block, not by letting the model guess
  from skill descriptions.
- **Browser tools — one source.** Always use `gstack:/browse`. Do
  not mix with other browser tooling.
- **TDD is not optional** inside
  `superpowers:test-driven-development`. An adjacent planning
  skill's "start coding" suggestion does not excuse skipping
  Red → Green → Refactor.
<!-- /board-superpowers:routing -->
