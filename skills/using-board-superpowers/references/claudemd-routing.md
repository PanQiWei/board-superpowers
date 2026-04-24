# CLAUDE.md routing block

Append this block verbatim to the project's `CLAUDE.md` (create the
file if it doesn't exist). The markers are load-bearing — tooling keys
off them to detect whether a project is already routed.

```markdown
<!-- board-superpowers:routing -->
## board-superpowers session routing

This project uses the `board-superpowers` plugin. Any Claude Code
session in this project plays one of two roles:

- **Board Consumer** — if the first message contains `[board-card:#N]`,
  or the user asks to work on / claim / implement card N, invoke the
  `consuming-card` skill immediately. That skill owns the full
  lifecycle: claim → implement → PR → update board.
- **Board Manager** — if the user asks about planning today's work,
  reviewing the board, decomposing a requirement, triaging blocked
  cards, or running a retro, invoke the `managing-board` skill.
- When unsure, invoke `using-board-superpowers` first.

board-superpowers depends on the `superpowers` and `gstack` plugins
and will delegate design and execution work to them. Do not
reimplement what they already do.
<!-- /board-superpowers:routing -->
```

## Why the markers matter

The `<!-- board-superpowers:routing -->` pair lets
`check-deps.sh` detect whether a project is already routed without
string-matching the prose (which may drift over time as plugin docs
evolve). Treat the markers as protocol, not decoration.
