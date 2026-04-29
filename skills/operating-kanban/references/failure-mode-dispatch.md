# operating-kanban — failure-mode dispatch reference

Per-projection failure-mode taxonomy + the surfacing convention each mode uses. This file is the cross-Form aggregator: Form A exit codes, Form B MCP tool errors, and Form C HTTP status codes all funnel into the typed failure categories below, and each category has a documented architect-visibility tier so callers (`managing-board`, `consuming-card`, `decomposing-into-milestones`, `bootstrapping-repo`) know whether to retry silently, write an audit row, or surface immediately to the architect.

## Architect-visibility tiers

| Tier | Behavior | When |
|------|----------|------|
| **A — silent retry** | Dispatch layer retries internally (bounded retry count + exponential backoff); caller never sees the failure unless retries exhaust. | Transient transport / rate-limit errors that are routinely self-correcting. |
| **B — log-only** | Dispatch returns failure to caller; caller logs to stderr but does not write an audit row or surface to the architect. | Diagnostic noise that does not change the action's outcome (e.g., deprecation notice on stderr, non-fatal). |
| **C — audit-row** | Dispatch returns failure to caller; caller writes an audit row with `outcome=failure` per the propose/resolve sequencing rule from `auditing-actions`. The architect reviews on next session start. | Failures that block the action but are recoverable on a later attempt (network timeout after retry exhaustion; rate-limit with a long `Retry-After`). |
| **D — surface-immediately** | Dispatch returns failure to caller; caller surfaces synchronously in the agent's reply ("I attempted X but the projection refused with Y; here is what I need from you"). | Failures that require architect intervention before the caller can proceed (auth failure, illegal transition, compliance gap, malformed registry). |

Tier A is the only tier where the dispatch layer itself retries. All other tiers return a typed failure to the caller; the caller's classification skill decides next steps. The four tiers are caller-policy categories — the dispatch layer assigns a tier per failure mode per the table below.

## Failure-mode taxonomy

| Mode | Detection | Tier | Retry policy |
|------|-----------|------|--------------|
| `projection-not-set` | `<repo>/.board-superpowers/settings.yml § modules.m10_kanban` is missing or has no kanbans entries; the legacy `config.yml § board` fallback also failed. | D | Not retryable. The caller routes the architect to bootstrapping-repo. |
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

A failure in the dispatch layer NEVER changes the upstream autonomy classification result. If the caller's classifying-actions consultation returned `R` (architect approval required), the failure path still runs through R's two-entry rule:

- The propose row is already written (before this skill was invoked).
- The dispatch attempt fails.
- The caller writes the resolve row with `outcome=failure` and the failure code.

The architect's approval was for the action's *intent*, not for "the action and any retries it might need". A failure is a terminal state for that R-class instance; if the caller wants to retry, it issues a fresh propose row, gets a fresh approval, and dispatches again. This is uniform with how `classifying-actions` already handles A-class actions that fail — the failure is a normal terminal state, not an exception requiring policy override.

## Hand-off to `auditing-actions`

For tier-C and tier-D failures the caller writes an audit row with these fields beyond the standard schema (per `auditing-actions` § Schema):

- `outcome: failure`
- `failure_mode: <one of the codes from the taxonomy table>`
- `failure_detail: <captured stderr / response body / structured error, scrubbed of secrets>`
- `retry_count: <how many in-tier-A retries were attempted before surfacing>`

Tier-A failures that retry successfully MAY (per project policy) write an audit row with `outcome: success, retry_count: N>0` so retry rates are observable; this is recommended but not required for v0.5.0.

The caller writes the row; this skill never invokes `auditing-actions` directly. Per the atomic-layer reflexive constraint (§ Reflexive constraint in `SKILL.md`) cross-skill calls happen at the molecular layer.

## Surfacing convention — what the caller says to the architect

Tier-D failures surface in the agent's reply with a four-part structure:

1. **What the caller was trying to do** — the action name + parameters in protocol vocabulary (`transition_card(kanban=primary, key=42, target=In Review)`).
2. **What happened** — the failure mode + the captured detail (`form-a-cli-error: gh project item-edit refused; stderr: 'expected one of [...]; got "Bogus"'`).
3. **What the caller has tried** — retry count if any, fallback attempts if any.
4. **What the caller needs from the architect** — the specific intervention (re-authenticate gh, fix the project_ref, choose a different status).

This is the same four-part surfacing convention used by `superpowers:systematic-debugging`'s investigation reports; the operating-kanban dispatch borrows it for protocol-layer failures so callers and architects share a vocabulary.

## Related

- `action-dispatch.md` — the per-action dispatch table; failures from any Form land here.
- `backend-selection.md` — failure modes upstream of dispatch (registry missing, projection unknown).
- `form-a-bash.md` / `form-b-mcp.md` / `form-c-rest.md` — per-Form failure shapes that funnel into this taxonomy.
- `auditing-actions` SKILL — the audit-row hand-off recipient.
- `classifying-actions` SKILL — the autonomy-classification authority unchanged by failures.
