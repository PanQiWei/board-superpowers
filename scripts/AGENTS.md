# scripts/ — bash tooling contract

> **Before any work in this directory** (writing, editing,
> renaming a script — not just running an editor):
>
> 1. Read [`../PLUGIN_DEVELOPMENT.md`](../PLUGIN_DEVELOPMENT.md)
>    — especially § "What this means for board-superpowers"
>    items 3 (Hooks ↔ scripts split) and the broader CC vs
>    Codex env-var differences. There is no standalone
>    "Scripts" section; conventions are woven through.
> 2. Note: this directory is for **AI-callable tools**, not
>    user-facing CLIs. The plugin is consumed via skills /
>    slash commands, not a dedicated CLI binary.
> 3. **If your work touches setup-stages files** —
>    `stages-registry.yml`, `stages_lib/**`,
>    `stages-registry.schema.json`, `lib/_canonical.py`, or any
>    helper consumed by the lifecycle diff — **also Read
>    [`../SETUP_STAGES_DEVELOPMENT.md`](../SETUP_STAGES_DEVELOPMENT.md)**
>    end-to-end before the first edit. The guide carries the
>    judgment calls (when to add a stage vs alternatives,
>    common axis misclassifications, the canonicalization
>    invariant, anti-patterns) the spec doesn't encode.
>    Same-PR contract: any change that makes the guide stale
>    fixes the guide in this PR.

This contract is the per-directory operational checklist for
bash tooling. The full platform contract lives in
`PLUGIN_DEVELOPMENT.md`; this file is the thin "what every PR
under `scripts/` must satisfy" view.

## Self-contained scripts

Two scripts in this directory are **deliberately self-contained**
— they do NOT source `scripts/lib/common.sh`:

- `scripts/check-deps.sh` — must run before `common.sh` is
  available (it is the dep-check shared primitive). A broken
  or missing lib cannot derail dep detection.
- (Hook scripts under `../hooks/` follow the same rule per
  [`../hooks/AGENTS.md`](../hooks/AGENTS.md) Invariant 1, but
  they live in a different directory.)

Helpers needed by these self-contained scripts are duplicated
INLINE; keep the two implementations in lockstep (existing
precedent: `bsp_sanitize_reason_line` is mirrored between
`session-start.sh` and `common.sh`).

## Strict-mode bash

Every script:

- Begins with `#!/usr/bin/env bash` (not `#!/bin/bash` —
  macOS ships bash 3.2 at `/bin/bash`; we target bash 3.2+
  via `env`).
- Sets `set -euo pipefail` before sourcing
  `scripts/lib/common.sh`.
- Sources `common.sh` for shared helpers (path resolution via
  `bsp_plugin_root()`, audit-log writers via
  `bsp_audit_local_write()`, etc.). Never hardcode
  `${CLAUDE_PLUGIN_ROOT}` (CC-only) or `${CODEX_PLUGIN_ROOT}`
  (Codex-only) — `bsp_plugin_root()` resolves correctly under
  both.

## shellcheck `-x` clean (CI gate)

Every script and its sourced helpers must pass
`shellcheck -x scripts/**/*.sh hooks/*.sh` cleanly. The `-x`
flag follows `source` directives so violations in `common.sh`
are caught at every caller. CI fails on warnings.

## Header comment

Every script's first non-shebang block is a one-paragraph
header comment explaining what the script does, what its
inputs are (env vars, args, stdin), and what it writes
(stdout, files, exit codes). This header is read both by
humans and by AI agents that source-walk the directory.

## Exit-code / stdout contracts

Scripts have well-defined contracts:

- **Exit code 0** = success. Non-zero exit codes are
  documented in the header comment (e.g., `1` = generic
  failure, `2` = preflight check failed, `3` = user
  cancellation).
- **stdout** = structured output for the caller (often JSON
  or one-record-per-line). Don't mix logging and structured
  output on the same stream.
- **stderr** = human-readable progress / warnings / errors.

Hooks (under `../hooks/`) follow the same conventions plus the
hook-specific `hookSpecificOutput.additionalContext` payload
shape for intent-injection markers (see
[`../hooks/AGENTS.md`](../hooks/AGENTS.md)).

## Where the long-form rules live

- Full bash conventions, `common.sh` API surface, Codex CLI vs
  CC env-var differences, plugin manifest schema →
  [`../PLUGIN_DEVELOPMENT.md`](../PLUGIN_DEVELOPMENT.md).
- Hook-specific contracts (timeout, marker grammar) →
  [`../hooks/AGENTS.md`](../hooks/AGENTS.md).
- Setup-stages system (registry, 5-callable contract,
  applicable_when, settings layering, anti-patterns) →
  [`../SETUP_STAGES_DEVELOPMENT.md`](../SETUP_STAGES_DEVELOPMENT.md).
