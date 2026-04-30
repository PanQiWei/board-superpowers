# board-canon — branch naming reference

Edge-case decision table that the parent `SKILL.md` § "Branch naming" points at.

## Generating a claim branch name — procedure

Run these steps to produce a canonical claim branch name from a card:

1. **Read the active kanban id** from `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`. For repos with one active kanban, this is typically `primary`.
2. **Encode the card key** into the branch-path form: lowercase `Card.key`, then replace `-` with `_` (so a Linear-shaped `ENG-42` becomes `eng_42`; a GitHub-Project-shaped `42` stays `42`). The canonical key as displayed on the board keeps its hyphen form; only the branch-path encoding rewrites it.
3. **Slugify the title**: lowercase, replace runs of non-alphanumeric with `-`, trim leading/trailing hyphens, then truncate at the last hyphen boundary inside the 64-char ceiling (40 chars is the deterministic truncation target documented in older drafts).
4. **Compose** as `claim/<kanban-id>-<key-slug>-<title-slug>`. The slugifier (`bsp_slugify` in `scripts/lib/common.sh`) is the implementation; it enforces the per-segment caps in step 5.
5. **Validate length budgets** (caller MUST enforce):
   - `<kanban-id>`: ≤ 32 chars (lowercase, alphanumeric, `_` only — NO hyphens).
   - `<key-slug>`: ≤ 64 chars (after underscore-encoding).
   - `<title-slug>`: ≤ 64 chars at the last hyphen boundary.
   - Total branch path under `claim/`: ≤ 200 chars.

The single-kanban carve-out simplifies step 1 (kanban-id is whatever the repo registered as its sole entry) and step 5's invariants (no cross-kanban prefix collision possible).

## Slug edge cases (title-slug)

The examples below all use kanban-id `primary` and `Card.key = 42` for concreteness; the same rules apply for any `(kanban-id, key)` pair.

| Title | Title-slug | Branch (kanban-id `primary`, key `42`) |
|-------|------------|-----------------------------------------|
| Empty title | `card-42` | `claim/primary-42-card-42` |
| All special chars: `!@#$%` | `card-42` | `claim/primary-42-card-42` |
| Mixed Chinese + English: `修复 WIP counter bug` | `wip-counter-bug` (Chinese stripped by `tr`) | `claim/primary-42-wip-counter-bug` |
| > 100 chars | First 40 chars then truncate at last hyphen | (varies; deterministic) |
| Leading / trailing hyphens after slug | Trimmed | (clean) |
| Title contains `claim/` | `claim/` stripped | `claim/primary-42-...` (no nested) |

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
3. Audit-log both actions explicitly (Reserved-class — must ask architect)

Better outcome: split the card into two and finish the original under its original name.

## Background — parser contract

This block is reference material consulted when implementing or maintaining the slugifier and reverse-parser. Day-to-day branch generation does NOT need to read it.

### Slugify rules

The branch-path encoding `claim/<kanban-id>-<key-slug>-<title-slug>` requires unambiguous segment boundaries. Since `-` is also the segment delimiter, hyphens inside the slug-able strings would collide with the delimiter. Slugify rules:

- **kanban-id**: lowercase alphanumeric + `_` only (NO hyphens). Hyphens in the configured kanban-id are not permitted; this is enforced at registration time per the disambiguation invariants below.
- **key-slug**: lowercase the canonical `Card.key`, then replace `-` with `_`. The canonical key as displayed on the board (e.g., `ENG-42`, `PROJ-123`) keeps its hyphen form; only the branch-path encoding rewrites it. Example: `Card.key = ENG-42` → branch segment `eng_42`.
- **title-slug**: lowercase, replace runs of non-alphanumeric with `-`, trim to length budget at the last hyphen boundary.

Reverse parse from a branch name to `(kanban-id, Card.key, title-fragment)`: split on `-`; the first prefix matching a registered kanban-id consumes that span; the next span up to the title-slug boundary is the underscore-encoded key-slug — apply `_` → `-` to recover the canonical key.

The slugifier (`bsp_slugify` in `scripts/lib/common.sh`) is the implementation; banned characters across all three segments (replaced with hyphens, runs collapsed): spaces, `/`, `:`, `?`, `[`, `]`, `^`, `~`, `\`, `*`, control characters. Leading and trailing hyphens are trimmed.

### Disambiguation invariants

A registered kanban-id MUST NOT be a prefix of any other registered kanban-id. Without this rule, a branch like `claim/foo-42-bar` cannot be decomposed cleanly when both `foo` and `foo_42` are registered as kanban-ids. Multi-kanban registration validates this invariant in `bootstrapping-repo` at the point of adding a new kanban entry to `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`. Single-kanban repos satisfy the invariant trivially.

The parser otherwise depends on the kanban-id allowlist from `settings.yml` to disambiguate: because `-` is permitted inside `<title-slug>` (and `_` is the encoded form of hyphens inside `<key-slug>`), the parser scans the kanban-id segment using the allowlist (longest-match) before delegating the remainder to the key-slug + title-slug split.

### Length budgets — rationale

Per-segment caps keep branch refnames inside git's 255-char ref limit AND under typical filesystem path budgets (most filesystems target ≤ 255 chars per path component, and worktrees nest the branch under `<base>/<repo>/<branch>`). The 40-char title-slug truncation target keeps `git branch` listings legible; the 64-char ceiling is the hard upper bound for unusual cases where the 40-char truncation would land mid-word.

### Legacy two-segment form — parser-accepted, never emitted

Some repos carry claim branches authored under earlier plugin versions in a two-segment form:

```
legacy:  claim/<N>-<slug>
         where:
         - <N> is the GitHub issue number (no `#` prefix)
         - <slug> is the card title slugified to lowercase
           alphanumeric + hyphens, max 40 characters
         e.g., claim/42-fix-bug
```

Implications of the legacy form:

- The kanban-id segment is absent — legacy branches do not encode which kanban they belong to. Repos that authored these branches were single-kanban by construction. The plugin registers each legacy branch against its owning kanban via `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.legacy_claims`; the parser uses that registry to resolve a legacy branch back to its `(kanban-id, Card.key)` composite identity.
- The `<N>` token IS the GitHub issue number — implicitly GitHub-Project-shaped. Under the canonical three-segment form, the same `42` is now the `<key-slug>` of `Card.key = 42`, which slugifies to `42` (so the visible characters are unchanged for GitHub-Project repos; the meaning is the abstraction).

Operational rules:

- Legacy branches that already exist on origin remain valid and are NOT physically renamed.
- New claims MUST use the canonical three-segment form, even on a repo where all prior claims used the legacy form.
- The parser distinguishes the two forms by segment count after `claim/` (two segments → legacy; three segments → canonical) plus a kanban-id allowlist read from `settings.yml`.
