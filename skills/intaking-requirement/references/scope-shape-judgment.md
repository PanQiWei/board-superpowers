# Scope-shape judgment — intaking-requirement reference

Read this file at intake **Step 2** to decide which structural level a fresh
requirement should land at. Apply the three tables below in order:

- **Table 1** — decide shape (cross-release roadmap / milestone-grouped /
  multi-card / single card).
- **Table 2** — pick the cross-card relationship mechanism if multiple cards
  are involved.
- **Table 3** — decide whether to hand the artifact to
  `board-superpowers:decomposing-into-milestones` and what entry conditions
  to attach.

After this file's tables fire, the next reads are:
- `spec-first-checklist.md` — at Step 3, once shape is "single card" or
  "multi-card", to verify spec preconditions.
- `intake-decision-tree.md` — at Step 4, once preconditions are clear, to
  pick the pre-card sibling skill.

## Primary-source vocabulary

The hierarchy in this file is anchored to four canonical primary sources
borrowed for structural shape only. Cadence assumptions (sprints, iterations,
fixed release cycles) are NOT inherited — AI orchestration collapses time
grain approximately 100× compared to human team baselines.

| Source | What it gives this file |
|--------|------------------------|
| Cohn, *Agile Estimating and Planning* (2005) — § "Planning Onion" | Six concentric horizons (strategy / portfolio / product / release / iteration / day). |
| Patton, *User Story Mapping* (2014) — § "The Big Picture" | Backbone activities → tasks → stories hierarchy. |
| Cockburn, *Crystal Clear* (2004) + c2 wiki — § "Walking Skeleton" | Lower bound for vertical slicing on a brand-new feature surface. |
| Denne & Cleland-Huang, *Software by Numbers* (2003) — § "Minimum Marketable Features" | Criterion for a correct milestone: coherent cards that deliver measurable value when shipped together. |

## Table 1 — Shape level for a fresh requirement

Rows are evaluated top-down; the first row whose triggers fire wins.

| Shape | Cohn horizon | Triggers — fire any one | Outcome |
|-------|--------------|------------------------|---------|
| **Cross-release roadmap** | portfolio | (a) Requirement crosses two or more plugin-version transitions; (b) names a release-gate or cross-version umbrella; (c) bundles features that will not all ship in one cycle. | Stop. Surface to Producer: "This is roadmap-level — a positioning doc or umbrella card belongs in the architecture spec first." Do NOT create cards yet. |
| **Milestone-grouped within a release-gate** | release | (a) Requirement names a coherent shipped-together unit; (b) cards together deliver Denne-MMF-shaped value (shipping any subset alone delivers strictly less); (c) cards span 2+ bounded contexts. | Use the umbrella-card-with-soft-`depends-on:` pattern. Route to `decomposing-into-milestones` with the umbrella card as anchor. |
| **Multi-card sharing a milestone** | release sub-batch | (a) Requirement adds 2-N independent capabilities; (b) INVEST Independence holds across candidate cards; (c) expected internal chunk count > 5 (empirical signal that single-card scope will reactively chunk). | Route to `decomposing-into-milestones`. |
| **Single card** | iteration | (a) Single user-visible / developer-visible capability; (b) Estimable as XS/S/M/L; (c) no cross-card design A/B requiring shared rationale; (d) belongs in one bounded context. | Direct card creation via this skill's § "Direct card creation". |

### The ">5 chunks" trigger rationale

This trigger is empirical. Cards that proceeded as "single card" and then
reactively chunked into 6-7 PRs each paid a separate review tax and kept
work-in-progress opaque to the architect. When intake estimates > 5 internal
chunks, upfront decomposition via `decomposing-into-milestones` is cheaper.

### Walking-skeleton hint for brand-new surfaces

When Table 1 routes to `decomposing-into-milestones` AND the requirement
targets a brand-new feature surface (no prior card / spec / SKILL has authored
functionality at this surface), attach an explicit hint to the handoff: "first
card should be a walking skeleton — smallest end-to-end implementation that
exercises every architectural layer." `decomposing-into-milestones` enforces
this hint via its vertical-slicing gate.

## Table 2 — Cross-card relationship mechanism

| Mechanism | Use when | Anti-pattern |
|-----------|----------|--------------|
| **GitHub Project Milestone field** | Cards form a coherent Denne-MMF group AND the architect wants explicit milestone-level reporting. Not currently used in this project — see § "Milestone field substitute". | Using milestones as topic tags. |
| **`depends-on:` chain** (hard) | One card cannot start until another finishes. Strict ordering. | Long chains (> 3) — that's a missed multi-card decomposition. |
| **`depends-on (soft):`** | One card prefers another to land first but can ship in either order. Binds a card to an umbrella without forcing strict ordering. | Treating soft-depends as schedule glue. |
| **Label** | Category / type tagging only (`type:feature`, `type:bug`, `size:M`). | Using labels to mean "v1 work" or "audit work" — that's the milestone field's job. |

### Milestone field substitute — umbrella card + soft depends-on

This project uses umbrella cards instead of the GitHub Milestone field. An
umbrella card declares the milestone's intent in its body; member cards bind
to it via `depends-on (soft): #<umbrella>`. The umbrella card itself is a real
card on the board (it can have AC and be claimed) but its primary role is
milestone anchoring.

Advantages over the GitHub Milestone field:
1. The umbrella card carries body content (scope boundary, "what's in / out").
2. The umbrella card participates in the governance pipeline (classify / audit
   applies to edits; milestone field changes have no action_id).

## Table 3 — When to invoke decomposing-into-milestones

| Trigger | Action | Note |
|---------|--------|------|
| Multi-capability requirement (Table 1 rows 2 or 3) | Route to `decomposing-into-milestones`. Attach walking-skeleton hint if brand-new surface. | The skill's INVEST + SPIDR pipeline produces N cards. |
| Requirement looks single-card-sized but architect wants sanity check | Optional handoff to `decomposing-into-milestones` in freeform mode. Routes back if artifact is < 30 lines. | Useful when scope feels uncertain. |
| Requirement has no clear capabilities (rambling design notes) | Do NOT route yet. Route to `superpowers:brainstorming` first. | `decomposing-into-milestones` needs a sharpened artifact. |
| Single card with clear AC | Skip `decomposing-into-milestones`. Use direct card creation. | For the card body shape, follow `board-superpowers:board-canon` § "Card body schema". |
| Pure refactor with no new capability | Skip entirely. INVEST gating doesn't apply; route to direct claim. | No user-visible / developer-visible value to test against. |

The boundary is sharp: `decomposing-into-milestones` owns INVEST + SPIDR +
sizing + the terminal Card body schema. This file owns "should the requirement
go through decomposition at all, and at what shape?" Do not cross the boundary
in either direction.
