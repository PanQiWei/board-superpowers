# using-board-superpowers — first-time user guide

What to tell the user when they invoke this skill for the first time on a new repo.

## v1-minimum first-time setup (manual)

Since `bootstrapping-repo` is deferred to v1-complete, first-time setup is manual. Walk the user through:

### 1. Create or identify the GitHub Project

```bash
# If creating new:
gh project create --owner <login> --title "<repo> board"

# Or use an existing project's number.
```

### 2. Add the standard Status field options

The Project's Status field needs these single-select options (in order):

```
Backlog | Ready | In Progress | Blocked | In Review | Done
```

If using GitHub's default Status field, it ships with `Todo / In Progress / Done`. Edit it via the Project's UI: add `Backlog`, `Ready`, `Blocked`, `In Review`; rename `Todo` to nothing (delete it).

### 3. Add the standard labels to the repo

```bash
gh label create "wip-override" --description "Allows claim past WIP cap" --color "FBCA04"
gh label create "suspended" --description "Card paused mid-work" --color "D4C5F9"
gh label create "security" --description "Triggers /cso review on PR" --color "B60205"
gh label create "pr-contract-override" --description "Bypass PR three-section validation" --color "C5DEF5"
```

### 4. Create `.board-superpowers/config.yml` in the repo

```yaml
# .board-superpowers/config.yml — committed to git
project:
  owner: <github-login-or-org>
  number: <project-number>
wip_cap_per_consumer: 1
# autonomy_overrides: {}   # deferred to v1-complete
```

### 5. Verify

```bash
bash $CLAUDE_PLUGIN_ROOT/scripts/check-deps.sh
bash $CLAUDE_PLUGIN_ROOT/scripts/read-board.sh \
  --owner <login> --project <number> --status Ready
```

Both should exit 0; the second prints the JSON list of Ready cards (empty `[]` if none yet).

## Sanity check

Open a fresh CC session in the repo. Type:

```
what should I work on
```

The session should auto-trigger `using-board-superpowers` (this skill), which routes to `managing-board` (daily routine), which produces the morning briefing.

If nothing triggers: check that the plugin is enabled in `~/.claude/plugins/marketplaces/<your-marketplace>/board-superpowers/`. Run `/plugin list` in CC to verify.

## v1-complete will automate steps 1-5

The `bootstrapping-repo` skill (deferred) handles all of the above interactively. v1-minimum users do it once by hand.
