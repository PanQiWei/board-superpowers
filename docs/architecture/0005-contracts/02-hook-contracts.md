# 02 — Hook contracts

> Pin the shape of every Claude Code (and forward-looking Codex CLI)
> hook board-superpowers registers: trigger event, stdin payload,
> stdout / `additionalContext` format, sanitization rules, exit
> codes, timeout. v1 wires `SessionStart` only; the format below is
> forward-looking so future hook entry points have one place to
> plug into.

---

## Where hooks register

| Platform | File | Schema |
|----------|------|--------|
| Claude Code | `${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json` | Per `PLUGIN_DEVELOPMENT.md` "Hooks (`hooks/hooks.json`)" |
| Codex CLI | `~/.codex/hooks.json` or `[hooks]` in `~/.codex/config.toml` | Per `PLUGIN_DEVELOPMENT.md` "Hooks" / Codex section |

board-superpowers ships the Claude Code registration only at v1.
The same `hooks/session-start.sh` script is platform-portable and
can be wired into Codex CLI by an architect-side
`~/.codex/hooks.json` entry; a first-class Codex registration is a
future card.

---

## Hook events board-superpowers uses

| Event | Status | Script | Purpose |
|-------|--------|--------|---------|
| `SessionStart` (`startup` matcher implicit) | active | `hooks/session-start.sh` | Layer 1 dep alert + first-time setup nudge |
| All others | not registered at v1 | — | Reserved for future cards (e.g., a `Stop` hook for end-of-session retro nudge) |

The 28+ Claude Code hook events available are enumerated in
`PLUGIN_DEVELOPMENT.md` ("Hooks (`hooks/hooks.json`)" → "Available
events"). board-superpowers deliberately uses the smallest
practical surface (per ADR-0007 C-PLUGIN-2 — no daemon; the SKILL
preflight is the reliable gate, hooks are advisory).

---

## `hooks/hooks.json` registration shape

```json
{
  "hooks": {
    "<EventName>": [
      {
        "matcher": "<optional matcher>",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh\"",
            "timeout": <seconds>
          }
        ]
      }
    ]
  }
}
```

Pinned conventions for board-superpowers hooks:

- **Path interpolation.** Every hook command references the script
  via `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh`. Never hard-code
  `~/.claude/plugins/...`.
- **Timeout cap.** Default Claude Code timeout is 600s; board-
  superpowers caps each hook at **10s**. Hook work that exceeds 10s
  belongs in a SKILL preflight, not a hook.
- **Type.** All hooks are `type: command` (bash). HTTP / MCP / agent
  hook types are not used at v1.

---

## `SessionStart` hook — the active wiring

### Registration

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

No `matcher` string at v1 — the hook fires on every session start.

### Trigger

Claude Code session start. Per `PLUGIN_DEVELOPMENT.md` "Hooks", the
event also includes a `matcher: "startup"` discriminator the plugin
does not currently constrain.

### Stdin payload (from Claude Code)

JSON object on stdin with at minimum:

| Field | Type | Purpose |
|-------|------|---------|
| `session_id` | string (UUID-shaped) | Identifies the originating session |
| `cwd` | string (absolute path) | Working directory at session start |
| `hook_event_name` | string | `"SessionStart"` for this hook |

board-superpowers' v1 implementation does NOT read stdin —
`session-start.sh` ignores it. The contract for future hook scripts
that DO read stdin: parse JSON, never trust user-controlled fields
without sanitization.

### Stdout payload (from board-superpowers)

When something requires the model's attention, **exactly one
JSON object** on stdout, RFC-8259-compliant:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<escaped string>"
  }
}
```

When everything is fine and there is nothing to inject, the script
emits nothing on stdout (silent no-op exit `0`).

### `additionalContext` body — the conspicuous-banner pattern

The injected string carries one or more of these tagged blocks
verbatim. Order, when multiple are emitted in one firing:

1. Dep alert (when present) — most urgent; missing deps block
   everything downstream.
2. Intent-injection marker (when present and no dep alert
   pre-empts it) — see § "Intent-injection markers" below.
3. Setup nudge (when present and no other block fires) —
   informational, never blocking.

#### `<board-superpowers-dep-alert priority="CRITICAL">` block

Emitted when at least one dep (`superpowers`, `gstack`) is missing.
Body composition:

- One-line summary: `⚠️ board-superpowers DEPENDENCY MISSING: <csv>`
- Imperative: "Your VERY FIRST response to the user in this session
  MUST begin with the banner below, reproduced VERBATIM inside a
  fenced code block …"
- A fenced code block (` ``` `) containing:
  - Box-drawing-char header
  - One bullet per missing dep (sanitized name)
  - One install instruction per known dep (`superpowers` →
    `/plugin install superpowers@claude-plugins-official`;
    `gstack` → the clone+setup line)
  - A reason line ("Without them, board-superpowers workflows will
    break mid-flow…")
- Imperative footer: "Do not silently skip the banner. Do not
  paraphrase it. Do not explain your way out of displaying it."

#### `<board-superpowers-intent-injection>` block

Emitted when on-disk state implies a specific skill should be
invoked **before** the model would normally route via
description matching. The hook reads
`~/.board-superpowers/manifest.yml`,
`~/.board-superpowers/repos/<normalized>/state.yml`, and
`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` to compute
the condition.

Body composition (verbatim payload — no Markdown, no
prose-shaped wrapping):

```
INVOKE: <skill-name>
REASON: <one-line explanation, ≤120 chars>
```

`<skill-name>` MUST be a board-superpowers skill name from the
v1 catalog (per
[`04-skill-contracts.md`](./04-skill-contracts.md) and
[`../0004-component-architecture.md`](../0004-component-architecture.md)
Decision 2). At v1 the only `<skill-name>` values the hook
emits are:

| Marker value | Trigger condition |
|--------------|-------------------|
| `bootstrapping-repo` | `~/.board-superpowers/manifest.yml` absent (first-time host) OR `~/.board-superpowers/repos/<normalized>/state.yml` absent (per-`(host, repo)` first-time) |
| `migrating-repo-version` | `state.yml:last_seen_version_in_repo` ≠ `plugin.json:version` (per-repo upgrade pending) OR `manifest.yml:last_seen_version` ≠ `plugin.json:version` AND `state.yml` absent (host upgrade with no per-repo state yet) |

Future hook events (`PreToolUse`, `PostToolUse`, `Stop` — none
wired at v1) MAY emit `INVOKE:` for any v1 skill name; the
marker grammar is the same. Adding a new `<skill-name>` value
the hook can emit is a contract change — update the table above
in the same PR.

**Grammar rules:**

- Exactly two lines: `INVOKE:` then `REASON:`. No leading or
  trailing whitespace inside the block.
- `<skill-name>` matches `[a-z][a-z0-9-]*` (kebab-case, the
  agentskills.io spec subset). Anything else is a malformed
  payload — the receiving entry skill MUST log + ignore.
- `<one-line explanation>` is plain ASCII, ≤120 chars,
  punctuation only `. , ; : - ( )`. No newlines, no JSON, no
  markup. The string lands inside the model's context — keep it
  un-parseable as instructions.
- **At most one `INVOKE:` marker per `additionalContext`
  payload.** If two conditions could fire simultaneously
  (e.g., bootstrap AND migrate would never co-occur, but
  hypothetical future markers might collide), pick the
  highest-priority one and drop the others. Priority order is
  documented in the table above by row order.

**Receiving-side contract.** Per
[`../0004-component-architecture.md`](../0004-component-architecture.md)
§ "Hook intent injection pattern":

- The `using-board-superpowers` entry skill consumes the marker
  and routes to the named skill.
- The receiving skill MUST be able to do the same work even if
  the marker never arrived — the marker is a fast-path
  optimization, never a correctness requirement.
- If the marker names a skill not in the v1 catalog, the entry
  skill stops and surfaces "unrecognized hook intent
  marker — please file a bug" rather than guessing.

#### `<board-superpowers-setup-nudge>` block

Emitted when `CLAUDE.md` exists in the project but lacks the
routing-marker pair. Body asks the model to surface a one-line
question to the user offering to inject the routing block, and
gates auto-injection on explicit consent.

### Sanitization expectation

Every value derived from `check-deps.sh --machine` output that
ends up in the `additionalContext` payload MUST go through
`sanitize_dep_name` (defined in `session-start.sh`):

```bash
sanitize_dep_name() {
  # 1. Replace any char outside [a-zA-Z0-9_-] with `-`
  # 2. Truncate to 32 chars
  # 3. Drop the value entirely if it has no alphanumeric content
  ...
}
```

Rationale: `additionalContext` is untrusted model input and may end
up in a system prompt slot. A rogue `check-deps.sh` output (or a
hostile filesystem layout matching one of the dep glob patterns)
must NOT be able to inject markup, prompt content, or control
characters into the model's context.

After sanitization, every interpolated piece passes through
`json_escape_string` (also in `session-start.sh`), which is a
pure-bash RFC 8259 §7 string escaper:

- Backslashes substituted **first** (otherwise subsequent escapes
  get double-escaped).
- Quotes, then `\n`, `\r`, `\t`, `\b`, `\f`.
- Remaining ASCII control chars (U+0000–U+001F, except HT/LF/CR
  which are already replaced) stripped via `LC_ALL=C tr -d`.

### Exit codes

| Code | Meaning | Claude Code behavior |
|------|---------|----------------------|
| `0`  | Success (banner emitted OR silent no-op) | Hook output read; session continues |
| `2`  | Blocking error (NOT used by board-superpowers) | Session blocked. Reserved for future hooks where blocking is the right semantics. |
| Any other non-zero | Non-blocking error | Hook output ignored; session continues |

**board-superpowers' invariant: hook failures MUST NEVER block
session start.** Per `hooks/AGENTS.md` Invariant 3 ("Never
block"): silent no-op on error is the correct failure mode at
this layer; the SKILL preflight (Layer 2) is the real safety
net.

### Timeout

Declared `10` seconds in `hooks.json`. Per `hooks/AGENTS.md`
Invariant 4 ("10-second budget"): "Keep new work well under
it." If `check-deps.sh --machine` ever exceeds 10s in practice,
the dep-detection algorithm (not the timeout) is the thing to
fix.

### Self-containment

`hooks/session-start.sh` MUST NOT source `scripts/lib/common.sh`.
A broken or missing lib must never prevent Claude Code startup.
Per `hooks/AGENTS.md` Invariant 1 ("Self-contained").

The script's only dependency-resolution step at v1 is locating
`${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh` and exec-ing it via
`bash`. If the path doesn't resolve, the hook silently no-ops.

### Cited rationale

- `hooks/AGENTS.md` — invariants 1–4 (self-contained,
  sanitize, never block, 10s budget).
- `0002-product-features-and-flows/05-bootstrap-surface.md` §1.5
  three-layer alert strategy — Layer 1 is this hook.
- ADR-0007 C-PLUGIN-2 — hooks are best-effort because there is no
  daemon to make them reliable.
- `PLUGIN_DEVELOPMENT.md` "Hooks (`hooks/hooks.json`)" — the
  upstream `hookSpecificOutput.additionalContext` payload contract.

---

## Forward-looking conventions for future hooks

When a future card adds a second hook entry, it MUST honor the same
conventions:

- **Self-containment** — a broken lib does not break the hook.
- **Sanitization** — every model-bound string passes through a
  domain-appropriate sanitizer + the JSON escaper.
- **Non-blocking failure** — exit non-zero only when blocking
  semantics are actually wanted; silent no-op otherwise.
- **Timeout < 10s** — work that needs longer belongs in a SKILL.
- **Test coverage** — a hermetic test under `tests/` exercising
  both the success and failure paths (per
  [`0008-test-architecture.md`](../0008-test-architecture.md)).

The `hooks.json` schema accepts multiple events and matchers; future
additions should reuse the existing top-level structure rather than
shipping a sibling JSON file.

---

## Codex CLI parity

Per `PLUGIN_DEVELOPMENT.md` "Codex CLI" → "Hooks", Codex supports a
6-event subset: `SessionStart`, `PreToolUse`, `PermissionRequest`,
`PostToolUse`, `UserPromptSubmit`, `Stop`. `SessionStart` exists on
both platforms, so `hooks/session-start.sh` is wire-compatible.

To enable on Codex side, an architect adds (or
board-superpowers ships in a future card) an entry like:

```toml
# ~/.codex/hooks.json (or [hooks] in ~/.codex/config.toml)
[[hooks.SessionStart]]
type = "command"
command = "bash ${BOARD_SP_PLUGIN_ROOT}/hooks/session-start.sh"
```

Note: Codex has no `${CLAUDE_PLUGIN_ROOT}` equivalent; the
hook-side script must derive its own plugin root via `BASH_SOURCE`
or an architect-set env var (`BOARD_SP_PLUGIN_ROOT` is the
recommended convention; see [`08-environment-variables.md`](./08-environment-variables.md)).

---

## Cross-references

- [`01-script-contracts.md`](./01-script-contracts.md) —
  `check-deps.sh` `--machine` mode keys (`MISSING`,
  `ROUTING_INJECTED`, `PROJECT`) — the parser side of this hook.
- [`07-path-conventions.md`](./07-path-conventions.md) — session-log
  paths (CC `~/.claude/projects/...`, Codex
  `~/.codex/sessions/...`) that future hooks may stat for
  preflight piggyback.
- [`08-environment-variables.md`](./08-environment-variables.md) —
  `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PROJECT_DIR`, `BOARD_SP_DEBUG`.
- ADR-0007 — derivation of why hooks must be best-effort.
- `PLUGIN_DEVELOPMENT.md` — upstream hook contracts (CC + Codex).
- `hooks/AGENTS.md` — operational checklist for
  changes to this surface.
