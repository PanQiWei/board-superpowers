# Decomposition Patterns

Recipes for common capability shapes. Each section shows the *wrong*
decomposition (usually a layer-split trap) and the *right* vertical
slicing.

Use this file as a lookup, not a textbook. When decomposing, skim to
find the pattern that matches the design, then apply.

## Contents

- Pattern 1 — New user-facing feature end-to-end
- Pattern 2 — Data model migration
- Pattern 3 — Adding a new surface (page, CLI command)
- Pattern 4 — Extracting a shared library / refactor (strangler fig)
- Pattern 5 — Bug fix with a regression test
- Pattern 6 — Dependency upgrade
- Pattern 7 — Feature flag rollout
- Pattern 8 — CRUD surface
- Pattern 9 — Async / background job
- When nothing fits — first-principles fallback

## Pattern 1 — New user-facing feature end-to-end

Example: "Add OAuth login."

### Wrong (layer split)

1. Migrate schema: add providers table.
2. Write backend OAuth endpoints.
3. Write frontend sign-in button.
4. Wire frontend to backend.

Each of 1–3 ships nothing the architect can verify. Card 4 is a
big-bang merge.

### Right (vertical slices by user flow)

1. **Happy-path sign-in.** Thinnest possible working sign-in: one
   provider, no error handling, skeleton dashboard. Schema change is
   included but only the columns needed.
2. **Profile surfaces.** Shows that sign-in actually worked — avatar,
   name, etc. Extends schema as needed.
3. **Sign-out.** Button, server-side revocation, redirect.
4. **Error flows.** Denied consent, network failure, token refresh
   edge cases.
5. **Second provider.** If needed.

Architect can verify after each card.

## Pattern 2 — Data model migration

Example: "Move orders from a single `orders` table to `orders` +
`order_items`."

### Wrong

1. Create `order_items` table.
2. Backfill data.
3. Migrate read paths.
4. Migrate write paths.
5. Drop old columns.

Cards 1–2 ship dead infrastructure. Card 5 is the scary one nobody
wants to review.

### Right (shadow-write pattern)

1. **Shadow table + dual-write.** New table exists; every write to
   `orders` also writes to `order_items`. Reads still use old table.
   One card. Verifiable: new writes land in both places.
2. **Backfill + consistency check.** One-time script + ongoing diff
   test. Verifiable: diff reports zero after a time window.
3. **Dual-read with new path preferred.** Reads go through both,
   compare, log divergence. Old table still authoritative. Verifiable:
   divergence log stays empty.
4. **Flip preference to new path.** Old table read only as fallback.
5. **Drop old columns.** Small, risky, isolated card.

## Pattern 3 — Adding a new surface (new page, new CLI command)

Example: "Add `claude stats` subcommand."

### Wrong

1. Add command parser.
2. Add data gatherer.
3. Add formatter.

Again: nothing ships until all three land.

### Right

1. **Stub command with fake data.** `claude stats` runs, prints a
   hardcoded table. Demonstrates routing works. Size: XS.
2. **Real data, one metric.** One number, real. Formatter is
   minimal.
3. **Remaining metrics, one per card** if they have different data
   sources, or one card if they're trivially similar.
4. **Polish pass** — colors, alignment, etc.

## Pattern 4 — Extracting a shared library / refactor

Example: "Extract session handling into `packages/session` from the
monorepo."

### Wrong

1. Create package.
2. Move files.
3. Update all imports.

Card 3 is the whole job in disguise, and touches every file in the repo.

### Right (strangler fig)

1. **Create the new package and put ONE function in it.** Pick the
   easiest, least-dependencies function. Update its call sites. Verify
   tests pass.
2. **Move the next two functions.** Same pattern.
3. **...** Repeat per function group until empty.
4. **Delete the old location.**

Each card is small, reversible, and ships value (new package grows, old
shrinks).

## Pattern 5 — Bug fix with a regression test

Example: "Fix: `divide_by` crashes on zero denominator."

### Wrong (one card)

"Fix the zero-denom bug."

Technically this is one card. But it loses the test. A well-managed bug
fix is almost always two artifacts.

### Right (still one card, but with the structure enforced)

One card. Acceptance criteria:

- [ ] Adding `divide_by(x, 0)` test case fails on current `main`.
- [ ] After the fix, `divide_by(x, 0)` raises `ZeroDivisionError`
      (or returns NaN — architect specifies).
- [ ] All prior `divide_by` tests still pass.

The acceptance criteria force the failing test to be written first and
the fix to target it. This is TDD encoded in AC form — don't let the
Consumer shortcut it.

Size: XS. Label: `type:bug`.

## Pattern 6 — Dependency upgrade

Example: "Upgrade React from 17 to 18."

### Wrong

"Upgrade React."

Single card, scope unbounded, likely to break everything.

### Right

1. **Audit.** A single card that reads the changelog, runs the
   compat checker, and outputs a list of breaking changes the codebase
   hits. Acceptance: `docs/upgrades/react-18-audit.md` exists and is
   reviewed. Size: S.
2. **One card per breaking change.** Each small, independently
   revertible.
3. **Final bump.** Change `package.json`, update lockfile, run full
   test suite. Size: XS (by the time you get here, all the hard work is
   done).

## Pattern 7 — Feature flag rollout

Example: "Add new checkout flow behind a flag, eventually replace old."

### Right

1. **Flag infrastructure.** Only if the project doesn't already have
   flags. Skip if it does.
2. **New flow behind flag, OFF.** Full new code path, covered by tests,
   off by default. Architect can enable locally to verify.
3. **Canary enable.** Flag on for X% of traffic, monitoring card.
4. **Full enable.**
5. **Remove old path.** Delete the old code once the flag has been on
   at 100% for a window. Happens as its own card, not as part of #4.

## Pattern 8 — CRUD surface

Example: "Admin UI for managing coupons."

### Wrong (split by operation)

1. List coupons page.
2. Create coupon page.
3. Edit coupon page.
4. Delete coupon action.

Four cards that each ship something. Not terrible. But they probably
share 60%+ of code; sequencing them as four separate PRs means heavy
rebasing and duplicate work.

### Better

1. **Read (list + detail).** Read-only UI. Useful on its own — the
   admin can now see coupons, which they couldn't before.
2. **Create.** Adds the create path.
3. **Edit + delete.** Usually symmetric in UI; tends to be one card.

Three cards. Each vertical, each ships user value.

## Pattern 9 — Async / background job

Example: "Send welcome email after signup."

### Right

1. **Enqueue on signup (worker is a no-op).** Hook into signup,
   enqueue a job. The worker logs but doesn't send. Architect verifies
   the enqueue happens.
2. **Real send.** Worker actually sends. Uses whatever email
   infrastructure exists or is picked up in a dep card.
3. **Retry / dead-letter.** Error handling.

## When nothing fits

If the capability is so novel nothing matches, fall back to first
principles:

1. What is the SINGLE thinnest slice a user could use after card 1?
   That's card 1.
2. What slice ADDS something usable after card 2? That's card 2.
3. Continue until the design is covered.
4. Pull out error paths and edge cases into their own trailing cards
   — they're usually the tail.

The mistake to avoid is "let me first get the foundation right".
Vertical slicing is a bet that you'd rather ship value five times at
middling quality than once at perfect. Agile accepts that bet.
