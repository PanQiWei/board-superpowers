# operating-kanban — Form A (bash CLI) reference

Form A is the bash-CLI invocation form: the projection's reference file documents shell invocations (e.g., `gh project ...`, `gh issue ...`, `gh api graphql ...`) wrapped through the plugin's `scripts/lib/common.sh` helpers; this skill runs them and parses stdout / stderr / exit-code per the conventions below.

Form A is the **only live invocation form at v0.5.0** — the GitHub Project v2 projection ships as Form A. Form B and Form C are documented for v1.x roadmap projections. This file is therefore both an authoring guide for future Form A projections AND the operational contract for the v0.5.0 dispatch path.

## When backends choose Form A

A projection ships as Form A when its backend has:

- A stable, scriptable CLI binary (`gh`, `linear` CLI, `glab`, `jira-cli`, etc.).
- No vendor-shipped MCP server (or one whose tool surface is too coarse to cover the eight protocol actions cleanly).
- A response shape that survives shell pipelines — JSON-on-stdout is preferred; tab-separated is acceptable; everything else needs wrapping.

The v0.5.0 GitHub Project v2 projection chose Form A because `gh` is stable, scriptable, ubiquitously installed on architect hosts, and exposes enough of the GraphQL surface (via `gh api graphql`) to cover the eight actions. Linear has an MCP server (Form B candidate) AND a CLI (Form A candidate) — its v1.x landing is currently planned as Form B per the registration cost / multi-tool-call latency trade-off.

## Invocation conventions

### stdout

- **Preferred**: JSON. The projection reference file documents the expected schema; this skill parses with `python3 -c 'import json,sys; ...'` (no `jq` dependency — shellcheck-clean and cross-host portable).
- **Acceptable**: tab-separated values when the underlying CLI does not emit JSON for that command. The reference file documents column order.
- **Forbidden**: free-form prose. If a CLI emits prose by default, the reference file MUST specify the JSON-mode flag (`--json`, `--format json`, etc.) to bypass it.

### stderr

- All CLI diagnostics (rate-limit warnings, deprecation notices, network retries) flow through stderr verbatim. This skill captures stderr but does NOT parse it — the caller decides whether to surface to the architect or log silently per the failure-mode taxonomy.
- The skill MUST NOT swallow stderr. Even on success, captured stderr is part of the return record so the caller can detect deprecation notices or rate-limit pressure.

### Exit codes

Per ADR-0007 plugin runtime constraints, every helper script invoked through Form A obeys strict exit-code conventions:

| Code | Meaning |
|------|---------|
| `0` | Success. Stdout contains the documented payload. |
| `1` | Generic failure. Stderr contains the diagnostic. |
| `2` | Pre-condition violation (illegal transition, refused claim, race-loss). Stderr names the violation. |
| `3` | Configuration / dependency missing (gh not installed, gh not authenticated, projection's project_ref invalid). Stderr names the dependency. |
| `4` | Transient failure (network timeout, rate-limited, 5xx). Caller MAY retry. |
| `≥5` | Reserved for projection-specific extension; reference file documents per-projection. |

This skill maps the exit code to a typed return shape; the caller's own retry/escalation policy reads the typed shape, never the raw exit code.

## Helper preference — `bsp_*` over raw CLI

`scripts/lib/common.sh` exposes a `bsp_*` helper family that the projection reference file SHOULD prefer over raw CLI invocations:

- `bsp_gh_field_id <owner> <project-num> <field-name>` — resolves a Status / Type / Size field's GraphQL node ID. Cached per session; avoids repeat GraphQL roundtrips.
- `bsp_gh_field_option_id <owner> <project-num> <field-name> <option>` — resolves a single-select field option's ID. Cached.

For data the helpers do not yet cover, fall back to the underlying `gh` invocation parsed with `python3 -c 'import json,sys; ...'`:

- Project GraphQL node ID (given `<owner> <project-number>`) → `gh project view <project-number> --owner <owner> --format json` and read `.id`.
- Project v2 item ID (given `<project-id> <issue-number>`) → `gh project item-list <project-number> --owner <owner> --format json --limit 200` and filter by `.items[].content.number == <issue-number>` to read `.id`.

Direct `gh project field-list ...` / `gh project item-list ...` calls work but issue redundant GraphQL queries every invocation. The helpers above are not optional for performance; they ARE optional for correctness — fresh projections may inline the raw call during initial authoring and refactor to helpers later.

The reference file documents which helper covers which action. When a new helper is needed, it lands in `scripts/lib/common.sh` in the same PR as the projection update, per the same-PR contract.

## Idempotency property — per `gh` call shape

Idempotency is per-call, not per-action. The same protocol action may be idempotent on Form A and not on Form B/C, or vice versa. For the v0.5.0 GitHub projection:

| `gh` call | Idempotent? | Notes |
|-----------|-------------|-------|
| `gh issue view`, `gh project item-list`, `gh api graphql` (read-only) | Yes (read-only) | Protocol-level reads are trivially idempotent. |
| `gh project item-add` | Yes (returns the same item ID for an already-added Issue) | Re-adding an Issue already on the project succeeds with the existing item ID; useful for `create_card` retries. |
| `gh project item-edit --field-id <Status> --single-select-option-id <X>` | Yes (no-op when current value equals target) | Protocol-level `transition_card` to current status is a successful no-op per the protocol contract. |
| `gh issue create` | **No** | Re-running creates a duplicate Issue. Callers guard `create_card` against duplicates by reading the board first. |
| `gh issue comment` | **No** | Each call posts a new comment. Protocol-level `comment_on_card` is documented as not-idempotent. |
| `git push origin <branch>` | Yes (push of the same SHA succeeds with "Everything up-to-date"). | Used by `claim_card` for branch publication. |
| `git push origin --delete <branch>` | Conditional — first call succeeds, subsequent calls fail with "remote ref does not exist". The dispatcher treats the second-and-later as a successful no-op for `release_claim`. |

When in doubt, the reference file's `Idempotency` row in `action-dispatch.md` is authoritative. This file's table is the v0.5.0 snapshot for one projection; it does not generalize.

## Worktree-relative paths

Per ADR-0003 (worktree discipline) every Form A invocation runs from inside a worktree, not from the repo root. Helper scripts therefore:

- Resolve paths relative to `git rev-parse --show-toplevel` (the worktree root), NOT relative to `bsp_plugin_root` (the plugin install dir, host-shared).
- Read `<repo>/.board-superpowers/settings.yml` at the worktree root, NOT at the host-shared install dir.
- Write outbox / jsonl fallback under `<repo>/.board-superpowers/audit/`, with `<repo>` resolved per the same rule.

The convention is uniform across maintainer worktrees and Consumer worktrees; the dispatch layer never special-cases.

## Related

- `action-dispatch.md` — per-action dispatch shape, parameterized by Form. The Form A column is what this file's conventions concretize.
- `backend-selection.md` — how the active projection is resolved before any Form A invocation runs.
- `failure-mode-dispatch.md` — how Form A exit codes 1/2/3/4 map to caller-visible surfacing tiers.
- ADR-0007 — plugin runtime constraints (strict exit codes; stdout-as-data convention).
- `scripts/lib/common.sh` — the `bsp_*` helper implementations.
- The v0.5.0 reference projection: `references/github-project-v2.md` (lands in this PR's projection-reference batch; documents the per-action `gh` invocations per Form A conventions above).
