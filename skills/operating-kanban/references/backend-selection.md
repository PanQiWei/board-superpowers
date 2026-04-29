# operating-kanban — backend-selection reference

Resolution algorithm that turns "the active kanban on this repo" into a concrete projection reference file under `references/<projection-id>.md`. Every protocol-action dispatch in this skill begins by running this algorithm; setup-capability predicates run a parallel form of the same lookup. Per ADR-0027 § Decision 2 the algorithm reads `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`; per ADR-0026 § "Multi-kanban semantics" the registry is shaped as a `kanbans:` list with v1.0 length=1 carve-out.

## Inputs

- The repo root (`<repo>`) handed in by the caller.
- The protocol action plus optional qualifier:
  - `kanban_id` (string) when the caller knows the target kanban.
  - `claim_branch` (string) when the caller is mid-claim and the kanban-id is encoded in the branch name (`claim/<kanban-id>-<key>-<slug>`).
  - Neither, when the caller relies on single-kanban defaulting.

## Algorithm

```text
function resolve_active_projection(repo_root, qualifier):
    settings = read_yaml(repo_root + "/.board-superpowers/settings.yml")
    if not settings.modules.m10_kanban:
        # Pre-v0.5.0 fallback: legacy config.yml § board block (see § Fallback below).
        return resolve_via_legacy_block(repo_root)

    kanbans = settings.modules.m10_kanban.kanbans
    if not kanbans:
        raise NotConfigured("modules.m10_kanban.kanbans empty")

    # v1.0 carve-out: list length=1 enforced. Reject anything else
    # — multi-kanban runtime ships in v1.x, schema reservation only.
    if len(kanbans) > 1:
        raise CarveOutViolation(
          "v0.5.0 supports kanbans length 1 only; saw " + len(kanbans)
        )

    if qualifier.kanban_id:
        entry = first(kanbans, k => k.id == qualifier.kanban_id)
        if not entry: raise UnknownKanban(qualifier.kanban_id)
    elif qualifier.claim_branch:
        kanban_id = parse_kanban_id_from_branch(qualifier.claim_branch)
        entry = first(kanbans, k => k.id == kanban_id)
        if not entry: raise UnknownKanban(kanban_id)
    else:
        # Single-kanban default — the only legal default at v0.5.0.
        entry = kanbans[0]

    projection_id = entry.projection
    reference_path = (
      "skills/operating-kanban/references/" + projection_id + ".md"
    )
    if not exists(reference_path):
        raise UnknownProjection(projection_id)

    return (entry, reference_path)
```

The function returns the kanban entry plus the path to its projection reference file. The dispatch layer (`action-dispatch.md`) consumes both: the kanban entry to thread `(kanban_id, Card.key)` resolution per the next section; the reference path to load the per-Form invocation patterns.

## Composite-key resolution `(kanban_id, Card.key)`

Per ADR-0026 § Multi-kanban semantics the unique card identity across a multi-kanban repo is the pair `(kanban_id, Card.key)` rather than `Card.key` alone. v0.5.0's length=1 carve-out means a bare `Card.key` is resolvable without ambiguity, so the protocol disambiguator below is OPTIONAL on length=1 repos:

- **Length 1**: `[board-card:#42]` resolves to `(kanbans[0].id, 42)`. Bare `Card.key` references in PR bodies, commit messages, and chat are accepted.
- **Length >1 (v1.x roadmap)**: `[board-card:<kanban-id>:#42]` REQUIRED. Bare `[board-card:#42]` rejected at the parsing layer; the operating-kanban dispatch surfaces "ambiguous card key — qualify with kanban-id" and refuses to act.

The discriminator MUST be a stable, repo-internal alias (`primary`, `legal`, etc.) — not the projection identifier, not the project_ref. The kanban entry's `id` field is the canonical alias; renaming it requires the architect to rewrite all in-flight branches and PR-body references, which is why ADR-0026 marks the alias `repo-internal alias; unique within this repo` rather than user-facing.

## Fallback — pre-v0.5.0 settings (deprecation path)

Until the setup-stages M10 stage lands on main (paired-PR work), freshly bootstrapped repos may still have only the legacy `config.yml § board` block:

```yaml
board:
  kanban: github-project-v2
  project: PanQiWei/3
```

When `modules.m10_kanban` is absent but the legacy block is present, this skill:

1. Synthesizes a single-entry `kanbans` list in memory: `[{id: "primary", projection: <board.kanban>, project_ref: <board.project>, role: primary}]`.
2. Emits a one-shot deprecation notice on stderr ("legacy `config.yml § board` detected; will be migrated to `settings.yml § modules.m10_kanban` once the setup-stages M10 stage lands on main").
3. Proceeds with the resolved single-entry list.

The fallback is removed once the M10 stage lands on main and the `migrating-repo-version` SKILL gains the rewrite step. Architects opting into the bootstrap flow after that point never hit this path.

## Failure modes — caller-visible behavior

Every failure surface MUST include the fix path so the operator can act without re-reading the spec. Bare "configuration is bad" is anti-pattern.

| Symptom | Caller-visible behavior |
|---------|-------------------------|
| Settings file missing entirely. | Surface: "kanban not yet configured on this repo. Run the `bootstrapping-repo` SKILL on this repo (the architect can say 'set up board-superpowers' / 'first time on this repo') to create `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`. See ADR-0026 § Schema for the kanban entry shape." Do NOT invent a projection. |
| `modules.m10_kanban.kanbans` empty list or absent on a fully-migrated repo. | Surface: "Configuration is empty: add at least one entry to `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans` — see ADR-0026 § Schema for the kanban entry shape (id / projection / project_ref / role). Run `bootstrapping-repo` to populate." |
| `kanbans` length > 1 on v0.5.0. | Refuse with: "v1.0 carve-out violated: `kanbans` length=<N> but v0.5.0 supports length=1 only. Multi-kanban runtime is v1.x roadmap; for now keep `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans` to a single entry. Schema reservation is parser-tolerant but the runtime is not." |
| Projection identifier names a projection not present in `references/`. | Refuse with: "unknown projection `<id>`. The plugin's shipped projections live in `skills/operating-kanban/references/<projection-id>.md`. Check (a) plugin version (the projection may have shipped in a later version), (b) the `projection:` field in the kanban entry of `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans`, (c) the projection registry in ADR-0026 § Projection identifiers. Do NOT silently fall back." |
| Caller passes a `kanban_id` not present in the registry. | Refuse with: "unknown kanban `<id>` on this repo. Registered kanban ids: <list of `kanbans[*].id`>. To register a new kanban, edit `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans` (per ADR-0026 § Schema) and re-run `bootstrapping-repo`." |
| Caller passes a `claim_branch` whose kanban-id segment fails to parse. | Refuse with: "malformed claim branch `<branch>` — expected shape `claim/<kanban-id>-<key>-<slug>`. The kanban-id segment must match a registered kanban id in `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans`. See `skills/board-canon/references/branch-naming.md` § Disambiguation invariants for the parser's allowlist rules." |

Detailed surfacing tiers (silent / log-only / audit-row / surface-immediately) live in `failure-mode-dispatch.md`. This file documents the resolver itself; surfacing convention is one layer up.

## Related

- ADR-0026 § "Multi-kanban semantics" — the schema this resolver reads.
- ADR-0027 § Decision 2 — the predicate evaluator's parallel use of the same lookup for setup-capability dispatch.
- `action-dispatch.md` — the next layer that consumes the resolver's output.
- `failure-mode-dispatch.md` — the surfacing convention this resolver's failures plug into.
- `<repo>/.board-superpowers/settings.yml § modules.m10_kanban` — the runtime authority; schema in [`docs/architecture/0005-contracts/03-config-schemas.md`](../../../docs/architecture/0005-contracts/03-config-schemas.md) § "modules.m10_kanban block".
