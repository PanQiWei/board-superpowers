# Card Schema Reference

The exact template `decomposing-into-milestones` writes for every card.
Consumer sessions read this contract via the `board-protocol` skill —
if the schema isn't followed, the Consumer can't reliably extract the
information it needs.

## Contents

- The template
- Section-by-section guidance (Context · Acceptance Criteria · Out of Scope · Size · Execution Hints · marker comment)
- Complete example (OAuth sign-in happy path)

## The template

```markdown
## Context

<1–3 paragraphs. Background. Files involved. Related cards (by #N).
Dependencies on other cards (by #N). Anything a Consumer session with NO
memory of the planning conversation needs to start.>

## Acceptance Criteria

- [ ] <criterion 1>
- [ ] <criterion 2>

## Out of Scope

- <rejected scope 1>
- <rejected scope 2>

## Size

XS | S | M | L

## Execution Hints

<optional>

<!-- board-superpowers:card -->
```

## Section-by-section guidance

### Context

Two to four sentences. Primary purpose: orient the Consumer fast.
Secondary: record the link to the design doc.

Include:

- **Link to the design doc** (as a repo-relative path, not a URL — URLs
  go stale when branches change).
- **Primary files involved** — 2–4, not a full manifest. Things like
  "likely edits: `src/auth/session.ts`, `src/api/auth/callback.ts`. Read
  but don't edit: `src/middleware/auth.ts`."
- **Dependencies on other cards** — `Depends on #42, #43`. A Consumer
  MUST refuse to claim a card whose deps aren't in Done yet.
- **What the card is NOT doing** — one line. (Fuller treatment in Out
  of Scope.)

Avoid:

- ❌ Repeating the design doc's content. Link; don't duplicate.
- ❌ Commentary on why the card exists. That's in the design doc.
- ❌ "This should be straightforward" — never helpful, often wrong.

### Acceptance Criteria

Every criterion MUST be a **statement of a true thing in the finished
world**, testable by an automated check. Not a task. Not a step. A
post-condition.

Good:

- [ ] `POST /auth/callback` returns 302 to `/dashboard` when the code is
      valid.
- [ ] A new row is present in `sessions` table after successful callback.
- [ ] `pnpm test` passes with 100% coverage of `src/auth/callback.ts`.

Bad:

- [ ] ❌ Implement the callback handler. *(task, not post-condition)*
- [ ] ❌ Make sure it works. *(not testable)*
- [ ] ❌ Add tests for the flow. *(implicit — tests are part of every
      card by default; don't restate)*
- [ ] ❌ Handle edge cases. *(under-specified)*

Rule of thumb: a non-author engineer should be able to read the
criteria, implement blindly, and have the result be what the architect
wanted.

### Out of Scope

Bulleted list. Purpose: inoculate against scope creep.

Populate from these sources:

- Things that the Consumer, mid-implementation, will be tempted to
  "while I'm in here" fix. Pre-emptively list them.
- Things from the design doc that belong to a different card in the set.
  Name those cards by number when possible.
- Error paths or edge cases deliberately deferred to a follow-up card.

Example:

```
## Out of Scope

- Handling Google's "consent denied" response — covered by card #45.
- Changing the existing password-login UI. That stays untouched.
- Migrating any existing users — this card is sign-in only, not sign-up.
```

### Size

Single label: **XS**, **S**, **M**, or **L**. No other values.

Written assumption ranges:

| Label | Expected diff | Files |
|-------|---------------|-------|
| XS | < 50 LOC | 1–2 |
| S | 50–200 LOC | 2–5 |
| M | 200–400 LOC | 5–10 |
| L | 400–500 LOC | up to 10 |

If you're tempted to write XL, the card is wrong — split it.

### Execution Hints (optional)

This is the one place where the Manager gives advice to the Consumer.
Keep it terse; the Consumer has its own judgment via superpowers/gstack.

Useful hints:

- Name the superpowers or gstack skill you think fits best:
  "Recommended execution path: `superpowers:subagent-driven-development`."
- Flag a known gotcha:
  "Note: `src/auth/middleware.ts` has a circular import with
  `src/session/` — do not import from there; use the re-export in
  `src/auth/index.ts` instead."
- Pre-empt a wrong turn:
  "Don't add a new database — use the existing `sessions` table with
  a new `provider` column."

Do NOT put Acceptance Criteria here. Do NOT put Out of Scope here. Do
NOT put implementation steps here — the Consumer, or the skill it
invokes, decides steps.

### The marker comment

The HTML comment `<!-- board-superpowers:card -->` at the very end of
the card body is the machine-readable marker. It's how `managing-board`
and other tools identify board-superpowers-managed cards vs. plain
issues on the project. Never remove it.

## Complete example

Title: `Sign in with Google — happy path`

Labels: `type:feature`, `size:S`

Body:

```markdown
## Context

See `docs/superpowers/specs/2026-04-22-oauth-design.md` (sections 1–3).

This is slice 1 of the OAuth capability — happy-path sign-in only.
Denied-consent and error flows are cards #46 and #47. Sign-out is #48.

Likely edits: `src/auth/google.ts` (new), `src/api/routes.ts`,
`src/pages/login.tsx`. Read-only reference: `src/session/index.ts`.

Depends on #44 (adds the `provider` column to `sessions` table).

## Acceptance Criteria

- [ ] `GET /auth/google` redirects to Google's OAuth consent screen with
      the correct client_id and scopes (`openid`, `email`, `profile`).
- [ ] `GET /auth/google/callback?code=...` exchanges the code for an ID
      token, creates a row in `sessions` with `provider='google'`, sets
      an HTTP-only cookie, and redirects to `/dashboard`.
- [ ] Hitting `/dashboard` with the cookie returns the logged-in shell
      (no profile data yet — that's card #49).
- [ ] `pnpm test src/auth/google.test.ts` passes with at least happy-path
      coverage; `pnpm test` as a whole stays green.

## Out of Scope

- Consent denied / error flows — card #46.
- Profile data / avatar — card #49.
- Sign-out — card #48.
- Token refresh — deferred, no card yet.

## Size

S

## Execution Hints

Recommended path: `superpowers:subagent-driven-development`.

Gotcha: our existing email-password flow in `src/auth/password.ts`
already creates session rows with `provider='password'`. Mirror that
pattern; don't build a parallel one.

<!-- board-superpowers:card -->
```
