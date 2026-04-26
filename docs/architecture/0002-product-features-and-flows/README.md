# Product features and flows

> Spec-level inventory of **what board-superpowers offers** (features)
> and **how a user actually walks through it** (flows). Lives between
> `0001-positioning.md` (vision / premises) and the entity-level
> `0003-domain-model/` (what each feature operates on) plus the
> to-be-filled `0004-component-architecture.md` (implementation
> shape). This is the architectural spec for the product surface —
> not a duplicate of `README.md` (which is adoption material).
>
> **Audience**: future maintainers asking "which feature must I not
> break" and "which flow must I not redesign". Completeness > brevity.

---

## Status

**Everything in this doc is spec.** Even where code exists today
that *looks like* it implements an entry below, no such entry is
load-bearing as "this is what the codebase does right now" — when
the actual implementation phase begins, the spec is the source of
truth and any existing code may be re-examined, refactored, or
torn down to match.

In other words: the spec leads, the code follows. Don't read this
doc as a tour of current code.

---

## How this directory is organized

This document was originally a single file. As it grew past ~4000
lines, it was split into the per-section files below. Heading
levels and `§X.Y` cross-references inside each file are preserved
verbatim — splitting was mechanical, not a rewrite. Internal
references like "see §1.4 F-C8" still work as textual pointers
across files.

### Part 1 — Features

The capability catalog. Each surface (Producer / Consumer /
Bootstrap / Decomposition / PR contract) lists the time-independent
"what can this role do" — flows in Part 2 compose these in time.

| File | Section | Coverage |
|------|---------|----------|
| [`01-work-hierarchy.md`](./01-work-hierarchy.md) | §1.1 Work hierarchy | Milestone × Thread (no Sprint), 2-axis orthogonal model |
| [`02-roles.md`](./02-roles.md) | §1.2 Roles | Producer / Consumer / Architect — purpose-based, not station-based |
| [`03-producer-surface.md`](./03-producer-surface.md) | §1.3 Producer surface | Manager specific role, 15 features F-01..F-15 in 5 groups |
| [`04-consumer-surface.md`](./04-consumer-surface.md) | §1.4 Consumer surface | Implementer specific role, 15 features F-C0..F-C14 in 5 groups; Mode-1 vs Mode-2 |
| [`05-bootstrap-surface.md`](./05-bootstrap-surface.md) | §1.5 Bootstrap surface | (layer × event) matrix; F-B1..F-B4 + shared dep-check primitive |
| [`06-decomposition-surface.md`](./06-decomposition-surface.md) | §1.6 Decomposition surface | INVEST + vertical slicing + card schema + size labels (XS/S/M/L) |
| [`07-cross-cutting-invariants.md`](./07-cross-cutting-invariants.md) | §1.7 Cross-cutting invariants | I-1..I-13 — project-wide contracts spanning multiple surfaces |
| [`08-pr-contract.md`](./08-pr-contract.md) | §1.8 PR contract | `## Automated Verification` (required) / `## Human Verification TODO` (OPTIONAL) / `## Retro Notes` |

### Part 2 — User flows

Time-ordered narratives that compose Part 1 features into actual
walked paths. Each flow names the features it activates and the
ADRs that constrain it.

| File | Sections | Coverage |
|------|----------|----------|
| [`20-user-flows.md`](./20-user-flows.md) | §2.1–§2.10 | First-time install / per-project bootstrap / plugin upgrade / daily Manager / intake / card consumption (Manager-dispatched + manual pull) / weekly retro / triage / mid-session dependency loss |

### Part 3 — Cross-references

The lookup tables: which feature lives in which skill, which ADR
constrains which feature, what's actually implemented today vs
spec-only.

| File | Sections | Coverage |
|------|----------|----------|
| [`30-cross-references.md`](./30-cross-references.md) | §3.1–§3.3 | Features → Skills mapping / Features → ADRs mapping / Implementation status summary |

---

## Related

- `0001-positioning.md` — premises, non-goals, audience (this doc lives
  inside the boundaries set there)
- `PLUGIN_DEVELOPMENT.md` (repo root) — plugin contracts both
  platforms expose; relevant when a feature touches a platform
  surface
- `MULTI_AGENT_DEVELOPMENT.md` (repo root) — multi-agent /
  subagent / orchestration contracts; constrains §1.4 F-C8 +
  F-C14 Mode-2 paths
- `adr/` — architectural decisions that constrain the features here
- `0004-component-architecture.md` (stub; not yet filled) — runtime
  topology that realizes these features
- [`0003-domain-model/`](../0003-domain-model/README.md) — entities,
  bounded contexts, aggregates, and domain events the flows
  manipulate
