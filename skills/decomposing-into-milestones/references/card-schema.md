# Card body schema — terminal contract

> **Authority**: This file is a thin wrapper over `board-superpowers:board-canon` § "Card body schema". The terminal schema (post-double-collapse) lives in `skills/board-canon/references/card-body-schema.md`. Do NOT duplicate the schema definition here — refer to the canonical source.

## What this skill produces

Every card emitted by `decomposing-into-milestones` Step 7 (synthesize batch) MUST conform to the terminal Card body schema, which is double-collapsed from the prior `board-canon` v0.3.0 schema and spec § 1.6.3 schema (per `#35`'s schema-drift-double-collapse acceptance criterion).

## Terminal schema — at a glance

```markdown
<!-- board-superpowers:creator-trace -->
**Created-by:** <platform>
**Session-id:** <session-id>
<!-- /board-superpowers:creator-trace -->
<!-- thin-pointer -->
**Spec**: <repo-relative-path-with-anchor>
**Owner**: @<github-handle>
**Estimate**: XS | S | M | L
<!-- /thin-pointer -->

## Goal
<one-sentence outcome statement — the user-visible state-change that lands when this card's PR merges>

## Acceptance criteria
- [ ] <post-condition statement, automatable by check OR by an explicit human observation>
- [ ] <...>

## Out of scope
- <thing a Consumer might be tempted to fix mid-implementation; explicit refusal>
- <...>

## Dependencies
- depends-on: #<N>          # hard — this card cannot start until #N is Done
- depends-on (soft): #<M>   # soft — prefer #M done first but can land in either order
- depended-on-by: #<K>      # reverse — informational; #K declares the hard dep

## Execution Hints
(optional — Producer-to-Consumer signals: recommended execution skill, known gotcha, type tag for conditional gate routing like `## Execution Hints: ui` for /qa or `: security` for /cso)

## Notes
<freeform rationale, driver, cross-card context, retro-folded lessons>

<!-- board-superpowers:audit-trail -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:audit-trail -->
```

> **Creator-trace block note**: the `<!-- board-superpowers:creator-trace -->` block shown at the
> top of the template uses `<platform>` and `<session-id>` as placeholders. In practice these
> values are **auto-filled by `bsp_render_creator_trace_block`** in `scripts/lib/common.sh` at
> `gh issue create` time — the Step 7 synthesis output should include the literal placeholder
> text; the intake caller (Step 8 item 3) prepends the rendered block before creating the issue.
> Do NOT hand-fill these fields in the synthesis output.

## Per-section authoring rules

### Thin-pointer block (required)

- `**Spec**:` — repo-relative path (NOT a URL — URLs go stale across branches). Multiple paths allowed (one per line) for cards that draw from multiple spec sources.
- `**Owner**:` — single GitHub handle (`@<handle>`). The Consumer who claims is responsible; ownership is informational.
- `**Estimate**:` — exactly one of `XS | S | M | L` per `references/size-calibration.md`. No XL, no story points, no fractional values.

### `## Goal` (required)

One-sentence statement of the user-visible / developer-visible outcome that lands when the card's PR merges. **Not** a procedural description ("implement OAuth callback handler"). **Not** a feeling ("improve sign-in UX"). A concrete observable change.

Examples:
- ✅ "Users can sign in with their Google account from the dashboard sign-in page."
- ❌ "Implement OAuth integration." (procedural)
- ❌ "Make sign-in better." (feeling)

### `## Acceptance criteria` (required)

Checkbox bullets. Each bullet is a **post-condition statement** of a true thing in the finished world, automatable by a script OR by an explicit human observation. Tasks ("implement X"), feelings ("works well"), and implicit items ("add tests") are forbidden.

Examples:
- ✅ "[ ] Clicking 'Sign in with Google' on the dashboard sign-in page redirects to Google's OAuth consent screen."
- ✅ "[ ] After Google consent, the user lands back on the dashboard with a session cookie set; `bash test/auth/oauth-callback.sh` exits 0."
- ❌ "[ ] Implement Google OAuth flow." (task)
- ❌ "[ ] Sign-in works." (untestable)

### `## Out of scope` (required, may be empty)

Bulleted list of things a Consumer might be tempted to fix mid-implementation. Inoculates against scope creep. If genuinely empty, write `- (none — all scope captured in Acceptance criteria)`.

### `## Dependencies` (required, may declare empty arms)

Three field types:

- `- depends-on: #N` — hard dependency. Card cannot enter Ready until #N is Done.
- `- depends-on (soft): #M` — soft dependency. Card prefers #M done first but can land in either order.
- `- depended-on-by: #K` — reverse dependency. Informational mirror of #K's hard `depends-on` on this card.

Empty form: `- (none — terminal card / first card in chain)`.

### `## Execution Hints` (optional)

Producer-to-Consumer signals. Used sparingly. Common shapes:

- `## Execution Hints: ui` — triggers Consumer's conditional QA gate (the `/qa` browser-QA pass during PR pre-flight).
- `## Execution Hints: security` — triggers Consumer's conditional security gate (the `/cso` audit pass during PR pre-flight).
- `## Execution Hints: recommended-skill: superpowers:test-driven-development` — pin a particular implementation discipline.
- Free-form gotcha note: `## Execution Hints: known-gotcha: gh CLI's --field flag has a colon-parsing bug — use --raw-field for values containing colons`.

If empty, omit the section entirely. Producer-side validation: AC and scope items are FORBIDDEN here (they belong in their own sections).

### `## Notes` (required)

Freeform rationale, driver, cross-card context. Examples:

- "Driver: user feedback in P0 intake — sign-in friction is blocking trial conversion."
- "Cross-card context: this card unblocks #45 (mobile sign-in) and #46 (account linking)."
- "Retro-folded: an earlier attempt assumed Google's OAuth scope `openid email profile` was sufficient; turned out we also need `https://www.googleapis.com/auth/userinfo.email` for the email field on the callback. Documented for future cards."

If genuinely empty, write `- (none — driver fully captured in Goal)`.

### Bottom marker (required)

Exactly:

```
<!-- board-superpowers:audit-trail -->
**Audit trail**: query ~/.board-superpowers/repos/<normalized>/audit-local.jsonl by `card_number = N`.
<!-- /board-superpowers:audit-trail -->
```

The marker is **protocol, not decoration**. Tooling (`managing-board`'s Review Queue routine, the daily briefing's filter logic) keys off the marker. The legacy `<!-- bsp-bottom-marker:do-not-edit -->` and `<!-- board-superpowers:card -->` forms are forbidden in new cards — every card body landed by this skill uses the idiomatic `audit-trail` marker.

## Filler detection

The following content patterns are forbidden in any section. Step 7 synthesis output is rejected if any appear:

- `TBD` / `tbd` / `TODO: write later` — unestimable; refuse per INVEST-E.
- `(none)` / `n/a` / `N/A` (when used as the entire section content for required sections) — write the explicit "no items" form instead (e.g., `- (none — terminal card)`).
- `tests pass` (without naming WHICH tests) — untestable per INVEST-T.
- `feels good` / `works well` / `is reasonable` / `looks correct` — untestable; refuse per INVEST-T.
- `figure out` / `we'll see` / `depends on what we find` — unestimable per INVEST-E.

The Producer-side validation in `enforcing-pr-contract` Contract B catches these at PR-submit time. The Step 7 self-check catches them at synthesis time, before the cards even reach the board.

## Cross-reference

For the **canonical schema definition** (the contract that `submit-pr.sh` and `managing-board` Review Queue both validate against), see:

- `skills/board-canon/SKILL.md` § "Card body schema"
- `skills/board-canon/references/card-body-schema.md`

This file documents how `decomposing-into-milestones` produces cards conforming to that schema. The schema definition itself lives in `board-canon` (single source of truth — atomic SKILL).
