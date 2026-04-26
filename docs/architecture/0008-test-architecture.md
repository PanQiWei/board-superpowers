# Test architecture

> **Status:** stub.

## Purpose

Define what gets tested at which layer, and *why* there's no test
at some layers. Today only `claim-card.sh` is covered; this doc is
where we decide which other layers earn tests, in what order, and
to what depth.

## Layers (TBD)

- **Unit / contract** — script stdout shape, exit codes, side-effect
  shape. Pattern established by `tests/test-claim-card*.sh`
  (hermetic bash + bare-repo-as-origin). Coverage today: only
  `claim-card.sh`.
- **Integration** — multi-script flows. E.g., bootstrap end-to-end
  (label create + Status validation + config write + gitignore
  edit). None yet.
- **Skill smoke** — does a SKILL frontmatter parse, do all
  references exist, do skill-internal links resolve, does each
  skill listed in handoff-table actually exist. None yet.
- **State-machine** — every transition in `board-protocol` has a
  test that triggers it and asserts the post-condition. None yet.
- **Manager / Consumer end-to-end** — drive a real Session against
  a scratch repo + Project. Likely out of scope for automation;
  manual smoke test category.

## Test guarantees per layer (TBD)

Each layer states what it asserts and what it deliberately doesn't.
The "deliberately doesn't" half is as important as the assertion —
it keeps lower layers honest.

## Hermetic pattern (TBD — promote from CLAUDE.md devguide)

Currently documented in `CLAUDE.md` "Testing" section. Move the
canonical version here once this file is filled in; keep CLAUDE.md
as a pointer.

- `HOME=$TMP/home` — isolate user config.
- `XDG_CONFIG_HOME=$TMP/xdg` — isolate worktree default path.
- `GIT_CONFIG_GLOBAL=$TMP/.gitconfig-global` +
  `GIT_CONFIG_SYSTEM=/dev/null`.
- Bare local repo as `origin`; never reach GitHub from a test.
- `core.hooksPath=/dev/null`, `core.excludesFile=/dev/null`.

## Test organization (TBD — proposed)

```
tests/
├── contract/              # script-level, hermetic
│   ├── test-claim-card.sh
│   └── test-claim-card-worktree.sh
├── integration/           # multi-script
│   └── test-bootstrap-end-to-end.sh        # not yet
├── skill/                 # frontmatter + reference link checks
│   └── test-skill-metadata.sh              # not yet
└── state-machine/         # transitions
    └── test-card-transitions.sh            # not yet
```

Currently flat at `tests/`. Reorganization is non-breaking (paths
inside test files use absolute repo-rooted scripts).

## CI (TBD)

- No CI configured yet. Likely candidate: GitHub Actions running
  the full `tests/**/*.sh` matrix on push.
- macOS + Linux runners both, since macOS BSD tooling differs from
  GNU (failure F-12 in `0006-failure-modes.md` is a macOS-only failure).
