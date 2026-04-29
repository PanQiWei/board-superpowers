# ADR 0027: Cron as a trigger carrier — external schedulers as a first-class plugin entry mechanism

**Status:** accepted
**Date:** 2026-04-29
**Deciders:** PanQiWei (maintainer)

## Context

The Producer / Consumer surface redesign work in PR #69
introduced a new requirement-layer dimension axis **J2 —
trigger carrier** (per
[`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md))
with four enum values: `session-hook`, `cron-job`,
`in-process-reflex`, `explicit-prompt`. Three of these are
unambiguously covered by existing rules — `session-hook` by
the plugin runtime hook contracts
([`../0005-contracts/02-hook-contracts.md`](../0005-contracts/02-hook-contracts.md)),
`in-process-reflex` by ADR-0008 plugin-to-plugin SKILL
invocation, and `explicit-prompt` by the architect-driven
prompt model. The fourth — `cron-job` — has no prior ADR
governance.

The naming raises a governance question against ADR-0007's
plugin-runtime constraints (C-PLUGIN-1 / -2 / -3):

- C-PLUGIN-1 prohibits in-memory cross-session IPC.
- C-PLUGIN-2 prohibits daemon threads inside plugin sessions.
- C-PLUGIN-3 mandates controlled Consumer-dispatch concurrency.

ADR-0007 introduced the **preflight piggyback idiom** as the
recognized resolution for "automatic / monitor / detect"
features under those constraints — every check piggybacks on
the architect's next prompt.

The PR #69 surface-redesign analysis revealed three failure
modes when piggyback is the **only** allowed automation path:

1. **K-budget exhaustion.** The session-hook carrier has a
   per-SessionStart injection capacity K (empirically `K ≈ 4`
   per `09-session-agent-protocol.md` § "K-budget rule").
   When more than K nodes need session-entry visibility,
   piling them all onto session-hook compresses each item's
   salience to noise — silently violating P1 ("architect
   attention is the bottleneck") instead of protecting it.

2. **Cadence-vs-session-frequency mismatch.** Several
   workflows are calendar-driven: weekly aggregated report,
   retro on Milestone close, kanban-hygiene drift detection.
   Their semantics demand "every 7 days" / "when Milestone
   closes" / "every 30 cards completed" — not "next time the
   architect prompts." Piggyback ties cadence to session
   frequency and therefore cannot express true cadence.

3. **Long-running agent-self-surface latency.** Long-stuck
   Consumer sessions, overnight batch dispatch result
   aggregation, and stale-claim sweep all need to **act
   between architect sessions**, not at session entry.
   Piggyback delays these to "next architect prompt," which
   may be hours or days away.

These are not edge cases — they are routine v1-complete
workflows. The empirical conclusion: piggyback is necessary
but not sufficient. The plugin needs a second carrier for
work that runs on its own clock and persists output for
later session pickup.

The mechanism candidates considered:

- **(a) In-process scheduler thread.** Rejected by
  C-PLUGIN-2 (no daemon).
- **(b) External scheduler invoking the plugin entry.**
  System cron / GitHub Actions cron / CC scheduled jobs
  invoke `claude --no-interactive --skill <name>` (or the
  equivalent Codex CLI command) on a fixed cadence.
- **(c) Sibling-plugin invocation as an indirect schedule.**
  Asks another plugin to play scheduler — multiplies
  governance complexity without solving the underlying
  carrier question.

Mechanism (b) is the only one that:

- Stays within ADR-0007's spirit — each invocation is a
  **standalone session lifecycle** (start, run, terminate);
  no daemon thread persists in memory.
- Aligns with existing plugin physics — the plugin already
  runs as a CLI on every architect-driven session; cron
  invocations are the same CLI with a different trigger
  source.
- Has cross-platform viability — system cron is universal;
  GitHub Actions cron is widely available; CC scheduled
  jobs and equivalents are emerging.

But mechanism (b) is currently **not declared** as a
supported carrier anywhere in the spec. ADR-0007 spoke only
to in-process behavior; it neither permitted nor prohibited
external invocation. The unstated default left
`cron-job` ambiguous as a J2 value — which is why
[`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md)
§ "Open / TBD" item 1 was opened.

## Decision

External orchestrators (system cron, CC scheduled jobs,
GitHub Actions cron, equivalent platform schedulers) are an
**explicit, supported trigger carrier** for plugin entry
points. They constitute J2 = `cron-job` per the Session
Agent Protocol.

This decision **complements** ADR-0007 — it does not
supersede:

- ADR-0007 (C-PLUGIN-2) prohibits **daemon threads inside
  plugin sessions** — still binding.
- ADR-0027 permits **discrete external invocations of
  plugin entry points by an external scheduler** — a
  separate concern.

The two are different scopes. C-PLUGIN-2 is about
long-running in-process state; cron is about stateless
scheduled invocation that **starts** a plugin session (or
its CLI equivalent), runs, and **terminates** when the
invocation completes. No daemon thread persists.

### What "cron-job carrier" means concretely

- **Entry shape.** The cron entry calls
  `claude --no-interactive --skill <name>` (CC) or the
  equivalent Codex CLI command (Codex; pending platform
  support — see Consequences below). Each invocation is a
  full session lifecycle: starts, runs the named skill,
  terminates.
- **No architect presence.** Cron-fired invocations execute
  without any architect being present. J5 = `inject-session`
  is therefore **illegal** for cron-J2 nodes per the
  Session Agent Protocol cross-axis matrix — there is no
  session prompt context to inject into.
- **Output via durable state only.** Cron output goes to:
  - `state.yml` (host-local per-(host, repo) state file).
  - Audit DB (BYO RDBMS per ADR-0006 §5).
  - GitHub artifacts (PR comments, commits, issues).
  - Files under `.board-superpowers/` (per-repo state).

  The next architect-driven session reads from these
  surfaces.
- **Safe re-entry.** Cron may run while an architect-driven
  session is also running. State writes use file locks
  (`flock` precedent from `audit-log-write.sh`) or
  sequenced DB writes. The two sessions never share
  in-memory state — they coordinate **only** through
  durable state, satisfying C-PLUGIN-1.

### The compute / present split idiom

When a node needs to be **visible at session entry** but its
compute is too heavy for hook injection or its trigger is
cadence-driven, use a two-phase split:

1. **Compute phase (`cron-job` carrier).** Runs on cadence,
   produces output to `state.yml` or audit DB. No session
   user-facing output.
2. **Present phase (`session-hook` carrier).** On the next
   SessionStart, reads the latest computed state and
   injects a brief summary into the architect's session.
   Reading-from-state is fast; injection stays within
   K-budget.

This idiom is the recommended way to surface cron-computed
results without bloating SessionStart hook execution.
Several v1-complete Producer nodes use it (board overview
A1, PR queue A2, "cards on me" A3 — all split into
cron-side compute + hook-side present).

### What is still prohibited

- **In-process daemon threads** — still forbidden per
  ADR-0007 (C-PLUGIN-2). Cron is *external* scheduling; an
  in-process scheduler thread is daemon-shaped and remains
  prohibited.
- **In-memory cross-session IPC** — still forbidden per
  ADR-0007 (C-PLUGIN-1). Cron-launched sessions
  communicate with subsequent sessions only through
  durable state (file / DB), never shared memory.
- **Cron writing directly to architect-facing channels
  without persistence** — cron may not directly post a
  Slack message / send an email that bypasses state. All
  external emissions are observable in audit DB or
  `state.yml`, so a subsequent session can reconstruct
  what cron did.

## Consequences

### Positive

1. **K-budget protection.** Cadence-driven workflows (retro
   / weekly / hygiene) move off SessionStart hook to cron.
   K-budget ≈ 4 stays available for genuinely
   architect-facing items at session entry.
2. **Cadence semantics correct.** Weekly report runs every
   7 days regardless of architect's session frequency.
   Retro fires on Milestone close (cron polls a closure
   condition) rather than on architect's next prompt.
3. **Compute / present split unlocked.** Heavy compute
   (board state aggregation, PR queue ordering, audit DB
   summarization) runs cron-side; SessionStart only reads
   pre-computed state. Hook execution stays sub-second.
4. **Long-running self-surface unlocked.** Long-stuck
   Consumer can be detected by cron sweeping for stale
   claims; cron emits a PR comment / GitHub issue without
   waiting for architect to enter session. The architect
   sees the surface on next session entry via state read.

### Negative / cost

1. **Setup complexity.** Cron requires `crontab -e` (system
   cron) or a `.github/workflows/<name>.yml` (GitHub Actions
   cron) or platform-specific scheduled job UI. Bootstrap
   surface (05) gains a stage for "set up cron schedule"
   when cron-J2 nodes ship in v1-complete.
2. **Cross-platform asymmetry.** CC has scheduled jobs on
   roadmap but availability is platform-specific.
   Codex CLI cron support is currently TBD pending platform
   evolution. Surface specs cite this gap; some cron-J2
   nodes may have to fall back to session-hook +
   state-cache (degraded experience: cadence not honored
   precisely; fires on next architect session instead) on
   Codex until platform support arrives.
3. **State coordination cost.** Cron-launched sessions and
   architect-driven sessions write to the same `state.yml`
   / audit DB concurrently. Concurrent writes need
   `flock` discipline or sequenced DB transactions.
   `audit-log-write.sh` already handles audit DB; `state.yml`
   writes need similar discipline added.
4. **Debuggability cost.** Cron-side failures are silent by
   default — no architect is present to see them. Failure
   surfacing must go through audit log + a present-phase
   summary; otherwise cron-failed nodes silently disappear
   from architect's view.

### Mitigations

- **Bootstrap-stage support.** A future Setup-Stages module
  (M11 or equivalent — exact module number to be allocated
  when v1-complete cron-J2 nodes ship) registers a "cron
  schedule" config-item stage. The architect declares
  cadence preferences during bootstrap; the stage emits
  the appropriate `crontab` or `.github/workflows/*.yml`.
- **Codex fallback documented.** Surface specs mark cron-J2
  nodes that lack Codex parity with a "Codex fallback:
  hook + state-cache" footnote. The fallback's degraded
  cadence semantics are explicit so architect understands
  the asymmetry.
- **Concurrency safety inherited from precedent.**
  `state.yml` writes use file locking (`flock` on Linux /
  macOS) following the `audit-log-write.sh` precedent. The
  inheritance is explicit; new state-writing scripts must
  cite this pattern.
- **Cron failure surfacing.** Every cron entry writes an
  audit row on completion (success / failure / partial).
  The compute / present split's present-phase summary
  reads recent audit rows and surfaces failures to the
  architect on next SessionStart. Silent cron failures are
  thereby converted to next-session visible failures.

### Implementation impact

- `09-session-agent-protocol.md` § "Open / TBD" item 1 is
  closed by this ADR; the J2 carrier ladder cites this
  ADR for cron-J2 selections.
- Surface specs (03 / 04 / 05) can use `J2 = cron-job` as a
  fully-supported value in their catalog tables.
- Bootstrap surface (05) expands to include a
  cron-schedule config-item stage in v1-complete (or v1.x,
  depending on which cron-J2 nodes ship in v1-complete).
- ADR-0007 body unchanged. ADR-0027 lives alongside as a
  complementary rule. Both are accepted-status, neither
  supersedes the other.
- `docs/architecture/AGENTS.md` spec change-impact matrix
  gains a row for cron-as-trigger-carrier (the row where
  it sits is determined by where the cron mechanism's
  primary spec home lives — currently the Session Agent
  Protocol's J2 axis).

## Alternatives considered

**(a) In-process scheduler thread.** A daemon thread inside
the plugin session that polls cadence triggers and fires
work. **Rejected** by ADR-0007 C-PLUGIN-2 — daemon threads
inside plugin sessions are prohibited regardless of
function. Revisiting ADR-0007's constraint set to unlock
cadence semantics has disproportionate cost when external
scheduling solves the same problem without disturbing the
constraint set.

**(c) Sibling-plugin invocation as indirect schedule.**
Asks a sibling plugin (e.g., `superpowers` or `gstack`) to
play scheduler — the sibling exposes a "fire X on cadence"
SKILL that board-superpowers invokes once at SessionStart.
**Rejected** on three grounds: (i) multiplies governance
complexity without solving the underlying carrier question
— the sibling plugin would need the same cron mechanism
internally (passing the buck); (ii) creates hidden
cross-plugin scheduling dependencies that ADR-0008
explicitly avoids; (iii) does not fix SessionStart
coupling — sibling-side schedule still fires on
board-superpowers' SessionStart cadence, not true calendar
cadence.

**(d) Webhook-based external trigger.** A web service
listens for GitHub webhook events (PR merged, issue
opened) and invokes the plugin entry. **Considered, set
aside** (not rejected). Webhooks address *event-driven*
triggers; cron addresses *cadence-driven* triggers (every
7 days, every Milestone close). They are complementary
carriers, not substitutes. Webhook-as-carrier may warrant
its own future ADR; it does not subsume cron, and cron
does not subsume it.

The chosen mechanism is **(b) external scheduler invoking
plugin entry** — see Decision section for the concrete
shape (cron entry calling `claude --no-interactive`, output
via durable state, compute / present split idiom).

## Related

- ADR-0007 — plugin-runtime-derived constraints (parent
  context; complementary, not superseded).
- ADR-0008 — plugin-to-plugin SKILL invocation (in-process
  composition; cron sessions invoke SKILLs in-process per
  ADR-0008 once they start).
- ADR-0006 — producer-autonomy-boundary (cron-fired
  mutating actions still classify A / R / N per the
  D-AUTONOMY-1 matrix — autonomy class is independent of
  trigger carrier).
- [`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md)
  § J2 + § "Cross-axis legal-combination matrix" — the
  protocol definition that names cron-job and bounds its
  cross-axis combinations.
- [`../../FEATURE_DESIGN_METHODOLOGY.md`](../../FEATURE_DESIGN_METHODOLOGY.md)
  § "Stage 2 — Locating each node" → § "J2 — Trigger
  carrier" → "Carrier ladder" — the selection algorithm
  that picks cron-job over session-hook for cadence-driven
  nodes.
- [`../0001-positioning.md`](../0001-positioning.md) P1 —
  "architect attention is the bottleneck"; cron's K-budget
  protection role serves P1 directly.
