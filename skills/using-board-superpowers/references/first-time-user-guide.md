# using-board-superpowers — first-time user guide

What to tell the user when they invoke this skill for the first time on a new repo.

## Manual first-time setup

Currently first-time setup is manual. Walk the user through:

### 1. Create or identify the GitHub Project

```bash
# If creating new:
gh project create --owner <login> --title "<repo> board"

# Or use an existing project's number.
```

### 2. Add the standard Status field options

The Project's Status field needs these single-select options (in this order):

```
Backlog | Ready | In Progress | Blocked | In Review | Done
```

If using GitHub's default Status field, it ships with `Todo / In Progress / Done`. Edit it via the Project's UI: add `Backlog`, `Ready`, `Blocked`, `In Review`; remove `Todo`.

### 3. Add the standard labels to the repo

```bash
gh label create "wip-override"          --description "Allows claim past WIP cap"          --color "FBCA04"
gh label create "suspended"             --description "Card paused mid-work"               --color "D4C5F9"
gh label create "security"              --description "Triggers /cso review on PR"         --color "B60205"
gh label create "pr-contract-override"  --description "Bypass PR three-section validation" --color "C5DEF5"
```

### 4. Create `.board-superpowers/config.yml` in the repo

```yaml
# .board-superpowers/config.yml — committed to git, shared by team.

# Project coordinates. Format: <owner>/<number>. The agent splits
# on '/' when calling the plugin's scripts.
project: <owner>/<number>

# Per-Consumer WIP cap (hard rejection from claim-card.sh when exceeded).
wip_cap_per_consumer: 1

# Future fields (not yet consumed):
#   autonomy_overrides: {}  # mutating-action override map (empty = ask-architect on every mutation)
```

When the agent calls `bash scripts/read-board.sh --owner <X> --project <N>`,
it reads this file, splits `project` on `/` to get `<X>` and `<N>`, and
passes them as args. Same for `claim-card.sh`.

### 5. Verify

```bash
bash $CLAUDE_PLUGIN_ROOT/scripts/check-deps.sh
bash $CLAUDE_PLUGIN_ROOT/scripts/read-board.sh \
  --owner <login> --project <number> --status Ready
```

(On Codex CLI, `${CLAUDE_PLUGIN_ROOT}` doesn't exist — substitute the absolute path to the plugin install.)

Both commands should exit 0; the second prints the JSON list of Ready cards (empty `[]` if none yet).

## Sanity check

Open a fresh CC session in the repo. Type:

```
what should I work on
```

The session should auto-trigger this entry skill, which routes to `managing-board` (daily routine), which produces the morning briefing.

If nothing triggers: check that the plugin is enabled. Run `/plugin list` in CC to verify. On Codex, check `~/.codex/hooks.json` for the SessionStart entry (run `bash <plugin-root>/scripts/register-codex-hooks.sh --install-user` if missing).
