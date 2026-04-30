# enforcing-pr-contract — validation rules

Precise rules `scripts/submit-pr.sh` enforces (and the `managing-board` review-queue routine mirrors).

## Required headings (literal-string match)

```python
required = [
    ("## Automated Verification", mandatory=True),
    ("## Human Verification TODO", mandatory=False),
    ("## Retro Notes", mandatory=True),
]
```

Match is **case-sensitive** and **substring-based** — the heading must appear somewhere in the body, on its own line. Variations like `### Automated Verification` (different heading level) are NOT accepted — the canonical contract uses `##`.

## Section non-empty

For each required section that is present:

```python
pattern = re.escape(heading) + r"\s*\n+(.*?)(?=\n##\s|\Z)"
match = re.search(pattern, body, re.DOTALL)
if not match or not match.group(1).strip():
    error("section is empty: " + heading)
```

Empty = whitespace only. A single `n/a` line counts as non-empty for `Retro Notes` (allowed) but counts as filler for `Automated Verification` (rejected).

## Filler detection (Automated Verification)

```python
filler_phrases = ["TBD", "todo: write tests", "no notes", "(none)", "n/a", "N/A"]
auto_text = section_content("## Automated Verification").strip()
if any(f.lower() == auto_text.lower() for f in filler_phrases):
    error("Automated Verification is filler — list the actual checks run")
```

The match is on the WHOLE section content, not substring. A section that says `[x] tests pass — N/A for this PR doesn't apply because...` is fine; only sections whose entire content equals a filler phrase are rejected.

## Filler detection (Human Verification TODO)

If the section is present, the same filler check runs against it. The section being absent is fine — it's optional.

## Contract C — PR↔Issue auto-close keyword

```python
# Run AFTER Contract A passes, BEFORE the trailer auto-injection step.
# Contract C is enforced via idempotent injection, not a hard reject.
import re
keyword_re = re.compile(
    r"(?im)^\s*(?:Close[ds]?|Fix(?:e[ds])?|Resolve[ds]?)\s+#" +
    re.escape(str(card_number)) + r"\b"
)
if keyword_re.search(body):
    # Already present — skip auto-trailer injection (idempotent).
    pass
else:
    # Not present — append the canonical `Closes #<N>` trailer.
    body += f"\n\n---\nCloses #{card_number} — board-superpowers v0.4.0 claim trailer.\n"
```

Match rules:

- **Case-insensitive** (`(?i)` flag): `Closes #N`, `closes #N`, `CLOSES #N` all match.
- **Multi-line** (`(?m)` flag): the keyword may appear on any line of the body, with optional leading whitespace.
- **Card-number-specific**: a `Closes #99` doesn't satisfy Contract C for `--card 35` — the keyword's number must equal the card argument. Cross-referencing other cards (e.g., body says `Closes #99 (incidental fix); Resolves #35 (this card)`) IS valid because at least one keyword matches the linked card.
- **Idempotent**: if the body already contains the matching keyword (e.g., the Consumer hand-wrote `Resolved #35` in the Retro Notes section), `submit-pr.sh` does NOT append a duplicate trailer. Only when no matching keyword exists does the trailer get injected.

GitHub's documented sanctioned auto-close keywords are `close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`, `resolved` — 9 forms total (3 verb roots × 3 inflections each: base, third-person-`s`, past-tense-`d`/`ed`). The regex above covers all 9 via `Close[ds]?|Fix(?:e[ds])?|Resolve[ds]?` plus case-insensitivity. Reference: <https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword>.

## Critical timing — Contract C must fire at PR-OPEN time

GitHub reads PR body keywords **at PR-open time** to register the PR↔Issue link. Retroactively appending the keyword after PR open does NOT retrigger the webhook for an already-merged PR.

This is why `submit-pr.sh` is the **only sanctioned PR-open path** in the plugin's loop. Direct `gh pr create` (bypassing the script) misses the trailer auto-injection at OPEN time and silently breaks the auto-close chain — observed on PR #42 / card #34. Contract C makes this implicit invariant explicit and enforces it at script + review-queue layers.

## Trailer preservation under body updates

The PR↔Issue link registered at OPEN is **not frozen** — GitHub re-evaluates the PR body on every update (`gh pr edit --body-file`, web UI body edits, GraphQL `updatePullRequest`) and re-derives `closingIssuesReferences` from the current content. An update that strips the canonical trailer silently de-registers the link; the next merge then fires without the auto-close webhook chain. Once that merge has happened, retroactively re-appending the trailer does NOT replay the chain — the merge event reads link state at merge time, and a fresh trailer that was absent at merge time is no different from a hand-typed line for webhook-replay purposes.

The sanctioned post-OPEN body-update path is `bash scripts/submit-pr.sh --update-body --pr <PR-N> --body-file <path> --card <N>`. The subcommand:

1. Fetches the PR's current body (`gh pr view --json body`).
2. Refuses if the current body has no Closes/Fixes/Resolves keyword for the linked card — that signals the OPEN-time body never had the trailer (e.g., direct `gh pr create`), the webhook chain is unrecoverable, and silently re-injecting would be misleading audit-trail. Surfaces the manual recovery path in the error message.
3. Otherwise: strips any tail-anchored canonical trailer block in the new body via `(?i)(?:\n+---\s*)?\n+[ \t]*(?:Close[ds]?|Fix(?:e[ds])?|Resolve[ds]?)\s+#<N>\b[^\n]*\s*\Z` (anchored to end-of-string via `\Z`, NOT `(?m)` + `$` which would match end-of-line and silently delete mid-body user prose; `\b` after `<N>` prevents `#530` from matching when `<N>` is `53`), then re-appends the canonical line. Idempotent under repeated invocation: every call produces exactly one trailer block regardless of whether the input body had zero, one, or many.
4. Writes back via `gh pr edit --body-file`.

Direct `gh pr edit --body-file` on a Consumer PR is treated as a contract violation by `consuming-card` Step 10. The Consumer's Step 10 "Common rationalizations to reject" table catches the most common slip ("I'll just use `gh pr edit` for a quick retro-note tweak").

## What submit-pr.sh does NOT check

- Section ordering (reviewers care; the script doesn't)
- Heading capitalization (case-sensitive match enforces)
- Linkage correctness beyond the keyword (the `--card` arg handles that)

## Why no schema-formal validation

We deliberately did NOT define a JSON-Schema-style strict format for the sections. Each card's verification needs are specific; forcing a rigid template would push Consumers into the "fill in the form" mode that produces filler. The `[x]` / `[ ]` / `[!]` checkbox convention is a soft norm — the script accepts any bullet content as long as it's not whole-section filler.

## Override mechanism

The Producer can override validation for a specific PR by adding the `pr-contract-override` label BEFORE merge. The override creates an audit-log entry so the bypass is traceable.
