# consuming-card — Stage 1: Claim

Full detail for the Claim stage (nodes A1, A2, A3).

## A1 — Receive card assignment

The session starts one of two ways:

**Mode-1 (architect-spawned)**: architect types `[board-card:#N]` or
`/board-superpowers:consuming-card N` in their primary session. The `using-board-superpowers`
entry skill routes to this skill and the card number is available via `$card_number` (named
argument, Claude Code) or `$ARGUMENTS` (Codex or fallback). If neither is set, parse the
first integer following `card`, `#`, or `[board-card:#` from the prompt.

**Mode-2 (Producer-spawned)**: a Producer routine SKILL (`briefing-daily` /
`intaking-requirement` / `reviewing-pr-queue` / `triaging-board`) session spawns this skill
as a subagent via `Agent` tool on Claude Code. The subagent receives an isolated context
with the card number in the prompt. It runs with `max_depth=1` — cannot spawn further
subagents.

If the card number cannot be resolved unambiguously, ask. Wrong card number = wrong worktree
= wasted claim transaction.

**B1-first — Pre-implementation check**: before claiming, check the kanban's WIP cap using
`board-superpowers:board-canon` § "WIP counting formula" — count of `In Progress + suspended`
cards (excluding `Blocked`). If WIP cap is reached, surface to the architect before
proceeding; do not claim a second card silently.

## A2 — Atomic claim + worktree entry

**Step 2 — Read the card**

Invoke `board-superpowers:operating-kanban` with action `read_card`. The skill
resolves the active projection from `<repo>/.board-superpowers/settings.yml
§ modules.m10_kanban` (or `<repo>/.board-superpowers/config.yml § board` if
absent) and dispatches Form A / B / C.

For the `github-project-v2` projection (Form A bash):

```bash
gh issue view <N> --json number,title,body,state,labels,comments
```

Inspect:

- **Status** — must be `Ready` to claim. If `In Progress` and a
  `claim/<kanban-id>-<key-slug>-<title-slug>` branch exists, someone else has it.
  Other states: wait or escalate to architect.
- **Card body** — read all 5 mandatory sections per `board-superpowers:board-canon`
  § "Card body schema".
- **Dependencies** — if any hard `depends-on` is not yet `Done`, STOP and surface
  to architect. Do not claim cards with unmet dependencies.
- **Labels** — note `security`, `ui`, or `suspended` labels; they gate the
  Stage 3 conditional passes.

**Step 3 — Claim transaction (action_id 100)**

1. Invoke `board-superpowers:classifying-actions` (action_id 100 — claim card).
   If R-class: audit propose → surface → await architect ack before proceeding.
2. Run the claim script:
   ```bash
   bash scripts/claim-card.sh \
     --owner <owner> --project <number> \
     --repo <repo> --card <N> --title "<title>"
   ```
   The owner + project number resolve from the active kanban registration. The script
   executes the 4-step claim transaction:
   - Create branch `claim/<kanban-id>-<key-slug>-<title-slug>` from `main`.
   - Push branch to remote (the claim primitive: branch push = ownership signal).
   - Flip card Status from `Ready` to `In Progress` via `transition_card` protocol action.
   - Create worktree at `$HOME/.config/superpowers/worktrees/<repo>/claim/<kanban-id>-<key-slug>-<title-slug>`.
3. On script failure: read stderr output carefully. Common causes:
   - Status already `In Progress` (race condition — another Consumer claimed it).
   - Branch name collision (duplicate slugs — surface to architect).
   - GitHub API auth failure (check `gh auth status`).
   Surface the error to the architect rather than silently retrying; double-claims
   corrupt the audit trail.
4. Invoke `board-superpowers:auditing-actions` (action_id 100, resolve entry).

**Branch naming**: `board-superpowers:board-canon` § "Branch naming" declares the canonical
v0.5.0+ format: `claim/<kanban-id>-<key-slug>-<title-slug>`. The `<kanban-id>` is the
active kanban's identifier (e.g., `default` for the default GitHub Project registration).
`<key-slug>` is the issue number slugified. `<title-slug>` is the card title downcased,
spaces → hyphens, non-alphanumeric stripped. Example: `claim/default-42-refactor-cache`.
Do NOT re-derive this format here — `board-canon` is the single source of truth.

## A3 — Spec fetch

The card body's "Spec" section contains a thin pointer (relative or absolute path, or GitHub
URL) to the authoritative spec document(s). Resolve it:

1. If relative path: read from the spec directory in the worktree (typically under `docs/` in the project).
2. If GitHub URL: read via `gh` or use the worktree's local checkout if available.
3. Create the plan-brief location if not present:
   `docs/board-superpowers/plans/card-<N>-brief.md` in the worktree (gitignored).

The plan brief is a per-card reformatting of the card's ACs + spec context, used by
`superpowers:writing-plans` and `superpowers:subagent-driven-development` in Stage 2.

After A3, proceed directly to Stage 2 (implementation). The worktree is your isolated work
surface — do NOT `cd` back to the repo root for any implementation work.

## Cross-session resume (A2 resume path)

If a prior Consumer session claimed the card but didn't complete:

1. Check that `claim/<kanban-id>-<key-slug>-<title-slug>` branch exists on remote.
2. Verify the worktree is still at `$HOME/.config/superpowers/worktrees/<repo>/claim/...`.
3. Read the card body + comments for the last known state.
4. Run `git status` + `git log --oneline main..HEAD` in the worktree.
5. Pick up from where it left off (Stage 2 or later).

Do not re-run `claim-card.sh` on an already-claimed card — that will fail because the Status
is already `In Progress`. Resume from the existing worktree.
