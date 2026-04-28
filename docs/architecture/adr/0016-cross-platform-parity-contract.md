# ADR 0016: Cross-platform parity contract via the platforms field on every stage

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

board-superpowers is a dual-platform plugin — every shipped
capability must run on both Claude Code and OpenAI Codex CLI.
The runtimes converge on most contracts (`SessionStart`,
`SKILL.md` body, project-instructions auto-load) but diverge
in load-bearing places. Two divergences the bootstrap
mechanism trips over today:

- **Hook registration is asymmetric.** CC auto-discovers
  `<plugin-root>/hooks/hooks.json` when the plugin loads —
  no architect action. Codex has no plugin-level
  auto-discovery; the architect must run
  `scripts/register-codex-hooks.sh --install-user`
  out-of-band per the README, which writes
  `~/.codex/config.toml`'s `[hooks]` table.
- **`${CLAUDE_PLUGIN_ROOT}` is CC-only.** Codex has no
  equivalent env var; scripts derive their own paths via
  `BASH_SOURCE` (abstracted in
  `scripts/lib/common.sh:bsp_plugin_root()`). Logic
  reaching for `${CLAUDE_PLUGIN_ROOT}` directly is
  implicitly CC-only.

The status quo documents the asymmetry in prose only
(README, `PLUGIN_DEVELOPMENT.md`); neither divergence is
modeled in any machine-readable artifact. This is the
failure mode flagged by
[`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
§ "Why a redesign" item 4 — *cross-platform parity is
ad-hoc*. G4 of the redesign promotes parity to a
first-class design constraint and demands it be modeled.
Closely related:
[ADR-0007](./0007-plugin-runtime-derived-constraints.md)
already names this asymmetry as a C-PLUGIN constraint in
prose; this ADR is the data-shape encoding.

## Decision

Every stage in the bootstrap stage registry MUST declare a
`platforms` field. Legal values:

- **`both`** — identical behavior on CC and Codex. Default
  for platform-agnostic primitives (file writes, GitHub API
  calls, DDL applies). Most v0.4.0-baseline stages.
- **`cc-only`** — intentionally CC-only (primitive depends
  on a CC-specific affordance, e.g., `${CLAUDE_PLUGIN_ROOT}`
  reachable directly). Silently skipped on Codex.
- **`codex-only`** — intentionally Codex-only (configures
  something CC handles automatically, e.g., hook
  registration). Silently skipped on CC.
- **`cc`** / **`codex`** — variant spellings, functionally
  identical to `cc-only` / `codex-only`. The schema accepts
  both so authors pick what reads naturally.

The unified check script (per
[ADR-0012](./0012-unified-check-script-trigger-model.md))
detects the running platform at startup and ignores stages
whose `platforms` does not match. A `codex-only` stage is
invisible to a CC session's lifecycle diff; `never-run` /
`stale` / `deprecated` never apply on the wrong platform.

**Composition with `applicable_when`** (per ADR-0020):
`platforms` is the **coarse special-case predicate** — a
fixed enum of platform identities that the hook resolves
purely from runtime context (no settings lookup). The
generic `applicable_when` predicate (declarative
setting-path / board-capability / Python escape hatch)
runs *after* `platforms` filtering. Both must evaluate true
for a stage to participate in the lifecycle. Concretely:

1. Hook detects platform (`cc` vs `codex`).
2. Hook drops stages whose `platforms` does not match
   (these never appear in any lifecycle state on this
   platform — not even `not-applicable`).
3. For surviving stages, hook evaluates `applicable_when`
   (if present). False → stage enters `not-applicable`
   state per ADR-0020. True / absent → stage participates
   normally (`never-run` / `completed` / `stale` /
   `deprecated`).

This split keeps `platforms` cheap and registry-static
(no settings dependency for the platform decision) while
letting `applicable_when` handle the data-driven
conditionals (kanban backend, capability presence, etc.).
Conflating the two would force the hook to load settings
just to compute platform applicability, breaking the
hook-cheap invariant.

Concrete v0.4.0-redesign consequences:

- **`m9.host.register-codex-hooks` is `platforms:
  codex-only`.** Runs `register-codex-hooks.sh
  --install-user` semantics from inside the bootstrap flow;
  what was a README-instructed manual step becomes an
  automated stage on Codex. The README instruction deletes.
- **Stages requiring `${CLAUDE_PLUGIN_ROOT}` directly
  declare `cc-only`.** The Codex equivalent uses
  `bsp_plugin_root()` self-derivation; v0.4.0-redesign
  avoids introducing such stages but `cc-only` is reserved
  for genuine future asymmetries.
- **Validation is load-time.** The registry's JSON Schema
  (per [ADR-0014](./0014-stage-registry-contract.md)) marks
  `platforms` required and enumerates the five legal
  values; missing or misspelled declarations fail CI before
  any hook reads the registry.

## Consequences

**Positive.** Platform asymmetry is first-class — every
reader of the registry sees the constraint alongside
`module` / `character` / `locality`; PR review has a
closed-form question for any new stage. README ceases to
be a load-bearing instruction surface — the m9 stage
automates what was prose. CI catches divergence at the
schema gate; no silent-CC-only regressions. The trigger
model is dead-simple — filter by running platform at
startup, no conditional branches inside executors.

**Negative.** One more required field on every stage —
most repeat `platforms: both`, which feels like ceremony.
Justified because no stage is added without the author
considering the platform question, even for "obviously
both" stages whose primitive may rely on a CC-only
affordance. The trigger model needs a reliable
platform-detection primitive at startup —
`${CLAUDE_PLUGIN_ROOT}` presence is the signal,
`bsp_plugin_root()` abstracts it; a future CC env-var
contract change is patched in the same PR.

## Alternatives considered

**α — Explicit `platforms` field on every stage (chosen).**
Every stage declares; load-time schema validates; trigger
model filters.

**β — Implicit "all stages run on both unless special",
flag platform-specific via the `flags` list.** Rejected.
`flags` is free-form binary tags — easy to forget to set,
easy to typo; the absence of a flag means "behaves on
both" silently rather than "the author considered the
question and concluded both." Silent platform divergence
is the failure mode this ADR exists to eliminate; an
opt-in flag scheme reproduces it.

**γ — Two parallel stage registries (one per platform).**
Rejected. Most stages run identically on both; duplicating
forces two sources of truth in sync for every common stage
with no benefit the α schema gate does not provide, and
complicates the lifecycle model — a stage `completed` in
one but absent from the other has no clear meaning.

**δ — Document platform asymmetry only in README (status
quo).** Rejected. README docs decay — the existing "run
register-codex-hooks.sh" line was already drifting; the
gap surfaced only when an architect noticed the missing
hook. G4 promotes parity to first-class; relegating to
README prose contradicts the goal. Load-time schema
validation catches violations at PR time.

## Notes

The five legal values include intentional redundancy (`cc`
≡ `cc-only`, `codex` ≡ `codex-only`) so authors pick the
naturally-reading spelling; matching is set-membership.
`m9.host.register-codex-hooks`'s `flags:
[platform-specific]` is informational; the authoritative
declaration is `platforms: codex-only`. A future third
platform adds an enum value additively — the ADR-0013
fingerprint flips affected stages to `stale`, no separate
migration logic.

## Related

- [ADR-0007](./0007-plugin-runtime-derived-constraints.md)
  — Plugin-runtime-derived constraints; the CC ↔ Codex
  asymmetry this ADR formalizes is a direct consequence of
  the C-PLUGIN constraints there. ADR-0007 is the prose
  statement; ADR-0016 is the data-shape encoding.
- ADR-0012 — Unified check-script trigger model; consumer
  of the `platforms` filter.
- ADR-0013 — Declarative state schema + 5-state lifecycle.
- ADR-0014 — Stage registry contract; the JSON Schema
  that enforces `platforms`-required at load time.
- ADR-0015, ADR-0017, ADR-0018, ADR-0019 — sibling
  redesign ADRs.
- [`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
  — Living design doc; § "Why a redesign" item 4, § "Goals"
  G4, the Stages table's `platforms` column, and § "Stage
  registry contract" `platforms` row are authoritative.
- `PLUGIN_DEVELOPMENT.md` (root) — canonical reference for
  the CC and Codex plugin contracts this ADR encodes.
