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
>    or
>    [`../../SKILL_DEVELOPMENT.md`](../../SKILL_DEVELOPMENT.md)
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
| ADR-0005 BoardAdapter contract surface | `0003-domain-model/03-aggregates-and-entities.md` § 3.6.3 (Anti-Corruption Layer); spec for any v1 script that calls the adapter (`board-canon` skill, future scripts). Per ADR-0005 Consequences (as amended by ADR-0010), the GitHubProjectAdapter wrapper port lands before v1 GA. |
| ADR-0006 D-AUTONOMY-1 matrix (rows or A/R/N classification) | `0002-product-features-and-flows/03-producer-surface.md` + `04-consumer-surface.md` (every feature row that cites the matrix); `classifying-actions` skill spec; `auditing-actions` skill spec (`action_id` catalog); `0005-contracts/06-audit-log-schema.md`. |
| ADR-0007 plugin-runtime constraint set (C-PLUGIN-1/-2/-3) | Every Producer / Consumer feature with verbs like *monitor*, *detect*, *trigger automatically*. The preflight-piggyback idiom citation. |
| ADR-0008 plugin-to-plugin SKILL invocation | `0005-contracts/04-skill-contracts.md` (sibling-skill classification table); `consuming-card` skill spec (F-C4 fallback rule). |
| `0002-product-features-and-flows/05-bootstrap-surface.md` (state file path / schema) | `0003-domain-model/02-bounded-contexts.md` § 3.2.3; `0003-domain-model/03-aggregates-and-entities.md` § RepoBootstrap / HostBootstrap; `0005-contracts/03-config-schemas.md` + `07-path-conventions.md`; `bootstrapping-repo` + `migrating-repo-version` skill specs. |
| `0002-product-features-and-flows/08-pr-contract.md` (three-section shape) | `consuming-card` skill spec (F-C12); `enforcing-pr-contract` skill spec; `managing-board` Review Queue routine spec (F-02 violation flagging). |
| Skill catalog (add / rename / split / merge any of the 10 v1 skills) | **`../../SKILLS.md` FIRST** (per its Source-of-truth contract — do not touch `../../skills/` until SKILLS.md is updated); then `0004-component-architecture.md` Decision 2 (capability → slot table); `0005-contracts/04-skill-contracts.md` (sibling-skill classification; v1 catalog table); the trigger row above; `../../README.md` and `../../README.zh-CN.md` if user-facing trigger phrases change. |
| Hook intent-injection marker grammar (`INVOKE:` / `REASON:`) | `0004-component-architecture.md` § "Hook intent injection pattern"; `0005-contracts/02-hook-contracts.md` § "Intent-injection markers"; `using-board-superpowers` entry-skill spec. |
| `~/.board-superpowers/` path layout (host-local state) | `0002-product-features-and-flows/05-bootstrap-surface.md`; `0003-domain-model/02-bounded-contexts.md` § 3.2.3; `0005-contracts/03-config-schemas.md` + `07-path-conventions.md`; `0002-product-features-and-flows/07-cross-cutting-invariants.md` I-13. |
| ADR-0009 BYO sqlite as audit DB scheme allowlist | `0005-contracts/06-audit-log-schema.md` (allowlist + scheme-dispatch DDL); `auditing-actions` skill spec; `audit-init.sh` + `audit-log-write.sh` scheme dispatch. |
| mode-field enum (jsonl fallback) | `bsp_audit_local_write` in `../../scripts/lib/common.sh`; `../../scripts/audit-log-write.sh`; `../../skills/auditing-actions/references/degradation-mode.md`; spec 06 § "jsonl fallback mode-field". |
| `post_merge_cleanup` config field (auto-cron tracking) | `0005-contracts/03-config-schemas.md` § post_merge_cleanup; `0002-product-features-and-flows/04-consumer-surface.md` F-C12 + F-C14; `../../skills/consuming-card/SKILL.md` Step 9.5 + Step 12; `../../skills/consuming-card/references/post-merge-cleanup.md`; `../../scripts/post-merge-cleanup.sh` + `../../scripts/install-post-merge-cron.sh`. |
| `AGENTS.md` § "How to compose gstack and superpowers" (the cross-plugin composition rules consumed by manager-mode intake) | `../../skills/managing-board/references/skill-routing.md` (manager-mode mirror) AND `../../skills/managing-board/references/scope-shape-judgment.md` (shape-level companion calling into `skills/decomposing-into-milestones/references/` for the "how" of decomposition); `../../skills/managing-board/references/spec-first-checklist.md` if the new compose rule introduces a new spec precondition; `../../skills/managing-board/references/intake.md` decision tree if a new sibling skill is added or a routing branch shifts. |

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
