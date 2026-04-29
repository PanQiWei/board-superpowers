# board-canon — branch naming reference

Edge-case decision table that the parent `SKILL.md` § "Branch naming" points at.

## Canonical form (v0.5.0+)

```
claim/<kanban-id>-<key-slug>-<title-slug>
```

Three segments, joined by hyphens after the `claim/` prefix:

- `<kanban-id>` — local id of the active kanban this card belongs to (read from `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`). For repos with one active kanban, the id is typically `primary`.
- `<key-slug>` — `slugify(Card.key)`. `Card.key` is the backend's display-stable opaque card identifier (GitHub Project v2: an issue number like `42`; Linear: `eng-42`; Jira: `proj-42`).
- `<title-slug>` — `slugify(Card.title)` truncated to ≤40 characters at the last hyphen.

## Slugifier rules

The slugifier (`bsp_slugify` in `scripts/lib/common.sh`) applies to both `<key-slug>` and `<title-slug>`:

- Lowercase, alphanumeric + hyphens only.
- Banned characters (replaced with hyphens, runs collapsed): spaces, `/`, `:`, `?`, `[`, `]`, `^`, `~`, `\`, `*`, control characters.
- Leading and trailing hyphens trimmed.
- Title slug truncated at 40 characters at the last hyphen boundary (deterministic).

## Disambiguation invariants

**Disambiguation invariant**: A registered kanban-id MUST NOT be a prefix of any other registered kanban-id. This is required for the branch parser to unambiguously split `claim/<kanban-id>-<key-slug>-<title-slug>` — without this rule, a branch like `claim/foo-42-bar` cannot be decomposed cleanly when both `foo` and `foo-42` are registered as kanban-ids. `bootstrapping-repo` enforces this when adding a new kanban entry to `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`.

The parser otherwise depends on the kanban-id allowlist from `settings.yml` to disambiguate: because `-` is permitted inside both `<key-slug>` and `<title-slug>`, the parser scans the kanban-id segment using the allowlist (longest-match) before delegating the remainder to the key-slug + title-slug split.

## Length budgets

Per-segment caps keep branch refnames inside git's 255-char ref limit AND under typical filesystem path budgets (most filesystems target ≤ 255 chars per path component, and worktrees nest the branch under `<base>/<repo>/<branch>`):

- `<kanban-id>`: ≤ 32 chars (lowercase, hyphens, alphanumeric only).
- `<key-slug>`: ≤ 64 chars.
- `<title-slug>`: ≤ 64 chars (the existing 40-char target is the deterministic truncation point; the 64-char ceiling is a hard upper bound for unusual cases).
- Total branch path under `claim/`: ≤ 200 chars (well under git's 255-char refname max + most filesystems' path component limits).

Slugifier callers MUST enforce these budgets at slug-generation time. `bootstrapping-repo` validates the kanban-id segment when registering a new kanban entry; the slugifier (`bsp_slugify`) enforces key-slug and title-slug caps.

## Slug edge cases (title-slug)

| Title | Title-slug | Branch (kanban-id `primary`, key `N`) |
|-------|------------|----------------------------------------|
| Empty title | `card-N` | `claim/primary-N-card-N` |
| All special chars: `!@#$%` | `card-N` | `claim/primary-N-card-N` |
| Mixed Chinese + English: `修复 WIP counter bug` | `wip-counter-bug` (Chinese stripped by `tr`) | `claim/primary-N-wip-counter-bug` |
| > 100 chars | First 40 chars then truncate at last hyphen | (varies; deterministic) |
| Leading / trailing hyphens after slug | Trimmed | (clean) |
| Title contains `claim/` | `claim/` stripped | `claim/primary-N-...` (no nested) |

## Why title-slug truncation at 40 chars

GitHub branch names work up to 250 chars but get awkward in `git branch` listings beyond ~50. The 40-char cap on title-slug, plus the `claim/` prefix, kanban-id, key-slug, and joining hyphens, leaves room for additions if needed.

## Examples by backend

| Active kanban | `Card.key` | `<key-slug>` | Card title | Branch |
|---------------|-----------|--------------|------------|--------|
| `primary` (GitHub Project v2) | `12` | `12` | `Implement board-canon SKILL.md` | `claim/primary-12-implement-board-canon-skill-md` |
| `primary` (GitHub Project v2) | `47` | `47` | `Fix issue with WIP counter (race)` | `claim/primary-47-fix-issue-with-wip-counter-race` |
| `eng` (future Linear projection) | `ENG-42` | `eng-42` | `Refactor token cache` | `claim/eng-eng-42-refactor-token-cache` |
| `legal` (future Jira projection) | `COMP-7` | `comp-7` | `Audit log retention review` | `claim/legal-comp-7-audit-log-retention-review` |

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
