# skills/ — skill-authoring contract

> # ⛔ STOP — Process gate (read this completely before any edit)
>
> Editing **any file under `skills/`** triggers a Process gate that
> requires `example-skills:skill-creator` to be invoked in this
> session FIRST. The gate is enforced at two layers:
>
> - **Tool-level (hard).** `hooks/pre-tool-use.sh` blocks
>   `Edit / Write / MultiEdit` on `skills/**` with exit code 2 +
>   reason on stderr until `example-skills:skill-creator` runs in
>   this session. The hook self-clears after a successful invocation
>   via the companion `hooks/post-tool-use.sh`. Contract:
>   [`../docs/architecture/0005-contracts/02-hook-contracts.md`](../docs/architecture/0005-contracts/02-hook-contracts.md)
>   § "PreToolUse gate hook".
> - **Doctrinal (binding).** AGENTS.md (root) Doctrine #4 prohibits
>   skipping the entry skill, even when the work feels routine.
>
> **Sequence to clear the gate** (both implementation and
> review phases):
>
> 1. **STOP** any plan to edit `skills/**`.
> 2. **Acknowledge in your reply**: "About to/just touched
>    skills/. Process gate fires; invoking
>    example-skills:skill-creator now." If `skill-creator`
>    already ran this session, swap "invoking" for "already
>    invoked at <turn>".
> 3. **Invoke `example-skills:skill-creator`** via the Skill
>    tool. The skill carries cross-platform skill-authoring
>    discipline (frontmatter optimization heuristics, Skeleton
>    selection, Regime 1/2 testing scaffolding) that the body of
>    [`../SKILL_DEVELOPMENT.md`](../SKILL_DEVELOPMENT.md)
>    documents. After invocation the gate clears for the rest of
>    this session.
> 4. **Read [`../SKILL_DEVELOPMENT.md`](../SKILL_DEVELOPMENT.md)
>    FIRST** — even if you read it in an earlier session.
>    Selective read of the touched sections (skill graph framing,
>    three-tier frontmatter, body skeletons, anti-patterns,
>    testing regimes) is fine, but the read MUST happen in
>    **this** session before the first edit. "I already know it"
>    is forbidden — the doc may have changed and your
>    context-window may have decayed since the last read.
> 5. **Update [`../SKILLS.md`](../SKILLS.md)** if your change
>    adds / removes / renames / re-layers a skill, OR adds a new
>    references file inside an existing skill (the catalog row
>    lists references). The catalog row MUST land in the same PR
>    (paired-PR contract); when feasible, in the same commit as
>    the SKILL change or in an immediately-preceding commit
>    (paired-commit, the strict reading of "edit FIRST" — see §
>    "SKILLS.md edit-first contract" below).
>
> **Review-phase additions** (independent review or self-review
> during PR-prep). Steps 1-4 above still apply. In addition:
>
> - **Cross-check against [`../SKILLS.md`](../SKILLS.md)** —
>   verify the catalog entry matches the SKILL's actual
>   `.skill-meta.yaml` (layer / type / mode / bounded-context)
>   and `SKILL.md` (description / cross-skill refs / body length
>   vs the layer's budget). Memory
>   `feedback_reviewer_prompt_reads_source_of_truth` mandates
>   that reviewers re-read source-of-truth sections independently
>   instead of relying on the implementer's checklist.
> - **Validate test-regime presence** — per
>   `SKILL_DEVELOPMENT.md` § "Testing skills", confirm the SKILL
>   has the appropriate test artifact: `evals/evals.json` for
>   output-shaped skills (Regime 2 — eval matrix); pressure-
>   scenario log for discipline-shaped skills (Regime 1 —
>   RED-GREEN-REFACTOR). A new skill landed without either is a
>   blocker, not a minor finding.
>
> **Cross-platform applicability — partial**: the **doctrinal**
> gate (this STOP block + AGENTS.md Doctrine #4) applies equally
> to Claude Code and Codex CLI. The **tool-level** gate
> (`hooks/pre-tool-use.sh` + `hooks/post-tool-use.sh`) is
> **Claude Code only** — Codex has no `Skill` model-facing tool
> to observe `skill-creator` invocations through, so the flag-file
> lifecycle cannot complete on Codex. Registering the hook pair
> on Codex without a working flag-write path would deadlock every
> `skills/` edit. Codex sessions get the doctrinal gate only;
> CC sessions get both layers. Full rationale:
> [`../docs/architecture/0005-contracts/02-hook-contracts.md`](../docs/architecture/0005-contracts/02-hook-contracts.md)
> § "Codex parity gap — gate enforcement". `scripts/register-codex-hooks.sh
> --install-user` writes only `SessionStart` on Codex; earlier
> rollouts that briefly included the gate pair are auto-cleaned
> on next install.

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
- `scripts/verify-skill-anti-patterns.sh` — A9 (project-internal
  codes in SKILL.md) + A10 (phase narrative in skill files).
- `tests/test-skills-edit-gate.sh` — gate hook hermetic regression
  test (Edit / Write / MultiEdit blocked without skill-creator;
  flag-file lifecycle through `pre-tool-use.sh` +
  `post-tool-use.sh`).
- `shellcheck -x` over any new / changed scripts in the skill
  directory (e.g., skill-bundled scripts under
  `<skill>/scripts/`).

## Stage-touching SKILLs — additional read

If your work edits **`skills/bootstrapping-repo/`** or
introduces a new SKILL whose body executes setup-stage
machinery (registry walk, lifecycle diff, agentic config-item
elicitation per [ADR-0023](../docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md)),
**also Read [`../SETUP_STAGES_DEVELOPMENT.md`](../SETUP_STAGES_DEVELOPMENT.md)**
end-to-end before the first edit. The Process gate above
(skill-creator + SKILL_DEVELOPMENT.md) covers SKILL-authoring
discipline; the setup-stages guide covers the system the SKILL
operates against (the 5-callable contract, three axes,
`applicable_when` forms, partitioned settings layout, anti-
patterns). Skill-authoring discipline + setup-stages
discipline are independent concerns — both reads are required
when the SKILL touches stages.

Concrete trigger conditions (any one suffices):

- The SKILL body invokes the bootstrap stage executor or the
  lifecycle-diff helper.
- The SKILL writes to any of the four partitioned
  `settings.yml` files.
- The SKILL adds a new `action_id` that classifies a
  setup-stage operation through `classifying-actions` /
  `auditing-actions`.
- The SKILL's spec changes the consumer-side contract for
  the agentic config-item protocol (the 5 protocol elements
  per [ADR-0023](../docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md)).

Same-PR contract: any SKILL change that makes
[`../SETUP_STAGES_DEVELOPMENT.md`](../SETUP_STAGES_DEVELOPMENT.md)
or [`../SKILLS.md`](../SKILLS.md) stale fixes both in this PR.

## Board-touching SKILLs — additional read

If your work edits **`skills/board-canon/`**, **`skills/operating-kanban/`**
(planned v0.5.0), or any SKILL whose body invokes the Kanban
Protocol's eight actions (`read_board`, `read_card`,
`create_card`, `transition_card`, `claim_card`, `release_claim`,
`link_pr_to_card`, `comment_on_card`) per
[ADR-0025](../docs/architecture/adr/0025-kanban-protocol-as-top-contract.md)
and [ADR-0026](../docs/architecture/adr/0026-multi-kanban-lifecycle-and-flat-card-hierarchy.md),
**also Read [`../BOARD_DEVELOPMENT.md`](../BOARD_DEVELOPMENT.md)**
end-to-end before the first edit. The Process gate above
(skill-creator + SKILL_DEVELOPMENT.md) covers SKILL-authoring
discipline; the board-development guide covers the system the
SKILL operates against (the eight protocol actions, six canonical
statuses, multi-kanban schema, flat-Card hierarchy + display-only
metadata, the bridge to setup-stages M10). Skill-authoring
discipline + board-layer discipline are independent concerns —
both reads are required when the SKILL touches the board layer.

Concrete trigger conditions (any one suffices):

- The SKILL body invokes any of the eight Kanban Protocol
  actions (or their projection-specific bash equivalent —
  `claim-card.sh`, the planned `operating-kanban` dispatch, etc.).
- The SKILL writes to `<repo>/.board-superpowers/settings.yml`
  under `modules.m10_kanban`.
- The SKILL touches the claim primitive, branch-naming
  convention, or Card schema (thin-pointer / 5 mandatory sections
  / bottom marker).
- The SKILL adds a new `action_id` that classifies a board
  operation through `classifying-actions` / `auditing-actions`.
- The SKILL changes the relationship between a Producer / Consumer
  routine and the protocol's eight actions.
- The SKILL adds or modifies a backend projection's reference
  file under `skills/operating-kanban/references/<backend>.md`.

Same-PR contract: any SKILL change that makes
[`../BOARD_DEVELOPMENT.md`](../BOARD_DEVELOPMENT.md),
[`../docs/architecture/0005-contracts/00-kanban-protocol.md`](../docs/architecture/0005-contracts/00-kanban-protocol.md),
or [`../SKILLS.md`](../SKILLS.md) stale fixes all stale ones in
this PR.

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
- Setup-stages system (when the SKILL operates against
  stages — registry, 5-callable contract, agentic config-item
  protocol, partitioned settings layering) →
  [`../SETUP_STAGES_DEVELOPMENT.md`](../SETUP_STAGES_DEVELOPMENT.md).
- Board / card / Kanban Protocol layer (when the SKILL invokes
  protocol actions, touches multi-kanban schema, or acts on
  cards / branches / claim) →
  [`../BOARD_DEVELOPMENT.md`](../BOARD_DEVELOPMENT.md).
