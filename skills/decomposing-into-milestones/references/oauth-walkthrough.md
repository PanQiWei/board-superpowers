# OAuth full walkthrough — worked example

> **Companion to** `references/decomposition-patterns.md` (SPIDR + Cohn anti-patterns + business pattern catalog). Cross-link from `SKILL.md` § "Worked examples".
> **Status**: serves both as `#35` AC #7 dry-run quality verification artifact AND as the canonical reference shape for new feature artifacts. Architects authoring synthesis output should mirror the structure shown here (input → identified capabilities → SPIDR axis selection → 5 cards with full bodies → INVEST + vertical-slicing gate tables → dep graph → batch summary).
>
> **Creator-trace placeholders**: each card body below shows a
> `<!-- board-superpowers:creator-trace -->` block with `<platform>` and `<session-id>` placeholder
> values. These placeholders are **NOT hand-filled in synthesis output** — the intake caller (Step 8
> item 3 in `SKILL.md`) prepends the real values via `bsp_render_creator_trace_block` in
> `scripts/lib/common.sh` at `gh issue create` time. See
> `skills/board-canon/references/card-body-schema.md` § "Creator-trace marker".

## Input (fictional design artifact)

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

## Identified capabilities

Read the input artifact and identify distinct user-visible capabilities:

1. Happy-path sign-in via Google OAuth (the most common path; ships first).
2. Happy-path sign-in via GitHub OAuth (alternative path; ships second per SPIDR-Paths).
3. Sign-out flow uniformly across all auth paths (independent capability).
4. Profile surface populated from OAuth provider data (extends sign-in slices).
5. OAuth callback error handling + rate limiting (defensive cross-cutting; SPIDR-Rules deferral candidate).
6. Account linking (existing email-password user links OAuth identity).

## SPIDR axis selection

- **Paths** primary: Google vs GitHub provider — two independent slices that ship value separately. Account linking is a third path-like capability that touches the existing email-password flow.
- **Rules** secondary: rate-limit + advanced error handling split into a follow-up card (not blocking happy path).
- No Spike needed (OAuth is well-understood); no Interfaces split (single dashboard surface); no Data restriction (provider list is the explicit Paths split).

## Decomposed output (5 cards)

### Card 1 — Google OAuth happy-path sign-in

```markdown
<!-- board-superpowers:creator-trace -->
**Created-by:** <platform>
**Session-id:** <session-id>
<!-- /board-superpowers:creator-trace -->
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
Driver: top-priority intake — sign-in friction blocks trial conversion. SPIDR Paths split: Google ships first as the highest-volume provider.

<!-- board-superpowers:audit-trail -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:audit-trail -->
```

### Card 2 — GitHub OAuth happy-path sign-in

```markdown
<!-- board-superpowers:creator-trace -->
**Created-by:** <platform>
**Session-id:** <session-id>
<!-- /board-superpowers:creator-trace -->
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

<!-- board-superpowers:audit-trail -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:audit-trail -->
```

### Card 3 — Sign-out

```markdown
<!-- board-superpowers:creator-trace -->
**Created-by:** <platform>
**Session-id:** <session-id>
<!-- /board-superpowers:creator-trace -->
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

<!-- board-superpowers:audit-trail -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:audit-trail -->
```

### Card 4 — Error flows + rate limiting

```markdown
<!-- board-superpowers:creator-trace -->
**Created-by:** <platform>
**Session-id:** <session-id>
<!-- /board-superpowers:creator-trace -->
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

<!-- board-superpowers:audit-trail -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:audit-trail -->
```

### Card 5 — Account linking for email-password users

```markdown
<!-- board-superpowers:creator-trace -->
**Created-by:** <platform>
**Session-id:** <session-id>
<!-- /board-superpowers:creator-trace -->
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

<!-- board-superpowers:audit-trail -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:audit-trail -->
```

## INVEST gate per card

| Card | I | N | V | E | S | T |
|---|---|---|---|---|---|---|
| 1 (Google sign-in) | ✅ no hidden coupling | ✅ outcome-shape body | ✅ users gain a sign-in path | ✅ M-sized | ✅ within L ceiling | ✅ AC scriptable |
| 2 (GitHub sign-in) | ✅ soft-deps Card 1 | ✅ outcome-shape | ✅ users gain a 2nd sign-in path | ✅ S-sized | ✅ within ceiling | ✅ AC scriptable |
| 3 (Sign-out) | ✅ hard-deps Card 1 | ✅ outcome-shape | ✅ users gain control over session | ✅ XS-sized | ✅ small | ✅ AC scriptable |
| 4 (Error + rate-limit) | ✅ hard-deps Cards 1+2 | ✅ outcome-shape | ✅ defense + UX clarity | ✅ S-sized | ✅ within ceiling | ✅ AC scriptable |
| 5 (Account linking) | ✅ hard-deps Cards 1+2 | ✅ outcome-shape | ✅ users gain identity merge | ✅ M-sized | ✅ within ceiling | ✅ AC scriptable |

All 5 cards pass INVEST 6-letter gate.

## Vertical-slicing gate per card

| Card | Layer-only? | Trailing wire-up? | Solo-PO? | Excessive spike? |
|---|---|---|---|---|
| 1 | ❌ (full UI + backend + DB) | ❌ | ❌ | ❌ |
| 2 | ❌ (full slice, reuses Card 1 abstractions) | ❌ | ❌ | ❌ |
| 3 | ❌ (full slice — UI button + backend revoke) | ❌ | ❌ | ❌ |
| 4 | ❌ (full slice — error UI + backend rate-limit) | ❌ | ❌ | ❌ |
| 5 | ❌ (full slice — profile UI + backend identity-bind) | ❌ | ❌ | ❌ |

All 5 cards pass vertical-slicing gate.

## Cross-card dep graph

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

## Batch summary

- 5 cards total.
- Size distribution: 1 XS + 2 S + 2 M.
- Total LOC estimate: ~700-1100 (sum of mid-points: 25 + 100 + 100 + 300 + 300 + 300 ≈ 1125, but cards 2-5 reuse Card 1 abstractions so realistic delta is ~700-900).
- Recommended ordering: Card 1 first (unblocks all others), then Card 2 (in parallel with 3, since 3 only hard-deps on 1), Cards 4 and 5 last (both hard-dep on Cards 1+2).
- All cards pass INVEST + vertical-slicing gates; ready for Step 8 batch propose → ack → batch create.
