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

## What submit-pr.sh does NOT check

- Section ordering (reviewers care; the script doesn't)
- Heading capitalization (case-sensitive match enforces)
- Trailer presence (auto-appended by submit-pr.sh)
- Linkage to a card (the `--card` arg handles that)

## Why no schema-formal validation

We deliberately did NOT define a JSON-Schema-style strict format for the sections. Each card's verification needs are specific; forcing a rigid template would push Consumers into the "fill in the form" mode that produces filler. The `[x]` / `[ ]` / `[!]` checkbox convention is a soft norm — the script accepts any bullet content as long as it's not whole-section filler.

## Override mechanism

The Producer can override validation for a specific PR by adding the `pr-contract-override` label BEFORE merge. The override creates an audit-log entry so the bypass is traceable.

## Future hardening (not yet implemented)

- Semantic filler detection (LLM-grade rather than regex)
- Per-card-type templates (mechanical vs UX vs spec) selected automatically from card labels
- Cross-PR retro aggregation (carry "lesson learned" entries forward to a per-quarter retro doc)
