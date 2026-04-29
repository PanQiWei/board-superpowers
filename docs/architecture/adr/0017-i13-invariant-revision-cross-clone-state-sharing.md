# ADR 0017: I-13 invariant revision — cross-clone state sharing via GitHub-based identity

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

The v0.4.0 spec
[`../0002-product-features-and-flows/07-cross-cutting-invariants.md`](../0002-product-features-and-flows/07-cross-cutting-invariants.md)
§ I-13 places per-repo bootstrap state at
`~/.board-superpowers/repos/<normalized>/state.yml`, where
`<normalized>` is the repo's **absolute on-disk path** with the
leading `/` stripped and remaining `/` replaced by `-` (per
[`../0005-contracts/07-path-conventions.md`](../0005-contracts/07-path-conventions.md)).
Identity is path-derived; two clones of the same GitHub repo at
different paths produce two independent host-local state
directories.

The bootstrap-redesign work
([`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md))
surfaces three structural weaknesses:

1. **Architect intent is per-`(host, repo)`, not per-clone.**
   The audit DSN, the bootstrap progress, the cached GitHub
   Project field IDs are facts about *the repo as a coordination
   object*, not facts about a particular working copy. An
   architect with primary `~/Dev/foo` and sandbox `~/Sandbox/foo`
   should not have to bootstrap twice or hand-sync
   `credentials.yml`.
2. **Worktrees of the same primary repo collide with path
   normalization.** A worktree at
   `~/.config/superpowers/worktrees/foo/feat-x` produces a
   different identity than its primary `~/Dev/foo`, even though
   both share `origin` and the same `(host, repo)` scope. Each
   worktree ends up with its own `state.yml`, `credentials.yml`,
   and audit DB — the opposite of what worktree-per-Consumer
   (ADR-0003) needs.
3. **Manual sync cost grows with clone count.** Every additional
   clone (or worktree) on the same host multiplies the surface
   area the architect must keep coherent; the path *is* the
   identity, with no programmatic way to express "this is the
   same repo as that one."

The redesign doc § "Repo identity" + § "Edge cases" + § "I-13
invariant revision (cross-clone state sharing)" + § "Decided"
formalize a replacement scheme. This ADR records the decision
so the same-PR contract update to `07-cross-cutting-invariants.md`
§ I-13 has a citable anchor.

## Decision

Repo identity is **GitHub-based**, derived from the `origin`
remote URL. The directory key is computed as:

```
git remote get-url origin
  → https://github.com/PanQiWei/board-superpowers.git
  → git@github.com:PanQiWei/board-superpowers.git

bsp_compute_repo_identity()
  → strip scheme prefix and `.git` suffix
  → extract <owner>/<repo> path component
  → replace `/` with `-`
  → "PanQiWei-board-superpowers"
```

Per-repo host-local state lives at
`~/.board-superpowers/repos/<owner>-<repo>/`, regardless of how
many physical clones of the repo exist on the host. I-13 is
**revised** to:

> **I-13 (revised).** Each `(host, GitHub repo)` pair shares a
> single host-local per-repo state directory at
> `~/.board-superpowers/repos/<repo-identity>/`, regardless of
> how many physical clones exist on the host. Per-clone
> physical isolation is preserved only for `repo-clone`
> locality stages (`.venv/`, `config.local.yml`).

The identity scheme handles edge cases as follows (per redesign
doc § "Edge cases"):

- **Local-only repo (no `origin`)** — fallback to path-based
  normalization with a `_path-` prefix
  (`~/.board-superpowers/repos/_path-Users-foo-myproj/`). The
  prefix prevents collision with GitHub identities. When the
  architect later adds a GitHub `origin`, the pre-v1
  breaking-change posture (per redesign § "Decided") permits
  deleting the `_path-...` directory and re-bootstrapping; no
  auto-migration stage ships.
- **HTTPS vs SSH URL form** — both `https://github.com/A/B.git`
  and `git@github.com:A/B.git` resolve to identity `A-B`. URL
  form is normalized away.
- **Multi-remote repos** — `origin` is the canonical source;
  non-`origin` remotes do not influence identity.
- **Forks** — fork's `origin` points to the fork
  (`<your-name>/<their-repo>`), so the fork has its own
  identity separate from upstream. State does not transfer
  between fork and upstream — a fork is a different
  coordination object.
- **Repo rename on GitHub** — `origin` URL no longer matches
  the existing identity directory. The `bsp-relocate-repo.sh
  <old-identity> <new-identity>` helper atomically `mv`s the
  state directory; the architect runs it once after the rename.
- **All worktrees share identity** — `git rev-parse
  --git-common-dir` resolves every worktree to the primary
  clone, which is where `origin` lives. Worktrees of the same
  primary repo share state, which is the correct behavior for
  worktree-per-Consumer (ADR-0003).

## Consequences

### Positive

- **One bootstrap per `(host, repo)` pair.** Two clones at
  `~/Dev/foo` and `~/Sandbox/foo` share `state.yml`,
  `credentials.yml`, and audit DB. Changes from one clone are
  immediately visible to the other; the architect bootstraps
  once and gains uniform behavior across every working copy.
- **Worktrees behave correctly with no special handling.**
  Worktree-per-Consumer (ADR-0003) was previously at odds with
  path-based identity; the GitHub-based scheme makes it work
  by construction.
- **Multi-architect-on-same-host alignment is correct by
  default.** Two architects on the same host who clone the same
  repo share the per-`(host, repo)` configuration — one
  authoritative copy of audit credentials, bootstrap progress,
  cached Project IDs. Per-architect divergence is preserved
  through `repo-clone` locality stages (`config.local.yml`,
  `.venv/`), which remain physically per-clone.
- **Identity is human-readable.** `<owner>-<repo>` directory
  names stay self-explanatory in `ls
  ~/.board-superpowers/repos/`.

### Negative

- **Pre-v1 breaking change.** Existing v0.4.0 installs that
  used path-based identity must delete
  `~/.board-superpowers/repos/<old-path-id>/` and re-bootstrap
  on upgrade. The redesign doc § "Decided" → "Pre-v1 breaking
  changes are accepted" carries this posture; no in-place
  migration logic ships.
- **Repo-rename adds an out-of-band manual step.** The
  architect runs `bsp-relocate-repo.sh <old> <new>` once after
  a GitHub rename. Rare enough that a continuous
  detect-and-prompt stage is not justified at v1; future
  enhancement permitted.
- **Cross-architect intent leak when sharing a host.** Two
  architects on the same host who clone the same repo now
  share the audit DSN. If they need independent audit trails,
  they must use distinct hosts (or distinct user accounts).
  The previous scheme accidentally isolated them; the new
  scheme exposes the underlying assumption that `(host, repo)`
  is the coordination unit, not `(host, path)`.

## Alternatives considered

### α — GitHub-based identity, cross-clone shared state (chosen)

This ADR's decision. Identity is `<owner>-<repo>` from `origin`;
state is shared across all clones and worktrees of the same
`(host, repo)` pair.

### β — Keep path-based identity (status quo)

Rejected. Architect intent is per-`(host, repo)` configuration
sharing; path-based isolation produces unnecessary divergence
between clones, and the manual sync cost grows linearly with
clone count. Worktree-per-Consumer (ADR-0003) makes the
multi-clone case the common case, not the exception, so the
divergence cost is felt on every Consumer session.

### γ — GitHub numeric repo ID via `gh api`

Rejected. The numeric ID (e.g., `123456789`) is stable across
renames but completely non-readable as a directory name;
`~/.board-superpowers/repos/123456789/` defeats the
self-explanatory listing property. A `gh api repos/<owner>/<repo>`
round-trip would also be required at first bootstrap, adding a
network dependency to a stage that otherwise needs only `git`.
The rare repo-rename case is handled adequately by
`bsp-relocate-repo.sh` without sacrificing readability.

### δ — Hybrid: display name + numeric ID alias in manifest

Rejected. Two-layer identity (display + alias) introduces
complexity without proportional value. Repo-rename frequency is
too low to justify manifest-aliasing machinery; α's helper-script
approach gives the architect one explicit action at rename time
and zero ongoing overhead.

## Notes

This ADR amends I-13 wording in
[`../0002-product-features-and-flows/07-cross-cutting-invariants.md`](../0002-product-features-and-flows/07-cross-cutting-invariants.md).
Per the same-PR contract-update discipline
([`../AGENTS.md`](../AGENTS.md) Doctrine #3), the PR that lands
this ADR also rewrites § I-13 to the revised wording and updates
[`../0005-contracts/07-path-conventions.md`](../0005-contracts/07-path-conventions.md)
to document the GitHub-based identity scheme (with `_path-`
fallback) alongside the legacy path-based normalization rule.
On acceptance, the ADR's status flips from `proposed` to
`accepted` and supersedes the original I-13 phrasing in
`07-cross-cutting-invariants.md`; this ADR then becomes the
canonical reference for the revised invariant.

The `_path-` prefix on the local-only-repo fallback is a
deliberate namespace separator: GitHub identities never start
with an underscore (GitHub username syntax forbids it), so the
prefix guarantees no accidental collision with a real
`<owner>-<repo>` identity.

## Related

- [ADR-0003](./0003-worktree-per-consumer.md) — One worktree per
  Consumer session; the pattern that path-based identity broke
  and GitHub-based identity restores.
- [ADR-0012](./0012-unified-check-script-trigger-model.md) —
  Unified check-script trigger model; partitioned status files
  this ADR governs the physical location of.
- ADR-0013 — Declarative state schema + 5-state lifecycle
  (sibling, plain text placeholder until landed); defines the
  `repo-shared` locality whose physical home this ADR specifies.
- ADR-0014 — Stage registry contract (sibling, plain text
  placeholder); the registry whose `locality` field this ADR
  binds to a directory layout.
- ADR-0015 — M4 audit per-repo locality (sibling, plain text
  placeholder); per-repo `credentials.yml` lives inside the
  identity-keyed directory this ADR defines.
- ADR-0016 — Cross-platform parity contract (sibling, plain text
  placeholder); orthogonal to identity, shares redesign-doc origin.
- ADR-0018 — M7 multi-stage per-block routing-block protocol
  (sibling, plain text placeholder); orthogonal to identity.
- ADR-0019 — Pre-v1 breaking-change posture (sibling, plain text
  placeholder); makes the no-in-place-migration posture in this
  ADR's Negative consequences citable.
- [`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
  — Living design doc; § "Repo identity" + § "Edge cases" +
  § "I-13 invariant revision (cross-clone state sharing)" are
  this ADR's authoritative reference.
- [`../0002-product-features-and-flows/07-cross-cutting-invariants.md`](../0002-product-features-and-flows/07-cross-cutting-invariants.md)
  § I-13 — Invariant whose wording this ADR amends.
- [`../0005-contracts/07-path-conventions.md`](../0005-contracts/07-path-conventions.md)
  — Path-conventions contract; the same-PR update extends it
  with the GitHub-based identity scheme alongside the legacy
  path normalization rule.
