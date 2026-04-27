---
name: bootstrapping-repo
description: Use when board-superpowers is being run for the FIRST time on a (host, repo) pair — when the host manifest at ~/.board-superpowers/manifest.yml is absent, or the per-repo state at ~/.board-superpowers/repos/<normalized>/state.yml is absent. Triggers on the SessionStart hook injecting an `INVOKE: bootstrapping-repo` marker (fast path) AND on user phrases like "set up board-superpowers", "first time on this repo", "bootstrap this repo", "I just installed the plugin". Apply this skill even when the user does not say "bootstrap" — any session whose state probe reveals the manifest or per-repo state is missing routes here. Do NOT use this skill once both state files exist; the regular Producer / Consumer skills take over from there.
when_to_use: Use when the SessionStart hook injected `INVOKE: bootstrapping-repo`, OR the user says "set up board-superpowers", "first time on this repo", "bootstrap this repo", "I just installed the plugin", "what do I need to do to start using this", OR the entry skill (using-board-superpowers) detects an absent manifest.yml / state.yml during its Layer 2 reliable-gate probe.
---

# bootstrapping-repo

This is the molecular skill that drives **first-time setup** of board-superpowers on a `(host, repo)` pair. It orchestrates the two bootstrap features defined in [`docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md`](../../docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md):

- **F-B1 (host bootstrap)** — once per host (machine). Writes `~/.board-superpowers/manifest.yml`.
- **F-B2 (per-repo bootstrap)** — once per `(host, repo)` pair. Validates the GitHub Project, writes `<repo>/.board-superpowers/config.yml`, appends a `.gitignore` entry, sets up BYO-RDBMS audit credentials, injects the routing block into `CLAUDE.md` + `AGENTS.md`, and writes the host-local per-repo `state.yml`.

The skill is a thin orchestration layer over two scripts: `scripts/bootstrap-host.sh` (F-B1) and `scripts/bootstrap-project.sh` (F-B2). Both scripts are idempotent — re-running this skill on an already-bootstrapped repo is a no-op.

## When this skill fires

Two paths deliver the architect into this skill:

1. **Hook fast path**: `hooks/session-start.sh` detects `manifest.yml` or per-repo `state.yml` is absent and injects `INVOKE: bootstrapping-repo` + `REASON: <one-liner>` into the session via `additionalContext`. The entry skill `using-board-superpowers` consumes the marker and routes here.
2. **Architect-spoken fallback**: the architect says "set up board-superpowers", "first time on this repo", "bootstrap this repo", or similar. The entry skill matches the phrase and routes here.

Both paths arrive at the same procedure below. The hook is best-effort (CC `SessionStart` delivery is unreliable per the spec); the entry skill's Layer-2 state probe is the reliable gate. This skill itself does NOT re-probe — by the time control reaches here, the entry skill has confirmed at least one of the state files is missing.

## Required atomic dependencies

- `board-superpowers:board-canon` — read-only schema authority. Step 2's preflight relies on the canonical 6-status field contract documented there. (Not invoked as a skill at v1-minimum; the contract is a static reference.)

The deferred atomic `auditing-actions` would normally consolidate the audit-log writes; in v1-minimum the inline jsonl writer below stands in.

## Procedure

The full sequence is four steps. Each step is independently idempotent and surfaces progress to the architect.

### Step 1 — F-B1 host bootstrap

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-host.sh"
```

The script:

1. Verifies `~/.board-superpowers/` exists with mode 0700 (creates it if absent).
2. Writes `manifest.yml` with `schema_version: 1`, `host_bootstrapped_at: <iso8601>`, `last_seen_version: <plugin version>`. Atomic via `mktemp` + `mv`.
3. If the manifest already exists with the same `last_seen_version`, exits 0 with no write (idempotent fast path).
4. Prints the absolute manifest path to stdout on success.

**Surface to the architect**: report whether the manifest was newly written, refreshed (version bump), or already current. On failure (exit code 1), surface the script's stderr and STOP — do not attempt step 2 with a broken host state.

`--force` is available as an escape hatch (overwrites unconditionally) but should be reserved for migration / dev scenarios; the architect must explicitly request it.

### Step 2 — preflight check for F-B2

Before running F-B2 the architect must confirm two things:

1. **GitHub Project v2 exists** with the canonical 6-option Status field — `Backlog → Ready → In Progress → In Review → Done → Blocked` (the order is load-bearing). Per ADR-0001's substrate-commitment posture, the script does NOT create the project — Project v2 single-select option creation via API is unreliable with standard tokens.

   If the project does NOT exist yet, walk the architect through `references/project-creation-walkthrough.md` (UI steps), wait for them to confirm completion, then proceed.

2. **`OWNER/PROJECT_NUMBER` resolved**. The architect provides this (e.g., `PanQiWei/4`). The script needs both to query the project and validate the Status field.

R-class discipline applies here too — do NOT proceed to step 3 without the architect's explicit confirmation that the Status field is set up correctly. F-B2's Status validation will hard-abort if the field drifts; that abort is recoverable but expensive (architect fixes UI, re-runs).

### Step 3 — F-B2 per-repo bootstrap

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-project.sh" \
  --owner "${OWNER}" \
  --project "${PROJECT_NUM}" \
  --repo-root "${REPO_ROOT}"
```

`--repo-root` defaults to `${CLAUDE_PROJECT_DIR:-$PWD}` resolved via `git rev-parse --show-toplevel`. Pass it explicitly when the architect is operating from a worktree to guarantee the correct primary-repo path is used.

The script handles the five F-B2 sub-steps + step 4 (routing injection) + step 3 (state.yml write) internally:

| F-B2 sub-step | What `bootstrap-project.sh` does |
|---------------|----------------------------------|
| 2a — labels | `setup-labels.sh` — creates the 9 standard labels (`type:feature`, `type:bug`, `type:chore`, `type:refactor`, `type:epic`, `size:XS`, `size:S`, `size:M`, `size:L`). Idempotent — pre-existing labels skipped. |
| 2b — Status field validation | Reads the project's Status field via `gh project field-list`; aborts with exit 2 if the 6 options are missing or out of order. |
| 2c — config.yml write | Renders `<repo>/.board-superpowers/config.yml` with `project: "OWNER/NUM"` and `wip_limit: 5`. Skipped when present unless `--force`. |
| 2d — .gitignore append | Appends an idempotent block ignoring `.board-superpowers/claims/`. |
| 2e — credentials.yml | Walks BYO-RDBMS DSN setup. Accepts the 6-scheme allowlist (`postgresql://`, `postgres://`, `mysql://`, `mysql+pymysql://`, `sqlite://`, `sqlite3://` per ADR-0009). Architect can decline → all A-class actions degrade to R-class until they reconfigure. |
| step 4 — routing injection | Appends the canonical routing block to BOTH `CLAUDE.md` and `AGENTS.md` between the marker pair `<!-- board-superpowers:routing -->` / `<!-- /board-superpowers:routing -->`. Records each block's SHA256 hash for F-B4 tamper detection. |
| step 3 — state.yml write | Writes `~/.board-superpowers/repos/<normalized>/state.yml` with `schema_version: 1`, `repo_bootstrapped_at`, `last_seen_version_in_repo`, `features_enabled: [bootstrap.host, bootstrap.per_repo]`, and the `routing_blocks[]` array recorded during step 4. |

**Surface to the architect** after each F-B2 sub-step completes:

- Number of labels created / skipped at 2a.
- Status field validation result at 2b (PASS / drift detected — print the specific mismatched options).
- File path of `config.yml` at 2c.
- Lines appended to `.gitignore` at 2d (or "already present" on idempotent skip).
- BYO-RDBMS scheme accepted (or declined with degradation notice) at 2e.
- Files routing-injected at step 4 (CLAUDE.md / AGENTS.md / both / neither).
- Final state.yml absolute path at step 3.

On exit codes 2 / 3 / 4 / 5, surface the script's stderr verbatim and STOP — F-B2 has surface-specific failure paths (Status drift, label delegation, BYO-RDBMS misconfiguration, orphan routing markers) and the script's error message names the recovery path.

### Step 4 — deliver the first-time user guide

After F-B2 completes successfully, hand the architect the post-bootstrap orientation. Load the content from `references/first-time-user-guide.md` and present it. The guide covers:

- How to create the first card (Manager session via `managing-board` intake routine, or hand-pasted in the GitHub UI using the `board-canon` Card body schema).
- How to claim a card (`[board-card:#N]` token in a fresh session).
- Where state files live (host manifest, per-repo state, in-repo config, gitignored claims).
- Two-role mental model — when to invoke `managing-board` vs `consuming-card`.

The introduction in `references/intro.md` covers conceptual onboarding (what this plugin is, the cross-plugin composition with `superpowers` + `gstack`, common first-time questions). Surface it inline if the architect asks "what does this thing actually do" during step 4 — otherwise treat it as on-demand reading.

## How mutating actions are handled (v1-minimum R-class default)

Every mutating action this skill orchestrates follows the propose → ack → act → audit discipline. F-B1's manifest write is borderline (D-AUTONOMY-1 classifies it A — trivial first-run setup), but at v1-minimum every step is treated R-class and audit-logged. When `classifying-actions` ships, the matrix below moves into that atomic and this section gets a single-line cross-reference.

```
For each mutating action:
  1. Propose the action to the architect with a one-line description.
  2. Wait for explicit acknowledgement.
  3. Act (run the script / write the file).
  4. Append an audit-log entry via bsp_audit_local_write
     (defined in scripts/lib/common.sh).
```

Some actions may be classified auto-act-OK by per-repo or per-user `autonomy_overrides:` in `.board-superpowers/config.yml`; until those overrides are configured, treat every action as requiring acknowledgement.

### Action ID catalog (inlined, deferred replacement by `classifying-actions`)

```
Bootstrap actions:
  bootstrap-host          — F-B1 manifest write (mode 0644, ts + version)
  bootstrap-project-2a    — labels create (delegates to setup-labels.sh)
  bootstrap-project-2b    — Status field validation (read-only; no audit)
  bootstrap-project-2c    — config.yml write (project + wip_limit)
  bootstrap-project-2d    — .gitignore append (idempotent block)
  bootstrap-project-2e    — credentials.yml write (chmod 0600; DSN allowlist)
  bootstrap-project-4     — routing block injection (CLAUDE.md + AGENTS.md)
  bootstrap-project-3     — state.yml write (host-local per-repo)
```

All R-class in v1-minimum-degraded mode. The action_id values land in the formal D-AUTONOMY-1 catalog when `classifying-actions` ships.

### Audit log entry

Each acted-on action appends one jsonl line to `~/.board-superpowers/repos/<normalized>/audit-local.jsonl` via `bsp_audit_local_write` from `scripts/lib/common.sh`:

```bash
bsp_audit_local_write "${REPO_ROOT}" "<action_id>" R bootstrapping-repo "<one-line summary>"
```

This is the v1-minimum-degraded interim trace per the [`SKILLS.md`](../../SKILLS.md) v1-minimum degradation note for `auditing-actions`. The full BYO-RDBMS schema lands when `auditing-actions` ships — at that point this inline write becomes a single-line call to the atomic.

## Idempotency invariants

- **Re-running this skill on an already-bootstrapped repo is a no-op.** F-B1 detects an existing manifest with the current version and skips the write. F-B2 detects an existing `state.yml` and skips the per-repo work entirely (per the spec § 1.5.2 trigger condition). The architect can re-invoke this skill safely; nothing is mutated when nothing needs to change.
- **`--force` is the escape hatch.** Both scripts accept `--force` to overwrite unconditionally. Only use this on explicit architect request — typical scenarios are recovering from a partial bootstrap, dev-loop schema work, or migrating a corrupted manifest.
- **F-B1's idempotency fast path is the version-equal check**, not a "does the file exist" check. A version bump after a plugin upgrade triggers a manifest refresh on next session — that's the F-B3 path (deferred to `migrating-repo-version`), but the host-side write itself is the same atomic mv used here.

## Failure paths (brief)

| Where | Symptom | Recovery |
|-------|---------|---------|
| F-B1 | exit 1 — bad plugin root, mkdir failure, write failure | Surface the script's stderr; do NOT attempt F-B2; ask the architect to inspect filesystem permissions or `${CLAUDE_PLUGIN_ROOT}` wiring. |
| F-B2 step 2b | exit 2 — Status field options missing or out of order | Surface the named mismatched options; tell the architect to fix in the GitHub Project UI; re-run this skill after they confirm. |
| F-B2 step 2a | exit 3 — `setup-labels.sh` delegation failed | Usually a token-scope issue (`gh auth status` to verify). After fix, re-run. |
| F-B2 step 2e | exit 4 — BYO-RDBMS DSN invalid (bad scheme; sqlite parent unwritable; interactive retry budget exhausted) | Surface the specific error from the script; offer two paths — fix the DSN or decline BYO-RDBMS (sets degraded R-class default). |
| F-B2 step 4 | exit 5 — orphan routing markers (only one of `<!-- board-superpowers:routing -->` / `<!-- /board-superpowers:routing -->` present in the target file) | Surface the script's verbatim error; abort. The architect inspects `CLAUDE.md` / `AGENTS.md`, removes the orphaned marker, then re-runs. Do NOT auto-repair — the architect's intent is unknown. |

In every failure path, leave the pre-bootstrap state intact: the scripts use atomic write semantics so a half-completed F-B2 does not leave a half-written `state.yml` claiming bootstrap completed.

## Anti-pattern: bootstrapping without consent

This skill MUST NOT run F-B2 silently. The first interaction with a fresh repo is the architect's introduction to the plugin — the routing block injection alone modifies two files (`CLAUDE.md`, `AGENTS.md`) the architect has been editing by hand. Auto-mutating those files without consent burns trust in a way that's hard to recover from.

Always:

1. Surface the F-B1 result (manifest written / refreshed) before asking about F-B2.
2. Confirm `OWNER/PROJECT_NUMBER` and the GitHub Project's Status field state before invoking F-B2.
3. Surface each F-B2 sub-step's outcome as it completes — do NOT batch-report at the end.

If the architect declines BYO-RDBMS at step 2e, the bootstrap completes and the friction is captured (every A-class action becomes R-class until they reconfigure). That trade-off is documented per ADR-0006's "trade-off explicitly registered" note — surface it once at decline time, do NOT nag on every subsequent session.

## Cross-platform notes

This skill works on both Claude Code and Codex CLI. Both `bootstrap-host.sh` and `bootstrap-project.sh` resolve their plugin root via `bsp_plugin_root` (Claude uses `${CLAUDE_PLUGIN_ROOT}`, Codex uses path-derivation) so the architect's invocation works without platform-specific argument shaping.

Routing block injection is dual-target by design — `CLAUDE.md` (for Claude Code's auto-load) and `AGENTS.md` (for Codex CLI's auto-load) both receive the same content, which is why the architect's session lands cleanly regardless of which platform they next open in this repo.
