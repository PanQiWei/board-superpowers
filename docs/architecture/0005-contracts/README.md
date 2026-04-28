# Contracts

> Single source of truth for every contract that crosses a
> board-superpowers component boundary. Script stdout shapes, exit
> codes, hook payloads, config schemas, env vars, audit log columns,
> GitHub artifact schemas, path conventions, marker formats — pinned
> here, in one place.
>
> **Audience.** Future maintainers asking "what is the exact shape
> of X" — what fields, what types, what enum values, what defaults,
> what stays stable across versions. Clarity for invariance > academic
> completeness.

---

## Status

**Spec.** Tracks 0002 features, 0003 entities, and the accepted ADRs.
0005 supersedes the "Protocol invariants" section that previously
lived in `CLAUDE.md`; that section now points here.

When `docs/architecture/AGENTS.md`'s change-impact matrix names a coupling, the schema
on each side of the coupling is pinned in 0005. When 0002 / 0003 / an
ADR explains *why* a contract exists, 0005 just says *what its exact
shape is* and links back. **0005 pins shape; rationale lives in the
cited ADR or feature spec.**

---

## What 0005 IS — and is NOT

**0005 IS:**

- A **contract registry** — every cross-component shape (script
  stdout, exit code, JSON schema, YAML schema, env var, marker
  string, file path) named once with its exact pinned form.
- **Cross-linked aggressively.** Every contract entry cites the
  ADR / feature spec / domain-model entry where the rationale lives.
- A **schema-delta normalizer.** Where 0002 / 0003 already document
  a schema (e.g., `state.yml` v1 in §1.5; AuditEntry columns in
  ADR-0006 §5), 0005 surfaces the canonical form and references the
  source — does not duplicate every field.
- The **finalizer of TBDs that the originating doc deferred to
  0005.** ADR-0006's `autonomy_overrides:` schema, the audit-DB
  credential mechanism, AuditTrail scope (per-Project vs global),
  per-`action_id` payload sub-schemas, and migration-runner
  ownership all land here as canonical.

**0005 is NOT:**

- ❌ A re-explanation of *why* a contract exists. Rationale lives
  in the originating ADR or feature spec; 0005 cites it.
- ❌ A speculative "future enterprise extension" surface. YAGNI per
  §1.5 cross-cutting principles. Anything not in v1 spec is either
  marked TBD with a one-line rationale + destination, or omitted.
- ❌ A duplicate of `card-schema.md`, `pr-template.md`, or
  `agentsmd-routing.md`. Those are the canonical source of their
  respective bodies; 0005 surfaces the **section list / parsing
  contract / marker-string** and links to the canonical body.
- ❌ A regression-test catalog. That's `0008-test-architecture.md`.
  0005 names which contract a test guards (when a test exists);
  the test itself lives elsewhere.
- ❌ A versioning policy doc. Bumping `plugin.json:version` on
  contract changes is documented in `AGENTS.md` ("Releasing"); 0005
  pins the contract shape per `schema_version` integer where one
  applies.

---

## Reading order

Navigator. Each file is single-topic; read top-down on first pass,
then jump back via cross-references.

| File | Coverage |
|------|----------|
| [`00-kanban-protocol.md`](./00-kanban-protocol.md) | **Top-level contract.** Semantic mental model every other contract derives meaning from. Establishes ontology (Board / Card / Status / Claim / PR Link / Label / Comment), six-state machine, identity rules (`Card.key` opacity, branch-naming abstraction), eight action contracts, compliance levels (L0-L3), and the three implementation projection forms (bash CLI / plugin-shipped MCP server / REST). Read FIRST on this directory's first-pass tour. |
| [`01-script-contracts.md`](./01-script-contracts.md) | Per-script: purpose, inputs, stdout shape, exit codes, side effects. Covers `check-deps.sh`, `bootstrap-project.sh`, `claim-card.sh`, `create-card.sh`, `transition-card.sh`, plus the `lib/common.sh` exported function surface. |
| [`02-hook-contracts.md`](./02-hook-contracts.md) | Per-hook: trigger event, stdin payload shape, stdout / `additionalContext` format, sanitization rules, exit codes, timeout. v1 wires `SessionStart` only; the format is forward-looking for additional events. |
| [`03-config-schemas.md`](./03-config-schemas.md) | Per YAML config: `~/.board-superpowers/manifest.yml`, `~/.board-superpowers/repos/<normalized>/state.yml` (host-local per I-13), `<repo>/.board-superpowers/config.yml`, `~/.board-superpowers/overrides.yml`, `~/.board-superpowers/credentials.yml`. Schema-version migration policy. The `autonomy_overrides:` finalization. |
| [`04-skill-contracts.md`](./04-skill-contracts.md) | SKILL.md frontmatter required vs CC-only fields; the procedural-skill requirement (ADR-0008); board-superpowers' own SKILL surface; classification of currently-composed sibling skills. |
| [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md) | Card body section list + parsing contract; ClaimMarker fields + info-leak guard; PR mandatory-section header strings; routing-block marker pair + `block_hash` format; Project v2 Status enum. |
| [`06-audit-log-schema.md`](./06-audit-log-schema.md) | Core 7-column AuditEntry schema; per-`action_id` payload sub-schemas (Producer rows 1–14 + Consumer rows 100–105); `outcome` enum; AuditTrail scope decision (per-Project); DDL ownership decision; migration model. |
| [`07-path-conventions.md`](./07-path-conventions.md) | Worktree path resolution priority; PlanBrief location; `.board-superpowers/` per-repo layout; `~/.board-superpowers/` per-host layout; session-log paths (CC + Codex); precise `.gitignore` block. |
| [`08-environment-variables.md`](./08-environment-variables.md) | Canonical table of every `BOARD_SP_*` env var: format, default, which scripts read it, cited ADR or feature spec. Plus `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PROJECT_DIR` consumption. |

---

## Contract-stability discipline

Three rules apply across every contract pinned here:

- **Public-contract scripts are immutable in shape.** Adding a new
  exit code, renaming a stdout key, or changing a `--machine` mode
  field name is a contract break. The change-impact matrix in
  `AGENTS.md` lists the callers that have to land in the same PR.
- **`schema_version` migrations are versioned-and-additive.**
  Per I-12, migrations add fields; they never remove or rename.
  Older plugin builds reading newer schema files MUST fail loudly,
  never silently drop unrecognized fields.
- **Marker strings are protocol, not decoration.** The
  `<!-- board-superpowers:routing -->` /
  `<!-- /board-superpowers:routing -->` pair (per I-10),
  `<!-- board-superpowers:card -->` (per F-09 schema), and
  `<!-- board-superpowers:pr -->` (per §1.8) are matched literally
  by tooling. Renaming, indenting, or merging into surrounding
  prose is a contract break.

---

## Related

- [`0001-positioning.md`](../0001-positioning.md) — premises P5
  (distribution stays minimal) and P7 (meta-methodology) constrain
  which contracts we *can* expose.
- [`0002-product-features-and-flows/`](../0002-product-features-and-flows/README.md)
  — feature surfaces whose contract shapes are pinned here.
  Especially §1.5 (config schemas), §1.6 (card schema), §1.7
  (cross-cutting invariants I-1..I-13), §1.8 (PR contract).
- [`0003-domain-model/`](../0003-domain-model/README.md) —
  entities whose physical layout becomes the contract here.
  Especially §3.3.5 / §3.3.6 / §3.3.7 (HostBootstrap / RepoBootstrap
  / RepoConfig) and §3.3.8 (AuditTrail).
- [`0004-component-architecture.md`](../0004-component-architecture.md)
  — runtime topology that realizes these contracts.
- [`0006-failure-modes.md`](../0006-failure-modes.md) — failure
  modes named in contract terms (e.g., "ghost claim" = ClaimMarker
  without ConsumerProcess; "marker race" = `<repo>/.board-superpowers/claims/`
  collision).
- [`0008-test-architecture.md`](../0008-test-architecture.md) —
  which test guards which contract; gaps are the test backlog.
- [`adr/`](../adr/README.md) — ADR-0002 (claim-card.sh exit codes),
  ADR-0003 (worktree path priority), ADR-0005 (BoardAdapter — referenced
  but not duplicated), ADR-0006 (audit-log + autonomy_overrides),
  ADR-0007 (preflight piggyback constraints), ADR-0008 (SKILL
  invocation as the cross-plugin contract).
- `docs/architecture/AGENTS.md` — change-impact matrix; absorbed
  into 0005's per-section entries.
- `PLUGIN_DEVELOPMENT.md` — CC + Codex plugin contract surfaces;
  04-skill-contracts cites this for portable-frontmatter rules.
- `MULTI_AGENT_DEVELOPMENT.md` — Mode-1 vs Mode-2 contracts;
  04-skill-contracts surfaces a subset (procedural-skill rule).
