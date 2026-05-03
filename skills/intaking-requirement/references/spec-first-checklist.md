# Spec-first checklist — intaking-requirement reference

Read this file at intake **Step 3** to verify spec preconditions before a
card is created — after scope-shape-judgment.md decided shape and before
intake-decision-tree.md picks a sibling skill.

Apply the six-row table: run each row's trigger check against the requirement.
If any trigger fires, the named spec artifact MUST land first (separate PR or
same-PR companion) before the card is created. If no row fires, proceed to
Step 4.

## Why "spec first"

The board contract assumes every card lands in a context where the architect's
reserved-power decisions (bounded-context boundaries, cross-plugin edges,
audit / autonomy / hook contracts) are already settled. A card that needs one
of those decisions made during implementation puts the Consumer session in an
architect role it does not have.

Spec-first eliminates that failure mode: the architect's decisions land first
(as ADRs, spec edits, or paired-PR companion changes), then the implementation
card claims the work.

## Six-row checklist

Run each row's trigger against the requirement. First row to fire sets the
action.

| # | Trigger | Artifact that must land first | Worked example |
|---|---------|------------------------------|----------------|
| 1 | Touches multiple bounded contexts (Board / Session / Bootstrap / Audit / Spec) | ADR or spec edit naming the cross-context contract | The audit-log governance card (Audit + Spec contexts): autonomy matrix + audit-log-schema spec landed first. |
| 2 | Adds a new cross-plugin edge (new `superpowers:*` or `gstack:/*` skill not yet in `SKILLS.md`) | `SKILLS.md` § "Cross-plugin edges" gains the row | The decomposing-into-milestones card: edges to `superpowers:writing-plans` and `gstack:/plan-eng-review` landed in SKILLS.md first. |
| 3 | Changes audit_log schema, action_id namespace, or autonomy matrix | Autonomy-matrix ADR + audit-log schema contract edited first | The audit-log governance card: autonomy matrix + audit-log-schema spec landed first. |
| 4 | Affects routing block or hook intent injection grammar (`INVOKE:` / `REASON:` markers) | Hook contracts spec edited first | Any new INVOKE target requires the spec edit before implementation. |
| 5 | Modifies host-local state layout (`~/.board-superpowers/` path conventions, file names, schema) | Config-schemas spec + path-conventions spec edited first | bootstrap v0.2.0: per-repo config split landed spec edits in same PR. |
| 6 | Spec-only work (the work IS the spec — landing an ADR, a feature row, a contract page) | None — the artifact is itself the spec | ADR-only PRs: the card body's Goal IS "land this spec". |

### Same-PR vs separate-PR

Rows 1-5 say "land first." The architect chooses:

- **Separate PR, sequenced**: spec PR lands; card is created against the
  merged spec; Consumer claims. Highest discipline; used when the spec change
  is shared across multiple downstream cards.
- **Same PR, paired**: spec edit + implementation land in one PR. Used when
  the spec change is local to one card and not shared.

Row 6 has no pre-card variant — the spec IS the artifact; the card body's
Goal is "land this spec."

### Anti-patterns

- **Discovering the spec edit mid-implementation**: Stop. Surface to architect.
  Route the spec edit back to intake. Resume the card after the spec lands.
- **Treating the change-impact matrix as a suggestion**: The matrix's "you
  must also update" column is binding for the same PR.
- **Backfilling spec after the fact**: Spec edits become archaeology. Catch
  them at intake.

## When docs/plans/<feature>/ is mandatory

The gitignored scaffolding directory is **mandatory** when:

- The card's AC includes a design A/B (architect lists options + leaning +
  Consumer picks).
- The intake produced brainstorming or eng-review artifacts.
- The decomposition produced 4+ cards (decomposition rationale needed).

It is **optional** for single-card intake with no design A/B and no extended
brainstorming artifact.

Lifecycle: delete `docs/plans/<feature>/` when the feature's last card lands.
Durable findings get promoted to the architecture spec in the PR that ships
the relevant card.
