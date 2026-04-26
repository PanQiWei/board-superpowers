# ADR 0007: Plugin-runtime-derived constraints — three constraints arising from CC / Codex plugin physics

**Status:** proposed
**Date:** 2026-04-26
**Deciders:** PanQiWei (maintainer)

## Context

board-superpowers is a Claude Code + OpenAI Codex CLI plugin
(see `PLUGIN_DEVELOPMENT.md` for the plugin-form contract). Plugin form
imposes physical constraints on what the runtime can and cannot
do. These are **not design choices**; they are runtime physics
that every feature, flow, and surface design has to close under.

Three constraints recur often enough to deserve names. Naming
them once here lets every downstream spec cite them by ID instead
of re-deriving the same arguments from scratch, and lets PR
review check feature designs against a fixed list rather than
re-discovering the same problem ad-hoc.

The same forces also produce a derived implementation idiom —
the **preflight piggyback** — that resolves the apparent tension
between "no daemon allowed" and "Producer must monitor things
automatically." That idiom is named here too because every
"automatic" Producer feature implements it.

## Decision

Three constraints are formally registered and named below.
Every feature spec, every routine, every script that touches
session lifecycle MUST close under all three. The preflight
piggyback idiom is registered as the canonical resolution
pattern.

### C-PLUGIN-1 — No in-memory cross-session IPC

CC and Codex sessions do not share in-memory state. There is no
direct IPC channel between sessions. Producer cannot directly
hold any Consumer session's runtime state — there is no in-memory
handle, no shared object graph, no cross-session subscription.

**Workarounds.** Every cross-session signal MUST explicitly choose
one of:

- **(a) GitHub artifacts** — Project field, PR, issue comments,
  claim-branch markers, repository files. The board *is* the
  shared state.
- **(b) Session-id reachback** — Consumer writes its session-id
  to the kanban card; Producer reads persisted session data via
  CC's `~/.claude/projects/<dir>/<session-id>.jsonl` or Codex's
  `codex exec resume [SESSION_ID]`.

**Implication.** Every cross-session information flow MUST
explicitly choose a workaround in its spec. There is no realtime
in-memory path; specs that assume one are incomplete and do not
ship.

### C-PLUGIN-2 — No daemon thread

board-superpowers does not run a long-lived background process
on the user's machine. No polling daemon, no push-notification
listener, no scheduled task we own.

**Implication.** All Producer "active monitoring" behavior —
stale-session detection, health degradation, blocked-too-long
alert, cadence-driven retro / report trigger — MUST be
**lazy-evaluated**: piggyback on the architect's next prompt.
This is what the preflight-piggyback idiom (below) exists to
implement.

### C-PLUGIN-3 — Controlled Consumer-dispatch concurrency

Producer dispatching Consumer sessions (especially in F-5
overnight batch) MUST support controlled concurrency: a serial
queue, or rate-limited parallelism with a maximum of N
concurrent sessions. The default is conservative (recommended
default = 1, serial); the architect configures it explicitly.

**Why concurrency must be bounded:**

- **Token cost.** Unconstrained parallel dispatch burns budget
  fast. A 5-card overnight batch at full parallelism with no cap
  is a budget event the architect must opt into, not a default.
- **Local machine resource pressure.** Each Consumer session is
  a real CC / Codex process plus its tools, MCP servers, and
  worktree. Memory / CPU / IO contention on commodity hardware
  is real.
- **GitHub API rate limits.** N parallel Consumers all hitting
  `gh` simultaneously can trip secondary rate limits and cascade
  into a global slow-down for that architect's account.

**Implication.** F-5 design MUST expose a concurrency parameter.
F-3 (dispatch recommendation) MUST respect both the current
in-flight Consumer count and the WIP limit before recommending a
new dispatch.

### Derived idiom — Preflight piggyback

Producer, on every received architect prompt, runs a lightweight
situation-awareness check **before** processing the prompt's
actual content. The check covers:

- Stale session detection (F-s)
- Cadence check (is retro / weekly report due?)
- Health degradation (did board health drop below threshold?)
- Has any dispatched Consumer completed since last prompt?

Check results are inserted at the top of Producer's response
(e.g. `Preflight: 2 PRs ready for verification, retro is due
(last ran 8 days ago).`) and only then does Producer process the
prompt's actual request.

This is board-superpowers' **core technical idiom under plugin
form.** All "automatic" features are implemented through it.
Every Producer feature whose spec uses verbs like *monitor*,
*detect*, *trigger automatically* MUST cite this idiom and
describe what it piggybacks on the preflight.

## Consequences

**What this enables:**

- A single fixed list of constraints to check feature designs
  against. PR review for any feature touching Producer behavior
  has a closed-form question: "does this close under C-PLUGIN-1,
  -2, -3?"
- A canonical implementation pattern (preflight piggyback) for
  every feature that wants "automatic" behavior, so the plugin
  doesn't accumulate N different ad-hoc workarounds for the same
  no-daemon problem.

**What this constrains:**

- **Every claim of "automation" in board-superpowers MUST verify
  it can close under all three constraints, otherwise reformulate
  as "lazy", "preflight", or "queued."** "Continuous monitoring"
  and "real-time alert" do not exist in plugin form and must not
  appear in feature specs.
- **The preflight piggyback idiom needs a dedicated section in
  `0004-component-architecture.md`** so every Producer feature
  has one place to point to.
- **C-PLUGIN-2 means Producer cannot push realtime
  notifications.** The architect must initiate a prompt to
  receive any awareness from Producer. This is compatible with
  P1 (architect attention is scarce, and unsolicited
  notifications would compete for it), but it MUST be made
  explicit in any spec where the architect might reasonably
  expect push semantics. Wording like "Producer notifies you
  when X" is forbidden in specs without a `via preflight on next
  prompt` qualifier.
- **C-PLUGIN-1 + C-PLUGIN-2 jointly imply that "stale" detection
  cannot be realtime.** It must be derived from observable
  GitHub timestamps (last commit, last comment, last status
  update), NOT from "I haven't heard a heartbeat from
  Consumer." Heartbeat-style protocols (Consumer pings Producer
  every N seconds) are off the table at the plugin layer; even
  if implementable they violate C-PLUGIN-2.

**What this rules out:**

- An external daemon shipped with the plugin (systemd unit,
  launchd plist, background script). Violates the plugin-form
  promise (`0001-positioning.md` P5: distribution stays minimal)
  and increases install complexity.
- GitHub-Actions cron triggers as a default mechanism. Feasible
  in principle but requires every architect's repo to enable
  Actions, violates P7 (we provide mechanism, not bound to a
  specific tech), and shifts state out of the architect's
  observable session loop into a system the architect doesn't
  inhabit during normal use.
- Trusting the architect to manually ask "is anything stale?"
  on every prompt. Violates the "automation" promise; the
  preflight piggyback exists precisely to remove that ceremony
  while staying within C-PLUGIN-2.

## Alternatives considered

**Ship an external daemon (systemd / launchd background script).**
Rejected: violates the plugin-form promise. Install ceases to be
"clone + register"; uninstall ceases to be "remove the plugin
directory." Cross-platform parity (macOS launchd vs Linux
systemd vs Windows) becomes a maintenance burden out of
proportion to side-project framing.

**Use GitHub Actions for cron-driven triggers.** Feasible — a
scheduled workflow could post a comment that Producer reads on
next prompt. Rejected as default: every architect's repo must
enable Actions and accept the minutes / billing exposure;
violates P7 by binding the cadence mechanism to a specific tech;
and the trigger result still has to wait for the architect's
next prompt to surface, so the gain over preflight piggyback is
small.

**Trust the architect to manually refresh awareness ("ask me
what's stale").** Rejected: violates the "automation" promise
the plugin makes about Producer routines. Preflight piggyback
is a strict improvement — the architect's normal prompts already
land, so situation-awareness output costs nothing extra at the
prompt boundary.

**Build a heartbeat protocol (Consumer pings Producer every N
seconds via repo file or comment).** Rejected: violates
C-PLUGIN-1 (there's still no in-memory channel; the heartbeat
is a poll over GitHub) and produces no information that
observable GitHub timestamps don't already provide. Adds
complexity, GitHub-API load, and a new source of false alarms
(Consumer crashed vs Consumer still running but quiet) without
adding signal.

**Allow unbounded Consumer parallelism (skip C-PLUGIN-3).**
Rejected on three independent grounds (token cost, machine
resource pressure, GitHub rate-limit cascade) — any one would
be sufficient. The architect can tune the cap upward; the
default must be conservative.

## Notes

- These three constraints derive from CC and Codex contracts
  documented in `PLUGIN_DEVELOPMENT.md`. If either platform
  changes its contract — e.g., Anthropic ships a daemon-style
  plugin surface, or Codex adds in-memory cross-session IPC —
  this ADR gets revisited and possibly superseded. Cite
  `PLUGIN_DEVELOPMENT.md` as the source of truth for the
  contracts themselves.
- The preflight piggyback idiom name should propagate into every
  Producer routine doc (`managing-board/references/*.md`) so the
  routines can cite it by name without re-explaining it.
- C-PLUGIN-3's "recommended default = 1, serial" is a starting
  point, not a research-backed number. Once F-5 ships and there
  is real data on overnight-batch behavior, the default should
  be re-examined and either confirmed or moved with evidence.

## Related

- ADR-0006 — Producer autonomy boundary (matrix row 14 —
  cadence-driven auto-trigger — is implemented via the
  preflight piggyback idiom defined here)
- `0001-positioning.md` P5 (distribution stays minimal), P7
  (meta-methodology, not opinionated configuration) — the
  premises these constraints derive from. The plugin-form
  contract itself is documented in `PLUGIN_DEVELOPMENT.md`,
  not in `0001-positioning.md`.
- `0002-product-features-and-flows/` (especially
  `03-producer-surface.md` and `04-consumer-surface.md`) — every
  feature spec with verbs like *monitor*, *detect*, *trigger
  automatically* MUST cite this ADR
- `0004-component-architecture.md` (stub) — the preflight
  piggyback idiom needs a dedicated section here
- `PLUGIN_DEVELOPMENT.md` — canonical reference for the CC and
  Codex plugin contracts these constraints derive from
- `MULTI_AGENT_DEVELOPMENT.md` — operationalizes C-PLUGIN-1
  (no in-memory IPC) and C-PLUGIN-2 (no daemon) for the multi-agent
  surface specifically; documents subagent lifecycle hooks,
  session-id reachback file paths, and which mid-flight IPC primitives
  exist on each platform (most are absent or experimental)
