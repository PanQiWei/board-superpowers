## Part 3 — Cross-references

### 3.1 Features → Skills mapping

Maps each feature ID in Part 1 to the skill / script / hook
artifact that implements it (or composes it). The column
"Implementing surface" names the artifact at the path it
currently lives. Where multiple artifacts collaborate on one
feature, all are listed.

**Producer features (§1.3.1):**

| Feature | Implementing surface |
|---------|---------------------|
| F-01 Atomic kanban query primitive | `skills/briefing-daily/SKILL.md` + `skills/triaging-board/SKILL.md` (compose Kanban Protocol `read_board` action via `operating-kanban`); v1 GitHubProjectAdapter projection per ADR-0005 (rescoped by ADR-0025) |
| F-02 Pending PR queue with ordering | `skills/reviewing-pr-queue/SKILL.md` + `references/review-queue-detail.md` |
| F-03 Blocked sessions inspection | `skills/triaging-board/SKILL.md` (Blocked scan via `read_board` filter); session-id reachback via `~/.claude/projects/.../<sid>.jsonl` |
| F-04 Today's dispatch recommendation | `skills/briefing-daily/SKILL.md` Step 4 (priority list) + § "Today's dispatch recommendation (extended variant)" |
| F-05 Board health snapshot | `skills/briefing-daily/SKILL.md` Steps 1–3 (board summary by Status) |
| F-06 Context briefing on switch-back | `skills/briefing-daily/SKILL.md` § "Re-entry context-switch reload" |
| F-07 End-of-day overnight batch dispatch | (deferred to v1.x per ADR-0011; partial coverage in `briefing-daily` extended dispatch variant) |
| F-08 Interactive intake & design routing | `skills/intaking-requirement/SKILL.md` + `references/intake-decision-tree.md`; routes to `superpowers:brainstorming` / `gstack:/office-hours` / `gstack:/plan-eng-review` via `composing-siblings` |
| F-09 Decomposition into cards | `skills/decomposing-into-milestones/SKILL.md` + `references/card-schema.md` + `references/decomposition-patterns.md`; `scripts/create-card.sh` |
| F-10 Triage with remediation ladder | `skills/triaging-board/SKILL.md` (Blocked dispatch + stale-claim release) |
| F-11 Stale session detection (lazy) | `skills/briefing-daily/SKILL.md` Step 3 (stale-claim heuristic via `read_board`); preflight piggyback per ADR-0007 |
| F-12 Retro routine | (deferred to v1.x per ADR-0011) |
| F-13 Weekly aggregated report | (deferred to v1.x per ADR-0011) |
| F-14 Harness setup & evolution conversation | (no implementing surface yet — planned) |
| F-15 Kanban hygiene & maintenance ops | `skills/triaging-board/SKILL.md` (kanban hygiene partial) |

**Consumer features (§1.4.1):**

| Feature | Implementing surface |
|---------|---------------------|
| F-C0 Self-selection from Ready (manual-pull entry) | `skills/consuming-card/SKILL.md` Stage F1 node A1 (`references/stage-1-claim.md` entry) |
| F-C1 Atomic claim primitive | `scripts/claim-card.sh`; `skills/consuming-card/SKILL.md` Stage F1 node A2 (`references/stage-1-claim.md`) |
| F-C2 Spec / plan / acceptance-criteria fetch | `skills/consuming-card/SKILL.md` Stage F1 node A3 (`references/stage-1-claim.md`) |
| F-C3 Worktree entry + In Progress transition | `skills/consuming-card/SKILL.md` Stage F1 node A2 (`references/stage-1-claim.md`); `scripts/transition-card.sh` |
| F-C4 TDD-driven implementation delegation | `skills/consuming-card/SKILL.md` Stage F2 node B2 + `references/stage-2-implement.md`; delegates to `superpowers:subagent-driven-development` etc. via `composing-siblings` |
| F-C5 TDD-skip mechanism | `skills/consuming-card/SKILL.md` Stage F2 node B3 (TDD-skip refusal); `skills/enforcing-pr-contract/SKILL.md` (PR three-section shape) |
| F-C6 Cross-card touch hard refuse | `skills/consuming-card/SKILL.md` Stage F2 node B4 (Cross-card refusal) — planned hook addition still deferred |
| F-C7 Permission boundary (three-layer) | `hooks/hooks.json` (planned `PreToolUse` registration); `skills/consuming-card/SKILL.md` Stage F2 node B5 (Permission-boundary) |
| F-C8 Surface protocol (suspend on uncertainty) | `skills/consuming-card/SKILL.md` Stage F4 node E2 (Crash / failure path) + node G2 (R-class propose-await) |
| F-C9 Pre-submit verification chain | `skills/consuming-card/SKILL.md` Stage F3 node C1 (`references/stage-3-verify.md`; composes `superpowers:verification-before-completion` + `superpowers:requesting-code-review` + `gstack:/review` via `composing-siblings`) |
| F-C10 Cross-platform adversarial review | `skills/consuming-card/SKILL.md` Stage F3 node C2 (`references/stage-3-verify.md`; composes `gstack:/codex` via `composing-siblings`) |
| F-C11 Conditional QA / security passes | `skills/consuming-card/SKILL.md` Stage F3 nodes C3-C4 (`references/stage-3-verify.md`; composes `gstack:/qa` + `gstack:/cso` conditionally via `composing-siblings`) |
| F-C12 PR submission with mandatory sections | `skills/consuming-card/SKILL.md` Stage F4 node D1 + `references/stage-4-submit.md`; uses `enforcing-pr-contract` templates |
| F-C13 Review-cycle response | `skills/consuming-card/SKILL.md` Stage F4 node D3 (`references/stage-4-submit.md` § "D3 — Review-feedback rework loop") |
| F-C14 Termination + heartbeat | `skills/consuming-card/SKILL.md` Stage F4 nodes E1-E2 (`references/stage-4-submit.md`); session-log mtime via `~/.claude/projects/.../<sid>.jsonl` |

**Bootstrap, Decomposition, Cross-cutting, PR contract:**

| Feature | Implementing surface |
|---------|---------------------|
| 1.5.0 Dependency check (shared primitive) | `scripts/check-deps.sh`; `hooks/session-start.sh` (Layer 1); `skills/using-board-superpowers/SKILL.md` Step 1 (Layer 2); just-in-time calls in the 4 Producer routine SKILLs (`briefing-daily` / `intaking-requirement` / `reviewing-pr-queue` / `triaging-board`) + `skills/consuming-card/SKILL.md` (Layer 3) |
| F-B1 Host bootstrap | `skills/using-board-superpowers/SKILL.md` (manifest write + intro routing); `skills/using-board-superpowers/references/intro.md` (intro narrative — planned) |
| F-B2 Per-repo bootstrap | `scripts/bootstrap-project.sh`; `skills/using-board-superpowers/SKILL.md` Step 3 + `references/agentsmd-routing.md` (routing source-of-truth) + `references/first-time-user-guide.md` (post-bootstrap pointer) |
| F-B3 Host version transition | `skills/using-board-superpowers/SKILL.md` (manifest version compare + changelog routing); `skills/using-board-superpowers/references/changelog/v<X>.md` (per-version highlights file — planned) |
| F-B4 Per-repo version transition | `skills/using-board-superpowers/SKILL.md` (state.yml compare + new-features list + routing-block hash + 3-way prompt); `${CLAUDE_PLUGIN_ROOT}/scripts/migrations/state-v<N>-to-v<N+1>.sh` (per-version state migrations — planned) |
| 1.6.1 INVEST criteria | `skills/decomposing-into-milestones/SKILL.md` ("The INVEST gate") |
| 1.6.2 Vertical slicing rule | `skills/decomposing-into-milestones/SKILL.md` ("Vertical slicing") + `references/decomposition-patterns.md` |
| 1.6.3 Card body schema | `skills/decomposing-into-milestones/references/card-schema.md`; `skills/board-protocol/SKILL.md` |
| 1.6.4 Size labels | `skills/decomposing-into-milestones/SKILL.md` ("Size calibration"); `scripts/bootstrap-project.sh` (creates `size:*` labels) |
| 1.7 Cross-cutting invariants I-1..I-13 | Distributed across skills + scripts; `docs/architecture/AGENTS.md` change-impact matrix; `docs/architecture/adr/*.md`; for I-11..I-13 also `${CLAUDE_PLUGIN_ROOT}/scripts/migrations/` (planned) |
| 1.8.1 `## Automated Verification` | `skills/enforcing-pr-contract/references/section-templates.md` |
| 1.8.2 `## Human Verification TODO` | `skills/enforcing-pr-contract/references/section-templates.md` |
| 1.8.3 `## Retro Notes` | `skills/enforcing-pr-contract/references/section-templates.md`; aggregated by F-12 |

### 3.2 Features → ADRs mapping

Each feature cites the ADRs that constrain it. Most features
cite ADR-0006 (autonomy boundary) and ADR-0007 (plugin-form
constraints) because those are the project-wide governance
ADRs; specific features cite the others when the action they
take is what the ADR is about.

| Feature | Constraining ADR(s) |
|---------|---------------------|
| F-01 | ADR-0001, ADR-0025 (Kanban Protocol `read_board`); ADR-0005 (v1 GitHubProjectAdapter projection's read shape) |
| F-02 | ADR-0025 (Kanban Protocol — the protocol fixes Card / PR Link semantics); ADR-0005 (v1 GitHub projection's PR-data shape) |
| F-03 | ADR-0007 (C-PLUGIN-1 workaround (b) — session-id reachback) |
| F-04 | ADR-0006 (matrix row 13 precondition); ADR-0007 (C-PLUGIN-3 — concurrency awareness) |
| F-05 | ADR-0007 (C-PLUGIN-2 — health snapshot via preflight piggyback, not daemon) |
| F-06 | ADR-0007 (C-PLUGIN-1 workaround (b)) |
| F-07 | ADR-0006 (row 13); ADR-0007 (C-PLUGIN-3) |
| F-08 | ADR-0004 (composition over reimpl — design routing) |
| F-09 | ADR-0006 (rows 1, 3); ADR-0001 (Project v2 as v1 board) |
| F-10 | ADR-0006 (rows 2, 3, 5, 7, 8) |
| F-11 | ADR-0007 (C-PLUGIN-2 — lazy detection via preflight piggyback) |
| F-12 | ADR-0006 (rows 4, 14); ADR-0007 (cadence trigger via preflight piggyback) |
| F-13 | ADR-0006 (row 14); ADR-0007 |
| F-14 | ADR-0006 (rows 4, 10 — modifies SoT); ADR-0004 (composes `gstack:/plan-eng-review`) |
| F-15 | ADR-0006 (rows 8, 11) |
| F-C0 | (no specific ADR — bootstrap-of-Consumer step) |
| F-C1 | ADR-0002 (claim via push); ADR-0003 (worktree per Consumer) |
| F-C2 | ADR-0001 (card body comes from the board substrate); ADR-0025 (Kanban Protocol `read_card`); ADR-0006 (row 5 precondition — Producer's Ready gate guarantees spec exists) |
| F-C3 | ADR-0003 (worktree per Consumer); ADR-0025 (Kanban Protocol `transition_card` action); ADR-0005 (v1 GitHub projection's status-transition shape) |
| F-C4 | ADR-0004 (composition over reimpl); MULTI_AGENT_DEVELOPMENT.md (`max_depth=1`) |
| F-C5 | (no specific ADR — TDD-skip is the default+override pattern) |
| F-C6 | ADR-0006 (row 4 / row 8 analog — cross-card structural change) |
| F-C7 | ADR-0006 (hard floor as N-class plugin-layer enforcement; future security ADR for promotion) |
| F-C8 | ADR-0007 (C-PLUGIN-1 workaround (a) — board-mediated surface) |
| F-C9 | ADR-0004 (composition over reimpl — chains three external skills) |
| F-C10 | ADR-0004 (composition over reimpl + cross-platform application) |
| F-C11 | ADR-0004 (composition over reimpl — gstack delegation) |
| F-C12 | ADR-0004 (composition for base PR body); ADR-0006 (row 12 — Consumer cannot self-merge) |
| F-C13 | ADR-0006 (row 4 — when scope expansion implied); ADR-0007 (Mode-2 wake-up via preflight) |
| F-C14 | ADR-0003 (worktree preserved on failure path); ADR-0006 (row 6 — Blocked transition); ADR-0007 (mtime-based heartbeat) |
| 1.5.0 | ADR-0007 (plugin-form derived); P5 |
| F-B1 | ADR-0007 (plugin-form derived — manifest at `~/.board-superpowers/`, no daemon); P5 |
| F-B2 | ADR-0001 (Project v2 substrate); ADR-0006 §5 (BYO RDBMS audit log); P5 + dual-platform per `PLUGIN_DEVELOPMENT.md` |
| F-B3 | ADR-0007 (changelog delivery via in-band preflight, not push notification); P5 |
| F-B4 | ADR-0006 (row 4 — routing-block re-injection modifies SoT; auto-update path is A only when block_hash matches); ADR-0007 (lazy-on-read migration via preflight piggyback) |
| 1.6.1 | (no specific ADR — INVEST is canonical, applied as gate) |
| 1.6.2 | (no specific ADR — vertical slicing is canonical) |
| 1.6.3 | ADR-0001 (card lives on the v1 GitHub Project v2 substrate); ADR-0025 (Kanban Protocol Card ontology); ADR-0005 (v1 GitHub projection's card-body shape) |
| 1.6.4 | (no specific ADR — size labels per P7 — taste captured per project, schema fixed) |
| 1.7 I-1..I-13 | I-2 → ADR-0006 row 12; I-4 → ADR-0006 (whole matrix); I-5 → ADR-0007; I-6 → ADR-0006 row 9; I-7 → ADR-0003; I-8 → ADR-0006 §5; I-9 → ADR-0006 row 5 + ADR-0001; I-10 → ADR-0007; I-11 → ADR-0006 row 4 (plugin-vs-user split governance); I-12 → ADR-0007 (lazy-on-read migration); I-13 → ADR-0002 (claim marker force-commit-to-claim-branch contract) |
| 1.8.1 | ADR-0004 (verification chain composes) |
| 1.8.2 | (no specific ADR — operationalizes P6) |
| 1.8.3 | ADR-0006 (row 14 — feeds F-12) |

### 3.3 Implementation status summary

Honest assessment of what's implemented today vs. what's spec-
only. Per the document's "Status" section at the top, the spec
leads and code follows; this table records the lead-vs-follow
delta as of this writing.

**Status legend:**
- **Implemented** — code exists and matches the spec.
- **Partial** — code exists but the spec extends beyond it.
- **Stub** — skill / script file exists but is shape-only;
  spec describes the full intended behavior.
- **Planned** — no code exists; the spec is the contract for
  future work.

| Feature | Status | Note |
|---------|--------|------|
| 1.5.0 Dependency check | Implemented | `scripts/check-deps.sh` covers the spec; three-layer delivery wired |
| F-B1 Host bootstrap | Planned | `~/.board-superpowers/manifest.yml` write + intro routing not yet implemented; current bootstrap is repo-only with no host-layer state |
| F-B2 Per-repo bootstrap | Partial | `bootstrap-project.sh` covers sub-capabilities 1–4; **sub-capability 5 (BYO RDBMS audit-log credential setup) not yet implemented**; **`state.yml` write not yet implemented**; **`AGENTS.md` injection not yet wired** (single-file injection only at v1); **`block_hash` SHA256 recording not yet implemented** |
| F-B3 Host version transition | Planned | Manifest version compare + changelog file routing not yet implemented; no `references/changelog/v<X>.md` files exist yet |
| F-B4 Per-repo version transition | Planned | `state.yml` version compare + new-features default-enable + routing-block hash 3-way prompt + lazy-on-read migration runner all not yet implemented |
| 1.6.1 INVEST criteria | Implemented | `decomposing-into-milestones/SKILL.md` enforces |
| 1.6.2 Vertical slicing | Implemented | `decomposing-into-milestones/SKILL.md` + `decomposition-patterns.md` |
| 1.6.3 Card body schema | Implemented | `card-schema.md` is canonical |
| 1.6.4 Size labels | Implemented | `bootstrap-project.sh` creates `size:*` labels; `decomposing-into-milestones/SKILL.md` enforces |
| F-01 | Implemented | `gh` CLI calls inside skills |
| F-02 | Partial | `review-queue.md` reference exists; ordering algorithm is shape-only |
| F-03 | Stub | Distinction between `running` vs `blocked-on-architect` not yet implemented; daily-routine.md only does stale-claim heuristic |
| F-04 | Partial | `daily-routine.md` Steps 4–5 implement the basics; preflight piggyback awareness only partial |
| F-05 | Stub | Health-grade computation (red/yellow/green) not yet implemented |
| F-06 | Planned | No reference file yet; spec describes the intended capability |
| F-07 | Planned | Overnight batch dispatch not yet implemented |
| F-08 | Implemented | `intake-routine.md` covers; routes to design skills correctly |
| F-09 | Implemented | `decomposing-into-milestones` skill is the most complete in the plugin |
| F-10 | Partial | Triage routine in `triaging-board/SKILL.md` covers basics; ladder formalization (per-row autonomy mapping) is shape-only |
| F-11 | Partial | `daily-routine.md` Step 2 implements the basic stale-detection heuristic; preflight piggyback formalization spec-only |
| F-12 | Partial | `retro-routine.md` reference exists; cadence-driven trigger via preflight piggyback not yet wired |
| F-13 | Planned | Weekly report not yet implemented |
| F-14 | Planned | Harness setup conversation not yet implemented |
| F-15 | Stub | Kanban hygiene basics inside triage routine; full implementation spec-only |
| F-C0 | Implemented | `consuming-card/SKILL.md` Stage F1 node A1 (`references/stage-1-claim.md`) |
| F-C1 | Implemented | `claim-card.sh`; `consuming-card/SKILL.md` Stage F1 node A2 |
| F-C2 | Partial | `consuming-card/SKILL.md` Stage F1 nodes A2-A3 (`references/stage-1-claim.md`); thin-pointer convention via third-party storage adapter is planned |
| F-C3 | Implemented | `consuming-card/SKILL.md` Stage F1 node A2; `transition-card.sh` |
| F-C4 | Implemented | `consuming-card/SKILL.md` Stage F2 node B2 + `references/stage-2-implement.md` |
| F-C5 | Partial | `consuming-card/SKILL.md` Stage F2 node B3 (TDD-skip refusal); default-by-`type:*` enforcement not yet wired |
| F-C6 | Stub | `consuming-card/SKILL.md` Stage F2 node B4 (Cross-card refusal) — hook addition still spec-only |
| F-C7 | Stub | `consuming-card/SKILL.md` Stage F2 node B5 (Permission-boundary); `hooks/hooks.json` `PreToolUse` registration planned |
| F-C8 | Partial | `consuming-card/SKILL.md` Stage F4 node E2 (Crash / failure path) + node G2 (R-class propose-await); Mode-2 `SendMessage` integration spec-only |
| F-C9 | Implemented | `consuming-card/SKILL.md` Stage F3 node C1 (`references/stage-3-verify.md`) chains the three skills |
| F-C10 | Partial | `consuming-card/SKILL.md` Stage F3 node C2 (`references/stage-3-verify.md`); explicit attribution-line enforcement in PR body spec-only |
| F-C11 | Implemented | `consuming-card/SKILL.md` Stage F3 nodes C3-C4 (conditional `gstack:/qa` + `gstack:/cso` via `composing-siblings`) |
| F-C12 | Implemented | `consuming-card/SKILL.md` Stage F4 nodes D1-D2 + `references/stage-4-submit.md` |
| F-C13 | Partial | `consuming-card/SKILL.md` Stage F4 node D3 (`references/stage-4-submit.md` § "D3 — Review-feedback rework loop"); Mode-2 wake-up integration spec-only |
| F-C14 | Partial | `consuming-card/SKILL.md` Stage F4 nodes E1-E2 covered; crash-detection mtime heuristic in Producer spec-only |
| 1.7 I-1 | Implemented | One-card-per-session enforced by `consuming-card/SKILL.md` |
| 1.7 I-2 | Implemented | No code path lets Consumer merge or Producer commit |
| 1.7 I-3 | Implemented (negatively) | Plugin does not model role / team — multi-architect symmetry holds by absence of single-architect filtering |
| 1.7 I-4 | Partial | Pattern present in TDD-skip and triage; full operational discipline (audit-log entry per override, plugin-layer enforcement) spec-only |
| 1.7 I-5 | Implemented | All current features close under C-PLUGIN-1/-2/-3 |
| 1.7 I-6 | Implemented | `wip_limit` in `config.yml`; `daily-routine.md` reads it |
| 1.7 I-7 | Implemented | `claim-card.sh` enforces |
| 1.7 I-8 | Planned | Audit-log uniformity is contract; persistence target (BYO RDBMS) per ADR-0006 not yet implemented |
| 1.7 I-9 | Partial | Card schema supports thin-pointer convention; in-repo `docs/` resolution implemented; third-party storage adapter planned |
| 1.7 I-10 | Implemented | Routing block exists in both `references/agentsmd-routing.md` source-of-truth and the appendix block at the bottom of `AGENTS.md` |
| 1.7 I-11 | Planned | Plugin-owned vs user-owned region split is contract; `block_hash` enforcement (F-B2 + F-B4) not yet implemented |
| 1.7 I-12 | Planned | `schema_version` field convention defined; migration runner at `${CLAUDE_PLUGIN_ROOT}/scripts/migrations/` not yet implemented; lazy-on-read invariant is spec |
| 1.7 I-13 | Partial | `claims/` gitignore entry implemented; `state.yml` does not exist yet (planned with F-B2); `config.yml` tracked correctly today |
| 1.8.1 | Partial | `enforcing-pr-contract/references/section-templates.md` defines the section; Review Queue routine's contract-violation flagging is partial |
| 1.8.2 | Partial | `enforcing-pr-contract/references/section-templates.md` defines the section; "OPTIONAL — not every PR" rule is in spec, not yet enforced by Review Queue |
| 1.8.3 | Implemented | `enforcing-pr-contract/references/section-templates.md` defines the section; F-12 aggregation of these notes is partial (see F-12) |

**Pre-release reality check (per `CLAUDE.md`)**: most features
are at "Stub" or "Partial" because the project is pre-release
and the spec leads. The "Implemented" column lists features
that have stable shape today and would only change shape under
a deliberate spec revision. Features marked "Planned" need a
card created on board-superpowers' own self-hosted board (see
the self-hosting section in `CLAUDE.md`) before implementation
work begins.

---

