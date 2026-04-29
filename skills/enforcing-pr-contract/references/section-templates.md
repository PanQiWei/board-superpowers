# enforcing-pr-contract — section templates

Concrete examples per card type. Parent `SKILL.md` shows the canonical templates; this file shows how they bend for different shapes of work.

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

When this card's claim crossed a WIP-limit boundary, add an extra bullet to the `## Automated Verification` block above (regardless of card type) for Manager review-queue visibility:

```markdown
- [x] WIP cap crossed: cross-kanban total at 3/3 with this claim (global `wip_limit: 3`) — flagged for review-queue visibility.
```

Per `board-canon` § "Multi-kanban WIP semantics" the primary cap is the per-actor **cross-kanban total** against the global `modules.m5_repo_configuration.wip_limit` in `<repo>/.board-superpowers/settings.yml`. The optional per-kanban `modules.m10_kanban.kanbans[].wip_limit_local` is an additional cap that, when set, must also hold for the originating kanban — emit a second bullet naming the kanban and its local cap when that local cap is the binding constraint. If the claim did NOT cross either cap, omit the line.

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
