---
name: operating-kanban
description: Use when an agent needs to perform any of the eight Kanban Protocol actions on the active backend — read_board, read_card, create_card, transition_card, claim_card, release_claim, link_pr_to_card, comment_on_card (OPTIONAL). Routes through the active projection's reference file (Form A bash CLI / Form B plugin-shipped MCP server / Form C REST/GraphQL) per the kanban entry recorded in this repo's settings. Also owns the bootstrap-side setup-capability registry that bootstrap stage predicates consume. Use even when the molecular skill body just says "read the board" or "transition card N to In Review" — that is a protocol action and dispatch goes through this skill. Do NOT use this skill for backend-agnostic schema questions ("what states does a card have", "what is the canonical Card body shape", "how is WIP counted") — that is the board-canon skill.
when_to_use: Use whenever a board-touching skill body invokes a Kanban Protocol action against the live backend, OR a bootstrap stage predicate evaluator needs to know whether the active projection declares a given setup capability.
user-invocable: false
---

# operating-kanban

Use this skill when you need to do one of the eight Kanban Protocol actions — `read_board` / `read_card` / `create_card` / `transition_card` / `claim_card` / `release_claim` / `link_pr_to_card` / `comment_on_card` — on the active backend. Caller passes the action name + payload + (optional) `kanban_id`. Caller receives back the action's typed result or a typed failure.

This skill is also the bootstrap-side dispatcher that answers "does the active projection declare capability X?" so a bootstrap stage predicate can decide to run or skip.

## Reflexive constraint

This skill is atomic: it MUST NOT call any other same-plugin skill. Externally it invokes the active projection (a bash command, an MCP tool, or an HTTP endpoint), but it never reaches back into `briefing-daily` / `intaking-requirement` / `reviewing-pr-queue` / `triaging-board` / `consuming-card` / `decomposing-into-milestones` / `bootstrapping-repo` / `board-canon` / `classifying-actions` / `auditing-actions`. The molecular caller orchestrates; this skill dispatches.

## How to apply this skill

You arrive here with an action name plus a payload. Run these four steps in order.

1. **Resolve the active projection.** Read `<repo>/.board-superpowers/settings.yml § modules.m10_kanban` to find the active kanban entry's `projection` field. Full procedure (including multi-kanban disambiguation, legacy fallback, and every refusal message) is in `references/backend-selection.md`. Output: a path to `references/<projection-id>.md`.

2. **Pick the action's procedure.** Look up the action name in the per-action quick reference below. The row tells you what to pass, what you get back, the action's compliance level, idempotency, and failure tier. For the full per-action breakdown — what `Form A` / `Form B` / `Form C` invocation look like and the audit hand-off sequencing — read `references/action-dispatch.md`.

3. **Invoke per the loaded reference.** Open the projection reference (e.g., `references/github-project-v2.md` for the GitHub Project v2 backend) and run that file's per-action procedure. Form A invocation conventions (exit-code mapping, helper preference, worktree-relative paths) are in `references/form-a-bash.md`; Form B and Form C have analogous files.

4. **On failure, route per `references/failure-mode-dispatch.md`.** Match the underlying signal (Form A exit code, Form B MCP error, Form C HTTP status) to the typed failure mode, take the tier action (silent retry / log-only / audit-row / surface-immediately), and surface to the caller. Do NOT retry unconditionally — the failure-mode table tells you which modes are retryable and at what budget.

## Per-action quick reference

You arrive at the right entry below by matching your action name. Each row tells you what to pass, what you get back, idempotency, the compliance level a projection must advertise to support it, and the failure tier of a typical refusal.

| Action | What you pass | What you get back | Idempotent? | Compliance |
|--------|---------------|-------------------|-------------|------------|
| `read_board` | `(kanban_id?)` | List of card records `(key, title, status, labels, url)` | Yes (read) | L0 |
| `read_card` | `(kanban_id, card_key)` | Full card record `(key, title, body, status, labels, url, timestamps, display_*)` | Yes (read) | L0 |
| `create_card` | `(kanban_id, title, body, labels)` — backend assigns `Card.key`, status starts at `Backlog` | New `Card.key` (opaque string) | No — re-running creates duplicates | L1 |
| `transition_card` | `(kanban_id, card_key, target_status)` | `(success | refused | conflict)` | Yes — transition to current status is a no-op success | L1 |
| `claim_card` | `(kanban_id, card_key, title)` | `(claim acquired | race lost | wip exceeded | refused)` | No across actors — race-loss is a real failure | L2 |
| `release_claim` | `(kanban_id, card_key)` | `(released | not held | branch already gone)` | Yes — repeat release is a no-op | L2 |
| `link_pr_to_card` | `(kanban_id, card_key, pr_url, pr_body)` | `(linked | already linked | fallback inserted)` | Yes — trailer presence is checked before appending | L2 |
| `comment_on_card` (OPTIONAL) | `(kanban_id, card_key, comment_body)` | `(posted | not supported | length exceeded)` | No — each call posts a fresh comment | L1 |

The compliance column is what the projection must advertise to accept the action. If the projection's level is below the row, dispatch refuses synchronously with a typed compliance-gap failure (tier D — surface immediately).

## Three invocation forms

The protocol is transport-agnostic: each projection picks one of three forms for its invocation surface. The choice is the projection's; this skill dispatches uniformly.

| Form | What the reference file documents | Where backends pick it |
|------|------------------------------------|-------------------------|
| Form A — bash CLI | `gh project ...` / `linear ...` / equivalent shell calls plus `bsp_*` helpers from `scripts/lib/common.sh`. | Backends with a stable scriptable CLI. The shipped GitHub Project v2 projection is Form A. |
| Form B — plugin-shipped MCP server | The plugin's `.mcp.json` registers the backend's MCP server; the reference names the tools and their input shapes. | Backends with an official MCP server (Linear, Atlassian Remote MCP for Jira). |
| Form C — REST / GraphQL | The reference documents endpoint shape, auth header derivation, response parsing. | Backends with no MCP server and where a CLI is insufficient. |

Per-form invocation conventions live in `references/form-a-bash.md`, `references/form-b-mcp.md`, `references/form-c-rest.md`. The active projection's reference file tells you which form applies.

## Setup capabilities — bootstrap-side dispatch

Some board-preparation operations (creating the canonical label set, validating the backend's status taxonomy) run only at bootstrap time, not in the runtime action loop. Each projection declares which of these capabilities it supports; bootstrap stage predicates consult that declaration to decide whether to run or skip a stage.

When the bootstrap stage predicate evaluator asks for capability X, do this:

1. Resolve the active projection per Step 1 above (`references/backend-selection.md`).
2. Read the projection reference (`references/<projection-id>.md`) § "Setup capabilities".
3. Return `true` if the named capability is declared; return `not-applicable` if it is not. `not-applicable` is normal flow (the bootstrap stage executor skips the stage); it is NOT a failure.

The capability vocabulary is registry-internal — capability names are valid only within this skill's reference files. The shipped GitHub Project v2 projection declares two capabilities (`ensure-labels`, `validate-status-field`); their procedures live in `references/github-project-v2.md` § "Setup capabilities".

## References

| File | When to read | Purpose |
|------|--------------|---------|
| `references/action-dispatch.md` | When you have an action name and need its procedure (the per-Form invocation rows, audit hand-off sequencing). | Per-action dispatch entries — input/output shape, idempotency, failure tier, per-Form invocation pointers. |
| `references/backend-selection.md` | When you need to resolve the active projection from this repo's settings (Step 1 above), or when you hit a missing-registry / unknown-projection refusal. | The settings → projection resolver; multi-kanban disambiguation; legacy fallback; refusal-message taxonomy. |
| `references/failure-mode-dispatch.md` | When the dispatch returned a non-success outcome and you need to classify, pick a tier, and decide retry / log / audit / surface. | Cross-Form failure taxonomy + four-tier visibility model + architect-surfacing template. |
| `references/form-a-bash.md` | When the active projection is Form A and you need exit-code mapping, helper preference, or worktree-path conventions. | Form A operational contract — invocation conventions, exit-code table, helper preference (`bsp_*` over raw CLI). |
| `references/form-b-mcp.md` | When you are authoring a future Form B projection (Linear, Jira via Atlassian Remote MCP). | Form B conventions — `userConfig.sensitive` credential storage, MCP tool-call shape, response parsing. |
| `references/form-c-rest.md` | When you are authoring a future Form C projection (REST / GraphQL backends with no MCP server). | Form C conventions — auth header derivation, request shape, response parsing. |
| `references/github-project-v2.md` | When the active projection is `github-project-v2` and you need the per-action procedure or setup-capability procedure for this backend. | The shipped GitHub Project v2 projection — paste-and-run shell snippets per action plus the two setup-capability procedures. |

When a new projection ships (Linear, Jira, etc.), its per-projection reference file lands in this directory under the projection's identifier. The reference file declares the projection's chosen Form, the per-action procedure, the custom-state folding map, and the supported setup capabilities.

## What this skill does NOT cover

- Want to know what states a card has, what the Card body schema looks like, how WIP is counted, or how a claim branch is named? See `board-canon`.
- Want to know whether your action proceeds automatically or waits for architect approval? See `classifying-actions`.
- Want to write the audit row that records what was decided and what happened? See `auditing-actions`.
- Want to run a bootstrap stage end-to-end (lifecycle diff, executor selection, stale-state detection)? That is the bootstrapping flow's responsibility; this skill answers the predicate question and dispatches the capability invocation, but does not orchestrate the stage.
- Want to discover which projections this skill recognizes? Read the file names under `references/<projection-id>.md`. There is no introspection API — new projections land by adding a reference file in a normal PR.
