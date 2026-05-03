# Runtime mechanism

End-to-end picture of what happens between "the user types a message" and "a downstream skill runs". The entry skill's body covers the *what*; this reference covers the *how*.

## The pipeline at a glance

```
┌──────────────────┐  1. SessionStart fires
│  Agent harness   │─────────────────────────────────────┐
│  (CC / Codex)    │                                     │
└────────┬─────────┘                                     │
         │ 2. user message + hook payload appear         │
         ▼                                               │
┌────────────────────────────┐    SessionStart hook     ▼
│   using-board-superpowers  │◀────  emits payload  ──hooks/session-start.sh
│        (entry skill)        │   - version banner          
│  3. reliable gate runs:     │   - dep / routing alert     
│     dep check (machine mode)│   - INVOKE: <skill>         
│     state probe              │   - REASON: <line>          
│     marker consumption       │
└──────────┬─────────┬────────┘
           │ routes  │ on dep / state issue: stop here
           ▼         ▼
┌─────────────────────────┐
│   Molecular skill body  │   reads contract from atomic skills,
│  (briefing-daily /       │  invokes scripts under ${CLAUDE_PLUGIN_ROOT}/scripts/,
│   consuming-card / etc)  │  delegates discipline-work to superpowers/gstack
└──────────┬──────────────┘
           │ on every mutating action
           ▼
┌────────────────────────────────┐
│   classifying-actions (atomic) │  decides A / R / N
└──────────┬─────────────────────┘
           ▼
┌────────────────────────────────┐
│   auditing-actions  (atomic)   │  writes 1 row (A) or 2 rows (R)
└──────────┬─────────────────────┘
           ▼
┌────────────────────────────────┐
│  scripts/audit-log-write.sh    │  → BYO RDBMS  OR  audit-local.jsonl
└────────────────────────────────┘
```

The pipeline is asynchronous in only one place — between "PR opens" and "PR merges", which is the user / reviewer's call to make. Everything else is synchronous within a single agent turn.

## SessionStart hook

`hooks/session-start.sh` fires once per session, on both CC and Codex CLI. It is **self-contained** by design: it MUST NOT source `scripts/lib/common.sh`, because a broken or missing lib must never prevent session startup. Helpers are duplicated inline and kept in lockstep with the canonical implementations in `common.sh` (per the contract documented in `hooks/AGENTS.md`).

The hook does two things:

1. **Dep alert.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh --machine` and surface a banner if anything is missing or if the consuming repo's `AGENTS.md` / `CLAUDE.md` lacks the canonical routing block.
2. **Intent injection.** Probe state files and, when conditions match, emit at most one `INVOKE: <skill>` + `REASON: <line>` pair into the session's `additionalContext`. Currently the only emitted marker is `INVOKE: bootstrapping-repo`, surfaced when the host manifest at `~/.board-superpowers/manifest.yml` or the per-repo state file at `~/.board-superpowers/repos/<normalized>/state.yml` is absent.

The hook always exits 0 even when checks fail — non-zero exit blocks the session, which is strictly worse than the plugin running unconfigured. Same reason the hook keeps under a 10-second budget: anything that would slow the session start is forked off rather than awaited.

## INVOKE marker grammar

```
INVOKE: <skill-name>
REASON: <plain-ASCII rationale; ≤120 chars; punctuation only ". , ; : - ( )">
```

At most one marker per payload. The `REASON:` value is sanitized — anything outside the whitelist is stripped, line endings normalized, length truncated. The entry skill consumes the marker as a fast-path routing decision but ALWAYS runs its own probes anyway, because `SessionStart` delivery is best-effort: if the hook silently misfires (timeout, disabled, broken interpreter), the entry skill must still route correctly.

## The reliable gate (3 steps the entry skill always runs)

1. **Dep check.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh --machine`. Empty stdout = OK. Non-empty stdout means a dep is missing OR the routing block isn't injected — surface to the user before any further routing.
2. **State probe.** Read `~/.board-superpowers/manifest.yml` and `~/.board-superpowers/repos/<normalized>/state.yml`. Use `bsp_primary_repo_root "${PWD}"` to resolve `<normalized>` — never `git rev-parse --show-toplevel` directly; details below.
3. **Marker consumption.** Read this turn's `additionalContext` for an `INVOKE:` line. Recognized skill name → route immediately. Unknown name → surface "unrecognized hook intent marker"; do not guess. Marker absent but step 2 found state files missing → still route to `bootstrapping-repo` (this is what "reliable" means — the gate doesn't depend on the hook firing).

## `bsp_primary_repo_root` vs `git rev-parse --show-toplevel`

When a session runs *inside* a `git worktree`, `git rev-parse --show-toplevel` returns the **worktree** path, not the primary repo path. That worktree path normalizes (via `bsp_normalize_repo_path`) to a different `<normalized>` than the canonical repo. Any per-repo state lookup keyed by `<normalized>` (the host-local `state.yml`, the `audit-local.jsonl` fallback) would miss, and the hook / entry skill would falsely think this is an un-bootstrapped repo and re-emit the `INVOKE: bootstrapping-repo` marker.

`bsp_primary_repo_root` (in `scripts/lib/common.sh`, also duplicated inline as `primary_repo_root` in `hooks/session-start.sh`) sidesteps this by reading `git rev-parse --git-common-dir` — which always points at the primary repo's `.git/` regardless of which worktree the call is made from — and returning `dirname` of that. Always use this helper when you need to derive `<normalized>`; never the toplevel.

## `bsp_pick_worktree_dir` — three-priority resolver

Where to *put* a new worktree is a separate question from *which repo am I in*. `bsp_pick_worktree_dir` resolves the base directory (not per-repo, not per-branch) by three priorities:

1. `$BOARD_SP_WORKTREE_DIR` if set and absolute.
2. `<repo_root>/.worktrees/` — only when the directory exists AND is gitignored. The check is `git check-ignore -q .worktrees`. A stray un-gitignored `.worktrees/` is rejected so accidentally committed worktree state can't poison the resolver.
3. Default: `${HOME}/.config/superpowers/worktrees`.

A relative `$BOARD_SP_WORKTREE_DIR` falls through to priority 2/3 with a stderr warning, rather than hard-failing — env vars are user-set, a typo shouldn't break the session.

## Routing block: fence sentinels and target markers

The plugin injects a canonical routing block into the consuming repo's `AGENTS.md` and `CLAUDE.md`. Two distinct marker pairs are involved:

- **Source-file fence sentinels** (in the plugin's `references/agentsmd-routing.md`):

  ```
  <!-- routing-block:start -->
  ...content the helper extracts and injects...
  <!-- routing-block:end -->
  ```

  Anything above the start fence or below the end fence is plugin-maintainer prose, not injected.

- **Target-file injection markers** (in the consumer repo's `AGENTS.md` / `CLAUDE.md`):

  ```
  <!-- board-superpowers:routing -->
  ...injected content...
  <!-- /board-superpowers:routing -->
  ```

The two pairs use deliberately different keywords so a naive `find()` for the target markers against the source returns nothing — the source carries fences, the target carries injection markers.

## Tamper-hash detection

When the routing block is injected, `bsp_inject_routing_block` (in `scripts/lib/common.sh`) computes a SHA256 over the normalized fence-bounded bytes of the source and writes the hex digest into `~/.board-superpowers/repos/<normalized>/state.yml` under `routing_blocks[].block_hash`. The normalization is deterministic — single trailing newline normalization plus consistent line endings — so the same source always yields the same hash.

Re-injection re-hashes. If the user has hand-edited the injected block in their `AGENTS.md`, the live hash diverges from the recorded one; the next bootstrap or migration run detects the drift and prompts the user before overwriting. The block can also be a stub redirect (e.g., a one-line "see other file"), in which case no hash is recorded; a missing entry in `routing_blocks[]` is the signal that the target was deliberately stubbed.

## Cross-platform path resolution

| Variable | Claude Code | Codex CLI |
|----------|-------------|-----------|
| Plugin root env | `${CLAUDE_PLUGIN_ROOT}` | `${CODEX_PLUGIN_ROOT}` |
| Hook discovery | Auto-discovers `hooks/hooks.json` | Does NOT auto-discover; user runs `scripts/register-codex-hooks.sh --install-user` once |
| Skill invocation tool | `Skill` tool | `skill` tool |
| `additionalContext` field | Inside `hookSpecificOutput` | Same field name |

Always read the plugin root via `bsp_plugin_root()` from `scripts/lib/common.sh` so the same script runs on both platforms; never hard-code either env var.

## Where state lives at the end of a turn

A turn that performed a mutating action leaves traces in three places:

1. **GitHub.** Card Status, branch, PR — the user-visible board.
2. **Host disk.** `~/.board-superpowers/repos/<normalized>/state.yml` for `last_seen_version_in_repo` and `routing_blocks[].block_hash` records; `~/.board-superpowers/credentials.yml` (chmod `0600`) for `audit_db_url`; `~/.board-superpowers/repos/<normalized>/audit-local.jsonl` if the audit DB was unreachable and the write fell back to local.
3. **Audit DB.** A `audit_log` row for every A-class action; two rows (propose + resolve) for every R-class action.

A read-only turn leaves only telemetry; mutations always leave at least one audit row, regardless of the BYO DB's reachability.

## Failure modes the pipeline tolerates

The pipeline is designed to keep working when individual links degrade:

- **Hook silent.** The entry skill's reliable gate runs the same probes the hook does, so a missed `INVOKE:` marker is not load-bearing.
- **Audit DB unreachable.** `audit-log-write.sh` falls back to `audit-local.jsonl` and stamps the row's `mode` field with the cause (no DB URL configured, network unreachable, etc.). A later sync job (when one exists) can replay the jsonl into the DB once it returns.
- **Worktree base dir missing.** `bsp_pick_worktree_dir` always returns a path; if priority 2 is invalid the resolver falls through to the default `~/.config/superpowers/worktrees`.
- **Routing block tampered.** The hash mismatch is detected at bootstrap / migration time; the user is prompted. Mid-session work continues.

What the pipeline does NOT tolerate is a missing `gh` or missing `git` — those are surfaced as dep-check failures and routing stops at the gate. The user fixes the binary, reruns, and the session continues from there.

Corollary: every audit row is durable but not necessarily in the database the user expects. If you're querying for evidence of a recent action and the DB has no row, check the per-host `audit-local.jsonl` before assuming the action did not happen — degraded writes always leave a trace, just possibly in a different store than usual.
