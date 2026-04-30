# operating-kanban — backend-selection reference

**When you have** a protocol action to dispatch (or a setup-capability predicate to evaluate) and need to know which projection's reference file to load, **arrive here**. This file gives you the procedure that turns "the active kanban on this repo" into a concrete projection-reference path under `references/<projection-id>.md`.

## What you need

- The repo root (`<repo>`) — usually `git rev-parse --show-toplevel` from inside the worktree.
- The protocol action plus an optional qualifier:
  - `kanban_id` (string) when you already know which kanban to act on.
  - `claim_branch` (string) when you are mid-claim and the kanban-id is encoded in the branch name (`claim/<kanban-id>-<key>-<slug>`).
  - Neither, when the repo has a single kanban configured (the only legal default at current ship).

## Procedure — 7 steps

Run these in order. Each step has a definite stop condition; do not skip.

1. **Read the registry.** Open `<repo>/.board-superpowers/settings.yml`. If the file is missing, surface "kanban not yet configured on this repo" per the failure table below and route the architect to the `bootstrapping-repo` SKILL. Do NOT invent a default.

2. **Locate the kanban module.** Look for `modules.m10_kanban`. If the key is absent but the legacy `config.yml § board` block is present, follow the deprecation-fallback branch in § Fallback below; otherwise surface "kanban not yet configured" per step 1.

3. **Read the kanbans list.** Read `modules.m10_kanban.kanbans`. If the list is empty or the key is missing, surface "Configuration is empty: add at least one entry to `modules.m10_kanban.kanbans` (each entry needs `id`, `projection`, `project_ref`, `role`)" and refuse to act.

4. **Enforce the length=1 carve-out.** If the list has more than one entry, refuse with: "kanban list length=<N>, but the runtime supports length=1 only. Multi-kanban support is reserved in the schema but not wired in the runtime; reduce the list to a single entry in `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans`." Do NOT silently pick the first entry.

5. **Resolve the active entry.** Pick the kanban entry per the qualifier:
   - `kanban_id` provided: find the entry where `id == kanban_id`. If no match, refuse with "unknown kanban `<id>`; registered ids: <list of `kanbans[*].id`>".
   - `claim_branch` provided: parse the kanban-id segment from the branch name (`claim/<kanban-id>-<key>-<slug>`). If parsing fails, refuse with "malformed claim branch `<branch>` — expected shape `claim/<kanban-id>-<key>-<slug>`". Find the entry where `id == kanban_id`; on miss, refuse as above.
   - Neither provided: take `kanbans[0]` (single-kanban default).

6. **Load the projection reference file.** Read `entry.projection` and locate `skills/operating-kanban/references/<projection-id>.md`. If the file does not exist, refuse with "unknown projection `<id>` — the plugin's shipped projections live in `skills/operating-kanban/references/<projection-id>.md`. Verify the `projection:` field in the kanban entry of `<repo>/.board-superpowers/settings.yml` and that the plugin version actually ships this projection." Do NOT silently fall back.

7. **Dispatch.** Hand the kanban entry plus the loaded reference path to the action-dispatch layer (`action-dispatch.md`). The dispatch layer reads the per-Form invocation pattern from the reference file and invokes the action.

### Bash sketch

The procedure above maps directly into shell. The plugin ships the actual implementation in `scripts/lib/common.sh`; this sketch is the conceptual flow:

```bash
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
settings="$repo_root/.board-superpowers/settings.yml"

[ -f "$settings" ] || { echo "kanban not yet configured" >&2; exit 3; }

# Read modules.m10_kanban.kanbans through the plugin's per-repo venv-managed PyYAML.
kanban_count="$(bsp_yaml_count "$settings" '.modules.m10_kanban.kanbans')"
[ "$kanban_count" -ge 1 ] || { echo "kanbans list empty" >&2; exit 3; }
[ "$kanban_count" -eq 1 ] || { echo "kanbans length=$kanban_count; runtime supports length=1 only" >&2; exit 2; }

projection_id="$(bsp_yaml_get "$settings" '.modules.m10_kanban.kanbans[0].projection')"
ref_path="${BSP_PLUGIN_ROOT}/skills/operating-kanban/references/${projection_id}.md"
[ -f "$ref_path" ] || { echo "unknown projection $projection_id" >&2; exit 3; }

# Hand off to action-dispatch with (entry, ref_path).
```

## Composite-key resolution `(kanban_id, Card.key)`

The unique card identity across a repo's kanban set is the pair `(kanban_id, Card.key)`. The current length=1 carve-out means a bare `Card.key` resolves without ambiguity, so the protocol disambiguator is OPTIONAL on length=1 repos:

- **Length 1** (current runtime): `[board-card:#42]` resolves to `(kanbans[0].id, "42")`. Bare `Card.key` references in PR bodies, commit messages, and chat are accepted. `Card.key` is an opaque string (e.g., GitHub Issue number rendered as a string for the GitHub Project v2 projection), NOT an integer — return the slug-decoded string regardless of backend. For non-GitHub projections, the key reference shape is `[board-card:#ENG-42]` and resolves to `(kanbans[0].id, "ENG-42")`.
- **Length > 1** (reserved): `[board-card:<kanban-id>:#42]` REQUIRED. Reject bare `[board-card:#42]` at the parsing layer with "ambiguous card key — qualify with kanban-id".

The discriminator MUST be a stable, repo-internal alias (`primary`, `legal`, etc.) — not the projection identifier, not the project_ref. The kanban entry's `id` field is the canonical alias. Renaming it requires the architect to rewrite all in-flight branches and PR-body references, which is why the alias is treated as repo-internal (unique within this repo) rather than user-facing.

## Fallback — legacy `config.yml § board` block (deprecation path)

If `modules.m10_kanban` is absent but the legacy block is present, synthesize a single-entry kanbans list in memory and proceed:

```yaml
# legacy shape:
board:
  kanban: github-project-v2
  project: PanQiWei/3
```

Procedure:

1. Synthesize `[{id: "primary", projection: <board.kanban>, project_ref: <board.project>, role: primary}]` in memory.
2. Emit a one-shot deprecation notice on stderr ("legacy `config.yml § board` detected; will be migrated to `settings.yml § modules.m10_kanban` once the architect re-runs `bootstrapping-repo`").
3. Continue from step 5 of the main procedure with the synthesized list.

The fallback path costs you nothing on the read side — the in-memory shape is identical to the migrated form.

## Failure modes — caller-visible behavior

Every failure surface MUST include the fix path so the operator can act without re-reading the spec. Bare "configuration is bad" is anti-pattern.

| Symptom | Caller-visible behavior |
|---------|-------------------------|
| Settings file missing entirely. | Surface: "kanban not yet configured on this repo. Run the `bootstrapping-repo` SKILL on this repo (the architect can say 'set up board-superpowers' / 'first time on this repo') to create `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`. The kanban entry shape is `{ id, projection, project_ref, role }`." Do NOT invent a projection. |
| `modules.m10_kanban.kanbans` empty list or absent on a fully-migrated repo. | Surface: "Configuration is empty: add at least one entry to `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans` (each entry needs `id`, `projection`, `project_ref`, `role`). Run `bootstrapping-repo` to populate." |
| `kanbans` length > 1. | Refuse with: "kanban list length=<N>, but the runtime supports length=1 only. Multi-kanban support is reserved in the schema but not wired in the runtime; reduce `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans` to a single entry. The schema parser is tolerant; the runtime is not." |
| Projection identifier names a projection not present in `references/`. | Refuse with: "unknown projection `<id>`. The plugin's shipped projections live in `skills/operating-kanban/references/<projection-id>.md`. Check (a) plugin version (the projection may have shipped in a later version) and (b) the `projection:` field in the kanban entry of `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans`. Do NOT silently fall back." |
| Caller passes a `kanban_id` not present in the registry. | Refuse with: "unknown kanban `<id>` on this repo. Registered kanban ids: <list of `kanbans[*].id`>. To register a new kanban, edit `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans` and re-run `bootstrapping-repo`." |
| Caller passes a `claim_branch` whose kanban-id segment fails to parse. | Refuse with: "malformed claim branch `<branch>` — expected shape `claim/<kanban-id>-<key>-<slug>`. The kanban-id segment must match a registered kanban id in `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans`. See `skills/board-canon/references/branch-naming.md` for the parser's allowlist rules." |

Detailed surfacing tiers (silent / log-only / audit-row / surface-immediately) live in `failure-mode-dispatch.md`. This file documents the resolver itself; surfacing convention is one layer up.

## Related

- `action-dispatch.md` — the next layer that consumes the resolver's output.
- `failure-mode-dispatch.md` — the surfacing convention this resolver's failures plug into.
- `<repo>/.board-superpowers/settings.yml § modules.m10_kanban` — the runtime authority. The schema is `{ kanbans: [{ id, projection, project_ref, role, wip_limit_local? }, ...] }`.
