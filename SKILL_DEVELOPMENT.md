# Skill Development Guide

> **Required reading** for anyone authoring or modifying any
> `SKILL.md` in this repo (everything under `skills/`). Sister
> document to `PLUGIN_DEVELOPMENT.md` and
> `MULTI_AGENT_DEVELOPMENT.md` — those cover the **plugin /
> hook / orchestration contracts**; this one covers the
> **skill-authoring contract**: how to write a skill that triggers
> reliably, stays under context budget, composes with other
> skills cleanly, and survives review.

Skills are board-superpowers' primary product surface. For every
skill in this repo, the `description` field is the matcher Claude
Code uses to decide whether to invoke it; the body is the
procedure the model executes once invoked. Both are load-bearing;
both must be authored against the discipline laid out below.

This document is **prescriptive guidance for new and revised
skills**. It does not catalogue or evaluate the skills currently
in this repo — when an example is needed, it is drawn from the
four reference libraries cited above, not from this project.

This document is grounded in four community / official sources we
treat as authoritative for skill authoring:

1. **Anthropic Skills spec** — <https://code.claude.com/docs/en/skills.md>
2. **OpenAI Codex Skills** — <https://developers.openai.com/codex/skills>
3. **agentskills.io specification** — <https://agentskills.io/specification>
   (cross-platform `SKILL.md` schema)
4. **Reference implementations** read in full while drafting this
   doc:
   - `anthropics/skills` (the Anthropic example-skills repo —
     `skill-creator`, `docx`, `claude-api`)
   - `obra/superpowers` (the `superpowers` plugin —
     `writing-skills`, `test-driven-development`,
     `systematic-debugging`, `brainstorming`,
     `subagent-driven-development`, `executing-plans`,
     `using-superpowers`)
   - `gstack` (Garry Tan's gstack plugin — `office-hours`,
     `qa`, `codex`, `autoplan`, `investigate`)
   - `ljg-skills` (Liu Jiaguo's personal toolkit —
     `ljg-card`, `ljg-paper`, `ljg-paper-flow`,
     `ljg-roundtable`, `ljg-word`, `ljg-skill-map`)

**URL freshness:** all URLs verified **2026-04-27**. Re-verify
when modifying related code. A broken or moved canonical URL is a
load-bearing fact and must be patched in the PR that catches it.

---

## TL;DR — what to remember if you read nothing else

1. **Think of skills as a graph, not a folder.** Every skill is
   a node at one of three layers (entry / molecular / atomic);
   every reference between skills is an edge whose
   materialization (pure reference / inline copy / hybrid)
   you choose deliberately. See §"Skill graph" below.
2. **`description = WHEN, not WHAT`.** Never summarize the
   procedure in the description. Triggering conditions only,
   third person, prefer "Use when ...".
3. **Body ≤ 500 lines, target 200–400.** Past that, split into
   `references/<topic>.md` and have the body link them
   explicitly. Never use `@` auto-load for references; never
   chain references more than one level deep.
4. **Cross-skill references always use the namespace prefix.**
   `superpowers:test-driven-development`, never bare
   `test-driven-development`.
5. **Subagents cannot spawn subagents** — your skill cannot rely
   on nested orchestration. One level deep, period.
6. **Skill body stays in English** even when project discussion is
   in Chinese, so the skill is portable across locales.
7. **Test the skill before you ship it.** Discipline skills get
   pressure-tested with subagents (RED-GREEN-REFACTOR);
   output skills get with-skill / baseline eval matrices.
   Untested skill = untested code.

---

## Surface mapping — Claude Code vs Codex CLI

| Surface | Claude Code | Codex CLI | Portable subset |
|---------|-------------|-----------|-----------------|
| Skill location | `skills/<name>/SKILL.md` (project / user / plugin) | `skills/<name>/SKILL.md` (project `.codex/skills/` or via plugin manifest) | Same path shape. |
| Required frontmatter | `name`, `description` | `name`, `description` | Same — both fields required everywhere. |
| Display metadata | richer frontmatter (`disable-model-invocation`, `user-invocable`, `allowed-tools`, `context: fork`, `agent`, `arguments`, `paths`) | optional `agents/openai.yaml` for `interface.{display_name, short_description, icon_*, brand_color, default_prompt}` | None. Each platform's display layer is platform-specific. |
| Triggering | model auto-matches on `description` | model auto-matches on `description` (subject to Codex's "explicit user instruction required" for some classes — see Codex docs) | Same matcher contract. |
| Cross-skill invocation | `Skill` tool | `skill` tool | Same intent; differ in tool name only. |
| Bundled scripts | `scripts/*.{sh,py,js}` invoked from body | same | Identical. |
| Bundled references | `references/<topic>.md` lazy-loaded by reading from body | same | Identical. |
| Bundled subagent prompts | `agents/<role>.md` (community convention; Anthropic example-skills uses this layout) | same convention; if you also want Codex-side display metadata, add `agents/openai.yaml` | Identical layout, optional `openai.yaml` is Codex-only. |
| Eval framework | `evals/evals.json` + `eval-viewer/` (Anthropic skill-creator pattern) | not formalized upstream | Anthropic-only today. |

This mirrors `PLUGIN_DEVELOPMENT.md` §"TL;DR — surface mapping"
for the same reason: write to the **portable subset** by default,
and only reach for platform-specific surfaces with explicit
justification in the skill itself.

---

## What a skill is (and isn't)

A **skill** is:

- A reusable **procedure** the model can invoke when it recognizes
  the triggering conditions.
- A **reference** the model can consult on demand
  (Quick-reference table, API doc, error catalogue).
- A **mental model** the model can apply when it spots the right
  problem shape.
- A **discipline** the model is required to follow when a class of
  task is detected.

A skill is **not**:

- A README about how the project works (that's `README.md`).
- A developer guide for plugin maintainers (that's
  `PLUGIN_DEVELOPMENT.md` / `MULTI_AGENT_DEVELOPMENT.md` / this
  doc).
- A narrative of how the user solved one specific problem in one
  session.
- A configuration file (use `hooks/`, `settings.json`,
  `.codex-plugin/plugin.json` instead).

If a behavior is enforceable mechanically (regex, validator,
hook), implement it as a hook or script — not a skill. Skills
exist for **judgment calls** that mechanical enforcement can't
make.

### Four taxonomic types

| Type | Examples | What it documents | How you test it |
|------|----------|-------------------|-----------------|
| **Technique** | `condition-based-waiting`, `claim-card.sh` usage | Concrete steps to apply | Run a fresh agent against a new scenario; does it apply the technique correctly? |
| **Pattern** | `flatten-with-flags`, `superpowers:brainstorming` | Mental model + when to use | Recognition scenarios + counter-examples |
| **Reference** | `claude-api`, `docx` | Schema / API / canonical state machine | Retrieval + correct-application scenarios |
| **Discipline** | `test-driven-development`, `verification-before-completion` | Rules the agent must follow under pressure | Pressure tests with combined load (time + sunk cost + exhaustion) |

Knowing your type up front tells you which testing regime applies
(see **Testing skills** below) and shapes the body skeleton.

---

## Anatomy of a skill

```
skills/
└── <skill-name>/
    ├── SKILL.md              # Required. Frontmatter + procedure.
    ├── references/           # Optional. Lazy-loaded reference docs.
    │   └── <topic>.md
    ├── scripts/              # Optional. Tools the skill invokes inline.
    │   └── <name>.{sh,py,js}
    ├── agents/               # Optional. Subagent role prompts.
    │   └── <role>.md
    ├── assets/               # Optional. Output templates / static resources.
    │   └── <file>
    └── evals/                # Optional (Anthropic-style eval framework).
        └── evals.json
```

**These directory names are a community convention, not part of
the spec.** They are however used identically by Anthropic
example-skills, superpowers, ljg-skills, and most gstack skills.
**Use them as written. Do not invent new ones** —
`templates/` (used by gstack `qa/`) is a counter-example that
fragments the convention without benefit.

### What goes where

| Directory | Semantics | Loading model | Examples |
|-----------|-----------|---------------|----------|
| `SKILL.md` | The procedure / contract / overview. | Loaded into context the moment the skill triggers. | Every skill. |
| `references/` | Long reference material the skill body **points at by name** when relevant. | Read on demand by the body's instructions ("see references/X.md"). | `using-superpowers/references/codex-tools.md` (cross-platform tool name map); `ljg-card/references/mode-{long,infograph,...}.md` (per-mode dispatcher). |
| `scripts/` | Executable tools the skill **invokes from the body** (`bash scripts/foo.sh`, `python scripts/foo.py`). Not exposed to the user. | Executed; not loaded as text. | `brainstorming/scripts/start-server.sh`; `skill-creator/scripts/aggregate_benchmark.py`. |
| `agents/` | Role prompts the skill spawns as subagents via `Agent` tool. | Read by a subagent invocation, not by the parent. | `skill-creator/agents/{grader,analyzer,comparator}.md`. |
| `assets/` | Static artifacts emitted as output (templates, fonts, icons). | Read or copied by scripts; not loaded as text. | `docx/assets/` templates; `ljg-card/assets/capture.js`. |
| `evals/` | Test cases + scoring config (Anthropic eval framework). | Consumed by `scripts/run_eval.py` only. | `skill-creator/evals/evals.json`. |

The split is **load-bearing for token economy**. Anything in
`SKILL.md` is paid for on every invocation. Anything in
`references/` is paid for only when the body says "go read it."
Get this wrong and a 70-line preamble starts riding into every
session — see "Anti-patterns" below.

---

## Skill graph: layered nodes (entry / molecular / atomic)

Up to this point we've discussed one skill at a time. The next two
sections shift to the **graph view**: every skill in this
ecosystem is a node, every reference between skills is an edge,
and the way you organize nodes and materialize edges has more
impact on usability than any single SKILL.md's prose.

This is not a board-superpowers invention. The same three-layer
structure is showing up across the recent agent-skill literature:

- **SkillX** (Wang et al., 2026 — <https://arxiv.org/html/2604.04804v2>)
  proposes Planning Skills (high-level task organization),
  Functional Skills (reusable tool-based subroutines), and Atomic
  Skills (per-tool execution patterns) — a near-1:1 match with
  the model below.
- **SoK: Agentic Skills — Beyond Tool Use in LLM Agents**
  (Jiang et al., 2026 — <https://arxiv.org/abs/2602.20867>)
  Section VI-F1: "a high-level skill (e.g., 'deploy a web
  application') invokes mid-level skills ('set up database,'
  'configure server,' 'run tests'), which in turn invoke
  low-level skills." This mirrors the option framework in
  hierarchical reinforcement learning.
- **HERAKLES** (Carta et al., 2025 — <https://arxiv.org/abs/2508.14751>)
  shows the lifecycle: composite skills that prove out get
  "compiled" downward into faster atomic policy — i.e., today's
  molecular layer becomes tomorrow's atomic layer.
- **Brad Frost's Atomic Design** (2013) is the same idea applied
  to UI: atoms → molecules → organisms → templates → pages.
- **Voyager** (Wang et al., TMLR 2024 — <https://arxiv.org/abs/2305.16291>)
  is the canonical "compositional skill library" for LLM agents,
  but its library is flat — no explicit layering. The papers
  above are what added the hierarchy.

### The three layers

| Layer | Role in the graph | Stability | Reuse rate | Description style | Dependency direction |
|-------|-------------------|-----------|-----------|--------------------|----------------------|
| **Entry** | First touch. The user (or a session) hits this. Routes / dispatches. Does no real work itself. | Low — changes when new scenarios appear. | 1 ↔ 1 with a triggering scenario. | Strong scenario keywords. Matches "what the user actually says." | Calls into molecular layer. |
| **Molecular** | A meaningful business / domain procedure. Composes several atomic capabilities into one workflow. Often state-machine-like. | Medium. | 1 ↔ N (a procedure used in several workflows). | Task-shaped: matches "what we're doing." | Calls into atomic layer. |
| **Atomic** | A single-purpose methodological primitive. Does one thing well. Reused everywhere. No business binding. | High — once stable, rarely changes. | M ↔ N (used by many composers). | Methodology / symptom keywords. Matches "the problem shape." | Does not call upward. |

### Concrete examples from the four reference libraries

| Layer | Examples |
|-------|----------|
| **Entry** | `superpowers:using-superpowers` (router for the entire superpowers library); `gstack:/autoplan` (orchestrates a full plan-review pipeline as one entry point). |
| **Molecular** | `superpowers:executing-plans`, `superpowers:subagent-driven-development`, `superpowers:requesting-code-review`; `gstack:/qa`, `gstack:/ship`, `gstack:/investigate`; `ljg-paper-flow` (composes `ljg-paper` and `ljg-card` into one fan-out pipeline); Anthropic `skill-creator` (orchestrates evals + grader + comparator subagents). |
| **Atomic** | `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `superpowers:brainstorming`, `superpowers:condition-based-waiting`, `superpowers:verification-before-completion`; `gstack:/codex`, `gstack:/browse`; `ljg-word`; Anthropic `claude-api`, `docx`. |

### Picking the layer for a new skill

When unsure, run these three checks in order:

1. **Does it route or does it work?** If the body is mostly
   "based on X, invoke skill Y," it's **entry**. If it has its
   own procedure, it's not.
2. **Does it have business / domain semantics?** If the skill
   only makes sense inside one task family (managing the
   board, consuming a card), it's **molecular**. If it is
   methodology that applies across families, it's not.
3. **Does it depend on no other skill in this plugin?** If yes,
   it's **atomic**. If it composes others, it's molecular.

If a skill seems to span two layers, **split it**. Mixing layers
inside one skill is the most common authoring mistake — see
Anti-pattern A9 below.

### Layer composition is not Anthropic's official model

Anthropic's spec deliberately stops at the single-skill level —
neither <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
nor <https://agentskills.io/specification> defines a skill-to-skill
composition primitive. Composition is left to plugins / hooks /
subagents. Treat the layering above as engineering practice
grounded in the cited literature, not a re-statement of platform
spec — and label it as such when you adopt it inside your own
skills.

### Anti-pattern: layer mixing

Two recurring failure modes:

- **Atomic doing entry's job.** A `test-driven-development`
  skill that also routes ("if the user says X, do Y; else
  Z"). This dilutes its description (anti-pattern A1) and
  bloats its body. Fix: extract the routing into a separate
  entry skill, leave the methodology pure.
- **Entry doing real work.** An entry / dispatcher skill that
  not only routes but also runs an inline bootstrap (creating
  files, mutating config, calling out to GitHub). This couples
  the entry to one specific molecular outcome and prevents
  reuse from other entry surfaces. Fix: have the entry call the
  molecular skill (or run the script via a hook), not embed the
  procedure.

---

## Skill graph: edge materialization (reference / inline / hybrid)

A skill graph isn't just nodes; it's edges. Whenever skill A
needs the capability of skill B (or script X, or reference Y, or
a section of `CLAUDE.md` Z), you choose how to **materialize**
the edge: how much of B's content does A's body actually contain,
versus how much it just points at?

This is the **transclusion problem** from hypertext theory — Ted
Nelson's Project Xanadu coined it in the 1960s, Vannevar Bush's
"Memex" (1945) anticipated it, and modern note-taking tools
re-invent it every decade. Logseq's documentation
(<https://discuss.logseq.com/t/the-difference-between-logseqs-block-embeds-and-block-references/8459>)
gives the cleanest one-sentence framing:

> A block reference is a window to another part of your database;
> a block embed is a portal.

We borrow that vocabulary directly.

### The three edge forms

| Form | What it looks like in a SKILL.md | Cost | Benefit |
|------|----------------------------------|------|---------|
| **Pure reference** ("window") | `**REQUIRED SUB-SKILL:** Use \`superpowers:test-driven-development\`.` | Runtime hop — model has to load the referenced skill on demand. Brief context switch. | Single source of truth. The referenced node can evolve without touching the referrer. |
| **Inline copy** ("portal-snapshot") | The referrer's body literally re-states the referenced content (e.g., copies the RED-GREEN-REFACTOR steps into its own body). | Duplication. When the source updates, the copy drifts silently. | Self-contained. The referrer can complete its job even if the referenced node is unreachable. |
| **Hybrid** | `Apply RED-GREEN-REFACTOR (defined in \`superpowers:test-driven-development\`) — write a failing test before any production code.` | Minimal duplication. | Reader gets enough context to act; can fetch the full version on demand. **Most common correct choice.** |

### The four edged-object types

The trade-off plays out differently for each kind of dependency:

1. **Skill ↔ Skill.** Cross-plugin or within-plugin methodology
   reuse. Example: a discipline skill that requires
   `superpowers:test-driven-development` before its own steps
   begin.
2. **Skill ↔ Script.** Executable capability dependency.
   Example: a body that runs `python scripts/aggregate_benchmark.py`
   after a multi-step eval — the script lives next to the skill,
   the skill body just invokes it.
3. **Skill ↔ Reference.** Passive document dependency, usually
   within the same skill. Example: `superpowers:systematic-debugging`
   pointing at `references/root-cause-tracing.md` for the deep
   procedure.
4. **Skill ↔ Project-level doc.** `CLAUDE.md`, `AGENTS.md`,
   GitHub issue body / comments. The most-overlooked edge.

### Five dimensions for picking a form

For each edge, weigh:

- **Stability of the referenced thing.** Volatile → reference
  (avoid drift). Anchor-stable → inline is fine.
- **Size of the referenced thing.** Large → reference (don't
  pollute the token budget). Small → inline is fine.
- **Critical-path autonomy of the referrer.** Must work even if
  the referenced thing is unreachable → inline. Can wait →
  reference.
- **Authority of the referenced thing.** It's the canonical
  source → reference (don't fork). It's a helper → inline is
  fine.
- **Edge frequency in one flow.** A procedure returns to the
  same dependency many times → modest inlining reduces
  context-switching. Single call → reference.

### Anthropic's hard constraint: one level deep

The Anthropic best-practices doc
(<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>)
states explicitly:

> Keep file references one level deep from SKILL.md. Avoid
> deeply nested reference chains. Claude may partially read
> files when they're referenced from other referenced files.

This is a **fidelity** constraint, not just a style preference.
A reference chain of `SKILL.md → references/foo.md →
references/bar.md` will see `bar.md` partially read at best.
Practical consequences:

- A `references/X.md` may **not** chain into another
  `references/Y.md` and expect the model to follow.
- If you find yourself wanting a chain, you almost certainly
  want either (a) inline `Y` into `X`, or (b) promote `X` to a
  separate skill that can reference `Y` as its own SKILL.md.

The same constraint, in spirit, applies to skill-to-skill
chains: a skill body that invokes
`superpowers:executing-plans` can rely on it invoking
`superpowers:subagent-driven-development` directly, but a
SKILL.md that depends on a four-skill transitive chain holding
together is fragile. State the full chain explicitly in the body
if it matters.

### Cross-skill references always carry the namespace prefix

```markdown
# ✅
**REQUIRED SUB-SKILL:** Use `superpowers:test-driven-development`
when writing the failing test for this card.

# ❌ — ambiguous, will not auto-discover the right skill
**REQUIRED SUB-SKILL:** Use `test-driven-development`.
```

The prefix is `<plugin-name>:<skill-name>`. Even within-plugin
references should keep the prefix — it costs nothing and keeps
behavior consistent when one of these skills is invoked from a
downstream repo where multiple plugins are loaded.

### How the four reference libraries actually choose

The same five dimensions explain the strategic differences across
the libraries we surveyed:

- **superpowers** uses **pure reference** almost exclusively.
  `REQUIRED SUB-SKILL:` markers point at canonical methodology
  skills (`test-driven-development`, `systematic-debugging`).
  No skill ever inlines another skill's body. Dimension that
  drove the choice: **authority** — TDD is canonical, must not
  fork.
- **gstack** uses **inline copy** heavily — every skill's body
  starts with a 70-line preamble injected via a template
  (`SKILL.md.tmpl`). Same writing-style block also injected
  everywhere. **This is the textbook anti-pattern**: the
  referenced thing is volatile (gets edited often) AND large
  AND not on the critical path of any one skill. Pure-reference
  via a hook would be correct.
- **ljg-paper-flow** uses **runtime fan-out reference** — for
  each input, the body says "spawn a subagent that invokes
  `ljg-paper`, then `ljg-card -c`." This is transclusion at
  execution time: the referenced skills' content never enters
  the parent's context. Right choice when the referenced
  skills are large and used many times in one flow.
- **Anthropic example-skills** uses **size-based switching** —
  short tables stay inline in `SKILL.md`; long API references
  go to `references/<topic>.md` linked by name. The clearest
  application of the "size" dimension above.

### Pipelining (fan-out / fan-in) when you genuinely need
runtime composition

When a skill has to run another skill across N independent
inputs, `ljg-paper-flow`'s pattern is the cleanest expression:

```markdown
For each input X:
  1. Dispatch an `Agent` subagent (subagent_type: general-purpose).
  2. The subagent should invoke `Skill` with `ljg-paper`,
     passing X.
  3. After ljg-paper produces the .org file, the same subagent
     invokes `Skill` with `ljg-card -c` to render a card.
  4. The subagent reports back when both artifacts exist.

After all subagents complete:
  - Aggregate the artifacts into a single index.
  - Report the index path back to the user.
```

### Hard limit: subagents cannot spawn subagents

Per `MULTI_AGENT_DEVELOPMENT.md` (and explicit in the Claude Code
docs): a subagent invoked via `Agent` cannot itself invoke
`Agent`. **Your skill cannot rely on nested orchestration**:

- Top-level session can spawn N subagents. ✅
- Each subagent can invoke `Skill` to load any number of skills. ✅
- Subagents cannot spawn further subagents. ❌

If a subagent's task seems to need further decomposition
mid-flight, the correct escalation is to surface it back through
shared state (a card body, a PR comment, a status field) rather
than try to spawn a sub-subagent.

### Academic anchors specific to edge materialization

- **Transclusion theory** — Ted Nelson, Project Xanadu (1960s);
  Vannevar Bush, "As We May Think" / Memex (1945).
- **Logseq's "window vs portal"** —
  <https://discuss.logseq.com/t/the-difference-between-logseqs-block-embeds-and-block-references/8459>.
  The cleanest informal definition.
- **Roam Research's four-tier system** (reference / embed /
  text / alias) — the only widely-deployed system that
  enumerates edge forms explicitly.
- **Single-source publishing / DITA / DocBook** — the industrial
  precedent for "store once, transclude many" in technical
  authoring.
- **`Agent Skills for Large Language Models`**
  (Xu & Yan, 2026 — <https://arxiv.org/abs/2602.12430>):
  > Skills may depend on other skills, tools, or external
  > services, and a dependency graph should be maintained and
  > audited for known vulnerabilities, similar to dependency
  > scanning in npm or pip.

  **This is the first primary source we've seen that names skill
  edges as a dependency graph and treats them as a first-class
  engineering concern (security, audit).** It is the academic
  cover for treating this section as a real engineering
  surface, not just authoring style.

---

## Frontmatter discipline

### The minimum spec

Per <https://agentskills.io/specification> and
<https://code.claude.com/docs/en/skills.md>:

```yaml
---
name: skill-name-with-hyphens
description: Use when [specific triggering conditions and symptoms]
---
```

- **`name`**: letters, numbers, hyphens only. **No** parentheses,
  spaces, slashes, underscores. Must match the skill's directory
  name.
- **`description`**: third person, ideally starts with "Use
  when ...". This is what the model sees in the available-skills
  list and matches against the user prompt.
- **Description char cap is platform-dependent**:
  - **Claude Code** caps the **combined** `description` +
    `when_to_use` at **1,536 chars** in the skill listing (per
    <https://code.claude.com/docs/en/skills.md>, 2026).
  - **Codex** publishes no per-skill cap; the only documented
    constraint is an aggregate budget of ~8,000 chars / 2% context.
  - **agentskills.io** community spec recommends 1,024 chars.
  - **Defensive rule for this repo**: keep `description` alone
    under 1,024 chars (cross-platform safe); use `when_to_use` to
    spend the additional 512-char CC headroom on extended trigger
    phrases that don't ride into the matcher description on Codex.

### `description = WHEN, not WHAT`

This is the single most load-bearing rule in skill authoring. It
comes from Anthropic's own empirical finding documented inside
`superpowers:writing-skills`:

> When a description summarizes the skill's workflow, Claude may
> follow the description instead of reading the full skill
> content. A description saying "code review between tasks"
> caused Claude to do ONE review, even though the skill's
> flowchart clearly showed TWO reviews [...] When the description
> was changed to just "Use when executing implementation plans
> with independent tasks" (no workflow summary), Claude correctly
> read the flowchart and followed the two-stage review process.

The mechanism is simple: every word of workflow you put in the
description is a word the model can substitute for the body. The
body becomes documentation the model skips.

#### Concrete examples

| ❌ Wrong | ✅ Right |
|---------|---------|
| `Use when executing plans — dispatches subagent per task with code review between tasks` | `Use when executing implementation plans with independent tasks in the current session` |
| `Use for TDD — write test first, watch it fail, write minimal code, refactor` | `Use when implementing any feature or bugfix, before writing implementation code` |
| `Decomposes a design doc into INVEST-shaped GitHub issues with vertical slices and a card schema` | `Use when the architect brings a design doc, spec, or multi-point requirement that needs to be turned into GitHub Project cards` |

If you find yourself writing verbs like "dispatches", "validates",
"transforms", "computes" in a description — stop. You're
describing the body. Rewrite as triggering conditions.

### Triggering symptoms over abstract intents

Descriptions match the user's **prompt vocabulary**, not the
domain's vocabulary. Embed the symptoms a user would actually
type:

```yaml
# ❌ too abstract — the user never says "race condition"
description: Use when async tests have race conditions

# ✅ symptoms the user actually types
description: Use when tests are flaky, hang, time out, or pass/fail inconsistently
```

Concretely: for a board-management skill, descriptions should
embed phrases a user actually types — "claim card", "what should
I work on", "decompose this", "today's work", a literal
`[board-card:#N]` token — not the domain abstraction "manage
GitHub Project state machine." The matcher fires on the user's
vocabulary, not the architect's.

### Three-tier frontmatter discipline

Frontmatter fields fall into three tiers. The tier determines
whether they are safe to use, what they cost, and whether they
break cross-platform parity. Every SKILL.md authored in this repo
MUST classify its frontmatter against this discipline.

#### Tier 1 — Portable subset (behavior-defining, both platforms)

Only **two fields** qualify:

| Field | Use |
|-------|-----|
| `name` | Skill identifier; defaults to dir name on CC, but always set explicitly. |
| `description` | The matcher Claude / Codex use to decide when to invoke. Empirically the single most load-bearing field. |

**Skill behavior MUST be expressible using only Tier 1.** If your
skill's correctness depends on a Tier 2 field, the skill is
Claude-Code-only — declare that explicitly in the body's overview.

#### Tier 2 — CC-only spec fields (additive UX, both-platforms-safe)

The Claude Code skills spec
(<https://code.claude.com/docs/en/skills.md>) defines **11
additional fields** beyond `name` / `description`. They are part
of an **official spec**, not anti-pattern A4 inventions — Codex's
parser silently ignores them, but they are NOT swallowed by CC.
Use them as **additive UX enhancements** that improve the
human-driven invocation experience without affecting body
behavior.

| Field | What it controls | Use it for |
|-------|------------------|-----------|
| `when_to_use` | Additional trigger phrases appended to `description` | Listing trigger vocabulary (`[board-card:#N]`, "claim card", "what should I work on") without bloating the primary description. |
| `argument-hint` | Autocomplete placeholder shown after `/<skill> ` | Sub-command type-hint UX. Examples: `[card-number]`, `"[optional context]"`. **Defensive quoting**: wrap values containing `:` `,` `*` in double quotes — root cause of the now-fixed [#22161](https://github.com/anthropics/claude-code/issues/22161) crash. |
| `arguments` | Named positional arguments | Body uses `$<name>` substitution (`$card_number` reads cleaner than `$0`). On Codex, `$card_number` is a literal string — **body must work in both modes**, e.g., reference `$ARGUMENTS` as fallback. |
| `disable-model-invocation` | `true` = only user can invoke | Skills with side effects you don't want Claude triggering autonomously: `/deploy`, `/migrate`. |
| `user-invocable` | `false` = hide from `/` menu | Atomic reflex-skills users don't drive directly (`board-canon`, `enforcing-pr-contract`). Hyphenated form. **`user_invocable` (underscore) is an ljg-skills typo that gets silently ignored.** |
| `allowed-tools` | Tools auto-approved while skill active | Lock down to a specific tool set for safety. Anthropic / superpowers / ljg-skills use this 0% of the time. gstack uses it 100%. Don't cargo-cult it. |
| `model` | Model override for this turn | Force a specific model (`claude-opus-4-7`, `inherit`, etc). Reset to session default after the turn. |
| `effort` | Effort level override | Force `low` / `medium` / `high` / `xhigh` / `max` for this skill's turn. |
| `context: fork` | Fork into subagent context | When the skill is a self-contained task that doesn't need conversation history. Pairs with `agent`. |
| `agent` | Subagent type when forking | `Explore`, `Plan`, `general-purpose`, or any `.claude/agents/<name>`. |
| `hooks` | Skill-lifecycle-scoped hooks | Per-skill PreToolUse / PostToolUse / Stop. See <https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents>. |
| `paths` | Glob limiting auto-trigger | Skill triggers only when working with matching files. |
| `shell` | `bash` (default) / `powershell` | PowerShell requires `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`. |

**Tier 2 cross-platform contract**: a skill using Tier 2 fields
MUST behave correctly on Codex despite those fields being ignored.
Concretely, never have body logic that depends on `arguments:`
named substitution alone — always provide an `$ARGUMENTS` fallback
path. Never depend on `paths:` constraining when the skill fires —
write trigger discipline into `description` / `when_to_use`.

#### Tier 3 — Anti-pattern A4 (forbidden)

Any field NOT in CC's spec AND NOT in Codex's spec gets dropped by
**both** runtimes. Examples seen in the wild:

```yaml
# ❌ Tier 3 — silently ignored everywhere
triggers: [...]
voice-triggers: [...]
preamble-tier: ...
benefits-from: ...
version: v0.1.0
layer: atomic
type: reference
mode: both
bounded-context: board
```

**Project-specific metadata (version + 4 dimensions) lives in a
sibling `.skill-meta.yaml` file, not in frontmatter.** See § "
board-superpowers metadata convention" below.

### board-superpowers metadata convention

This repo treats each skill as a **mini sub-project**: it has its
own version, its own taxonomic position, and its own platform
target. To avoid Tier 3 anti-patterns, these dimensions live in a
sibling `<skill-dir>/.skill-meta.yaml` file — **not** in the
SKILL.md frontmatter.

```yaml
# skills/board-canon/.skill-meta.yaml
version: v0.1.0           # semver; bump per skill on each behavior change
layer: atomic             # entry / molecular / atomic — graph position
type: reference           # technique / pattern / reference / discipline
mode: both                # claude-code-only / codex-only / both
bounded-context: board    # board / session / bootstrap / audit / spec
```

Schema:

| Field | Required | Enum | What it anchors |
|-------|----------|------|-----------------|
| `version` | Yes | semver string | Skill's independent version (mono-repo sub-project model). Bump on any behavior change to the SKILL.md body or its references/. |
| `layer` | Yes | `entry` / `molecular` / `atomic` | Position in the skill graph (per § "Skill graph"). Determines body length budget + what the skill is allowed to depend on. |
| `type` | Yes | `technique` / `pattern` / `reference` / `discipline` | Body skeleton + testing regime. Pattern → Skeleton A; reference → Skeleton B; pipeline → Skeleton C; discipline → pressure tests. |
| `mode` | Yes | `claude-code-only` / `codex-only` / `both` | Platform compatibility. Determines what frontmatter fields are safe and whether body can name CC tools directly. |
| `bounded-context` | Yes | `board` / `session` / `bootstrap` / `audit` / `spec` | DDD bounded context (per `docs/architecture/0003-domain-model/02-bounded-contexts.md`). |

Why a sibling file instead of frontmatter:

- **Tier 3 (A4) compliance** — runtime parsers ignore non-spec
  frontmatter fields silently. Putting metadata there looks like
  behavior but isn't.
- **Zero token cost at runtime** — `.skill-meta.yaml` is never
  loaded into the skill invocation context. The model doesn't need
  layer / type / mode to use the skill correctly; only the
  maintainer / CI needs them.
- **CI-checkable single source of truth** —
  `scripts/verify-skill-metadata.sh` validates that every yaml
  matches the canonical `SKILLS.md` catalog and that no field
  drifts.
- **SPOT-clean** — `SKILLS.md` catalog can omit these fields
  (they live in yaml), reducing inline duplication.

A change to a skill's behavior MUST bump `version` in the yaml in
the same PR. A change that **only** clarifies wording without
shifting behavior may keep `version` unchanged but MUST be noted
in the PR body.

---

## SKILL.md body structure

There is no single mandated skeleton, but four broadly compatible
shapes have emerged. Pick one and follow it consistently within a
related family of skills.

### Skeleton A — Discipline skill (superpowers style)

Use for skills that enforce a rule the model is tempted to skip
under pressure. Examples: `superpowers:test-driven-development`,
`superpowers:verification-before-completion`,
`superpowers:requesting-code-review`.

```markdown
---
name: ...
description: Use when ...
---

# Skill Name

## Overview
What is this. Core principle in 1–2 sentences.

## When to Use
- Symptom 1
- Symptom 2
When NOT to use: ...

## The Iron Law
One bolded rule, framed so a model under pressure can't rationalize
around it.

## Process
Numbered steps. Use a `dot` flowchart only if there's a real
decision point.

## Common Rationalizations
| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| ... | ... |

## Red Flags — STOP and Start Over
- Trigger 1
- Trigger 2
**All of these mean: ...**

## Verification Checklist
- [ ] ...
```

### Skeleton B — Reference / output skill (Anthropic style)

Use for skills that produce a complex artifact (a `.docx`, a
Claude API integration, a state-machine transition). Examples:
Anthropic `docx`, Anthropic `claude-api`.

```markdown
---
name: ...
description: Use when ...
---

# Skill Name

## Overview
1–2 sentences on what the skill does.

## Quick Reference
A scannable table — capability matrix or workflow selector.

## Workflows
### Workflow 1
Numbered steps. Inline minimal code. Heavy reference behind a
"see references/X.md" link.

### Workflow 2
...

## Common Mistakes
What goes wrong + fix.
```

### Skeleton C — Pipeline / orchestration skill (ljg-paper-flow style)

Use for skills that compose other skills. Examples:
`ljg-paper-flow` (per-input fan-out into `ljg-paper` and
`ljg-card`); `gstack:/autoplan` (one-shot multi-stage plan
review); Anthropic `skill-creator` (orchestrates eval +
grader + comparator subagents).

```markdown
---
name: ...
description: Use when ...
---

# Skill Name

## Overview
What this orchestrates and why a single skill (rather than two
manual steps) is the right shape.

## Steps
1. Invoke `superpowers:writing-plans` skill (REQUIRED SUB-SKILL).
2. For each item, dispatch an Agent subagent that:
   a. Invokes the per-item skill
   b. Waits for completion
   c. Reports back via `report_agent_job_result`
3. Aggregate the results and ...

## Failure modes
What to do when a sub-skill fails midway.
```

### Skeleton D — Personal cognitive skill (ljg style)

Use for skills that codify a way of thinking, often in mixed
language for personal use. Documented for completeness — not a
target shape for general-purpose plugins.

```markdown
---
name: ...
description: Use when ...
---

# 标题: 一句话标语

## 红线
1. 不能 ...
2. 不能 ...

## 执行
... 步骤 ...

## 品味准则
... 主观判断 ...
```

### Length budget

- **Target**: 200–400 lines for the SKILL.md body.
- **Hard cap**: 500 lines. Past that, you are forcing every
  invocation to pay an avoidable token cost.
- **Frequently-loaded skills** (entry-layer dispatchers, shared
  reference / schema skills): aim for under 200 lines. They
  ride into many sessions, so every line is paid for repeatedly.

If you bump the cap, the cost is real: every session that
triggers the skill pays the full body in tokens before the model
does anything useful. Check with `wc -l skills/<name>/SKILL.md`
during review.

### Flowcharts (`dot` blocks)

Use a `dot` flowchart **only** when there is a non-obvious
decision point or a loop where the model is likely to stop early.
Examples that earn their place:
`brainstorming/SKILL.md`, `subagent-driven-development/SKILL.md`,
`using-superpowers/SKILL.md`.

Do **not** use flowcharts for:

- Linear steps (use a numbered list).
- Reference material (use a table).
- Code (use a fenced code block).
- Generic labels like `step1`, `step2`, `helper3`.

If you do use one, follow the conventions in
`superpowers/writing-skills/graphviz-conventions.dot`.

### Voice and length per sentence

- **Imperative.** "Read the file." not "You should read the
  file."
- **Explain WHY** when a step looks arbitrary. The model under
  pressure follows reasoning more reliably than rules. Heavy-handed
  ALL-CAPS `MUST` / `NEVER` is a yellow flag — see
  `skill-creator/SKILL.md`'s "Writing Style" section.
- **No first person.** The skill body is an instruction to a
  future model, not a memoir. "We" / "I" / "my" are wrong here.
- **No narrative.** "In session 2025-10-03, we discovered ..." is
  a project log, not a skill.

---

## Within-skill layering: progressive disclosure via `references/`

This is the **within-node** companion to the graph-level
"Skill graph: edge materialization" section above. There the
question was "between two nodes, embed or point?"; here it is
"within one node, what stays in `SKILL.md` and what moves to
`references/<topic>.md`?"

The single rule: **anything over ~100 lines that the body doesn't
need on every invocation moves to `references/<topic>.md`**.
Examples that exemplify the cut:

- `systematic-debugging/SKILL.md` keeps the methodology in the
  body, splits the three supporting techniques
  (`root-cause-tracing.md`, `defense-in-depth.md`,
  `condition-based-waiting.md`) into siblings, and links them by
  name when relevant.
- `using-superpowers/SKILL.md` keeps the matcher and the priority
  rules in the body, splits the per-platform tool-name maps
  (`codex-tools.md`, `copilot-tools.md`, `gemini-tools.md`) into
  references read only when running on that platform.
- `ljg-card/SKILL.md` is the extreme: 100-line body that does
  pure dispatch, with all the heavy mode-specific rules in
  `references/mode-{long,infograph,multi,visual,comic,whiteboard}.md`.

### Linking conventions

- **Always link by relative path or skill-internal name**, never
  by `@`.

  ```markdown
  # ✅ explicit lazy reference
  See `references/state-machine.md` for the full transition table.

  # ❌ never use @ — it auto-loads and consumes 200k+ context
  @references/state-machine.md
  ```

- **Within the body, name the reference file when relevant**, so
  the model knows whether to crack it open. "When in doubt about a
  state transition, read `references/state-machine.md`." is far
  better than "There is more documentation in references/."

### Sub-directories under `references/` are usually a smell

If you find yourself wanting `references/foo/bar.md`, you almost
certainly want a separate skill instead. The flat namespace under
`references/` is the convention. Single counter-example seen in
the wild: large API references (e.g., `pptx/`-style skills bundle
multiple deep references — but that's hundreds of lines per
file).

---

## Within-skill resource layout: scripts, agents, assets

This section is the within-node companion to "Skill graph: edge
materialization." There the question was "embed or point at
another node?"; here it is "given that a node has its own
content, where does each piece live?"

### The 50-line rule for inline code

- **< 50 lines, single language, single purpose** → keep it
  inline in the SKILL.md body inside a fenced code block.
- **≥ 50 lines, or reusable across invocations, or
  multi-language** → move it to `scripts/<name>.{sh,py,js}` and
  invoke it from the body.

This keeps the body scannable while concentrating maintenance in
files that can be tested and shellchecked independently. See the
project-wide rule in `AGENTS.md` § Maintaining scripts: every
script gets a header comment, strict mode, and `shellcheck -x`.

### `scripts/` is for AI-callable tools, not user CLIs

Scripts under a skill's `scripts/` directory are **invoked by the
skill body**, not exposed to the user as standalone tools.
Examples:

- `brainstorming/scripts/start-server.sh` — the body says "run
  `bash start-server.sh` to bring up the local UI"; the user
  never runs it directly.
- `skill-creator/scripts/aggregate_benchmark.py` — the body says
  "run `python -m scripts.aggregate_benchmark` after the eval
  finishes"; never user-facing.

If you need a user-facing CLI, it goes in the **plugin's
top-level `scripts/`** (referenced via `${CLAUDE_PLUGIN_ROOT}/
scripts/<name>.sh` from any skill body), not in a skill's
`scripts/`. The split keeps user-facing tooling stable across
skill churn.

### `agents/<role>.md` — subagent role prompts

When a skill spawns a subagent and needs to give it a substantial
role prompt, put the prompt in `agents/<role>.md` and have the
body reference it:

```markdown
Spawn an `Agent` subagent (subagent_type: general-purpose) and
have it follow `agents/grader.md` to score each output.
```

The subagent's first action will be to read `agents/grader.md`.
Examples:

- `skill-creator/agents/{grader,analyzer,comparator}.md`
- `skill-creator/agents/grader.md` is **only** instructions for
  the subagent — no preamble, no "you are an AI assistant"
  boilerplate; it is text the subagent will receive.

Two community conventions exist for this layout:

| Convention | Used by | Notes |
|------------|---------|-------|
| `agents/<role>.md` | Anthropic example-skills (newer) | Mirrors Codex's `.codex/agents/` layout — converges with cross-platform vocabulary. **Prefer this for new skills.** |
| `<role>-prompt.md` (flat) | superpowers (`subagent-driven-development/{implementer,spec-reviewer,code-quality-reviewer}-prompt.md`) | Older convention. Don't introduce new instances; don't churn existing ones. |

### `assets/` — output templates and static resources

Use for things the skill **emits** as output, or static binaries
the skill processes. `docx/assets/` (Word templates), `ljg-card/
assets/capture.js` (Puppeteer screenshot helper). board-
superpowers will likely not need this directory — our outputs
are GitHub artifacts, not files the plugin generates.

### `evals/` — Anthropic eval framework

Use only when:

- The skill produces a verifiable output (file transform, schema
  validation, code generation), AND
- You're willing to maintain the eval harness across iterations.

Good candidates for `evals/`: schema-or-format skills (a
state-machine validator, a card-shape generator, a doc
templater) where adherence is mechanically gradable. Discipline
skills should use the pressure-test approach in §Regime 1
instead — adherence under pressure is not what `evals/` measures.

---

## Cross-platform skill writing

This repo is dual-platform per `PLUGIN_DEVELOPMENT.md`. Skills
must work on both Claude Code and Codex CLI unless a skill
explicitly self-tags as platform-only.

### The portable subset

A skill is platform-portable if it:

- Uses only `name` and `description` in frontmatter.
- Uses generic prose for tool calls ("read the file at X", "run
  `bash scripts/foo.sh`") rather than naming a Claude tool by its
  exact name (`Read`, `Bash`).
- References cross-skill dependencies with the namespace prefix
  (works the same on both platforms).
- Does not assume `${CLAUDE_PLUGIN_ROOT}` — instead, scripts
  resolve their own paths via `BASH_SOURCE` (this abstraction
  belongs in `scripts/lib/common.sh`, not in the skill body).

### Tool-naming guidance

| Generic prose | Claude-Code-specific |
|---------------|----------------------|
| "Read the file at `<path>`" | "Use the `Read` tool on `<path>`" |
| "Run `bash scripts/foo.sh`" | "Use the `Bash` tool: `bash scripts/foo.sh`" |
| "Spawn a subagent to ..." | "Use the `Agent` tool with `subagent_type: general-purpose` to ..." |

**Default to generic prose.** Only name a Claude tool when the
skill is explicitly tagged Claude-Code-only (and the body says
so).

### Tagging a platform-only skill

If a skill genuinely cannot be portable, declare it in the body's
overview:

```markdown
## Overview

> **Platform: Claude Code only.** This skill uses agent teams
> (`SendMessage`, `TeamCreate`) which are not available on Codex
> CLI. See `MULTI_AGENT_DEVELOPMENT.md` for the cross-platform
> alternatives.
```

This makes the constraint visible to a downstream maintainer
reading the skill cold and to a Codex user puzzling out why it
isn't firing.

### `agents/openai.yaml` for Codex display metadata

If you want richer Codex-side display (icon, brand color,
default prompt) for a skill that already has a `SKILL.md`, add
`agents/openai.yaml` alongside the SKILL.md per
<https://github.com/openai/skills/blob/main/skills/.system/skill-creator/references/openai_yaml.md>.
The `SKILL.md` stays the source of truth for behavior; the YAML
just shapes Codex's UI.

---

## Testing skills

Skills are code that runs against a model. They need tests. Two
distinct regimes apply, depending on the skill type.

### Regime 1 — Pressure testing (discipline skills)

For skills that enforce a rule (TDD, verification before
completion, the board protocol), follow superpowers' RED-GREEN-
REFACTOR cycle laid out in
`superpowers:writing-skills`:

1. **RED — Run a baseline.** Write 3+ pressure scenarios (time
   pressure, sunk cost, tired-end-of-day phrasing). Run each
   against a fresh subagent **without** the skill loaded.
   Document the rationalizations the agent uses verbatim.
2. **GREEN — Write the minimal skill.** Write the SKILL.md
   addressing exactly the rationalizations you saw. No
   speculative additions.
3. **REFACTOR — Close loopholes.** Re-run the scenarios with the
   skill loaded. Capture new rationalizations. Add explicit
   counters. Iterate until the agent complies under all combined
   pressures.

Concrete examples in
`superpowers/systematic-debugging/test-{academic,pressure-1,2,3}.md`
— each is a saved pressure test that future maintainers can
re-run.

### Regime 2 — Eval matrix (output skills)

For skills that produce a verifiable artifact (a card body, a PR
description, a state transition), follow Anthropic's `skill-
creator` pattern:

1. Write 3–5 realistic test prompts in `evals/evals.json`.
2. Run each prompt twice — once with the skill, once without
   (baseline). Save outputs to `evals/iteration-N/eval-K/{with_skill,without_skill}/`.
3. Score each output against named assertions (use a grader
   subagent reading `agents/grader.md`).
4. Aggregate to `benchmark.json`. Inspect for non-discriminating
   assertions (always-pass / always-fail), high-variance evals
   (likely flaky), token / time tradeoffs.
5. Iterate the skill, re-run, compare across iterations with
   `--previous-workspace`.

Use this for skills whose output adheres to a checkable schema
or shape (e.g., a card-shape generator where INVEST adherence is
mechanically gradable, a doc templater where required sections
are checkable).

### When NOT to test exhaustively

- Pure reference skills (a schema or API doc) where the test is
  "does an agent retrieve and apply the right rule" — a single
  retrieval scenario is enough.
- Skills that compose other already-tested skills, where the
  pipeline assembly is the only new logic — test the assembly,
  not the constituent skills.

But **do test before shipping**. An untested skill in a downstream
user's repo is a worse failure mode than a missing skill, because
the model will still try to follow it.

---

## Anti-patterns (community antipatterns to avoid)

These are real failure modes observed in the four reference
libraries. Avoid them in any skill authored against this guide.

### A1. Workflow-summarizing descriptions

**Symptom:** description says what the skill does step by step.

**Failure mode:** model reads description, skips body. (Anthropic
empirically demonstrated this.)

**Fix:** rewrite as triggering conditions only. Move workflow
into the body.

### A2. Preamble injection in every SKILL.md

**Symptom:** every skill's body starts with 50–100 lines of
identical bootstrap (env detection, CWD juggling, telemetry
shim) before the actual procedure begins.

**Where seen:** gstack injects `## Preamble (run first)` 70+
bash lines into every `SKILL.md` (seen in `office-hours/SKILL.md`,
`qa/SKILL.md`, etc.).

**Failure mode:** every skill invocation pays the preamble token
cost. The "skill description IS behavior" contract is diluted by
70 lines of noise. Maintenance updates to the preamble require
touching N skills.

**Fix:** move bootstrap into a hook (`hooks/session-start.sh`)
or a script called once on first invocation
(`scripts/check-deps.sh`). The plugin layer is the right home
for cross-skill setup; the SKILL.md body is the wrong one.

### A3. Skill-style writing inside SKILL.md that's actually a
README

**Symptom:** SKILL.md contains "## Installation", "## Project
background", "## Changelog" sections.

**Failure mode:** the model reads installation steps every time
the skill triggers. The user-facing overview belongs in
`README.md`, not in the skill.

**Fix:** keep SKILL.md to procedure + reference. Anything a human
reads to decide "should I install this plugin" goes in
`README.md`.

### A4. Custom non-spec frontmatter (= Tier 3 in the three-tier discipline)

**Symptom:** frontmatter contains fields not in
<https://agentskills.io/specification> AND not in
<https://code.claude.com/docs/en/skills.md>.

**Where seen:** gstack's `triggers:`, `voice-triggers:`,
`preamble-tier:`, `benefits-from:`, ljg's `user_invocable:`
(underscore is wrong; only the hyphenated `user-invocable` is
spec).

**Failure mode:** silently parsed and discarded by the runtime.
Looks like behavior; isn't.

**Fix:** if you need to express something (e.g., "this skill
depends on another"), state it in the body with a `**REQUIRED
SUB-SKILL:**` marker. If a real spec extension is needed, add it
to <https://agentskills.io/specification> upstream first.

**Note — Tier 2 fields are NOT A4 violations.** Fields like
`argument-hint`, `arguments`, `when_to_use`, `user-invocable`,
`allowed-tools`, `model`, `effort`, `context: fork`, `agent`,
`hooks`, `paths`, `shell` are **in CC's official spec**. Codex
silently ignores them, but CC honors them. They count as
"additive UX enhancements," not as anti-pattern. See § "Three-tier
frontmatter discipline" for the full classification.

**Note — board-superpowers metadata is NOT in frontmatter.**
Project-specific dimensions (version + layer + type + mode +
bounded-context) live in `<skill-dir>/.skill-meta.yaml`,
exactly to avoid this trap. See § "board-superpowers metadata
convention" for the schema.

### A5. Skill body in mixed language for portability claim

**Symptom:** SKILL.md body is in Chinese (or another non-English
language), but the skill is meant to be reusable across users.

**Where seen:** ljg-skills bodies are deliberately Chinese
because they're personal — this is a feature in their context.
But it makes the skill non-portable.

**Failure mode:** users / models in other locales can't follow
the body.

**Fix:** for any skill meant to be reused across users / locales,
**English body** is mandatory. Locale-specific notes (e.g., a
Chinese maintainer's mental model) belong in commit messages, PR
descriptions, or a separate `notes-zh.md` outside the SKILL —
not inside the SKILL.md the model reads.

### A6. Repeating a cross-referenced skill's body inline

**Symptom:** SKILL.md re-explains TDD inline rather than linking
`superpowers:test-driven-development`.

**Failure mode:** skill bloat; updates to the canonical skill
don't propagate.

**Fix:** state the requirement, link the canonical skill, write
only what's specific to your skill's context on top.

### A7. Auto-loading references via `@` syntax

**Symptom:** SKILL.md says `@references/foo.md` instead of "see
references/foo.md".

**Failure mode:** every invocation loads the reference
immediately, defeating progressive disclosure. 200k+ context
budget eaten before the model needs it.

**Fix:** explicit prose link only. The model is competent enough
to read a file when the body tells it to.

### A8. Underscore vs hyphen typos in frontmatter

**Symptom:** `user_invocable: true` instead of `user-invocable:
true`.

**Failure mode:** silently ignored. The skill thinks it's
user-invocable; the runtime disagrees.

**Fix:** copy the canonical field names from
<https://agentskills.io/specification>. When in doubt, hyphen.

---

## Honest gaps in official docs

The following are **not** documented as stable contracts; design
accordingly. None of these block authoring skills today, but
each is a known unknown to re-check periodically.

- **Aggregate description budget.** Codex docs state the
  available-skills list is capped at "approximately 2% of the
  model's context window, or 8000 characters when the context
  window is unknown" — descriptions auto-shorten when many
  skills are installed. **No published mechanism for which
  descriptions get truncated first.** Keep descriptions tight
  defensively.
- **Per-description char cap on Codex.** No published cap. Claude
  Code's effective limit is 1024 chars total frontmatter (per
  agentskills.io). Treat 1024 as the universal ceiling.
- **`SKILL.md` body cap.** No platform publishes one. Empirical
  500-line target comes from superpowers' published guidance,
  not from any platform spec.
- **Cross-platform skill spec maturity.**
  <https://agentskills.io/specification> exists and is the
  closest thing to a cross-platform spec. It is community-driven,
  not platform-owned by Anthropic or OpenAI. Treat it as
  authoritative for the portable subset; treat platform-specific
  fields as platform-specific.
- **Codex `agents/openai.yaml` schema specifics.** Documented at
  <https://github.com/openai/skills/blob/main/skills/.system/skill-creator/references/openai_yaml.md>
  but the schema may evolve. Re-verify before adding new
  `openai.yaml` files.
- **Subagent + skill interaction.** When a subagent loads a
  skill via the `Skill` tool, does the skill's body count
  against the parent's context window or the subagent's? Both
  platforms' docs are silent. Treat as the subagent's
  context — but verify before depending on it for token-budget
  calculations. See `MULTI_AGENT_DEVELOPMENT.md` § "Honest gaps"
  for the broader subagent-context-isolation question.

---

## Maintenance discipline for this doc

- All URLs verified **2026-04-27**. **Re-verify when modifying
  related code.** A broken or moved canonical URL is a
  load-bearing fact and must be patched in this PR, not deferred.
- When a new skill-authoring surface lands in either product
  (especially: new frontmatter field documented as stable, new
  bundled-resource directory convention, change to the
  description matcher), add a section here **before** the first
  board-superpowers skill uses it. This doc is leading, not
  trailing.
- When a contract from this doc changes (a frontmatter field
  renamed, a directory convention shifted, the spec at
  agentskills.io updated), update both the section here AND any
  dependent skills in board-superpowers in the same PR.
- This doc is referenced from `AGENTS.md`'s "Maintaining skills"
  section. Keep it digestible — agents read it cold.
- When promoting an "Honest gap" to a documented contract (e.g.,
  a body-length cap finally documented upstream), move the entry
  from the gaps section to the relevant body section with a
  note: "Documented upstream <date>; previously empirical."

---

## See also

- `PLUGIN_DEVELOPMENT.md` — base plugin contracts (manifest,
  marketplace, hooks, MCP, settings) for both CC and Codex.
  Skills are the largest behavior surface those contracts
  carry.
- `MULTI_AGENT_DEVELOPMENT.md` — multi-agent / subagent /
  orchestration contracts. Required reading before designing a
  skill that spawns subagents (Skeleton C / pipeline skills).
- `AGENTS.md` — board-superpowers developer guide.
  "Maintaining skills" section is the operational checklist that
  complements this doc.
- `README.md` — end-user overview.
- Reference implementations read in full while drafting:
  - `anthropics/skills` (`skill-creator`, `docx`, `claude-api`)
  - `obra/superpowers` (`writing-skills`,
    `test-driven-development`, `systematic-debugging`,
    `brainstorming`, `subagent-driven-development`,
    `executing-plans`, `using-superpowers`)
  - `gstack` (`office-hours`, `qa`, `codex`, `autoplan`,
    `investigate`)
  - `ljg-skills` (`ljg-card`, `ljg-paper`, `ljg-paper-flow`,
    `ljg-roundtable`, `ljg-word`, `ljg-skill-map`)
- Primary sources cited for the skill-graph framing:
  - Anthropic, *Skill authoring best practices* (2026) —
    <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
  - *agentskills.io specification* (2026) —
    <https://agentskills.io/specification>
  - Anthropic Engineering, *Equipping agents for the real world
    with Agent Skills* —
    <https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills>
  - Jiang et al., *SoK: Agentic Skills — Beyond Tool Use in LLM
    Agents* (2026) — <https://arxiv.org/abs/2602.20867>
  - Wang et al., *SkillX: Automatically Constructing Skill
    Knowledge Bases for Agents* (2026) —
    <https://arxiv.org/html/2604.04804v2>
  - Carta et al., *HERAKLES: Hierarchical Skill Compilation for
    Open-ended LLM Agents* (2025) —
    <https://arxiv.org/abs/2508.14751>
  - Xu & Yan, *Agent Skills for LLMs: Architecture, Acquisition,
    Security, and the Path Forward* (2026) —
    <https://arxiv.org/abs/2602.12430>
  - Wang et al., *Voyager: An Open-Ended Embodied Agent with
    Large Language Models* (TMLR 2024) —
    <https://arxiv.org/abs/2305.16291>
  - Brad Frost, *Atomic Design* (2013) — UI-side antecedent for
    the entry / molecular / atomic layering.
  - Logseq community docs, *Block embeds vs block references*
    — <https://discuss.logseq.com/t/the-difference-between-logseqs-block-embeds-and-block-references/8459>
  - Obsidian Help, *Link to blocks* —
    <https://help.obsidian.md/How+to/Link+to+blocks>
  - Ted Nelson, Project Xanadu (1960s) and Vannevar Bush, *As
    We May Think* (1945) — origins of transclusion.
