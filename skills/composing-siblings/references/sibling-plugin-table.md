# Sibling-plugin table — quick reference for board-superpowers callers

This table covers only the subset of `gstack:*` and `superpowers:*` skills
that board-superpowers' 9 handoff-point callers actually invoke. It is NOT a
full catalog of either plugin (~37 skills combined). For the full catalog, read
each plugin's own entry skill (`superpowers:using-superpowers` or
`gstack:/autoplan`).

## How to read this table

- **Invoke as**: the exact string to use in a skill reference. Namespace prefix
  is mandatory (see SKILL.md § "Invocation rules" Rule 2 for the namespace prefix
  discipline; the full boundary rules live in `boundary.md`).
- **Phase**: which phase this skill belongs to per the board-superpowers composition model (bookends = direction-setting + delivery QA/security; middle = implementation discipline loop).
- **Mode-2 safe**: whether the skill's body is procedural (does not itself
  issue a subagent spawn instruction). "TBD" means empirical verification is
  pending; do not invoke from Mode-2 without checking the decision tree in
  SKILL.md § "Invocation rules" Rule 3 (full per-skill fallback table in
  `procedural-fallback-rules.md`).
- **When to use**: the trigger signal that routes to this skill.

## superpowers:* skills (middle-phase disciplines)

| Invoke as | Phase | Mode-2 safe | When to use |
|-----------|-------|-------------|-------------|
| `superpowers:brainstorming` | Middle | yes | Requirements not yet settled; direction set but design not locked; need to explore the space before writing a plan |
| `superpowers:writing-plans` | Middle | yes | Design output exists and needs to be turned into an executable, ordered implementation plan |
| `superpowers:test-driven-development` | Middle | yes | About to write any feature code or bugfix; enforces Red → Green → Refactor discipline |
| `superpowers:subagent-driven-development` | Middle | TBD | Executing a multi-step implementation plan with parallelizable subtasks — see `procedural-fallback-rules.md` before invoking from Mode-2 |
| `superpowers:systematic-debugging` | Middle | yes | A test is failing or behavior is unexpected and the root cause is not obvious |
| `superpowers:verification-before-completion` | Middle | yes | About to claim implementation work is done; enforces evidence-first "done" standard |
| `superpowers:requesting-code-review` | Middle | yes | Implementation complete; soliciting an independent second-eyes review before opening a PR |

## gstack:/* skills (bookend disciplines)

| Invoke as | Phase | Mode-2 safe | When to use |
|-----------|-------|-------------|-------------|
| `gstack:/office-hours` | Bookend (pre-card) | yes | "Is this worth building?" — demand validation, YC-style forcing questions |
| `gstack:/plan-ceo-review` | Bookend (pre-card) | yes | "Rethink the problem" — scope expansion, 10-star product, premise challenge |
| `gstack:/plan-eng-review` | Bookend (pre-card) | yes | Architecture trade-off decisions that warrant a durable record |
| `gstack:/review` | Bookend (pre-PR) | yes | Production-bug-angle code review of the diff before the PR opens |
| `gstack:/qa` | Bookend (conditional) | yes | UI-touching cards: real-browser QA before PR submission |
| `gstack:/cso` | Bookend (conditional) | yes | Security-flagged cards: OWASP / STRIDE audit before PR submission |
| `gstack:/investigate` | Bookend (debugging) | yes | Second-angle investigation when `superpowers:systematic-debugging` is not resolving the root cause |

## Verification status

The Mode-2 safe status above was last verified against the sibling-plugin
codebases on **2026-05-03**. Re-verify when a sibling plugin ships a new major
version or when a previously-TBD entry needs to be resolved. The verification
procedure: read the skill's SKILL.md body; if the body contains an `Agent` tool
call or `spawn_agents_on_csv` instruction, the skill is NOT Mode-2 safe.

`superpowers:subagent-driven-development` is marked TBD because its name
implies subagent spawning. An audit performed on 2026-04-26 found it to be
procedural — the body instructs the agent on how to drive a subagent workflow
but does not itself issue an `Agent` tool call. Re-verify on each superpowers
release that touches this skill.
