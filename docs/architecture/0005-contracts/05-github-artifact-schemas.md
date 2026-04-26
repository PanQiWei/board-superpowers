# 05 — GitHub artifact schemas

> Pin the shape of every GitHub-hosted artifact board-superpowers
> reads or writes: Card body section list, ClaimMarker file
> fields, PR mandatory-section header strings, routing-block marker
> pair + `block_hash` format, Project v2 Status enum, and the
> standard label set. Where canonical bodies live elsewhere
> (`card-schema.md`, `pr-template.md`, `claudemd-routing.md`), 0005
> surfaces only the parsing contract and links.

---

## Card body — section list + parsing contract

Canonical body schema lives in
[`skills/decomposing-into-milestones/references/card-schema.md`](../../../skills/decomposing-into-milestones/references/card-schema.md).
0005 pins the **section list** (header strings, in this order) and
the **parsing contract** that downstream tooling can rely on.

### Required section headers (in this order)

| Order | Header | Required? | Notes |
|-------|--------|-----------|-------|
| 1 | `## Context` | yes | 1–3 paragraphs; background, files, dependencies |
| 2 | `## Acceptance Criteria` | yes | Markdown checklist (`- [ ] …`); each item a post-condition, not a task |
| 3 | `## Out of Scope` | yes | Bulleted list; deliberate exclusions |
| 4 | `## Size` | yes | One token: `XS` \| `S` \| `M` \| `L`. `XL` is invalid by design — split the card if you reach for it |
| 5 | `## Execution Hints` | optional | Single Manager-to-Consumer hint section; terse |

### Trailing marker

Every Card body MUST end with the exact bytes:

```
<!-- board-superpowers:card -->
```

The marker distinguishes board-superpowers Cards from plain Issues
on the same project. `managing-board` and other tooling key off
this marker. Per `card-schema.md` "The marker comment" + 0003 § 3.3.1
Card aggregate "Trailing marker required" invariant.

**Removal of the marker is a protocol violation** and breaks every
Manager routine that lists board-superpowers Cards.

### Parsing contract for downstream tools

Downstream tools (Manager Daily routine, F-C2 plan-brief
synthesizer, etc.) parse Card bodies under these rules:

- **Header matching.** `## <Section>` lines at the start of a line
  identify section boundaries. Whitespace before `##` is allowed
  but discouraged (would round-trip-lossy through some Markdown
  renderers).
- **Section ordering.** Tools MUST tolerate sections appearing in
  the canonical order; behavior on out-of-order sections is
  undefined.
- **Missing optional sections.** `## Execution Hints` absent =
  empty hints. Other missing sections = parse error / Card body
  contract violation.
- **`Depends on #N` syntax.** Within `## Context`, dependencies
  on other Cards are written as `Depends on #42, #43` (per
  `card-schema.md`). The F-C0 self-selection step (and Producer's
  Backlog → Ready gate) MUST refuse a Card whose deps aren't all
  Done yet.
- **`Closes #N` syntax** does NOT appear in Card bodies — that's
  a PR-body concept (see PR section below).

### Rationale

- `card-schema.md` (canonical body + section-by-section guidance).
- `board-protocol/SKILL.md` "Card body — schema".
- §1.6.3 (decomposition surface card-schema invariants).
- 0003 § 3.3.1 Card aggregate (CardBody member entity).

---

## ClaimMarker file — schema + info-leak guard

File path: `<repo>/.board-superpowers/claims/<N>.claim` on the
**ClaimBranch only**. Gitignored locally; force-committed (`git
add -f`) onto the claim branch by `claim-card.sh`.

### v1 schema (YAML)

```yaml
card: <integer card number>
session: <session slug>
claimed_at: <ISO 8601 UTC, "YYYY-MM-DDTHH:MM:SSZ">
base: <base branch name>
branch: <claim branch name, e.g. claim/42-oauth-callback>
```

### Field types

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `card` | integer | yes | Matches `<N>` in the file path |
| `session` | string | yes | Session slug — `BOARD_SP_SESSION_SLUG` env var if set, else `s-$(date +%s)-$$` |
| `claimed_at` | string (ISO 8601 UTC, `Z` suffix) | yes | When `claim-card.sh` wrote the file |
| `base` | string (branch name) | yes | The base branch the claim was forked from (`main`, `master`, etc.) |
| `branch` | string (`claim/<N>-<slug>`) | yes | The claim branch name |

### Forbidden field — `worktree:`

The marker file MUST NOT carry a `worktree:` field. The absolute
local path on disk would leak the claimant's OS username and
directory layout to anyone who clones the public repo and inspects
the claim branch. Per:

- `claim-card.sh` source comment ("Deliberately NOT writing a
  `worktree:` field…").
- ADR-0003 "WorktreePath info-leak guard".
- 0003 § 3.3.3 "WorktreePath info-leak guard" invariant.
- `tests/test-claim-card-worktree.sh` — regression assertion.

The Consumer session already has the worktree path via the
`worktree=` line on `claim-card.sh` stdout (per
[`01-script-contracts.md`](./01-script-contracts.md)) — that
ephemeral channel does not persist to the remote.

### Lifecycle

- **Created at F-C1** by `claim-card.sh` step 5.
- **Force-added (`git add -f`) and committed** in step 7. The
  commit message is `claim: card #<N> [<session-slug>]` followed
  by a body explaining "the presence of this branch on the remote
  means a Board Consumer session owns card #<N>".
- **Pushed atomically** in step 8 (`git push --force-with-lease=
  refs/heads/<branch>:`).
- **Deleted** when the claim branch is deleted (per ADR-0002
  "Branch deletion releases the claim").

### Cited rationale

- ADR-0002 (claim via branch push; marker is on-origin proof of
  claim).
- ADR-0003 (worktree path info-leak guard).
- §1.4.1 F-C1 (atomic claim primitive).
- 0003 § 3.3.3 ConsumerLogical aggregate (ClaimMarker member
  entity).

---

## PR body — mandatory sections + marker

Canonical body template lives in
[`skills/consuming-card/references/pr-template.md`](../../../skills/consuming-card/references/pr-template.md).
0005 pins the **section list**, the **OPTIONAL/required matrix**,
the **closing-line format**, and the **marker string**.

### Section header strings (in this order)

| Order | Header | Author | Required? |
|-------|--------|--------|-----------|
| 1 | `## Summary` | Delegated PR-creation skill (`superpowers:finishing-a-development-branch` / `gstack:/ship`) | yes (writes itself) |
| 2 | `## Test Plan` | Delegated skill | yes (writes itself) |
| 3 | `## Automated Verification` | Consumer | **required** |
| 4 | `## Human Verification TODO` | Consumer | **OPTIONAL** — omit cleanly when no end-to-end human check is needed |
| 5 | `## Retro Notes` | Consumer | **required when reusable lessons exist** (knowledge-harvesting only — NOT velocity / KPI / estimate-vs-actual) |

### Closing line

```
Closes #<card-number>.
```

Capital `C` in `Closes` (lowercase is not guaranteed across all
GitHub setups). Per `pr-template.md` "The closing line".

### Trailing marker

Every PR body MUST end with the exact bytes:

```
<!-- board-superpowers:pr -->
```

Per `pr-template.md` + `board-protocol/SKILL.md` "PR body — schema"
+ 0003 § 3.3.2 PR aggregate "§1.8 marker required" invariant.

`managing-board`'s Review Queue routine (F-02) keys off this marker
to find board-superpowers PRs among ordinary ones.

### Section content rules

The pinned content rules (per
[`02-product-features-and-flows/08-pr-contract.md`](../0002-product-features-and-flows/08-pr-contract.md)
and `pr-template.md`):

- `## Automated Verification` — mandatory; lists what tests ran +
  outcomes + cross-platform attribution (per F-C10).
- `## Human Verification TODO` — OPTIONAL; if present, every item
  MUST be a real check. Filler ("verify it works", "make sure
  tests pass") is a structural PR violation flagged by F-02.
- `## Retro Notes` — required when reusable lessons exist;
  knowledge-harvesting only; two-pass authorship (initial at
  PR-submit, supplemented post-merge). **Post-merge supplement
  trigger:** the same Consumer instance that authored the initial
  Retro Notes detects merge via `gh pr view --json merged` on its
  next preflight after PR closure; the supplement is appended via
  `gh pr edit --body` to the merged PR's body. The audit payload
  records `action_id=104` with `phase=post_merge_supplement` and
  the supplement contents (per `06-audit-log-schema.md`
  `action_id=104` payload sub-schema).

### Cited rationale

- §1.8 PR contract (canonical content + per-section rules).
- `pr-template.md` (canonical template).
- `board-protocol/SKILL.md` "PR body — schema".
- 0003 § 3.3.2 PR aggregate.
- F-C12 PR submission feature (`04-consumer-surface.md` §1.4.1).

---

## Routing-block marker pair

Used in **both** `<repo>/CLAUDE.md` AND `<repo>/AGENTS.md` (per
§1.5 dual-platform parity rule).

### Exact strings

```
<!-- board-superpowers:routing -->
<!-- /board-superpowers:routing -->
```

These are matched literally by:

- `scripts/check-deps.sh` (substring match: `board-superpowers:routing`).
- `bootstrap-project.sh` and `using-board-superpowers` (initial
  injection in F-B2; uses both opening and closing markers as
  insertion boundaries).
- F-B4 routing-block re-injection (uses both markers as the
  region boundary for `block_hash` computation).

**Renaming, indenting, or merging into surrounding prose is a
contract break.** Per `AGENTS.md` Protocol invariants → "CLAUDE.md
routing markers".

### Block content

The bytes between the marker pair are the **plugin-owned region**
(per I-11). Source of truth: `skills/using-board-superpowers/references/claudemd-routing.md`.
Per I-10, the block injected into downstream `CLAUDE.md` /
`AGENTS.md` is byte-identical to the SoT block.

### `block_hash` field — exact format

```
sha256:<64 lowercase hex characters>
```

Total length: 71 characters. Per §1.5.5 TBD-Notes resolution +
[`03-config-schemas.md`](./03-config-schemas.md) `state.yml`
schema.

The hash is computed over the bytes **between** the marker pair,
**excluding** the markers themselves. Newline normalization rule:
include the trailing `\n` before the closing marker; the
`bootstrap-project.sh` injection writes a deterministic form (one
blank line above and below the block content within the markers)
so the hash is stable across reads.

**Source-of-truth file shape.** The SoT body at
`skills/using-board-superpowers/references/claudemd-routing.md` is
the **injectable region only — the SoT file itself contains no
markers**. Injection wraps the SoT body as:

```
<!-- board-superpowers:routing -->
<blank line>
<SoT body>
<blank line>
<!-- /board-superpowers:routing -->
```

The hash is computed over the exact byte sequence
`<blank line>\n<SoT body>\n<blank line>` — the markers' bytes are
excluded; the wrapping newlines are included. Both the
`bootstrap-project.sh` writer and the F-B4 re-check share this
normalization. Editing the SoT file requires re-running F-B4 on
every downstream repo.

### Tamper detection (F-B4)

F-B4 re-computes the on-disk block's SHA256, finds the matching
`target_file` element in `state.yml:routing_blocks`, and
compares its `block_hash`:

- **Match** → re-inject new SoT content (auto, no prompt).
- **Mismatch** → architect modified the block; surface a 3-way
  prompt (replace / merge / leave alone). Per chezmoi `apply` 3-way
  prompt + Debian `dpkg conffile`.

### Cited rationale

- I-10 (mirror rule), I-11 (plugin-owned vs user-owned).
- §1.5.2 F-B2 (initial injection + initial hash).
- §1.5.4 F-B4 (re-check + 3-way prompt).
- `claudemd-routing.md` (canonical block body).
- `AGENTS.md` Protocol invariants → routing-marker entry.

---

## Project v2 Status enum

The six required Status options on the GitHub Project v2's
`Status` single-select field, in this exact order:

```
Backlog → Ready → In Progress → In Review → Done → Blocked
```

### Validation

`bootstrap-project.sh` step 2 validates the project has all six
options before completing F-B2. Missing options: the script aborts
with a stderr listing of the missing names (architect adds them
via the GitHub UI and re-runs).

Per ADR-0001 substrate-commitment posture: the script does NOT
create options. Project v2 single-select option creation via API
is unreliable with standard tokens — the architect creates them
via UI once.

### Allowed transitions (state machine)

Pinned in `board-protocol/SKILL.md` and 0003 § 3.3.1 (Card aggregate
state machine). 0005 reproduces the table:

| From → To | Who | When |
|-----------|-----|------|
| Backlog → Ready | Manager | Decomposition confirms INVEST compliance |
| Ready → In Progress | Consumer | Atomic claim succeeds |
| Ready → Backlog | Manager | Deprioritized |
| In Progress → In Review | Consumer | PR opened |
| In Progress → Blocked | Consumer | Unrecoverable blocker or scope problem |
| In Progress → Ready | Consumer | Abandoned cleanly (worktree + claim branch removed) |
| Blocked → Ready | Manager | After unblocking or re-scoping |
| In Review → Done | Human / GH auto-close | PR merged |
| In Review → In Progress | Consumer | Review changes require more work |

Anything else is a protocol violation. **`Backlog → anywhere except
Ready` is forbidden** — the Ready gate is non-bypassable (per I-9
spec-completeness gate).

### Status-string canonicalization

`transition-card.sh --to <status>` matches case-insensitively and
trims whitespace. The canonical strings (capitalized, exact
spaces) are what `bootstrap-project.sh` validates and what
GitHub stores.

### Cited rationale

- `board-protocol/SKILL.md` "The board" + state machine.
- 0003 § 3.3.1 Card aggregate state machine invariant.
- §1.5.2 F-B2 step 2 validation.
- ADR-0001 (substrate-commitment posture explains why API doesn't
  create options).
- ADR-0005 (BoardAdapter Status enum is the canonical type).

---

## Standard label set

Created idempotently by `bootstrap-project.sh` step 1.

### Type labels

| Name | Color (hex without `#`) | Description |
|------|-------------------------|-------------|
| `type:feature` | `0e8a16` | A new user-visible capability |
| `type:bug` | `d73a4a` | A defect in existing behavior |
| `type:chore` | `c5def5` | Non-code or infra work (deps, rename, config) |
| `type:refactor` | `fbca04` | Internal restructuring with no behavior change |
| `type:epic` | `5319e7` | A container for several vertical-slice cards |

### Size labels

| Name | Color | Description |
|------|-------|-------------|
| `size:XS` | `cccccc` | Under 50 LOC / 1-2 files |
| `size:S` | `b0bec5` | 50-200 LOC / 2-5 files |
| `size:M` | `607d8b` | 200-400 LOC / 5-10 files |
| `size:L` | `455a64` | 400-500 LOC / up to 10 files (ceiling — split if bigger) |

### Idempotency

`gh label create` returns "already exists" for pre-existing labels
with the same name; `bootstrap-project.sh` distinguishes that from
real failures (token-scope problems) and only aborts on real
failures.

### Cited rationale

- `bootstrap-project.sh` script header + step 1.
- §1.5.2 F-B2 sub-capability 1.
- 0003 § 3.3.1 Card aggregate (LabelSet member entity, CardType /
  Size value objects).

---

## Branch naming — `claim/<N>-<slug>`

Pattern:

```
claim/<card-number>-<short-slug>
```

- `<card-number>` — positive integer (the GitHub Issue number).
- `<short-slug>` — derived from the Card title via
  `bsp_sanitize_slug` (lowercased, `[^a-z0-9-]+` → `-`, collapsed,
  ≤ 40 chars). The 40-char ceiling is dictated by GitHub's branch-
  picker UI truncation.

This branch is three things at once (per `board-protocol/SKILL.md`
"Branch naming"):

- **Atomic lock** — first `git push --force-with-lease=<ref>:` wins.
- **Feature branch** for the PR.
- **Debugging aid** — `git branch -r | grep claim/` shows in-flight
  work.

### Cited rationale

- `board-protocol/SKILL.md` "Branch naming".
- ADR-0002 (atomicity-via-git-push).
- §1.4.1 F-C1.
- 0003 § 3.3.3 ConsumerLogical aggregate (ClaimBranch member
  entity).

---

## Cross-references

- [`01-script-contracts.md`](./01-script-contracts.md) — the scripts
  that write these artifacts (`claim-card.sh`, `create-card.sh`,
  `transition-card.sh`, `bootstrap-project.sh`).
- [`03-config-schemas.md`](./03-config-schemas.md) —
  `state.yml:routing_blocks[]` (list of `{target_file, block_hash,
  injected_at}`) carries the hashes of all tracked routing-block
  files.
- [`06-audit-log-schema.md`](./06-audit-log-schema.md) — every
  artifact mutation emits an AuditEntry.
- [`07-path-conventions.md`](./07-path-conventions.md) — filesystem
  layout for `.board-superpowers/claims/<N>.claim`.
- ADR-0001 (substrate commitment), ADR-0002 (claim via branch
  push), ADR-0003 (worktree info-leak), ADR-0005 (BoardAdapter
  Status enum), ADR-0006 (PR contract gating).
- §1.6 decomposition surface, §1.8 PR contract, I-9 / I-10 / I-11.
- 0003 § 3.3.1 / 3.3.2 / 3.3.3 (Card / PR / ConsumerLogical
  aggregates).
