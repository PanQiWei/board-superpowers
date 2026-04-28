# Glossary

Dictionary of every load-bearing term used in `using-board-superpowers/` and the rest of the plugin's surface. Read top-to-bottom on first encounter; thereafter use as a lookup. Definitions are deliberately short — the deeper how/why for each lives in the cross-referenced sibling reference.

## Producer

The single agent role that owns the board's *what-next* picture: planning, decomposing requirements into Cards, reviewing PRs, triaging blockers, releasing stale claims. Typically the human architect's session. Drives `board-superpowers:managing-board`.

## Consumer

An agent role that owns one Card from claim through merged PR. Many Consumers can run in parallel (different Cards, different worktrees). Each Consumer is single-purpose and bounded — it does NOT plan new work or touch other Cards. Drives `board-superpowers:consuming-card`.

## Card

A unit of work tracked as a GitHub Issue, mirrored as an item on the GitHub Project board, and (once claimed) backed by a `claim/<N>-<slug>` branch + `git worktree`. A Card body follows a fixed schema (thin pointer to spec, Goal, Acceptance criteria, Out of scope, Dependencies, Notes) terminated by a bottom marker. The 6-state lifecycle is enumerated in the entry skill body's "The 6 Card states" section; the full per-step narrative is in `card-lifecycle.md`.

## WIP

Work In Progress — the count of Cards currently on the Producer's plate. The formula is `count(In Progress) + count(suspended-label) + count(In Review)`. **Blocked Cards are NOT counted** so a stuck Card never locks the cap.

## WIP cap

The architect's per-host upper bound on WIP, configured in `<repo>/.board-superpowers/config.local.yml` as `wip_limit`. Producer routines refuse to claim a new Card when the cap is hit and surface the over-capacity Cards as triage candidates instead.

## SPOT

Single Point of Truth (sometimes "Single Source of Truth"). A contract whose definition lives in exactly one place; every other skill that needs it reads from that one place rather than re-stating. The 4 atomic skills (`board-canon`, `enforcing-pr-contract`, `classifying-actions`, `auditing-actions`) exist precisely to be SPOTs — without them, ~5 molecular skills would each carry their own copy of the contract and drift independently.

## Autonomy class

The decision class that `classifying-actions` returns for a mutating action: **A** (Auto — caller acts immediately, writes one audit row), **R** (Reserved — caller drafts a proposal, surfaces to architect, waits for ack, then acts and writes the resolve audit row), or **N** (No-go — caller refuses; surfaces the block reason). Defaults come from a 14-row Producer matrix + 14-row Consumer catalog and may be promoted/demoted via layered overrides in `~/.board-superpowers/overrides.yml` and `<repo>/.board-superpowers/config.local.yml`.

## Propose-resolve

The two-row audit pattern an R-class action produces: row 1 (`approval-stage=propose`) at proposal time, row 2 (`approval-stage=approved` OR `rejected`) after architect ack. A-class actions produce a single row (`approval-stage=auto`). The pattern is enforced by `auditing-actions` and lets a third party reconstruct what was proposed, what was approved, and what shipped — separately.

## Bounded context

A DDD term: a portion of the domain with its own vocabulary, rules, and aggregate boundaries. board-superpowers carves the domain into 5 contexts: **Board** (Card + PR aggregates over GitHub Project + Issues + git refs), **Session** (Producer + Consumer process aggregates over OS processes + worktrees), **Bootstrap** (host + per-repo first-time setup state), **Audit** (the trail aggregate written to a BYO RDBMS), and **Spec** (a thin SpecPointer linking a Card to its authoritative architecture doc when one exists). See `architecture-overview.md` for which skill operates in which context.

## Claim transaction

The 4-step atomic operation that transitions a Card from `Ready` to `In Progress` and arms a Consumer to do the work: (1) flip the GitHub Project Status field; (2) create a `git worktree`; (3) cut the `claim/<N>-<slug>` branch from `origin/main` inside that worktree; (4) push the empty branch so the board sees the claim signal. Implemented by `${CLAUDE_PLUGIN_ROOT}/scripts/claim-card.sh`. Idempotent — re-running is a no-op if the same branch already owns the Card.

## Worktree

A `git worktree` checkout — a parallel working directory backed by the same `.git/` as the repo root. Each Consumer gets its own worktree so multiple Consumers can edit different Cards simultaneously without contending over a shared `HEAD`. Default location: `$HOME/.config/superpowers/worktrees/<repo>/<branch>`, overridable via `BOARD_SP_WORKTREE_DIR`. The repo root itself is reserved for `main` — feature work never happens there.

## INVOKE marker

A two-line payload the `SessionStart` hook can inject into the agent's `additionalContext` to fast-path a routing decision:

```
INVOKE: <skill-name>
REASON: <one-line rationale>
```

The entry skill's reliable gate consumes the marker if present, but ALWAYS runs its own probes too — the hook is best-effort, the skill is the contract.

## BYO RDBMS

"Bring Your Own" relational database — Postgres, MySQL, or SQLite — connected via a `DATABASE_URL`-style string under the `audit_db_url:` key of `~/.board-superpowers/credentials.yml` (chmod `0600`). The runtime override `BOARD_SP_AUDIT_DB_URL` env var beats the file but does not persist. The plugin writes the audit log here. When neither source provides a URL or the database is unreachable, audit writes degrade to a local jsonl trace and the entry's `mode` field records the degradation cause.

## Audit log

The append-only record of every mutating action the plugin performs. Schema: action_id + decision (A/R/N) + skill name + approval-stage + outcome + structured payload + timestamps. Written by `${CLAUDE_PLUGIN_ROOT}/scripts/audit-log-write.sh` to either the BYO RDBMS or, on degradation, to `~/.board-superpowers/repos/<normalized>/audit-local.jsonl`.

## Slug

The kebab-case shortened title in a `claim/<N>-<slug>` branch name — generated from the Card title by `bsp_slugify` in `scripts/lib/common.sh`. Truncated to fit a length budget; a Card titled "Refactor X into Y" might land as `claim/54-refactor-x-into-y`.

## Reliable gate

The 3-step probe block (dep check + state probe + marker consumption) the entry skill always runs at session start, regardless of whether the `SessionStart` hook injected a marker. The "reliable" name is to call out that the gate is the contract; the hook is an optimization.

## Routing block

A fenced markdown block injected into the consuming repo's `AGENTS.md` and `CLAUDE.md` by `bootstrap-project.sh`. Documents how the agent should route board-superpowers traffic in *this* repo — owner / project number, role disambiguation rules, dogfood notes if applicable. The block is hash-tracked in `~/.board-superpowers/repos/<normalized>/state.yml` so the entry skill can detect tampering and prompt the user before re-injection.

## Manifest

`~/.board-superpowers/manifest.yml` — the host-local list of repos this host has bootstrapped, plus the global path defaults. Source of truth for "is this a brand-new host?" — its absence triggers `bootstrapping-repo`.

## Plugin root

The directory where the plugin's hooks, scripts, and skills live. Resolves to `${CLAUDE_PLUGIN_ROOT}` on Claude Code and `${CODEX_PLUGIN_ROOT}` on Codex CLI. Always read it via `bsp_plugin_root` from `scripts/lib/common.sh` so callers stay cross-platform; never hard-code either env var.

## Skill layer

board-superpowers groups skills into three layers with strict downward dependency:

- **Entry** — this skill (`using-board-superpowers`). Auto-matches first; routes only.
- **Molecular** — business workflows (`managing-board`, `consuming-card`, `decomposing-into-milestones`, `bootstrapping-repo`, `migrating-repo-version`).
- **Atomic** — single-purpose contracts reused by molecular skills (`board-canon`, `enforcing-pr-contract`, `classifying-actions`, `auditing-actions`). Atomic skills MUST NOT call any same-plugin skill — they are reflexes, not orchestrators.

The layer determines what the skill is allowed to depend on, its body-length budget, and how often it gets loaded.
