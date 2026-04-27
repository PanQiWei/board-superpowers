# tests/integration/ — opt-in real-network tests

This directory is the future home of board-superpowers tests that hit
**real network resources**:

- a real GitHub Project (requires `gh` auth + the maintainer's
  `project` scope token);
- a real BYO-RDBMS instance (requires Postgres / MySQL / SQLite
  credentials).

Tests under `tests/` (the parent directory) are **hermetic** — they
stub `gh`, run inside `mktemp -d` HOME directories, and never reach the
network. CI runners do not carry the secrets needed for the integration
suite, so these tests must remain **opt-in**.

## How to opt in

Set `BSP_INTEGRATION=1` in the environment before running an
integration test:

```sh
BSP_INTEGRATION=1 bash tests/integration/<name>.sh
```

Tests in this directory MUST gate their actual side-effecting work on
the env var. Without it they should print a friendly skip message and
exit 0.

## Currently empty

This card (Card 2 / `v0.2.0-bootstrap`) ships only the convention. No
integration tests exist yet. Future cards add tests here when they need
real-network coverage — for example, an end-to-end `bootstrap-project.sh`
run against a maintainer-owned scratch GitHub Project, or a real
Postgres-write smoke for `auditing-actions` once that skill ships.

When you author the first integration test, copy the BSP_INTEGRATION
gate from the canonical reference (will be added with the first real
test) and update this README to point at it.
