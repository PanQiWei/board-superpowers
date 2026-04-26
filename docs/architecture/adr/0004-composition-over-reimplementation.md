# ADR 0004: Composition over reimplementation of TDD / QA / review

**Status:** accepted
**Date:** 2026-04-25
**Deciders:** PanQiWei (maintainer)

## Context

board-superpowers operates one layer above implementation: it
schedules and routes work. The implementation discipline (TDD,
debugging, QA, code review, security audit, brainstorming) already
exists in two mature plugins:

- **`superpowers`** — coding-discipline loop: brainstorming →
  writing-plans → test-driven-development → systematic-debugging →
  verification-before-completion → requesting-code-review.
- **`gstack`** — bookend disciplines: office-hours,
  plan-ceo-review, plan-eng-review, /review, /qa, /cso,
  /investigate, /design-consultation, /design-review, /retro.

We could reimplement subsets inside board-superpowers to avoid the
runtime dependency. We deliberately do not.

The forces that pushed this decision:

1. **Quality compounds upstream.** Every release of `superpowers`
   sharpens TDD discipline, every release of `gstack` sharpens
   review/QA. If we re-implement, every upstream improvement
   becomes a port; if we compose, we adopt by reference.
2. **Scope discipline.** Plugin maintainers (board-superpowers
   contributors) should be writing scheduling-layer code, not
   re-validating "is this TDD assertion correct." Composition
   keeps our scope tight enough that one maintainer can hold the
   whole plugin in their head.
3. **Self-hosting consistency.** The plugin's own development
   already uses superpowers (TDD on scripts) and gstack (/codex
   for shell second opinions, /cso for pre-release security
   audit). A user of board-superpowers gets exactly what we use
   ourselves.

## Decision

board-superpowers **composes** `superpowers` and `gstack`. Any
discipline already provided by either is **routed to**, never
reimplemented.

- The `using-board-superpowers` SKILL preflight requires both
  plugins to be installed.
- The `consuming-card` SKILL routes execution to
  `superpowers:subagent-driven-development` (which itself routes
  to test-driven-development, systematic-debugging, etc.) and
  optionally to `gstack:/qa` for UI-touching cards.
- The `managing-board` SKILL's Intake routine routes design work
  to `superpowers:brainstorming` or `gstack:/office-hours`.
- The `decomposing-into-milestones` SKILL routes architectural
  pressure-testing to `gstack:/plan-eng-review` for non-trivial
  decompositions.
- Conflict arbitration follows `superpowers:using-superpowers`:
  **user instructions > skill > default behavior**. A gstack
  skill's "plan is ready, start coding" advice does not override
  superpowers' TDD discipline unless the user explicitly says so.

## Consequences

**What this enables:**

- The plugin's scope stays narrow. The whole codebase fits in
  one architect's head. Maintenance is single-person-tractable
  even as a side project.
- Upstream evolution flows in for free. New superpowers / gstack
  releases sharpen the experience without us doing porting work.
- Users get a coherent stack rather than a competing one. The
  three plugins compose; they don't fight.

**What this constrains:**

- Hard runtime dependency on both plugins. The plugin literally
  refuses to run without them — preflight is loud and reliable
  (three-layer alert strategy: SessionStart hook +
  using-board-superpowers SKILL Step 1 + just-in-time re-checks).
- Routing decisions become first-class architecture. The
  CLAUDE.md routing block injected during bootstrap (see
  `skills/using-board-superpowers/references/claudemd-routing.md`)
  has to encode phase-by-phase composition (gstack bookends +
  superpowers middle).
- We are exposed to upstream breakage. If `superpowers` ships a
  breaking change to the brainstorming skill's frontmatter,
  Manager Intake breaks until we update routing. Mitigation:
  just-in-time re-checks + version-pin discipline in CLAUDE.md.

**What this rules out:**

- Forking TDD / QA / review / brainstorming into board-superpowers.
  Permanently.
- "Reimplementing for performance" or "reimplementing because
  upstream is slow to merge our PR." If upstream isn't responsive,
  the answer is a contributor PR upstream, not a fork downstream.
- Wrapping upstream skills in our own thin wrapper just to add a
  custom prompt — we use the upstream skill as-is or we route
  somewhere else.

## Alternatives considered

**Hard fork TDD into board-superpowers.** Would have removed the
runtime dependency on `superpowers`. Rejected because the ongoing
cost of TDD-quality maintenance is real (TDD discipline is non-
trivial; superpowers' authors keep refining it) and we gain
nothing functional from owning the fork.

**Soft hint at superpowers/gstack but don't require.** Plugin
silently degrades when a dep is missing. Rejected because silent
degradation produces phantom successes — the architect's session
runs but skips TDD, which is exactly the failure mode we set up
the plugin to prevent. Loud preflight is the better failure
shape.

**Vendor specific commands as scripts.** E.g., write a
`bsp-tdd.sh` that invokes Claude Code with a hard-coded TDD
prompt. Rejected because it loses the model-routing benefit
(skill descriptions match against user phrasing; hard-coded
prompts don't), and locks us to today's API surface of upstream
plugins (any frontmatter change breaks us silently).

**Build our own discipline plugins.** "Why not write
`bsp-tdd`, `bsp-review`, etc., owned by us?" Rejected on the
same grounds as the marketplace non-goal in 0001-positioning.md:
versioning debt + chicken-and-egg + scope explosion. The
maintainer has neither the bandwidth nor the desire to maintain
a discipline-plugin ecosystem.

## Related

- ADR-0001 — Pluggable board backend (sibling architectural
  commitment; both define what board-superpowers refuses to own)
- `0001-positioning.md` P4b — composition is permanent (premise this
  ADR anchors)
- `skills/using-board-superpowers/references/claudemd-routing.md`
  — the runtime encoding of this composition (gets injected into
  every downstream CLAUDE.md at bootstrap)
- `0006-failure-modes.md` (stub) — F-06 mid-session dep removal is the
  failure mode this composition exposes us to; mitigation is
  just-in-time re-checks
