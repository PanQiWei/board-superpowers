# skills/ — skill-authoring contract

> **Before any work in this directory** (writing, editing,
> renaming, re-layering, or even *designing / discussing /
> reviewing* a skill — not just running an editor):
>
> 1. Invoke `example-skills:skill-creator` — the canonical entry
>    skill for create / modify / improve skill work. It carries
>    the cross-platform skill-authoring discipline.
> 2. Read [`../SKILL_DEVELOPMENT.md`](../SKILL_DEVELOPMENT.md) if
>    its content is not already in context. ~1290 lines, but
>    you only need the section your work touches (skill graph
>    framing, three-tier frontmatter, body skeletons,
>    anti-patterns, testing regimes).
> 3. **If your change adds / removes / renames / re-layers a
>    skill, edit [`../SKILLS.md`](../SKILLS.md) FIRST** —
>    per its Source-of-truth contract a `skills/` change without
>    a paired `SKILLS.md` change is unmergeable.

This contract is the per-directory operational checklist for
the skill-authoring discipline. The full guide lives in
`SKILL_DEVELOPMENT.md`; this file is the thin "what every PR
under `skills/` must satisfy" view.

## Frontmatter discipline (Tier 1 / 2 / 3)

- **Tier 1 (mandatory)**: `name` + `description`. The
  `description` field is **WHEN, not WHAT** — triggering
  conditions in third person, prefer "Use when …". Never
  summarize the procedure here.
- **Tier 2 (CC-spec optional fields, additive UX only)**:
  `when_to_use`, `argument-hint`, `arguments`, `user-invocable`
  — among others. The full 11-field CC-spec list (also
  including `disable-model-invocation`, `allowed-tools`,
  `model`, `effort`, `context: fork`, `agent`, `hooks`,
  `paths`, `shell`) lives in
  [`../PLUGIN_DEVELOPMENT.md`](../PLUGIN_DEVELOPMENT.md)
  § "Skills (`SKILL.md`)" and § "Skill frontmatter / metadata"
  (Codex parser silently ignores them; behavior must not depend
  on Tier 2 fields). Per-skill recommendations on which Tier 2
  fields to set live in [`../SKILLS.md`](../SKILLS.md)
  catalog.
- **Tier 3 (forbidden)**: custom non-spec fields like
  `version: …`. Those go in `.skill-meta.yaml` (see below).
  CI gate `scripts/verify-skill-frontmatter.sh` enforces.

## Required dual-file: `SKILL.md` + `.skill-meta.yaml`

Every skill directory must contain BOTH files. The yaml schema
is documented in `SKILL_DEVELOPMENT.md` § "board-superpowers
metadata convention" and consists of:

- `version` (semver, per-skill independent of plugin version)
- `layer` — entry / molecular / atomic
- `type` — technique / pattern / reference / discipline
- `mode` — claude-code-only / codex-only / both
- `bounded-context` — board / session / bootstrap / audit / spec

CI gate `scripts/verify-skill-metadata.sh` enforces consistency
between the yaml and the [`../SKILLS.md`](../SKILLS.md) catalog.
Drift here causes silent topology rot.

## Body length budgets

Per layer, hard ceilings:

- **Entry** ≤ 200 lines (loaded every session — every line
  counts against shared context budget).
- **Molecular** 250–450 lines (loaded when triggered by
  workflow scenarios).
- **Atomic** 200–300 lines (loaded on demand from molecular
  bodies).

Past 100 lines for a single topic, move it to
`references/<topic>.md` and link from the body explicitly.
Never use `@`-auto-load for references; never chain references
more than one level deep.

## Cross-skill references

Always carry the `<plugin>:<skill>` namespace prefix. Examples:

- `superpowers:test-driven-development` ✓
- `gstack:/qa` ✓
- `test-driven-development` ✗ (bare reference — fails to
  resolve unambiguously across plugins)

Internal same-plugin references inside this repo also use the
prefix `board-superpowers:<skill>` for consistency.

## Atomic-layer reflexive constraint

Atomic skills MUST NOT call same-plugin skills. They are
reflexes consumed by molecular skills, not orchestrators. If a
change appears to require an atomic calling another atomic, the
design has gone wrong — split / merge the atomics instead of
introducing the upward call.

## SKILLS.md edit-first contract

When adding / removing / renaming / re-layering any skill:

1. Edit [`../SKILLS.md`](../SKILLS.md) catalog FIRST (catalog
   row, call graph, bounded-context map, cross-plugin edges as
   applicable).
2. THEN create / move / delete the `skills/<name>/` directory.
3. Both halves land in the same PR. PRs that touch `skills/`
   without a paired `SKILLS.md` change are incomplete.

## CI gates (must pass before PR lands)

- `scripts/verify-skill-frontmatter.sh` — Tier 1 + Tier 2
  presence, no Tier 3.
- `scripts/verify-skill-metadata.sh` — yaml ↔ SKILLS.md
  catalog consistency.
- `shellcheck -x` over any new / changed scripts in the skill
  directory (e.g., skill-bundled scripts under
  `<skill>/scripts/`).

## Where the long-form rules live

This file is intentionally the per-directory checklist, not
the manual. For:

- Skill graph framing (entry / molecular / atomic), three-tier
  frontmatter rationale, body skeletons, anti-patterns, testing
  regimes → [`../SKILL_DEVELOPMENT.md`](../SKILL_DEVELOPMENT.md).
- Catalog of the 10 v1 skills + call graph + SPOT derivation +
  cross-plugin edges + maintenance contract →
  [`../SKILLS.md`](../SKILLS.md).
- Subagent / Mode-2 orchestration constraints (`max_depth=1`,
  procedural fallback patterns, `Agent` tool use) →
  [`../MULTI_AGENT_DEVELOPMENT.md`](../MULTI_AGENT_DEVELOPMENT.md).
