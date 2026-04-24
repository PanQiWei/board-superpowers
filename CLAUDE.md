# board-superpowers — project instructions

This repo **is** the plugin. Sessions here are plugin-maintainer
sessions, not product-user sessions. See @README.md for the
user-facing overview.

## Self-hosting

This repo uses its own plugin. The `board-superpowers:routing` block
at the bottom of this file is mirrored verbatim from
`skills/using-board-superpowers/references/claudemd-routing.md` —
edits to one must land in the other in the same commit.

The `<!-- board-superpowers:routing -->` / `<!-- /board-superpowers:routing -->`
marker pair is matched by tooling. Do not rename, indent, or merge
into surrounding prose.

## Protocol invariants

These are load-bearing because downstream installs depend on them:

- **`scripts/*.sh` are a public contract.** Hooks, skills (via
  `${CLAUDE_PLUGIN_ROOT}`), and user automations call them. Breaking
  changes need a migration note in the PR body.
- **`check-deps.sh` exit codes:** `0` = deps present, `2` = missing.
  No new non-zero codes without updating every caller + branching
  skill.
- **Skill `description` frontmatter is behavior.** Downstream models
  match on it. Treat edits with the same care as code.

## Project-specific skill routing

The global `~/.claude/CLAUDE.md` already routes gstack ↔ superpowers.
In addition, for this repo:

- Editing any `skills/*/SKILL.md` → invoke
  `superpowers:writing-skills` first.
- Second opinion on shell logic → `gstack:/codex`.
- Before tagging a release that touches `scripts/` or `hooks/` →
  `gstack:/cso`.
- **Not applicable here:** `gstack:/ship` `/land-and-deploy`
  `/canary`. This plugin has no deploy target; release = bump
  `plugin.json` + `marketplace.json`, push a git tag.

## Commands

```bash
bash scripts/check-deps.sh                      # preflight; exits 0 or 2
bash scripts/bootstrap-project.sh --help        # one-time per-repo setup
bash scripts/create-card.sh --help              # Manager: create card
bash scripts/claim-card.sh --help               # Consumer: atomic claim
bash scripts/transition-card.sh --help          # move card status
```

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
