# hooks/ — hook script contract

> **Before any work in this directory** (writing, editing,
> adding a hook event, modifying timeout / payload — not just
> running an editor):
>
> 1. Read [`../PLUGIN_DEVELOPMENT.md`](../PLUGIN_DEVELOPMENT.md)
>    § "Hooks (`hooks/hooks.json`)" — the dual-platform (CC +
>    Codex CLI) contract every hook script in this repo
>    conforms to.
> 2. If adding a new hook event, also read
>    [`../docs/architecture/0005-contracts/02-hook-contracts.md`](../docs/architecture/0005-contracts/02-hook-contracts.md)
>    § "Intent-injection markers".
> 3. **Update BOTH `hooks.json` AND
>    [`../scripts/register-codex-hooks.sh`](../scripts/register-codex-hooks.sh)**
>    snippet generator — Codex CLI does not auto-discover
>    `hooks/hooks.json`, so a new event without an updated
>    register script silently breaks Codex installs.

This contract is the per-directory operational checklist for
hook authoring. The full platform contract lives in
`PLUGIN_DEVELOPMENT.md`; this file is the thin "what every PR
under `hooks/` must satisfy" view.

## Events wired

The plugin wires three events:

| Event | Script | Role |
|-------|--------|------|
| `SessionStart` (`startup` matcher) | `session-start.sh` | Layer 1 dep alert + intent injection (advisory; never blocks). |
| `PreToolUse` (`Edit` / `Write` / `MultiEdit` matchers) | `pre-tool-use.sh` | skills/AGENTS.md Process gate enforcement (CC-only — see Codex parity gap below). Blocks file mutations under `skills/**` until `example-skills:skill-creator` is invoked in the session. Inverts the "never block" stance — see Invariant 5. Canonical block path is `hookSpecificOutput.permissionDecision: "deny"` JSON on stdout (with belt-and-suspenders exit 2 + stderr legacy path). |
| `PostToolUse` (`Skill` matcher, CC-only) | `post-tool-use.sh` | Companion to the gate hook. Records `*skill-creator` invocations into a per-session flag file under `${TMPDIR:-/tmp}/board-superpowers-sessions/<session_id>/skill-creator-invoked.flag`. The Skill-tool input field is not canonically documented; the hook scans every string value in `tool_input` for a value ending in `skill-creator` to stay robust against field-name variation. |

Other events (`Stop`, `UserPromptSubmit`, etc.) are not yet active
but must use the same payload pattern when added later.

**Codex parity gap — gate hook pair is CC-only**: Codex CLI has
no `Skill` model-facing tool to PostToolUse-hook into, so the
flag-file lifecycle cannot complete on Codex. Registering
PreToolUse on Codex without a working PostToolUse companion would
deadlock every `skills/` edit. `scripts/register-codex-hooks.sh`
therefore writes only `SessionStart` to `~/.codex/hooks.json`;
earlier rollouts that briefly registered the gate pair on Codex
get auto-cleaned by the merge logic on the next install. The
gate degrades to doctrinal text in `skills/AGENTS.md` for Codex
sessions. Full rationale + recovery path:
[`../docs/architecture/0005-contracts/02-hook-contracts.md`](../docs/architecture/0005-contracts/02-hook-contracts.md)
§ "Codex parity gap — gate enforcement".

Full per-event contract:
[`../docs/architecture/0005-contracts/02-hook-contracts.md`](../docs/architecture/0005-contracts/02-hook-contracts.md).

## INVOKE / REASON marker grammar

Hook scripts emit intent-injection markers via
`hookSpecificOutput.additionalContext` (CC) /
`hookSpecificOutput` (Codex). The grammar is:

```
INVOKE: <skill>
REASON: <one-line rationale>
```

Multi-line `REASON:` continues with leading whitespace. The
entry skill `using-board-superpowers` consumes the marker as a
fast-path routing optimization — but the entry skill ALSO does
the same state probe itself, because CC `SessionStart` delivery
is unreliable. **The marker is an optimization, not a
correctness requirement.**

Full grammar contract:
[`../docs/architecture/0005-contracts/02-hook-contracts.md`](../docs/architecture/0005-contracts/02-hook-contracts.md)
§ "Intent-injection markers".

## 10-second timeout (mandatory)

Every hook script must declare `timeout: 10` in
`hooks.json`. Hook execution beyond 10 seconds blocks session
start / tool dispatch and degrades user experience. If a hook
needs slow work, fork-and-exit the slow part to a background
process and return the marker fast.

## Dual-platform registration

| Platform | Discovery |
|----------|-----------|
| Claude Code | Auto-discovers `hooks/hooks.json` at plugin load. No user action required. |
| Codex CLI | **Does NOT auto-discover.** Users run `scripts/register-codex-hooks.sh --install-user` (or `--install-repo`) once per Codex install to wire the same `SessionStart` script into `~/.codex/hooks.json` (or `<repo>/.codex/hooks.json`). |

The register script is idempotent and backs up the target file
before merging. When adding a new hook event:

1. Update `hooks.json` (CC side).
2. Update the snippet generator inside
   `scripts/register-codex-hooks.sh` (Codex side).
3. Both changes ship in the same PR.

## Hook invariants

Hook scripts under this directory have stricter rules than
`../scripts/` because they run in a context (CC / Codex
`SessionStart`) where any error must NOT block session
startup. Spec docs cite these by number — **keep the numbering
stable**; multiple references in
[`../docs/architecture/0005-contracts/02-hook-contracts.md`](../docs/architecture/0005-contracts/02-hook-contracts.md)
and
[`../docs/architecture/0004-component-architecture.md`](../docs/architecture/0004-component-architecture.md)
cite "invariants 1–4" as a fixed enumeration.

1. **Self-contained.** Hook scripts MUST NOT source
   `../scripts/lib/common.sh`. A broken or missing lib must
   never prevent CC / Codex startup. If you need helpers from
   `common.sh`, duplicate them INLINE and keep the two
   implementations in lockstep (existing precedent:
   `bsp_sanitize_reason_line` in `session-start.sh`). This
   forces shebang `#!/usr/bin/env bash` + `set -euo pipefail`
   inline at the top of every hook script — you cannot lean on
   `common.sh`'s strict-mode helpers.
2. **Sanitize.** All text the hook injects into the session
   context (REASON lines, `additionalContext` payload, any
   marker body) MUST be sanitized — control chars stripped,
   newlines normalized, JSON-breaking sequences escaped — via
   `bsp_sanitize_reason_line` or its inline equivalent. An
   unsanitized REASON breaks the JSON envelope at best and
   leaks unintended content into the model's context at
   worst.
3. **Never block (advisory hooks).** Advisory hooks
   (`SessionStart`, future `Stop`, etc.) MUST exit `0` even
   when internal checks fail — non-zero exit codes block
   session start, which is a strictly worse failure than the
   plugin running unconfigured. Per
   [`../docs/architecture/0005-contracts/02-hook-contracts.md`](../docs/architecture/0005-contracts/02-hook-contracts.md)
   § "Exit codes": *"board-superpowers' invariant: advisory
   hook failures MUST NEVER block session start."* Safety
   hooks (Invariant 5) are exempt.
4. **10-second budget.** Declared in `hooks.json` (see
   "10-second timeout" section below). Keep new work well
   under it; long-running work should fork-and-exit a
   background process and return the marker fast.
5. **Gate-blocking inversion (safety hooks only).** When a
   hook's purpose is to enforce a safety gate (e.g.,
   `pre-tool-use.sh` blocking `skills/` edits until
   `example-skills:skill-creator` is invoked), the hook
   DELIBERATELY exits `2` to block the tool call — the
   inverse of Invariant 3. Trade-off: allowing the ungated
   action is strictly worse than blocking it (this is the
   doctrine the gate enforces). Such hooks MUST still fail
   OPEN on internal errors (parser failure, missing python3,
   etc.) — Invariant 5 only applies on the gate's positive
   match. Each gate-blocking hook MUST be cited by name in
   the spec section that documents its contract; the only
   gate-blocking hook today is `hooks/pre-tool-use.sh`
   (skills/AGENTS.md Process gate).

## Where the long-form rules live

- CC `${CLAUDE_PLUGIN_ROOT}` env, `hooks.json` schema,
  `hookSpecificOutput.additionalContext` payload shape, Codex
  CLI `~/.codex/hooks.json` format →
  [`../PLUGIN_DEVELOPMENT.md`](../PLUGIN_DEVELOPMENT.md).
- Marker grammar contract, payload examples →
  [`../docs/architecture/0005-contracts/02-hook-contracts.md`](../docs/architecture/0005-contracts/02-hook-contracts.md).
- Hook intent injection pattern rationale →
  [`../docs/architecture/0004-component-architecture.md`](../docs/architecture/0004-component-architecture.md)
  § "Hook intent injection pattern".
