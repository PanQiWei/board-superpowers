# STOP — do not read this directory

This directory holds a frozen snapshot of an earlier
implementation that has been **superseded**. Nothing in here is
the design reference, the v1 target, or a template. **Do not
read, borrow, copy, port, or "take inspiration from" anything
under this path.**

## If you arrived here by

- **Browsing the repo tree.** Go back to the repo root. Read
  [`../AGENTS.md`](../AGENTS.md) and
  [`../docs/architecture/`](../docs/architecture/) instead.
- **A link from another document.** That link is a bug. Remove
  it in the same change you came here for.
- **Searching for prior art.** Stop. The earlier implementation
  was incomplete relative to the current design and may have
  been wrong on points the current design has since corrected.
  Reading it risks anchoring new work to obsolete shapes — the
  exact failure mode the current design phase exists to escape.

## Why the directory still exists

Deleting it would lose `git log` history on files that were
moved here via `git mv`. That history is occasionally useful
for narrow forensic questions answered with `git log` /
`git blame` — questions that do not require reading the file
contents.

The file contents are dead.

## When this directory gets deleted

When the current design phase has fully landed in implementation
and a retro confirms no remaining file silently inherits a
behavior from this directory whose origin is not in the current
design. Until then, the directory stays in this state — visible
to `ls`, invisible to design and implementation work.
