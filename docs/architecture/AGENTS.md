# docs/architecture/ — spec governance contract

> **Before any edit under `docs/architecture/`** (writing /
> revising any spec doc, ADR, or contract — not just running
> an editor):
>
> 1. Identify which spec section your change touches and which
>    other docs cite it. The Spec change-impact matrix below
>    is the canonical cross-reference.
> 2. If your change makes a contract in any of
>    [`../../PLUGIN_DEVELOPMENT.md`](../../PLUGIN_DEVELOPMENT.md),
>    [`../../MULTI_AGENT_DEVELOPMENT.md`](../../MULTI_AGENT_DEVELOPMENT.md),
>    [`../../SKILL_DEVELOPMENT.md`](../../SKILL_DEVELOPMENT.md),
>    [`../../SETUP_STAGES_DEVELOPMENT.md`](../../SETUP_STAGES_DEVELOPMENT.md),
>    or
>    [`../../BOARD_DEVELOPMENT.md`](../../BOARD_DEVELOPMENT.md)
>    stale, fix the companion in the **same PR** — not a
>    follow-up. Doc lag is the primary failure mode that makes
>    this pattern decay over time.
> 3. Spec body stays in **English** (per
>    `SKILL_DEVELOPMENT.md` Anti-pattern A5). Chinese
>    discussion belongs in commit messages, PR bodies, or
>    `notes-zh.md` files outside the spec tree.

This contract is the per-directory operational checklist for
spec authoring. The full discipline is shaped by the docs
themselves; this file is the thin "what every spec PR must
satisfy" view.

## ADR discipline

- **One ADR per architectural decision.** ADRs are immutable
  once accepted. Superseding an ADR creates a new one; the old
  one's status field gets `superseded by ADR-N`. Never edit a
  retired ADR's body in-place.
- **Cite sources.** When a spec page makes a claim about the
  platform, link the canonical doc URL (CC docs, Codex docs,
  agentskills.io). When it makes a claim about academic
  methodology, link the primary source.
- **URL freshness.** Each spec page that cites external URLs
  carries a "URL freshness" check date. Re-verify when
  modifying related code; a broken or moved canonical URL is a
  load-bearing fact and must be patched in the PR that catches
  it.

## Same-PR contract update

If a spec change makes a companion doc stale (one of the three
required-reading docs above, or another spec page), fix the
companion in the **same PR**. PRs that update one side of a
contract without the matched side are incomplete.

## Spec change-impact matrix

The v1 spec is a graph of cross-references. Touching one node
often forces companion edits. Use this matrix during PR
preparation:

| If you change… | You must also update… |
|----------------|----------------------|
| `0001-positioning.md` premise (P1..P8) or non-goal | Every spec doc that cites the changed premise (grep `docs/architecture/` for `P<N>`). Promote to a new ADR if the premise materially shifts. |
| ADR-0005 BoardAdapter contract surface (now rescoped to v1 GitHubProjectAdapter projection per ADR-0025) | `0003-domain-model/06-context-map.md` § 3.6.3 (Anti-Corruption Layer — the projection IS the ACL); spec for any v1 script that calls the adapter (`board-canon` skill, future scripts). Per ADR-0005 Consequences (as amended by ADR-0010), the GitHubProjectAdapter wrapper port lands before v1 GA — but is now optional refactoring of the Form A projection, not a universal-contract gate. |
| `0005-contracts/00-kanban-protocol.md` (Kanban Protocol — top-level contract) ontology / state machine / identity / action contracts / compliance levels | ADR-0025 (the protocol's anchoring ADR — supersession requires updating it); ADR-0005 (rescoped projection); `0003-domain-model/01-ubiquitous-language.md` (`Card.key` / `Kanban Protocol` / `Kanban Protocol projection` / `KeySlug` entries); `0003-domain-model/03-aggregates-and-entities.md` § Card / § ConsumerLogical aggregates; `0003-domain-model/06-context-map.md` § 3.6.3 (the ACL reframe); `board-canon` skill spec (state machine + branch naming SPOT — protocol cites, does not duplicate); `operating-kanban` skill spec (when it lands v0.5.0; backend dispatch SPOT); `0005-contracts/03-config-schemas.md` (`kanban:` block in `<repo>/.board-superpowers/config.yml`); `0001-positioning.md` P2a (substrate commitment phrasing); per-backend reference files under `skills/operating-kanban/references/`. |
| Branch-naming convention `claim/<key-slug>-<title-slug>` (per ADR-0025 abstraction) | `0005-contracts/00-kanban-protocol.md` § Identity § Branch naming; `0003-domain-model/01-ubiquitous-language.md` (`Card.key` / `KeySlug` / `ClaimBranch` / `ClaimMarker` entries); `0003-domain-model/03-aggregates-and-entities.md` § Card aggregate / § ConsumerLogical aggregate (member entities); `0005-contracts/05-github-artifact-schemas.md` § Branch naming (v1 GitHub projection's byte-compatible form); `0005-contracts/07-path-conventions.md` § Worktree path resolution; `skills/board-canon/references/branch-naming.md` (slugifier SPOT — v0.5.0 patch). Same-PR rule when the branch shape ever changes again. |
| `0005-contracts/03-config-schemas.md` `modules.m10_kanban` block (v0.5.0 planned schema; not yet shipped) | M10 config-item stage (`m10.repo.choose-kanban-backend` per ADR-0024) MUST be patched in same PR as v0.5.0 ship; `operating-kanban` SKILL (must land same-PR); `0005-contracts/06-audit-log-schema.md` `project` column (audit emission writes the active backend's `project_ref`); `BOARD_DEVELOPMENT.md` § 7 "Setup-stages bridge" if the seam shape changes. |
| `BOARD_DEVELOPMENT.md` (any section — protocol mental model, anti-patterns, authoring rules, backend projection authoring, setup-stages bridge, AI-native concept hygiene reminder) OR ADR-0025 / ADR-0026 / `0005-contracts/00-kanban-protocol.md` § Multi-kanban semantics or § Card hierarchy or § Action contracts | **`../../BOARD_DEVELOPMENT.md`** in the SAME PR — the navigation guide cites these sections as authority and goes stale on every edit. Plus: `skills/board-canon/SKILL.md` (state machine + branch naming SPOT); `skills/operating-kanban/SKILL.md` (when it ships v0.5.0); each backend's reference file under `skills/operating-kanban/references/<backend>.md`; `skills/AGENTS.md` § "Board-touching SKILLs — additional read" if trigger conditions change; `0001-positioning.md` § "AI-native concept hygiene" if the falsification test or degenerate-concept catalog changes. |
| ADR-0006 D-AUTONOMY-1 matrix (rows or A/R/N classification) | `0002-product-features-and-flows/03-producer-surface.md` + `04-consumer-surface.md` (every feature row that cites the matrix); `classifying-actions` skill spec; `auditing-actions` skill spec (`action_id` catalog); `0005-contracts/06-audit-log-schema.md`. |
| ADR-0007 plugin-runtime constraint set (C-PLUGIN-1/-2/-3) | Every Producer / Consumer feature with verbs like *monitor*, *detect*, *trigger automatically*. The preflight-piggyback idiom citation. |
| ADR-0008 plugin-to-plugin SKILL invocation | `0005-contracts/04-skill-contracts.md` (sibling-skill classification table); `consuming-card` skill spec (F-C4 fallback rule). |
| `0005-contracts/09-session-agent-protocol.md` (J1–J5 axis definitions / value enums / K-budget rule for `session-hook` / cross-axis legal-combination matrix / surface-extension contract) | Every surface spec citing the protocol — `0002-product-features-and-flows/03-producer-surface-redesign.md`, `04-consumer-surface-redesign.md`, future `05-bootstrap-surface-redesign.md` extension if it adopts J1–J5; `../../FEATURE_DESIGN_METHODOLOGY.md` § "Stage 2 — Locating each node" if axis definitions or value enums shift; future ADR if the protocol gets revised at architectural significance (new dimension, value-enum break). Cron-as-trigger-carrier governance is pinned by [ADR-0027](./adr/0027-cron-as-trigger-carrier.md) (complement to ADR-0007 — plugin-runtime constraints unchanged); the protocol's J2 `cron-job` value cites this ADR. |
| ADR-0027 cron-as-trigger-carrier (the carrier ladder's `cron-job` value, the compute / present split idiom, the persistent-state-only output rule for cron) | `0005-contracts/09-session-agent-protocol.md` § J2 `cron-job` row + § "Open / TBD" closure marker; `0002-product-features-and-flows/03-producer-surface-redesign.md` + `04-consumer-surface-redesign.md` § "J1–J5 distribution observation" (the cron-bearing nodes' carrier values); future `05-bootstrap-surface-redesign.md` (M11 cron-schedule config-item stage when v1-complete cron-J2 nodes ship); `audit-log-write.sh` + future `state.yml`-writing scripts (concurrency-safety inheritance from cron + architect-session co-write). |
| `0002-product-features-and-flows/05-bootstrap-surface.md` (state file path / schema) | `0003-domain-model/02-bounded-contexts.md` § 3.2.3; `0003-domain-model/03-aggregates-and-entities.md` § RepoBootstrap / HostBootstrap; `0005-contracts/03-config-schemas.md` + `07-path-conventions.md`; `bootstrapping-repo` skill spec (sole executor for setup-stages per [ADR-0012](./adr/0012-unified-check-script-trigger-model.md), which absorbed the formerly deferred `migrating-repo-version` scope). |
| `0002-product-features-and-flows/05-bootstrap-surface-redesign.md` (any section — three axes, stages registry, trigger model, lifecycle, settings layering, repo identity, architect UX) OR any of ADR-0012..ADR-0024 (the setup-stages ADR family) | **`../../SETUP_STAGES_DEVELOPMENT.md`** in the SAME PR — the navigation guide cites these sections as authority and goes stale on every edit. Plus: `../../scripts/stages-registry.yml` + `../../scripts/stages_lib/**` + `../../scripts/stages-registry.schema.json` (the runtime registry); `../../skills/bootstrapping-repo/SKILL.md` (the SKILL that consumes the registry); the four `settings.yml` templates if their layout changes; `../../SKILLS.md` if the SKILL's role description shifts. |
| `0002-product-features-and-flows/08-pr-contract.md` (three-section shape) | `consuming-card` skill spec (F-C12); `enforcing-pr-contract` skill spec; `managing-board` Review Queue routine spec (F-02 violation flagging). |
| Skill catalog (add / rename / split / merge any of the 10 v1 skills) | **`../../SKILLS.md` FIRST** (per its Source-of-truth contract — do not touch `../../skills/` until SKILLS.md is updated); then `0004-component-architecture.md` Decision 2 (capability → slot table); `0005-contracts/04-skill-contracts.md` (sibling-skill classification; v1 catalog table); the trigger row above; `../../README.md` and `../../README.zh-CN.md` if user-facing trigger phrases change. |
| `SKILLS.md` v1 catalog narrowing (`migrating-repo-version` absorbed into `bootstrapping-repo` per ADR-0012) | `bootstrapping-repo` SKILL body (D10 follow-up); entry-skill catalog enumeration (`skills/using-board-superpowers/SKILL.md` + 5 references); `BOARD_DEVELOPMENT.md` § 7 setup-stages bridge writer attributions; `hooks/session-start.sh` `INVOKE` marker comments; `.codex-plugin/plugin.json` longDescription; project root `AGENTS.md` § "Project status"; ADR-0012 + ADR-0011 status-list audits to confirm no stale "deferred" claim. |
| Hook intent-injection marker grammar (`INVOKE:` / `REASON:`) | `0004-component-architecture.md` § "Hook intent injection pattern"; `0005-contracts/02-hook-contracts.md` § "Intent-injection markers"; `using-board-superpowers` entry-skill spec. |
| `~/.board-superpowers/` path layout (host-local state) | `0002-product-features-and-flows/05-bootstrap-surface.md`; `0003-domain-model/02-bounded-contexts.md` § 3.2.3; `0005-contracts/03-config-schemas.md` + `07-path-conventions.md`; `0002-product-features-and-flows/07-cross-cutting-invariants.md` I-13. |
| ADR-0009 BYO sqlite as audit DB scheme allowlist | `0005-contracts/06-audit-log-schema.md` (allowlist + scheme-dispatch DDL); `auditing-actions` skill spec; `audit-init.sh` + `audit-log-write.sh` scheme dispatch. |
| mode-field enum (jsonl fallback) | `bsp_audit_local_write` in `../../scripts/lib/common.sh`; `../../scripts/audit-log-write.sh`; `../../skills/auditing-actions/references/degradation-mode.md`; spec 06 § "jsonl fallback mode-field". |
| `post_merge_cleanup` config field (auto-cron tracking) | `0005-contracts/03-config-schemas.md` § post_merge_cleanup; `0002-product-features-and-flows/04-consumer-surface.md` F-C12 + F-C14; `../../skills/consuming-card/SKILL.md` Step 9.5 + Step 12; `../../skills/consuming-card/references/post-merge-cleanup.md`; `../../scripts/post-merge-cleanup.sh` + `../../scripts/install-post-merge-cron.sh`. |
| `AGENTS.md` § "How to compose gstack and superpowers" (the cross-plugin composition rules consumed by manager-mode intake) | `../../skills/managing-board/references/skill-routing.md` (manager-mode mirror) AND `../../skills/managing-board/references/scope-shape-judgment.md` (shape-level companion calling into `skills/decomposing-into-milestones/references/` for the "how" of decomposition); `../../skills/managing-board/references/spec-first-checklist.md` if the new compose rule introduces a new spec precondition; `../../skills/managing-board/references/intake.md` decision tree if a new sibling skill is added or a routing branch shifts. |
| `skills/AGENTS.md` Process gate — adding/removing a gated path or skill, OR adding a new gate-blocking hook | `../../hooks/pre-tool-use.sh` + `../../hooks/post-tool-use.sh` (the enforcement pair); `../../hooks/hooks.json` (event registration); `../../hooks/AGENTS.md` Invariant 5 (gate-blocking inversion); `../../scripts/register-codex-hooks.sh` (Codex parity); `0005-contracts/02-hook-contracts.md` § "PreToolUse gate hook" (contract); `../../tests/test-skills-edit-gate.sh` (regression test). |
| ADR-0027 § M3 dispatch model (`kanban_projection_capability` predicate; projection-reference-file dispatch; replaces ADR-0022's BoardAdapter SDK dispatch) — including any future supersession revisiting the dispatch shape | ADR-0022 (the superseded ADR; status header + § M3 text preserved); ADR-0024 (M10 stage canonical name amended); `0004-component-architecture.md` § "Decision references" ADR-0027 row; `0005-contracts/00-kanban-protocol.md` § Action contracts + § Setup capabilities (when v0.5.0 amendment lands); `0002-product-features-and-flows/05-bootstrap-surface-redesign.md` § Modules M3 + M10 (**#67 paired-PR territory** — coordinate before any future dispatch-shape change); `skills/operating-kanban/SKILL.md` + `references/<projection-id>.md` § "Setup capabilities" (the per-projection capability declarations the predicate evaluator reads); `BOARD_DEVELOPMENT.md` § 7 "Setup-stages bridge" (the bridge framing). |
| M10 stage canonical name (`m10.repo.choose-kanban-projection` per ADR-0027 § 4) and `modules.m10_kanban.<id>.projection` settings field name (per ADR-0026 § Multi-kanban schema) | ADR-0027 § 4 (the rename ADR); ADR-0024 § Part B (the rename source ADR; status header amended); ADR-0026 § Multi-kanban schema (settings.yml field name authority); `0002-product-features-and-flows/05-bootstrap-surface-redesign.md` § Modules M10 (**#67 paired-PR territory**); `0005-contracts/03-config-schemas.md` § `modules.m10_kanban` (field name shipping in PR #65); `skills/operating-kanban/references/<projection-id>.md` § "Setup capabilities" naming consistency; user-facing prompt strings in M10 stage's executor. |

When v1 implementation grows, this matrix grows additional
rows mapping spec → code (e.g., "if
`0005-contracts/04-skill-contracts.md` description discipline
changes → re-read every `skills/*/SKILL.md` frontmatter").

## Where the long-form companion docs live

- Plugin / hook / script platform contracts (CC + Codex) →
  [`../../PLUGIN_DEVELOPMENT.md`](../../PLUGIN_DEVELOPMENT.md).
- Subagent / agent-team / orchestration contracts →
  [`../../MULTI_AGENT_DEVELOPMENT.md`](../../MULTI_AGENT_DEVELOPMENT.md).
- Skill-authoring discipline →
  [`../../SKILL_DEVELOPMENT.md`](../../SKILL_DEVELOPMENT.md).
- Skill catalog / call graph / topology →
  [`../../SKILLS.md`](../../SKILLS.md).
- Setup-stages development (registry, 5-callable contract,
  agentic config-item protocol, partitioned settings layering,
  anti-patterns) →
  [`../../SETUP_STAGES_DEVELOPMENT.md`](../../SETUP_STAGES_DEVELOPMENT.md).
