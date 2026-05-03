# Boundary rules — atomic reflex constraint + namespace prefix rule

## Atomic reflex constraint

`composing-siblings` is an atomic skill. Atomic skills in board-superpowers are
reflexes: they are consumed by molecular skills, they do not call any same-plugin
skill, and they do not orchestrate work. This constraint exists to prevent
call-graph cycles and to preserve the SPOT (single-point-of-truth) property:
each atomic consolidates one contract that would otherwise be inlined N times.

Concretely:
- `composing-siblings` MUST NOT invoke `board-superpowers:briefing-daily`,
  `board-superpowers:intaking-requirement`, `board-superpowers:reviewing-pr-queue`,
  `board-superpowers:triaging-board`, `board-superpowers:consuming-card`,
  `board-superpowers:bootstrapping-repo`,
  `board-superpowers:decomposing-into-milestones`, or any other skill in this
  plugin.
- If a future change to `composing-siblings` seems to require calling another
  same-plugin skill, the design has gone wrong. Split or merge the atomics
  instead of introducing the call.
- Cross-plugin references (`gstack:*` / `superpowers:*`) are also not invoked
  from this skill's body — this skill defines the invocation rules, it does not
  itself invoke the siblings.

This constraint is enforced by the `SKILLS.md` call-graph topology and reviewed
in CI gate `scripts/verify-skill-metadata.sh`.

## Namespace prefix rule

Every reference to a sibling skill MUST carry the full `<plugin>:<skill>`
namespace prefix. This rule applies in both SKILL.md bodies and in prose
references in reference files.

### Correct forms

```
superpowers:test-driven-development
superpowers:brainstorming
superpowers:writing-plans
superpowers:verification-before-completion
superpowers:requesting-code-review
superpowers:subagent-driven-development
superpowers:systematic-debugging
gstack:/office-hours
gstack:/plan-ceo-review
gstack:/plan-eng-review
gstack:/review
gstack:/qa
gstack:/cso
gstack:/investigate
```

Note the asymmetry: `superpowers` uses `:` separator; `gstack` uses `:/`
separator (this is gstack's convention for its skills, which use the slash
prefix). Both forms are correct for their respective plugins.

### Incorrect forms (never use)

```
test-driven-development          # bare — ambiguous across plugins
brainstorming                    # bare — will not resolve correctly
/office-hours                    # slash-only — missing plugin prefix
qa                               # bare — will not resolve correctly
```

### Why the prefix matters

When multiple plugins are loaded simultaneously (which is the normal state —
board-superpowers requires both `superpowers` and `gstack`), a bare skill name
is ambiguous: the platform may resolve it to a same-plugin skill, a sibling
skill, or fail silently. The namespace prefix guarantees cross-platform
unambiguous resolution on both Claude Code and Codex CLI.

The prefix is also load-bearing for maintainability: greping for
`superpowers:` or `gstack:/` in the codebase unambiguously finds all
cross-plugin edges. Bare references scatter and become invisible.

## What this skill does NOT govern

- **board-superpowers internal skill references** — those use the
  `board-superpowers:` prefix and their topology is defined in `SKILLS.md`.
- **Script invocations** (`bash scripts/foo.sh`) — those are not skill
  invocations and follow the script contract in `scripts/AGENTS.md`.
- **MCP tool calls** — those are not skill invocations. The board-superpowers
  composition model explicitly rules out MCP as the cross-plugin composition
  channel; SKILL invocation is the canonical mechanism, not cross-process IPC.
