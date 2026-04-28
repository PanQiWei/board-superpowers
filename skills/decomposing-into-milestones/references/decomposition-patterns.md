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

## Worked examples — see companion file

The full 5-card OAuth sign-in walkthrough (input artifact + identified capabilities + SPIDR axis selection + 5 card bodies + INVEST/vertical-slicing gate tables + cross-card dep graph + batch summary) lives in `oauth-walkthrough.md`. Splitting it out keeps this reference focused on patterns rather than worked-example detail. The companion file serves both as the canonical worked-example shape AND as `#35`'s dry-run quality verification artifact.
