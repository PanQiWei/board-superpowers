# operating-kanban — failure-mode dispatch reference

**When you arrive here**: the active projection's invocation has returned a non-success outcome, and you need to (a) classify the failure, (b) pick the right surfacing tier, and (c) decide whether to retry, log, write an audit row, or interrupt the architect synchronously. This file is the cross-Form aggregator: Form A exit codes, Form B MCP tool errors, and Form C HTTP status codes all funnel into typed failure categories below, and each category has a documented architect-visibility tier so callers (`managing-board`, `consuming-card`, `decomposing-into-milestones`, `bootstrapping-repo`) act consistently.

## How to use this file

1. **Identify the failure mode** from § Failure-mode taxonomy by matching the underlying signal (exit code, MCP error code, HTTP status).
2. **Read off the tier** (A / B / C / D) from the same row.
3. **Take the tier action** per § Architect-visibility tiers.
4. **For tier D**, fill in the four-part architect-surfacing template at the bottom and surface synchronously.

## Architect-visibility tiers — what to do per class

**If the failure is class A — silent retry.** The dispatch layer retries internally with a bounded retry count and exponential backoff. The caller never sees the failure unless retries exhaust. Use this for transient transport errors and rate-limits that self-correct (retry budget: 3 attempts at 1s / 4s / 16s for `network-timeout`; one wait-then-retry for `rate-limited` with `Retry-After` ≤ 60s). When retries exhaust, promote to tier C.

**If the failure is class B — log-only.** Return failure to the caller; have the caller log to stderr but NOT write an audit row or surface to the architect. Use this for diagnostic noise that does not change the action's outcome (deprecation notices, non-fatal warnings).

**If the failure is class C — audit-row.** Return failure to the caller; have the caller write an audit row with `outcome=failure` per the propose/resolve sequencing rule from `auditing-actions`. The architect reviews on the next session start. Use this for failures that block the action but are recoverable on a later attempt (network timeout after retry exhaustion, rate-limit with a long `Retry-After`, 409 conflict).

**If the failure is class D — surface immediately.** Return failure to the caller; have the caller surface synchronously in the agent's reply using the four-part template below. Use this for failures that require architect intervention before progress is possible (auth failure, illegal transition, compliance gap, malformed registry).

Tier A is the only tier where the dispatch layer itself retries. All other tiers return a typed failure to the caller; the caller's classification skill decides next steps.

## Architect-surfacing template — use this for tier D

When you surface a tier-D failure, write the agent reply in this four-part shape:

1. **What you were trying to do** — the action name plus parameters in protocol vocabulary. Example: `transition_card(kanban=primary, key=42, target=In Review)`.
2. **What happened** — the failure mode plus the captured detail. Example: `form-a-cli-error: gh project item-edit refused; stderr: 'expected one of [...]; got "Bogus"'`.
3. **What you have tried** — retry count if any, fallback attempts if any. Example: "retried once after 4 s with the same outcome".
4. **What you need from the architect** — the specific intervention. Example: "re-authenticate gh", "fix the project_ref", "choose a different status from the legal set [...]".

This is the same four-part shape used by `superpowers:systematic-debugging`'s investigation reports; the operating-kanban dispatch borrows it so callers and architects share a vocabulary.

## Failure-mode taxonomy

| Mode | Detection | Tier | Retry policy |
|------|-----------|------|--------------|
| `projection-not-set` | `<repo>/.board-superpowers/settings.yml § modules.m10_kanban` is missing or has no kanbans entries; the legacy `config.yml § board` fallback also failed. | D | Not retryable. Route the architect to `bootstrapping-repo`. |
| `projection-id-unknown` | The kanban entry's `projection` field names a value with no matching `references/<projection-id>.md` file. | D | Not retryable. Indicates plugin version skew or registry corruption; architect reviews. |
| `capability-not-declared` | Bootstrap stage predicate evaluator asks the active projection for a capability the projection does not declare. | (returns `not-applicable`, not failure) | N/A — `not-applicable` is normal flow in the bootstrap-stage applicability model, not a failure. The bootstrap-stage executor skips the stage. |
| `compliance-gap` | The active projection's advertised compliance level (L0..L3) is below what the requested action requires (e.g., projection L0, caller asked for `claim_card` which needs L2). | D | Not retryable. Surface "this projection does not support claim_card". |
| `form-a-cli-error` | Form A invocation exited 1 (generic failure) or 2 (pre-condition violation: illegal transition, refused claim, race-loss). Stderr captured. | C (generic) / D (pre-condition) | Not retryable on exit 2 (the violation is deterministic). Exit 1 retryable once with bounded backoff before promoting to tier C. |
| `form-a-config-error` | Form A invocation exited 3 (configuration / dependency missing: gh not installed, gh not authenticated, project_ref invalid). | D | Not retryable. Architect installs / authenticates / fixes config. |
| `form-b-mcp-tool-error` | Form B MCP tool returned a structured error code: `tool-not-found`, `permission-denied`, `invalid-input`. | D (`tool-not-found` / `permission-denied`) / C (`invalid-input`) | Not retryable on `tool-not-found` / `permission-denied`. `invalid-input` retryable once after parameter sanitization. |
| `form-c-http-4xx` | Form C HTTP returned 400 / 422 / 403 / 409 (request-shape or auth-scope problem). | D (400/422/403) / C (409 conflict) | Not retryable on 400/422/403. 409 retryable once after re-reading the conflicting card. |
| `form-c-http-404` | Form C HTTP returned 404 (resource not found). | C (for reads) / A (for DELETE — treat as success) | Not retryable for reads. DELETE-on-404 is success per Form C idempotency rules. |
| `network-timeout` | Form A exit 4 (transient), or Form B/C transport error (curl exit 28 / connection-refused / DNS failure). | A (within retry budget) → C (after exhaustion) | Retryable: 3 attempts with exponential backoff (1s / 4s / 16s). After exhaustion, promote to tier C. |
| `rate-limited` | Form A exit 4 with stderr matching `rate.?limit`, OR Form C HTTP 429 with `Retry-After` header. | A (when `Retry-After` ≤ 60s) → C (when `Retry-After` > 60s or header absent) | Wait `Retry-After` then retry once at tier A. Otherwise tier C. |
| `auth-failed` | Form A exit 3 with stderr matching `auth`, OR Form B MCP `permission-denied`, OR Form C HTTP 401. | D | Form C OAuth projections retry once after refresh attempt before promoting. All other auth failures: not retryable. Architect reviews credentials. |

The table covers the cross-Form failure surface; per-projection reference files MAY add projection-specific failure codes (e.g., GitHub's `secondary rate limit` is a distinct exit code in `form-a-bash.md` even though it folds into `rate-limited` here). Projection-specific codes inherit the base table's tier unless the reference file overrides explicitly.

## Compatibility with `classifying-actions`

A failure in the dispatch layer NEVER changes the upstream autonomy classification result. If your `classifying-actions` consultation returned `R` (architect approval required), the failure path still runs through R's two-entry rule:

- The propose row is already written (before this skill was invoked).
- The dispatch attempt fails.
- You write the resolve row with `outcome=failure` and the failure code.

The architect's approval was for the action's *intent*, not for "the action and any retries it might need". A failure is a terminal state for that R-class instance; if you want to retry, issue a fresh propose row, get a fresh approval, and dispatch again. This is uniform with how `classifying-actions` already handles A-class actions that fail — the failure is a normal terminal state, not an exception requiring policy override.

## Hand-off to `auditing-actions`

For tier-C and tier-D failures, write an audit row with these fields beyond the standard schema (per `auditing-actions` § Schema):

- `outcome: failure`
- `failure_mode: <one of the codes from the taxonomy table>`
- `failure_detail: <captured stderr / response body / structured error, scrubbed of secrets>`
- `retry_count: <how many in-tier-A retries were attempted before surfacing>`

Tier-A failures that retry successfully MAY (per project policy) write an audit row with `outcome: success, retry_count: N>0` so retry rates are observable; this is recommended but not required.

The caller writes the row; this skill never invokes `auditing-actions` directly. Atomic skills do not call sibling skills — cross-skill calls happen at the molecular layer.

## Related

- `action-dispatch.md` — the per-action dispatch table; failures from any Form land here.
- `backend-selection.md` — failure modes upstream of dispatch (registry missing, projection unknown).
- `form-a-bash.md` / `form-b-mcp.md` / `form-c-rest.md` — per-Form failure shapes that funnel into this taxonomy.
- `auditing-actions` SKILL — the audit-row hand-off recipient.
- `classifying-actions` SKILL — the autonomy-classification authority unchanged by failures.
