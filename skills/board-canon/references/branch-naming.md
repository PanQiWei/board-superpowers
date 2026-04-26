# board-canon — branch naming reference

Edge-case decision table that the parent `SKILL.md` § "Branch naming" points at.

## Slug edge cases

| Title | Slug | Branch |
|-------|------|--------|
| Empty title | `card-N` | `claim/N-card-N` |
| All special chars: `!@#$%` | `card-N` | `claim/N-card-N` |
| Mixed Chinese + English: `修复 WIP counter bug` | `wip-counter-bug` (Chinese stripped by `tr`) | `claim/47-wip-counter-bug` |
| > 100 chars | First 40 chars then truncate at last hyphen | (varies; deterministic) |
| Leading / trailing hyphens after slug | Trimmed | (clean) |
| Title contains "claim/" | "claim/" stripped | `claim/N-...` (no nested) |

## Why slug truncation at 40 chars

GitHub branch names work up to 250 chars but get awkward in `git branch` listings beyond ~50. The 40-char cap on slug + `claim/` prefix + card number leaves room for additions if needed.

## What about non-claim branches?

Sometimes a Consumer needs an interim branch (e.g., to test something experimentally before deciding it belongs in the claim branch). Convention:

- Interim branches go under `wip/<consumer>/<purpose>` (NOT `claim/...`)
- They do NOT signal claim — pushing them does not transition the card
- They are deleted when their experiment ends

## Single claim branch per card

The same card uses exactly ONE `claim/N-slug` branch across its entire lifetime, including rework. Rework after a "request changes" review pushes new commits to the same branch — does NOT create `claim/N-slug-v2`.

The only exception: if the card is fully released and re-claimed by a different Consumer with a meaningfully different approach, the new claim may use a slightly different slug (the card title may have evolved). The card's audit log shows the full history regardless.

## What if the claim branch needs renaming?

If a card's title materially changes mid-implementation (which is itself a smell), the Consumer can:

1. Push the new branch name
2. Delete the old branch on origin
3. Audit-log both actions explicitly (R-class — must ask architect)

Better outcome: split the card into two and finish the original under its original name.
