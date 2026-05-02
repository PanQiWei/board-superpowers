# 02 — Hook contracts

> Pin the shape of every Claude Code (and forward-looking Codex CLI)
> hook board-superpowers registers: trigger event, stdin payload,
> stdout / `additionalContext` format, sanitization rules, exit
> codes, timeout. The plugin wires `SessionStart` (advisory) plus
> `PreToolUse` and `PostToolUse` (the skills/AGENTS.md Process gate
> enforcement pair); other events have one place to plug into when
> a future card needs them.

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
| `PreToolUse` (`Edit` / `Write` / `MultiEdit` matchers) | active | `hooks/pre-tool-use.sh` | skills/AGENTS.md Process gate — block file mutations under `skills/**` until `example-skills:skill-creator` is invoked in the session. Companion to `PostToolUse`. |
| `PostToolUse` (`Skill` matcher) | active | `hooks/post-tool-use.sh` | Records `*skill-creator` skill invocations into a per-session flag file consumed by `pre-tool-use.sh`. |
| All others | not registered | — | Reserved for future cards (e.g., a `Stop` hook for end-of-session retro nudge). |

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
description matching. The hook implements the **unified
check-script protocol** (per ADR-0012): it reads the four
partitioned settings files (`~/.board-superpowers/settings.yml`,
`~/.board-superpowers/repos/<repo-identity>/settings.yml`,
`<repo>/.board-superpowers/settings.yml`,
`<repo>/.board-superpowers/settings.local.yml`) and
`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`, computes
the lifecycle diff (per ADR-0013's 6-state model), and emits
a marker if any stage is `pending` or `drifted`.

The hook is **observation-only**: it reads settings files and
emits a marker. It never writes status. It never executes a
stage. The `bootstrapping-repo` SKILL is the single executor
for every stage that needs running — automated and agentic alike
(ADR-0012).

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
| `bootstrapping-repo` | Any stage in the registry (ADR-0014) is `pending` (no entry in `modules.lifecycle.<id>`) or `drifted` (recorded `generation` or `target_state_hash` no longer matches registry); covers both first-time bootstrap AND plugin upgrade drift |

> **Replaces:** the v0.4.0 two-entry table (`bootstrapping-repo`
> for file-absence only + `migrating-repo-version` for version drift).
> The `migrating-repo-version` marker is **removed** — migration is
> "running the stages the lifecycle identifies as `drifted`", handled
> by the same `bootstrapping-repo` SKILL (ADR-0012 absorbed
> `migrating-repo-version` into the unified model).

---

### Unified check-script protocol — setup-stages (ADR-0012)

> **This sub-section documents the hook's behavior under the
> v0.5.0 setup-stages redesign.** It applies to
> `hooks/session-start.sh` v0.5.0+.

#### What the hook reads

On every `SessionStart`, the hook reads:

1. `${CLAUDE_PLUGIN_ROOT}/scripts/stages-registry.yml` — the
   stage registry (ADR-0014); the source of current `generation`
   and `target_state_schema` for each stage.
2. `~/.board-superpowers/settings.yml` — host-shared
   `modules.lifecycle` entries (ADR-0013 lifecycle store).
3. `~/.board-superpowers/repos/<repo-identity>/settings.yml` —
   repo-shared `modules.lifecycle` entries (primary lifecycle
   store for most stages).
4. `<repo>/.board-superpowers/settings.yml` — repo-git locality
   (checked for existence; no lifecycle entries at repo-git in v1).
5. `<repo>/.board-superpowers/settings.local.yml` — repo-clone
   locality (checked for existence; `modules.lifecycle` entries
   present if repo-clone stages have run).
6. `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` — current
   plugin version.

`<repo-identity>` is derived from `git remote get-url origin`
(GitHub-based: `<owner>-<repo>`) per ADR-0017; `_path-<normalized>`
fallback for local-only repos.

#### What the hook computes

For each stage in the registry whose `applicable_when` predicate
(per ADR-0020) evaluates true against current settings:

1. **Layer 1 check (O(1)):** compare `entry.generation` vs
   `registry[stage_id].generation`. If equal: `applied`.
2. **Layer 2 check (hash):** if generations differ OR no entry
   exists: compute `sha256(canonical YAML emit of registry's
   current `compute_target_state()` output)` and compare against
   `entry.target_state_hash`. If no entry: `pending`.
3. **Lifecycle classification:** `pending` | `applied` |
   `drifted` | `deprecated` | `not-applicable` | `failed` |
   `blocked` per ADR-0013.

The hook emits `INVOKE: bootstrapping-repo / REASON: <N> stages
need running (<stage_id1>, <stage_id2>, ...)` when one or more
stages are `pending` or `drifted`. A canonical REASON wording
(from ADR-0012):

```
INVOKE: bootstrapping-repo
REASON: 3 stages need running (m4.repo.acquire-dsn, m7.repo.inject-routing-block, m9.host.register-codex-hooks)
```

#### Invariants that still apply

- **Invariant 1 (Self-contained)** — the hook MUST NOT source
  `scripts/lib/common.sh`. If the registry or any settings file
  is missing or corrupt, the hook silently no-ops (no marker
  emitted). The SKILL itself re-checks state (ADR-0012 marker is
  a fast-path optimization, not a correctness requirement).
- **Invariant 3 (Never block)** — the hook always exits 0,
  even if the registry cannot be loaded or the diff fails. This
  is an advisory hook; blocking session start is worse than
  running unconfigured.
- **Invariant 4 (10s budget)** — the check reads ~4 small YAML
  files + ~20 hash comparisons. Well under the budget. If the
  registry grows large enough to exceed this, the registry
  design (not the timeout) needs rethinking.
- **ADR-0012 observation-only rule** — the hook reads the
  settings files but NEVER writes to them. Stage execution is
  exclusively the SKILL's job.

#### Codex CLI parity

`hooks/session-start.sh` is platform-portable. Both Claude Code
and Codex CLI wire the same script. The registry-diff logic is
pure YAML parsing + integer/string comparison — no CC-specific
APIs. Per `SKILLS.md` "Cross-platform hook delivery".

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

- `hooks/AGENTS.md` — invariants 1–5 (self-contained,
  sanitize, never block on advisory hooks, 10s budget,
  gate-blocking inversion for safety hooks).
- `0002-product-features-and-flows/05-bootstrap-surface.md` §1.5
  three-layer alert strategy — Layer 1 is this hook.
- ADR-0007 C-PLUGIN-2 — hooks are best-effort because there is no
  daemon to make them reliable.
- `PLUGIN_DEVELOPMENT.md` "Hooks (`hooks/hooks.json`)" — the
  upstream `hookSpecificOutput.additionalContext` payload contract.

---

## `PreToolUse` gate hook — skills/AGENTS.md Process gate enforcement

### Why this hook exists

`AGENTS.md` (root) Doctrine #4 mandates that
`example-skills:skill-creator` is invoked before any edit under
`skills/`. Until this hook landed, enforcement was honor-system —
the doctrine surfaced as a system-reminder when `skills/AGENTS.md`
was lazy-loaded but the model could read past it while already in
flow. Architect feedback recorded the same gap firing across at
least three consecutive consumer sessions; the only structural
recourse is a tool-level gate.

### Trigger and matcher set

The hook registers under three `PreToolUse` matchers:

- `Edit` — every file Edit tool call.
- `Write` — every file Write tool call.
- `MultiEdit` — every multi-edit tool call.

Each matcher invokes the same `hooks/pre-tool-use.sh` script, which
filters internally on `tool_input.file_path`. Only paths matching
`*/skills/*` or `skills/*` are gated; everything else exits 0
immediately.

### Companion `PostToolUse` hook

`hooks/post-tool-use.sh` listens for `Skill` tool invocations. When
`tool_input.skill` (or `skill_name`) ends with `skill-creator`
(matching `example-skills:skill-creator` and any future
namespace variants), the script writes a flag file at
`${TMPDIR:-/tmp}/board-superpowers-sessions/<session_id>/skill-creator-invoked.flag`.
The flag is per-session — restarted sessions re-fire the gate, which
is correct (Doctrine #4 says the entry skill MUST be invoked
**in this session**, not "ever").

### Failure-mode trade-off (Invariant 5)

Per `hooks/AGENTS.md` Invariant 3, advisory hooks (`SessionStart`)
MUST exit 0 — blocking session start is worse than running
unconfigured. The gate hook inverts this trade-off (per Invariant 5):
**allowing ungated edits to skills/ is worse than blocking the
edit**, because Doctrine #4 names that exact failure mode as
non-recoverable in-session. The hook therefore exits 2 with a
reason on stderr when the gate fires.

The hook fails OPEN on its own internal errors — missing python3,
malformed JSON payload, parse exceptions, write errors on the flag
directory — because hook-internal failure should not punish the
architect for a bug in the hook implementation. Only the gate's
positive match (skill-creator confirmed not invoked) triggers
exit 2.

### Stdin payload

```json
{
  "session_id": "<UUID-like string>",
  "tool_name": "Edit | Write | MultiEdit | Skill | ...",
  "tool_input": {
    "file_path": "/path/to/file",      // for Edit/Write/MultiEdit
    "skill": "<plugin>:<skill-name>"   // for Skill (PostToolUse)
  }
}
```

The hook sanitizes `session_id` defensively (rejects any character
outside `[a-zA-Z0-9_-]`) before interpolating into the flag-file
path; sanitization fails open (exit 0).

### Stdout / stderr / exit codes

| Path | Outcome | Exit code | stdout | stderr |
|------|---------|-----------|--------|--------|
| Edit/Write/MultiEdit on `skills/**`, flag absent | gate fires | 2 | (empty) | gate-explanation block |
| Edit/Write/MultiEdit on `skills/**`, flag present | allowed | 0 | (empty) | (empty) |
| Edit/Write/MultiEdit outside `skills/` | not gated | 0 | (empty) | (empty) |
| Other tool name (e.g., `Read`, `Bash`) | not gated | 0 | (empty) | (empty) |
| Malformed JSON / missing python3 / extraction error | fail-open | 0 | (empty) | (empty) |

### Known gap — Bash escape hatch

The hook gates `Edit / Write / MultiEdit` only. A motivated bypass
via `Bash` (e.g., `bash -c 'cat > skills/foo.md'` or `sed -i`) is
not blocked. Rationale for accepting the gap:

- The system prompt already prefers Edit/Write over Bash mutations
  ("Avoid using this tool to run `sed`, `awk`...; use Edit/Write
  instead"). Bypass requires deliberate choice, not accident.
- Gating Bash by command-string grep is brittle — a
  command like `cd somewhere/skills/foo && touch bar.md` triggers
  false positives.
- Audit-log inspection (per `auditing-actions`) provides a
  detection path for deliberate bypass.

If the gap becomes load-bearing, a follow-up card adds a Bash
matcher with a tighter heuristic (e.g., grep for `>\s*\S*skills/`
or `--include skills/`).

### State directory

`${TMPDIR:-/tmp}/board-superpowers-sessions/<session_id>/`

The directory is per-session and created on demand by
`post-tool-use.sh`. It is NOT persistent — `/tmp` is wiped on host
reboot. Persistence is intentionally absent: Doctrine #4's
"in this session" requirement implies session-scoped state.

### Cited rationale

- `AGENTS.md` (root) Doctrine #4 — mandates the entry skill before
  any edit under `skills/`.
- `skills/AGENTS.md` "Process gate" — the implementation /
  review-phase contract this hook enforces.
- Memory `feedback_v1_release_gate_no_workarounds` — workarounds
  must close before release; honor-system enforcement counts as
  a workaround the gate hook removes.
- Canonical CC PreToolUse output schema —
  <https://code.claude.com/docs/en/hooks.md> § "PreToolUse"
  documents `hookSpecificOutput.permissionDecision: "deny"` as
  the modern block mechanism; exit 2 + stderr is the legacy path
  ("older pattern, still works"). The hook emits both for
  belt-and-suspenders compatibility across CC versions.

### Codex parity gap — gate enforcement

The gate hook pair (`pre-tool-use.sh` + `post-tool-use.sh`)
is **Claude Code only**. Codex CLI does not get tool-level
enforcement; the gate degrades to doctrinal text in
`skills/AGENTS.md` "⛔ STOP" block. Three reasons:

1. **No `Skill` tool in Codex.** Codex skills are loaded by the
   runtime, not invoked as a model-facing tool. There is no
   `Skill` tool call to PostToolUse-hook into, so the flag-file
   lifecycle (the `Skill` invocation writes the flag, the Edit
   reads it) cannot complete on Codex.
2. **Deadlock risk.** If `pre-tool-use.sh` were registered on
   Codex without a working `post-tool-use.sh` companion, every
   Edit / Write into `skills/` would block forever — there is
   no path to clear the flag.
3. **`tool_input` schema divergence.** Codex's `apply_patch` tool
   does not expose `file_path` the way CC's `Edit` does. Even if
   the matcher fired (via Codex's `apply_patch | Edit | Write`
   normalization), the path-extraction would silently fail and
   the gate would fail-open — no enforcement in practice.

`scripts/register-codex-hooks.sh` therefore registers
`SessionStart` only on Codex. Earlier rollouts that briefly
included PreToolUse / PostToolUse entries are auto-cleaned on
the next install (the merge logic drops any existing
board-superpowers entries from those events).

If Codex eventually exposes a Skill-equivalent tool that fires
PostToolUse, this gap closes; until then, doctrinal text + the
`example-skills:skill-creator` skill body itself (which can
include its own opt-in self-reporting) are the enforcement on
Codex.

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

- [`00-kanban-protocol.md`](./00-kanban-protocol.md) — top-level
  Kanban Protocol; hooks here are protocol-agnostic (they fire
  before any backend dispatch happens).
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
