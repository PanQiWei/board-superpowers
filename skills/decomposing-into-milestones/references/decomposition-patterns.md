# Decomposition patterns — Cohn SPIDR + business catalog

> **Sources**:
> - Cohn, "Five Simple But Powerful Ways to Split User Stories" (SPIDR) — <https://www.mountaingoatsoftware.com/blog/five-simple-but-powerful-ways-to-split-user-stories>
> - Cohn, "Five Story-Splitting Mistakes and How to Stop Making Them" — <https://www.mountaingoatsoftware.com/blog/five-story-splitting-mistakes-and-how-to-stop-making-them>
> Both are Mountain Goat Software canonical sources. **Hamburger method** and **Lawrence patterns** are widely cited in the community but were NOT found at primary URLs in this research pass — treat as community supplement, not Cohn-canon.

## SPIDR — primary

Cohn's 5 canonical split patterns, derived from his analysis of 1000+ user stories across teams he coached. SPIDR is **not** a replacement for Lawrence patterns; it is Cohn's own empirically-derived 5-set.

### S — Spike

A research activity to reduce uncertainty before splitting. The spike's output is a written answer to a specific question (the Acceptance Criterion is "we have a written answer to the question"). Spikes are time-boxed (typically S-sized) and produce **no shipped functionality**.

**Use when**: Independence (INVEST-I) or Estimability (INVEST-E) is failing because of a knowledge gap — "we don't know how OAuth callback URLs interact with this hosting provider's reverse proxy". A spike can answer this in 1-2 hours and unblock the next 4 cards.

**Refuse when**: The "uncertainty" is risk aversion — the team knows the answer but is afraid of committing. Excessive spike extraction (>1/N candidates) is itself a smell (Cohn anti-pattern #4).

### P — Paths

Split by alternative user paths through the same feature. Each path is a separate card.

**Examples**:
- "Pay with credit card" vs. "Pay with Apple Pay" vs. "Pay with bank transfer" — 3 cards, each a vertical slice.
- "Sign in with email + password" vs. "Sign in with OAuth (Google)" vs. "Sign in with OAuth (GitHub)" — 3 cards.
- "Search by keyword" vs. "Search by tag" vs. "Search by date range" — 3 cards.

**Use when**: A feature has multiple alternative entry points or branches. Each branch is shippable independently — users can pay with card before Apple Pay lands.

**Refuse when**: The "paths" are sequential dependencies (path B requires path A), not alternatives. That's a `depends-on` chain, not a Paths split.

### I — Interfaces

Split by browser / hardware / progressive UI fidelity. Each interface variant is a separate card.

**Examples**:
- "Render on desktop browser" vs. "Render on mobile browser" — 2 cards.
- "Plain HTML form" vs. "Enhanced form with autocomplete" — 2 cards (the second is a progressive enhancement on top of the first).
- "CLI command" vs. "GUI button" — 2 cards (same underlying logic, two surfaces).

**Use when**: A feature ships across multiple user-facing surfaces, and one surface can ship before the others. Often pairs with progressive enhancement — ship the no-JS fallback first, layer JS on top.

**Refuse when**: All surfaces share the same underlying logic and the surfaces themselves are trivial — that's not a vertical slice on either surface, just a layer split.

### D — Data

Split by restricting supported data formats / value ranges. Each data variant is a separate card.

**Examples**:
- "Accept MP4 only" → defer "accept WebM, AVI, MKV, MOV..." to follow-up cards.
- "Accept 5-digit US ZIP only" → defer "accept Canadian / UK / international postcodes".
- "Accept ASCII characters only" → defer "accept Unicode" / "accept emoji".

**Use when**: A feature could in principle support N data formats / ranges, but supporting only the most common (1-2) ships value immediately. The remaining (N-2) are follow-up cards.

**Refuse when**: The "supported data" can't be cleanly restricted — restricting breaks the feature entirely. (E.g., "search by date range" with only one date format is fine; "translate to N languages" with only English is meaningless.)

### R — Rules

Split by deferring business-rule enforcement. Each rule is a separate card.

**Examples**:
- "Sign up with email + password" → defer "validate password complexity" / "rate-limit signups" / "block disposable email domains".
- "Submit comment" → defer "profanity filter" / "spam detection" / "rate limit per user".
- "Upload file" → defer "scan for malware" / "verify copyright" / "check file size limit".

**Use when**: The core capability ships value with a minimal rule set, and additional rules layer on top without breaking the core.

**Refuse when**: A "deferred" rule is actually critical for the core value (e.g., deferring authentication on a paid endpoint).

## Five splitting mistakes — Cohn anti-patterns

These are the canonical refusals during the vertical-slicing gate (Step 3 of the SKILL).

### 1. Solo PO splitting

**Anti-pattern**: One person (the product owner / architect) splits stories alone, without dialogue with the implementer.

**Consequence**: Unbalanced or dependent substories. The implementer discovers mid-implementation that the split doesn't match the layer-stack.

**Refusal**: a card whose decomposition was done unilaterally. Restart with collaborative slicing — surface the candidate batch to the implementer for one round of feedback before creating cards.

### 2. Technical layer decomposition (THE layer-split anti-pattern)

**Anti-pattern**: Frontend / backend / schema / DB-only cards.

**Consequence**: > "Stories that don't deliver any value to users on their own" (Cohn). Layer-only cards violate INVEST-V.

**Refusal**: any card whose title or AC is layer-scoped. Reslice using SPIDR Paths / Data / Rules to find the vertical seam.

### 3. Solution over requirements

**Anti-pattern**: The story body specifies HOW (implementation detail) rather than WHAT (post-condition behavior).

**Consequence**: Constrains the implementer, signals stories are smaller than they should be (over-specification = not enough room for negotiation).

**Refusal**: any card whose AC reads as a procedural recipe. Restate as post-conditions on the finished world.

### 4. Excessive spike extraction

**Anti-pattern**: More than 1/N candidates are spikes.

**Consequence**: Signals risk aversion, not knowledge gap. Real uncertainty is rare; over-spiking is procrastination.

**Refusal**: a batch with >1 spike per N regular cards. Trim spikes to genuine knowledge gaps; the rest are estimable directly.

### 5. Premature rule implementation

**Anti-pattern**: Enforcing all business rules upfront, in the first card.

**Consequence**: Inflates card size; first slice can't ship until all rules are coded.

**Refusal**: any first card that bundles 5+ rules. Split via SPIDR-R: ship core capability with minimum rules; layer rules in follow-up cards.

## Business pattern catalog (board-superpowers shortcuts)

These are board-superpowers-original patterns — common feature shapes mapped to recommended SPIDR axes. Use as a lookup, not a textbook.

| Capability shape | Recommended SPIDR axis | Typical card count |
|---|---|---|
| **New feature** (e.g., OAuth sign-in) | Paths (sign-in flow) + Rules (rate limit, error handling) | 3-5 |
| **Data model migration** | Spike (backfill strategy) + Rules (deferred validation) + Data (subset migration) | 2-4 |
| **New surface** (CLI / API / UI) | Interfaces (one surface first) + Paths (per-action) | 4-8 |
| **Refactor with new capability** | Spike (architecture) + Paths (preserve old + introduce new + cutover) | 3 |
| **Bug fix touching multiple surfaces** | Paths (each surface separately) | 2-4 |
| **Dep upgrade** (e.g., framework v1 → v2) | Spike (compat assessment) + Rules (deprecation handling) + Interfaces (per-surface migration) | 3-6 |
| **Feature flag introduction** | Paths (flag-on / flag-off) + Rules (rollout criteria) | 2-3 |
| **CRUD on new entity** | Paths (create / read / update / delete) + Rules (auth / validation deferred) | 4-5 |
| **Async job / background task** | Spike (concurrency model) + Paths (success / failure / retry) | 3-4 |

When a candidate matches one of these shapes, start with the recommended axis. The catalog is a starting point — empirical observation may show a different axis is more productive for the specific feature.

## OAuth full walkthrough

> **Status**: Placeholder for the dry-run quality verification output (`#35` AC #7). The architect runs the SKILL against a fictional OAuth sign-in feature requirement; output captured here as a worked example.

### Input (fictional design artifact)

```
Feature: OAuth sign-in for the dashboard

Users currently sign in with email + password. Add OAuth sign-in
via Google as the second supported provider, then GitHub. Pages
that require sign-in must accept either auth path.

Requirements:
- Google OAuth + GitHub OAuth.
- Sign-out works for all auth paths uniformly.
- New users via OAuth get a default profile (name + avatar from
  the OAuth provider).
- Existing email-password users can link an OAuth identity to
  their account.
- Rate-limit failed OAuth callback handling (10 / hour / IP).
```

### Identified capabilities

Read the input artifact and identify distinct user-visible capabilities:

1. Happy-path sign-in via Google OAuth (the most common path; ships first).
2. Happy-path sign-in via GitHub OAuth (alternative path; ships second per SPIDR-Paths).
3. Sign-out flow uniformly across all auth paths (independent capability).
4. Profile surface populated from OAuth provider data (extends sign-in slices).
5. OAuth callback error handling + rate limiting (defensive cross-cutting; SPIDR-Rules deferral candidate).
6. Account linking (existing email-password user links OAuth identity).

### SPIDR axis selection

- **Paths** primary: Google vs GitHub provider — two independent slices that ship value separately. Account linking is a third path-like capability that touches the existing email-password flow.
- **Rules** secondary: rate-limit + advanced error handling split into a follow-up card (not blocking happy path).
- No Spike needed (OAuth is well-understood); no Interfaces split (single dashboard surface); no Data restriction (provider list is the explicit Paths split).

### Decomposed output (5 cards)

#### Card 1 — Google OAuth happy-path sign-in

```markdown
<!-- thin-pointer -->
**Spec**: docs/features/oauth-signin.md § 1 Google
**Owner**: @architect
**Estimate**: M
<!-- /thin-pointer -->

## Goal
Users can sign in to the dashboard using their Google account from the sign-in page.

## Acceptance criteria
- [ ] Clicking "Sign in with Google" on the dashboard sign-in page redirects to Google's OAuth consent screen.
- [ ] After Google consent, the user lands on the dashboard with a session cookie set; `bash test/auth/google-callback.sh` exits 0.
- [ ] First-time Google sign-in creates a user row with email + name + avatar URL populated from the OAuth `userinfo` endpoint.
- [ ] Returning Google sign-in updates `last_sign_in_at` and refreshes the session.

## Out of scope
- GitHub OAuth (Card 2).
- Account linking for existing email-password users (Card 5).
- OAuth scope beyond `openid email profile` (defer until profile surface needs it).

## Dependencies
- (none — first card in chain)

## Notes
Driver: P0 intake — sign-in friction blocks trial conversion. SPIDR Paths split: Google ships first as the highest-volume provider.

<!-- board-superpowers:card -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:card -->
```

#### Card 2 — GitHub OAuth happy-path sign-in

```markdown
<!-- thin-pointer -->
**Spec**: docs/features/oauth-signin.md § 2 GitHub
**Owner**: @architect
**Estimate**: S
<!-- /thin-pointer -->

## Goal
Users can sign in to the dashboard using their GitHub account from the sign-in page.

## Acceptance criteria
- [ ] Clicking "Sign in with GitHub" on the dashboard sign-in page redirects to GitHub's OAuth consent screen.
- [ ] After GitHub consent, the user lands on the dashboard with a session cookie set; `bash test/auth/github-callback.sh` exits 0.
- [ ] First-time GitHub sign-in creates a user row populated from the GitHub `/user` endpoint.

## Out of scope
- Account linking (Card 5).

## Dependencies
- depends-on (soft): #<Card-1> — preferred ordering (Card 1 establishes the OAuth abstraction layer; Card 2 reuses it). Either ordering ships value, but Card 2 first means duplicating the abstraction work.

## Notes
SPIDR Paths split: second provider, smaller card because abstractions from Card 1 are reusable.

<!-- board-superpowers:card -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:card -->
```

#### Card 3 — Sign-out

```markdown
<!-- thin-pointer -->
**Spec**: docs/features/oauth-signin.md § 3 Sign-out
**Owner**: @architect
**Estimate**: XS
<!-- /thin-pointer -->

## Goal
Users can sign out from any authenticated page; the session and OAuth refresh-token are revoked.

## Acceptance criteria
- [ ] Clicking "Sign out" in the user menu clears the session cookie and redirects to the sign-in page.
- [ ] The OAuth refresh-token (if any) is revoked at the provider via the provider's revocation endpoint; `bash test/auth/signout.sh` exits 0.

## Out of scope
- "Sign out from all devices" — defer to follow-up (SPIDR Rules).

## Dependencies
- depends-on: #<Card-1> — sign-out uses the session abstraction Card 1 establishes.

## Notes
Uniform across providers — same logic for Google + GitHub.

<!-- board-superpowers:card -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:card -->
```

#### Card 4 — Error flows + rate limiting

```markdown
<!-- thin-pointer -->
**Spec**: docs/features/oauth-signin.md § 4 Error handling
**Owner**: @architect
**Estimate**: S
<!-- /thin-pointer -->

## Goal
OAuth callback errors are surfaced to the user with actionable messages, and the callback endpoint is rate-limited per IP.

## Acceptance criteria
- [ ] OAuth provider error responses (`error=access_denied` etc.) render a user-facing error page with a "try again" link; `bash test/auth/error-flows.sh` exits 0 covering 4 error cases.
- [ ] The callback endpoint rate-limits to 10 failed attempts per IP per hour; the 11th returns HTTP 429.
- [ ] Rate-limit counter resets after the hour window; `bash test/auth/rate-limit.sh` exits 0.

## Out of scope
- CSRF-token-mismatch handling (already covered by the OAuth state parameter validation).

## Dependencies
- depends-on: #<Card-1>, #<Card-2> — rate limit applies to both providers' callbacks; error UX uses the same template across providers.

## Notes
SPIDR Rules: rate-limit is a deferred rule that doesn't block happy path but defends against abuse.

<!-- board-superpowers:card -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:card -->
```

#### Card 5 — Account linking for email-password users

```markdown
<!-- thin-pointer -->
**Spec**: docs/features/oauth-signin.md § 5 Account linking
**Owner**: @architect
**Estimate**: M
<!-- /thin-pointer -->

## Goal
Existing email-password users can link an OAuth identity to their account from the profile page; the linked identity becomes a valid sign-in path for the same account.

## Acceptance criteria
- [ ] On the profile page, clicking "Link Google account" / "Link GitHub account" redirects through the OAuth consent flow and binds the returned identity to the current user (no new user row created).
- [ ] After linking, the user can sign out and sign back in via the linked OAuth provider, landing on the same account; `bash test/auth/account-linking.sh` exits 0.
- [ ] Attempting to link an OAuth identity already bound to a different account returns a clear error (NOT silently rebinding); test covers this case.

## Out of scope
- "Unlink" flow — defer (low frequency; users can contact support).

## Dependencies
- depends-on: #<Card-1>, #<Card-2> — uses both providers' OAuth flows; reuses Card 1 abstractions.

## Notes
SPIDR Paths: a third path-like capability that touches the existing email-password authentication. Ships independently of Cards 1+2 once those are Done.

<!-- board-superpowers:card -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:card -->
```

### INVEST gate per card

| Card | I | N | V | E | S | T |
|---|---|---|---|---|---|---|
| 1 (Google sign-in) | ✅ no hidden coupling | ✅ outcome-shape body | ✅ users gain a sign-in path | ✅ M-sized | ✅ within L ceiling | ✅ AC scriptable |
| 2 (GitHub sign-in) | ✅ soft-deps Card 1 | ✅ outcome-shape | ✅ users gain a 2nd sign-in path | ✅ S-sized | ✅ within ceiling | ✅ AC scriptable |
| 3 (Sign-out) | ✅ hard-deps Card 1 | ✅ outcome-shape | ✅ users gain control over session | ✅ XS-sized | ✅ small | ✅ AC scriptable |
| 4 (Error + rate-limit) | ✅ hard-deps Cards 1+2 | ✅ outcome-shape | ✅ defense + UX clarity | ✅ S-sized | ✅ within ceiling | ✅ AC scriptable |
| 5 (Account linking) | ✅ hard-deps Cards 1+2 | ✅ outcome-shape | ✅ users gain identity merge | ✅ M-sized | ✅ within ceiling | ✅ AC scriptable |

All 5 cards pass INVEST 6-letter gate.

### Vertical-slicing gate per card

| Card | Layer-only? | Trailing wire-up? | Solo-PO? | Excessive spike? |
|---|---|---|---|---|
| 1 | ❌ (full UI + backend + DB) | ❌ | ❌ | ❌ |
| 2 | ❌ (full slice, reuses Card 1 abstractions) | ❌ | ❌ | ❌ |
| 3 | ❌ (full slice — UI button + backend revoke) | ❌ | ❌ | ❌ |
| 4 | ❌ (full slice — error UI + backend rate-limit) | ❌ | ❌ | ❌ |
| 5 | ❌ (full slice — profile UI + backend identity-bind) | ❌ | ❌ | ❌ |

All 5 cards pass vertical-slicing gate.

### Cross-card dep graph

```
Card 1 (Google sign-in, M)
   ├── soft ──> Card 2 (GitHub sign-in, S)
   ├── hard ──> Card 3 (Sign-out, XS)
   ├── hard ──> Card 4 (Error + rate-limit, S)
   └── hard ──> Card 5 (Account linking, M)

Card 2 ─── hard ──> Card 4 (rate-limit applies to both)
       └── hard ──> Card 5 (linking uses both providers)
```

Hard dependencies: 3 → 1; 4 → 1, 2; 5 → 1, 2.
Soft dependency: 2 → 1 (preferred ordering, not blocking).

### Batch summary

- 5 cards total.
- Size distribution: 1 XS + 2 S + 2 M.
- Total LOC estimate: ~700-1100 (sum of mid-points: 25 + 100 + 100 + 300 + 300 + 300 ≈ 1125, but cards 2-5 reuse Card 1 abstractions so realistic delta is ~700-900).
- Recommended ordering: Card 1 first (unblocks all others), then Card 2 (in parallel with 3, since 3 only hard-deps on 1), Cards 4 and 5 last (both hard-dep on Cards 1+2).
- All cards pass INVEST + vertical-slicing gates; ready for Step 8 batch propose → ack → batch create.
