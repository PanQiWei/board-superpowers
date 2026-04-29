# enforcing-pr-contract — section templates

Concrete examples per card type. Parent `SKILL.md` shows the canonical templates; this file shows how they bend for different shapes of work.

## Per-kanban WIP-limit callout

If this card's claim crossed the per-kanban `wip_limit` (e.g., the `wip_limit: 2` cap on the `default` kanban from `<repo>/.board-superpowers/settings.yml § modules.m5_wip.kanbans.<kanban-id>.wip_limit`), note that under `## Automated Verification` for Manager review-queue visibility:

```markdown
## Automated Verification

- [x] WIP cap crossed: `default` kanban (`wip_limit: 2`) at 2/2 with this claim — flagged for review-queue visibility.
- [...other verification rows...]
```

If the claim did NOT cross a `wip_limit` boundary, omit the line.

## Pure docs change

```markdown
## Automated Verification

- [x] `markdown-link-check docs/**/*.md` — pass (no broken links)
- [!] no shell scripts touched — shellcheck N/A

## Retro Notes

- The cross-link between `SKILL_DEVELOPMENT.md` and `SKILLS.md` was easy to miss when adding the new metadata convention; the next time we add a project-wide concept, search both docs upfront.
```

(Human Verification TODO omitted — no UI surface)

## Adding a new SKILL.md

```markdown
## Automated Verification

- [x] `bash scripts/verify-skill-metadata.sh` — pass
- [x] `bash scripts/verify-skill-frontmatter.sh` — pass
- [x] Skill triggers in fresh CC session for prompt "<the trigger phrase>"

## Human Verification TODO

- [ ] Open `/<plugin>:<skill>` in autocomplete — confirm `argument-hint` displays correctly
- [ ] Trigger the skill via natural-language prompt — confirm body executes the procedure end-to-end

## Retro Notes

- The skill's `description` had to be made significantly more "pushy" than initial draft to avoid undertriggering — the empirical pattern in `SKILL_DEVELOPMENT.md` § "description = WHEN, not WHAT" was load-bearing.
```

## Bug fix in a script

```markdown
## Automated Verification

- [x] Added regression test in `tests/test-claim-card.sh` — passes
- [x] `shellcheck -x scripts/claim-card.sh` — clean
- [x] Re-ran the original failing scenario manually — bug no longer reproduces

## Retro Notes

- The bug was a `set -e` interaction with `command | python3 -c "..."` — the python script's `sys.exit(1)` in a pipeline is invisible to the caller without `set -o pipefail`. We already had `pipefail` set at the top of `lib/common.sh` but the test harness did not. Updated harness; consider auditing other harnesses for the same pattern.
```

## Refactor with no behavior change

```markdown
## Automated Verification

- [x] All existing tests still pass: `bash tests/run-all.sh`
- [x] `shellcheck -x scripts/**/*.sh` — clean
- [x] `git diff main..HEAD` shows only the intended file moves

## Retro Notes

- n/a — pure mechanical refactor, no reusable lessons.
```

(Human Verification TODO omitted)

## Spec-only change (architecture decision)

```markdown
## Automated Verification

- [x] `markdown-link-check <doc-paths>` — pass (no broken cross-links)
- [x] All cross-references between the affected docs updated in same PR

## Retro Notes

- A spec change had to be cross-linked from 4 different surface docs; a project's change-impact matrix was load-bearing for finding all of them. Adding a new architectural decision without grepping the matrix risks orphan links.
```
