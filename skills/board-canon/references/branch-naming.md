# board-canon — branch naming reference

Edge-case decision table that the parent `SKILL.md` § "Branch naming" points at.

## Canonical form (v0.5.0+)

```
claim/<kanban-id>-<key-slug>-<title-slug>
```

Three segments, joined by hyphens after the `claim/` prefix:

- `<kanban-id>` — local id of the active kanban this card belongs to (read from `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`). For repos with one active kanban, the id is typically `primary`.
- `<key-slug>` — branch-path encoding of the canonical `Card.key`: lowercase the key, then rewrite `-` to `_` (so a Linear-shaped `ENG-42` becomes `eng_42`; a GitHub-Project-shaped `42` stays `42`). The canonical `Card.key` displayed on the board keeps its hyphen form; only the branch-path encoding rewrites. See "Slugify rules" below.
- `<title-slug>` — `slugify(Card.title)`, truncated to ≤64 characters at the last hyphen boundary (40 chars is the deterministic truncation target documented in older drafts; 64 is the hard ceiling).

## Length budgets

Per-segment caps keep branch refnames inside git's 255-char ref limit AND under typical filesystem path budgets (most filesystems target ≤ 255 chars per path component, and worktrees nest the branch under `<base>/<repo>/<branch>`):

- `<kanban-id>`: ≤ 32 chars (lowercase, alphanumeric, `_` only — NO hyphens; see "Slugify rules" below).
- `<key-slug>`: ≤ 64 chars (after underscore-encoding of canonical `Card.key` hyphens).
- `<title-slug>`: ≤ 64 chars at the last hyphen boundary (the 40-char target documented in older drafts is the deterministic truncation point; the 64-char ceiling is the hard upper bound for unusual cases).
- Total branch path under `claim/`: ≤ 200 chars (well under git's 255-char refname max + most filesystems' path component limits).

Slugifier callers MUST enforce these budgets at slug-generation time. Multi-kanban registration (v0.5.x+) will validate the kanban-id segment in `bootstrapping-repo` at the point of adding a new kanban entry. The v0.5.0 carve-out limits each repo to a single kanban entry, so the kanban-id length and disambiguation invariants are trivially satisfied for v0.5.0 repos. The slugifier (`bsp_slugify`) enforces key-slug and title-slug caps in all cases.

## Slugify rules

The branch-path encoding `claim/<kanban-id>-<key-slug>-<title-slug>` requires unambiguous segment boundaries. Since `-` is also the segment delimiter, hyphens inside the slug-able strings would collide with the delimiter. Slugify rules:

- **kanban-id**: lowercase alphanumeric + `_` only (NO hyphens). Hyphens in the configured kanban-id are not permitted; this is enforced at registration time per the disambiguation invariants below.
- **key-slug**: lowercase the canonical `Card.key`, then replace `-` with `_`. The canonical key as displayed on the board (e.g., `ENG-42`, `PROJ-123`) keeps its hyphen form; only the branch-path encoding rewrites it. Example: `Card.key = ENG-42` → branch segment `eng_42`.
- **title-slug**: lowercase, replace runs of non-alphanumeric with `-`, trim to length budget at the last hyphen boundary.

Reverse parse from a branch name to `(kanban-id, Card.key, title-fragment)`: split on `-`; the first prefix matching a registered kanban-id consumes that span; the next span up to the title-slug boundary is the underscore-encoded key-slug — apply `_` → `-` to recover the canonical key.

The slugifier (`bsp_slugify` in `scripts/lib/common.sh`) is the implementation; banned characters across all three segments (replaced with hyphens, runs collapsed): spaces, `/`, `:`, `?`, `[`, `]`, `^`, `~`, `\`, `*`, control characters. Leading and trailing hyphens are trimmed.

## Disambiguation invariants

**Disambiguation invariant**: A registered kanban-id MUST NOT be a prefix of any other registered kanban-id. This is required for the branch parser to unambiguously split `claim/<kanban-id>-<key-slug>-<title-slug>` — without this rule, a branch like `claim/foo-42-bar` cannot be decomposed cleanly when both `foo` and `foo_42` are registered as kanban-ids. Multi-kanban registration (v0.5.x+) will validate this invariant in `bootstrapping-repo` at the point of adding a new kanban entry to `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`. The v0.5.0 carve-out limits each repo to a single kanban entry, so the invariant is trivially satisfied.

The parser otherwise depends on the kanban-id allowlist from `settings.yml` to disambiguate: because `-` is permitted inside `<title-slug>` (and `_` is the encoded form of hyphens inside `<key-slug>`), the parser scans the kanban-id segment using the allowlist (longest-match) before delegating the remainder to the key-slug + title-slug split.

## Slug edge cases (title-slug)

| Title | Title-slug | Branch (kanban-id `primary`, key `N`) |
|-------|------------|----------------------------------------|
| Empty title | `card-N` | `claim/primary-N-card-N` |
| All special chars: `!@#$%` | `card-N` | `claim/primary-N-card-N` |
| Mixed Chinese + English: `修复 WIP counter bug` | `wip-counter-bug` (Chinese stripped by `tr`) | `claim/primary-N-wip-counter-bug` |
| > 100 chars | First 40 chars then truncate at last hyphen | (varies; deterministic) |
| Leading / trailing hyphens after slug | Trimmed | (clean) |
| Title contains `claim/` | `claim/` stripped | `claim/primary-N-...` (no nested) |

## Why title-slug truncation at 40 chars (typical) / 64 chars (ceiling)

GitHub branch names work up to 250 chars but get awkward in `git branch` listings beyond ~50. The 40-char deterministic-truncation target on title-slug, plus the `claim/` prefix, kanban-id, key-slug, and joining hyphens, leaves room for additions if needed. The 64-char ceiling (per Length budgets above) is the hard upper bound for unusual cases where the 40-char truncation would land mid-word.

## Examples by backend

| Active kanban | `Card.key` | `<key-slug>` | Card title | Branch |
|---------------|-----------|--------------|------------|--------|
| `primary` (GitHub Project v2) | `12` | `12` | `Implement board-canon SKILL.md` | `claim/primary-12-implement-board-canon-skill-md` |
| `primary` (GitHub Project v2) | `47` | `47` | `Fix issue with WIP counter (race)` | `claim/primary-47-fix-issue-with-wip-counter-race` |
| `eng` (future Linear projection) | `ENG-42` | `eng_42` | `Refactor token cache` | `claim/eng-eng_42-refactor-token-cache` |
| `legal` (future Jira projection) | `COMP-7` | `comp_7` | `Audit log retention review` | `claim/legal-comp_7-audit-log-retention-review` |

## Single claim branch per card

The same card uses exactly ONE claim branch across its entire lifetime, including rework. Rework after a "request changes" review pushes new commits to the same branch — does NOT create a `-v2` suffixed variant.

The only exception: if the card is fully released and re-claimed by a different Consumer with a meaningfully different approach, the new claim may use a slightly different title-slug (the card title may have evolved). The card's audit log shows the full history regardless.

## What about non-claim branches?

Sometimes a Consumer needs an interim branch (e.g., to test something experimentally before deciding it belongs in the claim branch). Convention:

- Interim branches go under `wip/<consumer>/<purpose>` (NOT `claim/...`)
- They do NOT signal claim — pushing them does not transition the card
- They are deleted when their experiment ends

## What if the claim branch needs renaming?

If a card's title materially changes mid-implementation (which is itself a smell), the Consumer can:

1. Push the new branch name
2. Delete the old branch on origin
3. Audit-log both actions explicitly (R-class — must ask architect)

Better outcome: split the card into two and finish the original under its original name.

## v0.4.x legacy form — historical callout (parser-accepted, never emitted under v0.5.0+)

> **Read this block as historical context only.** Branches authored before v0.5.0 use the older two-segment form. The claim-branch parser MUST accept both forms during the transition window; the slugifier MUST emit only the canonical three-segment form for any new claim authored under v0.5.0+.

The legacy form was:

```
v0.4.x legacy:  claim/<N>-<slug>
                where:
                - <N> is the GitHub issue number (no `#` prefix)
                - <slug> is the card title slugified to lowercase
                  alphanumeric + hyphens, max 40 characters
                e.g., claim/42-fix-bug
```

Implications of the legacy form:

- The kanban-id segment is absent — legacy branches do not encode which kanban they belong to. Repos that authored these branches were single-kanban by construction (multi-kanban runtime is a v0.5.0+ feature). Migration registers each legacy branch against its owning kanban via `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.legacy_claims`; the parser uses that registry to resolve a legacy branch back to its `(kanban-id, Card.key)` composite identity.
- The `<N>` token IS the GitHub issue number — implicitly GitHub-Project-shaped. Under v0.5.0+ this is generalized: the same `42` is now `<key-slug>` of `Card.key = 42`, which slugifies to `42` (so the visible characters are unchanged for GitHub-Project repos; the meaning is the abstraction).

Operational rules:

- Legacy branches that already exist on origin remain valid and are NOT physically renamed.
- New claims authored under v0.5.0+ MUST use the canonical three-segment form, even on a repo where all prior claims used the legacy form.
- The parser distinguishes the two forms by segment count after `claim/` (two segments → legacy; three segments → canonical) plus a kanban-id allowlist read from `settings.yml`.
