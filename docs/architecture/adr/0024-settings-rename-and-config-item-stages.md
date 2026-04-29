# ADR 0024: settings.yml rename + new config-item stages (`m5.repo.set-wip-limit`, `m10.repo.choose-kanban-backend`)

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

Two related decisions emerge from the v0.5.0 bootstrap redesign
(per
[`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md))
sharing the "redesign the architect-facing settings surface"
context. Bundling keeps review pair-programmed — the rename
rationale alongside the first two stages that consume it.

**Part A — settings file naming.** v0.4.0 ships **four
plumbing files with four different names**: host-shared
`manifest.yml`, repo-shared `state.yml`, repo-git `config.yml`,
repo-clone `config.local.yml`, plus `~/.board-superpowers/overrides.yml`
holding host-shared autonomy presets per ADR-0006. The
disparate naming reflects implementation history (each file
landed in a different release window with whichever name fit
at the time), not architectural meaning.

**Part B — two new config-item stages.** Today's WIP limit
lives only as a hard-coded default inside the consuming-card
SKILL — no per-repo elicitation surface exists. ADR-0005's
BoardAdapter contract describes a backend selection seam but
v0.4.0 hard-codes GitHub-Project-v2 throughout M3 with no
first-class "this repo uses backend X" declaration. Both gaps
are blocked on the same prerequisite: a uniform place to put
architect-facing config items, governed by a uniform
elicitation protocol. ADR-0023 ships the protocol; this ADR
ships the file-naming unification (Part A) and the two
exemplar stages (Part B) that consume it.

## Decision

### Part A — rename to the `settings.yml` family

Rename the four v0.4.0 plumbing files to a unified
`settings.yml` family per locality, and fold `overrides.yml`
content into the host-shared `settings.yml` under
`modules.m8_autonomy`:

| v0.4.0 path | v0.5.0 path | Locality |
|-------------|-------------|----------|
| `~/.board-superpowers/manifest.yml` | `~/.board-superpowers/settings.yml` | host-shared |
| `~/.board-superpowers/overrides.yml` | folded into `~/.board-superpowers/settings.yml` `modules.m8_autonomy` | host-shared |
| `~/.board-superpowers/repos/<repo-identity>/state.yml` | `~/.board-superpowers/repos/<repo-identity>/settings.yml` | repo-shared |
| `<repo>/.board-superpowers/config.yml` | `<repo>/.board-superpowers/settings.yml` | repo-git |
| `<repo>/.board-superpowers/config.local.yml` | `<repo>/.board-superpowers/settings.local.yml` | repo-clone |

`~/.board-superpowers/repos/<repo-identity>/credentials.yml`
**remains a separate file** (mode 0600) for secret isolation —
the `settings.yml` family is mode 0644, so DSNs / tokens /
passwords MUST NOT live in it.

This is a **pre-v1 breaking rename** (mirroring ADR-0012). No
in-place migration logic ships; architects upgrading from
v0.4.0 delete legacy host-local state and re-bootstrap on
first v0.5.0 session.

**Boundary with ADR-0021**: ADR-0021 defines the **internal
structure** of each `settings.yml` (two-section split + module
namespacing + per-module `schema_version`). This ADR scopes
only the **file naming** — what the four files are called and
where they live.

### Part B — two new agentic stages

Both stages exemplify the ADR-0023 5-element config item
protocol; both persist via Axis B locality into the
appropriate `settings.yml` from Part A; both re-prompt via the
ADR-0013 lifecycle.

**`m5.repo.set-wip-limit`** — module M5, agentic
(`confirm-only`), locality `repo-clone`. Schema
`{wip_limit: int}`, default `5`, validation kind
`numeric-range` (1..20); architect may accept the default to
advance. Persists into
`<repo>/.board-superpowers/settings.local.yml:modules.m5_repo_configuration.wip_limit`.

**`m10.repo.choose-kanban-backend`** — module M10, agentic
(`confirm-only`, `single-choice-currently`), locality
`repo-git` (committed into git so every clone agrees on which
backend M3 talks to). Schema
`{kanban_backend: enum [github-project-v2]}`, validation kind
`single-choice`. v0.5.0 enum has exactly one option; future
Linear / Jira options land via registry-only enum extension
(each option carries `introduced_in_version` per ADR-0023 so
additive enum bumps don't gratuitously re-prompt repos that
already picked an extant option). Persists into
`<repo>/.board-superpowers/settings.yml:modules.m10_kanban.backend`.

**Boundary with ADR-0022**: ADR-0022 governs the **capability
dispatch behavior** of the chosen backend (M3 stages reading
`BoardAdapter.<capability>()`, `applicable_when:
board_capability=...` predicates). This ADR scopes only the
**stage's existence** + its **persistence target** — where the
choice is recorded so ADR-0022's dispatch logic has a
deterministic input to read.

## Consequences

### Positive

- **One filename family, one suffix variant.** `settings.yml`
  + `.local.yml` replace five history-named files; cognitive
  load drops from "five names" to "one name + locality
  routing".
- **Settings discovery is uniform** — "Where is X configured?"
  is answered by Axis B locality alone, pairing cleanly with
  ADR-0023 element 4 ("Persistence by locality").
- **WIP limit becomes a real config item** — today's
  hard-coded default disappears; per-repo customization works
  through the same elicitation surface as every other knob.
- **BoardAdapter selection has a home** — ADR-0005's contract
  finally has a deterministic place to read its input from;
  ADR-0022's dispatch logic does not have to invent one.

### Negative

- **Pre-v1 breaking rename** — every architect upgrading from
  v0.4.0 deletes legacy state + re-bootstraps; no transitional
  dual-name window. Mitigated by v0.4.0 being pre-v1 and the
  breaking-change posture already accepted in the design doc.
- **`overrides.yml` re-elicitation** — the fold to
  `settings.yml:modules.m8_autonomy` causes M8 to re-prompt
  on first v0.5.0 session. Mitigated by M8's "no presets,
  skip" default (one-keystroke re-confirm).
- **Two more stages in the registry** — both declarative-only
  (registry entry + `stages_lib/<stage_id>.py` helpers per
  ADR-0014), no per-stage SKILL code.

## Alternatives considered

### α — Rename + new stages bundled in one ADR (chosen)

Both halves share the "v0.5.0 redesign the settings surface"
motivation; reviewers benefit from seeing the rename rationale
alongside the two stages that consume it.

### β — Keep v0.4.0 plumbing names

Rejected. Four different filenames for four locality variants
is unhelpful disparate-naming-by-history. Architects already
remember Axis B locality to know **which** file holds their
setting; making them also remember **which name** at that
locality doubles cognitive cost without adding signal.

### γ — Add the new stages to v0.4.0 names without renaming

Rejected. Writing `m5.repo.set-wip-limit` into
`config.local.yml` while ADR-0023 calls it "settings
persistence by locality" produces immediate documentation
drift. Pre-v1 is the right window to rename — small user
population, no semver compatibility contract exists, and every
other v0.5.0 redesign decision already requires re-bootstrap.

### δ — Bundle Part A and Part B into separate ADRs

Rejected. Part A's rename motivates Part B's persistence target;
Part B's stages exemplify why the rename matters. Splitting
forces the reader to hold one decision in their head while
reviewing the other.

## Notes

Two-name boundaries within the v0.5.0 ADR series:

- **ADR-0021** = internal structure of each `settings.yml`;
  this ADR = file naming.
- **ADR-0022** = capability dispatch behavior of the chosen
  backend; this ADR = selection stage existence + persistence
  target.
- **ADR-0023** = 5-element config item protocol; this ADR's
  two new stages are exemplar consumers (they fill in the
  protocol's five elements but do not modify the protocol).

Future extensions to either new stage (e.g., `wip_limit_per_user`,
a Linear backend) are **registry edit + helpers update** per
ADR-0014 and ADR-0023's future-feature procedure — no new ADR
unless the change introduces architectural-grade decisions.

## Related

- ADR-0005 — BoardAdapter contract; v0.5.0 enum
  `[github-project-v2]` is its v1 reference adapter.
- ADR-0006 — Autonomy boundary; `overrides.yml` folds into
  host-shared `settings.yml:modules.m8_autonomy`.
- ADR-0012 — Unified check-script trigger model; the pre-v1
  delete-and-re-bootstrap posture is shared.
- ADR-0013 — Declarative state schema + 5-state lifecycle;
  `target_state` / `generation` / `target_state_hash` recorded
  inside each `settings.yml` follow this contract.
- ADR-0014 — Stage registry contract; both new stages are
  authored against this contract.
- ADR-0021 — Settings modular layering; defines the **internal
  structure** of the files this ADR renames.
- ADR-0022 — BoardAdapter capability dispatch; consumes the
  selection persisted by `m10.repo.choose-kanban-backend`.
- ADR-0023 — Architect UX + config item protocol; both new
  stages exemplify it.
- [`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
  — § "Declarative state schema" → "Four settings files",
  § "Stages" rows, § "Decided" resolution items.
- [`../0005-contracts/03-config-schemas.md`](../0005-contracts/03-config-schemas.md)
  — settings-file schema contract; updated in the replacement
  PR to reflect the rename + folded `overrides.yml`.
