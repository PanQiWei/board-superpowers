# consuming-card — PR template reference

Practical templates the Consumer pastes into their PR body draft. The full validation rules live in `board-superpowers:enforcing-pr-contract` references.

## Default template (paste, then fill)

```markdown
<one-paragraph PR description — what changed and why>

## Automated Verification

- [x] <check 1 — name the actual command run>
- [x] <check 2>
- [ ] <check 3 — known-failing, explain>

## Human Verification TODO

- [ ] <action 1 — what the reviewer should click / observe>

## Retro Notes

- <lesson 1 — phrased as something the next card's Consumer can apply>

Closes #<N>
```

## When sections degenerate

If you find yourself wanting to write filler in a section, that's a signal to pause. Common signals:

- "All tests pass" in Automated Verification → name the test files / commands
- "(none)" in Human Verification TODO → either there's truly nothing, in which case omit the section entirely, OR you're missing a UI/UX surface that needs human eyes
- "n/a" in Retro Notes → either truly true (small mechanical change), in which case write `n/a — straightforward bug fix, no reusable lessons` (the explicit "n/a" is allowed); OR you skipped the 5-second pause to think about lessons

The validator at `submit-pr.sh` rejects whole-section filler; thinking it through at draft time is cheaper than re-editing after rejection.

## Body before sections (the description)

The pre-section paragraph should answer "what changed and why" in 1-3 sentences. Don't repeat the card title. Don't say "Implements card #12" — the closing trailer covers that. Say what the merge actually changes for the next reader.

Good: "Replaces the inline state machine in `claim-card.sh` with a call to `board-canon`'s claim protocol — eliminates 30 lines of duplicated transition rules."

Bad: "This PR implements card #12: write claim-card.sh."
